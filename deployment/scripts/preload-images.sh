#!/usr/bin/env bash
# Preload images from Docker cache into KIND cluster and Gitea registry
# Usage: preload-images.sh <cluster-name>
# Runs async in background during cluster-deploy/cluster-recreate
#
# This script:
# 1. Checks Docker daemon for cached images (ai-chatbot, backstage, open-swe-*)
# 2. Pushes images to Gitea registry (primary - pods pull from here)
# 3. Optionally loads into KIND containerd (for local-only images)
# 4. Triggers Kargo warehouse refresh for immediate promotion
#
# Optimizations:
# - Processes small images first (ai-chatbot before open-swe-agent)
# - Parallel pushes for faster overall completion
# - Skips KIND load for registry-tagged images (pods pull from Gitea)
#
# Environment:
#   SKIP_IMAGE_PRELOAD=true    Skip preloading entirely
#   WAIT_IMAGE_PRELOAD=true    Run synchronously (blocking)
#   PARALLEL_JOBS=3            Number of parallel image pushes (default: 3)

set -euo pipefail

# Fix for "no space left on device" error when loading large images
# /run/user/1000 is tmpfs with limited space; use /tmp instead
export TMPDIR="${TMPDIR:-/tmp}"

CLUSTER_NAME="${1:-$(hostname -s)}"
LOG_PREFIX="[preload-images]"
GITEA_REGISTRY="gitea.cnoe.localtest.me:8443"
GITEA_ORG="giteaadmin"
PRELOADED_FILE="/tmp/preloaded-images-$$.txt"
PARALLEL_JOBS="${PARALLEL_JOBS:-3}"

# Target images to preload with priority (lower = higher priority, processed first)
# Priority based on: 1) Pod startup criticality, 2) Image size (smaller = faster)
# Format: "name:priority"
IMAGES_ORDERED=(
  "ai-chatbot:1"           # ~285MB - critical for demo, small
  "open-swe-web:2"         # ~270MB - UI, small
  "backstage:3"            # ~1.2GB - developer portal
  "backstage-devspace:4"   # devcontainer image
  "open-swe-devspace:5"    # ~3.3GB - devcontainer image
  "open-swe-agent:6"       # ~4.5GB - largest, process last
)

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"; }

cleanup() {
  # Kill any background jobs
  jobs -p | xargs -r kill 2>/dev/null || true
  rm -f "$PRELOADED_FILE" /tmp/preload-*.log 2>/dev/null || true
}
trap cleanup EXIT

wait_for_gitea() {
  local timeout=300 elapsed=0
  log "Waiting for Gitea registry to be available..."

  # Phase 1: Wait for Gitea API to respond
  while [ $elapsed -lt $timeout ]; do
    if curl -sk "https://${GITEA_REGISTRY}/api/v1/version" &>/dev/null; then
      log "Gitea API is ready"
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    if [ $((elapsed % 30)) -eq 0 ]; then
      log "Still waiting for Gitea API (${elapsed}s/${timeout}s)..."
    fi
  done

  if [ $elapsed -ge $timeout ]; then
    log "WARNING: Gitea API not ready after ${timeout}s"
    return 1
  fi

  # Phase 2: Wait for container registry v2 endpoint (nginx routing must be ready)
  # This ensures the registry is ready for container image pushes
  local registry_timeout=120 registry_elapsed=0
  log "Waiting for container registry endpoint..."
  while [ $registry_elapsed -lt $registry_timeout ]; do
    # Check if registry v2 endpoint responds (returns 401 Unauthorized, which is expected)
    local status_code
    status_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://${GITEA_REGISTRY}/v2/")
    if [ "$status_code" = "401" ] || [ "$status_code" = "200" ]; then
      log "Container registry endpoint is ready (HTTP $status_code)"
      return 0
    fi
    sleep 5
    registry_elapsed=$((registry_elapsed + 5))
    if [ $((registry_elapsed % 30)) -eq 0 ]; then
      log "Still waiting for registry endpoint (${registry_elapsed}s/${registry_timeout}s, last status: $status_code)..."
    fi
  done

  log "WARNING: Container registry endpoint not ready after ${registry_timeout}s"
  return 1
}

