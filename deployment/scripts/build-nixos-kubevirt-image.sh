#!/usr/bin/env bash
#
# build-nixos-kubevirt-image.sh - Build NixOS KubeVirt image and load into Kind
#
# This script:
# 1. Checks if image already exists in Kind cluster (idempotent)
# 2. Builds kubevirt-minimal-qcow2 from nixos-config flake
# 3. Packages qcow2 into nginx Docker image
# 4. Loads image into Kind cluster
#
# Usage:
#   ./build-nixos-kubevirt-image.sh [OPTIONS]
#
# Options:
#   --force           Force rebuild even if image exists
#   --local           Use local nixos-config worktree (default)
#   --github          Use github:vpittamp/nixos-config
#   --flake-ref URL   Use custom flake reference
#   --cluster NAME    Kind cluster name (default: auto-detect from hostname)
#
# Environment variables:
#   NIXOS_CONFIG_PATH - Path to local nixos-config (default: ~/repos/vpittamp/nixos-config/main)
#   KIND_CLUSTER      - Kind cluster name (default: hostname)
#   NIXOS_IMAGE_TAG   - Docker image tag (default: nixos-kubevirt-minimal:latest)
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${STACKS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Default paths
NIXOS_CONFIG_LOCAL="${NIXOS_CONFIG_PATH:-$HOME/repos/vpittamp/nixos-config/main}"
NIXOS_CONFIG_GITHUB="github:vpittamp/nixos-config"
FLAKE_PKG="kubevirt-minimal-qcow2"

# Docker image settings
IMAGE_TAG="${NIXOS_IMAGE_TAG:-nixos-kubevirt-minimal:latest}"

# Output paths
BUILD_DIR=""
OUT_QCOW2="/tmp/nixos-kubevirt-minimal.qcow2"

# Options
FORCE_BUILD=false
USE_GITHUB=false
CUSTOM_FLAKE_REF=""
FLAKE_REF=""

# ============================================================================
# Helper Functions
# ============================================================================

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "Missing required command: $1"
    exit 1
  }
}

cleanup() {
  if [ -n "$BUILD_DIR" ] && [ -d "$BUILD_DIR" ]; then
    log_info "Cleaning up build directory..."
    rm -rf "$BUILD_DIR"
  fi
}
trap cleanup EXIT

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)
        FORCE_BUILD=true
        shift
        ;;
      --local)
        USE_GITHUB=false
        shift
        ;;
      --github)
        USE_GITHUB=true
        shift
        ;;
      --flake-ref)
        CUSTOM_FLAKE_REF="$2"
        shift 2
        ;;
      --cluster)
        KIND_CLUSTER="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build NixOS KubeVirt minimal image and load into Kind cluster.

Options:
  --force           Force rebuild even if image exists
  --local           Use local nixos-config worktree (default)
  --github          Use github:vpittamp/nixos-config
  --flake-ref URL   Use custom flake reference
  --cluster NAME    Kind cluster name (default: auto-detect)
  -h, --help        Show this help

Environment:
  NIXOS_CONFIG_PATH   Local nixos-config path (default: ~/repos/vpittamp/nixos-config/main)
  KIND_CLUSTER        Kind cluster name (default: hostname)
  NIXOS_IMAGE_TAG     Docker image tag (default: nixos-kubevirt-minimal:latest)
EOF
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

preflight_checks() {
  log_info "Running pre-flight checks..."

  require nix
  require docker
  require kind

  # Detect cluster name if not set
  if [ -z "${KIND_CLUSTER:-}" ]; then
    KIND_CLUSTER="$(hostname)"
    log_info "Auto-detected cluster name: $KIND_CLUSTER"
  fi

  # Verify Kind cluster exists
  if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
    log_error "Kind cluster '$KIND_CLUSTER' not found"
    log_error "Available clusters: $(kind get clusters 2>/dev/null | tr '\n' ' ')"
    exit 1
  fi

  # Determine flake reference
  if [ -n "$CUSTOM_FLAKE_REF" ]; then
    FLAKE_REF="$CUSTOM_FLAKE_REF"
  elif [ "$USE_GITHUB" = true ]; then
    FLAKE_REF="$NIXOS_CONFIG_GITHUB"
  else
    if [ ! -d "$NIXOS_CONFIG_LOCAL" ]; then
      log_error "Local nixos-config not found: $NIXOS_CONFIG_LOCAL"
      log_error "Use --github or --flake-ref to specify an alternative"
      exit 1
    fi
    FLAKE_REF="$NIXOS_CONFIG_LOCAL"
  fi

  log_success "Pre-flight checks passed"
  log_info "Flake reference: $FLAKE_REF"
  log_info "Package: $FLAKE_PKG"
  log_info "Image tag: $IMAGE_TAG"
  log_info "Kind cluster: $KIND_CLUSTER"
}

