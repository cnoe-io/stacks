#!/bin/bash
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
    echo "This script creates a Kind cluster on NixOS with Azure Workload Identity support."
    echo "It works around NixOS WSL Docker Desktop mounting issues by copying keys after cluster creation."
    echo ""
    echo "Examples:"
    echo "  $0                                    # Basic cluster creation"
    echo "  $0 --package ../dist/my-app          # Deploy with a specific package"
    echo "  $0 --use-catalog                     # Use the catalog"
    echo "  $0 --package ../dist/app1 --package ../dist/app2  # Multiple packages"
    echo ""
    echo "All arguments are passed directly to 'idpbuilder create' after --kind-config"
    exit 0
fi

# Capture additional arguments to pass to idpbuilder
IDPBUILDER_ARGS="$@"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}NixOS Kind Cluster Deployment Script${NC}"
echo -e "${GREEN}======================================${NC}"

if [ -n "$IDPBUILDER_ARGS" ]; then
    echo -e "${YELLOW}Additional arguments for idpbuilder: $IDPBUILDER_ARGS${NC}"
fi

# Step 1: Delete existing cluster if it exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Deleting existing cluster...${NC}"
    kind delete cluster --name ${CLUSTER_NAME}
fi

# Step 2: Create cluster without mounted keys
echo -e "${GREEN}Creating Kind cluster...${NC}"
idpbuilder create --kind-config ${SCRIPT_DIR}/kind-config-nixos.yaml --dev-password $IDPBUILDER_ARGS

# Step 3: Wait for cluster to be ready
echo -e "${GREEN}Waiting for cluster to be ready...${NC}"
for i in {1..30}; do
    if docker exec ${CLUSTER_NAME}-control-plane kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}Cluster nodes are ready${NC}"
        break
    fi
    echo "Waiting for cluster... ($i/30)"
    sleep 2
done

# Step 4: Get kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
kind get kubeconfig --name ${CLUSTER_NAME} > ~/.kube/config

# Step 5: Copy custom keys into the container
# Note: docker cp doesn't work properly on NixOS WSL, using cat and docker exec instead
echo -e "${GREEN}Copying custom service account keys...${NC}"
cat ${SCRIPT_DIR}/keys/sa.key | docker exec -i ${CLUSTER_NAME}-control-plane tee /tmp/sa.key > /dev/null
cat ${SCRIPT_DIR}/keys/sa.pub | docker exec -i ${CLUSTER_NAME}-control-plane tee /tmp/sa.pub > /dev/null

# Step 6: Backup original keys and replace with custom ones
echo -e "${GREEN}Replacing service account keys in container...${NC}"
docker exec ${CLUSTER_NAME}-control-plane bash -c "
    # Backup original keys
    cp /etc/kubernetes/pki/sa.key /etc/kubernetes/pki/sa.key.bak
    cp /etc/kubernetes/pki/sa.pub /etc/kubernetes/pki/sa.pub.bak
    
    # Replace with custom keys
    cp /tmp/sa.key /etc/kubernetes/pki/sa.key
    cp /tmp/sa.pub /etc/kubernetes/pki/sa.pub
    
    # Fix permissions
    chmod 600 /etc/kubernetes/pki/sa.key
    chmod 644 /etc/kubernetes/pki/sa.pub
    
    # Clean up temp files
    rm /tmp/sa.key /tmp/sa.pub
"

# Step 7: Restart API server to pick up new keys
echo -e "${GREEN}Restarting API server...${NC}"
kubectl delete pod -n kube-system -l component=kube-apiserver --force --grace-period=0 2>/dev/null || true

# Wait for API server to come back
echo -e "${GREEN}Waiting for API server to restart...${NC}"
for i in {1..60}; do
    if kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}API server is ready${NC}"
        break
    fi
    echo "Waiting for API server... ($i/60)"
    sleep 2
done

# Step 8: Restart controller manager to pick up new keys
echo -e "${GREEN}Restarting controller manager...${NC}"
kubectl delete pod -n kube-system -l component=kube-controller-manager --force --grace-period=0 2>/dev/null || true

# Step 9: Sync JWKS to Azure
echo -e "${GREEN}Syncing JWKS to Azure...${NC}"
if [ -f "${SCRIPT_DIR}/sync-jwks-to-azure.sh" ]; then
    ${SCRIPT_DIR}/sync-jwks-to-azure.sh
else
    echo -e "${YELLOW}Warning: sync-jwks-to-azure.sh not found${NC}"
    echo -e "${YELLOW}Please run it manually to enable Azure Workload Identity${NC}"
fi

# Step 10: Wait for Azure AD cache to refresh
echo -e "${GREEN}Waiting for Azure AD cache to refresh (60 seconds)...${NC}"
sleep 60

# Step 11: Force reconciliation of ClusterSecretStore
echo -e "${GREEN}Forcing ClusterSecretStore reconciliation...${NC}"
kubectl annotate clustersecretstore azure-keyvault-store force-sync=$(date +%s) --overwrite 2>/dev/null || true

# Step 12: Verify deployment
echo -e "${GREEN}Verifying deployment...${NC}"
sleep 5

# Check ClusterSecretStore status
if kubectl get clustersecretstore azure-keyvault-store &>/dev/null; then
    STATUS=$(kubectl get clustersecretstore azure-keyvault-store -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "False")
    if [ "$STATUS" = "True" ]; then
        echo -e "${GREEN}✅ ClusterSecretStore is ready${NC}"
        
        # Count synced secrets
        SYNCED=$(kubectl get externalsecret -A 2>/dev/null | grep -c "SecretSynced.*True" || echo "0")
        echo -e "${GREEN}✅ $SYNCED external secrets successfully synced${NC}"
    else
        echo -e "${YELLOW}⚠️  ClusterSecretStore is not ready yet${NC}"
        echo -e "${YELLOW}   Azure AD might need more time to refresh cache${NC}"
        echo -e "${YELLOW}   Try running: kubectl get clustersecretstore azure-keyvault-store -o yaml${NC}"
    fi
