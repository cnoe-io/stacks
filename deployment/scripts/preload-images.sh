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
GITEA_REGISTRY="gitea.cnoe.localtest.me"
GITEA_ORG="giteaadmin"
PRELOADED_FILE="/tmp/preloaded-images-$$.txt"
# Increased from 3 to 4 for faster parallel image pushes
# Modern systems can handle 4-6 parallel pushes safely
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"; }

# Dynamically discover images from built manifests
# Scans packages/dist/<env>/ for image references matching gitea.cnoe.localtest.me
# Returns unique image:tag pairs that need to be pushed to Gitea
# Output format: full image reference with tag (e.g., gitea.cnoe.localtest.me/giteaadmin/ai-chatbot:latest)
discover_gitea_images() {
  local stacks_dir="${STACKS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
  local build_env="kind-${CLUSTER_NAME}"
  local dist_dir="${stacks_dir}/packages/dist/${build_env}"

  # Fallback to kind if host-specific build doesn't exist
  if [ ! -d "$dist_dir" ]; then
    dist_dir="${stacks_dir}/packages/dist/kind"
  fi

  if [ ! -d "$dist_dir" ]; then
    # Log to stderr since stdout is captured
    echo "WARNING: No dist directory found at $dist_dir" >&2
    return 1
  fi

  # Log to stderr since stdout is captured for image list
  echo "Scanning $dist_dir for Gitea image references..." >&2

  # Extract unique image references from manifests
  # Search in */manifests/ subdirectories for Deployment YAML files
  # Pattern: gitea.cnoe.localtest.me/giteaadmin/<name>:<tag>
  # Note: Preserves the requested tag from manifests (e.g., :latest)
  find "$dist_dir" -path "*/manifests/*.yaml" -exec grep -h "image:.*${GITEA_REGISTRY}" {} \; 2>/dev/null | \
    sed -E 's/.*image:\s*//; s/["\x27]//g; s/\s*$//' | \
    grep -E "^${GITEA_REGISTRY}/" | \
    sort -u
}

# Get image size for priority sorting (smaller images first for faster startup)
get_image_size_bytes() {
  local image="$1"
  docker inspect "$image" --format='{{.Size}}' 2>/dev/null || echo "999999999999"
}

# Build prioritized image list dynamically
# Returns array of "image_name:requested_tag:found_tag:size_bytes" entries sorted by size (to stdout)
# Logs progress to stderr
# The requested_tag is preserved from manifests (e.g., :latest) for proper tag aliasing
# The found_tag is the actual tag in Docker cache (e.g., :v1.7.4)
build_image_list() {
  local images=()

  # Get all Gitea images from manifests
  while IFS= read -r full_image; do
    [ -z "$full_image" ] && continue

    # Add :latest tag if no tag specified
    case "$full_image" in
      *:*) ;;
      *) full_image="${full_image}:latest" ;;
    esac

    # Extract just the name:tag part (without registry/org prefix)
    local name_tag="${full_image#${GITEA_REGISTRY}/${GITEA_ORG}/}"
    local name="${name_tag%%:*}"
    local requested_tag="${name_tag##*:}"

    # Find matching image in Docker (may have different tag than requested)
    # Check exact match first, then search for any version tag
    local local_image=""
    local found_tag=""

    if docker image inspect "$full_image" &>/dev/null; then
      # Exact match exists
      local_image="$full_image"
      found_tag="$requested_tag"
    else
      # Search for image with any tag matching this name
      local_image=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | \
        grep -E "(/${name}:|^${name}:)" | \
        grep -v '<none>' | \
        head -1 || true)
      if [ -n "$local_image" ]; then
        found_tag=$(echo "$local_image" | rev | cut -d: -f1 | rev)
      fi
    fi

    if [ -n "$local_image" ]; then
      local size
      size=$(get_image_size_bytes "$local_image")
      # Format: name:requested_tag:found_tag:size
      images+=("${name}:${requested_tag}:${found_tag}:${size}")
      if [ "$requested_tag" != "$found_tag" ]; then
        echo "  Found: $name ($(echo "$size" | awk '{printf "%.0fMB", $1/1024/1024}')) [manifest: :${requested_tag}, docker: :${found_tag}]" >&2
      else
        echo "  Found: $name ($(echo "$size" | awk '{printf "%.0fMB", $1/1024/1024}'))" >&2
      fi
    else
      echo "  Skip: $name - not in Docker cache" >&2
    fi
  done < <(discover_gitea_images)

  # Sort by size (smaller first, size is 4th field) and return entries
  printf '%s\n' "${images[@]}" | sort -t: -k4 -n
}

