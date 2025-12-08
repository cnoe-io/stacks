#!/usr/bin/env bash
#
# Bootstrap script for Talos Linux cluster with ArgoCD GitOps
# Feature: 102-bootstrap-talos-argocd
#
# This script orchestrates the complete cluster bootstrap process:
# 0. (Optional) Setup Azure infrastructure for Workload Identity
# 1. Validate prerequisites (tools, cluster access, Azure)
# 2. Install ArgoCD via Helm
# 3. Sync JWKS to Azure Storage for Workload Identity
# 4. Apply ArgoCD root application for GitOps takeover
#
# Usage:
#   ./scripts/bootstrap-cluster.sh [OPTIONS]
#
# Options:
#   --setup-azure  Run Azure infrastructure setup first
#   --skip-jwks    Skip JWKS sync to Azure Storage
#   --force        Force reinstall even if already installed
#   -h, --help     Show this help message
#
# Environment variables:
#   See scripts/.env.template for required variables
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source helper libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/azure.sh"
source "${SCRIPT_DIR}/lib/talos.sh"

# Error handling
trap 'handle_error $? "$BASH_COMMAND"' ERR

handle_error() {
    local exit_code=$1
    local command="$2"
    log_error "Command failed with exit code $exit_code: $command"
    log_info "Bootstrap can be resumed from current phase using: $0"
    log_info "Current phase: $(get_current_phase)"
    exit "$exit_code"
}

# Retry helper
retry_with_backoff() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local cmd="$*"

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$cmd"; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        attempt=$((attempt + 1))
    done

    log_error "All $max_attempts attempts failed"
    return 1
}

# Configuration
PHASE_FILE="${SCRIPT_DIR}/.bootstrap-phase"
ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.3.0}"

# Parse command line arguments
SKIP_JWKS=false
FORCE_REINSTALL=false
SETUP_AZURE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --setup-azure)
            SETUP_AZURE=true
            shift
            ;;
        --skip-jwks)
            SKIP_JWKS=true
            shift
            ;;
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Bootstrap a Talos Linux cluster with ArgoCD GitOps and Azure Workload Identity"
            echo ""
            echo "Options:"
            echo "  --setup-azure  Run Azure infrastructure setup first (storage, AD app, federated creds)"
            echo "  --skip-jwks    Skip JWKS sync and OIDC verification"
            echo "  --force        Force reinstall even if already installed"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Phases:"
            echo "  0. Azure Infrastructure (if --setup-azure)"
            echo "  1. Validate prerequisites"
            echo "  2. Install ArgoCD via Helm"
            echo "  3. Verify OIDC issuer configuration"
            echo "  4. Sync JWKS to Azure Storage"
            echo "  5. Apply ArgoCD root application"
            echo ""
            echo "Environment Variables (see .env.template):"
            echo "  AZURE_SUBSCRIPTION_ID   Azure subscription"
            echo "  AZURE_TENANT_ID         Azure AD tenant"
            echo "  AZURE_CLIENT_ID         Azure AD app client ID"
            echo "  AZURE_KEYVAULT_NAME     Key Vault for secrets"
            echo "  AZURE_STORAGE_ACCOUNT   Storage for OIDC"
            echo "  SERVICE_ACCOUNT_ISSUER  OIDC issuer URL (e.g., https://oidcXXX.z13.web.core.windows.net/)"
            echo "  GIT_REPO_URL            Git repo for ArgoCD"
            echo "  GIT_BRANCH              Git branch for ArgoCD"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

#
# Phase tracking for idempotent re-runs
#
get_current_phase() {
    if [[ -f "$PHASE_FILE" ]]; then
        cat "$PHASE_FILE"
    else
        echo "init"
    fi
}

set_phase() {
    local phase="$1"
    echo "$phase" > "$PHASE_FILE"
    log_info "Phase updated: $phase"
}

