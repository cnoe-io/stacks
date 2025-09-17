#!/usr/bin/env bash
# Enhanced NixOS deployment script with SSH NodePort support
# Combines the NixOS key handling with SSH port exposure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="localdev"

# Show help if requested
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo -e "${BLUE}Usage: $0 [additional idpbuilder arguments]${NC}"
    echo ""
    echo "This script creates a Kind cluster on NixOS with:"
    echo "  - Azure Workload Identity support"
    echo "  - SSH NodePort access for development containers"
    echo "  - Workaround for NixOS WSL Docker Desktop mounting issues"
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
echo -e "${GREEN}   NixOS Kind Cluster with SSH Support${NC}"
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

# Step 2: Check if service account keys exist
KEYS_DIR="${SCRIPT_DIR}/keys"
if [ ! -f "${KEYS_DIR}/sa.key" ] || [ ! -f "${KEYS_DIR}/sa.pub" ]; then
    echo -e "${RED}Error: Service account keys not found in ${KEYS_DIR}${NC}"
    echo -e "${YELLOW}Please ensure sa.key and sa.pub exist in ${KEYS_DIR}${NC}"
    echo ""
    echo "To generate keys:"
    echo "  mkdir -p ${KEYS_DIR}"
    echo "  openssl genrsa -out ${KEYS_DIR}/sa.key 2048"
    echo "  openssl rsa -in ${KEYS_DIR}/sa.key -pubout -out ${KEYS_DIR}/sa.pub"
    exit 1
fi

# Step 3: Create cluster with SSH ports but without mounted keys
echo -e "${GREEN}Creating Kind cluster with SSH NodePort support...${NC}"
echo -e "${BLUE}Using config: ${SCRIPT_DIR}/kind-config-nixos-ssh.yaml${NC}"

# Check if the SSH config exists, fall back to regular nixos config
CONFIG_FILE="${SCRIPT_DIR}/kind-config-nixos-ssh.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}SSH config not found, using regular NixOS config${NC}"
    CONFIG_FILE="${SCRIPT_DIR}/kind-config-nixos.yaml"
fi

CERT_BASE="$HOME/stacks/certificates"
CERT_OVERRIDES=()
if [ -f "$CERT_BASE/nginx-override.yaml" ]; then
    CERT_OVERRIDES+=("-c" "nginx:$CERT_BASE/nginx-override.yaml")
fi
if [ -f "$CERT_BASE/argocd-override.yaml" ]; then
    CERT_OVERRIDES+=("-c" "argocd:$CERT_BASE/argocd-override.yaml")
fi

if [ ${#CERT_OVERRIDES[@]} -gt 0 ]; then
    echo -e "${BLUE}Using static certificate overrides for IDPBuilder${NC}"
else
    echo -e "${YELLOW}No certificate overrides found; cluster will create a new self-signed cert${NC}"
fi

idpbuilder create --kind-config "$CONFIG_FILE" ${CERT_OVERRIDES[@]} --dev-password $IDPBUILDER_ARGS

# Step 4: Wait for cluster to be ready
echo -e "${GREEN}Waiting for cluster to be ready...${NC}"
for i in {1..30}; do
    if docker exec ${CLUSTER_NAME}-control-plane kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}✓ Cluster nodes are ready${NC}"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

# Step 5: Get kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
mkdir -p ~/.kube
kind get kubeconfig --name ${CLUSTER_NAME} > ~/.kube/config

# Step 6: Copy custom keys into the container
echo -e "${GREEN}Installing custom service account keys...${NC}"
cat ${KEYS_DIR}/sa.key | docker exec -i ${CLUSTER_NAME}-control-plane tee /tmp/sa.key > /dev/null
cat ${KEYS_DIR}/sa.pub | docker exec -i ${CLUSTER_NAME}-control-plane tee /tmp/sa.pub > /dev/null

# Step 7: Replace keys in container
echo -e "${GREEN}Replacing service account keys...${NC}"
docker exec ${CLUSTER_NAME}-control-plane bash -c "
    # Backup original keys
    cp /etc/kubernetes/pki/sa.key /etc/kubernetes/pki/sa.key.bak 2>/dev/null || true
    cp /etc/kubernetes/pki/sa.pub /etc/kubernetes/pki/sa.pub.bak 2>/dev/null || true
    
    # Replace with custom keys
    cp /tmp/sa.key /etc/kubernetes/pki/sa.key
    cp /tmp/sa.pub /etc/kubernetes/pki/sa.pub
    
    # Fix permissions
    chmod 600 /etc/kubernetes/pki/sa.key
    chmod 644 /etc/kubernetes/pki/sa.pub
    
    # Clean up
    rm /tmp/sa.key /tmp/sa.pub
"

# Step 8: Restart API server
echo -e "${GREEN}Restarting API server...${NC}"
kubectl delete pod -n kube-system -l component=kube-apiserver --force --grace-period=0 2>/dev/null || true

# Wait for API server
for i in {1..60}; do
    if kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}✓ API server ready${NC}"
        break
    fi
    [ $i -eq 1 ] && echo -n "  Waiting for API server"
    echo -n "."
    sleep 2