get_gitea_credentials() {
  # Try to get credentials from Kubernetes secret first
  local password=""
  password=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -n "$password" ]; then
    export GITEA_USER="giteaAdmin"
    export GITEA_PASSWORD="$password"
    log "Got Gitea credentials from Kubernetes secret"
    return 0
  fi

  # Fallback to idpbuilder dev password
  export GITEA_USER="giteaAdmin"
  export GITEA_PASSWORD="developer"
  log "Using default idpbuilder dev credentials"
  return 0
}

# Get image size in MB for logging
get_image_size_mb() {
  local image="$1"
  local size_bytes
  size_bytes=$(docker inspect "$image" --format='{{.Size}}' 2>/dev/null || echo "0")
  echo $((size_bytes / 1024 / 1024))
}

# Check if image is tagged for Gitea registry
is_gitea_tagged() {
  local image="$1"
  [[ "$image" == "${GITEA_REGISTRY}/"* ]]
}

preload_image() {
  local name="$1"
  local gitea_image="${GITEA_REGISTRY}/${GITEA_ORG}/${name}"

  # Find image in Docker daemon (check multiple patterns)
  # Images may be tagged as:
  #   - gitea.cnoe.localtest.me:8443/giteaadmin/<name>:<tag>
  #   - ghcr.io/pittampalliorg/<name>:<tag>
  #   - <name>:<tag> (local build)
  local local_image
  local_image=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | \
    grep -E "(/${name}:|^${name}:)" | \
    grep -v '<none>' | \
    head -1 || true)

  if [ -z "$local_image" ]; then
    log "SKIP: $name - not in Docker cache"
    return 0
  fi

  local tag
  tag=$(echo "$local_image" | rev | cut -d: -f1 | rev)
  local size_mb
  size_mb=$(get_image_size_mb "$local_image")
  log "FOUND: $local_image (${size_mb}MB)"

  # OPTIMIZATION: Skip KIND load for Gitea-tagged images
  # Pods pull from Gitea registry, not local containerd
  # Only load to KIND for locally-built images (not registry-tagged)
  if ! is_gitea_tagged "$local_image"; then
    log "Loading into KIND cluster '$CLUSTER_NAME'..."
    if kind load docker-image --name "$CLUSTER_NAME" "$local_image" 2>&1; then
      log "Loaded into KIND: $local_image"
    else
      log "WARNING: Failed to load into KIND (cluster may not be ready)"
    fi
  else
    log "Skipping KIND load (image already tagged for Gitea registry)"
  fi

  # Push to Gitea registry via skopeo
  log "Pushing to Gitea registry..."
  if skopeo copy --dest-tls-verify=false \
    --dest-creds "${GITEA_USER}:${GITEA_PASSWORD}" \
    "docker-daemon:${local_image}" \
    "docker://${gitea_image}:${tag}" 2>&1; then
    log "Pushed to Gitea: ${gitea_image}:${tag}"
    echo "$name" >> "$PRELOADED_FILE"
    return 0
  else
    log "WARNING: Failed to push to Gitea (skopeo error)"
    return 1
  fi
}

# Process a single image (for parallel execution)
process_image_async() {
  local name="$1"
  local log_file="/tmp/preload-${name}.log"

  {
    preload_image "$name"
  } > "$log_file" 2>&1

  # Output log content with prefix
  while IFS= read -r line; do
    echo "$line"
  done < "$log_file"
}

