#!/usr/bin/env bash
#
# migrate-existing-cluster.sh - Migrate existing cluster to persistent certificates
#
# This script extracts current TLS certificate and Attic signing key from a running
# cluster and uploads them to Azure Key Vault for persistent use.
#
# Usage:
#   ./migrate-existing-cluster.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be uploaded without actually uploading
#
# Prerequisites:
#   - kubectl configured to access the cluster
#   - Azure CLI authenticated: az login
#   - Attic cache 'backstage' exists and is operational
#

set -euo pipefail

# Configuration
VAULT_NAME="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
CERT_SECRET_NAME="${CERT_SECRET_NAME:-idpbuilder-cert}"
CERT_NAMESPACE="${CERT_NAMESPACE:-ingress-nginx}"
ATTIC_NAMESPACE="nix-cache"
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

DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run]"
            echo ""
            echo "Migrates existing cluster certificates to Azure Key Vault for persistence."
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be uploaded without actually uploading"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
command -v kubectl &>/dev/null || { log_error "kubectl not found"; exit 1; }
command -v az &>/dev/null || { log_error "Azure CLI (az) not found"; exit 1; }
command -v openssl &>/dev/null || { log_error "OpenSSL not found"; exit 1; }

# Verify Azure authentication
if ! az account show &>/dev/null; then
    log_error "Not authenticated to Azure. Run: az login"
    exit 1
fi

# Verify cluster access
if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot access Kubernetes cluster. Check kubectl configuration."
    exit 1
fi

log_info "Migrating existing cluster to persistent certificates"
log_info "Azure Key Vault: $VAULT_NAME"

if $DRY_RUN; then
    log_warning "DRY RUN MODE - no changes will be made"
fi

# Create temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# =============================================================================
# STEP 1: Extract TLS Certificate
# =============================================================================

log_info "Extracting TLS certificate from cluster..."

# Check if secret exists
if ! kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" &>/dev/null; then
    log_error "TLS secret not found: $CERT_SECRET_NAME in $CERT_NAMESPACE"
    exit 1
fi

# Extract certificate
kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TMPDIR/tls.crt"
kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > "$TMPDIR/tls.key"

