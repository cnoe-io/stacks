#!/usr/bin/env bash
#
# Common helper functions for Talos GitOps bootstrap scripts
# Feature: 102-bootstrap-talos-argocd
#

set -euo pipefail

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if a command exists
require_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        if [[ -n "$install_hint" ]]; then
            log_info "Install hint: $install_hint"
        fi
        return 1
    fi
}

# Validate required environment variables
require_env() {
    local var_name="$1"
    local description="${2:-$var_name}"

    if [[ -z "${!var_name:-}" ]]; then
        log_error "Required environment variable not set: $var_name"
        log_info "Description: $description"
        return 1
    fi
}

# Wait for a condition with timeout
wait_for() {
    local description="$1"
    local check_cmd="$2"
    local timeout="${3:-300}"  # Default 5 minutes
    local interval="${4:-5}"   # Default 5 seconds

    log_info "Waiting for: $description (timeout: ${timeout}s)"

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$check_cmd" &>/dev/null; then
            log_success "$description - ready"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    echo ""
    log_error "Timeout waiting for: $description"
    return 1
}

# Wait for Kubernetes pods to be ready
wait_for_pods() {
    local namespace="$1"
    local selector="$2"
    local timeout="${3:-300}"

    log_info "Waiting for pods in $namespace with selector '$selector'"
    kubectl wait --for=condition=Ready pod \
        -n "$namespace" \
        -l "$selector" \
        --timeout="${timeout}s"
}

# Check if Helm release exists
helm_release_exists() {
    local release_name="$1"
    local namespace="$2"

    helm list -n "$namespace" --filter "^${release_name}$" -q 2>/dev/null | grep -q "^${release_name}$"
}

# Check if Kubernetes resource exists
k8s_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"

    if [[ -n "$namespace" ]]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null
    else
        kubectl get "$resource_type" "$resource_name" &>/dev/null
    fi
}

# Retry a command with exponential backoff
retry_with_backoff() {
    local max_attempts="${1:-5}"
    local base_delay="${2:-2}"
    shift 2
    local cmd="$*"

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: $cmd"
        if eval "$cmd"; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            local delay=$((base_delay ** attempt))
            log_warn "Command failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    log_error "Command failed after $max_attempts attempts"
    return 1
}

# Generate a temporary file path
temp_file() {
    local prefix="${1:-bootstrap}"
    mktemp "/tmp/${prefix}.XXXXXX"
}

# Cleanup temporary files on exit
declare -a CLEANUP_FILES=()

cleanup_temp_files() {
    for file in "${CLEANUP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
}

register_cleanup() {
    CLEANUP_FILES+=("$1")
}

trap cleanup_temp_files EXIT

# Print a section header
print_header() {
    local title="$1"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Print completion message with summary
print_completion() {
    local phase="$1"
    local status="$2"

    echo ""
    if [[ "$status" == "success" ]]; then
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  ✓ $phase completed successfully${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}  ✗ $phase failed${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
    echo ""
}
