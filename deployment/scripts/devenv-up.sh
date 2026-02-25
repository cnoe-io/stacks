#!/usr/bin/env bash
# devenv-up.sh - Standalone replacement for `devenv up`
# Watches source manifests and pushes them to Gitea for ArgoCD to sync.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${STACKS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

_resolve_nix_tool() {
  local pattern="$1" label="$2"
  local matches=( $pattern )
  if [ -f "${matches[0]}" ]; then
    export PATH="$(dirname "${matches[0]}"):$PATH"
    return 0
  fi
  echo "❌ $label not found. Run inside devenv shell or install via nix."
  return 1
}

if ! command -v watchexec &>/dev/null; then
  _resolve_nix_tool "/nix/store/*watchexec*/bin/watchexec" "watchexec" || exit 1
fi

CLUSTER_NAME="${CLUSTER_HOST:-$(hostname -s 2>/dev/null || hostname)}"

if [ -f "$STACKS_DIR/.env-files/kind.env" ]; then
  set -a
  source "$STACKS_DIR/.env-files/kind.env"
  set +a
fi

WATCH_ONLY=false
if [[ "${1:-}" == "--watch" ]]; then
  WATCH_ONLY=true
fi

if [ "$WATCH_ONLY" = false ]; then
  echo "🚀 Initial cluster update..."
  source "$STACKS_DIR/deployment/scripts/cluster-menu.sh"
  cluster-update
fi

echo ""
echo "👁️  Watching source manifests for changes..."
echo "   Directories: packages/base/, components/, overlays/"
echo "   Debounce: 2000ms"
echo ""
exec watchexec \
  --debounce 2000ms \
  --exts yaml,yml,json,sh \
  --watch "$STACKS_DIR/packages/base" \
  --watch "$STACKS_DIR/packages/components" \
  --watch "$STACKS_DIR/packages/overlays" \
  --ignore ".direnv" \
  --ignore "result*" \
  --on-busy-update restart \
  -- "$STACKS_DIR/deployment/scripts/devenv-watch-handler.sh"
