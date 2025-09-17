#!/usr/bin/env bash
# This script updates ArgoCD's TLS certificates ConfigMap with the static certificate

CERT_FILE="/home/vpittamp/stacks/certificates/tls.crt"

if [ ! -f "$CERT_FILE" ]; then
  echo "Error: Certificate file not found at $CERT_FILE"
  exit 1
fi

echo "Updating ArgoCD TLS certificates ConfigMap..."

# Create the ConfigMap with both domain entries
kubectl create configmap argocd-tls-certs-cm \
  -n argocd \
  --from-file=cnoe.localtest.me="$CERT_FILE" \
  --from-file=gitea.cnoe.localtest.me="$CERT_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ConfigMap updated. Restarting ArgoCD components..."

# Restart ArgoCD components to reload certificates
kubectl rollout restart deployment -n argocd argocd-server argocd-repo-server argocd-applicationset-controller

echo "Waiting for rollout to complete..."
kubectl rollout status deployment -n argocd argocd-repo-server --timeout=60s

echo "Done! ArgoCD should now trust the static certificate."
