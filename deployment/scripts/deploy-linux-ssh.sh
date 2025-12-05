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
DEPLOYMENT_DIR="$(dirname "${SCRIPT_DIR}")"
STACKS_DIR="$(dirname "${DEPLOYMENT_DIR}")"
KEYS_DIR="${STACKS_DIR}/ref-implementation/azure-workload-identity/keys"

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
cleanup_kind_artifacts() {
    local containers networks
    containers=$(docker ps -aq --filter "label=io.x-k8s.kind.cluster")
    if [ -n "$containers" ]; then
        echo -e "${YELLOW}⚠️  Removing lingering kind containers...${NC}"
        docker rm -f $containers >/dev/null 2>&1 || true
    fi

    if ! kind get clusters >/dev/null 2>&1; then
        networks=$(docker network ls --filter name=^kind$ --format '{{.ID}}')
        if [ -n "$networks" ]; then
            docker network rm kind >/dev/null 2>&1 || true
        fi
    fi
}

ensure_kind_ports_free() {
    local ports=(8443 32222 30022 30023 30024 30025 30026 30027)
    if ! command -v ss >/dev/null 2>&1; then
        return
    fi
    for port in "${ports[@]}"; do
        if ss -Htanl | grep -qE "[:.]${port} "; then
            error "Port ${port} is in use. Please free it before recreating the cluster."
            exit 1
        fi
    done
}

mapfile -t EXISTING_CLUSTERS < <(kind get clusters 2>/dev/null || true)
for cluster in "${EXISTING_CLUSTERS[@]}"; do
    [ -n "$cluster" ] || continue
    echo -e "${YELLOW}⚠️  Deleting existing cluster (${cluster})...${NC}"
    idpbuilder delete || kind delete cluster --name "$cluster" || true
done

cleanup_kind_artifacts
ensure_kind_ports_free

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

# Step 3: Generate minimal Kind configuration with Azure Workload Identity
CONFIG_FILE="${DEPLOYMENT_DIR}/config/kind-config.yaml"
echo -e "${GREEN}Generating Kind configuration with Azure Workload Identity...${NC}"

# Ensure config directory exists
mkdir -p "${DEPLOYMENT_DIR}/config"

# Use SERVICE_ACCOUNT_ISSUER from wi.env, or fall back to default
SERVICE_ACCOUNT_ISSUER="${SERVICE_ACCOUNT_ISSUER:-https://oidcissuer65846b7df97b.z13.web.core.windows.net/}"

# Generate Docker Hub registry config from 1Password (avoids rate limiting)
CONTAINERD_CONFIG_DIR="${DEPLOYMENT_DIR}/config/containerd"
DOCKER_USER="vpittamp23"
if command -v op &>/dev/null; then
    echo -e "${GREEN}Generating Docker Hub registry config from 1Password...${NC}"
    DOCKER_TOKEN=$(op read 'op://CLI/DOCKER_PERSONAL_ACCESS_TOKEN/password' 2>/dev/null)
    if [ -n "$DOCKER_TOKEN" ]; then
        mkdir -p "${CONTAINERD_CONFIG_DIR}/docker.io"
        AUTH_B64=$(echo -n "${DOCKER_USER}:${DOCKER_TOKEN}" | base64 -w0)
        cat > "${CONTAINERD_CONFIG_DIR}/docker.io/hosts.toml" <<DOCKEREOF
server = "https://registry-1.docker.io"

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
  [host."https://registry-1.docker.io".header]
    Authorization = ["Basic ${AUTH_B64}"]
DOCKEREOF
        echo -e "${GREEN}✓ Docker Hub auth configured (200 pulls/6hr limit)${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not retrieve Docker token from 1Password${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  1Password CLI not available, skipping Docker Hub auth${NC}"
fi

cat > "${CONFIG_FILE}" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
    # Mount Azure Workload Identity service account keys
    - hostPath: ${KEYS_DIR}
      containerPath: /etc/kubernetes/pki/custom-keys
      readOnly: true
    # Mount Docker Hub registry config (with auth from 1Password)
    - hostPath: ${CONTAINERD_CONFIG_DIR}
      containerPath: /etc/containerd/certs.d
      readOnly: true

  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        # Azure Workload Identity OIDC issuer
        service-account-issuer: "${SERVICE_ACCOUNT_ISSUER}"
        service-account-key-file: /etc/kubernetes/pki/custom-keys/sa.pub
        service-account-signing-key-file: /etc/kubernetes/pki/custom-keys/sa.key
    controllerManager:
      extraArgs:
        service-account-private-key-file: /etc/kubernetes/pki/custom-keys/sa.key

containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
EOF

echo -e "${GREEN}✓ Generated config with issuer: ${SERVICE_ACCOUNT_ISSUER}${NC}"


# Step 4: Create cluster with idpbuilder
echo -e "${GREEN}Creating Kind cluster with Azure Workload Identity support...${NC}"
echo -e "${BLUE}Using config: ${CONFIG_FILE}${NC}"

