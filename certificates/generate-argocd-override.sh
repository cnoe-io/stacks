#!/usr/bin/env bash
# Script to generate ArgoCD override file with static certificate for TLS trust

CERT_DIR="$(dirname "$0")"
CERT_FILE="$CERT_DIR/tls.crt"
OUTPUT_FILE="$CERT_DIR/argocd-override.yaml"

if [ ! -f "$CERT_FILE" ]; then
  echo "Error: Certificate file not found at $CERT_FILE"
  exit 1
fi

echo "Generating ArgoCD override file..."

# Read the certificate and indent it for YAML
CERT_CONTENT=$(cat "$CERT_FILE" | sed 's/^/    /')

cat > "$OUTPUT_FILE" <<EOF
---
# ConfigMap with TLS certificates for ArgoCD to trust
# This allows ArgoCD to connect to Gitea repositories over HTTPS
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-tls-certs-cm
  namespace: argocd
data:
  cnoe.localtest.me: |
$CERT_CONTENT
  gitea.cnoe.localtest.me: |
$CERT_CONTENT
EOF

echo "ArgoCD override file generated at $OUTPUT_FILE"
