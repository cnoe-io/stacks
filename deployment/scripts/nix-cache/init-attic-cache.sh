#!/usr/bin/env bash
#
# init-attic-cache.sh - Initialize Attic cache namespace and generate admin token
#
# This script:
# 1. Generates an admin JWT token with full permissions (10-year validity)
# 2. Sets up port-forward to Attic service
# 3. Logs into Attic CLI
# 4. Creates a cache namespace (default: "nixos")
# 5. Retrieves and displays the cache public key
# 6. Outputs NixOS configuration snippet for VM integration
#
# Usage:
#   ./init-attic-cache.sh [CACHE_NAME] [ATTIC_URL]
#
# Arguments:
#   CACHE_NAME - Name of the cache namespace to create (default: "nixos")
#   ATTIC_URL  - Attic service URL (default: http://localhost:8080 via port-forward)
#
# Examples:
#   ./init-attic-cache.sh                    # Use defaults
#   ./init-attic-cache.sh my-cache           # Custom cache name
#   ./init-attic-cache.sh nixos http://10.0.0.1:8080  # Custom URL (no port-forward)
#
# Prerequisites:
#   - kubectl configured to access cluster with nix-cache namespace
#   - Attic pod running in nix-cache namespace
#   - Attic CLI installed locally (nix-env -iA nixpkgs.attic)
#

set -euo pipefail

# Configuration
CACHE_NAME="${1:-nixos}"
ATTIC_URL="${2:-http://localhost:8080}"
NAMESPACE="nix-cache"
DEPLOYMENT="attic"

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

# Cleanup function (port-forward PID tracking)
PF_PID=""
cleanup() {
    if [ -n "$PF_PID" ] && kill -0 "$PF_PID" 2>/dev/null; then
        log_info "Stopping port-forward (PID: $PF_PID)..."
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
        log_success "Port-forward stopped"
    fi
}
trap cleanup EXIT INT TERM

# Main script starts here
log_info "Initializing Attic cache: $CACHE_NAME"
echo ""

# Step 1: Verify Attic pod is running
log_info "Checking Attic pod status..."
if ! kubectl get deployment -n "$NAMESPACE" "$DEPLOYMENT" &>/dev/null; then
    log_error "Attic deployment not found in namespace $NAMESPACE"
    log_error "Please deploy Attic first: cd ~/stacks && source deployment/scripts/cluster-menu.sh && cluster-update"
    exit 1
fi

POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app=attic -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$POD_STATUS" != "Running" ]; then
    log_error "Attic pod is not running (status: $POD_STATUS)"
    log_error "Check pod status: kubectl get pods -n $NAMESPACE -l app=attic"
    exit 1
fi
log_success "Attic pod is running"

# Step 2: Generate admin token (T039)
log_info "Generating admin JWT token (valid for 10 years)..."
ADMIN_TOKEN=$(kubectl exec -n "$NAMESPACE" "deploy/$DEPLOYMENT" -- \
    atticd-atticadm make-token \
        --sub "admin" \
        --validity "10y" \
        --pull "*" \
        --push "*" \
        --create-cache "*" \
        --configure-cache "*" \
        --destroy-cache "*" 2>/dev/null | tr -d '\n\r')

if [ -z "$ADMIN_TOKEN" ]; then
    log_error "Failed to generate admin token"
    exit 1
fi
log_success "Admin token generated"
echo ""
log_warning "IMPORTANT: Save this token securely (1Password, Bitwarden, etc.)"
echo -e "${YELLOW}Admin Token:${NC} $ADMIN_TOKEN"
echo ""

