#!/bin/bash

set -e

echo "🔄 Recreating idpbuilder with latest GitHub changes..."

# Destroy existing cluster
echo "🗑️  Destroying existing cluster..."
kind delete cluster --name localdev || echo "Cluster doesn't exist or already deleted"

# Wait a moment for cleanup
sleep 5

# Recreate with latest packages
echo "🚀 Creating new cluster with latest packages..."
idpbuilder create \
  --use-path-routing \
  --package https://github.com/cnoe-io/stacks//ref-implementation \
  --package https://github.com/sriaradhyula/stacks//caipe/base \
  --package https://github.com/sriaradhyula/stacks//caipe/complete

echo "✅ Cluster recreated successfully!"
echo "🌐 ArgoCD: https://cnoe.localtest.me:8443/argocd"
echo "🏠 Backstage: https://cnoe.localtest.me:8443/backstage"
echo "🤖 AI Platform: https://cnoe.localtest.me:8443/ai-platform-engineering"
