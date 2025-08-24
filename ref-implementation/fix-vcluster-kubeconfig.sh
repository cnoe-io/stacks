#!/bin/bash
# Fix vcluster kubeconfigs to use ingress URLs for Windows Headlamp access

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Fixing VCluster Kubeconfigs for Windows Headlamp${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Check if vcluster CLI is available
if ! command -v vcluster &>/dev/null; then
    echo -e "${RED}Error: vcluster CLI not found${NC}"
    echo -e "${YELLOW}Install with: curl -L -o vcluster 'https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64' && chmod +x vcluster && sudo mv vcluster /usr/local/bin${NC}"
    exit 1
fi

# Backup current config
BACKUP_FILE=~/.kube/config.backup-$(date +%Y%m%d-%H%M%S)
cp ~/.kube/config "${BACKUP_FILE}"
echo -e "${GREEN}✅ Backed up current kubeconfig to: ${BACKUP_FILE}${NC}"
echo ""

# Fix dev vcluster
NAME="vcluster-dev-helm"
NAMESPACE="dev-vcluster"
ENV="dev"
INGRESS_URL="https://dev-vcluster.cnoe.localtest.me:8443"
CONTEXT_NAME="vcluster_vcluster-dev-helm_dev-vcluster_kind-localdev"

echo -e "${GREEN}Updating ${ENV} vcluster kubeconfig...${NC}"
echo "  Server URL: ${INGRESS_URL}"

# Check if vcluster exists (ensure we're in host context)
kubectl config use-context kind-localdev &>/dev/null || true
if kubectl get pod "${NAME}-0" -n "${NAMESPACE}" &>/dev/null; then
    TEMP_CONFIG=$(mktemp)
    
    if vcluster connect "${NAME}" -n "${NAMESPACE}" --server "${INGRESS_URL}" --insecure --print --update-current=false > "${TEMP_CONFIG}" 2>/dev/null; then
        # Remove old vcluster context if it exists
        kubectl config delete-context "${CONTEXT_NAME}" 2>/dev/null || true
        kubectl config delete-cluster "${CONTEXT_NAME}" 2>/dev/null || true
        kubectl config delete-user "${CONTEXT_NAME}" 2>/dev/null || true
        
        # Merge new config
        KUBECONFIG=~/.kube/config:"${TEMP_CONFIG}" kubectl config view --flatten > ~/.kube/config.new
        mv ~/.kube/config.new ~/.kube/config
        
        echo -e "${GREEN}  ✅ Updated ${ENV} vcluster context${NC}"
    else
        echo -e "${RED}  ✗ Failed to generate kubeconfig for ${ENV} vcluster${NC}"
    fi
    
    rm -f "${TEMP_CONFIG}"
else
    echo -e "${YELLOW}  ⚠️  ${ENV} vcluster not found, skipping${NC}"
fi

echo ""

# Fix staging vcluster
NAME="vcluster-staging-helm"
NAMESPACE="staging-vcluster"
ENV="staging"
INGRESS_URL="https://staging-vcluster.cnoe.localtest.me:8443"
CONTEXT_NAME="vcluster_vcluster-staging-helm_staging-vcluster_kind-localdev"

echo -e "${GREEN}Updating ${ENV} vcluster kubeconfig...${NC}"
echo "  Server URL: ${INGRESS_URL}"

# Check if vcluster exists (ensure we're in host context)
kubectl config use-context kind-localdev &>/dev/null || true
if kubectl get pod "${NAME}-0" -n "${NAMESPACE}" &>/dev/null; then
    TEMP_CONFIG=$(mktemp)
    
    if vcluster connect "${NAME}" -n "${NAMESPACE}" --server "${INGRESS_URL}" --insecure --print --update-current=false > "${TEMP_CONFIG}" 2>/dev/null; then
        # Remove old vcluster context if it exists
        kubectl config delete-context "${CONTEXT_NAME}" 2>/dev/null || true
        kubectl config delete-cluster "${CONTEXT_NAME}" 2>/dev/null || true
        kubectl config delete-user "${CONTEXT_NAME}" 2>/dev/null || true
        
        # Merge new config
        KUBECONFIG=~/.kube/config:"${TEMP_CONFIG}" kubectl config view --flatten > ~/.kube/config.new
        mv ~/.kube/config.new ~/.kube/config
        
        echo -e "${GREEN}  ✅ Updated ${ENV} vcluster context${NC}"
    else
        echo -e "${RED}  ✗ Failed to generate kubeconfig for ${ENV} vcluster${NC}"
    fi
    
    rm -f "${TEMP_CONFIG}"
else
    echo -e "${YELLOW}  ⚠️  ${ENV} vcluster not found, skipping${NC}"
fi

echo ""

# Verify the changes
echo -e "${GREEN}Current cluster server URLs:${NC}"
kubectl config view -o json | jq -r '.clusters[] | "  \(.name): \(.cluster.server)"' 2>/dev/null || kubectl config get-clusters

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}✅ Kubeconfig Fixed for Windows Headlamp${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "VClusters now use ingress URLs that are accessible from Windows:"
echo "  • Dev: https://dev-vcluster.cnoe.localtest.me:8443"
echo "  • Staging: https://staging-vcluster.cnoe.localtest.me:8443"
echo ""
echo -e "${YELLOW}Note:${NC} Headlamp may show certificate warnings for the self-signed certs."
echo "      These can be safely accepted."
echo ""
echo "To test a connection:"
echo "  kubectl config use-context vcluster_vcluster-dev-helm_dev-vcluster_kind-localdev"
echo "  kubectl get ns"