#!/usr/bin/env bash
# Cluster management functions for stacks project
# Source this file or run directly to access cluster-* functions

# Automatically detect repository root (works in Codespaces, local, CI)
if [ -z "$STACKS_DIR" ]; then
  # Try git root first (most reliable)
  if STACKS_DIR=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$STACKS_DIR" ]; then
    export STACKS_DIR
  # Fallback: derive from script location
  elif [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    export STACKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  # Last resort: common paths
  elif [ -d "/workspaces/stacks" ]; then
    export STACKS_DIR="/workspaces/stacks"
  elif [ -d "/workspace/stacks" ]; then
    export STACKS_DIR="/workspace/stacks"
  elif [ -d "$HOME/stacks" ]; then
    export STACKS_DIR="$HOME/stacks"
  else
    echo "❌ Could not detect STACKS_DIR. Please set it manually: export STACKS_DIR=/path/to/stacks"
    return 1 2>/dev/null || exit 1
  fi
fi

custom_bundle="$STACKS_DIR/scripts/certificates/system/ca-bundle-with-idpbuilder.crt"
if [ -f "$custom_bundle" ]; then
  export SSL_CERT_FILE="$custom_bundle"
  export NIX_SSL_CERT_FILE="$custom_bundle"
fi

# Source ArgoCD authentication helper
ARGOCD_AUTH_SCRIPT="$STACKS_DIR/deployment/scripts/argocd-auth.sh"
if [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
  source "$ARGOCD_AUTH_SCRIPT"
fi

# Source NixOS KubeVirt helper (build-nixos-image, nixos-vm-status, etc.)
NIXOS_KUBEVIRT_SCRIPT="$STACKS_DIR/deployment/scripts/nixos-kubevirt.sh"
if [ -f "$NIXOS_KUBEVIRT_SCRIPT" ]; then
  source "$NIXOS_KUBEVIRT_SCRIPT"
fi

# 1Password service account helper
load-1password-token() {
  # Load 1Password service account token from Azure Key Vault for automated access
  if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    # Check if Azure Key Vault has the token
    if command -v az &>/dev/null && az account show &>/dev/null 2>&1; then
      local token=$(az keyvault secret show \
        --vault-name "${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}" \
        --name "ONEPASSWORD-SERVICE-ACCOUNT-TOKEN" \
        --query value -o tsv 2>/dev/null)

      if [ -n "$token" ]; then
        export OP_SERVICE_ACCOUNT_TOKEN="$token"
        return 0
      fi
    fi

    # Fallback: check if token file exists locally
    if [ -f "/tmp/op-service-account-token.txt" ]; then
      export OP_SERVICE_ACCOUNT_TOKEN=$(cat /tmp/op-service-account-token.txt)
      return 0
    fi
  fi
  return 1
}

# Sync applications that have auto-sync disabled (e.g., backstage for devspace compatibility)
# Called after cluster creation to ensure all apps get initial sync
# Waits for key dependencies (keycloak) before triggering syncs
sync-manual-apps() {
  if ! command -v argocd &>/dev/null; then
    echo "⚠️  argocd CLI not found - skipping manual app sync"
    return 0
  fi

  # Ensure we have ArgoCD auth
  if [ -z "$ARGOCD_AUTH_TOKEN" ]; then
    echo "⚠️  ARGOCD_AUTH_TOKEN not set - skipping manual app sync"
    return 0
  fi

  echo "🔄 Syncing applications without auto-sync..."

  # Wait for keycloak to be healthy (backstage depends on keycloak-clients secret)
  # This secret is created by keycloak-config job after keycloak is ready
  local timeout=180
  local interval=5  # Reduced from 10s for faster startup
  local elapsed=0

  echo "   Waiting for keycloak dependencies (up to ${timeout}s)..."
  while [ $elapsed -lt $timeout ]; do
    # Check if keycloak app is healthy
    local keycloak_health=$(kubectl get application keycloak -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)

    # Check if keycloak-clients secret exists (created by keycloak-config job)
    local secret_exists=$(kubectl get secret keycloak-clients -n keycloak --no-headers 2>/dev/null | wc -l)

    if [ "$keycloak_health" = "Healthy" ] && [ "$secret_exists" -gt 0 ]; then
      echo "   ✓ Keycloak healthy and keycloak-clients secret exists"
      break
    fi

    # Show progress
    if [ "$keycloak_health" != "Healthy" ]; then
      echo "   Keycloak: ${keycloak_health:-Unknown} (${elapsed}s/${timeout}s)"
    elif [ "$secret_exists" -eq 0 ]; then
      echo "   Waiting for keycloak-clients secret (${elapsed}s/${timeout}s)"
    fi

    sleep $interval
    elapsed=$((elapsed + interval))
  done

  if [ $elapsed -ge $timeout ]; then
    echo "   ⚠️  Timeout waiting for keycloak dependencies - syncing anyway"
  fi

  # Find apps that are OutOfSync AND don't have automated sync policy
  local manual_apps=$(kubectl get applications -n argocd -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.syncPolicy.automated == null and .status.sync.status == "OutOfSync") | .metadata.name' 2>/dev/null)

  if [ -z "$manual_apps" ]; then
    echo "   No manual apps need syncing"
    return 0
  fi

  local synced=0
  local failed=0
  for app in $manual_apps; do
    echo "   Syncing: $app"
    if argocd app sync "argocd/$app" --insecure --async --timeout 300 2>/dev/null; then
      synced=$((synced + 1))
    else
      echo "   ⚠️  Failed to sync: $app"
      failed=$((failed + 1))
    fi
  done

  if [ $synced -gt 0 ]; then
    echo "✅ Triggered sync for $synced manual app(s)"
  fi
  if [ $failed -gt 0 ]; then
    echo "⚠️  Failed to sync $failed app(s) - may need manual intervention"
  fi
}

# Known hosts that can run Kind clusters
KNOWN_HOSTS=(thinkpad ryzen hetzner)

# Detect current hostname with validation against known hosts
detect_hostname() {
  # Allow override via environment variable (for CI/testing)
  local detected_host="${CLUSTER_HOST:-$(hostname)}"

  # Validate against known hosts
  local is_known=false
  for known in "${KNOWN_HOSTS[@]}"; do
    if [[ "$detected_host" == "$known" ]]; then
      is_known=true
      break
    fi
  done

  if [ "$is_known" = false ]; then
    echo "❌ Unknown host: $detected_host" >&2
    echo "   Supported hosts: ${KNOWN_HOSTS[*]}" >&2
    echo "" >&2
    echo "For CI or custom environments, set:" >&2
    echo "  export CLUSTER_HOST=<hostname>" >&2
    return 1
  fi

  echo "$detected_host"
}

# Azure authentication helper functions
detect_host_context() {
  # Detect hostname first
  local hostname
  hostname="$(detect_hostname 2>/dev/null)"

  # If we have a hostname, look for matching context
  if [ -n "$hostname" ]; then
    local expected_ctx="kind-${hostname}"
    if kubectl config get-contexts -o name 2>/dev/null | grep -q "^${expected_ctx}$"; then
      echo "$expected_ctx"
      return 0
    fi
  fi

  # Fallback: Find any kind-* context (backward compatibility)
  local ctx
  ctx=$(kubectl config get-contexts -o name 2>/dev/null | grep '^kind-' | tail -1)
  if [ -z "$ctx" ]; then
    ctx=$(kubectl config current-context 2>/dev/null || echo "")
  fi
  echo "$ctx"
}

# Derive the Kind cluster name from hostname
detect_cluster_name() {
  local hostname
  hostname="$(detect_hostname)" || return 1
  echo "$hostname"
}

# Check for legacy 'localdev' cluster and offer migration
check_legacy_cluster() {
  # Check if old 'localdev' cluster exists
  if kind get clusters 2>/dev/null | grep -q "^localdev$"; then
    local hostname
    hostname="$(detect_hostname 2>/dev/null)"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  LEGACY CLUSTER DETECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Found existing 'localdev' cluster. New deployment will use hostname-based naming."
    echo ""
    echo "Expected cluster name: ${hostname}"
    echo "Current cluster:       localdev"
    echo ""
    echo "Migration options:"
    echo "  1. Delete old cluster: idpbuilder delete --name localdev"
    echo "  2. Keep both clusters: They can coexist with different contexts"
    echo ""
    echo -n "Delete 'localdev' cluster and continue? [y/N] "
    read -r -t 10 -n 1 response || response="n"
    echo ""

    if [[ "$response" =~ ^[Yy]$ ]]; then
      echo "🗑️  Deleting localdev cluster..."
      idpbuilder delete --name localdev || kind delete cluster --name localdev
      echo "✅ Legacy cluster deleted"
      echo ""
    else
      echo ""
      echo "Keeping both clusters. Use kubectl context to switch:"
      echo "  kubectl config use-context kind-localdev"
      echo "  kubectl config use-context kind-${hostname}"
      echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi
}

check-azure-auth() {
  # Check Azure authentication status - only prompts if not automated
  # Skip if SKIP_AZURE_AUTH is set (for local development)
  if [ "${SKIP_AZURE_AUTH:-}" = "true" ]; then
    echo "⏭️  Skipping Azure authentication check (SKIP_AZURE_AUTH=true)"
    return 0
  fi

  local token_expiry=$(az account get-access-token --query "expiresOn" -o tsv 2>/dev/null || echo "")

  if [ -z "$token_expiry" ]; then
    # Not logged in
    echo "❌ Azure authentication required"
    echo "💡 Please authenticate with: az login"
    echo ""
    echo "For local development without Azure integration:"
    echo "  export SKIP_AZURE_AUTH=true"
    echo ""
    echo "For automation, consider:"
    echo "  - Service Principal: az login --service-principal -u <app-id> -p <password> --tenant <tenant>"
    echo "  - Managed Identity: Available automatically in Azure VMs/Container Instances"
    echo "  - GitHub Actions: Use azure/login@v1 action"
    return 1
  fi

  # Check token expiry
  local current_time=$(date +%s)
  local expiry_time=$(date -d "$token_expiry" +%s 2>/dev/null || echo 0)
  local time_diff=$((expiry_time - current_time))

  if [ $time_diff -lt 300 ]; then
    echo "⚠️  Azure token expires soon (${time_diff}s remaining)"
    echo "💡 Refresh with: az login"
    # Continue anyway - might still work
  else
    local account=$(az account show --query "user.name" -o tsv 2>/dev/null)
    echo "✅ Authenticated as: $account (token valid for ${time_diff}s)"
  fi

  return 0
}

# Ensure kustomize packages are ready
ensure-kustomize-ready() {
  # Check if kustomize or kubectl (with kustomize built-in) is available
  if ! command -v kustomize &>/dev/null && ! command -v kubectl &>/dev/null; then
    echo "❌ kustomize or kubectl required"
    return 1
  fi

  # Check if packages directory exists
  if [[ ! -d "$STACKS_DIR/packages" ]]; then
    echo "❌ packages/ directory not found"
    return 1
  fi

  return 0
}

# Build kustomize packages for idpBuilder
kustomize-build() {
  local ENV="${1:-kind}"
  local DETECTED_HOST
  DETECTED_HOST="$(detect_hostname 2>/dev/null)" || DETECTED_HOST=""

  # Derive build environment (kind-thinkpad, kind-ryzen, etc.)
  local BUILD_ENV="$ENV"
  if [[ "$ENV" == "kind" ]] && [[ -n "$DETECTED_HOST" ]]; then
    BUILD_ENV="kind-${DETECTED_HOST}"
    echo "🏷️  Detected host: ${DETECTED_HOST} -> using environment: ${BUILD_ENV}"
  fi

  # Export for use in idpbuilder -p flag
  export KUSTOMIZE_BUILD_ENV="$BUILD_ENV"

  echo "🔨 Building kustomize packages for $BUILD_ENV..."

  # Source environment variables (Azure credentials, etc.)
  if [ -f "$STACKS_DIR/.env-files/kind.env" ] && [[ "$ENV" == "kind"* ]]; then
    echo "📋 Loading environment from kind.env..."
    source "$STACKS_DIR/.env-files/kind.env"
  fi

  cd "$STACKS_DIR/packages"

  # Check if yq-go is available, otherwise wrap with nix-shell
  local BUILD_CMD="make build-kustomize-${BUILD_ENV}"
  local BUILD_SUCCESS=false

  if command -v yq &>/dev/null && yq --version 2>&1 | grep -q "mikefarah"; then
    # yq-go available (inside devenv or installed globally)
    $BUILD_CMD 2>&1 && BUILD_SUCCESS=true
  elif command -v nix-shell &>/dev/null; then
    # Use nix-shell to provide yq-go
    nix-shell -p yq-go --run "$BUILD_CMD" 2>&1 && BUILD_SUCCESS=true
  else
    echo "❌ yq-go required. Install via: nix-shell -p yq-go, or run inside devenv shell"
    return 1
  fi

  if $BUILD_SUCCESS; then
    local APP_COUNT=$(ls -1 "dist/${BUILD_ENV}"/*.yaml 2>/dev/null | wc -l)
    echo "✅ Build complete: ${APP_COUNT} applications in packages/dist/${BUILD_ENV}/"
    return 0
  else
    echo "❌ Kustomize build failed"
    return 1
  fi
}

# Legacy: Stub for backwards compatibility
ensure-cdk8s-dependencies() {
  ensure-kustomize-ready
}

# Generate kind-config.yaml from template with STACKS_DIR substitution
generate-kind-config() {
  local TEMPLATE_FILE="$STACKS_DIR/deployment/config/kind-config.yaml.template"
  local OUTPUT_FILE="$STACKS_DIR/deployment/config/kind-config.yaml"

  if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "⚠️  kind-config.yaml.template not found, using existing kind-config.yaml"
    return 0
  fi

  echo "📝 Generating kind-config.yaml from template..."

  # Ensure containerd config directory exists
  mkdir -p "$STACKS_DIR/deployment/config/containerd"

  # Setup registry authentication (docker.io, ghcr.io, gitea)
  local REGISTRY_AUTH_SCRIPT="$STACKS_DIR/deployment/scripts/setup-registry-auth.sh"
  if [ -f "$REGISTRY_AUTH_SCRIPT" ]; then
    "$REGISTRY_AUTH_SCRIPT"
  fi

  # Substitute STACKS_DIR in template using sed (envsubst not always available)
  sed "s|\${STACKS_DIR}|$STACKS_DIR|g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"

  echo "✅ Generated kind-config.yaml with STACKS_DIR=$STACKS_DIR"
}

# Fix /etc/hosts on KIND nodes for gitea.cnoe.localtest.me resolution
# Required because containerd on KIND nodes doesn't use CoreDNS, it uses node's /etc/hosts
# Without this, *.localtest.me resolves to ::1 (localhost) and image pulls fail
fix-kind-hosts() {
  local CLUSTER_NAME="${1:-$(detect_hostname)}"

  echo "🔧 Fixing /etc/hosts on KIND nodes for gitea.cnoe.localtest.me..."

  # Get the ingress-nginx ClusterIP
  local INGRESS_IP
  INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

  if [ -z "$INGRESS_IP" ]; then
    echo "⚠️  Could not get ingress-nginx ClusterIP, skipping hosts fix"
    return 0
  fi

  echo "   Ingress ClusterIP: $INGRESS_IP"

  # Find all KIND nodes for this cluster
  local nodes
  nodes=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${CLUSTER_NAME}-(control|worker)" || true)

  if [ -z "$nodes" ]; then
    echo "⚠️  No KIND nodes found for cluster: $CLUSTER_NAME"
    return 0
  fi

  # Add /etc/hosts entry to each node (idempotent)
  for node in $nodes; do
    docker exec "$node" sh -c "grep -q 'gitea.cnoe.localtest.me' /etc/hosts || echo '$INGRESS_IP gitea.cnoe.localtest.me' >> /etc/hosts" 2>/dev/null
    echo "   ✅ Updated $node"
  done

  echo "✅ KIND nodes /etc/hosts fixed for Gitea OCI registry access"
}

# Ensure Kargo pipeline repositories exist in Gitea with correct host-suffix
# Kargo stages reference host-specific repos (e.g., idpbuilder-thinkpad-backstage-manifests)
# These repos must exist before Kargo can promote images
ensure-kargo-repos() {
  local CLUSTER_NAME="${1:-$(detect_hostname 2>/dev/null)}"

  if [ -z "$CLUSTER_NAME" ]; then
    echo "⚠️  Could not detect hostname, skipping Kargo repo setup"
    return 0
  fi

  echo "🔧 Ensuring Kargo repositories exist for host: $CLUSTER_NAME"

  # Get Gitea credentials
  local GITEA_PASSWORD
  GITEA_PASSWORD=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -z "$GITEA_PASSWORD" ]; then
    echo "⚠️  Could not get Gitea credentials, skipping Kargo repo setup"
    return 0
  fi

  local GITEA_URL="https://gitea.cnoe.localtest.me:8443"
  local GITEA_USER="giteaAdmin"

  # Repositories needed by Kargo pipelines (backstage outer-loop only, inner-loop uses main branch)
  local KARGO_REPOS=(
    "idpbuilder-${CLUSTER_NAME}-backstage-manifests"
  )

  for repo in "${KARGO_REPOS[@]}"; do
    # Check if repo exists
    local repo_exists
    repo_exists=$(curl -k -s -o /dev/null -w "%{http_code}" \
      -u "$GITEA_USER:$GITEA_PASSWORD" \
      "$GITEA_URL/api/v1/repos/$GITEA_USER/$repo")

    if [ "$repo_exists" = "200" ]; then
      echo "   ✅ Repository exists: $repo"
    else
      echo "   📦 Creating repository: $repo"
      if curl -k -s -X POST "$GITEA_URL/api/v1/user/repos" \
        -H "Content-Type: application/json" \
        -u "$GITEA_USER:$GITEA_PASSWORD" \
        -d "{\"name\": \"$repo\", \"private\": false, \"auto_init\": true}" \
        > /dev/null; then
        echo "   ✅ Created: $repo"
      else
        echo "   ⚠️  Failed to create: $repo"
      fi
    fi
  done

  echo "✅ Kargo repositories verified"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Nginx Override Generation
# ═══════════════════════════════════════════════════════════════════════════════

# generate-nginx-override: Generate nginx override file with persistent TLS if available
# Returns the path to the nginx override file via echo
# Uses: Azure Key Vault persistent TLS if available, otherwise falls back to simple override
generate-nginx-override() {
  local NGINX_OVERRIDE_SCRIPT="$STACKS_DIR/deployment/scripts/persistent-secrets/generate-nginx-override.sh"
  local NGINX_OVERRIDE_FILE=""

  if [ -f "$NGINX_OVERRIDE_SCRIPT" ]; then
    echo "🔐 Generating nginx override with persistent TLS certificate..." >&2
    NGINX_OVERRIDE_FILE=$("$NGINX_OVERRIDE_SCRIPT" 2>/dev/null) || NGINX_OVERRIDE_FILE=""

    if [ -n "$NGINX_OVERRIDE_FILE" ] && [ -f "$NGINX_OVERRIDE_FILE" ]; then
      echo "✅ Using persistent TLS certificate from Azure Key Vault" >&2
      echo "$NGINX_OVERRIDE_FILE"
      return 0
    else
      echo "⚠️  Persistent cert not available, using standard nginx override" >&2
    fi
  fi

  # Fallback to standard override
  echo "${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Portable Core - Manifest Application (no infrastructure dependencies)
# ═══════════════════════════════════════════════════════════════════════════════

# cluster-apply-manifests: Portable core for kustomize + idpbuilder
# This function contains the infrastructure-agnostic manifest application logic.
# It can be used by both cluster-deploy (full setup) and cluster-update (manifest only).
#
# Arguments:
#   $1 - nginx override file (optional, defaults to simple override)
#   $2 - argocd override file (optional, for CA trust injection)
#   $@ - additional args passed to idpbuilder (optional)
#
# Required environment:
#   CLUSTER_HOST - hostname for cluster naming (set before calling)
#   STACKS_DIR   - path to stacks repository
#
# Exports:
#   KUSTOMIZE_BUILD_ENV - the resolved build environment (e.g., kind-thinkpad)
#
cluster-apply-manifests() {
  local NGINX_OVERRIDE_FILE="${1:-${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml}"
  if [ $# -gt 0 ]; then
    shift
  fi
  local ARGOCD_OVERRIDE_FILE="${1:-}"
  if [ $# -gt 0 ]; then
    shift
  fi
  local GITEA_OVERRIDE_FILE="${GITEA_OVERRIDE_FILE:-${STACKS_DIR}/deployment/overrides/gitea-actions.yaml}"
  local DEPLOY_DIR="$STACKS_DIR/deployment"
  local ORIG_DIR="$(pwd)"

  # Validate required environment
  if [ -z "${CLUSTER_HOST:-}" ]; then
    echo "❌ CLUSTER_HOST not set. Call detect_hostname first."
    return 1
  fi

  local CLUSTER_NAME="$CLUSTER_HOST"

  # Source environment files (kind.env for KIND clusters)
  [ -f "$STACKS_DIR/.env-files/kind.env" ] && source "$STACKS_DIR/.env-files/kind.env"

  # Clear any WSL Docker environment variables
  if [[ -S /var/run/docker.sock ]]; then
    unset DOCKER_HOST
    unset DOCKER_TLS_VERIFY
    unset DOCKER_CERT_PATH
    export DOCKER_HOST=""
  fi

  # Ensure kustomize packages are ready
  echo "🔍 Checking kustomize packages..."
  ensure-kustomize-ready || { cd "$ORIG_DIR"; return 1; }

  # Build kustomize packages (sets KUSTOMIZE_BUILD_ENV)
  kustomize-build "kind" || { cd "$ORIG_DIR"; return 1; }

  # Generate kind-config.yaml from template with current STACKS_DIR
  generate-kind-config

  echo ""
  echo "🚀 Applying manifests to cluster: ${CLUSTER_NAME}..."
  echo ""

  # Detect if caller already provided a gitea override
  local HAS_GITEA_OVERRIDE="false"
  local prev_arg=""
  for arg in "$@"; do
    if [[ "$arg" == --package-custom-file=gitea:* ]] || [[ "$arg" == -c=gitea:* ]]; then
      HAS_GITEA_OVERRIDE="true"
      break
    fi
    if [[ "$prev_arg" == "--package-custom-file" || "$prev_arg" == "-c" ]] && [[ "$arg" == gitea:* ]]; then
      HAS_GITEA_OVERRIDE="true"
      break
    fi
    prev_arg="$arg"
  done

  # Build idpbuilder command with optional overrides
  local IDPBUILDER_ARGS=(
    --name "${CLUSTER_NAME}"
    -p "$STACKS_DIR/packages/dist/$KUSTOMIZE_BUILD_ENV/"
    --package-custom-file "nginx:${NGINX_OVERRIDE_FILE}"
    --kind-config "$DEPLOY_DIR/config/kind-config.yaml"
    --dev-password
  )

  # Add ArgoCD override if provided (for CA trust injection at creation time)
  if [ -n "$ARGOCD_OVERRIDE_FILE" ] && [ -f "$ARGOCD_OVERRIDE_FILE" ]; then
    echo "   Including ArgoCD CA trust configuration..."
    IDPBUILDER_ARGS+=(--package-custom-file "argocd:${ARGOCD_OVERRIDE_FILE}")
  fi

  # Add Gitea Actions override if present and not explicitly provided
  if [ "$HAS_GITEA_OVERRIDE" = "false" ] && [ -f "$GITEA_OVERRIDE_FILE" ]; then
    echo "   Including Gitea Actions configuration..."
    IDPBUILDER_ARGS+=(--package-custom-file "gitea:${GITEA_OVERRIDE_FILE}")
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # Background Image Preloading (runs in PARALLEL with idpbuilder)
  # Started AFTER kustomize-build so dist/ folder has the manifest files
  # The preload script has its own wait_for_gitea logic
  # ─────────────────────────────────────────────────────────────────────────────
  local IMAGE_PRELOAD_SCRIPT="$STACKS_DIR/deployment/scripts/preload-images.sh"
  local IMAGE_PRELOAD_LOG="/tmp/image-preload.log"
  if [ "${SKIP_IMAGE_PRELOAD:-}" != "true" ] && [ -f "$IMAGE_PRELOAD_SCRIPT" ]; then
    echo "🖼️  Starting background image preload (parallel with idpbuilder)..."
    (
      # Preload script waits for Gitea, discovers images from dist/, pushes to registry
      "$IMAGE_PRELOAD_SCRIPT" "$CLUSTER_NAME"
    ) > "$IMAGE_PRELOAD_LOG" 2>&1 &
    local IMAGE_PRELOAD_PID=$!
    echo "   Started background image preload (PID: $IMAGE_PRELOAD_PID)"
    echo "   Log: $IMAGE_PRELOAD_LOG"
    echo ""
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # Background DevContainer Push (runs in PARALLEL with idpbuilder and image preload)
  # Pushes existing devcontainer images to Gitea for DevSpace development.
  # SMART MODE: Only pushes images that already exist locally (no rebuild).
  # This is fast for cluster-recreate where images were previously built.
  # To force rebuild: FORCE_BUILD=true or use 'push-devcontainers --build all'
  # ─────────────────────────────────────────────────────────────────────────────
  local DEVCONTAINER_SCRIPT="$STACKS_DIR/deployment/scripts/push-devcontainers.sh"
  local DEVCONTAINER_LOG="/tmp/devcontainer-push.log"
  if [ "${SKIP_DEVCONTAINER_PUSH:-}" != "true" ] && [ -f "$DEVCONTAINER_SCRIPT" ]; then
    echo "🐳 Starting background devcontainer push (parallel with idpbuilder)..."
    echo "   Mode: push existing images only (use --build for rebuild)"
    (
      # DevContainer script waits for Gitea, pushes existing local images
      "$DEVCONTAINER_SCRIPT" all
    ) > "$DEVCONTAINER_LOG" 2>&1 &
    local DEVCONTAINER_PID=$!
    echo "   Started background devcontainer push (PID: $DEVCONTAINER_PID)"
    echo "   Log: $DEVCONTAINER_LOG"
    echo ""
  fi

  # Apply using idpbuilder (idempotent operation)
  # Any extra args ($@) are passed through to idpbuilder
  idpbuilder create "${IDPBUILDER_ARGS[@]}" "$@"

  local result=$?

  cd "$ORIG_DIR"
  return $result
}

# ═══════════════════════════════════════════════════════════════════════════════
# Base functions - always non-interactive
# ═══════════════════════════════════════════════════════════════════════════════

cluster-deploy() {
  # Full cluster creation with infrastructure setup
  # Uses portable core (cluster-apply-manifests) for manifest application
  # Infrastructure-specific: Azure TLS, CA injection, JWKS sync, Kargo repos, ArgoCD auth, Tailscale

  # Check if being called internally (skip auth check if SKIP_AZURE_CHECK is set)
  if [ "${SKIP_AZURE_CHECK:-}" != "true" ]; then
    echo "🔐 Checking Azure authentication..."
    check-azure-auth || return 1
    echo ""
  fi

  local DEPLOY_DIR="$STACKS_DIR/deployment"
  local ORIG_DIR="$(pwd)"

  # Source environment files FIRST (before any operations that need them)
  [ -f "$STACKS_DIR/.env-files/kind.env" ] && source "$STACKS_DIR/.env-files/kind.env"

  # Export hostname for cluster naming (required by cluster-apply-manifests)
  export CLUSTER_HOST="$(detect_hostname)" || { cd "$ORIG_DIR"; return 1; }
  echo "🏷️  Detected host: ${CLUSTER_HOST}"

  # Load 1Password service account token for automated secret access
  if command -v op &>/dev/null; then
    load-1password-token && echo "✅ 1Password service account token loaded"
  fi

  # Check for legacy cluster and handle migration
  check_legacy_cluster || { cd "$ORIG_DIR"; return 1; }

  # ─────────────────────────────────────────────────────────────────────────────
  # Infrastructure-specific: Generate nginx + ArgoCD overrides with persistent TLS
  # ─────────────────────────────────────────────────────────────────────────────
  local NGINX_OVERRIDE_SCRIPT="$STACKS_DIR/deployment/scripts/persistent-secrets/generate-nginx-override.sh"
  local NGINX_OVERRIDE_FILE="/tmp/nginx-override-with-cert.yaml"
  local ARGOCD_OVERRIDE_FILE="/tmp/argocd-override-with-ca.yaml"

  if [ -f "$NGINX_OVERRIDE_SCRIPT" ]; then
    echo "🔐 Generating nginx override with persistent TLS certificate..."
    NGINX_OVERRIDE_FILE=$("$NGINX_OVERRIDE_SCRIPT" 2>/dev/null) || NGINX_OVERRIDE_FILE="/tmp/nginx-override-with-cert.yaml"

    # Verify the override file was created
    if [ ! -f "$NGINX_OVERRIDE_FILE" ]; then
      echo "⚠️  Persistent cert not available, using standard nginx override"
      NGINX_OVERRIDE_FILE="${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml"
      ARGOCD_OVERRIDE_FILE=""
    else
      echo "✅ Using persistent TLS certificate from Azure Key Vault"
    fi
  else
    NGINX_OVERRIDE_FILE="${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml"
    ARGOCD_OVERRIDE_FILE=""
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # Background CA + TLS injection: Runs in parallel with idpbuilder
  # This patches ArgoCD CA trust and server TLS as soon as ArgoCD is ready,
  # rather than waiting for idpbuilder to complete. Required because:
  # - idpbuilder overwrites argocd-tls-certs-cm with its auto-generated cert
  # - ArgoCD uses ssl-passthrough, so it terminates TLS itself; the
  #   argocd-server-tls Secret ensures it presents the persistent CA cert
  #   instead of its auto-generated self-signed cert
  # ─────────────────────────────────────────────────────────────────────────────
  local ARGOCD_CA_PID=""
  if [ -n "$ARGOCD_OVERRIDE_FILE" ] && [ -f "$ARGOCD_OVERRIDE_FILE" ]; then
    (
      exec > /tmp/argocd-ca-injection.log 2>&1
      echo "$(date): Starting background ArgoCD CA + TLS injection..."

      # Wait for ArgoCD ConfigMap to exist (polling every 2s for faster startup)
      waited=0
      while ! kubectl get configmap argocd-tls-certs-cm -n argocd 2>/dev/null; do
        sleep 2
        waited=$((waited + 2))
        if [ $((waited % 10)) -eq 0 ]; then
          echo "$(date): Waiting for argocd-tls-certs-cm (${waited}s)..."
        fi
        if [ $waited -ge 300 ]; then
          echo "$(date): TIMEOUT waiting for argocd-tls-certs-cm"
          exit 1
        fi
      done

      echo "$(date): ConfigMap exists, applying custom CA trust and server TLS..."
      kubectl apply -f "$ARGOCD_OVERRIDE_FILE"

      echo "$(date): Restarting ArgoCD components..."
      kubectl rollout restart deployment argocd-server -n argocd
      kubectl rollout restart deployment argocd-repo-server -n argocd
      kubectl rollout restart statefulset argocd-application-controller -n argocd
      kubectl rollout status deployment argocd-server -n argocd --timeout=120s
      kubectl rollout status deployment argocd-repo-server -n argocd --timeout=120s

      echo "$(date): SUCCESS - ArgoCD CA trust and server TLS configured"
    ) &
    ARGOCD_CA_PID=$!
    echo "   Started background CA + TLS injection (PID: $ARGOCD_CA_PID, log: /tmp/argocd-ca-injection.log)"
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # NOTE: Image preloading is now handled inside cluster-apply-manifests()
  # It starts AFTER kustomize-build so the dist/ folder has manifest files
  # ─────────────────────────────────────────────────────────────────────────────
  # Apply manifests using portable core (cluster-apply-manifests)
  # ─────────────────────────────────────────────────────────────────────────────
  local result=0

  echo "🚀 Creating cluster with idpbuilder..."
  cluster-apply-manifests "$NGINX_OVERRIDE_FILE" "$ARGOCD_OVERRIDE_FILE" "$@"
  result=$?

  # Sync JWKS after cluster creation (infrastructure-specific)
  if [ $result -eq 0 ]; then
    local JWKS_SCRIPT="$STACKS_DIR/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh"
    if [ -f "$JWKS_SCRIPT" ]; then
      echo "🔄 Syncing JWKS to Azure for External Secrets..."
      "$JWKS_SCRIPT"
    fi
  fi

  # Wait for background CA injection to complete before ArgoCD auth init
  if [ -n "$ARGOCD_CA_PID" ]; then
    echo "   Waiting for background CA + TLS injection to complete..."
    wait "$ARGOCD_CA_PID" 2>/dev/null || true
  fi

  # ─────────────────────────────────────────────────────────────────────────────
  # Post-deployment infrastructure setup
  # ─────────────────────────────────────────────────────────────────────────────
  if [ $result -eq 0 ]; then
    fix-kind-hosts "${CLUSTER_HOST}"
    ensure-kargo-repos "${CLUSTER_HOST}"
  fi

  # Initialize ArgoCD authentication and save token to 1Password after successful deployment
  if [ $result -eq 0 ] && [ "${SKIP_ARGOCD_INIT:-}" != "true" ]; then
    echo ""
    echo "🔐 Initializing ArgoCD authentication and saving token..."

    # Brief wait for ArgoCD API to be ready (argocd-auth-init has retry logic)
    sleep 2

    # Initialize and save token
    if command -v argocd &>/dev/null && [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
      if argocd-auth-init; then
        echo "✅ ArgoCD authentication configured and token saved to 1Password"

        # Sync applications that have auto-sync disabled (e.g., backstage)
        # These apps won't deploy automatically and need an initial sync trigger
        sync-manual-apps
      else
        echo "⚠️  ArgoCD authentication initialization failed (may retry later)"
      fi
    fi
  fi

  # Generate Tailscale remote access token after deployment (ASYNC by default)
  # This runs in background to avoid blocking cluster-deploy for 5-10 minutes
  # Use WAIT_TAILSCALE_TOKEN=true to wait synchronously
  if [ $result -eq 0 ] && [ "${SKIP_TAILSCALE_TOKEN:-}" != "true" ]; then
    local TAILSCALE_KUBECONFIG_SCRIPT="$STACKS_DIR/deployment/scripts/tailscale/tailscale-kubeconfig.sh"
    local TAILSCALE_TOKEN_LOG="/tmp/tailscale-token-generation.log"
    if [ -f "$TAILSCALE_KUBECONFIG_SCRIPT" ]; then
      echo ""
      echo "🔑 Tailscale remote access token generation..."

      # Create async token generation script
      cat > /tmp/generate-tailscale-token.sh << TAILSCALE_SCRIPT
#!/usr/bin/env bash
set -x
exec > "$TAILSCALE_TOKEN_LOG" 2>&1
echo "\$(date): Starting Tailscale token generation..."

TIMEOUT=600
INTERVAL=30
ELAPSED=0
READY=false

while [ \$ELAPSED -lt \$TIMEOUT ]; do
  if kubectl wait --for=condition=available deployment/k8s-api-tailscale-serve -n tailscale --timeout=\${INTERVAL}s 2>/dev/null; then
    READY=true
    break
  fi
  ELAPSED=\$((ELAPSED + INTERVAL))
  echo "\$(date): Waiting for k8s-api-tailscale-serve (\${ELAPSED}s/\${TIMEOUT}s)..."
done

if [ "\$READY" = true ]; then
  sleep 2  # Brief wait for deployment stabilization
  if "$TAILSCALE_KUBECONFIG_SCRIPT" generate; then
    echo "\$(date): SUCCESS - Tailscale token generated and stored in Azure Key Vault"
  else
    echo "\$(date): FAILED - Token generation failed"
    exit 1
  fi
else
  echo "\$(date): TIMEOUT - k8s-api-tailscale-serve not ready after \${TIMEOUT}s"
  exit 1
fi
TAILSCALE_SCRIPT
      chmod +x /tmp/generate-tailscale-token.sh

      if [ "${WAIT_TAILSCALE_TOKEN:-}" = "true" ]; then
        # Synchronous mode: wait for completion
        echo "   Running synchronously (WAIT_TAILSCALE_TOKEN=true)..."
        if /tmp/generate-tailscale-token.sh; then
          echo "✅ Tailscale remote access token generated"
          echo "   Kubeconfig: ~/.kube/tailscale-cluster.yaml"
        else
          echo "⚠️  Tailscale token generation failed (check $TAILSCALE_TOKEN_LOG)"
        fi
      else
        # Async mode: run in background and return immediately
        /tmp/generate-tailscale-token.sh &
        local TAILSCALE_PID=$!
        echo "   Started background token generation (PID: $TAILSCALE_PID)"
        echo "   Log: $TAILSCALE_TOKEN_LOG"
        echo "   Check status: tail -f $TAILSCALE_TOKEN_LOG"
        echo "   Or wait: wait $TAILSCALE_PID && cat $TAILSCALE_TOKEN_LOG"
        echo ""
        echo "   ⏱️  This saves ~5-10 minutes - cluster-deploy returning immediately"
      fi
    fi
  fi

  cd "$ORIG_DIR"
  return $result
}

cluster-build() {
  local ORIG_DIR="$(pwd)"
  local ENV="${1:-kind}"

  # Clear any WSL Docker environment variables
  # Check if we have a native Docker socket
  if [[ -S /var/run/docker.sock ]]; then
    unset DOCKER_HOST
    unset DOCKER_TLS_VERIFY
    unset DOCKER_CERT_PATH
    export DOCKER_HOST=""
  fi

  [ -f "$STACKS_DIR/.env-files/kind.env" ] && source "$STACKS_DIR/.env-files/kind.env"

  # Ensure kustomize packages are ready
  echo "🔍 Checking kustomize packages..."
  ensure-kustomize-ready || { cd "$ORIG_DIR"; return 1; }

  # Build kustomize packages
  kustomize-build "$ENV"
  local result=$?

  cd "$ORIG_DIR"
  return $result
}

# Legacy alias for cluster-synth
cluster-synth() {
  cluster-build "$@"
}

cluster-recreate() {
  # Health check script for timing and summary
  local HEALTH_CHECK="$STACKS_DIR/deployment/scripts/cluster-health-check.sh"

  # Initialize timing
  if [ -f "$HEALTH_CHECK" ]; then
    "$HEALTH_CHECK" reset
    "$HEALTH_CHECK" start "total"
    "$HEALTH_CHECK" start "pre-flight"
  fi

  # Check Azure authentication first (required for JWKS sync)
  echo "🔐 Checking Azure authentication..."
  check-azure-auth || return 1
  echo ""

  # Clear any WSL Docker environment variables
  # Check if we have a native Docker socket
  if [[ -S /var/run/docker.sock ]]; then
    unset DOCKER_HOST
    unset DOCKER_TLS_VERIFY
    unset DOCKER_CERT_PATH
    export DOCKER_HOST=""
  fi

  # Start pre-fetching persistent TLS certificate from AKV in background
  # This runs in parallel with Tailscale cleanup to save time
  local NGINX_OVERRIDE_SCRIPT="$STACKS_DIR/deployment/scripts/persistent-secrets/generate-nginx-override.sh"
  local AKV_FETCH_PID=""
  if [ -f "$NGINX_OVERRIDE_SCRIPT" ]; then
    echo "🔐 Pre-fetching persistent TLS certificate from AKV (background)..."
    "$NGINX_OVERRIDE_SCRIPT" &>/dev/null &
    AKV_FETCH_PID=$!
  fi

  # Tailscale best practice: Clean up old devices before cluster recreation
  # This ensures new devices get canonical hostnames (no -1 suffix)
  # See: https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress
  #
  # Strategy: Async cleanup + delayed service deployment via ArgoCD sync waves
  # - Cleanup starts 120-second grace period for hostname release
  # - Tailscale LoadBalancer services deploy at sync wave 50 (~3-5 min into sync)
  # - Grace period completes well before LoadBalancer services are created
  # - Result: Canonical hostnames (argocd, kagent, etc.) without suffixes
  local CLEANUP_SCRIPT="$STACKS_DIR/deployment/scripts/tailscale/cleanup-old-devices.sh"
  if command -v tailscale &>/dev/null && [ -f "$CLEANUP_SCRIPT" ]; then
    echo "🧹 Cleaning up old Tailscale devices..."
    echo "   (Grace period will elapse before Tailscale services deploy at sync wave 50)"
    echo ""

    # Run cleanup WITHOUT --wait flag
    # LoadBalancer services delayed to sync wave 50 (~3-5 min into ArgoCD sync)
    # This ensures the 120-second grace period completes naturally
    if "$CLEANUP_SCRIPT"; then
      echo ""
      echo "✅ Tailscale devices deleted (grace period starts now)"
      echo "   LoadBalancer services will deploy at sync wave 50 (~3-5 min)"
    else
      echo ""
      echo "⚠️  Tailscale cleanup failed (continuing anyway)"
      echo "   New devices may get -3 suffix (e.g., kagent-3 instead of kagent)"
    fi
    echo ""
  else
    if [ ! -f "$CLEANUP_SCRIPT" ]; then
      echo "⚠️  Tailscale cleanup script not found"
    elif ! command -v tailscale &>/dev/null; then
      echo "⚠️  Tailscale CLI not found - skipping device cleanup"
    fi
    echo "   New devices may get -3 suffix (e.g., kagent-3 instead of kagent)"
    echo ""
  fi

  # Wait for AKV fetch to complete (should already be done after Tailscale cleanup)
  if [ -n "$AKV_FETCH_PID" ]; then
    wait "$AKV_FETCH_PID" 2>/dev/null || true
    echo "✅ Persistent TLS certificate pre-fetched"
  fi

  [ -f "$HEALTH_CHECK" ] && "$HEALTH_CHECK" end "pre-flight"

  # Detect cluster name from hostname
  local CLUSTER_NAME="$(detect_cluster_name)"
  if [ $? -ne 0 ] || [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Failed to detect cluster name"
    return 1
  fi

  [ -f "$HEALTH_CHECK" ] && "$HEALTH_CHECK" start "cluster-delete"
  echo "🗑️  Deleting cluster: ${CLUSTER_NAME}..."
  idpbuilder delete --name "${CLUSTER_NAME}"
  [ -f "$HEALTH_CHECK" ] && "$HEALTH_CHECK" end "cluster-delete"

  # Clear cached ArgoCD token since cluster is being recreated
  unset ARGOCD_AUTH_TOKEN

  echo ""
  echo "🔨 Creating fresh cluster..."

  [ -f "$HEALTH_CHECK" ] && "$HEALTH_CHECK" start "cluster-deploy"
  # cluster-deploy will handle ArgoCD initialization automatically
  SKIP_AZURE_CHECK=true cluster-deploy "$@"
  local deploy_result=$?
  [ -f "$HEALTH_CHECK" ] && "$HEALTH_CHECK" end "cluster-deploy"

  # Wait for cluster to stabilize and show summary
  if [ -f "$HEALTH_CHECK" ]; then
    "$HEALTH_CHECK" start "stabilization"
    echo ""
    echo "⏳ Waiting for cluster to stabilize..."
    sleep 30  # Give apps time to start syncing

    # Wait up to 5 minutes for cluster to be ready
    "$HEALTH_CHECK" wait 300 || true

    "$HEALTH_CHECK" end "stabilization"
    "$HEALTH_CHECK" end "total"

    # Print final summary
    "$HEALTH_CHECK" summary
  fi

  return $deploy_result
}

cluster-update-gum() {
  # Interactive gum-based update with real-time feedback
  if ! command -v gum &>/dev/null; then
    echo "❌ gum is required for interactive mode"
    echo "Install with: nix-env -iA nixpkgs.gum"
    echo "Or use: cluster-update (non-interactive)"
    return 1
  fi

  local PACKAGES_DIR="$STACKS_DIR/packages"
  local HOST_CONTEXT="$(detect_host_context)"
  local ORIG_DIR="$(pwd)"
  local DEPLOY_DIR="$STACKS_DIR/deployment"
  local CLUSTER_MENU_SCRIPT="$STACKS_DIR/deployment/scripts/cluster-menu.sh"

  if [ "${SKIP_AZURE_CHECK:-}" != "true" ]; then
    gum style --foreground 45 "🔐 Checking Azure authentication..."
    if ! check-azure-auth; then
      gum style --foreground 196 "❌ Azure authentication required"
      return 1
    fi
    echo ""
  fi

  # Source environment files FIRST (kind.env for KIND clusters)
  [ -f "$STACKS_DIR/.env-files/kind.env" ] && {
    gum style --foreground 45 "📋 Loading environment from kind.env..."
    source "$STACKS_DIR/.env-files/kind.env"
  }

  # Export hostname for synthesis (host-aware Tailscale names)
  export CLUSTER_HOST="$(detect_hostname)" || return 1
  local CLUSTER_NAME="$CLUSTER_HOST"
  gum style --foreground 45 "🏷️  Detected host: ${CLUSTER_HOST}"

  if command -v op &>/dev/null; then
    if load-1password-token; then
      gum style --foreground 82 "✅ 1Password service account token loaded"
    fi
  fi

  # Clear any WSL Docker environment variables
  if [[ -S /var/run/docker.sock ]]; then
    unset DOCKER_HOST
    unset DOCKER_TLS_VERIFY
    unset DOCKER_CERT_PATH
    export DOCKER_HOST=""
  fi

  # Check if cluster exists
  if [ -z "$HOST_CONTEXT" ] || ! kubectl --context "$HOST_CONTEXT" cluster-info &>/dev/null; then
    gum style --foreground 196 "❌ No cluster found. Please create a cluster first with 'cld' or 'cluster-deploy'"
    return 1
  fi

  if [ -n "$HOST_CONTEXT" ]; then
    kubectl config use-context "$HOST_CONTEXT" >/dev/null 2>&1 || true
  fi

  # Ensure kustomize packages are ready
  gum spin --spinner dot --title "🔍 Checking kustomize packages..." -- \
    env STACKS_DIR="$STACKS_DIR" bash -lc "source '$CLUSTER_MENU_SCRIPT'; ensure-kustomize-ready >/dev/null 2>&1"

  if [ $? -ne 0 ]; then
    gum style --foreground 196 "❌ Failed to ensure kustomize packages are ready"
    return 1
  fi

  # Step 1: Build with spinner (includes restructuring for idpBuilder)
  gum spin --spinner dot --title "🔨 Building kustomize packages..." -- \
    env STACKS_DIR="$STACKS_DIR" bash -lc "source '$CLUSTER_MENU_SCRIPT'; kustomize-build kind >/dev/null 2>&1"

  if [ $? -ne 0 ]; then
    gum style --foreground 196 "❌ Kustomize build failed"
    kustomize-build "kind"
    cd "$ORIG_DIR"
    return 1
  fi

  gum style --foreground 82 "✅ Synthesis complete"

  # Generate kind-config.yaml from template with current STACKS_DIR
  generate-kind-config

  # Step 2: Update cluster with spinner
  # Ensure build env is set in this shell (gum runs build in a subshell)
  export KUSTOMIZE_BUILD_ENV="kind-${CLUSTER_NAME}"
  local GITEA_OVERRIDE_FILE="${STACKS_DIR}/deployment/overrides/gitea-actions.yaml"
  local GITEA_CUSTOM_ARG=""
  if [ -f "$GITEA_OVERRIDE_FILE" ]; then
    GITEA_CUSTOM_ARG="--package-custom-file 'gitea:${GITEA_OVERRIDE_FILE}'"
  fi
  gum spin --spinner dot --title "🚀 Updating cluster: ${CLUSTER_NAME} (idempotent)..." -- \
    bash -lc "idpbuilder create --name '$CLUSTER_NAME' -p '$STACKS_DIR/packages/dist/$KUSTOMIZE_BUILD_ENV/' --package-custom-file 'nginx:${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml' ${GITEA_CUSTOM_ARG} --kind-config '$DEPLOY_DIR/config/kind-config.yaml' --dev-password >/dev/null 2>&1"

  if [ $? -ne 0 ]; then
    gum style --foreground 196 "❌ Cluster update failed"
    return 1
  fi

  gum style --foreground 82 "✅ Cluster updated"

  # Step 3: Check ArgoCD applications
  gum style --foreground 45 "📊 Checking ArgoCD application status..."
  echo ""

  local apps=$(kubectl get applications -n argocd -o name 2>/dev/null | wc -l)
  if [ $apps -gt 0 ]; then
    # Show status with gum table
    kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status,\
MESSAGE:.status.conditions[0].message | \
      gum format

    echo ""
    gum style --foreground 82 "💡 Monitor detailed sync progress:"
    gum style --foreground 250 "   ArgoCD UI: https://argocd.cnoe.localtest.me:8443"
  else
    gum style --foreground 214 "⚠️  No ArgoCD applications found yet"
  fi

  cd "$ORIG_DIR"
  gum style --foreground 82 "✨ Update complete!"
}

cluster-update() {
  # Update existing cluster with idpbuilder (idempotent operation)
  # Uses portable core (cluster-apply-manifests) for manifest application
  local HOST_CONTEXT="$(detect_host_context)"
  local NO_EXIT=""
  local ORIG_DIR="$(pwd)"

  # Check for --no-exit flag
  if [[ "$1" == "--no-exit" ]]; then
    NO_EXIT="--no-exit"
    shift
  fi

  # Optional Azure auth check (for environment variables)
  if [ "${SKIP_AZURE_CHECK:-}" != "true" ]; then
    echo "🔐 Checking Azure authentication..."
    check-azure-auth || return 1
    echo ""
  fi

  # Export hostname for cluster naming (required by cluster-apply-manifests)
  export CLUSTER_HOST="$(detect_hostname)" || return 1
  echo "🏷️  Detected host: ${CLUSTER_HOST}"

  # Load 1Password service account token for automated secret access
  if command -v op &>/dev/null; then
    load-1password-token && echo "✅ 1Password service account token loaded"
  fi

  # Check if cluster exists
  if [ -z "$HOST_CONTEXT" ] || ! kubectl --context "$HOST_CONTEXT" cluster-info &>/dev/null; then
    echo "❌ No cluster found. Please create a cluster first with 'cld' or 'cluster-deploy'"
    return 1
  fi

  if [ -n "$HOST_CONTEXT" ]; then
    kubectl config use-context "$HOST_CONTEXT" >/dev/null 2>&1 || true
  fi

  # For updates, use static deployment file only (no secret generation needed)
  # The TLS secret already exists from initial creation or ExternalSecret sync
  # This is faster and doesn't require Azure auth
  local NGINX_OVERRIDE_FILE="${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml"
  echo "📄 Using static nginx deployment override (TLS secret already exists)"

  # Apply manifests using portable core
  cluster-apply-manifests "$NGINX_OVERRIDE_FILE" || {
    cd "$ORIG_DIR"
    return 1
  }

  echo ""
  echo "✅ Cluster update complete"

  # Fix /etc/hosts on KIND nodes for Gitea OCI registry access
  fix-kind-hosts "${CLUSTER_HOST}"

  # Step 4: Show ArgoCD application status
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 ARGOCD APPLICATION STATUS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  local apps=$(kubectl get applications -n argocd -o name 2>/dev/null | wc -l)
  if [ $apps -gt 0 ]; then
    kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status,\
MESSAGE:.status.conditions[0].message 2>/dev/null || \
      kubectl get applications -n argocd 2>/dev/null

    echo ""
    echo "💡 Monitor detailed sync progress at:"
    echo "   ArgoCD UI: https://argocd.cnoe.localtest.me:8443"
  else
    echo "⚠️  No ArgoCD applications found yet"
    echo "   Applications may still be syncing. Check again in a few moments."
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Optionally display diff summary at end
  if [ -n "$CHANGES" ] && [ -f "${DIFF_FILE}.summary" ]; then
    echo ""
    echo "📋 Manifest changes summary saved to: ${DIFF_FILE}.summary"

    if [[ "$NO_EXIT" != "--no-exit" ]]; then
      echo ""
      echo -n "View full diff now? [y/N] "
      read -r -t 3 -n 1 response || response="n"
      echo ""

      if [[ "$response" =~ ^[Yy]$ ]]; then
        if command -v bat &>/dev/null; then
          bat --style=changes --paging=always --language=diff "$DIFF_FILE"
        elif command -v less &>/dev/null; then
          less -R "$DIFF_FILE"
        else
          cat "$DIFF_FILE" | head -100
        fi
      fi
    fi
  fi

  cd "$ORIG_DIR"

  # Keep terminal open in watch mode
  if [[ "$NO_EXIT" == "--no-exit" ]]; then
    echo ""
    echo "Press any key to continue..."
    read -n 1 -s
  fi
}

cluster-status() {
  local HOST_CONTEXT="$(detect_host_context)"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 CLUSTER STATUS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if kubectl --context "$HOST_CONTEXT" cluster-info &>/dev/null; then
    echo "✅ Cluster is running"
    echo ""
    kubectl get nodes
    echo ""

    # Use ArgoCD CLI for application status if available
    if command -v argocd &>/dev/null && [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
      echo "ArgoCD Applications (via CLI):"
      argocd-status 2>/dev/null || kubectl get applications -n argocd 2>/dev/null || echo "  No applications found"
    else
      echo "ArgoCD Applications:"
      kubectl get applications -n argocd 2>/dev/null || echo "  No applications found"
    fi
  else
    echo "❌ No cluster found"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

cluster-menu() {
  # Interactive menu for cluster operations
  if ! command -v gum &>/dev/null; then
    echo "❌ gum is required for the interactive menu"
    echo "Install with: nix-env -iA nixpkgs.gum"
    echo ""
    echo "Available commands without gum:"
    echo "  cluster-build (clb)    - Build kustomize packages"
    echo "  cluster-deploy (cld)   - Deploy cluster"
    echo "  cluster-update (clu)   - Update cluster"
    echo "  cluster-recreate (clr) - Recreate cluster"
    echo "  cluster-status (clst)  - Show status"
    return 1
  fi

  local CLUSTER_MENU_SCRIPT="$STACKS_DIR/deployment/scripts/cluster-menu.sh"

  while true; do
    local choice=$(gum choose \
      "Build Only" \
      "Update Cluster (idempotent)" \
      "Build & Deploy" \
      "Build & Deploy (with spinner)" \
      "Recreate Cluster" \
      "Show Status" \
      "Exit")

    case "$choice" in
      "Build Only")
        cluster-build
        echo ""
        gum style --foreground 82 "Press any key to continue..."
        read -n 1 -s
        ;;
      "Update Cluster (idempotent)")
        cluster-update-gum
        echo ""
        gum style --foreground 82 "Press any key to continue..."
        read -n 1 -s
        ;;
      "Build & Deploy")
        cluster-deploy
        echo ""
        gum style --foreground 82 "Press any key to continue..."
        read -n 1 -s
        ;;
      "Synthesize & Deploy (with spinner)")
        gum spin --spinner dot --title "Deploying cluster..." -- \
          env STACKS_DIR="$STACKS_DIR" bash -lc "source '$CLUSTER_MENU_SCRIPT'; cluster-deploy >/dev/null 2>&1"
        gum style --foreground 82 "✅ Deployment complete"
        echo ""
        gum style --foreground 82 "Press any key to continue..."
        read -n 1 -s
        ;;
      "Recreate Cluster")
        if gum confirm "This will delete the existing cluster. Continue?"; then
          cluster-recreate
          echo ""
          gum style --foreground 82 "Press any key to continue..."
          read -n 1 -s
        fi
        ;;
      "Show Status")
        cluster-status
        echo ""
        gum style --foreground 82 "Press any key to continue..."
        read -n 1 -s
        ;;
      "Exit")
        break
        ;;
    esac
  done
}

# Aliases
alias clb="cluster-build"      # Build kustomize packages
alias cls="cluster-build"      # Legacy alias (was cluster-synth)
alias cld="cluster-deploy"
alias clu="cluster-update"
alias cluw="cluster-update --no-exit"
alias clug="cluster-update-gum"
alias clr="cluster-recreate"
alias clst="cluster-status"
alias clm="cluster-menu"
# NixOS aliases (clnix, clnix-force, clnix-github, etc.) defined in nixos-kubevirt.sh

# Kargo repo management (ensure host-specific repos exist in Gitea)
alias kargo-repos="ensure-kargo-repos"

# ArgoCD Aliases (if argocd-auth.sh is loaded)
if [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
  alias argo-status="argocd-status"
  alias argo-sync="argocd-sync"
  alias argo-sync-all="argocd-sync-all"
  alias argo-outofsync="argocd-list-outofsync"
fi

# Tailscale remote access aliases
TAILSCALE_KUBECONFIG_SCRIPT="$STACKS_DIR/deployment/scripts/tailscale/tailscale-kubeconfig.sh"
if [ -f "$TAILSCALE_KUBECONFIG_SCRIPT" ]; then
  alias ts-kubeconfig="$TAILSCALE_KUBECONFIG_SCRIPT"
  alias ts-kubeconfig-gen="$TAILSCALE_KUBECONFIG_SCRIPT generate"
  alias ts-kubeconfig-get="$TAILSCALE_KUBECONFIG_SCRIPT get"
  alias ts-kubeconfig-test="$TAILSCALE_KUBECONFIG_SCRIPT test"
fi

# Cluster health check and summary
CLUSTER_HEALTH_CHECK="$STACKS_DIR/deployment/scripts/cluster-health-check.sh"
if [ -f "$CLUSTER_HEALTH_CHECK" ]; then
  alias clhealth="$CLUSTER_HEALTH_CHECK summary"
  alias clwait="$CLUSTER_HEALTH_CHECK wait"

  # Convenience function
  cluster-health() {
    "$CLUSTER_HEALTH_CHECK" "${1:-summary}"
  }
fi

# Image preloading (loads from Docker cache to KIND + Gitea)
IMAGE_PRELOAD_SCRIPT="$STACKS_DIR/deployment/scripts/preload-images.sh"
if [ -f "$IMAGE_PRELOAD_SCRIPT" ]; then
  alias preload-images="$IMAGE_PRELOAD_SCRIPT"
fi

# DevContainer push (builds and pushes shared devcontainers to Gitea)
DEVCONTAINER_PUSH_SCRIPT="$STACKS_DIR/deployment/scripts/push-devcontainers.sh"
if [ -f "$DEVCONTAINER_PUSH_SCRIPT" ]; then
  alias push-devcontainers="$DEVCONTAINER_PUSH_SCRIPT"
  alias devcontainer-push="$DEVCONTAINER_PUSH_SCRIPT"  # Alternative alias
fi

# If script is being run directly (not sourced), show help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "🎯 Cluster Management Functions"
  echo ""
  echo "Usage:"
  echo "  Source this file: source cluster-menu.sh"
  echo "  Or run directly to execute cluster-menu: ./cluster-menu.sh"
  echo ""
  echo "Available functions:"
  echo "  cluster-synth (cls)      - Build kustomize packages"
  echo "  cluster-deploy (cld)     - Create/deploy cluster from scratch"
  echo "  cluster-update (clu)     - Update existing cluster (idempotent)"
  echo "  cluster-update-gum (clug) - Interactive update with gum"
  echo "  cluster-recreate (clr)   - Delete and recreate cluster"
  echo "  cluster-status (clst)    - Show cluster and ArgoCD status"
  echo "  cluster-menu (clm)       - Interactive management menu (requires gum)"
  echo ""
  echo "Tailscale Remote Access:"
  echo "  ts-kubeconfig            - Manage remote kubeconfig (see ts-kubeconfig help)"
  echo "  ts-kubeconfig-gen        - Generate new token after cluster recreation"
  echo "  ts-kubeconfig-get        - Get kubeconfig from Azure Key Vault"
  echo "  ts-kubeconfig-test       - Test remote kubectl access"
  echo ""
  echo "Kustomize Watch Mode (Auto-rebuild):"
  echo "  clwatch                  - Start file watcher (requires devenv shell)"
  echo "  clrebuild                - One-shot rebuild without watching"
  echo ""
  echo "  Or via devenv:"
  echo "    devenv up              - Start watcher as background process"
  echo "    watch-kustomize        - Start watcher in foreground"
  echo "    kustomize-build        - One-shot rebuild"
  echo ""

  # If gum is available, run the menu directly
  if command -v gum &>/dev/null; then
    cluster-menu
  fi
fi