# ============================================================================
# Image Existence Check (Idempotent)
# ============================================================================

check_image_exists() {
  log_info "Checking if image already exists in Kind cluster..."

  # Check if Docker image is loaded in Kind
  local kind_node="${KIND_CLUSTER}-control-plane"

  if docker exec "$kind_node" crictl images 2>/dev/null | grep -q "${IMAGE_TAG%%:*}"; then
    if [ "$FORCE_BUILD" = true ]; then
      log_warn "Image exists but --force specified, rebuilding..."
      return 1
    else
      log_success "Image already loaded in Kind cluster"
      log_info "Use --force to rebuild"
      return 0
    fi
  fi

  log_info "Image not found in Kind cluster, will build"
  return 1
}

# ============================================================================
# Build Image
# ============================================================================

build_image() {
  log_info "Building NixOS KubeVirt image..."

  local installable="${FLAKE_REF}#${FLAKE_PKG}"
  log_info "Building: $installable"

  # Build the qcow2 image
  local result
  result=$(nix build --no-link --print-out-paths "$installable" 2>&1) || {
    log_error "Nix build failed"
    echo "$result"
    exit 1
  }

  # Find the qcow2 file in the result
  local qcow2_path
  qcow2_path=$(find "$result" -name "*.qcow2" -type f 2>/dev/null | head -1)

  if [ -z "$qcow2_path" ]; then
    log_error "No qcow2 file found in build output: $result"
    exit 1
  fi

  log_success "Built: $qcow2_path"

  # Copy to output location
  cp "$qcow2_path" "$OUT_QCOW2"
  log_info "QCOW2 size: $(du -h "$OUT_QCOW2" | awk '{print $1}')"
}

# ============================================================================
# Package as Docker Image
# ============================================================================

package_docker_image() {
  log_info "Packaging qcow2 into Docker image..."

  BUILD_DIR=$(mktemp -d -t nixos-kubevirt-build.XXXXXX)

  # Create Dockerfile
  cat > "$BUILD_DIR/Dockerfile" <<'DOCKERFILE'
FROM nginx:alpine
COPY nixos.qcow2 /usr/share/nginx/html/nixos.qcow2
RUN chmod 644 /usr/share/nginx/html/nixos.qcow2
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
DOCKERFILE

  # Copy qcow2
  cp "$OUT_QCOW2" "$BUILD_DIR/nixos.qcow2"

  # Build Docker image
  docker build -t "$IMAGE_TAG" "$BUILD_DIR" || {
    log_error "Docker build failed"
    exit 1
  }

  log_success "Docker image built: $IMAGE_TAG"
}

# ============================================================================
# Load into Kind
# ============================================================================

load_into_kind() {
  log_info "Loading image into Kind cluster '$KIND_CLUSTER'..."

  kind load docker-image --name "$KIND_CLUSTER" "$IMAGE_TAG" || {
    log_error "Failed to load image into Kind"
    exit 1
  }

  log_success "Image loaded into Kind cluster"
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo "=========================================="
  echo "  NixOS KubeVirt Image Builder"
  echo "=========================================="
  echo ""

  parse_args "$@"
  preflight_checks

  if check_image_exists; then
    log_success "Image ready. Skipping build."
    exit 0
  fi

  build_image
  package_docker_image
  load_into_kind

  echo ""
  log_success "Build complete!"
  echo ""
  log_info "Next steps:"
  echo "  1. Set environment: export NIXOS_SWAY_IMAGE_SERVER_IMAGE='$IMAGE_TAG'"
  echo "  2. Run: cluster-update (or clu)"
  echo "  3. VM will boot automatically via ArgoCD"
  echo ""
}

main "$@"
