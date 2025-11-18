#!/usr/bin/env bash
# Generate remote Kubernetes access via Tailscale
# This script discovers cluster info and creates a simple remote access command

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Tailscale Remote Access Generator ===${NC}"
echo ""

# Check if running in cluster context
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo -e "${RED}❌ Not connected to Kubernetes cluster${NC}"
  echo "Please ensure kubectl is configured"
  exit 1
fi

# Check if Tailscale CLI is available
if ! command -v tailscale >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  Tailscale CLI not found locally${NC}"
  echo "Install with: curl -fsSL https://tailscale.com/install.sh | sh"
  echo ""
  echo "Continuing without local Tailscale checks..."
  TAILSCALE_AVAILABLE=false
else
  TAILSCALE_AVAILABLE=true
fi

echo -e "${BLUE}Step 1: Checking Tailscale deployment...${NC}"

# Check if Tailscale operator is deployed
if ! kubectl get namespace tailscale >/dev/null 2>&1; then
  echo -e "${RED}❌ Tailscale namespace not found${NC}"
  echo ""
  echo "Deploy Tailscale first:"
  echo "  source ~/stacks/deployment/scripts/cluster-menu.sh"
  echo "  clu"
  exit 1
fi

OPERATOR_POD=$(kubectl get pod -n tailscale -l app=tailscale-operator -o name 2>/dev/null | head -1)
if [ -z "$OPERATOR_POD" ]; then
  echo -e "${YELLOW}⚠️  Tailscale operator not found${NC}"
  echo "Checking for API proxy instead..."

  PROXY_POD=$(kubectl get pod -n tailscale -l app=tailscale-api-proxy -o name 2>/dev/null | head -1)
  if [ -z "$PROXY_POD" ]; then
    echo -e "${RED}❌ No Tailscale pods found${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓${NC} Found Tailscale API proxy"
  USE_PROXY=true
else
  echo -e "${GREEN}✓${NC} Found Tailscale operator"
  USE_PROXY=false
fi

echo ""
echo -e "${BLUE}Step 2: Discovering Tailscale hostname...${NC}"

# Get Tailscale hostname from the cluster
if [ "$USE_PROXY" = "true" ]; then
  # For API proxy, check the pod environment
  TAILSCALE_HOSTNAME=$(kubectl get pod -n tailscale -l app=tailscale-api-proxy -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="TS_HOSTNAME")].value}' 2>/dev/null || echo "")
  API_PORT="8001"
  USE_HTTPS=false
else
  # For operator, check ProxyGroup or operator logs
  TAILSCALE_HOSTNAME=$(kubectl get proxygroup -n tailscale -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  # If no ProxyGroup, try to get from operator deployment env
  if [ -z "$TAILSCALE_HOSTNAME" ]; then
    CLUSTER_NAME=$(kubectl get deployment -n tailscale tailscale-operator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OPERATOR_HOSTNAME")].value}' 2>/dev/null | sed 's/-operator$//' || echo "kind")
    TAILSCALE_HOSTNAME="${CLUSTER_NAME}-api-server"
  fi

  API_PORT="443"
  USE_HTTPS=true
fi

if [ -z "$TAILSCALE_HOSTNAME" ]; then
  echo -e "${RED}❌ Could not determine Tailscale hostname${NC}"
  exit 1
fi

echo -e "${GREEN}✓${NC} Tailscale hostname: ${TAILSCALE_HOSTNAME}"

# Check if we can resolve it locally
if [ "$TAILSCALE_AVAILABLE" = "true" ]; then
  echo ""
  echo -e "${BLUE}Step 3: Checking Tailscale connectivity...${NC}"

  if tailscale status | grep -q "${TAILSCALE_HOSTNAME}"; then
    TS_IP=$(tailscale status | grep "${TAILSCALE_HOSTNAME}" | awk '{print $1}')
    echo -e "${GREEN}✓${NC} Device found in Tailscale network: ${TS_IP}"
  else
    echo -e "${YELLOW}⚠️  Device not visible in local Tailscale network${NC}"
    echo "This is normal if you're generating access for a different machine"
  fi
fi

echo ""
echo -e "${BLUE}Step 4: Creating service account and token...${NC}"

NAMESPACE="tailscale"
SERVICE_ACCOUNT="headlamp-remote"

# Create service account
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
kubectl create serviceaccount ${SERVICE_ACCOUNT} -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# Create or update ClusterRoleBinding
cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SERVICE_ACCOUNT}-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${SERVICE_ACCOUNT}
  namespace: ${NAMESPACE}
EOF

echo -e "${GREEN}✓${NC} Service account created: ${SERVICE_ACCOUNT}"

# Create long-lived token
TOKEN=$(kubectl create token ${SERVICE_ACCOUNT} -n ${NAMESPACE} --duration=87600h 2>/dev/null)
echo -e "${GREEN}✓${NC} Token generated (valid for 10 years)"

# Get cluster CA
CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

echo ""
echo -e "${BLUE}Step 5: Generating kubeconfig...${NC}"

# Determine server URL
if [ "$USE_HTTPS" = "true" ]; then
  SERVER_URL="https://${TAILSCALE_HOSTNAME}:${API_PORT}"
else
  SERVER_URL="http://${TAILSCALE_HOSTNAME}:${API_PORT}"
fi

# Create kubeconfig
KUBECONFIG_FILE="${HOME}/kubeconfig-tailscale-remote.yaml"

cat > "${KUBECONFIG_FILE}" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
$(if [ "$USE_HTTPS" = "true" ]; then
  echo "    certificate-authority-data: ${CA_CERT}"
  echo "    server: ${SERVER_URL}"
else
  echo "    insecure-skip-tls-verify: true"
  echo "    server: ${SERVER_URL}"
fi)
  name: tailscale-cluster
contexts:
- context:
    cluster: tailscale-cluster
    user: ${SERVICE_ACCOUNT}
  name: tailscale-cluster
current-context: tailscale-cluster
users:
- name: ${SERVICE_ACCOUNT}
  user:
$(if [ "$USE_HTTPS" = "true" ]; then
  echo "    token: ${TOKEN}"
else
  echo "    {}"
fi)
EOF

echo -e "${GREEN}✓${NC} Kubeconfig saved to: ${KUBECONFIG_FILE}"

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}REMOTE MACHINE SETUP INSTRUCTIONS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}1. Install Tailscale on remote machine (if not already installed):${NC}"
echo ""
echo "   curl -fsSL https://tailscale.com/install.sh | sh"
echo "   sudo tailscale up"
echo ""

