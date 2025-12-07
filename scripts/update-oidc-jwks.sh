#!/usr/bin/env bash
# update-oidc-jwks.sh - Update JWKS in Azure storage when cluster changes
set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT is one level up from scripts/
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
WI_ENV="${PROJECT_ROOT}/.env-files/wi.env"

# Source the environment file if it exists
if [[ -f "$WI_ENV" ]]; then
    set -a
    source "$WI_ENV"
    set +a
fi

log() { printf '[%(%T)T] %s\n' -1 "$*"; }

# Check prerequisites
if [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
    log "❌ AZURE_STORAGE_ACCOUNT not set. Run azure-infra setup first."
    exit 1
fi

if [[ -z "${SERVICE_ACCOUNT_ISSUER:-}" ]]; then
    log "❌ SERVICE_ACCOUNT_ISSUER not set. Run azure-infra setup first."
    exit 1
fi

# Fetch current cluster's JWKS
log "🔑 Fetching JWKS from current Kubernetes cluster..."
TEMP_JWKS=$(mktemp)
trap 'rm -f "$TEMP_JWKS"' EXIT

if kubectl get --raw /openid/v1/jwks 2>/dev/null | jq -c . >"$TEMP_JWKS"; then
    log "✅ Successfully fetched JWKS from cluster"
    
    # Upload to Azure storage
    log "📤 Uploading JWKS to Azure storage account '$AZURE_STORAGE_ACCOUNT'..."
    
    if az storage blob upload \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --container-name "\$web" \
        --name "openid/v1/jwks" \
        --file "$TEMP_JWKS" \
        --content-type "application/json" \
        --overwrite \
        --auth-mode login \
        -o none; then
        log "✅ JWKS successfully updated in Azure storage"
        log "   Issuer: $SERVICE_ACCOUNT_ISSUER"
        log "   JWKS URL: ${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks"
    else
        log "❌ Failed to upload JWKS to Azure storage"
        exit 1
    fi
else
    log "❌ Failed to fetch JWKS from cluster. Ensure:"
    log "   - kubectl is configured correctly"
    log "   - The cluster API server is accessible"
    log "   - The cluster has OIDC enabled"
    exit 1
fi