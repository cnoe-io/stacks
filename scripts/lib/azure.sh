#!/usr/bin/env bash
#
# Azure CLI helper functions for Talos GitOps bootstrap
# Feature: 102-bootstrap-talos-argocd
#

set -euo pipefail

# Source common functions (only if not already loaded)
if [[ -z "${_COMMON_SH_LOADED:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_LIB_DIR}/common.sh"
fi

# Validate Azure CLI is logged in
validate_azure_login() {
    log_info "Validating Azure CLI login..."

    if ! az account show &>/dev/null; then
        log_error "Azure CLI not logged in. Run: az login"
        return 1
    fi

    local account_name
    account_name=$(az account show --query 'name' -o tsv)
    log_success "Logged in to Azure: $account_name"
}

# Validate required Azure environment variables
validate_azure_env() {
    log_info "Validating Azure environment variables..."

    require_env "AZURE_SUBSCRIPTION_ID" "Azure subscription ID"
    require_env "AZURE_TENANT_ID" "Azure AD tenant ID"
    require_env "AZURE_CLIENT_ID" "Azure AD application (client) ID for workload identity"
    require_env "AZURE_KEYVAULT_NAME" "Azure Key Vault name (without .vault.azure.net)"
    require_env "AZURE_STORAGE_ACCOUNT" "Azure Storage account name for OIDC hosting"

    log_success "Azure environment variables validated"
}

# Check if Azure Key Vault is accessible
validate_keyvault_access() {
    local keyvault_name="${1:-$AZURE_KEYVAULT_NAME}"

    log_info "Validating access to Key Vault: $keyvault_name"

    if ! az keyvault show --name "$keyvault_name" &>/dev/null; then
        log_error "Cannot access Key Vault: $keyvault_name"
        log_info "Ensure you have 'Key Vault Secrets User' role on the vault"
        return 1
    fi

    log_success "Key Vault accessible: $keyvault_name"
}

# Check if Azure Storage account is configured for static website
validate_storage_static_website() {
    local storage_account="${1:-$AZURE_STORAGE_ACCOUNT}"

    log_info "Validating Storage account static website: $storage_account"

    local static_website_enabled
    static_website_enabled=$(az storage blob service-properties show \
        --account-name "$storage_account" \
        --auth-mode login \
        --query 'staticWebsite.enabled' -o tsv 2>/dev/null)

    if [[ "$static_website_enabled" != "true" ]]; then
        log_error "Static website not enabled on storage account: $storage_account"
        log_info "Enable with: az storage blob service-properties update --account-name $storage_account --static-website --index-document index.html"
        return 1
    fi

    log_success "Storage static website enabled: $storage_account"
}

# Get the static website URL for a storage account
get_storage_website_url() {
    local storage_account="${1:-$AZURE_STORAGE_ACCOUNT}"

    az storage account show \
        --name "$storage_account" \
        --query 'primaryEndpoints.web' -o tsv | sed 's:/$::'
}

# Upload a file to Azure Storage $web container
upload_to_web_container() {
    local storage_account="$1"
    local blob_name="$2"
    local local_file="$3"
    local content_type="${4:-application/json}"

    log_info "Uploading $blob_name to $storage_account static website..."

    az storage blob upload \
        --account-name "$storage_account" \
        --container-name '$web' \
        --name "$blob_name" \
        --file "$local_file" \
        --content-type "$content_type" \
        --auth-mode login \
        --overwrite \
        --output none

    log_success "Uploaded: $blob_name"
}

# Check if a Key Vault secret exists
keyvault_secret_exists() {
    local keyvault_name="$1"
    local secret_name="$2"

    az keyvault secret show \
        --vault-name "$keyvault_name" \
        --name "$secret_name" \
        &>/dev/null
}

# Get a secret value from Key Vault
get_keyvault_secret() {
    local keyvault_name="$1"
    local secret_name="$2"

    az keyvault secret show \
        --vault-name "$keyvault_name" \
        --name "$secret_name" \
        --query 'value' -o tsv
}

# Validate federated credential exists for workload identity
validate_federated_credential() {
    local app_id="${1:-$AZURE_CLIENT_ID}"
    local credential_name="${2:-kubernetes-federated-identity}"

    log_info "Checking federated credential for app: $app_id"

    # Get the object ID for the app
    local object_id
    object_id=$(az ad app show --id "$app_id" --query 'id' -o tsv 2>/dev/null) || {
        log_error "Cannot find Azure AD application: $app_id"
        return 1
    }

    # Check if federated credential exists
    if az ad app federated-credential show \
        --id "$object_id" \
        --federated-credential-id "$credential_name" &>/dev/null; then
        log_success "Federated credential exists: $credential_name"
        return 0
    else
        log_warn "Federated credential not found: $credential_name"
        log_info "Create with: az ad app federated-credential create --id $object_id ..."
        return 1
    fi
}

# Validate all Azure prerequisites
validate_azure_prerequisites() {
    print_header "Validating Azure Prerequisites"

    validate_azure_login
    validate_azure_env
    validate_keyvault_access
    validate_storage_static_website

    print_completion "Azure validation" "success"
}
