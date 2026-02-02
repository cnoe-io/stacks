#!/usr/bin/env bash
# Push shared devcontainer images to Gitea registry
#
# This script pushes shared devcontainer images used by DevSpace.
# It waits for Gitea registry to be ready before pushing.
#
# SMART MODE (default): Only pushes images that already exist locally.
# This is ideal for cluster-recreate where images were previously built.
#
# Usage:
#   ./push-devcontainers.sh              # Push existing images only (smart mode)
#   ./push-devcontainers.sh all          # Push all existing images
#   ./push-devcontainers.sh nodejs       # Push Node.js only (if exists)
#   ./push-devcontainers.sh python       # Push Python only (if exists)
#   ./push-devcontainers.sh hybrid       # Push hybrid only (if exists)
#   ./push-devcontainers.sh --build      # Force build before push
#   ./push-devcontainers.sh --build all  # Build and push all
#
# Environment variables:
#   GITEA_REGISTRY  Registry host (default: gitea.cnoe.localtest.me:8443)
#   GITEA_USER      Registry user (default: giteaadmin)
#   GITEA_PASSWORD  Registry password (default: giteaAdmin)
#   FORCE_BUILD     Force docker build (default: false)
#   SKIP_BUILD      Legacy: same as not using --build (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${STACKS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DEVCONTAINERS_DIR="${STACKS_DIR}/devcontainers"

# Registry configuration
GITEA_REGISTRY="${GITEA_REGISTRY:-gitea.cnoe.localtest.me:8443}"
GITEA_USER="${GITEA_USER:-giteaadmin}"
# Default password matches idpbuilder's --dev-password default
GITEA_PASSWORD="${GITEA_PASSWORD:-developer}"

# Build control - default to NOT building (smart push mode)
FORCE_BUILD="${FORCE_BUILD:-false}"
# Legacy support: SKIP_BUILD=false means force build
if [ "${SKIP_BUILD:-true}" = "false" ]; then
  FORCE_BUILD="true"
fi

# Logging
log() {
  echo "[devcontainers] $(date '+%H:%M:%S') $*"
}

# Wait for Gitea registry to be ready
wait_for_gitea() {
  local timeout=300 elapsed=0 poll_interval=3
  log "Waiting for Gitea registry to be available..."

  # Phase 1: Wait for Gitea API
  while [ $elapsed -lt $timeout ]; do
    if curl -sk "https://${GITEA_REGISTRY}/api/v1/version" &>/dev/null; then
      log "Gitea API is ready (${elapsed}s)"
      break
    fi
    sleep $poll_interval
    elapsed=$((elapsed + poll_interval))
    if [ $((elapsed % 30)) -eq 0 ]; then
      log "Still waiting for Gitea API (${elapsed}s/${timeout}s)..."
    fi
  done

  if [ $elapsed -ge $timeout ]; then
    log "ERROR: Gitea API not ready after ${timeout}s"
    return 1
  fi

  # Phase 2: Wait for container registry v2 endpoint
  local registry_timeout=120 registry_elapsed=0
  log "Waiting for container registry endpoint..."
  while [ $registry_elapsed -lt $registry_timeout ]; do
    local status_code
    status_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://${GITEA_REGISTRY}/v2/")
    if [ "$status_code" = "401" ] || [ "$status_code" = "200" ]; then
      log "Container registry endpoint is ready (HTTP $status_code, ${registry_elapsed}s)"
      return 0
    fi
    sleep $poll_interval
    registry_elapsed=$((registry_elapsed + poll_interval))
    if [ $((registry_elapsed % 30)) -eq 0 ]; then
      log "Still waiting for registry endpoint (${registry_elapsed}s/${registry_timeout}s, last status: $status_code)..."
    fi
  done

  log "ERROR: Container registry endpoint not ready after ${registry_timeout}s"
  return 1
}

