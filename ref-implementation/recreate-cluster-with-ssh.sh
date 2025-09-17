#!/bin/bash
# Script to recreate IDPBuilder cluster with SSH NodePort support
# This enables direct SSH access to DevSpace containers without port-forwarding
# Automatically detects and handles NixOS environment

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   IDPBuilder Cluster Recreation with SSH Support"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-localdev}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Detect if we're on NixOS
IS_NIXOS=false
if [ -f /etc/os-release ] && grep -q "NixOS" /etc/os-release; then
    IS_NIXOS=true
    echo -e "${BLUE}Detected NixOS environment${NC}"
fi

# Choose appropriate config file
if [ "$IS_NIXOS" = true ]; then
    KIND_CONFIG=${KIND_CONFIG:-"kind-config-nixos-ssh.yaml"}
    echo -e "${BLUE}Using NixOS-compatible configuration${NC}"
else
    KIND_CONFIG=${KIND_CONFIG:-"kind-config-with-ssh.yaml"}
fi

echo -e "${YELLOW}⚠️  WARNING: This will DELETE and RECREATE your cluster!${NC}"
echo -e "${YELLOW}⚠️  All data in the current cluster will be lost.${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Aborted."
    exit 1
fi

# Step 1: Delete existing cluster
echo -e "${BLUE}Step 1: Deleting existing cluster...${NC}"
idpbuilder delete || true

# Step 2: Check for service account keys if on NixOS
if [ "$IS_NIXOS" = true ]; then
    KEYS_DIR="${SCRIPT_DIR}/keys"
    if [ ! -f "${KEYS_DIR}/sa.key" ] || [ ! -f "${KEYS_DIR}/sa.pub" ]; then
        echo -e "${YELLOW}Warning: Service account keys not found in ${KEYS_DIR}${NC}"
        echo -e "${YELLOW}Cluster will use default keys (Azure Workload Identity won't work)${NC}"
        echo ""
        echo "To generate keys for Azure Workload Identity:"
        echo "  mkdir -p ${KEYS_DIR}"
        echo "  openssl genrsa -out ${KEYS_DIR}/sa.key 2048"
        echo "  openssl rsa -in ${KEYS_DIR}/sa.key -pubout -out ${KEYS_DIR}/sa.pub"
        echo ""
    fi
fi

# Step 3: Create new cluster with SSH support
echo -e "${BLUE}Step 2: Creating cluster with SSH NodePort mappings...${NC}"
echo "Using Kind config: $SCRIPT_DIR/$KIND_CONFIG"

# Check if the config file exists
if [ ! -f "$SCRIPT_DIR/$KIND_CONFIG" ]; then
    echo -e "${RED}Error: Kind config file not found at $SCRIPT_DIR/$KIND_CONFIG${NC}"
    exit 1
fi

# Create cluster
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

idpbuilder create \
    --kind-config "$SCRIPT_DIR/$KIND_CONFIG" \
    --name "$CLUSTER_NAME" \
    ${CERT_OVERRIDES[@]} \
    --dev-password

# Step 4: Handle NixOS key replacement if needed
if [ "$IS_NIXOS" = true ] && [ -f "${KEYS_DIR}/sa.key" ] && [ -f "${KEYS_DIR}/sa.pub" ]; then
    echo -e "${BLUE}Step 3a: Replacing service account keys (NixOS)...${NC}"
    
    # Copy keys into container
    cat ${KEYS_DIR}/sa.key | docker exec -i ${CLUSTER_NAME}-control-plane tee /tmp/sa.key > /dev/null
    cat ${KEYS_DIR}/sa.pub | docker exec -i ${CLUSTER_NAME}-control-plane tee /tmp/sa.pub > /dev/null
    
    # Replace keys
    docker exec ${CLUSTER_NAME}-control-plane bash -c "
        cp /etc/kubernetes/pki/sa.key /etc/kubernetes/pki/sa.key.bak 2>/dev/null || true
        cp /etc/kubernetes/pki/sa.pub /etc/kubernetes/pki/sa.pub.bak 2>/dev/null || true
        cp /tmp/sa.key /etc/kubernetes/pki/sa.key
        cp /tmp/sa.pub /etc/kubernetes/pki/sa.pub
        chmod 600 /etc/kubernetes/pki/sa.key
        chmod 644 /etc/kubernetes/pki/sa.pub
        rm /tmp/sa.key /tmp/sa.pub
    "
    
    # Restart API server and controller manager
    echo -e "${BLUE}Step 3b: Restarting Kubernetes components...${NC}"
    kubectl delete pod -n kube-system -l component=kube-apiserver --force --grace-period=0 2>/dev/null || true
    sleep 5
    kubectl delete pod -n kube-system -l component=kube-controller-manager --force --grace-period=0 2>/dev/null || true
    
    # Wait for API to be ready again
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
fi

# Step 5: Wait for cluster to be ready
echo -e "${BLUE}Step 4: Waiting for cluster to be ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

if [ -x "$HOME/stacks/scripts/sync-cluster-certificates.sh" ]; then
    echo -e "${GREEN}Syncing IDPBuilder certificates to local trust stores...${NC}"
    "$HOME/stacks/scripts/sync-cluster-certificates.sh"
else
    echo -e "${YELLOW}Warning: sync-cluster-certificates.sh not found${NC}"
fi

# Step 6: Apply CDK8s manifests with SSH services
echo -e "${BLUE}Step 5: Applying SSH service configurations...${NC}"
echo "Note: You'll need to rebuild CDK8s and apply the manifests"
echo ""
echo "Run these commands:"
echo -e "${GREEN}cd /home/vpittamp/stacks/cdk8s${NC}"
echo -e "${GREEN}npm run synth${NC}"
echo -e "${GREEN}kubectl apply -f dist/backstage-dev/manifests/${NC}"
echo ""

# Step 7: Show SSH port mappings
echo -e "${BLUE}Step 6: SSH Port Mappings${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "The following SSH ports are now available:"
echo ""
echo -e "  ${GREEN}30022${NC} → backstage-dev SSH"
echo -e "  ${GREEN}30023${NC} → backstage-staging SSH"
echo -e "  ${GREEN}30024${NC} → nextjs-dev SSH"
echo -e "  ${GREEN}30025${NC} → nextjs-staging SSH"
echo -e "  ${GREEN}30026${NC} → (reserved for future use)"
echo -e "  ${GREEN}30027${NC} → (reserved for future use)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}✓ Cluster recreated with SSH support!${NC}"
echo ""
echo "Next steps:"
echo "1. Rebuild and apply your CDK8s configurations"
echo "2. Start DevSpace for your application"
echo "3. Connect via SSH directly to localhost:30022 (for backstage-dev)"
echo ""
echo "Example SSH connection:"
echo -e "${YELLOW}ssh -p 30022 devspace@localhost${NC}"
echo ""
echo "VS Code Remote SSH config:"
echo "Host backstage-dev-ssh"
echo "  HostName localhost"
echo "  Port 30022"
echo "  User devspace"
echo "  IdentityFile ~/.devspace/ssh/id_devspace_ecdsa"
echo ""
