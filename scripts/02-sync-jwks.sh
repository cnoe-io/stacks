#!/usr/bin/env bash
#
# Sync OIDC JWKS to Azure Storage for Workload Identity
# Feature: 102-bootstrap-talos-argocd
#
# This script performs Phase 2 of the bootstrap:
# - Extracts JWKS from Kubernetes OIDC endpoint
# - Generates OpenID Connect configuration
# - Uploads both to Azure Storage static website
#
# This enables Azure AD to validate tokens from the cluster,
# allowing External Secrets Operator to use Workload Identity.
#
# Prerequisites:
# - kubectl configured and connected to cluster
# - az CLI logged in with storage permissions
# - Azure Storage account with static website enabled
#
# Usage:
#   ./scripts/02-sync-jwks.sh [--force]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/azure.sh"

# Configuration
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
JWKS_PATH="${JWKS_PATH:-.well-known/jwks.json}"
OPENID_CONFIG_PATH="${OPENID_CONFIG_PATH:-.well-known/openid-configuration}"

# Parse arguments
FORCE_SYNC=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_SYNC=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

#
# Validate Azure configuration
#
validate_config() {
    log_info "Validating Azure configuration..."

    if [[ -z "$AZURE_STORAGE_ACCOUNT" ]]; then
        log_error "AZURE_STORAGE_ACCOUNT environment variable not set"
        return 1
    fi

    # Validate Azure login
    validate_azure_login

    # Check storage account accessibility
    if ! az storage account show --name "$AZURE_STORAGE_ACCOUNT" &>/dev/null; then
        log_error "Cannot access storage account: $AZURE_STORAGE_ACCOUNT"
        return 1
    fi

    log_success "Azure configuration validated"
}

#
# Get OIDC issuer URL from storage account
#
get_issuer_url() {
    local website_url
    website_url=$(get_storage_website_url "$AZURE_STORAGE_ACCOUNT")
    echo "$website_url"
}

#
# Check if JWKS is already synced and valid
#
check_jwks_synced() {
    local issuer_url
    issuer_url=$(get_issuer_url)
    local jwks_url="${issuer_url}/openid/v1/jwks"

    log_info "Checking existing JWKS at: $jwks_url"

    # Try to fetch JWKS from Azure Storage
    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' "$jwks_url" 2>/dev/null) || true

    if [[ "$http_code" == "200" ]]; then
        # Verify JWKS has keys
        local key_count
        key_count=$(curl -s "$jwks_url" 2>/dev/null | jq -r '.keys | length' 2>/dev/null) || true

        if [[ -n "$key_count" ]] && [[ "$key_count" -gt 0 ]]; then
            log_success "JWKS already synced with $key_count keys"
            return 0
        fi
    fi

    log_info "JWKS not found or invalid"
    return 1
}

#
# Extract JWKS from Kubernetes cluster
#
extract_jwks() {
    local output_file="${1:-/tmp/jwks.json}"

    log_info "Extracting JWKS from cluster..."

    # Extract JWKS from Kubernetes OIDC endpoint
    if ! kubectl get --raw /openid/v1/jwks > "$output_file" 2>/dev/null; then
        log_error "Failed to extract JWKS from cluster"
        log_info "Ensure kubectl is configured and cluster is accessible"
        return 1
    fi

    # Validate JWKS structure
    if ! jq -e '.keys | length > 0' "$output_file" &>/dev/null; then
        log_error "JWKS has no keys"
        return 1
    fi

    local key_count
    key_count=$(jq -r '.keys | length' "$output_file")
    log_success "Extracted JWKS with $key_count keys"

    register_cleanup "$output_file"
    echo "$output_file"
}

#
# Generate OpenID Connect configuration
#
generate_openid_config() {
    local issuer_url="$1"
    local output_file="${2:-/tmp/openid-configuration.json}"

    log_info "Generating OpenID configuration..."

    cat > "$output_file" <<EOF
{
  "issuer": "${issuer_url}/",
  "jwks_uri": "${issuer_url}/openid/v1/jwks",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ]
}
EOF

    log_success "OpenID configuration generated"
    register_cleanup "$output_file"
    echo "$output_file"
}

