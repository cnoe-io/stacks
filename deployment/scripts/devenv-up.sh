#!/usr/bin/env bash
# devenv-up.sh - Standalone replacement for `devenv up`
#
# Watches source manifests, rebuilds kustomize, and applies via idpbuilder.
# Replaces the devenv process-compose approach which has incompatibilities
# with exported bash functions (BASH_FUNC_*%%) from fzf/sesh.
#
# Usage:
#   ./deployment/scripts/devenv-up.sh          # Build, apply, watch
#   ./deployment/scripts/devenv-up.sh --watch  # Watch only (skip initial apply)
#
# Requirements: watchexec, yq-go, kustomize/kubectl, idpbuilder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${STACKS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Ensure required tools are available (resolve from nix store if not in PATH)
# Uses shell glob instead of find - nix store is too large for find to complete
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

# watchexec: file watcher
if ! command -v watchexec &>/dev/null; then
  _resolve_nix_tool "/nix/store/*watchexec*/bin/watchexec" "watchexec" || exit 1
fi

# yq-go (mikefarah): required by kustomize build scripts
# Must find mikefarah's yq, not the Python yq
if ! (command -v yq &>/dev/null && yq --version 2>&1 | grep -q mikefarah); then
  _resolve_nix_tool "/nix/store/*yq-go*/bin/yq" "yq-go" || exit 1
fi

# Detect cluster name
CLUSTER_NAME="${CLUSTER_HOST:-$(hostname -s 2>/dev/null || hostname)}"
KUSTOMIZE_BUILD_ENV="kind-$CLUSTER_NAME"

# Source environment
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
  # Initial build
  echo "🔨 Initial kustomize build..."
  cd "$STACKS_DIR/packages"
  make "build-kustomize-kind-$CLUSTER_NAME" 2>&1

  # Initial apply
  echo ""
  echo "🚀 Initial idpbuilder apply..."
  GITEA_OVERRIDE_FILE="$STACKS_DIR/deployment/overrides/gitea-actions.yaml"
  GITEA_CUSTOM_ARG=""
  if [ -f "$GITEA_OVERRIDE_FILE" ]; then
    GITEA_CUSTOM_ARG="--package-custom-file gitea:${GITEA_OVERRIDE_FILE}"
  fi
  idpbuilder create \
    --name "$CLUSTER_NAME" \
    -p "$STACKS_DIR/packages/dist/$KUSTOMIZE_BUILD_ENV/" \
    --package-custom-file "nginx:$STACKS_DIR/deployment/overrides/nginx-hostnetwork-no-hostport.yaml" \
    ${GITEA_CUSTOM_ARG} \
    --kind-config "$STACKS_DIR/deployment/config/kind-config.yaml" \
    --dev-password \
    --color \
    --log-level warn
fi

# Start file watcher
echo ""
echo "👁️  Watching source manifests for changes..."
echo "   Directories: packages/base/, components/, overlays/, scripts/"
echo "   Debounce: 2000ms"
echo ""
exec watchexec \
  --debounce 2000ms \
  --exts yaml,yml,json,sh \
  --watch "$STACKS_DIR/packages/base" \
  --watch "$STACKS_DIR/packages/components" \
  --watch "$STACKS_DIR/packages/overlays" \
  --watch "$STACKS_DIR/packages/scripts" \
  --watch "$STACKS_DIR/deployment/scripts" \
  --ignore "dist" \
  --ignore ".direnv" \
  --ignore "result*" \
  --on-busy-update restart \
  -- "$STACKS_DIR/deployment/scripts/devenv-watch-handler.sh"
