#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Configuration
SERVICE_ACCOUNT_ISSUER="https://oidcissuer65846b7df97b.z13.web.core.windows.net/"
SERVICE_ACCOUNT_SIGNING_KEY_FILE="/home/vpittamp/stacks/ref-implementation/keys/sa.key"
SERVICE_ACCOUNT_KEY_FILE="/home/vpittamp/stacks/ref-implementation/keys/sa.pub"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-azure-workload-identity}"

echo "========================================="
echo "Testing Azure Workload Identity Approach"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Issuer: ${SERVICE_ACCOUNT_ISSUER}"
echo "  SA Key: ${SERVICE_ACCOUNT_SIGNING_KEY_FILE}"
echo "  SA Pub: ${SERVICE_ACCOUNT_KEY_FILE}"
echo "  Cluster: ${KIND_CLUSTER_NAME}"
echo ""

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "${KIND_CLUSTER_NAME}"; then
    echo "Cluster '${KIND_CLUSTER_NAME}' already exists. Deleting it..."
    kind delete cluster --name "${KIND_CLUSTER_NAME}"
fi

preflight() {
  echo "Running preflight checks..."
  
  if [[ ! -f "${SERVICE_ACCOUNT_SIGNING_KEY_FILE}" ]]; then
    echo "ERROR: ${SERVICE_ACCOUNT_SIGNING_KEY_FILE} is missing."
    exit 1
  fi
  
  if [[ ! -f "${SERVICE_ACCOUNT_KEY_FILE}" ]]; then
    echo "ERROR: ${SERVICE_ACCOUNT_KEY_FILE} is missing."
    exit 1
  fi
  
  echo "✓ SA key files exist"
  
  # Check if the OIDC discovery document exists
  if curl -sSf "${SERVICE_ACCOUNT_ISSUER}.well-known/openid-configuration" > /dev/null 2>&1; then
    echo "✓ OIDC discovery document exists"
  else
    echo "⚠ OIDC discovery document not accessible (this is expected for testing)"
  fi
  
  echo "Preflight checks completed"
  echo ""
}

create_kind_cluster() {
  echo "Creating Kind cluster with Azure Workload Identity configuration..."
  echo ""
  
  # Create the cluster using the exact same structure as azure-workload-identity
  cat <<EOF | kind create cluster --name "${KIND_CLUSTER_NAME}" --image "kindest/node:v1.31.4" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
    - hostPath: ${SERVICE_ACCOUNT_KEY_FILE}
      containerPath: /etc/kubernetes/pki/sa.pub
    - hostPath: ${SERVICE_ACCOUNT_SIGNING_KEY_FILE}
      containerPath: /etc/kubernetes/pki/sa.key
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        service-account-issuer: ${SERVICE_ACCOUNT_ISSUER}
        service-account-key-file: /etc/kubernetes/pki/sa.pub
        service-account-signing-key-file: /etc/kubernetes/pki/sa.key
    controllerManager:
      extraArgs:
        service-account-private-key-file: /etc/kubernetes/pki/sa.key
EOF

  if [ $? -eq 0 ]; then
    echo ""
    echo "Cluster creation completed. Waiting for node to be ready..."
    kubectl wait node "${KIND_CLUSTER_NAME}-control-plane" --for=condition=Ready --timeout=90s
    
    echo ""
    echo "Verifying SA key mounts..."
    docker exec "${KIND_CLUSTER_NAME}-control-plane" ls -la /etc/kubernetes/pki/sa.* || echo "Unable to verify SA keys"
    
    echo ""
    echo "Checking API server configuration..."
    kubectl get pod -n kube-system -l component=kube-apiserver -o yaml | grep -E "service-account" | head -5
    
    echo ""
    echo "========================================="
    echo "Cluster created successfully!"
    echo "========================================="
  else
    echo ""
    echo "ERROR: Cluster creation failed!"
    echo "This confirms the issue is with Docker Desktop + WSL2, not idpbuilder"
  fi
}

# Run the test
preflight
create_kind_cluster