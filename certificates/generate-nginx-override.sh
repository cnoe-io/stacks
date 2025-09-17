#!/usr/bin/env bash
# Generate nginx override file with static certificates for IDPBuilder

CERT_DIR="$HOME/stacks/certificates"
OUTPUT_FILE="$CERT_DIR/nginx-override.yaml"

# Ensure certificates exist
if [ ! -f "$CERT_DIR/tls.crt" ] || [ ! -f "$CERT_DIR/tls.key" ]; then
  echo "Error: tls.crt or tls.key not found in $CERT_DIR"
  exit 1
fi

echo "Generating nginx override file..."

# Generate the override file with the ingress-nginx certificate
cat > "$OUTPUT_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: idpbuilder-cert
  namespace: ingress-nginx
type: kubernetes.io/tls
data:
  tls.crt: $(base64 -w 0 < "$CERT_DIR/tls.crt")
  tls.key: $(base64 -w 0 < "$CERT_DIR/tls.key")
EOF

echo "Generated nginx override at: $OUTPUT_FILE"

# Also generate the default namespace certificate
DEFAULT_OUTPUT="$CERT_DIR/default-cert.yaml"
cat > "$DEFAULT_OUTPUT" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: idpbuilder-cert
  namespace: default
type: Opaque
data:
  ca.crt: $(base64 -w 0 < "$CERT_DIR/ca.crt")
EOF

echo "Generated default namespace certificate at: $DEFAULT_OUTPUT"
