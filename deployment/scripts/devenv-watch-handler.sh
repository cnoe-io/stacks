#!/usr/bin/env bash
# devenv-watch-handler.sh - Called by watchexec when source manifests change
# This script syncs the stacks repo to Gitea so ArgoCD applies changes.

set -e

STACKS_DIR="${STACKS_DIR:-${DEVENV_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}}"

echo ""
echo "🔄 Change detected, syncing to Gitea..."
source "$STACKS_DIR/deployment/scripts/cluster-menu.sh"
seed-stacks-gitea-repo

echo ""
echo "✅ Synced. ArgoCD will apply changes automatically. Watching for changes..."