#
# Phase 0: Azure Infrastructure Setup (optional)
#
setup_azure_infrastructure() {
    print_header "Phase 0: Azure Infrastructure Setup"

    if [[ -x "${SCRIPT_DIR}/00-bootstrap-azure-infra.sh" ]]; then
        local azure_flags=""
        if [[ "$FORCE_REINSTALL" == "true" ]]; then
            azure_flags="--force"
        fi
        "${SCRIPT_DIR}/00-bootstrap-azure-infra.sh" $azure_flags

        # Reload environment after Azure setup
        if [[ -f "${SCRIPT_DIR}/.env" ]]; then
            log_info "Reloading environment from: ${SCRIPT_DIR}/.env"
            set -a
            source "${SCRIPT_DIR}/.env"
            set +a
        fi
    else
        log_error "Azure infrastructure script not found: ${SCRIPT_DIR}/00-bootstrap-azure-infra.sh"
        return 1
    fi

    set_phase "azure-ready"
    print_completion "Azure infrastructure" "success"
}

#
# Prerequisite validation
#
validate_prerequisites() {
    print_header "Validating Prerequisites"

    # Check required tools
    log_info "Checking required tools..."
    require_command "talosctl" "Install from https://www.talos.dev/"
    require_command "kubectl" "Install from https://kubernetes.io/docs/tasks/tools/"
    require_command "helm" "Install from https://helm.sh/docs/intro/install/"
    require_command "az" "Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
    require_command "jq" "Install with: apt install jq / brew install jq"

    log_success "All required tools available"

    # Validate Talos cluster
    validate_talos_prerequisites

    # Validate Azure (if not skipping JWKS)
    if [[ "$SKIP_JWKS" != "true" ]]; then
        validate_azure_prerequisites
    fi

    print_completion "Prerequisites" "success"
}

#
# Phase 1: Install ArgoCD via Helm
#
install_argocd() {
    print_header "Phase 1: Installing ArgoCD"

    # Check if already installed
    if helm_release_exists "argocd" "$ARGOCD_NAMESPACE" && [[ "$FORCE_REINSTALL" != "true" ]]; then
        log_success "ArgoCD already installed, skipping"
        set_phase "argocd-installed"
        return 0
    fi

    # Run ArgoCD install script
    if [[ -x "${SCRIPT_DIR}/01-install-argocd.sh" ]]; then
        "${SCRIPT_DIR}/01-install-argocd.sh"
    else
        log_error "ArgoCD install script not found: ${SCRIPT_DIR}/01-install-argocd.sh"
        return 1
    fi

    set_phase "argocd-installed"
    print_completion "ArgoCD installation" "success"
}