done
echo ""

# Step 9: Restart controller manager
echo -e "${GREEN}Restarting controller manager...${NC}"
kubectl delete pod -n kube-system -l component=kube-controller-manager --force --grace-period=0 2>/dev/null || true

# Step 10: Wait for all system pods to be ready
echo -e "${GREEN}Waiting for system pods...${NC}"
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s

# Sync certificates into local/system trust stores
if [ -x "$HOME/stacks/scripts/sync-cluster-certificates.sh" ]; then
    echo -e "${GREEN}Syncing IDPBuilder certificates to local trust stores...${NC}"
    "$HOME/stacks/scripts/sync-cluster-certificates.sh"
else
    echo -e "${YELLOW}Warning: sync-cluster-certificates.sh not found${NC}"
fi

# Step 11: Deploy SSH services (if CDK8s manifests exist and namespaces are ready)
if [ -d "/home/vpittamp/stacks/cdk8s/dist" ]; then
    echo -e "${GREEN}Checking for SSH service manifests...${NC}"
    
    # Apply backstage SSH service if it exists and namespace is ready
    if [ -f "/home/vpittamp/stacks/cdk8s/dist/backstage-dev/manifests/Service.backstage-dev-ssh.k8s.yaml" ]; then
        if kubectl get namespace backstage &>/dev/null 2>&1; then
            echo -e "${GREEN}Applying backstage-dev SSH service...${NC}"
            kubectl apply -f /home/vpittamp/stacks/cdk8s/dist/backstage-dev/manifests/Service.backstage-dev-ssh.k8s.yaml
        else
            echo -e "${YELLOW}Backstage namespace not ready yet, skipping SSH service${NC}"
            echo -e "${YELLOW}Apply it later with: kubectl apply -f /home/vpittamp/stacks/cdk8s/dist/backstage-dev/manifests/Service.backstage-dev-ssh.k8s.yaml${NC}"
        fi
    fi
    
    # Apply other SSH services as needed
    for manifest in /home/vpittamp/stacks/cdk8s/dist/*/manifests/Service.*-ssh.k8s.yaml; do
        if [ -f "$manifest" ]; then
            # Extract namespace from the manifest
            NAMESPACE=$(grep "namespace:" "$manifest" | head -1 | awk '{print $2}')
            if [ -n "$NAMESPACE" ] && kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
                echo -e "${GREEN}Applying $(basename $manifest)...${NC}"
                kubectl apply -f "$manifest"
            else
                echo -e "${YELLOW}Namespace $NAMESPACE not ready, skipping $(basename $manifest)${NC}"
            fi
        fi
    done
fi

# Step 12: Sync JWKS to Azure (if script exists)
if [ -f "${SCRIPT_DIR}/sync-jwks-to-azure.sh" ]; then
    echo -e "${GREEN}Syncing JWKS to Azure...${NC}"
    ${SCRIPT_DIR}/sync-jwks-to-azure.sh
else
    echo -e "${YELLOW}Skipping Azure JWKS sync (script not found)${NC}"
fi

# Step 13: Show SSH port mappings
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Cluster created successfully with SSH support!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
echo ""
echo -e "${BLUE}SSH Access (after starting DevSpace):${NC}"
echo "  ssh -p 30022 devspace@localhost    # backstage-dev"
echo "  ssh -p 30024 devspace@localhost    # nextjs-dev"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Build CDK8s if needed:"
echo "   cd /home/vpittamp/stacks/cdk8s && npm run synth"
echo ""
echo "2. Apply your application manifests:"
echo "   kubectl apply -f /home/vpittamp/stacks/cdk8s/dist/backstage-dev/manifests/"
echo ""
echo "3. Start DevSpace for your app:"
echo "   cd /home/vpittamp/backstage-cnoe && devspace dev --skip-build"
echo ""
echo "4. Connect via SSH directly (no port-forward needed!):"
echo "   ssh -p 30022 devspace@localhost"
echo ""

# Step 14: Setup VClusters (optional, from original script)
if command -v vcluster &>/dev/null; then
    echo -e "${GREEN}Setting up VCluster connections...${NC}"
    
    # Wait for vclusters to be deployed by ArgoCD
    echo "  Waiting for vclusters to be ready..."
    for i in {1..60}; do
        if kubectl get pod vcluster-dev-helm-0 -n dev-vcluster &>/dev/null 2>&1 && \
           kubectl get pod vcluster-staging-helm-0 -n staging-vcluster &>/dev/null 2>&1; then
            echo -e "${GREEN}  VClusters pods found${NC}"
            break
        fi
        [ $i -eq 1 ] && echo -n "  Waiting"
        echo -n "."
        sleep 2
    done
    echo ""
    
    # Additional wait for vclusters to be fully ready
    sleep 10
    
    VCLUSTER_CONFIGS=(
        "vcluster-dev-helm:dev-vcluster:dev"
        "vcluster-staging-helm:staging-vcluster:staging"
    )
    
    for vcluster_config in "${VCLUSTER_CONFIGS[@]}"; do
        IFS=':' read -r NAME NAMESPACE ENV <<< "${vcluster_config}"
        
        # Check if vcluster exists and is running
        if kubectl get pod "${NAME}-0" -n "${NAMESPACE}" &>/dev/null 2>&1; then
            echo -e "${GREEN}  Found ${ENV} vcluster${NC}"
            
            # Get vcluster kubeconfig and merge it
            INGRESS_URL="https://${ENV}-vcluster.cnoe.localtest.me:8443"
            CONTEXT_NAME="${ENV}-vcluster"
            
            echo "  Getting kubeconfig for ${ENV} vcluster..."
            VCLUSTER_KUBECONFIG=$(vcluster connect "${NAME}" -n "${NAMESPACE}" --server "${INGRESS_URL}" --insecure --print 2>/dev/null)
            
            if [ -n "$VCLUSTER_KUBECONFIG" ]; then
                # Write temporary kubeconfig
                echo "$VCLUSTER_KUBECONFIG" > /tmp/vcluster-${ENV}.yaml
                
                # Merge with main kubeconfig
                KUBECONFIG="${HOME}/.kube/config:/tmp/vcluster-${ENV}.yaml" kubectl config view --flatten > /tmp/merged-config.yaml
                
                # Replace main kubeconfig
                mv /tmp/merged-config.yaml ${HOME}/.kube/config
                
                # Rename context to something more friendly
                kubectl config rename-context "vcluster_${NAME}_${NAMESPACE}_kind-localdev" "${CONTEXT_NAME}" 2>/dev/null || true
                
                echo -e "${GREEN}  ✓ Added ${CONTEXT_NAME} context${NC}"
                
                # Clean up temp file
                rm -f /tmp/vcluster-${ENV}.yaml
            else
                echo -e "${YELLOW}  Failed to get kubeconfig for ${ENV} vcluster${NC}"
            fi
        else
            echo -e "${YELLOW}  ${ENV} vcluster not found or not ready${NC}"
        fi
    done
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
