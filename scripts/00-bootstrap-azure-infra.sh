#!/usr/bin/env bash
#
# Bootstrap Azure infrastructure for Kubernetes Workload Identity
# Feature: 102-bootstrap-talos-argocd
#
# This script creates and configures all Azure resources needed for:
# - OIDC issuer (Azure Storage static website)
# - Azure AD application for Workload Identity
# - Federated identity credentials for service accounts
# - Key Vault access configuration
#
# Prerequisites:
# - az CLI installed and logged in
# - jq installed
# - Valid Azure subscription
#
# Usage:
#   ./scripts/00-bootstrap-azure-infra.sh [--skip-existing] [--force]
#
# The script is idempotent - it can be run multiple times safely.
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source helper libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/azure.sh"

# Configuration defaults
RESOURCE_GROUP="${RESOURCE_GROUP:-rg3}"
LOCATION="${LOCATION:-eastus}"
APP_NAME="${APP_NAME:-gitops-talos}"

# Parse command line arguments
SKIP_EXISTING=false
FORCE_RECREATE=false
VERBOSE=false
CHECK_ONLY=false
UPDATE_ISSUER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-existing)
            SKIP_EXISTING=true
            shift
            ;;
        --force)
            FORCE_RECREATE=true
            shift
            ;;
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --update-issuer)
            UPDATE_ISSUER=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            set -x
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Bootstrap Azure infrastructure for Kubernetes Workload Identity"
            echo ""
            echo "Options:"
            echo "  --check          Check if Azure infrastructure exists (no changes)"
            echo "  --update-issuer  Update federated credentials with current issuer URL"
            echo "  --skip-existing  Skip resources that already exist"
            echo "  --force          Force recreation of resources"
            echo "  --verbose        Enable verbose output"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  AZURE_SUBSCRIPTION_ID  Azure subscription ID (required)"
            echo "  AZURE_TENANT_ID        Azure AD tenant ID (required)"
            echo "  AZURE_KEYVAULT_NAME    Azure Key Vault name (will be discovered if not set)"
            echo "  RESOURCE_GROUP         Resource group name (default: rg3)"
            echo "  LOCATION               Azure region (default: eastus)"
            echo "  APP_NAME               Azure AD app name (default: gitops-talos)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

