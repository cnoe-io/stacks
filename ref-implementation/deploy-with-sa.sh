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

# Source the environment variables
echo "Loading environment variables..."
source /home/vpittamp/stacks/ref-implementation/set-sa-env.sh

# Check if envsubst is available
if ! command -v envsubst &> /dev/null; then
    echo "ERROR: envsubst command not found. Installing gettext-base..."
    sudo apt-get update && sudo apt-get install -y gettext-base
fi

# Generate the final Kind config from template
echo "Generating Kind configuration from template..."
envsubst < /home/vpittamp/stacks/ref-implementation/kind-config-template.yaml > /home/vpittamp/stacks/ref-implementation/kind-config-generated.yaml

echo "Generated configuration saved to: kind-config-generated.yaml"
echo ""
echo "Configuration preview:"
echo "----------------------------------------"
grep -E "(service-account|extraMounts)" /home/vpittamp/stacks/ref-implementation/kind-config-generated.yaml | head -20
echo "----------------------------------------"
echo ""

# Create the cluster with idpbuilder
echo "Creating Kind cluster with idpbuilder..."
echo "Command: idpbuilder create -p /home/vpittamp/stacks/ref-implementation/ -p /home/vpittamp/stacks/cdk8s/dist/ --kind-config /home/vpittamp/stacks/ref-implementation/kind-config-generated.yaml"
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