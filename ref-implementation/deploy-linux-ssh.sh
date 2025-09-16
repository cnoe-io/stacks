#!/usr/bin/env bash
# Linux deployment script with SSH NodePort support and direct key mounting
# Works on native Linux environments without WSL2 workarounds

set -e

# Fix Docker socket issues on NixOS/Linux with WSL variables
if [[ -n "${DOCKER_HOST:-}" ]] && [[ "${DOCKER_HOST}" == *"wsl"* ]]; then
    echo "Detected WSL Docker host environment variable"
    if [[ -S /var/run/docker.sock ]]; then
        echo "Native Docker socket found at /var/run/docker.sock, unsetting DOCKER_HOST"
        unset DOCKER_HOST
        export DOCKER_HOST=""
    fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="$(dirname "${SCRIPT_DIR}")"
CLUSTER_NAME="local"
KEYS_DIR="${SCRIPT_DIR}/keys"

# Source environment variables from wi.env if it exists
if [ -f "${STACKS_DIR}/.env-files/wi.env" ]; then
    echo -e "${GREEN}Loading environment from ${STACKS_DIR}/.env-files/wi.env${NC}"
    source "${STACKS_DIR}/.env-files/wi.env"
fi

# Show help if requested
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo -e "${BLUE}Usage: $0 [additional idpbuilder arguments]${NC}"
    echo ""
    echo "This script creates a Kind cluster on Linux with:"
    echo "  - Azure Workload Identity support"
    echo "  - SSH NodePort access for development containers"
    echo "  - Direct service account key mounting"
    echo ""
    echo "SSH Ports allocated:"
    echo "  30022 - backstage-dev"
    echo "  30023 - backstage-staging"
    echo "  30024 - nextjs-dev"
    echo "  30025 - nextjs-staging"
    echo "  30026-30027 - reserved for future use"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Basic cluster creation"
    echo "  $0 --package ../dist/my-app          # Deploy with a specific package"
    echo "  $0 --use-catalog                     # Use the catalog"
    echo ""
    exit 0
fi

# Capture additional arguments to pass to idpbuilder
IDPBUILDER_ARGS="$@"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   Linux Kind Cluster with SSH Support${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -n "$IDPBUILDER_ARGS" ]; then
    echo -e "${YELLOW}Additional arguments: $IDPBUILDER_ARGS${NC}"
else
    echo -e "${YELLOW}Note: No packages specified. Add --package flags to deploy applications.${NC}"
    echo -e "${YELLOW}Example: $0 --package ../dist/${NC}"
fi
echo ""

# Step 1: Delete existing cluster if it exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}⚠️  Deleting existing cluster...${NC}"
    idpbuilder delete || kind delete cluster --name ${CLUSTER_NAME} || true
fi

# Step 2: Generate or check service account keys
mkdir -p "${KEYS_DIR}"

if [ ! -f "${KEYS_DIR}/sa.key" ] || [ ! -f "${KEYS_DIR}/sa.pub" ]; then
    echo -e "${GREEN}Generating new service account keys...${NC}"
    openssl genrsa -out "${KEYS_DIR}/sa.key" 2048
    openssl rsa -in "${KEYS_DIR}/sa.key" -pubout -out "${KEYS_DIR}/sa.pub"
    echo -e "${GREEN}✓ Keys generated in ${KEYS_DIR}${NC}"
else
    echo -e "${GREEN}✓ Using existing keys from ${KEYS_DIR}${NC}"
fi

# Step 3: Create the Kind configuration with direct mounts
CONFIG_FILE="${SCRIPT_DIR}/kind-config-linux-ssh.yaml"
echo -e "${GREEN}Creating Kind configuration with direct key mounting...${NC}"