fi

# Step 13: Setup VCluster kubeconfigs
echo -e "${GREEN}Setting up VCluster kubeconfigs...${NC}"

# Check if vcluster CLI is available
if command -v vcluster &>/dev/null; then
    # Define vclusters to connect
    VCLUSTER_CONFIGS=(
        "vcluster-dev-helm:dev-vcluster:dev"
        "vcluster-staging-helm:staging-vcluster:staging"
    )
    
    VCLUSTER_CONTEXTS=()
    
    for vcluster_config in "${VCLUSTER_CONFIGS[@]}"; do
        IFS=':' read -r NAME NAMESPACE ENV <<< "${vcluster_config}"
        
        echo -e "${GREEN}Checking ${ENV} vcluster...${NC}"
        
        # Wait for vcluster pod to be running
        VCLUSTER_READY=false
        for i in {1..30}; do
            if kubectl get pod "${NAME}-0" -n "${NAMESPACE}" &>/dev/null; then
                POD_STATUS=$(kubectl get pod "${NAME}-0" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null)
                if [ "$POD_STATUS" = "Running" ]; then
                    VCLUSTER_READY=true
                    echo -e "${GREEN}  ✅ ${ENV} vcluster is running${NC}"
                    break
                fi
            fi
            if [ $i -eq 1 ]; then
                echo "  Waiting for ${ENV} vcluster to be ready..."
            fi
            sleep 2
        done
        
        if [ "$VCLUSTER_READY" = true ]; then
            # Generate and merge kubeconfig
            TEMP_CONFIG=$(mktemp)
            
            # Use the ingress URL for direct access (no port-forwarding needed)
            INGRESS_URL="https://${ENV}-vcluster.cnoe.localtest.me:8443"
            
            if vcluster connect "${NAME}" -n "${NAMESPACE}" --server "${INGRESS_URL}" --insecure --print > "${TEMP_CONFIG}" 2>/dev/null; then
                # Backup current config if not already backed up
                if [ ! -f ~/.kube/config.pre-vcluster ]; then
                    cp ~/.kube/config ~/.kube/config.pre-vcluster
                fi
                
                # Merge into main kubeconfig
                KUBECONFIG=~/.kube/config:"${TEMP_CONFIG}" kubectl config view --flatten > ~/.kube/config.new
                mv ~/.kube/config.new ~/.kube/config
                
                # Get the context name that was added
                CONTEXT_NAME=$(grep "current-context:" "${TEMP_CONFIG}" | cut -d' ' -f2)
                VCLUSTER_CONTEXTS+=("${ENV}:${CONTEXT_NAME}")
                
                echo -e "${GREEN}  ✅ Added kubeconfig for ${ENV} vcluster${NC}"
            else
                echo -e "${YELLOW}  ⚠️  Failed to get kubeconfig for ${ENV} vcluster${NC}"
            fi
            
            rm -f "${TEMP_CONFIG}"
        else
            echo -e "${YELLOW}  ⚠️  ${ENV} vcluster not ready, skipping${NC}"
        fi
    done
    
    echo ""
else
    echo -e "${YELLOW}⚠️  vcluster CLI not found, skipping vcluster kubeconfig setup${NC}"
    echo -e "${YELLOW}   Install with: curl -L -o vcluster 'https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64' && chmod +x vcluster && sudo mv vcluster /usr/local/bin${NC}"
fi

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Cluster endpoints:"
echo "  ArgoCD:    https://argocd.cnoe.localtest.me:8443"
echo "  Gitea:     https://gitea.cnoe.localtest.me:8443"
echo "  Backstage: https://backstage.cnoe.localtest.me:8443"
echo ""
echo "To check cluster status: kubectl get nodes"
echo "To check secrets: kubectl get externalsecret -A"
echo ""

# Show available contexts if vclusters were added
if [ ${#VCLUSTER_CONTEXTS[@]} -gt 0 ]; then
    echo -e "${GREEN}Available Kubernetes contexts:${NC}"
    echo "  Host cluster: kind-localdev (current)"
    
    for vcluster_context in "${VCLUSTER_CONTEXTS[@]}"; do
        IFS=':' read -r ENV CONTEXT <<< "${vcluster_context}"
        echo "  ${ENV} vcluster: ${CONTEXT}"
    done
    
    echo ""
    echo -e "${BLUE}To switch contexts:${NC}"
    echo "  kubectl config use-context <context-name>"
    echo ""
    echo -e "${BLUE}Example:${NC}"
    if [ ${#VCLUSTER_CONTEXTS[@]} -gt 0 ]; then
        IFS=':' read -r ENV CONTEXT <<< "${VCLUSTER_CONTEXTS[0]}"
        echo "  kubectl config use-context ${CONTEXT}"
        echo "  kubectl get pods -A  # Now shows ${ENV} vcluster pods"
    fi
    echo ""
    echo -e "${GREEN}Note:${NC} VClusters are accessible via ingress URLs - no port-forwarding needed!"
    echo "  Dev: https://dev-vcluster.cnoe.localtest.me:8443"
    echo "  Staging: https://staging-vcluster.cnoe.localtest.me:8443"
fi
