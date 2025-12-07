#!/usr/bin/env bash
# check-azure-infra.sh - Validate if existing Azure infrastructure meets requirements
set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT is one level up from scripts/
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Determine environment file based on cluster type
if [[ -n "${ENV_FILE:-}" ]]; then
    # Use provided ENV_FILE
    ENV_FILE="$ENV_FILE"
elif [[ "${CLUSTER_TYPE:-}" = "aks" ]]; then
    # For AKS clusters, use production env file
    ENV_FILE="${PROJECT_ROOT}/.env-files/production.env"
else
    # Default to wi.env for KIND clusters
    ENV_FILE="${PROJECT_ROOT}/.env-files/wi.env"
fi

# Source the environment file if it exists
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
    # Handle legacy APP_ID variable
    if [[ -n "${APP_ID:-}" ]] && [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
        export AZURE_CLIENT_ID="$APP_ID"
    fi
fi

# Initialize validation status
INFRA_VALID=true
VALIDATION_MESSAGES=()

log() { printf '[%(%T)T] %s\n' -1 "$*"; }
add_validation_message() { VALIDATION_MESSAGES+=("$1"); }

# Function to check if storage account exists and has OIDC documents
check_storage_account() {
    log "🔍 Checking storage account..."
    
    # Check if we have a storage account name
    if [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
        add_validation_message "❌ No storage account found (AZURE_STORAGE_ACCOUNT not set)"
        INFRA_VALID=false
        return 1
    fi
    
    # Check if storage account follows our naming pattern
    if [[ ! "$AZURE_STORAGE_ACCOUNT" =~ ^oidcissuer[a-f0-9]{12}$ ]]; then
        add_validation_message "⚠️  Storage account '$AZURE_STORAGE_ACCOUNT' doesn't follow expected pattern (oidcissuer[hex])"
        # This is a warning, not a failure - we might be using a custom name
    fi
    
    # Check if storage account exists
    if ! az storage account show -n "$AZURE_STORAGE_ACCOUNT" -g "${RESOURCE_GROUP:-rg4}" --query name -o tsv &>/dev/null; then
        add_validation_message "❌ Storage account '$AZURE_STORAGE_ACCOUNT' not found in resource group '${RESOURCE_GROUP:-rg4}'"
        INFRA_VALID=false
        return 1
    fi
    
    add_validation_message "✅ Storage account '$AZURE_STORAGE_ACCOUNT' exists"
    
    # Check if static website is enabled
    local static_website_enabled
    static_website_enabled=$(az storage blob service-properties show \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --auth-mode login \
        --query staticWebsite.enabled -o tsv 2>/dev/null || echo "false")
    
    if [[ "$static_website_enabled" != "true" ]]; then
        add_validation_message "❌ Static website not enabled on storage account"
        INFRA_VALID=false
        return 1
    fi
    
    add_validation_message "✅ Static website is enabled"
    return 0
}

# Function to check OIDC documents
check_oidc_documents() {
    log "🔍 Checking OIDC documents..."
    
    if [[ -z "${SERVICE_ACCOUNT_ISSUER:-}" ]]; then
        add_validation_message "❌ SERVICE_ACCOUNT_ISSUER not set"
        INFRA_VALID=false
        return 1
    fi
    
    # Check if discovery document is accessible
    local discovery_url="${SERVICE_ACCOUNT_ISSUER}.well-known/openid-configuration"
    if ! curl -sf "$discovery_url" >/dev/null; then
        add_validation_message "❌ OIDC discovery document not accessible at $discovery_url"
        INFRA_VALID=false
        return 1
    fi
    
    add_validation_message "✅ OIDC discovery document is accessible"
    
    # Check if JWKS endpoint is accessible
    local jwks_url="${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks"
    if ! curl -sf "$jwks_url" >/dev/null; then
        add_validation_message "❌ JWKS endpoint not accessible at $jwks_url"
        INFRA_VALID=false
        return 1
    fi
    
    add_validation_message "✅ JWKS endpoint is accessible"
    return 0
}

# Function to check federated credentials in detail
check_federated_credentials_detail() {
    local creds="$1"
    
    # Get list from environment or use defaults
    local sa_configs="${WORKLOAD_IDENTITY_SERVICE_ACCOUNTS:-external-secrets:keyvault kargo:acr-sa mcp-tools:acr-sa}"
    
    # Check each configured service account
    for sa_config in $sa_configs; do
        namespace="${sa_config%%:*}"
        sa_name="${sa_config##*:}"
        subject="system:serviceaccount:${namespace}:${sa_name}"
        
        if echo "$creds" | jq -e ".[] | select(.subject==\"$subject\")" >/dev/null 2>&1; then
            add_validation_message "✅ Federated credential exists: $namespace/$sa_name"
        else
            add_validation_message "⚠️  Missing federated credential: $namespace/$sa_name"
        fi
    done
}

# Function to check Azure AD app and federated credentials
check_azure_ad_app() {
    log "🔍 Checking Azure AD application..."
    
    # Check if we have an AZURE_CLIENT_ID
    if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
        add_validation_message "❌ No Azure AD app found (AZURE_CLIENT_ID not set)"
        INFRA_VALID=false
        return 1
    fi
    
    # Check if app exists
    if ! az ad app show --id "$AZURE_CLIENT_ID" --query appId -o tsv &>/dev/null; then
        add_validation_message "❌ Azure AD app with ID '$AZURE_CLIENT_ID' not found"
        INFRA_VALID=false
        return 1
    fi
    
    add_validation_message "✅ Azure AD app '$AZURE_CLIENT_ID' exists"
    
    # Check if service principal exists
    if ! az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv &>/dev/null; then
        add_validation_message "❌ Service principal for app '$AZURE_CLIENT_ID' not found"
        INFRA_VALID=false
        return 1
    fi
    
    add_validation_message "✅ Service principal exists"
    
    # Check for federated credentials
    local fed_cred_count
    fed_cred_count=$(az ad app federated-credential list --id "$AZURE_CLIENT_ID" --query 'length(@)' -o tsv 2>/dev/null || echo "0")
    
    if [[ "$fed_cred_count" -eq 0 ]]; then
        add_validation_message "⚠️  No federated credentials found for app (will be created during bootstrap)"
        # This is not a failure - federated credentials are created per service account
    else
        add_validation_message "✅ Found $fed_cred_count federated credential(s)"
        
        # Get all federated credentials for detailed checking
        local creds
        creds=$(az ad app federated-credential list --id "$AZURE_CLIENT_ID" --query '[].{name:name, subject:subject, issuer:issuer}' -o json 2>/dev/null || echo "[]")
        
        # Check configured service accounts
        check_federated_credentials_detail "$creds"
        
        # Check if any federated credential matches our issuer
        local matching_issuer
        matching_issuer=$(echo "$creds" | jq -r ".[] | select(.issuer==\"${SERVICE_ACCOUNT_ISSUER%/}\") | .issuer" | head -1)
        
        if [[ -n "$matching_issuer" ]]; then
            add_validation_message "✅ Found federated credential with matching issuer"
        else
            add_validation_message "⚠️  No federated credential matches current issuer (may need update)"
        fi
    fi
    
    return 0
}

# Function to check KeyVault access
check_keyvault_access() {
    log "🔍 Checking KeyVault access..."
    
    if [[ -z "${AZURE_KEYVAULT_NAME:-}" ]]; then
        add_validation_message "ℹ️  No KeyVault configured (AZURE_KEYVAULT_NAME not set)"
        return 0  # This is optional, not a failure
    fi
    
    # Check if KeyVault exists
    local vault_id
    vault_id=$(az keyvault show --name "$AZURE_KEYVAULT_NAME" --query id -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$vault_id" ]]; then
        add_validation_message "⚠️  KeyVault '$AZURE_KEYVAULT_NAME' not found"
        return 0  # Warning, not failure
    fi
    
    # Check if app has access
    local role_assignment
    role_assignment=$(az role assignment list \
        --assignee "$AZURE_CLIENT_ID" \
        --role "Key Vault Secrets User" \
        --scope "$vault_id" \
        --query "[0].id" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$role_assignment" ]]; then
        add_validation_message "✅ App has Key Vault Secrets User role"
    else
        add_validation_message "⚠️  App lacks Key Vault access (will be granted if needed)"
    fi
    
    return 0
}

# Main validation
main() {
    log "════════════════════════════════════════════════════════════════"
    log "🔍 Validating Azure Infrastructure"
    log "════════════════════════════════════════════════════════════════"
    
    # Determine cluster type
    local cluster_type="${CLUSTER:-kind}"
    log "Cluster type: $cluster_type"
    
    # Run checks based on cluster type
    if [[ "$cluster_type" == "kind" ]]; then
        # For KIND clusters, check storage and OIDC setup
        check_storage_account
        check_oidc_documents
    else
        # For AKS clusters, skip storage/OIDC checks
        add_validation_message "ℹ️  Skipping storage account check (AKS uses Azure-managed OIDC)"
        add_validation_message "ℹ️  Skipping OIDC documents check (managed by Azure)"
    fi
    
    # Always check Azure AD app and KeyVault for all cluster types
    check_azure_ad_app
    check_keyvault_access
    
    # Print validation summary
    echo
    log "📋 Validation Summary:"
    for msg in "${VALIDATION_MESSAGES[@]}"; do
        echo "   $msg"
    done
    
    echo
    if [[ "$INFRA_VALID" == "true" ]]; then
        log "✅ Azure infrastructure validation PASSED"
        log "   All requirements are met for Kubernetes workload identity"
        exit 0
    else
        log "❌ Azure infrastructure validation FAILED"
        log "   Infrastructure needs to be provisioned or updated"
        exit 1
    fi
}

main "$@"