echo -e "${YELLOW}2. Copy this kubeconfig to your remote machine:${NC}"
echo ""
echo "   # On this machine:"
echo "   cat ${KUBECONFIG_FILE}"
echo ""
echo "   # On remote machine:"
echo "   cat > ~/kubeconfig-k8s.yaml <<'EOFCONFIG'"
cat "${KUBECONFIG_FILE}"
echo "   EOFCONFIG"
echo ""

echo -e "${YELLOW}3. Test connection on remote machine:${NC}"
echo ""
echo -e "   ${GREEN}export KUBECONFIG=~/kubeconfig-k8s.yaml${NC}"
echo -e "   ${GREEN}kubectl get nodes${NC}"
echo ""

echo -e "${YELLOW}4. For Headlamp Desktop on remote machine:${NC}"
echo ""
echo "   - Open Headlamp Desktop"
echo "   - Click '+' or 'Add Cluster'"
echo "   - Select 'From Kubeconfig'"
echo "   - Browse to ~/kubeconfig-k8s.yaml"
echo "   - Click 'Add'"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}One-liner for remote machine (after Tailscale is running):${NC}"
echo ""
echo -e "${GREEN}export KUBECONFIG=~/kubeconfig-k8s.yaml && kubectl get nodes${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}Connection Details:${NC}"
echo "  Server: ${SERVER_URL}"
echo "  Tailscale Device: ${TAILSCALE_HOSTNAME}"
echo "  Auth Method: $([ "$USE_HTTPS" = "true" ] && echo "Service Account Token" || echo "Proxy (no auth)")"
echo ""

# Save connection info to a file
INFO_FILE="${HOME}/tailscale-remote-access-info.txt"
cat > "${INFO_FILE}" <<EOF
Tailscale Kubernetes Remote Access Information
Generated: $(date)

Server URL: ${SERVER_URL}
Tailscale Hostname: ${TAILSCALE_HOSTNAME}
Authentication: $([ "$USE_HTTPS" = "true" ] && echo "Token-based" || echo "Proxy-based")
Kubeconfig Location: ${KUBECONFIG_FILE}

Remote Machine Setup:
1. Install Tailscale: curl -fsSL https://tailscale.com/install.sh | sh
2. Start Tailscale: sudo tailscale up
3. Copy kubeconfig from: ${KUBECONFIG_FILE}
4. Test: export KUBECONFIG=~/kubeconfig-k8s.yaml && kubectl get nodes

Troubleshooting:
- Verify Tailscale: tailscale status | grep ${TAILSCALE_HOSTNAME}
- Check connectivity: tailscale ping ${TAILSCALE_HOSTNAME}
- Test API: curl -k ${SERVER_URL}/healthz
EOF

echo -e "${GREEN}📄 Connection info saved to: ${INFO_FILE}${NC}"
echo ""
