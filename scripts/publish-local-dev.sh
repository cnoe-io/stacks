#!/usr/bin/env bash
set -euo pipefail

#
# Inner Loop Publish Script
# Pushes application images to KIND Gitea OCI registry for rapid iteration
#
# Usage: ./publish-local-dev.sh <image-tar-path> [image-name]
#
# This script:
# 1. Pushes the image to KIND Gitea OCI registry
# 2. Tags with dev-YYYYMMDD-HHMMSS-<sha> format
# 3. Optionally triggers Hub Kargo warehouse refresh
#
# Prerequisites:
# - skopeo installed
# - Network access to KIND Gitea via Tailscale
# - Gitea admin credentials
#

# Configuration
GITEA_REGISTRY="${GITEA_REGISTRY:-gitea.cnoe.localtest.me:8443}"
GITEA_ORG="${GITEA_ORG:-giteaadmin}"
IMAGE_NAME="${2:-backstage-cnoe}"
KARGO_WAIT="${KARGO_WAIT:-0}"
KARGO_STAGE="${KARGO_STAGE:-hub-backstage-local-dev}"

# Generate version tag: dev-YYYYMMDD-HHMMSS[-sha]
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [ -d .git ]; then
  GIT_SHA=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "")
  VERSION_TAG="dev-${TIMESTAMP}${GIT_SHA:+-${GIT_SHA}}"
else
  VERSION_TAG="dev-${TIMESTAMP}"
fi

echo "=================================================================="
echo "  Inner Loop: Publishing to KIND Gitea"
echo "=================================================================="
echo ""
echo "Registry:    ${GITEA_REGISTRY}/${GITEA_ORG}"
echo "Image:       ${IMAGE_NAME}"
echo "Tag:         ${VERSION_TAG}"
echo ""

# Check for image source
IMAGE_SOURCE="${1:-}"
if [ -z "$IMAGE_SOURCE" ]; then
  echo "Usage: $0 <image-tar-path|docker-image-ref> [image-name]"
  echo ""
  echo "Examples:"
  echo "  $0 ./result                         # From Nix build output"
  echo "  $0 docker://myapp:latest            # From local Docker"
  echo "  $0 docker-archive:./image.tar       # From tar archive"
  exit 1
fi

# Determine source type
if [ -f "$IMAGE_SOURCE" ]; then
  # File path - assume docker-archive format
  SOURCE_REF="docker-archive:${IMAGE_SOURCE}"
elif [[ "$IMAGE_SOURCE" == docker://* ]] || [[ "$IMAGE_SOURCE" == docker-archive:* ]]; then
  # Already has protocol prefix
  SOURCE_REF="$IMAGE_SOURCE"
else
  # Assume docker daemon reference
  SOURCE_REF="docker://${IMAGE_SOURCE}"
fi

DEST_REF="docker://${GITEA_REGISTRY}/${GITEA_ORG}/${IMAGE_NAME}:${VERSION_TAG}"

echo "Source: ${SOURCE_REF}"
echo "Destination: ${DEST_REF}"
echo ""

# Push to Gitea
echo "Pushing image to Gitea..."
skopeo copy \
  --dest-tls-verify=false \
  "${SOURCE_REF}" \
  "${DEST_REF}"

echo ""
echo "Successfully pushed: ${GITEA_REGISTRY}/${GITEA_ORG}/${IMAGE_NAME}:${VERSION_TAG}"

# Optionally trigger Hub Kargo warehouse refresh
if [ "$KARGO_WAIT" = "1" ]; then
  echo ""
  echo "Triggering Hub Kargo warehouse refresh..."

  # Check if hub kubeconfig exists
  HUB_KUBECONFIG="${HUB_KUBECONFIG:-$HOME/.kube/hub-config}"
  if [ -f "$HUB_KUBECONFIG" ]; then
    kubectl --kubeconfig="$HUB_KUBECONFIG" annotate warehouse hub-backstage-gitea \
      -n kargo-pipelines refresh=$(date +%s) --overwrite 2>/dev/null || \
      echo "Warning: Could not refresh warehouse (may not exist yet)"

    echo ""
    echo "Waiting for Kargo stage promotion..."
    echo "Watch status: kubectl --kubeconfig=$HUB_KUBECONFIG get freight,promotions -n kargo-pipelines -w"
  else
    echo "Warning: Hub kubeconfig not found at $HUB_KUBECONFIG"
    echo "Set HUB_KUBECONFIG environment variable or copy hub kubeconfig to ~/.kube/hub-config"
  fi
fi

echo ""
echo "Inner loop publish complete!"
echo "Hub Kargo will automatically detect and promote to: ${KARGO_STAGE}"