# Step 3: Set up port-forward if using localhost URL (T040 partial)
if [[ "$ATTIC_URL" == http://localhost:* ]]; then
    log_info "Setting up port-forward to Attic service..."
    kubectl port-forward -n "$NAMESPACE" "svc/$DEPLOYMENT" 8080:8080 &>/dev/null &
    PF_PID=$!

    # Wait for port-forward to be ready
    log_info "Waiting for port-forward to be ready..."
    for i in {1..10}; do
        if curl -s "$ATTIC_URL" &>/dev/null; then
            break
        fi
        if ! kill -0 "$PF_PID" 2>/dev/null; then
            log_error "Port-forward process died unexpectedly"
            exit 1
        fi
        sleep 1
    done

    if ! curl -s "$ATTIC_URL" &>/dev/null; then
        log_error "Port-forward failed to establish connection after 10 seconds"
        exit 1
    fi

    log_success "Port-forward established (PID: $PF_PID)"
else
    log_info "Using direct URL: $ATTIC_URL (no port-forward needed)"
fi

# Step 4: Login to Attic CLI (T040)
log_info "Logging into Attic CLI..."
if ! command -v attic &>/dev/null; then
    log_error "Attic CLI not found in PATH"
    log_error "Install Attic: nix-env -iA nixpkgs.attic"
    log_error "Or add to configuration.nix: environment.systemPackages = [ pkgs.attic ];"
    exit 1
fi

if attic login local "$ATTIC_URL" "$ADMIN_TOKEN" 2>/dev/null; then
    log_success "Logged in to Attic server: local"
else
    log_error "Failed to login to Attic"
    log_error "Check Attic service is accessible: curl $ATTIC_URL"
    exit 1
fi

# Step 5: Create cache namespace (T041)
log_info "Creating cache namespace: $CACHE_NAME..."
if attic cache create "$CACHE_NAME" 2>/dev/null; then
    log_success "Cache created: $CACHE_NAME"
elif attic cache info "$CACHE_NAME" &>/dev/null; then
    log_warning "Cache already exists: $CACHE_NAME (skipping creation)"
else
    log_error "Failed to create cache namespace"
    log_error "Check Attic logs: kubectl logs -n $NAMESPACE deploy/$DEPLOYMENT --tail=50"
    exit 1
fi

# Step 6: Retrieve cache info and parse public key (T042)
log_info "Retrieving cache information..."
CACHE_INFO=$(attic cache info "$CACHE_NAME" 2>/dev/null)
if [ -z "$CACHE_INFO" ]; then
    log_error "Failed to retrieve cache info"
    exit 1
fi

# Parse public key from cache info output
CACHE_PUBLIC_KEY=$(echo "$CACHE_INFO" | grep "Public key:" | awk '{print $3}')
if [ -z "$CACHE_PUBLIC_KEY" ]; then
    log_error "Failed to parse cache public key from cache info"
    log_error "Cache info output:"
    echo "$CACHE_INFO"
    exit 1
fi

log_success "Cache public key retrieved"
echo ""
echo "==================================="
echo "Cache Information"
echo "==================================="
echo "$CACHE_INFO"
echo ""

# Step 7: Output NixOS configuration snippet (T043)
echo "==================================="
echo "NixOS VM Configuration"
echo "==================================="
echo ""
echo "Add this to your NixOS VM configuration (e.g., nixos-config/base-vm-config.nix):"
echo ""
cat <<EOF
{ config, pkgs, ... }:

{
  nix.settings = {
    # Attic cache as primary substituter (falls back to cache.nixos.org if miss)
    substituters = [
      "http://attic.nix-cache.svc.cluster.local:8080/${CACHE_NAME}"
      "https://cache.nixos.org"
    ];

    # Trust Attic cache public key for signature verification
    trusted-public-keys = [
      "${CACHE_PUBLIC_KEY}"  # Attic cache generated key
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="  # Official NixOS cache
    ];
  };
}
EOF
echo ""
echo "==================================="
echo ""

log_success "Cache initialization complete!"
echo ""
log_info "Next steps:"
echo "  1. Copy the NixOS configuration snippet above to your VM configuration"
echo "  2. Push packages to cache: ./push-to-cache.sh /run/current-system $CACHE_NAME"
echo "  3. Rebuild VM to use Attic cache: nixos-rebuild switch"
echo ""
log_info "Admin token saved in Attic CLI config: ~/.config/attic/config.toml"