trigger_kargo_refresh() {
  if [ ! -f "$PRELOADED_FILE" ]; then
    log "No images preloaded, skipping Kargo refresh"
    return 0
  fi

  log "Triggering Kargo warehouse refresh..."

  # Map images to warehouses
  # Note: ai-chatbot doesn't have a warehouse yet (not in Kargo pipeline)
  declare -A WAREHOUSES=(
    ["open-swe-web"]="open-swe-web"
    ["open-swe-agent"]="open-swe-agent"
    ["backstage"]="backstage-local"
  )

  # Wait for kargo-pipelines namespace to exist (warehouses created by ArgoCD)
  local ns_timeout=120 ns_elapsed=0
  while ! kubectl get namespace kargo-pipelines &>/dev/null; do
    if [ $ns_elapsed -ge $ns_timeout ]; then
      log "WARNING: kargo-pipelines namespace not found after ${ns_timeout}s, skipping refresh"
      return 0
    fi
    sleep 5
    ns_elapsed=$((ns_elapsed + 5))
  done

  local refreshed=0
  local warehouse_timeout=60  # Per-warehouse wait timeout

  for name in $(cat "$PRELOADED_FILE"); do
    local warehouse="${WAREHOUSES[$name]:-}"
    if [ -n "$warehouse" ]; then
      log "Refreshing warehouse: $warehouse"

      # Wait for warehouse to exist with timeout
      local wh_elapsed=0
      while ! kubectl get warehouse "$warehouse" -n kargo-pipelines &>/dev/null; do
        if [ $wh_elapsed -ge $warehouse_timeout ]; then
          log "WARNING: Warehouse '$warehouse' not found after ${warehouse_timeout}s (ArgoCD may still be syncing)"
          break
        fi
        sleep 5
        wh_elapsed=$((wh_elapsed + 5))
        if [ $((wh_elapsed % 15)) -eq 0 ]; then
          log "  Waiting for warehouse '$warehouse' (${wh_elapsed}s/${warehouse_timeout}s)..."
        fi
      done

      # Try to refresh if warehouse exists
      if kubectl annotate warehouse "$warehouse" \
        -n kargo-pipelines \
        refresh="$(date +%s)" \
        --overwrite 2>/dev/null; then
        refreshed=$((refreshed + 1))
      fi
    fi
  done

  if [ $refreshed -gt 0 ]; then
    log "Refreshed $refreshed warehouse(s)"
  else
    log "No warehouses refreshed (images pushed to Gitea, Kargo will detect on next poll)"
  fi
}

show_summary() {
  if [ -f "$PRELOADED_FILE" ]; then
    local count
    count=$(wc -l < "$PRELOADED_FILE")
    log "SUCCESS: Preloaded $count image(s)"
    log "Images: $(cat "$PRELOADED_FILE" | tr '\n' ' ')"
  else
    log "No images were preloaded (none found in Docker cache)"
  fi
}

main() {
  log "Starting image preload for cluster: $CLUSTER_NAME"
  log "Processing order (priority): ${IMAGES_ORDERED[*]}"
  log "Parallel jobs: $PARALLEL_JOBS"
  log ""

  # Check prerequisites
  if ! command -v docker &>/dev/null; then
    log "ERROR: docker not found"
    return 1
  fi
  if ! command -v kind &>/dev/null; then
    log "ERROR: kind not found"
    return 1
  fi
  if ! command -v skopeo &>/dev/null; then
    log "ERROR: skopeo not found"
    return 1
  fi

  # Wait for Gitea before pushing
  wait_for_gitea || return 1

  # Get Gitea credentials for registry push
  get_gitea_credentials

  # Extract image names in priority order
  local images_by_priority=()
  for entry in "${IMAGES_ORDERED[@]}"; do
    local name="${entry%%:*}"
    images_by_priority+=("$name")
  done

  log ""
  log "=== Phase 1: High-priority images (sequential for fast pod startup) ==="
  # Process first 2 images sequentially to ensure they're available ASAP
  local high_priority_count=2
  for ((i=0; i<high_priority_count && i<${#images_by_priority[@]}; i++)); do
    local name="${images_by_priority[$i]}"
    log ""
    preload_image "$name"
  done

  log ""
  log "=== Phase 2: Remaining images (parallel for throughput) ==="
  # Process remaining images in parallel
  local pids=()
  local parallel_count=0

  for ((i=high_priority_count; i<${#images_by_priority[@]}; i++)); do
    local name="${images_by_priority[$i]}"

    # Start background job
    (
      log ""
      preload_image "$name"
    ) &
    pids+=($!)
    parallel_count=$((parallel_count + 1))

    # Limit parallel jobs
    if [ $parallel_count -ge $PARALLEL_JOBS ]; then
      # Wait for at least one job to complete
      wait -n 2>/dev/null || wait "${pids[0]}"
      # Remove completed PIDs (simplified - just reset and track active)
      parallel_count=$((parallel_count - 1))
    fi
  done

  # Wait for all remaining background jobs
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  log ""
  trigger_kargo_refresh

  log ""
  show_summary
  log "Image preload complete"
}

main
