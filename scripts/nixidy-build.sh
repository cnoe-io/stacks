#!/usr/bin/env bash
# nixidy-build.sh - Wrapper script for building nixidy manifests
#
# Usage:
#   ./scripts/nixidy-build.sh [kind|talos]
#
# Environment variables:
#   CLUSTER_TYPE - Override the cluster type (kind or talos)
#   AZURE_CLIENT_ID, AZURE_TENANT_ID - Required for Talos builds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
NIXIDY_DIR="$REPO_ROOT/nixidy"

# Default to kind if no argument provided
CLUSTER_TYPE="${1:-${CLUSTER_TYPE:-kind}}"

# Validate cluster type
if [[ "$CLUSTER_TYPE" != "kind" && "$CLUSTER_TYPE" != "talos" ]]; then
    echo "Error: Invalid cluster type '$CLUSTER_TYPE'. Must be 'kind' or 'talos'"
    exit 1
fi

echo "Building manifests for cluster type: $CLUSTER_TYPE"

# Check for required environment variables for Talos
if [[ "$CLUSTER_TYPE" == "talos" ]]; then
    if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
        echo "Error: AZURE_CLIENT_ID is required for Talos builds"
        exit 1
    fi
    if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
        echo "Error: AZURE_TENANT_ID is required for Talos builds"
        exit 1
    fi
fi

# Change to nixidy directory
cd "$NIXIDY_DIR"

# Build using nixidy
echo "Running: nixidy build .#$CLUSTER_TYPE"
nix run .#nixidy -- build ".#$CLUSTER_TYPE"

# Check if result symlink exists
if [[ -L result ]]; then
    echo ""
    echo "Build complete! Output in: $NIXIDY_DIR/result"
    echo ""
    echo "Generated applications:"
    ls -1 result/ | grep -v '^apps$' || true
    echo ""
    echo "To deploy to KIND:"
    echo "  idpbuilder create --package $NIXIDY_DIR/dist/"
else
    echo "Build may have failed - no result symlink found"
    exit 1
fi
