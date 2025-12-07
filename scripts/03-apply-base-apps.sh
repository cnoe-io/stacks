#!/usr/bin/env bash
#
# Apply ArgoCD root application and verify sync status
# Feature: 102-bootstrap-talos-argocd
#
# This script performs Phase 3 of the bootstrap:
# - Applies the ArgoCD root Application (App-of-Apps)
# - Waits for initial sync to complete
# - Verifies all child applications are synced
#
# Prerequisites:
# - ArgoCD installed and running (Phase 1)
# - JWKS synced to Azure Storage (Phase 2)
# - Git repository accessible from cluster
#
# Usage:
#   ./scripts/03-apply-base-apps.sh [--sync-only]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT available for future use if needed
# REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source helper libraries
source "${SCRIPT_DIR}/lib/common.sh"

# Configuration
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ROOT_APP_NAME="${ROOT_APP_NAME:-argocd-bootstrap}"
SYNC_TIMEOUT="${SYNC_TIMEOUT:-600}"  # 10 minutes
SYNC_CHECK_INTERVAL="${SYNC_CHECK_INTERVAL:-10}"

# Git configuration
GIT_REPO_URL="${GIT_REPO_URL:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_PATH="${GIT_PATH:-cdk8s/dist/talos}"

# Parse arguments
SYNC_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --sync-only)
            SYNC_ONLY=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

#
# Validate Git configuration
#
validate_git_config() {
    log_info "Validating Git configuration..."

    if [[ -z "$GIT_REPO_URL" ]]; then
        log_error "GIT_REPO_URL environment variable not set"
        log_info "Set in .env: GIT_REPO_URL=https://github.com/your-org/your-repo.git"
        return 1
    fi

    log_success "Git configuration validated"
    log_info "  Repository: $GIT_REPO_URL"
    log_info "  Branch: $GIT_BRANCH"
    log_info "  Path: $GIT_PATH"
}

#
# Check if root application already exists
#
root_app_exists() {
    kubectl get application "$ROOT_APP_NAME" -n "$ARGOCD_NAMESPACE" &>/dev/null
}

#
# Get application sync status
#
get_app_sync_status() {
    local app_name="$1"
    kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown"
}

#
# Get application health status
#
get_app_health_status() {
    local app_name="$1"
    kubectl get application "$app_name" -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown"
}

#
# Generate root application manifest
#
generate_root_app_manifest() {
    local manifest_file="${1:-/tmp/argocd-root-application.yaml}"

    log_info "Generating root application manifest..." >&2

    cat > "$manifest_file" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${ROOT_APP_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: bootstrap-script
    app.kubernetes.io/name: ${ROOT_APP_NAME}
    app.kubernetes.io/component: bootstrap
    app.kubernetes.io/part-of: platform
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GIT_REPO_URL}
    path: ${GIT_PATH}
    targetRevision: ${GIT_BRANCH}
    directory:
      recurse: true
      include: '*.yaml'
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - PrunePropagationPolicy=foreground
  ignoreDifferences:
    - group: argoproj.io
      kind: Application
      jsonPointers:
        - /status
EOF

    log_success "Root application manifest generated: $manifest_file" >&2
    register_cleanup "$manifest_file"
    echo "$manifest_file"
}

#
# Apply root application manifest
#
apply_root_application() {
    log_info "Applying root ArgoCD Application..."

    local manifest_file
    manifest_file=$(generate_root_app_manifest)

    # Apply the manifest
    kubectl apply -f "$manifest_file"

    log_success "Root application applied: $ROOT_APP_NAME"
}