#
# Phase 2: Verify and Configure OIDC Issuer
#
verify_oidc_issuer() {
    print_header "Phase 2: Verifying OIDC Issuer Configuration"

    if [[ "$SKIP_JWKS" == "true" ]]; then
        log_warn "Skipping OIDC verification (--skip-jwks flag)"
        return 0
    fi

    # Check if SERVICE_ACCOUNT_ISSUER is set
    if [[ -z "${SERVICE_ACCOUNT_ISSUER:-}" ]]; then
        log_warn "SERVICE_ACCOUNT_ISSUER not set in environment"
        log_info "Skipping OIDC issuer verification. Run ./00-bootstrap-azure-infra.sh to set up Azure infrastructure."
        return 0
    fi

    # Get current cluster OIDC issuer
    log_info "Checking cluster OIDC issuer..."
    local cluster_issuer
    cluster_issuer=$(kubectl get --raw /.well-known/openid-configuration 2>/dev/null | jq -r '.issuer' || echo "")

    if [[ -z "$cluster_issuer" ]]; then
        log_warn "Cannot retrieve cluster OIDC issuer. Skipping verification."
        return 0
    fi

    # Normalize URLs (remove trailing slashes)
    local expected_issuer="${SERVICE_ACCOUNT_ISSUER%/}"
    local actual_issuer="${cluster_issuer%/}"

    log_info "Expected OIDC issuer: $expected_issuer"
    log_info "Actual OIDC issuer:   $actual_issuer"

    if [[ "$expected_issuer" != "$actual_issuer" ]]; then
        log_warn "OIDC issuer mismatch detected!"
        log_warn "The cluster is presenting tokens with issuer: $actual_issuer"
        log_warn "But Azure expects issuer: $expected_issuer"

        # If this is a fresh cluster with default issuer (IP-based), warn strongly
        if [[ "$actual_issuer" =~ ^https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:6443$ ]]; then
            log_error "Cluster is using default API server IP as OIDC issuer."
            log_error "This MUST be changed for Azure Workload Identity to work."
            log_info ""
            log_info "Option 1: Patch the Talos cluster (recommended for new clusters):"
            log_info "  talosctl patch mc --mode no-reboot \\"
            log_info "    --patch '[{\"op\": \"add\", \"path\": \"/cluster/apiServer/extraArgs\", \"value\": {\"service-account-issuer\": \"${expected_issuer}/\"}}]'"
            log_info ""
            log_info "Option 2: Update Azure federated credentials to match cluster:"
            log_info "  SERVICE_ACCOUNT_ISSUER=\"$actual_issuer\" ./00-bootstrap-azure-infra.sh --update-issuer"
            log_info ""
            log_info "See: docs/hcloud-server-setup.md Phase 8 for detailed instructions"
            log_info ""
            log_info "After patching, restart system pods:"
            log_info "  kubectl rollout restart daemonset/kube-proxy -n kube-system"
            return 1
        fi

        # Issuer mismatch but not default - could be intentional configuration
        log_warn "Issuer mismatch may cause Azure Workload Identity authentication failures."
        log_warn "Run: ./00-bootstrap-azure-infra.sh --update-issuer to fix"
    else
        log_success "OIDC issuer correctly configured: $actual_issuer"
    fi

    set_phase "oidc-verified"
    print_completion "OIDC issuer verification" "success"
}

#
# Phase 3: Sync JWKS to Azure Storage
#
sync_jwks() {
    print_header "Phase 3: Syncing JWKS to Azure Storage"

    if [[ "$SKIP_JWKS" == "true" ]]; then
        log_warn "Skipping JWKS sync (--skip-jwks flag)"
        return 0
    fi

    local current_phase
    current_phase=$(get_current_phase)

    # Check if JWKS already synced (unless forcing)
    if [[ "$current_phase" == "jwks-synced" ]] && [[ "$FORCE_REINSTALL" != "true" ]]; then
        log_success "JWKS already synced, skipping"
        return 0
    fi

    # Run JWKS sync script
    if [[ -x "${SCRIPT_DIR}/02-sync-jwks.sh" ]]; then
        "${SCRIPT_DIR}/02-sync-jwks.sh"
    else
        log_error "JWKS sync script not found: ${SCRIPT_DIR}/02-sync-jwks.sh"
        return 1
    fi

    set_phase "jwks-synced"
    print_completion "JWKS sync" "success"
}

#
# Phase 4: Apply ArgoCD Root Application
#
apply_base_apps() {
    print_header "Phase 4: Applying ArgoCD Applications"

    # Run base apps script
    if [[ -x "${SCRIPT_DIR}/03-apply-base-apps.sh" ]]; then
        "${SCRIPT_DIR}/03-apply-base-apps.sh"
    else
        log_error "Base apps script not found: ${SCRIPT_DIR}/03-apply-base-apps.sh"
        return 1
    fi

    set_phase "gitops-active"
    print_completion "ArgoCD applications" "success"
}

#
# Print access information
#
print_access_info() {
    print_header "Bootstrap Complete!"

    echo ""
    log_success "Cluster bootstrap completed successfully"
    echo ""

    echo "Access URLs (via Tailscale):"
    echo "  ArgoCD UI:     https://svc-argocd.${TAILSCALE_TAILNET:-<tailnet>}.ts.net"
    echo "  Kubernetes:    https://svc-k8s-api.${TAILSCALE_TAILNET:-<tailnet>}.ts.net"
    echo ""

    echo "ArgoCD admin password:"
    echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath=\"{.data.password}\" | base64 -d"
    echo ""

    echo "Port-forward for local access:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo ""

    echo "Verify ArgoCD applications:"
    echo "  kubectl get applications -n argocd"
    echo ""

    echo "Generate remote kubeconfig:"
    echo "  ./scripts/generate-remote-kubeconfig.sh"
    echo ""
}

