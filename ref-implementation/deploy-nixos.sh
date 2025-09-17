#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup_kind_artifacts() {
    local containers networks
    containers=$(docker ps -aq --filter "label=io.x-k8s.kind.cluster")
    if [ -n "$containers" ]; then
        echo -e "${YELLOW}Removing lingering kind containers...${NC}"
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
            echo -e "${RED}Port ${port} is in use. Please free it before recreating the cluster.${NC}"
            exit 1
        fi
    done
}

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
mapfile -t EXISTING_CLUSTERS < <(kind get clusters 2>/dev/null || true)
for cluster in "${EXISTING_CLUSTERS[@]}"; do
    [ -n "$cluster" ] || continue
    echo -e "${YELLOW}Deleting existing cluster (${cluster})...${NC}"
    kind delete cluster --name "$cluster" || true
done

cleanup_kind_artifacts
ensure_kind_ports_free

# Step 2: Create cluster without mounted keys
echo -e "${GREEN}Creating Kind cluster...${NC}"

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

idpbuilder create --kind-config ${SCRIPT_DIR}/kind-config-nixos.yaml ${CERT_OVERRIDES[@]} --dev-password $IDPBUILDER_ARGS

# Determine actual cluster name
ACTUAL_CLUSTER=$(kind get clusters 2>/dev/null | head -1)
if [ -z "$ACTUAL_CLUSTER" ]; then
    echo -e "${RED}❌ Kind cluster was not created successfully${NC}"
    exit 1
fi
HOST_CONTEXT="kind-${ACTUAL_CLUSTER}"

# Step 3: Wait for cluster to be ready
echo -e "${GREEN}Waiting for cluster to be ready...${NC}"
for i in {1..30}; do
    if docker exec ${ACTUAL_CLUSTER}-control-plane kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}Cluster nodes are ready${NC}"
        break
    fi
    echo "Waiting for cluster... ($i/30)"
    sleep 2
done

# Step 4: Get kubeconfig
echo -e "${GREEN}Updating kubeconfig...${NC}"
kind get kubeconfig --name ${ACTUAL_CLUSTER} > ~/.kube/config

# Step 5: Copy custom keys into the container
# Note: docker cp doesn't work properly on NixOS WSL, using cat and docker exec instead
echo -e "${GREEN}Copying custom service account keys...${NC}"
cat ${SCRIPT_DIR}/keys/sa.key | docker exec -i ${ACTUAL_CLUSTER}-control-plane tee /tmp/sa.key > /dev/null
cat ${SCRIPT_DIR}/keys/sa.pub | docker exec -i ${ACTUAL_CLUSTER}-control-plane tee /tmp/sa.pub > /dev/null

# Step 6: Backup original keys and replace with custom ones
echo -e "${GREEN}Replacing service account keys in container...${NC}"
docker exec ${ACTUAL_CLUSTER}-control-plane bash -c "
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

# Step 12b: Sync certificates into local/system trust stores
if [ -x "$HOME/stacks/scripts/sync-cluster-certificates.sh" ]; then
    echo -e "${GREEN}Syncing IDPBuilder certificates to local trust stores...${NC}"
    "$HOME/stacks/scripts/sync-cluster-certificates.sh"
else
    echo -e "${YELLOW}Warning: sync-cluster-certificates.sh not found${NC}"
fi

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
echo -e "${GREEN}Preparing local VCluster kubeconfigs...${NC}"

VCLUSTER_CONTEXTS=()
if [ -x "${SCRIPT_DIR}/setup-vcluster-kubeconfigs.sh" ]; then
    if HOST_CONTEXT_OVERRIDE="${HOST_CONTEXT}" ${SCRIPT_DIR}/setup-vcluster-kubeconfigs.sh; then
        for ENV in dev staging; do
            if kubectl config get-contexts "${ENV}" --no-headers >/dev/null 2>&1; then
                VCLUSTER_CONTEXTS+=("${ENV}")
            fi
        done
    else
        echo -e "${YELLOW}⚠️  setup-vcluster-kubeconfigs.sh reported issues${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  setup-vcluster-kubeconfigs.sh not found or not executable${NC}"
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
    echo "  Host cluster: ${HOST_CONTEXT} (current)"
    
    for ENV in "${VCLUSTER_CONTEXTS[@]}"; do
        echo "  ${ENV} vcluster: ${ENV}"
    done
    
    echo ""
    echo -e "${BLUE}To switch contexts:${NC}"
    echo "  kubectl config use-context <context-name>"
    echo ""
    echo -e "${BLUE}Example:${NC}"
    if [ ${#VCLUSTER_CONTEXTS[@]} -gt 0 ]; then
        FIRST_ENV="${VCLUSTER_CONTEXTS[0]}"
        echo "  kubectl config use-context ${FIRST_ENV}"
        echo "  kubectl get pods -A  # Now shows ${FIRST_ENV} vcluster pods"
    fi
    echo ""
    echo -e "${GREEN}Note:${NC} VClusters are accessible via ingress URLs - no port-forwarding needed!"
    echo "  Dev: https://dev-vcluster.cnoe.localtest.me:8443"
    echo "  Staging: https://staging-vcluster.cnoe.localtest.me:8443"
fi
