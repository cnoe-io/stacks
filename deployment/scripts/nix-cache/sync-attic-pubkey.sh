#!/usr/bin/env bash
#
# sync-attic-pubkey.sh - Sync or verify Attic cache public key
#
# Modes:
#   - If persistent signing key exists in AKV: Verify the cluster uses it (no NixOS changes needed)
#   - Otherwise: Sync the new public key to NixOS configuration (requires rebuild)
#
# Usage:
#   ./sync-attic-pubkey.sh [NIXOS_CONFIG_PATH]
#   ./sync-attic-pubkey.sh --verify-only
#
# Arguments:
#   NIXOS_CONFIG_PATH - Path to nixos-config base.nix (default: auto-detect)
#   --verify-only     - Only verify the key matches expected, don't update anything
#
# Prerequisites:
#   - kubectl configured to access cluster with nix-cache namespace
#   - Attic pod running with 'backstage' cache created
#
# When using persistent keys from Azure Key Vault:
#   - The public key is set during one-time setup and doesn't change
#   - This script only verifies the key matches the expected value
#   - No NixOS rebuild is needed after cluster recreation
#

set -euo pipefail

# Configuration
NAMESPACE="nix-cache"
CACHE_NAME="backstage"
TIMEOUT=300  # 5 minutes
VAULT_NAME="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
VERIFY_ONLY=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --verify-only)
      VERIFY_ONLY=true
      shift
      ;;
  esac
done

