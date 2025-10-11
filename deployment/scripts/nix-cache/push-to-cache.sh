#!/usr/bin/env bash
#
# push-to-cache.sh - Push Nix store paths to Attic cache
#
# This script:
# 1. Validates the store path exists in /nix/store
# 2. Pushes the package and its dependencies to Attic cache
# 3. Displays cache statistics after push completes
#
# Usage:
#   ./push-to-cache.sh [STORE_PATH] [CACHE_NAME]
#
# Arguments:
#   STORE_PATH - Nix store path to push (default: /run/current-system)
#   CACHE_NAME - Name of the cache namespace (default: "nixos")
#
# Examples:
#   ./push-to-cache.sh                                      # Push current system
#   ./push-to-cache.sh /run/current-system                  # Explicit system push
#   ./push-to-cache.sh /nix/store/abc123-package-1.0 nixos  # Push specific package
#
# Prerequisites:
#   - Attic CLI installed and logged in (run init-attic-cache.sh first)
#   - Cache namespace already created
#   - Port-forward active or Tailscale connectivity to Attic service
#   - Sufficient network bandwidth for large uploads
#
# Performance:
#   - First push: 5-10 minutes for full system closure (~20GB uncompressed)
#   - Subsequent pushes: 1-2 minutes (deduplication skips existing chunks)
#   - Upload speed: 50-200 MB/s depending on network
#

set -euo pipefail

# Configuration
STORE_PATH="${1:-/run/current-system}"
CACHE_NAME="${2:-nixos}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

# Main script starts here
log_info "Pushing store path to Attic cache: $CACHE_NAME"
echo ""

# Step 1: Validate Attic CLI is installed and logged in (T046 partial)
if ! command -v attic &>/dev/null; then
    log_error "Attic CLI not found in PATH"
    log_error "Install Attic: nix-env -iA nixpkgs.attic"
    log_error "Or add to configuration.nix: environment.systemPackages = [ pkgs.attic ];"
    exit 1
fi

# Check if logged in by attempting to list caches
if ! attic cache list &>/dev/null; then
    log_error "Not logged in to Attic"
    log_error "Run init-attic-cache.sh first to generate admin token and login"
    log_error "Or manually login: attic login local http://localhost:8080 <ADMIN_TOKEN>"
    exit 1
fi

# Step 2: Validate store path exists (T046)
log_info "Validating store path: $STORE_PATH"

# Resolve symlinks (e.g., /run/current-system -> /nix/store/abc123...)
RESOLVED_PATH=$(readlink -f "$STORE_PATH" 2>/dev/null || echo "$STORE_PATH")

if [ ! -e "$RESOLVED_PATH" ]; then
    log_error "Store path does not exist: $STORE_PATH"
    if [ "$RESOLVED_PATH" != "$STORE_PATH" ]; then
        log_error "Resolved path: $RESOLVED_PATH"
    fi
    log_error "Check the path exists: ls -la $STORE_PATH"
    exit 1
fi

# Verify it's a Nix store path (starts with /nix/store/)
if [[ ! "$RESOLVED_PATH" =~ ^/nix/store/ ]]; then
    log_error "Not a valid Nix store path: $RESOLVED_PATH"
    log_error "Store paths must start with /nix/store/"
    log_error "Common valid paths:"
    log_error "  - /run/current-system (current system closure)"
    log_error "  - /nix/store/abc123...-package-name-1.0"
    exit 1
fi

log_success "Store path validated: $RESOLVED_PATH"

# Step 3: Verify cache exists
log_info "Verifying cache namespace exists: $CACHE_NAME"
if ! attic cache info "$CACHE_NAME" &>/dev/null; then
    log_error "Cache namespace does not exist: $CACHE_NAME"
    log_error "Run init-attic-cache.sh first to create the cache"
    log_error "Or create manually: attic cache create $CACHE_NAME"
    exit 1
fi
log_success "Cache namespace verified"

# Step 4: Push store path to cache (T047)
log_info "Pushing store path to cache (this may take several minutes)..."
log_info "Store path: $RESOLVED_PATH"
log_info "Cache: $CACHE_NAME"
echo ""

# Calculate total size before push (for progress indication)
if command -v nix-store &>/dev/null; then
    TOTAL_SIZE=$(nix-store -qR "$RESOLVED_PATH" 2>/dev/null | wc -l || echo "unknown")
    log_info "Total dependencies: $TOTAL_SIZE packages"
else
    log_warning "nix-store not found - cannot calculate dependency count"
fi

echo ""
log_info "Starting push (output from attic push)..."
echo "-----------------------------------"

# Run attic push with full output (shows progress)
if attic push "$CACHE_NAME" "$RESOLVED_PATH"; then
    echo "-----------------------------------"
    log_success "Push completed successfully"
else
    echo "-----------------------------------"
    log_error "Push failed"
    log_error "Check Attic logs: kubectl logs -n nix-cache deploy/attic --tail=50"
    log_error "Check network connectivity: curl http://localhost:8080 or Tailscale connection"
    exit 1
fi

# Step 5: Display cache statistics (T048)
echo ""
log_info "Retrieving cache statistics..."
CACHE_INFO=$(attic cache info "$CACHE_NAME" 2>/dev/null)
if [ -z "$CACHE_INFO" ]; then
    log_warning "Failed to retrieve cache statistics"
else
    echo ""
    echo "==================================="
    echo "Cache Statistics"
    echo "==================================="
    echo "$CACHE_INFO"
    echo ""
fi

log_success "Push complete!"
echo ""
log_info "Next steps:"
echo "  1. Configure NixOS VM to use this cache (see init-attic-cache.sh output)"
echo "  2. Rebuild VM: nixos-rebuild switch"
echo "  3. Verify cache hit rate: journalctl -u nix-daemon.service | grep substituter"
echo ""
log_info "To push additional packages:"
echo "  ./push-to-cache.sh /nix/store/abc123-package-1.0 $CACHE_NAME"
echo "  ./push-to-cache.sh \$(nix-build '<nixpkgs>' -A firefox) $CACHE_NAME"
