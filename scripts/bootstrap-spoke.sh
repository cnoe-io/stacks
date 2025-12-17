#!/bin/bash
# bootstrap-spoke.sh - Bootstrap a spoke cluster for hub-and-spoke ArgoCD management
#
# This script:
# - Creates ServiceAccount on spoke cluster for ArgoCD management
# - Generates long-lived bearer token
# - Exports credentials to Azure Key Vault
# - Verifies spoke connectivity
#
# Usage:
#   ./bootstrap-spoke.sh <spoke-name>
#   ./bootstrap-spoke.sh --all              # Bootstrap all spokes
#   ./bootstrap-spoke.sh --list             # List credential status
#   ./bootstrap-spoke.sh --verify <spoke>   # Verify spoke connectivity
#
# Environment Variables:
#   AZURE_KEYVAULT_NAME    - Azure Key Vault name for credential storage (required)
#
# Prerequisites:
#   - kubectl configured with contexts for spoke clusters
#   - Azure CLI logged in with Key Vault access
#   - Spoke clusters must be accessible

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source spoke helpers
source "$SCRIPT_DIR/lib/spoke-helpers.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
  echo "Bootstrap spoke cluster for hub-and-spoke ArgoCD management"
  echo ""
  echo "Usage:"
  echo "  $0 <spoke-name>              Bootstrap a single spoke"
  echo "  $0 --all                     Bootstrap all spokes"
  echo "  $0 --list                    List credential status"
  echo "  $0 --verify <spoke-name>     Verify spoke connectivity"
  echo ""
  echo "Valid spoke names: ${VALID_SPOKES[*]}"
  echo ""
  echo "Required environment variables:"
  echo "  AZURE_KEYVAULT_NAME    Azure Key Vault name"
  echo ""
  echo "Examples:"
  echo "  export AZURE_KEYVAULT_NAME=idp-kv"
  echo "  $0 thinkpad"
  echo "  $0 --all"
}

check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check kubectl
  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found"
    exit 1
  fi

  # Check Azure CLI
  if ! command -v az &>/dev/null; then
    log_error "Azure CLI not found"
    exit 1
  fi

  # Check AZURE_KEYVAULT_NAME
  if [[ -z "${AZURE_KEYVAULT_NAME:-}" ]]; then
    log_error "AZURE_KEYVAULT_NAME environment variable not set"
    exit 1
  fi

  # Verify Azure login
  if ! az account show &>/dev/null; then
    log_error "Not logged in to Azure CLI. Run: az login"
    exit 1
  fi

  log_success "Prerequisites check passed"
}

bootstrap_single_spoke() {
  local spoke_name="$1"

  log_info "Bootstrapping spoke: $spoke_name"

  # Validate spoke name
  validate_spoke_name "$spoke_name" || return 1

  # Check kubectl context exists
  if ! kubectl config get-contexts "$spoke_name" &>/dev/null; then
    log_error "kubectl context '$spoke_name' not found"
    log_info "Available contexts:"
    kubectl config get-contexts -o name
    return 1
  fi

  # Create ServiceAccount on spoke
  log_info "Creating ServiceAccount on spoke..."
  create_spoke_service_account "$spoke_name" || return 1

  # Export credentials to Key Vault
  log_info "Exporting credentials to Azure Key Vault..."
  export_credentials_to_keyvault "$spoke_name" || return 1

  log_success "Spoke '$spoke_name' bootstrapped successfully"
  echo ""
  echo "Credentials stored in Key Vault '$AZURE_KEYVAULT_NAME':"
  echo "  Token: ARGOCD-CLUSTER-${spoke_name^^}-TOKEN"
  echo "  CA:    ARGOCD-CLUSTER-${spoke_name^^}-CA"
}

bootstrap_all_spokes() {
  log_info "Bootstrapping all spokes: ${VALID_SPOKES[*]}"
  echo ""

  local failed=()
  local succeeded=()

  for spoke in "${VALID_SPOKES[@]}"; do
    echo "============================================"
    if bootstrap_single_spoke "$spoke"; then
      succeeded+=("$spoke")
    else
      failed+=("$spoke")
      log_warn "Failed to bootstrap spoke: $spoke"
    fi
    echo ""
  done

  echo "============================================"
  echo "Summary"
  echo "============================================"
  echo "Succeeded: ${succeeded[*]:-none}"
  echo "Failed:    ${failed[*]:-none}"

  if [[ ${#failed[@]} -gt 0 ]]; then
    return 1
  fi
}

verify_spoke() {
  local spoke_name="$1"

  log_info "Verifying spoke: $spoke_name"

  validate_spoke_name "$spoke_name" || return 1
  verify_spoke_connectivity "$spoke_name"
}

# ============================================================================
# Main
# ============================================================================

main() {
  if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
  fi

  case "${1:-}" in
    --help|-h)
      show_usage
      exit 0
      ;;
    --list)
      check_prerequisites
      list_spoke_credentials
      exit 0
      ;;
    --all)
      check_prerequisites
      bootstrap_all_spokes
      exit $?
      ;;
    --verify)
      if [[ -z "${2:-}" ]]; then
        log_error "Spoke name required for --verify"
        exit 1
      fi
      verify_spoke "$2"
      exit $?
      ;;
    -*)
      log_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
    *)
      check_prerequisites
      bootstrap_single_spoke "$1"
      exit $?
      ;;
  esac
}

main "$@"