# Check if persistent signing key exists in Azure Key Vault
check_persistent_key() {
  if command -v az &>/dev/null && az account show &>/dev/null 2>&1; then
    if az keyvault secret show --vault-name "$VAULT_NAME" --name "ATTIC-SIGNING-PUBLIC-KEY" &>/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

# Get expected public key from AKV
get_expected_pubkey() {
  az keyvault secret show --vault-name "$VAULT_NAME" --name "ATTIC-SIGNING-PUBLIC-KEY" --query value -o tsv 2>/dev/null
}

# Auto-detect nixos-config base.nix path
if [ -n "${1:-}" ] && [ "${1:-}" != "--verify-only" ]; then
  NIXOS_CONFIG="$1"
elif [ -n "${NIXOS_CONFIG_DIR:-}" ]; then
  NIXOS_CONFIG="$NIXOS_CONFIG_DIR/configurations/base.nix"
elif [ -f "$HOME/repos/vpittamp/nixos-config/main/configurations/base.nix" ]; then
  NIXOS_CONFIG="$HOME/repos/vpittamp/nixos-config/main/configurations/base.nix"
elif [ -f "$HOME/nixos-config/configurations/base.nix" ]; then
  NIXOS_CONFIG="$HOME/nixos-config/configurations/base.nix"
elif [ -f "/etc/nixos/configurations/base.nix" ]; then
  NIXOS_CONFIG="/etc/nixos/configurations/base.nix"
else
  echo "Error: Could not find nixos-config base.nix"
  echo "Set NIXOS_CONFIG_DIR or pass path as argument"
  exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}i${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*"; }

# Check for persistent signing key mode
if check_persistent_key; then
  EXPECTED_PUBKEY=$(get_expected_pubkey)
  if [ -n "$EXPECTED_PUBKEY" ]; then
    log_info "Persistent signing key detected in Azure Key Vault"
    log_info "Expected public key: ${EXPECTED_PUBKEY:0:50}..."

    if $VERIFY_ONLY; then
      log_success "Verify-only mode: Persistent key configured"
      log_info "Public key: $EXPECTED_PUBKEY"
      exit 0
    fi

    # In persistent key mode, we just verify the cluster uses the right key
    # No NixOS config changes needed since the key was set during one-time setup
    log_info "Verifying cluster uses persistent signing key..."

    # Wait for Attic pod to be ready (shorter timeout since we're just verifying)
    if ! kubectl wait --for=condition=ready pod -l app=attic -n "$NAMESPACE" --timeout=60s &>/dev/null; then
      log_warning "Attic pod not ready yet - cannot verify signing key"
      log_info "The persistent key should be used automatically when the pod starts"
      exit 0
    fi

    # Get the actual public key from the cluster
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=attic -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POD_NAME" ]; then
      sleep 5  # Wait for cache to be created
      ACTUAL_PUBKEY=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
        TOKEN=\$(atticadm -f /etc/attic/server.toml make-token --sub verify --validity 1m --pull $CACHE_NAME 2>/dev/null)
        wget -q -O- --header=\"Authorization: Bearer \$TOKEN\" http://localhost:8080/_api/v1/cache-config/$CACHE_NAME 2>/dev/null
      " 2>/dev/null | grep -o '"public_key":"[^"]*"' | cut -d'"' -f4 || echo "")

      if [ -n "$ACTUAL_PUBKEY" ]; then
        if [ "$ACTUAL_PUBKEY" = "$EXPECTED_PUBKEY" ]; then
          log_success "Cluster is using the persistent signing key"
          log_info "Public key matches: $ACTUAL_PUBKEY"
          exit 0
        else
          log_warning "Public key mismatch!"
          log_warning "Expected: $EXPECTED_PUBKEY"
          log_warning "Actual:   $ACTUAL_PUBKEY"
          log_warning "The cluster may not be using the persistent key from AKV"
          log_warning "Check if the ExternalSecret synced correctly"
          exit 1
        fi
      else
        log_warning "Could not retrieve public key from cluster"
        log_info "The cache may not be fully initialized yet"
      fi
    fi

    log_success "Persistent key mode - no NixOS config changes needed"
    exit 0
  fi
fi

log_info "Syncing Attic public key to: $NIXOS_CONFIG"

# Wait for Attic pod to be ready
log_info "Waiting for Attic pod to be ready (timeout: ${TIMEOUT}s)..."
if ! kubectl wait --for=condition=ready pod -l app=attic -n "$NAMESPACE" --timeout="${TIMEOUT}s" 2>/dev/null; then
  log_warning "Attic pod not ready after ${TIMEOUT}s - skipping public key sync"
  log_warning "Run this script manually after Attic is ready:"
  log_warning "  $0"
  exit 0
fi

# Wait a bit more for the cache to be created by the startup script
log_info "Waiting for backstage cache to be initialized..."
sleep 10

# Get the public key from the cache
log_info "Retrieving public key for cache: $CACHE_NAME..."
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=attic -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
  log_warning "No Attic pod found - skipping public key sync"
  exit 0
fi

# Generate a temporary token and get cache info via API (attic CLI not available in container)
PUBLIC_KEY=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
  TOKEN=\$(atticadm -f /etc/attic/server.toml make-token --sub sync --validity 1m --pull $CACHE_NAME 2>/dev/null)
  wget -q -O- --header=\"Authorization: Bearer \$TOKEN\" http://localhost:8080/_api/v1/cache-config/$CACHE_NAME 2>/dev/null
" 2>/dev/null | grep -o '"public_key":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -z "$PUBLIC_KEY" ]; then
  log_warning "Could not retrieve public key - cache may not exist yet"
  log_warning "The cache will be created on first Attic pod startup"
  log_warning "Re-run this script after the pod has been running for a minute"
  exit 0
fi

log_success "Retrieved public key: $PUBLIC_KEY"

# Check if base.nix exists
if [ ! -f "$NIXOS_CONFIG" ]; then
  log_warning "NixOS config not found at: $NIXOS_CONFIG"
  log_warning "Update manually in your nix.settings:"
  log_warning "  extra-trusted-public-keys = [ \"$PUBLIC_KEY\" ];"
  exit 0
fi

# Get the current public key from base.nix
CURRENT_KEY=$(grep -oP 'backstage:[A-Za-z0-9+/=]+' "$NIXOS_CONFIG" | head -1 || echo "")

if [ "$CURRENT_KEY" = "$PUBLIC_KEY" ]; then
  log_success "Public key already up to date"
  exit 0
fi

# Update the public key in base.nix
log_info "Updating public key in base.nix..."
if [ -n "$CURRENT_KEY" ]; then
  sed -i "s|$CURRENT_KEY|$PUBLIC_KEY|g" "$NIXOS_CONFIG"
else
  log_warning "Could not find existing backstage key pattern in base.nix"
  log_warning "Add manually to extra-trusted-public-keys:"
  log_warning "  \"$PUBLIC_KEY\""
  exit 0
fi

log_success "Updated nixos-config with new public key"
log_info "Old key: $CURRENT_KEY"
log_info "New key: $PUBLIC_KEY"

# Show git diff
if command -v git &>/dev/null; then
  CONFIG_DIR=$(dirname "$NIXOS_CONFIG")
  if [ -d "$CONFIG_DIR/../.git" ] || [ -d "$CONFIG_DIR/.git" ]; then
    echo ""
    log_info "Git diff:"
    (cd "$CONFIG_DIR/.." && git diff --no-color configurations/base.nix 2>/dev/null) || \
    (cd "$CONFIG_DIR" && git diff --no-color base.nix 2>/dev/null) || true
  fi
fi

# Sync cluster CA certificate for TLS trust
# This ensures Nix can connect to the Attic cache over HTTPS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_SYNC_SCRIPT="$SCRIPT_DIR/../../scripts/certificates/sync-cluster-certificates.sh"
if [ -x "$CERT_SYNC_SCRIPT" ]; then
  echo ""
  log_info "Syncing cluster CA certificate for TLS trust..."
  "$CERT_SYNC_SCRIPT" --force
else
  log_warning "Certificate sync script not found at: $CERT_SYNC_SCRIPT"
  log_warning "You may need to manually sync the CA certificate for HTTPS to work"
fi

echo ""
log_success "Attic cache sync complete"
echo ""
log_info "Next steps:"
log_info "  1. Commit the change to nixos-config repo"
log_info "  2. Rebuild NixOS: sudo nixos-rebuild switch --flake ."
log_info ""
log_info "Or run: (cd $(dirname "$NIXOS_CONFIG")/.. && git add -A && git commit -m 'chore: Update Attic cache credentials' && sudo nixos-rebuild switch --flake .)"
