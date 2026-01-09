#!/usr/bin/env bash
# nixidy-watch-handler.sh
# Handles file change events from watchexec for nixidy development workflow
# Part of: Feature - File-watching development workflow
#
# Usage:
#   ./scripts/nixidy-watch-handler.sh          # Run full synth → deploy → sync cycle
#   NIXIDY_WATCH_SYNC_ARGOCD=false ./scripts/nixidy-watch-handler.sh  # Skip ArgoCD sync
#
# Environment Variables:
#   NIXIDY_WATCH_SYNC_ARGOCD=true    # Auto-sync ArgoCD after deploy (default: true)
#   NIXIDY_WATCH_SHOW_DIFF=false     # Show detailed diff of changed manifests (default: false)

set -euo pipefail

# Ensure STACKS_DIR is set
STACKS_DIR="${STACKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export STACKS_DIR

# Lockfile to prevent concurrent builds
LOCKFILE="/tmp/nixidy-watch.lock"

# Snapshot file for change detection
SNAPSHOT_FILE="/tmp/nixidy-watch-snapshot.txt"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
log_success() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $1"; }
log_error() { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $1"; }
log_change() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }

# Create a snapshot of dist/ directory (file paths + checksums)
snapshot_dist() {
    local dist_dir="$STACKS_DIR/dist"
    if [[ -d "$dist_dir" ]]; then
        find "$dist_dir" -type f -name "*.yaml" -exec md5sum {} \; 2>/dev/null | sort
    fi
}

# Save current state before build
save_snapshot() {
    snapshot_dist > "$SNAPSHOT_FILE"
}

# Compare snapshots and report changes
report_changes() {
    local dist_dir="$STACKS_DIR/dist"
    local new_snapshot
    new_snapshot=$(snapshot_dist)

    # If no previous snapshot, skip comparison
    if [[ ! -f "$SNAPSHOT_FILE" ]]; then
        return 0
    fi

    local old_snapshot
    old_snapshot=$(cat "$SNAPSHOT_FILE")

    # If snapshots are identical, no changes
    if [[ "$old_snapshot" == "$new_snapshot" ]]; then
        log_info "No manifest changes detected"
        return 0
    fi

    echo ""
    log_change "━━━ Manifest Changes ━━━"

    # Track changes by application
    declare -A app_changes
    local added_files=()
    local modified_files=()
    local deleted_files=()

    # Find added and modified files
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local checksum file
        checksum=$(echo "$line" | awk '{print $1}')
        file=$(echo "$line" | awk '{print $2}')

        local old_checksum
        old_checksum=$(echo "$old_snapshot" | grep -F "$file" | awk '{print $1}' || true)

        if [[ -z "$old_checksum" ]]; then
            added_files+=("$file")
        elif [[ "$old_checksum" != "$checksum" ]]; then
            modified_files+=("$file")
        fi
    done <<< "$new_snapshot"

    # Find deleted files
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local file
        file=$(echo "$line" | awk '{print $2}')

        if ! echo "$new_snapshot" | grep -qF "$file"; then
            deleted_files+=("$file")
        fi
    done <<< "$old_snapshot"

    # Extract app name from file path (dist/<app>/manifests/*.yaml or dist/<app>.yaml)
    extract_app_name() {
        local file="$1"
        local relative="${file#$dist_dir/}"
        echo "$relative" | cut -d'/' -f1 | sed 's/\.yaml$//'
    }

    # Format manifest name (just the filename without path)
    format_manifest() {
        local file="$1"
        basename "$file"
    }

    # Group and display added files
    if [[ ${#added_files[@]} -gt 0 ]]; then
        declare -A added_by_app
        for file in "${added_files[@]}"; do
            local app=$(extract_app_name "$file")
            local manifest=$(format_manifest "$file")
            added_by_app["$app"]+="$manifest "
        done

        for app in "${!added_by_app[@]}"; do
            echo -e "  ${GREEN}+ ${app}${NC}"
            for manifest in ${added_by_app[$app]}; do
                echo -e "    ${DIM}${manifest}${NC}"
            done
        done
    fi

    # Group and display modified files
    if [[ ${#modified_files[@]} -gt 0 ]]; then
        declare -A modified_by_app
        for file in "${modified_files[@]}"; do
            local app=$(extract_app_name "$file")
            local manifest=$(format_manifest "$file")
            modified_by_app["$app"]+="$manifest "
        done

        for app in "${!modified_by_app[@]}"; do
            echo -e "  ${YELLOW}~ ${app}${NC}"
            for manifest in ${modified_by_app[$app]}; do
                echo -e "    ${DIM}${manifest}${NC}"
            done

            # Show detailed diff if enabled
            if [[ "${NIXIDY_WATCH_SHOW_DIFF:-false}" == "true" ]]; then
                for file in "${modified_files[@]}"; do
                    if [[ "$(extract_app_name "$file")" == "$app" ]]; then
                        show_file_diff "$file"
                    fi
                done
            fi
        done
    fi

    # Group and display deleted files
    if [[ ${#deleted_files[@]} -gt 0 ]]; then
        declare -A deleted_by_app
        for file in "${deleted_files[@]}"; do
            local app=$(extract_app_name "$file")
            local manifest=$(format_manifest "$file")
            deleted_by_app["$app"]+="$manifest "
        done

        for app in "${!deleted_by_app[@]}"; do
            echo -e "  ${RED}- ${app}${NC}"
            for manifest in ${deleted_by_app[$app]}; do
                echo -e "    ${DIM}${manifest}${NC}"
            done
        done
    fi

    # Summary line
    local total_changes=$((${#added_files[@]} + ${#modified_files[@]} + ${#deleted_files[@]}))
    echo -e "  ${DIM}(${#added_files[@]} added, ${#modified_files[@]} modified, ${#deleted_files[@]} deleted)${NC}"
    echo ""
}

# Show diff for a specific file (requires git or diff)
show_file_diff() {
    local file="$1"
    local old_content new_content

    # Get old content from git if available, otherwise skip
    if command -v git &>/dev/null && git -C "$STACKS_DIR" rev-parse --git-dir &>/dev/null; then
        old_content=$(git -C "$STACKS_DIR" show "HEAD:${file#$STACKS_DIR/}" 2>/dev/null || true)
        if [[ -n "$old_content" ]] && [[ -f "$file" ]]; then
            echo -e "    ${DIM}─── diff ───${NC}"
            diff --color=always -u <(echo "$old_content") "$file" 2>/dev/null | head -20 | sed 's/^/    /' || true
            echo -e "    ${DIM}────────────${NC}"
        fi
    fi
}

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

    # Save snapshot of current dist/ for change detection
    save_snapshot

    # Step 1: Synthesize nixidy manifests
    log_info "Step 1/3: Synthesizing nixidy manifests..."
    if ! nixidy-synth "kind"; then
        log_error "Nixidy synthesis failed"
        return 1
    fi
    log_success "Synthesis complete"

    # Report what changed
    report_changes
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
