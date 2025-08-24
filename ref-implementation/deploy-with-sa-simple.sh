#!/bin/bash
set -e

echo "========================================="
echo "Kind Cluster Deployment with Custom SA Keys"
echo "========================================="

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "localdev"; then
    echo "Cluster 'localdev' already exists. Delete it first with: kind delete cluster --name localdev"
    exit 1
fi

# Set the paths directly
SERVICE_ACCOUNT_KEY_FILE="/home/vpittamp/stacks/ref-implementation/keys/sa.pub"
SERVICE_ACCOUNT_SIGNING_KEY_FILE="/home/vpittamp/stacks/ref-implementation/keys/sa.key"
SERVICE_ACCOUNT_ISSUER="https://oidcissuer65846b7df97b.z13.web.core.windows.net/"

# Verify files exist
if [ ! -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
    echo "ERROR: Service account public key not found at $SERVICE_ACCOUNT_KEY_FILE"
    exit 1
fi

if [ ! -f "$SERVICE_ACCOUNT_SIGNING_KEY_FILE" ]; then
    echo "ERROR: Service account private key not found at $SERVICE_ACCOUNT_SIGNING_KEY_FILE"
    exit 1
fi

echo "Using SA keys from:"
echo "  Public: $SERVICE_ACCOUNT_KEY_FILE"
echo "  Private: $SERVICE_ACCOUNT_SIGNING_KEY_FILE"
echo "  Issuer: $SERVICE_ACCOUNT_ISSUER"

# Create the Kind config directly with substituted values
cat > /home/vpittamp/stacks/ref-implementation/kind-config-generated.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."gitea.cnoe.localtest.me:8443"]
    endpoint = ["https://gitea.cnoe.localtest.me"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs."gitea.cnoe.localtest.me".tls]
    insecure_skip_verify = true
nodes:
- role: control-plane
  image: "kindest/node:v1.31.4"
  labels:
    ingress-ready: "true"
  extraPortMappings:
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
  - containerPort: 32222
    hostPort: 32222
    protocol: TCP
  extraMounts:
    - hostPath: $SERVICE_ACCOUNT_KEY_FILE
      containerPath: /etc/kubernetes/pki/sa.pub
      readOnly: true
    - hostPath: $SERVICE_ACCOUNT_SIGNING_KEY_FILE
      containerPath: /etc/kubernetes/pki/sa.key
      readOnly: true
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraArgs:
        service-account-issuer: "$SERVICE_ACCOUNT_ISSUER"
        service-account-key-file: /etc/kubernetes/pki/sa.pub
        service-account-signing-key-file: /etc/kubernetes/pki/sa.key
    controllerManager:
      extraArgs:
        service-account-private-key-file: /etc/kubernetes/pki/sa.key
EOF

echo ""
echo "Generated configuration saved to: kind-config-generated.yaml"
echo ""

# Create the cluster with idpbuilder
echo "Creating Kind cluster with idpbuilder..."
echo ""

idpbuilder create \
    -p /home/vpittamp/stacks/ref-implementation/ \
    -p /home/vpittamp/stacks/cdk8s/dist/ \
    --kind-config /home/vpittamp/stacks/ref-implementation/kind-config-generated.yaml

# Check if cluster was created successfully
if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "Cluster created successfully!"
    echo "========================================="
    
    # Verify the SA keys are mounted
    echo ""
    echo "Verifying SA key mounts..."
    docker exec localdev-control-plane ls -la /etc/kubernetes/pki/sa.* 2>/dev/null || echo "Unable to verify SA keys in container"
    
    # Check API server configuration
    echo ""
    echo "Checking API server configuration..."
    kubectl get pod -n kube-system -l component=kube-apiserver -o yaml 2>/dev/null | grep -E "service-account" | head -5 || echo "Unable to check API server configuration"
    
    echo ""
    echo "Access ArgoCD at: https://argocd.cnoe.localtest.me:8443/"
    echo "Get ArgoCD password: idpbuilder get secrets -p argocd"
else
    echo ""
    echo "ERROR: Cluster creation failed!"
    echo "Check the logs above for details."
    exit 1
fi