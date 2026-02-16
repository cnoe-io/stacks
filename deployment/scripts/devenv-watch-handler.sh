#!/usr/bin/env bash
# devenv-watch-handler.sh - Called by watchexec when source manifests change
# This script rebuilds kustomize packages and applies them via idpbuilder

set -e

CLUSTER_NAME="${CLUSTER_HOST:-$(hostname -s 2>/dev/null || hostname)}"
KUSTOMIZE_BUILD_ENV="kind-$CLUSTER_NAME"
STACKS_DIR="${DEVENV_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

echo ""
echo "🔄 Change detected, rebuilding (kustomize)..."
cd "$STACKS_DIR/packages" && make "build-kustomize-kind-$CLUSTER_NAME" 2>&1

echo ""
echo "🚀 Applying to cluster..."
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
  --color

echo ""
echo "✅ Applied. Watching for changes..."
