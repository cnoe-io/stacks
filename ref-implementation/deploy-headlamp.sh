#!/usr/bin/env bash
# Deploy Headlamp with External Secrets support

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   Deploying Headlamp with External Secrets Support${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please ensure you have a Kubernetes cluster running.${NC}"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

# Step 1: Create namespace
echo -e "${GREEN}Creating headlamp namespace...${NC}"
kubectl create namespace headlamp --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Apply RBAC for External Secrets
echo -e "${GREEN}Applying RBAC configuration for External Secrets...${NC}"
kubectl apply -f "${SCRIPT_DIR}/headlamp-external-secrets-rbac.yaml"

# Step 3: Check if Helm is installed
if command -v helm &> /dev/null; then
    echo -e "${GREEN}Installing Headlamp using Helm...${NC}"
    
    # Add Helm repo
    helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
    helm repo update
    
    # Install or upgrade Headlamp with custom values
    if [ -f "${SCRIPT_DIR}/headlamp-config.yaml" ]; then
        helm upgrade --install headlamp headlamp/headlamp \
            --namespace headlamp \
            --values "${SCRIPT_DIR}/headlamp-config.yaml" \
            --wait
    else
        helm upgrade --install headlamp headlamp/headlamp \
            --namespace headlamp \
            --set ingress.enabled=true \
            --set ingress.hosts[0].host=headlamp.cnoe.localtest.me \
            --set ingress.hosts[0].paths[0].path=/ \
            --set ingress.hosts[0].paths[0].pathType=Prefix \
            --wait
    fi
else
    echo -e "${YELLOW}Helm not found. Installing using kubectl...${NC}"
    
    # Download and apply the manifest
    curl -s https://raw.githubusercontent.com/kubernetes-sigs/headlamp/main/kubernetes-headlamp.yaml | \
        sed 's/namespace: kube-system/namespace: headlamp/g' | \
        kubectl apply -n headlamp -f -
    
    # Apply custom ingress
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: headlamp.cnoe.localtest.me
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: headlamp
            port:
              number: 80
  tls:
  - hosts:
    - headlamp.cnoe.localtest.me
    secretName: headlamp-tls
EOF
fi

# Step 4: Wait for deployment
echo -e "${GREEN}Waiting for Headlamp deployment...${NC}"
kubectl rollout status deployment -n headlamp --timeout=300s 2>/dev/null || \
    kubectl rollout status deployment headlamp -n headlamp --timeout=300s

# Step 5: Get service token (for in-cluster access)
echo -e "${GREEN}Creating service account token...${NC}"
SECRET_NAME="headlamp-token"
kubectl create token headlamp -n headlamp --duration=87600h > /tmp/headlamp-token 2>/dev/null || true

# Step 6: Check External Secrets CRDs
echo -e "${GREEN}Checking External Secrets CRDs...${NC}"
if kubectl get crd externalsecrets.external-secrets.io &>/dev/null; then
    echo -e "${GREEN}✓ External Secrets CRDs found${NC}"
    
    # List External Secrets resources
    echo ""
    echo -e "${BLUE}External Secrets Resources:${NC}"
    kubectl get externalsecrets --all-namespaces 2>/dev/null | head -10 || echo "  No ExternalSecrets found"
    kubectl get secretstores --all-namespaces 2>/dev/null | head -10 || echo "  No SecretStores found"
    kubectl get clustersecretstores 2>/dev/null | head -10 || echo "  No ClusterSecretStores found"
else
    echo -e "${YELLOW}⚠ External Secrets CRDs not found. ESO may not be installed yet.${NC}"
fi

# Step 7: Show access information
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Headlamp deployed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Access Headlamp:${NC}"
echo "  URL: https://headlamp.cnoe.localtest.me:8443"
echo ""
echo -e "${BLUE}Desktop App:${NC}"
echo "  Run: headlamp"
echo "  It will use your local kubeconfig"
echo ""
echo -e "${BLUE}In-cluster Access:${NC}"
if [ -f /tmp/headlamp-token ]; then
    echo "  Token saved to: /tmp/headlamp-token"
    echo "  Use this token to login to the web interface"
fi
echo ""
echo -e "${BLUE}View External Secrets in Headlamp:${NC}"
echo "  1. Navigate to 'Custom Resources' in the left menu"
echo "  2. Look for 'external-secrets.io' group"
echo "  3. You'll see:"
echo "     - ExternalSecrets"
echo "     - SecretStores"
echo "     - ClusterSecretStores"
echo "     - PushSecrets"
echo ""
echo -e "${BLUE}Installed Plugins:${NC}"
echo "  - Prometheus metrics"
echo "  - OpenCost (cost analysis)"
echo "  - Cert-Manager"
echo "  - Flux"
echo ""
echo -e "${YELLOW}Note: External Secrets will appear as Custom Resources in Headlamp.${NC}"
echo -e "${YELLOW}The UI provides native support for viewing and managing CRDs.${NC}"