cat > "${CONFIG_FILE}" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."gitea.cnoe.localtest.me:8443"]
    endpoint = ["https://gitea.cnoe.localtest.me"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."gitea.cnoe.localtest.me".tls]
    insecure_skip_verify = true
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: 6443
nodes:
- role: control-plane
  image: "kindest/node:v1.31.4"
  labels:
    ingress-ready: "true"
  extraPortMappings:
  # Standard IDPBuilder ports
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
  - containerPort: 32222
    hostPort: 32222
    protocol: TCP
  
  # DevSpace SSH ports for development containers
  # Backstage SSH ports
  - containerPort: 30022
    hostPort: 30022
    protocol: TCP
    listenAddress: "0.0.0.0"
  - containerPort: 30023
    hostPort: 30023
    protocol: TCP
    listenAddress: "0.0.0.0"
  
  # NextJS SSH ports
  - containerPort: 30024
    hostPort: 30024
    protocol: TCP
    listenAddress: "0.0.0.0"
  - containerPort: 30025
    hostPort: 30025
    protocol: TCP
    listenAddress: "0.0.0.0"
  
  # Additional service SSH ports
  - containerPort: 30026
    hostPort: 30026
    protocol: TCP
    listenAddress: "0.0.0.0"
  - containerPort: 30027
    hostPort: 30027
    protocol: TCP
    listenAddress: "0.0.0.0"
  
  # Direct mount of keys - works on Linux
  extraMounts:
    - hostPath: ${KEYS_DIR}
      containerPath: /etc/kubernetes/pki/custom-keys
      readOnly: true
      
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      certSANs:
      - "localhost"
      - "127.0.0.1"
      - "nixos-hetzner"
      - "178.156.202.233"  # Hetzner public IP
      - "kubernetes"
      - "kubernetes.default"
      - "kubernetes.default.svc"
      - "kubernetes.default.svc.cluster.local"
      extraArgs:
        service-account-issuer: "${SERVICE_ACCOUNT_ISSUER:-https://oidcissuer65846b7df97b.z13.web.core.windows.net/}"
        service-account-key-file: /etc/kubernetes/pki/custom-keys/sa.pub
        service-account-signing-key-file: /etc/kubernetes/pki/custom-keys/sa.key
    controllerManager:
      extraArgs:
        service-account-private-key-file: /etc/kubernetes/pki/custom-keys/sa.key
EOF

# Step 4: Create cluster with direct key mounting
echo -e "${GREEN}Creating Kind cluster with SSH NodePort support and mounted keys...${NC}"
echo -e "${BLUE}Using config: ${CONFIG_FILE}${NC}"

# Clear any Docker environment variables from WSL
unset DOCKER_HOST
unset DOCKER_TLS_VERIFY
unset DOCKER_CERT_PATH

# Explicitly pass the cluster name to idpbuilder
idpbuilder create --name "${CLUSTER_NAME}" --kind-config "${CONFIG_FILE}" --dev-password $IDPBUILDER_ARGS

# Step 5: Wait for cluster to be ready
echo -e "${GREEN}Waiting for cluster to be ready...${NC}"
for i in {1..30}; do
    if kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}✓ Cluster nodes are ready${NC}"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

# Step 6: Get kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
mkdir -p ~/.kube

# Try to get kubeconfig, handle if cluster name doesn't match
if ! kind get kubeconfig --name ${CLUSTER_NAME} > ~/.kube/config 2>/dev/null; then
    echo -e "${YELLOW}Warning: Could not get kubeconfig for cluster '${CLUSTER_NAME}'${NC}"
    echo -e "${YELLOW}Attempting to find the correct cluster name...${NC}"
    
    # List all kind clusters and try the first one
    ACTUAL_CLUSTER=$(kind get clusters 2>/dev/null | head -1)
    if [ -n "$ACTUAL_CLUSTER" ]; then
        echo -e "${GREEN}Found cluster: ${ACTUAL_CLUSTER}${NC}"
        kind get kubeconfig --name ${ACTUAL_CLUSTER} > ~/.kube/config
        echo -e "${YELLOW}Note: Cluster was created as '${ACTUAL_CLUSTER}' instead of '${CLUSTER_NAME}'${NC}"
    else
        echo -e "${RED}❌ No Kind clusters found${NC}"
        exit 1
    fi
fi

# Step 7: Verify keys are mounted correctly
echo -e "${GREEN}Verifying service account keys...${NC}"
# Use the actual cluster name if it differs
CONTAINER_NAME="${ACTUAL_CLUSTER:-$CLUSTER_NAME}-control-plane"
if docker exec ${CONTAINER_NAME} ls /etc/kubernetes/pki/custom-keys/sa.key &>/dev/null; then
    echo -e "${GREEN}✓ Keys are properly mounted${NC}"