# Clear any Docker environment variables from WSL
unset DOCKER_HOST
unset DOCKER_TLS_VERIFY
unset DOCKER_CERT_PATH

# Create cluster using idpbuilder defaults
echo -e "${BLUE}Allowing IDPBuilder to generate self-signed certificates${NC}"

if [ -x "$STACKS_DIR/scripts/cluster/remove-core-dns-package.sh" ]; then
    echo -e "${GREEN}Cleaning legacy CoreDNS overrides (if any)${NC}"
    "$STACKS_DIR/scripts/cluster/remove-core-dns-package.sh" || true
fi

idpbuilder create --kind-config "${CONFIG_FILE}" --dev-password $IDPBUILDER_ARGS

ACTUAL_CLUSTER=$(kind get clusters 2>/dev/null | tail -1)
if [ -z "$ACTUAL_CLUSTER" ]; then
    echo -e "${RED}❌ Kind cluster was not created successfully${NC}"
    exit 1
fi
HOST_CONTEXT="kind-${ACTUAL_CLUSTER}"

# Step 5: Wait for cluster to be ready
echo -e "${GREEN}Waiting for cluster to be ready...${NC}"
for i in {1..30}; do
    if docker exec ${ACTUAL_CLUSTER}-control-plane kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}✓ Cluster nodes are ready${NC}"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

# Step 6: Get kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
mkdir -p ~/.kube

if ! kind get kubeconfig --name ${ACTUAL_CLUSTER} > ~/.kube/config 2>/dev/null; then
    echo -e "${RED}❌ Failed to write kubeconfig for cluster '${ACTUAL_CLUSTER}'${NC}"
    exit 1
fi

# Step 7: Verify keys are mounted correctly
echo -e "${GREEN}Verifying service account keys...${NC}"
# Use the actual cluster name
CONTAINER_NAME="${ACTUAL_CLUSTER}-control-plane"
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

if [ -x "$STACKS_DIR/scripts/certificates/sync-cluster-certificates.sh" ]; then
    echo -e "${GREEN}Syncing IDPBuilder certificates to local trust stores...${NC}"
    "$STACKS_DIR/scripts/certificates/sync-cluster-certificates.sh"
else
    echo -e "${YELLOW}Warning: sync-cluster-certificates.sh not found${NC}"
fi

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
if [ -f "${STACKS_DIR}/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh" ]; then
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
        echo -e "${YELLOW}  ${STACKS_DIR}/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh${NC}"
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
    ${STACKS_DIR}/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ JWKS successfully synced to Azure${NC}"
        
        # Wait a moment for Azure to process the update
        echo "  Waiting for Azure to process JWKS update..."
        sleep 5
    else
        echo -e "${RED}⚠️  JWKS sync failed - External Secrets will not work properly${NC}"
        echo -e "${YELLOW}You can manually run: ${STACKS_DIR}/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh${NC}"
    fi
else
    echo -e "${RED}⚠️  Azure JWKS sync script not found - External Secrets will fail${NC}"
    echo -e "${YELLOW}Expected at: ${STACKS_DIR}/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh${NC}"
fi

# Step 11: Verify External Secrets health
echo -e "${GREEN}Verifying External Secrets configuration...${NC}"
if kubectl wait --for=condition=Ready clustersecretstore/azure-keyvault-store --timeout=120s &>/dev/null; then
    echo -e "${GREEN}✓ Azure Key Vault integration is working${NC}"
else
    STATUS=$(kubectl get clustersecretstore azure-keyvault-store -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo "NotFound")
    if [ "$STATUS" = "NotFound" ]; then
        echo -e "${YELLOW}⚠️  ClusterSecretStore 'azure-keyvault-store' not found yet.${NC}"
        echo -e "${YELLOW}ArgoCD may still be syncing applications. Monitor progress with:${NC}"
        echo -e "${YELLOW}  kubectl get applications -n argocd${NC}"
    else
        echo -e "${YELLOW}⚠️  Azure Key Vault status: $STATUS${NC}"
        echo -e "${YELLOW}Inspect logs with: kubectl logs -n external-secrets deploy/external-secrets${NC}"
    fi
fi

# Step 12: Setup browser certificates (lightweight, no rebuild needed)
if [ -f "$STACKS_DIR/scripts/certificates/setup-browser-certs.sh" ]; then
    echo -e "${GREEN}Setting up browser certificates...${NC}"
    "$STACKS_DIR/scripts/certificates/setup-browser-certs.sh" 2>&1 | grep -E "(✓|Warning:|Error:)" || true
fi

# Step 13: Refresh ArgoCD token in 1Password
if [ -x "$STACKS_DIR/scripts/cluster/update-argocd-token.sh" ]; then
    echo -e "${GREEN}Updating ArgoCD token in 1Password...${NC}"
    if ! "$STACKS_DIR/scripts/cluster/update-argocd-token.sh"; then
        echo -e "${YELLOW}⚠️  Unable to store ArgoCD token automatically; check logs above.${NC}"
    fi
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
kubectl config get-contexts | grep -E "(CURRENT|kind-|dev|staging)" | grep -v "vcluster_"
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
