#!/usr/bin/env bash
#
# setup-persistent-certs.sh - One-time setup for persistent TLS certificates and Attic signing keys
#
# This script generates:
#   1. Long-lived TLS certificate (10 years) for *.cnoe.localtest.me
#   2. Attic Ed25519 signing keypair for cache signature verification
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
#   - nix available for attic keypair generation
#

set -euo pipefail

# Configuration
VAULT_NAME="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
CERT_VALIDITY_DAYS=3650  # 10 years
CERT_DOMAIN="cnoe.localtest.me"
CACHE_NAME="backstage"

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
            echo "Generates persistent TLS certificates and Attic signing keys,"
            echo "then uploads them to Azure Key Vault."
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
# STEP 1: Generate TLS Certificate
# =============================================================================

log_info "Generating TLS certificate for *.$CERT_DOMAIN (valid for $CERT_VALIDITY_DAYS days)..."

# Generate private key
openssl genrsa -out "$TMPDIR/tls.key" 4096

# Generate self-signed certificate with SANs
cat > "$TMPDIR/cert.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = California
L = San Francisco
O = CNOE Local Development
OU = Platform Engineering
CN = *.$CERT_DOMAIN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CERT_DOMAIN
DNS.2 = *.$CERT_DOMAIN
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

openssl req -x509 -new \
    -key "$TMPDIR/tls.key" \
    -out "$TMPDIR/tls.crt" \
    -days "$CERT_VALIDITY_DAYS" \
    -config "$TMPDIR/cert.conf" \
    -sha256

# For self-signed certs, the CA is the cert itself
cp "$TMPDIR/tls.crt" "$TMPDIR/ca.crt"

# Display certificate info
log_success "TLS certificate generated:"
openssl x509 -in "$TMPDIR/tls.crt" -noout -subject -dates -fingerprint | sed 's/^/  /'

# =============================================================================
# STEP 2: Generate Attic Signing Keypair
# =============================================================================

log_info "Generating Attic Ed25519 signing keypair..."

# Try to use attic CLI if available, otherwise use openssl
if command -v attic &>/dev/null; then
    # Use attic gen-keypair for correct format
    cd "$TMPDIR"
    attic gen-keypair "$CACHE_NAME"

    # Extract the key parts
    ATTIC_PRIVATE_KEY=$(cat "$CACHE_NAME")
    ATTIC_PUBLIC_KEY=$(cat "${CACHE_NAME}.pub")
else
    log_warning "attic CLI not found, generating Ed25519 keypair with openssl"

    # Generate Ed25519 keypair
    openssl genpkey -algorithm Ed25519 -out "$TMPDIR/attic-signing.key"
    openssl pkey -in "$TMPDIR/attic-signing.key" -pubout -out "$TMPDIR/attic-signing.pub"

    # Extract raw key bytes and encode
    # Note: This may need adjustment to match exact attic format
    PRIVATE_KEY_B64=$(openssl pkey -in "$TMPDIR/attic-signing.key" -outform DER 2>/dev/null | tail -c 32 | base64 -w0)
    PUBLIC_KEY_B64=$(openssl pkey -in "$TMPDIR/attic-signing.key" -pubout -outform DER 2>/dev/null | tail -c 32 | base64 -w0)

    ATTIC_PRIVATE_KEY="secretkey:${PRIVATE_KEY_B64}"
    ATTIC_PUBLIC_KEY="${CACHE_NAME}:${PUBLIC_KEY_B64}"
fi

log_success "Attic signing keypair generated"
log_info "  Public key: ${ATTIC_PUBLIC_KEY:0:50}..."

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

# Upload Attic signing keypair
ATTIC_PRIVATE_B64=$(echo -n "$ATTIC_PRIVATE_KEY" | base64 -w0)
az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "ATTIC-SIGNING-PRIVATE-KEY" \
    --value "$ATTIC_PRIVATE_B64" \
    --description "Attic cache signing private key (base64 encoded)" \
    --output none

log_success "Uploaded ATTIC-SIGNING-PRIVATE-KEY"

az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "ATTIC-SIGNING-PUBLIC-KEY" \
    --value "$ATTIC_PUBLIC_KEY" \
    --description "Attic cache signing public key (backstage:BASE64 format)" \
    --output none

log_success "Uploaded ATTIC-SIGNING-PUBLIC-KEY"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Persistent certificates and keys uploaded to Azure Key Vault"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Secrets created in $VAULT_NAME:"
echo "  - IDPBUILDER-TLS-CRT       (TLS certificate, valid until $(date -d "+$CERT_VALIDITY_DAYS days" +%Y-%m-%d))"
echo "  - IDPBUILDER-TLS-KEY       (TLS private key)"
echo "  - IDPBUILDER-CA-CRT        (CA certificate)"
echo "  - ATTIC-SIGNING-PRIVATE-KEY (Attic signing key)"
echo "  - ATTIC-SIGNING-PUBLIC-KEY  (Attic verification key)"
echo ""
echo "Certificate fingerprint:"
openssl x509 -in "$TMPDIR/tls.crt" -noout -fingerprint -sha256 | sed 's/^/  /'
echo ""
echo "Attic public key (add to NixOS config once):"
echo "  $ATTIC_PUBLIC_KEY"
echo ""
echo "Next steps:"
echo "  1. Add Attic public key to nixos-config/configurations/base.nix"
echo "  2. Run: sudo nixos-rebuild switch --flake ."
echo "  3. Run cluster-recreate to use persistent certificates"
echo ""
