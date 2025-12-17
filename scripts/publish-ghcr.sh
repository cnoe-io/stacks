#!/usr/bin/env bash
set -euo pipefail

#
# Outer Loop Publish Script
# Pushes application images to GHCR for production CI/CD pipeline
#
# Usage: VERSION=1.2.3 ./publish-ghcr.sh <image-tar-path> [image-name]
#
# This script:
# 1. Pushes the image to GHCR with semantic version tag
# 2. Hub Kargo automatically detects new semver tags
# 3. Auto-promotes to dev stage, manual promotion to staging
#
# Prerequisites:
# - skopeo installed
# - GHCR_TOKEN environment variable (GitHub PAT with packages:write)
# - VERSION environment variable (semver: x.y.z)
#

# Configuration
GHCR_REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
GHCR_ORG="${GHCR_ORG:-pittampalliorg}"
IMAGE_NAME="${2:-backstage-cnoe}"

# Version is required for outer loop
VERSION="${VERSION:-}"
if [ -z "$VERSION" ]; then
  echo "ERROR: VERSION environment variable is required"
  echo ""
  echo "Usage: VERSION=1.2.3 $0 <image-tar-path> [image-name]"
  echo ""
  echo "Examples:"
  echo "  VERSION=1.0.0 $0 ./result backstage-cnoe"
  echo "  VERSION=\$(git describe --tags) $0 docker://myapp:latest"
  exit 1
fi

# Validate version format (semver)
if ! [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: VERSION must be semantic version format (e.g., 1.2.3 or v1.2.3)"
  exit 1
fi

# Normalize version (ensure no 'v' prefix for consistency)
VERSION="${VERSION#v}"

echo "=================================================================="
echo "  Outer Loop: Publishing to GHCR"
echo "=================================================================="
echo ""
echo "Registry:    ${GHCR_REGISTRY}/${GHCR_ORG}"
echo "Image:       ${IMAGE_NAME}"
echo "Version:     ${VERSION}"
echo ""

# Check for GHCR token
if [ -z "${GHCR_TOKEN:-}" ]; then
  echo "ERROR: GHCR_TOKEN environment variable is required"
  echo ""
  echo "Generate a GitHub PAT with 'packages:write' scope:"
  echo "  https://github.com/settings/tokens/new?scopes=write:packages"
  echo ""
  echo "Then set: export GHCR_TOKEN=<your-token>"
  exit 1
fi

# Check for image source
IMAGE_SOURCE="${1:-}"
if [ -z "$IMAGE_SOURCE" ]; then
  echo "Usage: VERSION=x.y.z $0 <image-tar-path|docker-image-ref> [image-name]"
  echo ""
  echo "Examples:"
  echo "  VERSION=1.0.0 $0 ./result                    # From Nix build output"
  echo "  VERSION=1.0.0 $0 docker://myapp:latest       # From local Docker"
  echo "  VERSION=1.0.0 $0 docker-archive:./image.tar  # From tar archive"
  exit 1
fi

# Determine source type
if [ -f "$IMAGE_SOURCE" ]; then
  SOURCE_REF="docker-archive:${IMAGE_SOURCE}"
elif [[ "$IMAGE_SOURCE" == docker://* ]] || [[ "$IMAGE_SOURCE" == docker-archive:* ]]; then
  SOURCE_REF="$IMAGE_SOURCE"
else
  SOURCE_REF="docker://${IMAGE_SOURCE}"
fi

DEST_REF="docker://${GHCR_REGISTRY}/${GHCR_ORG}/${IMAGE_NAME}:${VERSION}"

echo "Source: ${SOURCE_REF}"
echo "Destination: ${DEST_REF}"
echo ""

# Push to GHCR with authentication
echo "Pushing image to GHCR..."
skopeo copy \
  --dest-creds="${GHCR_ORG}:${GHCR_TOKEN}" \
  "${SOURCE_REF}" \
  "${DEST_REF}"

echo ""
echo "Successfully pushed: ${GHCR_REGISTRY}/${GHCR_ORG}/${IMAGE_NAME}:${VERSION}"
echo ""

# Also tag as 'latest' for convenience
echo "Tagging as latest..."
LATEST_REF="docker://${GHCR_REGISTRY}/${GHCR_ORG}/${IMAGE_NAME}:latest"
skopeo copy \
  --dest-creds="${GHCR_ORG}:${GHCR_TOKEN}" \
  "${DEST_REF}" \
  "${LATEST_REF}"

echo ""
echo "=================================================================="
echo "  Outer Loop Publish Complete!"
echo "=================================================================="
echo ""
echo "Published:"
echo "  - ${GHCR_REGISTRY}/${GHCR_ORG}/${IMAGE_NAME}:${VERSION}"
echo "  - ${GHCR_REGISTRY}/${GHCR_ORG}/${IMAGE_NAME}:latest"
echo ""
echo "Hub Kargo Pipeline:"
echo "  1. Hub Kargo will detect new version from GHCR"
echo "  2. Freight created: backstage-ghcr-${VERSION}"
echo "  3. Auto-promote to: hub-backstage-dev (thinkpad spoke)"
echo "  4. Manual promote to: hub-backstage-staging (talos spoke)"
echo ""
echo "Monitor progress:"
echo "  kubectl --kubeconfig=~/.kube/hub-config get freight,promotions -n kargo-pipelines"
