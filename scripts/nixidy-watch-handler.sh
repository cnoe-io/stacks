#!/usr/bin/env bash
# nixidy-watch-handler.sh
# Handles file change events from watchexec for nixidy development workflow
# Part of: Feature - File-watching development workflow
#
# Usage:
#   ./scripts/nixidy-watch-handler.sh          # Run full synth → deploy → sync cycle
#   NIXIDY_WATCH_SYNC_ARGOCD=false ./scripts/nixidy-watch-handler.sh  # Skip ArgoCD sync

set -euo pipefail

# Ensure STACKS_DIR is set
STACKS_DIR="${STACKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export STACKS_DIR

# Lockfile to prevent concurrent builds
LOCKFILE="/tmp/nixidy-watch.lock"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
log_success() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $1"; }
log_error() { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $1"; }

# Acquire lock (non-blocking)
acquire_lock() {
    if ! mkdir "$LOCKFILE" 2>/dev/null; then
        log_warning "Build already in progress, skipping..."
        exit 0
    fi
    trap "rm -rf '$LOCKFILE'" EXIT
}

# Main handler
main() {
    acquire_lock

    log_info "File change detected, starting nixidy build cycle..."
    echo ""

    # Source cluster-menu.sh for existing functions
    # shellcheck source=../deployment/scripts/cluster-menu.sh
    source "$STACKS_DIR/deployment/scripts/cluster-menu.sh"

    # Step 1: Synthesize nixidy manifests
    log_info "Step 1/3: Synthesizing nixidy manifests..."
    if ! nixidy-synth "kind"; then
        log_error "Nixidy synthesis failed"
        return 1
    fi
    log_success "Synthesis complete"
    echo ""

    # Step 2: Deploy via idpbuilder (idempotent)
    log_info "Step 2/3: Updating cluster via idpbuilder..."
    local CLUSTER_NAME
    CLUSTER_NAME="$(detect_cluster_name 2>/dev/null || echo "localdev")"
    local DEPLOY_DIR="$STACKS_DIR/deployment"

    # Run idpbuilder create (idempotent - safe to run repeatedly)
    if ! idpbuilder create \
        --name "${CLUSTER_NAME}" \
        -p "$STACKS_DIR/dist/" \
        --package-custom-file "nginx:${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml" \
        --kind-config "$DEPLOY_DIR/config/kind-config.yaml" \
        --dev-password 2>&1 | tail -20; then
        log_warning "idpbuilder create returned non-zero (may still be successful)"
    fi
    log_success "Cluster updated"
    echo ""

    # Step 3: Trigger ArgoCD sync (optional, controlled by env var)
    if [ "${NIXIDY_WATCH_SYNC_ARGOCD:-true}" = "true" ]; then
        log_info "Step 3/3: Triggering ArgoCD sync..."

        # Source ArgoCD auth helper
        local ARGOCD_AUTH_SCRIPT="$STACKS_DIR/deployment/scripts/argocd-auth.sh"
        if [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
            # shellcheck source=../deployment/scripts/argocd-auth.sh
            source "$ARGOCD_AUTH_SCRIPT"

            if argocd-ensure-auth 2>/dev/null; then
                argocd-sync-all 2>&1 | tail -10 || true
                log_success "ArgoCD sync triggered"
            else
                log_warning "ArgoCD auth failed, skipping sync (cluster may still be initializing)"
            fi
        else
            log_warning "argocd-auth.sh not found, skipping ArgoCD sync"
        fi
    else
        log_info "Step 3/3: ArgoCD sync disabled (NIXIDY_WATCH_SYNC_ARGOCD=false)"
    fi

    echo ""
    log_success "Build cycle complete!"
    echo ""
}

main "$@"
