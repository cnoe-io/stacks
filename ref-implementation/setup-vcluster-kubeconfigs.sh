#!/usr/bin/env bash
# Setup VCluster kubeconfigs and merge them into the main kubeconfig
# This script properly generates and manages VCluster contexts

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   VCluster Kubeconfig Setup${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check prerequisites
if ! command -v vcluster &>/dev/null; then
    echo -e "${RED}vcluster CLI not found. Installing...${NC}"
    curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64"
    chmod +x vcluster
    sudo mv vcluster /usr/local/bin/
fi

if ! kubectl cluster-info &>/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to host cluster. Please ensure cluster is running.${NC}"
    exit 1
fi

# VCluster configurations
declare -A VCLUSTERS=(
    ["dev"]="vcluster-dev-helm:dev-vcluster:https://dev-vcluster.cnoe.localtest.me:8443"
    ["staging"]="vcluster-staging-helm:staging-vcluster:https://staging-vcluster.cnoe.localtest.me:8443"
)

# Create directory for vcluster kubeconfigs
VCLUSTER_KUBECONFIG_DIR="${HOME}/.kube/vclusters"
mkdir -p "${VCLUSTER_KUBECONFIG_DIR}"

# Track successful configurations
CONFIGURED_VCLUSTERS=()

for ENV in "${!VCLUSTERS[@]}"; do
    IFS=':' read -r NAME NAMESPACE SERVER_URL <<< "${VCLUSTERS[$ENV]}"
    
    echo -e "${BLUE}Processing ${ENV} vcluster...${NC}"
    
    # Check if vcluster pod exists
    if ! kubectl get pod "${NAME}-0" -n "${NAMESPACE}" &>/dev/null 2>&1; then
        echo -e "${YELLOW}  ${ENV} vcluster not found. It may not be deployed yet.${NC}"
        continue
    fi
    
    # Wait for vcluster to be ready
    echo "  Waiting for ${ENV} vcluster to be ready..."
    if ! kubectl wait --for=condition=Ready pod "${NAME}-0" -n "${NAMESPACE}" --timeout=60s &>/dev/null 2>&1; then
        echo -e "${YELLOW}  ${ENV} vcluster pod not ready after 60s${NC}"
        continue
    fi
    
    # Generate kubeconfig using vcluster CLI
    echo "  Generating kubeconfig for ${ENV} vcluster..."
    VCLUSTER_KUBECONFIG="${VCLUSTER_KUBECONFIG_DIR}/${ENV}.yaml"
    
    # Use vcluster to generate the kubeconfig
    if vcluster connect "${NAME}" \
        -n "${NAMESPACE}" \
        --server "${SERVER_URL}" \
        --insecure \
        --update-current=false \
        --kube-config="${VCLUSTER_KUBECONFIG}" &>/dev/null 2>&1; then
        
        echo -e "${GREEN}  ✓ Generated kubeconfig for ${ENV} vcluster${NC}"
        
        # Update the context name in the generated kubeconfig (handle both old and new cluster names)
        kubectl config rename-context \
            "vcluster_${NAME}_${NAMESPACE}_kind-local" \
            "${ENV}" \
            --kubeconfig="${VCLUSTER_KUBECONFIG}" 2>/dev/null || \
        kubectl config rename-context \
            "vcluster_${NAME}_${NAMESPACE}_kind-localdev" \
            "${ENV}" \
            --kubeconfig="${VCLUSTER_KUBECONFIG}" 2>/dev/null || true
        
        # Set the current context in the vcluster kubeconfig
        kubectl config use-context "${ENV}" \
            --kubeconfig="${VCLUSTER_KUBECONFIG}" 2>/dev/null || true
        
        CONFIGURED_VCLUSTERS+=("${ENV}")
    else
        echo -e "${YELLOW}  Failed to generate kubeconfig for ${ENV} vcluster${NC}"
        
        # Alternative method: Extract service account token directly
        echo "  Trying alternative method..."
        
        # Get the service account token
        SECRET_NAME=$(kubectl get sa vc-${NAME} -n ${NAMESPACE} -o jsonpath='{.secrets[0].name}' 2>/dev/null || echo "")
        
        if [ -z "$SECRET_NAME" ]; then
            # For newer Kubernetes versions, create a token
            echo "  Creating service account token..."
            TOKEN=$(kubectl create token vc-${NAME} -n ${NAMESPACE} --duration=87600h 2>/dev/null || echo "")
        else
            TOKEN=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
        fi
        
        if [ -n "$TOKEN" ]; then
            # Create kubeconfig manually
            cat > "${VCLUSTER_KUBECONFIG}" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: ${SERVER_URL}
  name: ${ENV}
contexts:
- context:
    cluster: ${ENV}
    user: ${ENV}
  name: ${ENV}
current-context: ${ENV}
users:
- name: ${ENV}
  user:
    token: ${TOKEN}
EOF
            echo -e "${GREEN}  ✓ Created kubeconfig for ${ENV} vcluster (alternative method)${NC}"
            CONFIGURED_VCLUSTERS+=("${ENV}")
        else
            echo -e "${RED}  Failed to create kubeconfig for ${ENV} vcluster${NC}"
        fi
    fi
done

# Merge vcluster kubeconfigs with main kubeconfig
if [ ${#CONFIGURED_VCLUSTERS[@]} -gt 0 ]; then
    echo ""
    echo -e "${GREEN}Merging VCluster kubeconfigs...${NC}"
    
    # Backup current kubeconfig
    cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d_%H%M%S)
    
    # Build KUBECONFIG path list
    KUBECONFIG_LIST="${HOME}/.kube/config"
    for ENV in "${CONFIGURED_VCLUSTERS[@]}"; do
        KUBECONFIG_LIST="${KUBECONFIG_LIST}:${VCLUSTER_KUBECONFIG_DIR}/${ENV}-vcluster.yaml"
    done
    
    # Merge all kubeconfigs
    KUBECONFIG="${KUBECONFIG_LIST}" kubectl config view --flatten > ~/.kube/config.merged
    mv ~/.kube/config.merged ~/.kube/config
    
    echo -e "${GREEN}✓ Kubeconfigs merged successfully${NC}"
fi

# Test connections
echo ""
echo -e "${GREEN}Testing VCluster connections...${NC}"
for ENV in "${CONFIGURED_VCLUSTERS[@]}"; do
    echo -n "  Testing ${ENV}-vcluster: "
    if kubectl get ns --context="${ENV}-vcluster" &>/dev/null 2>&1; then
        NODE_COUNT=$(kubectl get nodes --context="${ENV}-vcluster" 2>/dev/null | tail -n +2 | wc -l)
        NS_COUNT=$(kubectl get ns --context="${ENV}-vcluster" 2>/dev/null | tail -n +2 | wc -l)
        echo -e "${GREEN}✓ Connected (${NODE_COUNT} nodes, ${NS_COUNT} namespaces)${NC}"
    else
        echo -e "${RED}✗ Connection failed${NC}"
    fi
done

# Show summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ VCluster Setup Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ ${#CONFIGURED_VCLUSTERS[@]} -gt 0 ]; then
    echo -e "${BLUE}Configured VClusters:${NC}"
    for ENV in "${CONFIGURED_VCLUSTERS[@]}"; do
        echo "  - ${ENV}-vcluster"
    done
    echo ""
    echo -e "${BLUE}Kubeconfig locations:${NC}"
    echo "  Main: ~/.kube/config"
    echo "  VClusters: ${VCLUSTER_KUBECONFIG_DIR}/"
    echo ""
    echo -e "${BLUE}Switch contexts:${NC}"
    echo "  kubectl config use-context kind-localdev     # Host cluster"
    for ENV in "${CONFIGURED_VCLUSTERS[@]}"; do
        echo "  kubectl config use-context ${ENV}-vcluster   # ${ENV^} environment"
    done
    echo ""
    echo -e "${BLUE}Direct access:${NC}"
    for ENV in "${CONFIGURED_VCLUSTERS[@]}"; do
        echo "  kubectl --context=${ENV} get pods --all-namespaces"
    done
else
    echo -e "${YELLOW}No VClusters were configured.${NC}"
    echo "This could mean:"
    echo "  1. VClusters are not deployed yet (check ArgoCD)"
    echo "  2. VClusters are still initializing"
    echo "  3. There's an issue with the vcluster CLI"
    echo ""
    echo "Check VCluster status:"
    echo "  kubectl get pods -n dev-vcluster"
    echo "  kubectl get pods -n staging-vcluster"
fi

# Show current contexts
echo ""
echo -e "${BLUE}Current contexts:${NC}"
kubectl config get-contexts | grep -E "(CURRENT|kind-localdev|dev-vcluster|staging-vcluster)" || true