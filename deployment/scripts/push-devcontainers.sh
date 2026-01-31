#!/usr/bin/env bash
# Push shared devcontainer images to Gitea registry
#
# This script builds and pushes the shared devcontainer images used by DevSpace.
# It waits for Gitea registry to be ready before pushing.
#
# Usage:
#   ./push-devcontainers.sh              # Build and push all (default)
#   ./push-devcontainers.sh all          # Build and push all
#   ./push-devcontainers.sh nodejs       # Build and push Node.js only
#   ./push-devcontainers.sh python       # Build and push Python only
#   ./push-devcontainers.sh hybrid       # Build and push hybrid only
#   ./push-devcontainers.sh --skip-build # Push only (assumes images already built)
#
# Environment variables:
#   GITEA_REGISTRY  Registry host (default: gitea.cnoe.localtest.me:8443)
#   GITEA_USER      Registry user (default: giteaadmin)
#   GITEA_PASSWORD  Registry password (default: giteaAdmin)
#   SKIP_BUILD      Skip docker build, only push (default: false)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${STACKS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DEVCONTAINERS_DIR="${STACKS_DIR}/devcontainers"

# Registry configuration
GITEA_REGISTRY="${GITEA_REGISTRY:-gitea.cnoe.localtest.me:8443}"
GITEA_USER="${GITEA_USER:-giteaadmin}"
# Default password matches idpbuilder's --dev-password default
GITEA_PASSWORD="${GITEA_PASSWORD:-developer}"

# Build control
SKIP_BUILD="${SKIP_BUILD:-false}"

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

# Build a devcontainer image
build_image() {
  local name="$1"
  local dockerfile="$2"
  local tag="${GITEA_REGISTRY}/${GITEA_USER}/${name}:latest"

  if [ "$SKIP_BUILD" = "true" ]; then
    log "Skipping build for $name (SKIP_BUILD=true)"
    return 0
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
build_and_push() {
  local name="$1"
  local dockerfile="$2"

  build_image "$name" "$dockerfile" || return 1
  push_image "$name" || return 1
}

# Main execution
main() {
  local target="${1:-all}"

  # Handle help flags
  if [ "$target" = "--help" ] || [ "$target" = "-h" ]; then
    echo "Usage: $0 [all|nodejs|python|hybrid] [--skip-build]"
    echo ""
    echo "Build and push shared devcontainer images to Gitea registry."
    echo ""
    echo "Images:"
    echo "  nodejs  - Node.js 22 only (for Next.js apps)"
    echo "  python  - Python 3.12 only (for FastAPI apps)"
    echo "  hybrid  - Node.js 22 + Python 3.12 (for agent apps)"
    echo "  all     - All images (default)"
    echo ""
    echo "Options:"
    echo "  --skip-build  Push only (assumes images already built)"
    echo ""
    echo "Environment variables:"
    echo "  GITEA_REGISTRY   Registry host (default: gitea.cnoe.localtest.me:8443)"
    echo "  GITEA_USER       Registry user (default: giteaadmin)"
    echo "  GITEA_PASSWORD   Registry password (default: giteaAdmin)"
    echo "  SKIP_BUILD       Skip docker build (default: false)"
    echo "  SKIP_DEVCONTAINER_PUSH  Skip entirely in cluster-menu.sh"
    exit 0
  fi

  # Handle --skip-build flag
  if [ "$target" = "--skip-build" ]; then
    SKIP_BUILD=true
    target="${2:-all}"
  fi

  log "=== DevContainer Push Script ==="
  log "Registry: ${GITEA_REGISTRY}"
  log "User: ${GITEA_USER}"
  log "Target: ${target}"
  log "Skip build: ${SKIP_BUILD}"

  # Check if devcontainers directory exists
  if [ ! -d "$DEVCONTAINERS_DIR" ]; then
    log "ERROR: Devcontainers directory not found: $DEVCONTAINERS_DIR"
    exit 1
  fi

  # Wait for registry and login
  wait_for_gitea || exit 1
  docker_login || exit 1

  # Build and push based on target
  local failed=0
  case "$target" in
    nodejs|node)
      build_and_push "nodejs-22-devspace" "Dockerfile.nodejs-22" || failed=1
      ;;
    python|py)
      build_and_push "python-312-devspace" "Dockerfile.python-312" || failed=1
      ;;
    hybrid|both)
      build_and_push "nodejs-python-devspace" "Dockerfile.nodejs-python" || failed=1
      ;;
    all)
      build_and_push "nodejs-22-devspace" "Dockerfile.nodejs-22" || failed=1
      build_and_push "python-312-devspace" "Dockerfile.python-312" || failed=1
      build_and_push "nodejs-python-devspace" "Dockerfile.nodejs-python" || failed=1
      ;;
    *)
      log "Usage: $0 [all|nodejs|python|hybrid] [--skip-build]"
      log ""
      log "Images:"
      log "  nodejs  - Node.js 22 only (for Next.js apps)"
      log "  python  - Python 3.12 only (for FastAPI apps)"
      log "  hybrid  - Node.js 22 + Python 3.12 (for agent apps)"
      log "  all     - All images (default)"
      exit 1
      ;;
  esac

  if [ $failed -eq 0 ]; then
    log ""
    log "=== DevContainers pushed successfully ==="
    log "Available images:"
    log "  ${GITEA_REGISTRY}/${GITEA_USER}/nodejs-22-devspace:latest"
    log "  ${GITEA_REGISTRY}/${GITEA_USER}/python-312-devspace:latest"
    log "  ${GITEA_REGISTRY}/${GITEA_USER}/nodejs-python-devspace:latest"
  else
    log ""
    log "=== Some devcontainers failed to push ==="
    exit 1
  fi
}

main "$@"