# Docker login to Gitea registry
docker_login() {
  log "Logging in to Gitea registry..."
  if echo "${GITEA_PASSWORD}" | docker login "${GITEA_REGISTRY}" -u "${GITEA_USER}" --password-stdin 2>/dev/null; then
    log "Docker login successful"
    return 0
  else
    log "ERROR: Docker login failed"
    return 1
  fi
}

# Check if image exists locally
image_exists() {
  local name="$1"
  local tag="${GITEA_REGISTRY}/${GITEA_USER}/${name}:latest"
  docker image inspect "$tag" &>/dev/null
}

# Build a devcontainer image
build_image() {
  local name="$1"
  local dockerfile="$2"
  local tag="${GITEA_REGISTRY}/${GITEA_USER}/${name}:latest"

  # Check if image already exists locally
  if image_exists "$name"; then
    if [ "$FORCE_BUILD" = "true" ]; then
      log "Image $name exists locally, rebuilding (FORCE_BUILD=true)..."
    else
      log "Image $name exists locally, skipping build"
      return 0
    fi
  elif [ "$FORCE_BUILD" != "true" ]; then
    log "Image $name not found locally (use --build to create)"
    return 1
  fi

  log "Building $name..."
  if docker build -t "$tag" -f "${DEVCONTAINERS_DIR}/${dockerfile}" "${DEVCONTAINERS_DIR}"; then
    log "Built $name successfully"
    return 0
  else
    log "ERROR: Failed to build $name"
    return 1
  fi
}

# Push a devcontainer image
push_image() {
  local name="$1"
  local tag="${GITEA_REGISTRY}/${GITEA_USER}/${name}:latest"

  log "Pushing $name..."
  local retry=0 max_retries=3
  while [ $retry -lt $max_retries ]; do
    if docker push "$tag" 2>&1; then
      log "Pushed $name successfully"
      return 0
    fi
    retry=$((retry + 1))
    if [ $retry -lt $max_retries ]; then
      log "Push failed, retrying ($retry/$max_retries)..."
      sleep $((retry * 2))
    fi
  done

  log "ERROR: Failed to push $name after $max_retries attempts"
  return 1
}

# Build and push a single image
# Returns: 0=success, 1=failed, 2=skipped (image not found locally)
build_and_push() {
  local name="$1"
  local dockerfile="$2"

  # In smart mode, check if image exists before attempting anything
  if [ "$FORCE_BUILD" != "true" ] && ! image_exists "$name"; then
    log "Skipping $name (not found locally, use --build to create)"
    return 2  # Skipped, not an error
  fi

  build_image "$name" "$dockerfile" || return 1
  push_image "$name" || return 1
  return 0
}