# IMAGES_ORDERED will be populated dynamically in main()
IMAGES_ORDERED=()

cleanup() {
  # Kill any background jobs
  jobs -p | xargs -r kill 2>/dev/null || true
  rm -f "$PRELOADED_FILE" /tmp/preload-*.log 2>/dev/null || true
}
trap cleanup EXIT

wait_for_gitea() {
  local timeout=300 elapsed=0 poll_interval=3
  log "Waiting for Gitea registry to be available..."

  # Phase 1: Wait for Gitea API to respond
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
      log "Container registry endpoint is ready (HTTP $status_code, ${registry_elapsed}s)"
      return 0
    fi
    sleep $poll_interval
    registry_elapsed=$((registry_elapsed + poll_interval))
    if [ $((registry_elapsed % 30)) -eq 0 ]; then
      log "Still waiting for registry endpoint (${registry_elapsed}s/${registry_timeout}s, last status: $status_code)..."
    fi
  done

  log "WARNING: Container registry endpoint not ready after ${registry_timeout}s"
  return 1
}

get_gitea_credentials() {
  # Get and verify Gitea credentials with retry logic
  # Auth may fail initially during cluster creation as Gitea restarts
  local max_attempts=10
  local attempt=1
  local password=""

  while [ $attempt -le $max_attempts ]; do
    # Try to get credentials from Kubernetes secret first
    password=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

    if [ -z "$password" ]; then
      # Fallback to gitops dev password
      password="developer"
    fi

    export GITEA_USER="giteaadmin"
    export GITEA_PASSWORD="$password"

    # Verify credentials work by testing API auth
    local auth_status
    auth_status=$(curl -sk -o /dev/null -w "%{http_code}" -u "${GITEA_USER}:${GITEA_PASSWORD}" \
      "https://${GITEA_REGISTRY}/api/v1/user")

    if [ "$auth_status" = "200" ]; then
      log "Got Gitea credentials from Kubernetes secret (verified)"
      return 0
    fi

    # Auth failed - Gitea might be restarting, wait and retry
    if [ $attempt -lt $max_attempts ]; then
      log "Auth verification failed (HTTP $auth_status), waiting 10s... (attempt $attempt/$max_attempts)"
      sleep 10
    fi
    attempt=$((attempt + 1))
  done

  log "WARNING: Could not verify Gitea credentials after $max_attempts attempts"
  log "Using credentials anyway - pushes may fail"
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
  local requested_tag="${2:-latest}"  # Tag from manifest (e.g., :latest)
  local found_tag="${3:-}"            # Tag found in Docker (e.g., :v1.7.4)
  local gitea_image="${GITEA_REGISTRY}/${GITEA_ORG}/${name}"

  # Find image in Docker daemon (check multiple patterns)
  # Images may be tagged as:
  #   - gitea.cnoe.localtest.me/giteaadmin/<name>:<tag>
  #   - ghcr.io/pittampalliorg/<name>:<tag>
  #   - <name>:<tag> (local build)
  local local_image=""
  if [ -n "$found_tag" ]; then
    local_image=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | \
      grep -E "(/${name}:${found_tag}$|^${name}:${found_tag}$)" | \
      grep -v '<none>' | \
      head -1 || true)
  fi
  if [ -z "$local_image" ] && [ -n "$requested_tag" ]; then
    local_image=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | \
      grep -E "(/${name}:${requested_tag}$|^${name}:${requested_tag}$)" | \
      grep -v '<none>' | \
      head -1 || true)
  fi
  if [ -z "$local_image" ]; then
    local_image=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | \
      grep -E "(/${name}:|^${name}:)" | \
      grep -v '<none>' | \
      head -1 || true)
  fi

  if [ -z "$local_image" ]; then
    log "SKIP: $name - not in Docker cache"
    return 0
  fi

  # Use found_tag from caller if provided, otherwise extract from image
  if [ -z "$found_tag" ]; then
    found_tag=$(echo "$local_image" | rev | cut -d: -f1 | rev)
  fi
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

  # Push to Gitea registry via skopeo with retry logic
  # Auth can fail mid-push during parallel operations; retry with fresh credentials
  local max_retries=3
  local retry=0
  local push_success=false

  while [ $retry -lt $max_retries ] && [ "$push_success" = "false" ]; do
    if [ $retry -gt 0 ]; then
      log "Retry $retry/$max_retries: Refreshing credentials and retrying push..."
      sleep $((retry * 5))  # Exponential backoff: 5s, 10s, 15s

      # Refresh credentials - they may have changed or token expired
      local new_password
      new_password=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
      if [ -n "$new_password" ]; then
        export GITEA_PASSWORD="$new_password"
      fi
    fi

    log "Pushing to Gitea registry as :${found_tag}..."
    local push_output
    push_output=$(skopeo copy --dest-tls-verify=false \
      --dest-creds "${GITEA_USER}:${GITEA_PASSWORD}" \
      "docker-daemon:${local_image}" \
      "docker://${gitea_image}:${found_tag}" 2>&1) && push_success=true

    if [ "$push_success" = "true" ]; then
      log "Pushed to Gitea: ${gitea_image}:${found_tag}"

      # Push with requested tag as alias if different from found tag
      # This ensures pods requesting :latest can pull the image
      if [ "$requested_tag" != "$found_tag" ]; then
        log "Also tagging as :${requested_tag} (manifest requested this tag)..."
        local alias_output
        if alias_output=$(skopeo copy --dest-tls-verify=false \
          --dest-creds "${GITEA_USER}:${GITEA_PASSWORD}" \
          "docker-daemon:${local_image}" \
          "docker://${gitea_image}:${requested_tag}" 2>&1); then
          log "Pushed alias: ${gitea_image}:${requested_tag}"
        else
          log "WARNING: Failed to push alias tag :${requested_tag}: $(echo "$alias_output" | tail -1)"
        fi
      fi

      echo "$name" >> "$PRELOADED_FILE"
      return 0
    fi

    # Check if it's an auth error (worth retrying) vs other error
    if echo "$push_output" | grep -qE "authentication required|unauthorized|invalid username"; then
      log "Auth error detected, will retry with fresh credentials"
      retry=$((retry + 1))
    else
      # Non-auth error (EOF, network, etc.) - also retry but log differently
      log "Push error: $(echo "$push_output" | tail -1)"
      retry=$((retry + 1))
    fi
  done

  log "WARNING: Failed to push to Gitea after $max_retries attempts"
  return 1
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

  # Build WAREHOUSES mapping dynamically from images.yaml (single source of truth)
  # plus special cases for images managed outside kargo-inner-loop
  local stacks_dir="${STACKS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
  local images_yaml="${stacks_dir}/packages/base/manifests/kargo-inner-loop/images.yaml"

  declare -A WAREHOUSES=(
    # Special cases: images managed by other Kargo pipelines or with different warehouse names
    ["open-swe-web"]="open-swe-web"
    ["open-swe-agent"]="open-swe-agent"
    ["backstage"]="backstage-local"  # Managed by kargo-backstage-pipeline
  )

  # Dynamically add warehouses from images.yaml (kargo-inner-loop apps)
  if [ -f "$images_yaml" ] && command -v yq &>/dev/null; then
    local image_count
    image_count=$(yq '.images | length' "$images_yaml" 2>/dev/null || echo 0)
    for i in $(seq 0 $((image_count - 1))); do
      local name image_repo warehouse
      name=$(yq -r ".images[$i].name" "$images_yaml")
      image_repo=$(yq -r ".images[$i].imageName // .images[$i].name" "$images_yaml")
      # Use warehouseName if specified, otherwise default to name
      warehouse=$(yq -r ".images[$i].warehouseName // .images[$i].name" "$images_yaml")
      if [ -n "$name" ] && [ "$name" != "null" ] && [ -n "$image_repo" ] && [ "$image_repo" != "null" ]; then
        # Key by actual image repository name discovered from manifests (e.g. opencode-durable-agent),
        # map to warehouse/stage identity (e.g. durable-agent).
        WAREHOUSES["$image_repo"]="$warehouse"
      fi
    done
    log "Loaded ${image_count} warehouse mappings from images.yaml"
  else
    log "WARNING: images.yaml not found or yq not available, using hardcoded mappings only"
  fi

  # Wait for kargo-pipelines namespace to exist (warehouses created by ArgoCD)
  local ns_timeout=120 ns_elapsed=0 poll_interval=3
  while ! kubectl get namespace kargo-pipelines &>/dev/null; do
    if [ $ns_elapsed -ge $ns_timeout ]; then
      log "WARNING: kargo-pipelines namespace not found after ${ns_timeout}s, skipping refresh"
      return 0
    fi
    sleep $poll_interval
    ns_elapsed=$((ns_elapsed + poll_interval))
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
        sleep $poll_interval
        wh_elapsed=$((wh_elapsed + poll_interval))
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

  # Dynamically discover and build image list from manifests
  log "Discovering images from Kubernetes manifests..."
  while IFS= read -r entry; do
    [ -n "$entry" ] && IMAGES_ORDERED+=("$entry")
  done < <(build_image_list)

  if [ ${#IMAGES_ORDERED[@]} -eq 0 ]; then
    log "No Gitea images found in manifests or Docker cache"
    log "Manifests scanned, but no matching images in local Docker"
    return 0
  fi

  # Separate images into small (<500MB) and large (>=500MB) for processing strategy
  # Entry format: name:requested_tag:found_tag:size
  local small_images=()
  local large_images=()
  local LARGE_IMAGE_THRESHOLD=$((500 * 1024 * 1024))  # 500MB in bytes

  log "Discovered ${#IMAGES_ORDERED[@]} images to preload:"
  for entry in "${IMAGES_ORDERED[@]}"; do
    # Parse entry: name:requested_tag:found_tag:size
    local name requested_tag found_tag size
    name=$(echo "$entry" | cut -d: -f1)
    requested_tag=$(echo "$entry" | cut -d: -f2)
    found_tag=$(echo "$entry" | cut -d: -f3)
    size=$(echo "$entry" | cut -d: -f4)
    local size_mb=$((size / 1024 / 1024))

    # Store as "name:requested_tag:found_tag" for processing
    local image_info="${name}:${requested_tag}:${found_tag}"

    if [ "$size" -lt "$LARGE_IMAGE_THRESHOLD" ]; then
      small_images+=("$image_info")
      if [ "$requested_tag" != "$found_tag" ]; then
        log "  - $name (${size_mb}MB) [parallel] [:${requested_tag} alias for :${found_tag}]"
      else
        log "  - $name (${size_mb}MB) [parallel]"
      fi
    else
      large_images+=("$image_info")
      if [ "$requested_tag" != "$found_tag" ]; then
        log "  - $name (${size_mb}MB) [sequential - large] [:${requested_tag} alias for :${found_tag}]"
      else
        log "  - $name (${size_mb}MB) [sequential - large]"
      fi
    fi
  done
  log ""

  log ""
  log "=== Phase 1: Small images (parallel for speed) ==="
  log "Processing ${#small_images[@]} small images with $PARALLEL_JOBS parallel jobs..."

  # Process small images in parallel
  local pids=()
  local parallel_count=0

  for image_info in "${small_images[@]}"; do
    # Parse image_info: name:requested_tag:found_tag
    local name requested_tag found_tag
    name=$(echo "$image_info" | cut -d: -f1)
    requested_tag=$(echo "$image_info" | cut -d: -f2)
    found_tag=$(echo "$image_info" | cut -d: -f3)

    # Start background job
    (
      log ""
      preload_image "$name" "$requested_tag" "$found_tag"
    ) &
    pids+=($!)
    parallel_count=$((parallel_count + 1))

    # Limit parallel jobs
    if [ $parallel_count -ge $PARALLEL_JOBS ]; then
      # Wait for at least one job to complete
      wait -n 2>/dev/null || wait "${pids[0]}"
      parallel_count=$((parallel_count - 1))
    fi
  done

  # Wait for all small image jobs to complete before starting large images
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  log ""
  log "=== Phase 2: Large images (sequential for reliability) ==="
  log "Processing ${#large_images[@]} large images sequentially..."

  # Process large images sequentially to avoid auth/connection issues
  for image_info in "${large_images[@]}"; do
    # Parse image_info: name:requested_tag:found_tag
    local name requested_tag found_tag
    name=$(echo "$image_info" | cut -d: -f1)
    requested_tag=$(echo "$image_info" | cut -d: -f2)
    found_tag=$(echo "$image_info" | cut -d: -f3)

    log ""
    preload_image "$name" "$requested_tag" "$found_tag"
  done

  log ""
  trigger_kargo_refresh

  log ""
  show_summary
  log "Image preload complete"
}

main
