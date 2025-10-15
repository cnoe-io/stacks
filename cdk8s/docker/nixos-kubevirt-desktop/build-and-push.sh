#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# NixOS KubeVirt Desktop Image Builder
#
# This script builds a NixOS qcow2 image and packages it as a Docker image
# with nginx for serving to KubeVirt DataVolumes.
#
# Prerequisites:
#   - nixos-generate (from nixos-generators package)
#   - docker
#   - Access to /etc/nixos/configurations/kubevirt-desktop.nix
#
# Usage:
#   ./build-and-push.sh <docker-tag> [nixos-config-path]
#
# Example:
#   ./build-and-push.sh v1.1.0-tailscale /etc/nixos/configurations/kubevirt-desktop.nix
##############################################################################

# Configuration
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_USERNAME="${DOCKER_USERNAME:-vpittamp23}"
DOCKER_IMAGE="${DOCKER_IMAGE:-nixos-kubevirt-desktop}"

# Arguments
DOCKER_TAG="${1:-latest}"
NIXOS_CONFIG="${2:-/etc/nixos/configurations/kubevirt-desktop.nix}"

# Derived paths
BUILD_DIR="$(mktemp -d)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_OUTPUT_DIR="${BUILD_DIR}/nixos-output"
DOCKER_BUILD_DIR="${BUILD_DIR}/docker-build"

# Full image name
FULL_IMAGE_NAME="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${DOCKER_IMAGE}:${DOCKER_TAG}"

echo "=== NixOS KubeVirt Desktop Image Builder ==="
echo "Docker Image: ${FULL_IMAGE_NAME}"
echo "NixOS Config: ${NIXOS_CONFIG}"
echo "Build Directory: ${BUILD_DIR}"
echo ""

# Cleanup function
cleanup() {
  echo "Cleaning up temporary build directory: ${BUILD_DIR}"
  rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

# Step 1: Build NixOS qcow2 image
echo "Step 1/4: Building NixOS qcow2 image..."
echo "This may take 20-30 minutes on first build (cached builds: ~3 minutes)"
cd /etc/nixos
nixos-generate --format qcow \
  --configuration "${NIXOS_CONFIG}" \
  --out-link "${NIXOS_OUTPUT_DIR}"

# Verify qcow2 was created
if [ ! -f "${NIXOS_OUTPUT_DIR}/nixos.qcow2" ]; then
  echo "ERROR: NixOS qcow2 file not found at ${NIXOS_OUTPUT_DIR}/nixos.qcow2"
  exit 1
fi

QCOW2_SIZE=$(du -h "${NIXOS_OUTPUT_DIR}/nixos.qcow2" | cut -f1)
echo "✓ NixOS qcow2 built successfully (Size: ${QCOW2_SIZE})"
echo ""

# Step 2: Prepare Docker build context
echo "Step 2/4: Preparing Docker build context..."
mkdir -p "${DOCKER_BUILD_DIR}"
cp "${SCRIPT_DIR}/Dockerfile" "${DOCKER_BUILD_DIR}/"
cp "${NIXOS_OUTPUT_DIR}/nixos.qcow2" "${DOCKER_BUILD_DIR}/"
echo "✓ Docker build context ready"
echo ""

# Step 3: Build Docker image
echo "Step 3/4: Building Docker image..."
docker build \
  -t "${FULL_IMAGE_NAME}" \
  "${DOCKER_BUILD_DIR}"
echo "✓ Docker image built successfully"
echo ""

# Step 4: Push to Docker registry
echo "Step 4/4: Pushing Docker image to ${DOCKER_REGISTRY}..."
docker push "${FULL_IMAGE_NAME}"
echo "✓ Docker image pushed successfully"
echo ""

# Summary
echo "=== Build Complete ==="
echo "Image: ${FULL_IMAGE_NAME}"
echo "Size: $(docker images ${FULL_IMAGE_NAME} --format '{{.Size}}')"
echo ""
echo "Update your CDK8s applications.ts with:"
echo "  image: '${DOCKER_USERNAME}/${DOCKER_IMAGE}:${DOCKER_TAG}'"