#
# Upload JWKS to Azure Storage
#
upload_jwks() {
    local jwks_file="$1"

    log_info "Uploading JWKS to Azure Storage..."

    # Upload to openid/v1/jwks path (standard OIDC path)
    upload_to_web_container "$AZURE_STORAGE_ACCOUNT" "openid/v1/jwks" "$jwks_file"

    # Also upload to .well-known path for compatibility
    upload_to_web_container "$AZURE_STORAGE_ACCOUNT" ".well-known/jwks.json" "$jwks_file"
}

#
# Upload OpenID configuration to Azure Storage
#
upload_openid_config() {
    local config_file="$1"

    log_info "Uploading OpenID configuration to Azure Storage..."

    upload_to_web_container "$AZURE_STORAGE_ACCOUNT" ".well-known/openid-configuration" "$config_file"
}

#
# Verify OIDC endpoint is accessible
#
verify_oidc_endpoint() {
    local issuer_url
    issuer_url=$(get_issuer_url)

    log_info "Verifying OIDC endpoints..."

    # Check openid-configuration
    local config_url="${issuer_url}/.well-known/openid-configuration"
    log_info "  Checking: $config_url"

    local config_response
    if ! config_response=$(curl -s "$config_url" 2>/dev/null); then
        log_error "Failed to fetch OpenID configuration"
        return 1
    fi

    # Validate response
    if ! echo "$config_response" | jq -e '.issuer' &>/dev/null; then
        log_error "Invalid OpenID configuration response"
        return 1
    fi

    log_success "OpenID configuration accessible"

    # Check JWKS
    local jwks_url
    jwks_url=$(echo "$config_response" | jq -r '.jwks_uri')
    log_info "  Checking: $jwks_url"

    local jwks_response
    if ! jwks_response=$(curl -s "$jwks_url" 2>/dev/null); then
        log_error "Failed to fetch JWKS"
        return 1
    fi

    local key_count
    key_count=$(echo "$jwks_response" | jq -r '.keys | length' 2>/dev/null) || true

    if [[ -z "$key_count" ]] || [[ "$key_count" -eq 0 ]]; then
        log_error "JWKS has no keys"
        return 1
    fi

    log_success "JWKS accessible with $key_count keys"
}

#
# Print summary
#
print_summary() {
    local issuer_url
    issuer_url=$(get_issuer_url)

    echo ""
    log_info "JWKS Sync Summary"
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "OIDC Issuer URL: ${issuer_url}/"
    echo ""
    echo "Endpoints:"
    echo "  OpenID Config: ${issuer_url}/.well-known/openid-configuration"
    echo "  JWKS URI:      ${issuer_url}/openid/v1/jwks"
    echo ""
    echo "Azure AD Configuration:"
    echo "  Use the issuer URL when creating federated credentials:"
    echo "  az ad app federated-credential create \\"
    echo "    --id <app-object-id> \\"
    echo "    --parameters '{\"name\":\"k8s-federated\",\"issuer\":\"${issuer_url}/\",\"subject\":\"system:serviceaccount:external-secrets:external-secrets\",\"audiences\":[\"api://AzureADTokenExchange\"]}'"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
}

#
# Main execution
#
main() {
    print_header "Syncing OIDC JWKS to Azure Storage"

    # Validate prerequisites
    require_command "kubectl" "Install from https://kubernetes.io/docs/tasks/tools/"
    require_command "az" "Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
    require_command "jq" "Install with: apt install jq / brew install jq"
    require_command "curl" "Install with: apt install curl / brew install curl"

    # Validate configuration
    validate_config

    # Check if already synced (unless forcing)
    if [[ "$FORCE_SYNC" != "true" ]] && check_jwks_synced; then
        log_success "JWKS already synced, skipping (use --force to re-sync)"
        print_summary
        return 0
    fi

    # Get issuer URL
    local issuer_url
    issuer_url=$(get_issuer_url)
    log_info "OIDC Issuer URL: $issuer_url"

    # Extract JWKS from cluster
    local jwks_file
    jwks_file=$(extract_jwks)

    # Generate OpenID configuration
    local config_file
    config_file=$(generate_openid_config "$issuer_url")

    # Upload to Azure Storage
    upload_jwks "$jwks_file"
    upload_openid_config "$config_file"

    # Verify endpoints are accessible
    log_info "Waiting for Azure CDN propagation..."
    sleep 5

    verify_oidc_endpoint

    print_summary
    print_completion "JWKS Sync" "success"
}

# Run main
main "$@"