# Extract CA if present, otherwise use the cert itself (self-signed)
ca_b64=$(kubectl get secret "$CERT_SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
if [ -n "$ca_b64" ]; then
    echo "$ca_b64" | base64 -d > "$TMPDIR/ca.crt"
else
    openssl x509 -in "$TMPDIR/tls.crt" -out "$TMPDIR/ca.crt"
fi

# Display certificate info
log_success "TLS certificate extracted:"
openssl x509 -in "$TMPDIR/tls.crt" -noout -subject -dates -fingerprint | sed 's/^/  /'

# =============================================================================
# STEP 2: Extract Attic Signing Key
# =============================================================================

log_info "Extracting Attic signing key from cluster..."

# Check if Attic pod is running
POD_NAME=$(kubectl get pods -n "$ATTIC_NAMESPACE" -l app=attic -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    log_warning "Attic pod not found - skipping signing key extraction"
    ATTIC_PUBLIC_KEY=""
else
    # Get the public key from the cache
    ATTIC_PUBLIC_KEY=$(kubectl exec -n "$ATTIC_NAMESPACE" "$POD_NAME" -- sh -c "
        TOKEN=\$(atticadm -f /etc/attic/server.toml make-token --sub migrate --validity 1m --pull $CACHE_NAME 2>/dev/null)
        wget -q -O- --header=\"Authorization: Bearer \$TOKEN\" http://localhost:8080/_api/v1/cache-config/$CACHE_NAME 2>/dev/null
    " 2>/dev/null | grep -o '"public_key":"[^"]*"' | cut -d'"' -f4 || echo "")

    if [ -n "$ATTIC_PUBLIC_KEY" ]; then
        log_success "Attic public key extracted: ${ATTIC_PUBLIC_KEY:0:50}..."

        # Note: We can only extract the public key via API
        # The private key would need to be extracted from the Attic database
        log_warning "Note: Only public key can be extracted via API"
        log_warning "For full keypair, run setup-persistent-certs.sh to generate new keys"
    else
        log_warning "Could not extract Attic public key"
    fi
fi

# =============================================================================
# STEP 3: Upload to Azure Key Vault
# =============================================================================

if $DRY_RUN; then
    echo ""
    log_info "DRY RUN - Would upload the following secrets:"
    echo "  - IDPBUILDER-TLS-CRT (TLS certificate)"
    echo "  - IDPBUILDER-TLS-KEY (TLS private key)"
    echo "  - IDPBUILDER-CA-CRT (CA certificate)"
    if [ -n "$ATTIC_PUBLIC_KEY" ]; then
        echo "  - ATTIC-SIGNING-PUBLIC-KEY (Attic public key)"
    fi
    echo ""
    log_info "Certificate fingerprint:"
    openssl x509 -in "$TMPDIR/tls.crt" -noout -fingerprint -sha256 | sed 's/^/  /'
    exit 0
fi

log_info "Uploading secrets to Azure Key Vault..."

# Upload TLS certificate (base64 encoded)
TLS_CRT_B64=$(base64 -w0 < "$TMPDIR/tls.crt")
TLS_KEY_B64=$(base64 -w0 < "$TMPDIR/tls.key")
CA_CRT_B64=$(base64 -w0 < "$TMPDIR/ca.crt")

az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "IDPBUILDER-TLS-CRT" \
    --value "$TLS_CRT_B64" \
    --description "Migrated TLS certificate from existing cluster (base64 PEM)" \
    --output none

log_success "Uploaded IDPBUILDER-TLS-CRT"

az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "IDPBUILDER-TLS-KEY" \
    --value "$TLS_KEY_B64" \
    --description "Migrated TLS private key from existing cluster (base64 PEM)" \
    --output none

log_success "Uploaded IDPBUILDER-TLS-KEY"

az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "IDPBUILDER-CA-CRT" \
    --value "$CA_CRT_B64" \
    --description "Migrated CA certificate from existing cluster (base64 PEM)" \
    --output none

log_success "Uploaded IDPBUILDER-CA-CRT"

# Upload Attic public key if available
if [ -n "$ATTIC_PUBLIC_KEY" ]; then
    az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "ATTIC-SIGNING-PUBLIC-KEY" \
        --value "$ATTIC_PUBLIC_KEY" \
        --description "Migrated Attic signing public key (backstage:BASE64 format)" \
        --output none

    log_success "Uploaded ATTIC-SIGNING-PUBLIC-KEY"

    log_warning "Note: ATTIC-SIGNING-PRIVATE-KEY not uploaded (not extractable via API)"
    log_warning "For full Attic signing key persistence, run setup-persistent-certs.sh"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Migration complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Secrets uploaded to $VAULT_NAME:"
echo "  - IDPBUILDER-TLS-CRT"
echo "  - IDPBUILDER-TLS-KEY"
echo "  - IDPBUILDER-CA-CRT"
if [ -n "$ATTIC_PUBLIC_KEY" ]; then
    echo "  - ATTIC-SIGNING-PUBLIC-KEY"
fi
echo ""
echo "Certificate fingerprint:"
openssl x509 -in "$TMPDIR/tls.crt" -noout -fingerprint -sha256 | sed 's/^/  /'
echo ""

if [ -z "$ATTIC_PUBLIC_KEY" ] || [ -z "$(az keyvault secret show --vault-name "$VAULT_NAME" --name "ATTIC-SIGNING-PRIVATE-KEY" --query value -o tsv 2>/dev/null || echo "")" ]; then
    echo "Next steps for full Attic signing key persistence:"
    echo "  1. Run: ./setup-persistent-certs.sh"
    echo "     This will generate a new Attic signing keypair"
    echo "  2. Update nixos-config/configurations/base.nix with new public key"
    echo "  3. Run: sudo nixos-rebuild switch --flake ."
else
    echo "Next steps:"
    echo "  1. Run cluster-recreate to test persistent certificates"
    echo "  2. Verify browser trust and Attic cache work without changes"
fi
echo ""
