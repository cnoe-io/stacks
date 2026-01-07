#!/usr/bin/env bash
#
# setup-persistent-certs.sh - One-time setup for persistent TLS certificates
#
# This script generates:
#   1. Long-lived TLS certificate (10 years) for *.cnoe.localtest.me
#
# All secrets are uploaded to Azure Key Vault for retrieval during cluster creation.
#
# Usage:
#   ./setup-persistent-certs.sh [--force]
#
# Options:
#   --force    Overwrite existing secrets in Azure Key Vault
#
# Prerequisites:
#   - Azure CLI authenticated: az login
#

set -euo pipefail

# Configuration
VAULT_NAME="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
CERT_VALIDITY_DAYS=3650  # 10 years
CERT_DOMAIN="cnoe.localtest.me"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}i${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✖${NC} $*" >&2; }

FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Generates persistent TLS certificates and uploads them to Azure Key Vault."
            echo ""
            echo "Options:"
            echo "  --force    Overwrite existing secrets in Azure Key Vault"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
command -v az &>/dev/null || { log_error "Azure CLI (az) not found"; exit 1; }
command -v openssl &>/dev/null || { log_error "OpenSSL not found"; exit 1; }

# Verify Azure authentication
if ! az account show &>/dev/null; then
    log_error "Not authenticated to Azure. Run: az login"
    exit 1
fi

log_info "Using Azure Key Vault: $VAULT_NAME"

# Check if secrets already exist
check_secret_exists() {
    local name="$1"
    az keyvault secret show --vault-name "$VAULT_NAME" --name "$name" &>/dev/null
}

if ! $FORCE; then
    if check_secret_exists "IDPBUILDER-TLS-CRT"; then
        log_warning "Persistent TLS certificate already exists in Key Vault"
        log_warning "Use --force to overwrite"
        exit 0
    fi
fi

# Create temp directory for cert generation
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

log_info "Generating certificates in $TMPDIR"

# =============================================================================
# STEP 1: Generate CA Certificate
# =============================================================================

log_info "Generating CA certificate (valid for $CERT_VALIDITY_DAYS days)..."

# Generate CA private key
openssl genrsa -out "$TMPDIR/ca.key" 4096

# Generate CA certificate config
cat > "$TMPDIR/ca.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = US
ST = California
L = San Francisco
O = CNOE Local Development
OU = Platform Engineering
CN = CNOE Local Development CA

[v3_ca]
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
EOF

# Generate self-signed CA certificate
openssl req -x509 -new -nodes \
    -key "$TMPDIR/ca.key" \
    -out "$TMPDIR/ca.crt" \
    -days "$CERT_VALIDITY_DAYS" \
    -config "$TMPDIR/ca.conf" \
    -sha256

log_success "CA certificate generated"

# =============================================================================
# STEP 2: Generate Server Certificate signed by CA
# =============================================================================

log_info "Generating server certificate for *.$CERT_DOMAIN..."

# Generate server private key
openssl genrsa -out "$TMPDIR/tls.key" 4096

# Generate server certificate config
cat > "$TMPDIR/server.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = California
L = San Francisco
O = CNOE Local Development
OU = Platform Engineering
CN = *.$CERT_DOMAIN

[v3_req]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CERT_DOMAIN
DNS.2 = *.$CERT_DOMAIN
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

# Generate server CSR
openssl req -new \
    -key "$TMPDIR/tls.key" \
    -out "$TMPDIR/server.csr" \
    -config "$TMPDIR/server.conf"

# Sign server certificate with CA
cat > "$TMPDIR/server_ext.conf" <<EOF
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:$CERT_DOMAIN, DNS:*.$CERT_DOMAIN, DNS:localhost, IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid, issuer
EOF

openssl x509 -req \
    -in "$TMPDIR/server.csr" \
    -CA "$TMPDIR/ca.crt" \
    -CAkey "$TMPDIR/ca.key" \
    -CAcreateserial \
    -out "$TMPDIR/tls.crt" \
    -days "$CERT_VALIDITY_DAYS" \
    -extfile "$TMPDIR/server_ext.conf" \
    -sha256

# Display certificate info
log_success "Server certificate generated and signed by CA"
echo "  CA Certificate:"
openssl x509 -in "$TMPDIR/ca.crt" -noout -subject | sed 's/^/    /'
echo "  Server Certificate:"
openssl x509 -in "$TMPDIR/tls.crt" -noout -subject -dates | sed 's/^/    /'

# =============================================================================
# STEP 3: Upload to Azure Key Vault
# =============================================================================

log_info "Uploading secrets to Azure Key Vault..."

# Upload TLS certificate (base64 encoded)
TLS_CRT_B64=$(base64 -w0 < "$TMPDIR/tls.crt")
TLS_KEY_B64=$(base64 -w0 < "$TMPDIR/tls.key")
CA_CRT_B64=$(base64 -w0 < "$TMPDIR/ca.crt")

az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "IDPBUILDER-TLS-CRT" \
    --value "$TLS_CRT_B64" \
    --description "Persistent TLS certificate for idpbuilder (base64 PEM)" \
    --output none

log_success "Uploaded IDPBUILDER-TLS-CRT"

az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "IDPBUILDER-TLS-KEY" \
    --value "$TLS_KEY_B64" \
    --description "Persistent TLS private key for idpbuilder (base64 PEM)" \
    --output none

log_success "Uploaded IDPBUILDER-TLS-KEY"

az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "IDPBUILDER-CA-CRT" \
    --value "$CA_CRT_B64" \
    --description "Persistent CA certificate for idpbuilder (base64 PEM)" \
    --output none

log_success "Uploaded IDPBUILDER-CA-CRT"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Persistent certificates uploaded to Azure Key Vault"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Secrets created in $VAULT_NAME:"
echo "  - IDPBUILDER-TLS-CRT       (Server certificate for K8s TLS secrets)"
echo "  - IDPBUILDER-TLS-KEY       (Server private key for K8s TLS secrets)"
echo "  - IDPBUILDER-CA-CRT        (CA certificate for browser trust stores)"
echo ""
echo "Certificate validity: $(date -d "+$CERT_VALIDITY_DAYS days" +%Y-%m-%d)"
echo ""
echo "PKI Structure:"
echo "  CA Certificate (IDPBUILDER-CA-CRT):"
echo "    - Has CA:TRUE (can sign certificates)"
echo "    - Install in browser trust stores (Chrome, Firefox)"
echo ""
echo "  Server Certificate (IDPBUILDER-TLS-CRT):"
echo "    - Has CA:FALSE (end-entity certificate)"
echo "    - Signed by CA certificate"
echo "    - Use in K8s TLS secrets for ingress"
echo ""
echo "Next steps:"
echo "  1. Run cluster-recreate to use persistent certificates"
echo ""