#
# Main execution
#
main() {
    print_header "Talos Linux Cluster Bootstrap"

    log_info "Repository root: $REPO_ROOT"
    log_info "Script directory: $SCRIPT_DIR"

    # Load environment
    # Note: Using 'set -a' before source ensures all variables are exported to subprocesses
    # This is critical because scripts like 02-sync-jwks.sh run as separate processes
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "Loading environment from: ${SCRIPT_DIR}/.env"
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
        # Verify critical variables are set
        if [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
            log_warn "AZURE_STORAGE_ACCOUNT not set in .env - JWKS sync will fail"
        fi
        if [[ -z "${GIT_REPO_URL:-}" ]]; then
            log_warn "GIT_REPO_URL not set in .env - ArgoCD app will fail"
        fi
    elif [[ -f "${REPO_ROOT}/.env" ]]; then
        log_info "Loading environment from: ${REPO_ROOT}/.env"
        set -a
        source "${REPO_ROOT}/.env"
        set +a
    else
        log_warn "No .env file found. Using environment variables."
        log_info "Create from template: cp ${SCRIPT_DIR}/.env.template ${SCRIPT_DIR}/.env"
    fi

    # Debug: Show key environment variables (without sensitive values)
    log_info "Environment check:"
    log_info "  AZURE_STORAGE_ACCOUNT: ${AZURE_STORAGE_ACCOUNT:-(not set)}"
    log_info "  AZURE_KEYVAULT_NAME: ${AZURE_KEYVAULT_NAME:-(not set)}"
    log_info "  GIT_REPO_URL: ${GIT_REPO_URL:-(not set)}"
    log_info "  GIT_BRANCH: ${GIT_BRANCH:-main}"
    log_info "  GIT_PATH: ${GIT_PATH:-cdk8s/dist}"

    # Validate GIT_PATH doesn't have branch prefix (common mistake)
    if [[ "${GIT_PATH:-}" == *"consolidate-bootstrap"* ]] || [[ "${GIT_PATH:-}" == *"bootstrap-talos"* ]]; then
        log_warn "GIT_PATH appears to contain branch name prefix: ${GIT_PATH}"
        log_warn "This is likely incorrect. Path should be relative to repo root (e.g., 'cdk8s/dist')"
        log_warn "The branch is specified via GIT_BRANCH, not in the path."
    fi

    # Resume from current phase
    local current_phase
    current_phase=$(get_current_phase)
    log_info "Current phase: $current_phase"

    # Handle Azure infrastructure setup if requested
    if [[ "$SETUP_AZURE" == "true" ]] && [[ "$current_phase" == "init" ]]; then
        setup_azure_infrastructure
        current_phase="azure-ready"
    fi

    # Execute bootstrap phases
    case "$current_phase" in
        init|azure-ready)
            validate_prerequisites
            install_argocd
            verify_oidc_issuer
            sync_jwks
            apply_base_apps
            ;;
        argocd-installed)
            verify_oidc_issuer
            sync_jwks
            apply_base_apps
            ;;
        oidc-verified)
            sync_jwks
            apply_base_apps
            ;;
        jwks-synced)
            apply_base_apps
            ;;
        gitops-active|complete)
            if [[ "$FORCE_REINSTALL" == "true" ]]; then
                if [[ "$SETUP_AZURE" == "true" ]]; then
                    setup_azure_infrastructure
                fi
                validate_prerequisites
                install_argocd
                verify_oidc_issuer
                sync_jwks
                apply_base_apps
            else
                log_success "Bootstrap already complete. Use --force to re-run."
            fi
            ;;
        *)
            log_error "Unknown phase: $current_phase"
            exit 1
            ;;
    esac

    set_phase "complete"
    print_access_info
}

# Run main function
main "$@"