# Main execution
main() {
  local target="${1:-all}"

  # Handle help flags
  if [ "$target" = "--help" ] || [ "$target" = "-h" ]; then
    echo "Usage: $0 [--build] [all|nodejs|python|hybrid]"
    echo ""
    echo "Push shared devcontainer images to Gitea registry."
    echo ""
    echo "SMART MODE (default): Only pushes images that already exist locally."
    echo "This is ideal for cluster-recreate where images were previously built."
    echo ""
    echo "Images:"
    echo "  nodejs  - Node.js 22 only (for Next.js apps)"
    echo "  python  - Python 3.12 only (for FastAPI apps)"
    echo "  hybrid  - Node.js 22 + Python 3.12 (for agent apps)"
    echo "  all     - All existing images (default)"
    echo ""
    echo "Options:"
    echo "  --build       Force build images before push (slower)"
    echo "  --skip-build  Legacy: same as default (push existing only)"
    echo ""
    echo "Environment variables:"
    echo "  GITEA_REGISTRY   Registry host (default: gitea.cnoe.localtest.me:8443)"
    echo "  GITEA_USER       Registry user (default: giteaadmin)"
    echo "  GITEA_PASSWORD   Registry password (default: developer)"
    echo "  FORCE_BUILD      Force docker build (default: false)"
    echo "  SKIP_DEVCONTAINER_PUSH  Skip entirely in cluster-menu.sh"
    echo ""
    echo "Examples:"
    echo "  $0                    # Push all existing images to Gitea"
    echo "  $0 --build all        # Build and push all images"
    echo "  $0 nodejs             # Push nodejs only (if exists locally)"
    exit 0
  fi

  # Handle --build flag (force build)
  if [ "$target" = "--build" ]; then
    FORCE_BUILD=true
    target="${2:-all}"
  fi

  # Handle legacy --skip-build flag (now the default behavior)
  if [ "$target" = "--skip-build" ]; then
    FORCE_BUILD=false
    target="${2:-all}"
  fi

  log "=== DevContainer Push Script ==="
  log "Registry: ${GITEA_REGISTRY}"
  log "User: ${GITEA_USER}"
  log "Target: ${target}"
  log "Mode: $([ "$FORCE_BUILD" = "true" ] && echo "build + push" || echo "push existing only")"

  # Check if devcontainers directory exists
  if [ ! -d "$DEVCONTAINERS_DIR" ]; then
    log "ERROR: Devcontainers directory not found: $DEVCONTAINERS_DIR"
    exit 1
  fi

  # Wait for registry and login
  wait_for_gitea || exit 1
  docker_login || exit 1

  # Build and push based on target
  # Track results: pushed, skipped, failed
  local pushed=0 skipped=0 failed=0
  local result

  process_image() {
    local name="$1"
    local dockerfile="$2"
    build_and_push "$name" "$dockerfile"
    result=$?
    case $result in
      0) pushed=$((pushed + 1)) ;;
      2) skipped=$((skipped + 1)) ;;
      *) failed=$((failed + 1)) ;;
    esac
  }

  case "$target" in
    nodejs|node)
      process_image "nodejs-22-devspace" "Dockerfile.nodejs-22"
      ;;
    python|py)
      process_image "python-312-devspace" "Dockerfile.python-312"
      ;;
    hybrid|both)
      process_image "nodejs-python-devspace" "Dockerfile.nodejs-python"
      ;;
    all)
      process_image "nodejs-22-devspace" "Dockerfile.nodejs-22"
      process_image "python-312-devspace" "Dockerfile.python-312"
      process_image "nodejs-python-devspace" "Dockerfile.nodejs-python"
      ;;
    *)
      log "Usage: $0 [--build] [all|nodejs|python|hybrid]"
      log ""
      log "Images:"
      log "  nodejs  - Node.js 22 only (for Next.js apps)"
      log "  python  - Python 3.12 only (for FastAPI apps)"
      log "  hybrid  - Node.js 22 + Python 3.12 (for agent apps)"
      log "  all     - All images (default)"
      exit 1
      ;;
  esac

  log ""
  log "=== DevContainer Push Summary ==="
  log "  Pushed:  $pushed"
  log "  Skipped: $skipped (not found locally)"
  log "  Failed:  $failed"

  if [ $pushed -gt 0 ]; then
    log ""
    log "Images available in Gitea registry:"
    image_exists "nodejs-22-devspace" && log "  ${GITEA_REGISTRY}/${GITEA_USER}/nodejs-22-devspace:latest"
    image_exists "python-312-devspace" && log "  ${GITEA_REGISTRY}/${GITEA_USER}/python-312-devspace:latest"
    image_exists "nodejs-python-devspace" && log "  ${GITEA_REGISTRY}/${GITEA_USER}/nodejs-python-devspace:latest"
  fi

  if [ $skipped -gt 0 ] && [ $pushed -eq 0 ]; then
    log ""
    log "No images were pushed. To build images first, run:"
    log "  $0 --build all"
    log "Or build manually:"
    log "  cd ${DEVCONTAINERS_DIR} && bash build-push.sh all"
  fi

  if [ $failed -gt 0 ]; then
    exit 1
  fi
}

main "$@"
