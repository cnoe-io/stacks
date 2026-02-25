#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "🚀 Bootstrapping local infrastructure..."

# Wait for nodes to be ready
echo "⏳ Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Add repos
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update

# Install NGINX Ingress
echo "🌐 Installing NGINX Ingress..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.10.1 \
  -f "${STACKS_DIR}/deployment/config/nginx-values.yaml" \
  --wait

# Install Gitea
echo "📦 Installing Gitea..."
helm upgrade --install gitea gitea-charts/gitea \
  --namespace gitea \
  --create-namespace \
  -f "${STACKS_DIR}/deployment/config/gitea-values.yaml" \
  --wait

# Create gitea-credential secret to mimic gitops behavior
echo "🔐 Creating gitea-credential secret..."
kubectl create secret generic gitea-credential \
  --namespace gitea \
  --from-literal=username=giteaadmin \
  --from-literal=password=developer \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Local infrastructure bootstrapped successfully."