else
    echo -e "${YELLOW}⚠️  Keys not found, falling back to copy method${NC}"
    # Fallback: Copy keys if mounting failed
    docker exec ${CONTAINER_NAME} mkdir -p /etc/kubernetes/pki/custom-keys 2>/dev/null || true
    cat ${KEYS_DIR}/sa.key | docker exec -i ${CONTAINER_NAME} tee /etc/kubernetes/pki/custom-keys/sa.key > /dev/null
    cat ${KEYS_DIR}/sa.pub | docker exec -i ${CONTAINER_NAME} tee /etc/kubernetes/pki/custom-keys/sa.pub > /dev/null
fi

# Step 8: Wait for all system pods to be ready
echo -e "${GREEN}Waiting for system pods...${NC}"
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s

# Step 9: Deploy SSH services (if CDK8s manifests exist)
CDK8S_DIST="/home/vpittamp/stacks/cdk8s/dist"
if [ -d "${CDK8S_DIST}" ]; then
    echo -e "${GREEN}Checking for SSH service manifests...${NC}"
    
    # Find and apply all SSH service manifests
    for manifest in ${CDK8S_DIST}/*/manifests/Service.*-ssh.k8s.yaml; do
        if [ -f "$manifest" ]; then
            # Extract namespace from the manifest
            NAMESPACE=$(grep "namespace:" "$manifest" | head -1 | awk '{print $2}')
            if [ -n "$NAMESPACE" ]; then
                # Ensure namespace exists
                kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
                echo -e "${GREEN}Applying $(basename $manifest) to namespace ${NAMESPACE}...${NC}"
                kubectl apply -f "$manifest"
            fi
        fi
    done
else
    echo -e "${YELLOW}CDK8s dist directory not found, skipping SSH services${NC}"
fi

# Step 10: Sync JWKS to Azure (CRITICAL for External Secrets)
if [ -f "${SCRIPT_DIR}/sync-jwks-to-azure.sh" ]; then
    echo -e "${GREEN}Checking Azure authentication for JWKS sync...${NC}"
    
    # Pre-check Azure auth to fail fast
    if ! az account show &>/dev/null; then
        echo -e "${RED}❌ Azure authentication required for JWKS sync${NC}"
        echo -e "${YELLOW}The External Secrets Operator requires JWKS to be synced to Azure.${NC}"
        echo -e "${YELLOW}Please run: az login${NC}"
        echo -e "${YELLOW}Then re-run this deployment script${NC}"
        echo ""
        echo -e "${YELLOW}Note: The cluster has been created but External Secrets will not work.${NC}"
        echo -e "${YELLOW}After logging in to Azure, you can run:${NC}"
        echo -e "${YELLOW}  ${SCRIPT_DIR}/sync-jwks-to-azure.sh${NC}"
        exit 1
    fi
    
    # Check token expiry
    TOKEN_EXPIRY=$(az account get-access-token --query "expiresOn" -o tsv 2>/dev/null || echo "")
    if [ -n "$TOKEN_EXPIRY" ]; then
        CURRENT_TIME=$(date +%s)
        EXPIRY_TIME=$(date -d "$TOKEN_EXPIRY" +%s 2>/dev/null || echo 0)
        TIME_DIFF=$((EXPIRY_TIME - CURRENT_TIME))
        
        if [ $TIME_DIFF -lt 60 ]; then
            echo -e "${RED}❌ Azure token expired or about to expire${NC}"
            echo -e "${YELLOW}Token expires at: $TOKEN_EXPIRY${NC}"
            echo -e "${YELLOW}Please run: az login${NC}"
            echo -e "${YELLOW}Then re-run this deployment script${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}Syncing JWKS to Azure (required for External Secrets)...${NC}"
    
    # Wait for API server to be fully ready
    echo "  Ensuring API server is ready..."
    for i in {1..30}; do
        if kubectl get --raw /openid/v1/jwks &>/dev/null; then
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    
    # Run the sync
    ${SCRIPT_DIR}/sync-jwks-to-azure.sh
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ JWKS successfully synced to Azure${NC}"
        
        # Wait a moment for Azure to process the update
        echo "  Waiting for Azure to process JWKS update..."
        sleep 5
        
        # If External Secrets is already deployed, restart it to pick up the new JWKS
        if kubectl get deployment -n external-secrets external-secrets &>/dev/null 2>&1; then
            echo -e "${GREEN}Restarting External Secrets to use new JWKS...${NC}"
            kubectl rollout restart deployment -n external-secrets external-secrets external-secrets-cert-controller external-secrets-webhook
            kubectl rollout status deployment -n external-secrets external-secrets --timeout=60s
        fi
    else
        echo -e "${RED}⚠️  JWKS sync failed - External Secrets will not work properly${NC}"
        echo -e "${YELLOW}You can manually run: ${SCRIPT_DIR}/sync-jwks-to-azure.sh${NC}"
    fi
else
    echo -e "${RED}⚠️  Azure JWKS sync script not found - External Secrets will fail${NC}"
    echo -e "${YELLOW}Expected at: ${SCRIPT_DIR}/sync-jwks-to-azure.sh${NC}"
fi

# Step 11: Verify External Secrets health
echo -e "${GREEN}Verifying External Secrets configuration...${NC}"
MAX_WAIT=60
for i in $(seq 1 $MAX_WAIT); do
    STATUS=$(kubectl get clustersecretstore azure-keyvault-store -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "NotFound")
    if [ "$STATUS" == "Valid" ]; then
        echo -e "${GREEN}✓ Azure Key Vault integration is working${NC}"
        break
    elif [ "$STATUS" == "NotFound" ]; then
        echo "  Waiting for ClusterSecretStore to be created... ($i/$MAX_WAIT)"
    else
        echo "  Azure Key Vault status: $STATUS ($i/$MAX_WAIT)"
    fi
    sleep 2
done

if [ "$STATUS" != "Valid" ]; then
    echo -e "${YELLOW}⚠️  Azure Key Vault integration not ready after ${MAX_WAIT} seconds${NC}"
    echo -e "${YELLOW}Current status: $STATUS${NC}"
    echo -e "${YELLOW}You may need to:${NC}"
    echo -e "${YELLOW}  1. Check Azure credentials and configuration${NC}"
    echo -e "${YELLOW}  2. Verify JWKS sync: curl https://oidcissuer65846b7df97b.z13.web.core.windows.net/openid/v1/jwks${NC}"
    echo -e "${YELLOW}  3. Check logs: kubectl logs -n external-secrets deploy/external-secrets${NC}"
fi

# Step 12: Setup VClusters with proper kubeconfig generation
echo -e "${GREEN}Checking for VClusters...${NC}"

# Wait for vclusters to be deployed by ArgoCD
VCLUSTERS_FOUND=false
for i in {1..60}; do
    if kubectl get pod vcluster-dev-helm-0 -n dev-vcluster &>/dev/null 2>&1 || \
       kubectl get pod vcluster-staging-helm-0 -n staging-vcluster &>/dev/null 2>&1; then
        VCLUSTERS_FOUND=true
        echo -e "${GREEN}  VCluster pods found${NC}"
        break
    fi
    [ $i -eq 1 ] && echo -n "  Waiting for VClusters"
    echo -n "."
    sleep 5
done
echo ""

if [ "$VCLUSTERS_FOUND" = true ]; then
    # Run the dedicated VCluster setup script
    if [ -f "${SCRIPT_DIR}/setup-vcluster-kubeconfigs.sh" ]; then
        echo -e "${GREEN}Running VCluster kubeconfig setup...${NC}"
        ${SCRIPT_DIR}/setup-vcluster-kubeconfigs.sh
    else
        echo -e "${YELLOW}VCluster setup script not found, attempting basic setup...${NC}"
        
        # Fallback: Basic vcluster setup
        if command -v vcluster &>/dev/null; then
            VCLUSTER_CONFIGS=(
                "vcluster-dev-helm:dev-vcluster:dev"
                "vcluster-staging-helm:staging-vcluster:staging"
            )
            
            for vcluster_config in "${VCLUSTER_CONFIGS[@]}"; do
                IFS=':' read -r NAME NAMESPACE ENV <<< "${vcluster_config}"
                
                if kubectl get pod "${NAME}-0" -n "${NAMESPACE}" &>/dev/null 2>&1; then
                    echo -e "${GREEN}  Connecting to ${ENV} vcluster...${NC}"
                    
                    # Generate kubeconfig
                    VCLUSTER_KUBECONFIG="/tmp/vcluster-${ENV}.yaml"
                    if vcluster connect "${NAME}" -n "${NAMESPACE}" \
                        --server "https://${ENV}-vcluster.cnoe.localtest.me:8443" \
                        --insecure --update-current=false --print > "${VCLUSTER_KUBECONFIG}" 2>/dev/null; then
                        
                        # Merge with main kubeconfig
                        KUBECONFIG="${HOME}/.kube/config:${VCLUSTER_KUBECONFIG}" \
                            kubectl config view --flatten > /tmp/merged-config.yaml
                        mv /tmp/merged-config.yaml ${HOME}/.kube/config
                        
                        # Rename context for clarity (handle both old and new cluster names)
                        kubectl config rename-context \
                            "vcluster_${NAME}_${NAMESPACE}_kind-local" \
                            "${ENV}" 2>/dev/null || \
                        kubectl config rename-context \
                            "vcluster_${NAME}_${NAMESPACE}_kind-localdev" \
                            "${ENV}" 2>/dev/null || true
                        
                        echo -e "${GREEN}  ✓ Added ${ENV}-vcluster context${NC}"
                    fi
                fi
            done
        else
            echo -e "${YELLOW}vcluster CLI not found. Install it to manage VClusters.${NC}"
            echo "  curl -L -o vcluster https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64"
            echo "  chmod +x vcluster && sudo mv vcluster /usr/local/bin/"
        fi
    fi
else
    echo -e "${YELLOW}No VClusters found. They may be deployed later by ArgoCD.${NC}"
    echo "Run '${SCRIPT_DIR}/setup-vcluster-kubeconfigs.sh' after VClusters are ready."
fi

# Step 13: Setup browser certificates (lightweight, no rebuild needed)
if [ -f "${SCRIPT_DIR}/../scripts/setup-browser-certs.sh" ]; then
    echo -e "${GREEN}Setting up browser certificates...${NC}"
    "${SCRIPT_DIR}/../scripts/setup-browser-certs.sh" 2>&1 | grep -E "(✓|Warning:|Error:)" || true
fi

# Step 14: Show summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Cluster created successfully with SSH support!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Service Account Keys:${NC}"
echo "  Location: ${KEYS_DIR}"
echo "  Mounted at: /etc/kubernetes/pki/custom-keys/"
echo ""
echo -e "${BLUE}SSH NodePort Mappings:${NC}"
echo "  Port 30022 → backstage-dev"
echo "  Port 30023 → backstage-staging"
echo "  Port 30024 → nextjs-dev"
echo "  Port 30025 → nextjs-staging"
echo "  Port 30026-30027 → reserved"
echo ""
echo -e "${BLUE}Cluster Endpoints:${NC}"
echo "  ArgoCD:    https://argocd.cnoe.localtest.me:8443"
echo "  Gitea:     https://gitea.cnoe.localtest.me:8443"
echo "  Backstage: https://backstage.cnoe.localtest.me:8443"
echo "  Headlamp:  https://headlamp.cnoe.localtest.me:8443"
echo "  Kargo:     https://kargo.cnoe.localtest.me:8443"
echo ""
echo -e "${BLUE}Kubernetes Contexts:${NC}"
kubectl config get-contexts | grep -E "(CURRENT|kind-local|kind-localdev|dev|staging)" | grep -v "vcluster_"
echo ""
echo -e "${BLUE}SSH Access (after starting DevSpace):${NC}"
echo "  ssh -p 30022 devspace@localhost    # backstage-dev"
echo "  ssh -p 30024 devspace@localhost    # nextjs-dev"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Check ArgoCD for application status:"
echo "   kubectl get applications -n argocd"
echo ""
echo "2. Start DevSpace for your app:"
echo "   cd /home/vpittamp/backstage-cnoe && devspace dev --skip-build"
echo ""
echo "3. Connect via SSH directly (no port-forward needed!):"
echo "   ssh -p 30022 devspace@localhost"
echo ""