#
# Wait for application to sync
#
wait_for_app_sync() {
    local app_name="$1"
    local timeout="$2"

    log_info "Waiting for $app_name to sync (timeout: ${timeout}s)..."

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local sync_status health_status
        sync_status=$(get_app_sync_status "$app_name")
        health_status=$(get_app_health_status "$app_name")

        if [[ "$sync_status" == "Synced" ]]; then
            log_success "$app_name: Synced (Health: $health_status)"
            return 0
        fi

        echo -n "."
        sleep "$SYNC_CHECK_INTERVAL"
        elapsed=$((elapsed + SYNC_CHECK_INTERVAL))
    done

    echo ""
    log_error "Timeout waiting for $app_name to sync"
    log_info "Current status: Sync=$sync_status, Health=$health_status"
    return 1
}

#
# List all ArgoCD applications and their status
#
list_applications() {
    log_info "ArgoCD Application Status:"
    echo ""
    echo "────────────────────────────────────────────────────────────────────────"
    printf "%-35s %-12s %-12s\n" "APPLICATION" "SYNC" "HEALTH"
    echo "────────────────────────────────────────────────────────────────────────"

    # Get all applications
    local apps
    apps=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    for app in $apps; do
        local sync_status health_status
        sync_status=$(get_app_sync_status "$app")
        health_status=$(get_app_health_status "$app")

        # Color coding
        local sync_color health_color
        case "$sync_status" in
            Synced) sync_color="${GREEN}" ;;
            OutOfSync) sync_color="${YELLOW}" ;;
            *) sync_color="${RED}" ;;
        esac

        case "$health_status" in
            Healthy) health_color="${GREEN}" ;;
            Progressing) health_color="${YELLOW}" ;;
            *) health_color="${RED}" ;;
        esac

        printf "%-35s ${sync_color}%-12s${NC} ${health_color}%-12s${NC}\n" \
            "$app" "$sync_status" "$health_status"
    done

    echo "────────────────────────────────────────────────────────────────────────"
    echo ""
}

#
# Wait for all child applications to sync
#
wait_for_all_apps() {
    local timeout="${1:-$SYNC_TIMEOUT}"

    log_info "Waiting for all applications to sync..."

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        # Count applications
        local total synced
        total=$(kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l)
        synced=$(kubectl get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | \
            grep -c "Synced" || true)

        log_info "Applications: $synced/$total synced"

        if [[ "$synced" -eq "$total" ]] && [[ "$total" -gt 0 ]]; then
            log_success "All $total applications are synced"
            return 0
        fi

        sleep "$SYNC_CHECK_INTERVAL"
        elapsed=$((elapsed + SYNC_CHECK_INTERVAL))
    done

    log_error "Timeout waiting for all applications to sync"
    list_applications
    return 1
}

#
# Trigger a sync for an application
#
trigger_sync() {
    local app_name="$1"

    log_info "Triggering sync for: $app_name"

    # Use kubectl patch to trigger sync by updating annotation
    kubectl patch application "$app_name" -n "$ARGOCD_NAMESPACE" \
        --type merge \
        -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
        2>/dev/null || true
}

#
# Main execution
#
main() {
    print_header "Applying ArgoCD Applications"

    # Validate prerequisites
    require_command "kubectl" "Install from https://kubernetes.io/docs/tasks/tools/"

    # Validate Git configuration
    validate_git_config

    if [[ "$SYNC_ONLY" == "true" ]]; then
        # Just trigger sync and wait
        log_info "Sync-only mode: triggering sync for existing applications"
        trigger_sync "$ROOT_APP_NAME"
        wait_for_all_apps
    else
        # Full apply flow
        if root_app_exists; then
            log_info "Root application already exists, triggering refresh..."
            trigger_sync "$ROOT_APP_NAME"
        else
            apply_root_application
        fi

        # Wait for root application to sync first
        wait_for_app_sync "$ROOT_APP_NAME" 120

        # Give time for child applications to be created
        log_info "Waiting for child applications to be created..."
        sleep 10

        # Wait for all child applications
        wait_for_all_apps "$SYNC_TIMEOUT"
    fi

    # List final status
    list_applications

    print_completion "ArgoCD Applications" "success"
}

# Run main
main "$@"