#
# Validate Azure prerequisites
#
validate_prerequisites() {
    print_header "Validating Prerequisites"

    require_command "az" "Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
    require_command "jq" "Install with: apt install jq / brew install jq"

    # Validate Azure login
    validate_azure_login

    # Get subscription ID if not set
    if [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
        AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        log_info "Using current subscription: $AZURE_SUBSCRIPTION_ID"
    fi

    # Get tenant ID if not set
    if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
        AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
        log_info "Using tenant: $AZURE_TENANT_ID"
    fi

    # Set subscription
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"

    log_success "Prerequisites validated"
}

#
# Ensure resource group exists
#
ensure_resource_group() {
    log_info "Checking resource group: $RESOURCE_GROUP"

    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_success "Resource group exists: $RESOURCE_GROUP"
    else
        log_info "Creating resource group: $RESOURCE_GROUP in $LOCATION"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

#
# Create or find OIDC storage account
#
setup_oidc_storage() {
    print_header "Setting Up OIDC Storage Account"

    # Check if we already have a storage account configured
    if [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
        if az storage account show --name "$AZURE_STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            log_success "Using existing storage account: $AZURE_STORAGE_ACCOUNT"
            return 0
        else
            log_warn "Configured storage account '$AZURE_STORAGE_ACCOUNT' not found"
        fi
    fi

    # Try to find existing OIDC storage account
    log_info "Looking for existing OIDC storage accounts..."
    local existing_account
    existing_account=$(az storage account list -g "$RESOURCE_GROUP" \
        --query "[?starts_with(name, 'oidcissuer')].name | [0]" -o tsv 2>/dev/null || echo "")

    if [[ -n "$existing_account" ]] && [[ "$SKIP_EXISTING" == "true" ]]; then
        AZURE_STORAGE_ACCOUNT="$existing_account"
        log_success "Found existing OIDC storage account: $AZURE_STORAGE_ACCOUNT"
    else
        # Create new storage account
        AZURE_STORAGE_ACCOUNT="oidcissuer$(openssl rand -hex 6)"
        log_info "Creating OIDC storage account: $AZURE_STORAGE_ACCOUNT"

        # Check name availability
        local name_available
        name_available=$(az storage account check-name --name "$AZURE_STORAGE_ACCOUNT" \
            --query nameAvailable -o tsv 2>/dev/null || echo "false")

        if [[ "$name_available" != "true" ]]; then
            # Try with a different suffix
            AZURE_STORAGE_ACCOUNT="oidcissuer$(openssl rand -hex 6)"
        fi

        az storage account create \
            --name "$AZURE_STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind StorageV2 \
            --sku Standard_LRS \
            --allow-blob-public-access true \
            --tags purpose=workload-identity-oidc cluster-type=talos \
            --output none

        log_success "Storage account created: $AZURE_STORAGE_ACCOUNT"
    fi

    # Enable static website
    log_info "Enabling static website on storage account..."
    az storage blob service-properties update \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --auth-mode login \
        --static-website \
        --index-document "index.html" \
        --404-document "error.html" \
        --output none

    # Get the issuer URL
    SERVICE_ACCOUNT_ISSUER=$(az storage account show \
        --name "$AZURE_STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "primaryEndpoints.web" -o tsv)

    log_success "OIDC Issuer URL: $SERVICE_ACCOUNT_ISSUER"
}

#
# Check if Azure infrastructure exists (for --check mode)
#
check_infrastructure() {
    print_header "Checking Azure Infrastructure"

    local all_ok=true

    # Check storage account
    if [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
        if az storage account show --name "$AZURE_STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            log_success "Storage Account: $AZURE_STORAGE_ACCOUNT (exists)"
        else
            log_error "Storage Account: $AZURE_STORAGE_ACCOUNT (NOT FOUND)"
            all_ok=false
        fi
    else
        log_warn "Storage Account: Not configured in environment"
        all_ok=false
    fi

    # Check Azure AD app
    if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
        if az ad app show --id "$AZURE_CLIENT_ID" &>/dev/null; then
            log_success "Azure AD App: $AZURE_CLIENT_ID (exists)"

            # Check service principal
            if az ad sp show --id "$AZURE_CLIENT_ID" &>/dev/null; then
                log_success "Service Principal: exists"
            else
                log_error "Service Principal: MISSING (run --update-issuer to create)"
                all_ok=false
            fi

            # Check federated credentials
            local fic_count
            fic_count=$(az ad app federated-credential list --id "$AZURE_CLIENT_ID" --query "length(@)" -o tsv 2>/dev/null || echo "0")
            if [[ "$fic_count" -gt 0 ]]; then
                log_success "Federated Credentials: $fic_count configured"

                # Check if issuer matches
                local configured_issuer
                configured_issuer=$(az ad app federated-credential list --id "$AZURE_CLIENT_ID" \
                    --query "[0].issuer" -o tsv 2>/dev/null || echo "")
                if [[ -n "${SERVICE_ACCOUNT_ISSUER:-}" ]]; then
                    local expected_issuer="${SERVICE_ACCOUNT_ISSUER%/}"
                    local actual_issuer="${configured_issuer%/}"
                    if [[ "$expected_issuer" == "$actual_issuer" ]]; then
                        log_success "OIDC Issuer: matches ($configured_issuer)"
                    else
                        log_warn "OIDC Issuer: MISMATCH"
                        log_warn "  Expected: $expected_issuer"
                        log_warn "  Actual:   $actual_issuer"
                        log_warn "  Run with --update-issuer to fix"
                        all_ok=false
                    fi
                fi
            else
                log_error "Federated Credentials: NONE configured"
                all_ok=false
            fi
        else
            log_error "Azure AD App: $AZURE_CLIENT_ID (NOT FOUND)"
            all_ok=false
        fi
    else
        log_warn "Azure AD App: Not configured in environment"
        all_ok=false
    fi

    # Check Key Vault access
    if [[ -n "${AZURE_KEYVAULT_NAME:-}" ]] && [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
        local vault_id
        vault_id=$(az keyvault show --name "$AZURE_KEYVAULT_NAME" --query id -o tsv 2>/dev/null || echo "")
        if [[ -n "$vault_id" ]]; then
            local sp_object_id
            sp_object_id=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv 2>/dev/null || echo "")
            if [[ -n "$sp_object_id" ]]; then
                local role_exists
                role_exists=$(az role assignment list --assignee "$sp_object_id" --role "Key Vault Secrets User" \
                    --scope "$vault_id" --query "[0].id" -o tsv 2>/dev/null || echo "")
                if [[ -n "$role_exists" ]]; then
                    log_success "Key Vault Access: Key Vault Secrets User role assigned"
                else
                    log_error "Key Vault Access: Role NOT assigned"
                    all_ok=false
                fi
            fi
        fi
    fi

    # Check App Configuration access
    if [[ -n "${AZURE_APPCONFIG_NAME:-}" ]] && [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
        local appconfig_id
        appconfig_id=$(az appconfig show --name "$AZURE_APPCONFIG_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")
        if [[ -n "$appconfig_id" ]]; then
            local sp_object_id
            sp_object_id=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv 2>/dev/null || echo "")
            if [[ -n "$sp_object_id" ]]; then
                local role_exists
                role_exists=$(az role assignment list --assignee "$sp_object_id" --role "App Configuration Data Reader" \
                    --scope "$appconfig_id" --query "[0].id" -o tsv 2>/dev/null || echo "")
                if [[ -n "$role_exists" ]]; then
                    log_success "App Configuration Access: App Configuration Data Reader role assigned"
                else
                    log_error "App Configuration Access: Role NOT assigned"
                    all_ok=false
                fi
            fi
        fi
    fi

    echo ""
    if [[ "$all_ok" == "true" ]]; then
        log_success "All Azure infrastructure checks passed!"
        return 0
    else
        log_error "Some Azure infrastructure checks failed."
        log_info "Run without --check to create/update infrastructure."
        return 1
    fi
}

#
# Create or find Azure AD application
#
setup_azure_ad_app() {
    print_header "Setting Up Azure AD Application"

    # Check if app already exists
    local existing_app_id
    existing_app_id=$(az ad app list --display-name "$APP_NAME" \
        --query "[0].appId" -o tsv 2>/dev/null || echo "")

    if [[ -n "$existing_app_id" ]]; then
        if [[ "$FORCE_RECREATE" == "true" ]]; then
            log_warn "Deleting existing Azure AD app: $APP_NAME"
            local object_id
            object_id=$(az ad app show --id "$existing_app_id" --query id -o tsv)
            az ad app delete --id "$object_id" --output none || true
            sleep 5  # Wait for deletion to propagate
            existing_app_id=""
        else
            AZURE_CLIENT_ID="$existing_app_id"
            log_success "Using existing Azure AD app: $APP_NAME (ID: $AZURE_CLIENT_ID)"
        fi
    fi

    if [[ -z "$existing_app_id" ]]; then
        log_info "Creating Azure AD application: $APP_NAME"
        AZURE_CLIENT_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
        log_success "Azure AD app created: $AZURE_CLIENT_ID"

        # Wait for propagation
        sleep 5
    fi

    # ALWAYS ensure service principal exists (even for existing apps)
    log_info "Ensuring service principal exists..."
    if ! az ad sp show --id "$AZURE_CLIENT_ID" &>/dev/null; then
        az ad sp create --id "$AZURE_CLIENT_ID" --output none
        log_success "Service principal created"
        sleep 3  # Wait for SP creation to propagate
    else
        log_info "Service principal already exists"
    fi

    # Get app object ID for federated credentials
    APP_OBJECT_ID=$(az ad app show --id "$AZURE_CLIENT_ID" --query id -o tsv)
}

#
# Create federated identity credentials
#
setup_federated_credentials() {
    print_header "Setting Up Federated Identity Credentials"

    # Define service accounts that need federated credentials
    local -a SA_CONFIGS=(
        "external-secrets:external-secrets"    # ESO service account
        "mcp-tools:acr-sa"                     # MCP tools ACR access
        "kargo:acr-sa"                         # Kargo ACR access
        "ai-chatbot:ai-chatbot"                # AI chatbot Dapr secrets/config access
        "planner-agent:planner-dapr-agent"     # Planner agent Dapr secrets/config access
        "workflow-orchestrator:workflow-orchestrator"  # Workflow orchestrator Dapr secrets/config access
        "workflow-builder:workflow-orchestrator"       # Workflow orchestrator in workflow-builder namespace
        "activity-executor:activity-executor"  # Activity executor Dapr secrets/config access
        "dapr-sandbox:dapr-shared"             # Shared Dapr instances for agent sandboxes
    )

    # Remove trailing slash from issuer if present
    local issuer="${SERVICE_ACCOUNT_ISSUER%/}"

    for sa_config in "${SA_CONFIGS[@]}"; do
        local namespace="${sa_config%%:*}"
        local sa_name="${sa_config##*:}"
        local fic_name="${namespace}-${sa_name}"
        local subject="system:serviceaccount:${namespace}:${sa_name}"

        log_info "Checking federated credential: $fic_name"

        # Check if credential exists and get current issuer
        local existing_issuer
        existing_issuer=$(az ad app federated-credential list --id "$APP_OBJECT_ID" \
            --query "[?name=='${fic_name}'].issuer | [0]" -o tsv 2>/dev/null || echo "")

        if [[ -n "$existing_issuer" ]]; then
            # Check if issuer needs updating
            local existing_issuer_normalized="${existing_issuer%/}"
            local new_issuer_normalized="${issuer%/}"

            if [[ "$existing_issuer_normalized" != "$new_issuer_normalized" ]]; then
                if [[ "$UPDATE_ISSUER" == "true" ]] || [[ "$FORCE_RECREATE" == "true" ]]; then
                    log_warn "Updating federated credential issuer: $fic_name"
                    log_info "  Old: $existing_issuer"
                    log_info "  New: $issuer"
                    az ad app federated-credential update \
                        --id "$APP_OBJECT_ID" \
                        --federated-credential-id "$fic_name" \
                        --parameters "{
                            \"name\": \"${fic_name}\",
                            \"issuer\": \"${issuer}\",
                            \"subject\": \"${subject}\",
                            \"audiences\": [\"api://AzureADTokenExchange\"]
                        }" \
                        --output none
                    log_success "Updated federated credential: $fic_name"
                else
                    log_warn "Federated credential issuer mismatch: $fic_name"
                    log_warn "  Current: $existing_issuer"
                    log_warn "  Expected: $issuer"
                    log_warn "  Use --update-issuer to update"
                fi
            elif [[ "$FORCE_RECREATE" == "true" ]]; then
                log_info "Deleting existing federated credential: $fic_name"
                az ad app federated-credential delete \
                    --id "$APP_OBJECT_ID" \
                    --federated-credential-id "$fic_name" \
                    --output none
                sleep 2

                log_info "Recreating federated credential: $fic_name"
                az ad app federated-credential create \
                    --id "$APP_OBJECT_ID" \
                    --parameters "{
                        \"name\": \"${fic_name}\",
                        \"issuer\": \"${issuer}\",
                        \"subject\": \"${subject}\",
                        \"audiences\": [\"api://AzureADTokenExchange\"]
                    }" \
                    --output none
                log_success "Recreated federated credential: $fic_name"
            else
                log_success "Federated credential exists with correct issuer: $fic_name"
            fi
            continue
        fi

        # Create federated credential
        log_info "Creating federated credential: $fic_name"
        az ad app federated-credential create \
            --id "$APP_OBJECT_ID" \
            --parameters "{
                \"name\": \"${fic_name}\",
                \"issuer\": \"${issuer}\",
                \"subject\": \"${subject}\",
                \"audiences\": [\"api://AzureADTokenExchange\"]
            }" \
            --output none

        log_success "Created federated credential: $fic_name"
    done
}

#
# Discover and configure Key Vault
#
setup_keyvault() {
    print_header "Configuring Key Vault Access"

    # Discover Key Vault if not set
    if [[ -z "${AZURE_KEYVAULT_NAME:-}" ]]; then
        log_info "Discovering Key Vault in resource group: $RESOURCE_GROUP"
        AZURE_KEYVAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi

    if [[ -z "$AZURE_KEYVAULT_NAME" ]]; then
        log_warn "No Key Vault found in resource group: $RESOURCE_GROUP"
        log_info "Key Vault access configuration skipped"
        return 0
    fi

    log_info "Using Key Vault: $AZURE_KEYVAULT_NAME"

    # Get Key Vault resource ID
    local vault_id
    vault_id=$(az keyvault show --name "$AZURE_KEYVAULT_NAME" --query id -o tsv)

    # Get service principal object ID
    local sp_object_id
    sp_object_id=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv)

    # Check if role assignment exists
    local existing_role
    existing_role=$(az role assignment list \
        --assignee "$sp_object_id" \
        --role "Key Vault Secrets User" \
        --scope "$vault_id" \
        --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [[ -n "$existing_role" ]]; then
        log_success "Key Vault Secrets User role already assigned"
    else
        log_info "Assigning Key Vault Secrets User role..."
        az role assignment create \
            --assignee "$sp_object_id" \
            --role "Key Vault Secrets User" \
            --scope "$vault_id" \
            --output none
        log_success "Key Vault access configured"
    fi
}

#
# Configure App Configuration access
#
setup_appconfig() {
    print_header "Configuring App Configuration Access"

    # Discover App Configuration if not set
    local appconfig_name="${AZURE_APPCONFIG_NAME:-}"
    if [[ -z "$appconfig_name" ]]; then
        log_info "Discovering App Configuration in resource group: $RESOURCE_GROUP"
        appconfig_name=$(az appconfig list --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi

    if [[ -z "$appconfig_name" ]]; then
        log_warn "No App Configuration found in resource group: $RESOURCE_GROUP"
        log_info "App Configuration access configuration skipped"
        return 0
    fi

    log_info "Using App Configuration: $appconfig_name"

    # Get App Configuration resource ID
    local appconfig_id
    appconfig_id=$(az appconfig show --name "$appconfig_name" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

    # Get service principal object ID
    local sp_object_id
    sp_object_id=$(az ad sp show --id "$AZURE_CLIENT_ID" --query id -o tsv)

    # Check if role assignment exists
    local existing_role
    existing_role=$(az role assignment list \
        --assignee "$sp_object_id" \
        --role "App Configuration Data Reader" \
        --scope "$appconfig_id" \
        --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [[ -n "$existing_role" ]]; then
        log_success "App Configuration Data Reader role already assigned"
    else
        log_info "Assigning App Configuration Data Reader role..."
        az role assignment create \
            --assignee "$sp_object_id" \
            --role "App Configuration Data Reader" \
            --scope "$appconfig_id" \
            --output none
        log_success "App Configuration access configured"
    fi

    # Export for .env file
    AZURE_APPCONFIG_NAME="$appconfig_name"
}

#
# Save configuration to .env file
#
save_configuration() {
    print_header "Saving Configuration"

    local env_file="${SCRIPT_DIR}/.env"
    local template_file="${SCRIPT_DIR}/.env.template"

    # Backup existing .env if it exists
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing .env file"
    fi

    # Create .env file
    cat > "$env_file" <<EOF
# Environment for Talos GitOps Bootstrap
# Generated by 00-bootstrap-azure-infra.sh on $(date)
# Feature: 102-bootstrap-talos-argocd

# Azure subscription and tenant
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
AZURE_TENANT_ID="${AZURE_TENANT_ID}"

# Azure AD Application (for Workload Identity)
AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"

# Azure Key Vault (secrets storage)
AZURE_KEYVAULT_NAME="${AZURE_KEYVAULT_NAME:-}"

# Azure App Configuration (for centralized config)
AZURE_APPCONFIG_NAME="${AZURE_APPCONFIG_NAME:-}"

# Azure Storage Account (for OIDC JWKS hosting)
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT}"

# OIDC Issuer URL (derived from storage account)
SERVICE_ACCOUNT_ISSUER="${SERVICE_ACCOUNT_ISSUER}"

# Git repository (for ArgoCD)
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/PittampalliOrg/stacks.git}"
GIT_BRANCH="${GIT_BRANCH:-102-bootstrap-talos-argocd}"

# Tailscale tailnet (for remote access)
TAILSCALE_TAILNET="${TAILSCALE_TAILNET:-}"

# ArgoCD Helm chart version
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.3.0}"
EOF

    chmod 600 "$env_file"
    log_success "Configuration saved to: $env_file"

    # Also update the template if key values have changed
    if [[ -f "$template_file" ]]; then
        log_info "Configuration template at: $template_file"
    fi
}

#
# Print summary
#
print_summary() {
    print_header "Azure Infrastructure Setup Complete!"

    echo ""
    echo "Azure Resources Configured:"
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "Resource Group:        $RESOURCE_GROUP"
    echo "Storage Account:       $AZURE_STORAGE_ACCOUNT"
    echo "OIDC Issuer URL:       $SERVICE_ACCOUNT_ISSUER"
    echo "Azure AD App:          $APP_NAME"
    echo "Azure AD Client ID:    $AZURE_CLIENT_ID"
    if [[ -n "${AZURE_KEYVAULT_NAME:-}" ]]; then
    echo "Key Vault:             $AZURE_KEYVAULT_NAME"
    fi
    if [[ -n "${AZURE_APPCONFIG_NAME:-}" ]]; then
    echo "App Configuration:     $AZURE_APPCONFIG_NAME"
    fi
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Ensure your Talos cluster is running and accessible:"
    echo "   talosctl cluster show"
    echo ""
    echo "2. Run the full bootstrap:"
    echo "   ./scripts/bootstrap-cluster.sh"
    echo ""
    echo "3. Or run individual phases:"
    echo "   ./scripts/01-install-argocd.sh    # Install ArgoCD"
    echo "   ./scripts/02-sync-jwks.sh         # Sync OIDC JWKS"
    echo "   ./scripts/03-apply-base-apps.sh   # Apply GitOps apps"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
}

#
# Main execution
#
main() {
    print_header "Azure Infrastructure Bootstrap"

    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "App Name: $APP_NAME"

    # Load existing environment if available
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "Loading existing configuration from .env"
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    fi

    # Handle check-only mode
    if [[ "$CHECK_ONLY" == "true" ]]; then
        validate_prerequisites
        check_infrastructure
        return $?
    fi

    # Handle update-issuer mode (only updates federated credentials)
    if [[ "$UPDATE_ISSUER" == "true" ]]; then
        validate_prerequisites

        # Need OIDC storage account for issuer URL
        if [[ -z "${SERVICE_ACCOUNT_ISSUER:-}" ]]; then
            log_error "SERVICE_ACCOUNT_ISSUER not set. Run without flags first to discover storage account."
            return 1
        fi

        # Need Azure AD app for federated credentials
        if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
            log_error "AZURE_CLIENT_ID not set. Run without flags first to create/discover Azure AD app."
            return 1
        fi

        APP_OBJECT_ID=$(az ad app show --id "$AZURE_CLIENT_ID" --query id -o tsv)
        setup_federated_credentials
        setup_keyvault
        setup_appconfig
        log_success "Issuer update complete!"
        return 0
    fi

    # Execute full setup phases
    validate_prerequisites
    ensure_resource_group
    setup_oidc_storage
    setup_azure_ad_app
    setup_federated_credentials
    setup_keyvault
    setup_appconfig
    save_configuration

    print_summary
}

# Run main function
main "$@"
