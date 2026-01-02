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

# Ensure nixidy is ready (nix available and flake exists)
ensure-nixidy-ready() {
  local NIXIDY_DIR="$STACKS_DIR/nixidy"

  # Check if nix is available
  if ! command -v nix &>/dev/null; then
    echo "❌ nix is not installed. Please install Nix first."
    echo "   Visit: https://nixos.org/download.html"
    return 1
  fi

  # Check if flake.nix exists
  if [ ! -f "$NIXIDY_DIR/flake.nix" ]; then
    echo "❌ nixidy/flake.nix not found"
    return 1
  fi

  return 0
}

# Synthesize nixidy manifests
nixidy-synth() {
  local NIXIDY_DIR="$STACKS_DIR/nixidy"
  local ENV="${1:-kind}"

  echo "🔨 Synthesizing nixidy manifests for $ENV..."

  cd "$NIXIDY_DIR"

  # Build nixidy manifests (creates result symlink)
  if nix develop -c nixidy build ".#$ENV" 2>&1; then
    echo "✅ Nixidy synthesis complete. Manifests in: $NIXIDY_DIR/result/"
    return 0
  else
    echo "❌ Nixidy synthesis failed"
    return 1
  fi
}

# Legacy: Ensure CDK8s dependencies are installed (deprecated - use nixidy)
ensure-cdk8s-dependencies() {
  echo "⚠️  CDK8s is deprecated. Using nixidy instead."
  ensure-nixidy-ready
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

  # Substitute STACKS_DIR in template using sed (envsubst not always available)
  sed "s|\${STACKS_DIR}|$STACKS_DIR|g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"

  echo "✅ Generated kind-config.yaml with STACKS_DIR=$STACKS_DIR"
}

# Base functions - always non-interactive
cluster-deploy() {
  # Check if being called internally (skip auth check if SKIP_AZURE_CHECK is set)
  if [ "${SKIP_AZURE_CHECK:-}" != "true" ]; then
    echo "🔐 Checking Azure authentication..."
    check-azure-auth || return 1
    echo ""
  fi

  local NIXIDY_DIR="$STACKS_DIR/nixidy"
  local DEPLOY_DIR="$STACKS_DIR/deployment"
  local ORIG_DIR="$(pwd)"

  # Source environment files FIRST (before any operations that need them)
  # Use kind.env for KIND clusters (renamed from wi.env in feature 106)
  [ -f "$STACKS_DIR/.env-files/kind.env" ] && source "$STACKS_DIR/.env-files/kind.env"

  # Export hostname for synthesis (host-aware Tailscale names)
  export CLUSTER_HOST="$(detect_hostname)" || { cd "$ORIG_DIR"; return 1; }
  echo "🏷️  Detected host: ${CLUSTER_HOST}"

  # Load 1Password service account token for automated secret access
  if command -v op &>/dev/null; then
    load-1password-token && echo "✅ 1Password service account token loaded"
  fi

  # Clear any WSL Docker environment variables
  # Check if we have a native Docker socket
  if [[ -S /var/run/docker.sock ]]; then
    unset DOCKER_HOST
    unset DOCKER_TLS_VERIFY
    unset DOCKER_CERT_PATH
    export DOCKER_HOST=""
  fi

  # Ensure nixidy is ready
  echo "🔍 Checking nixidy dependencies..."
  ensure-nixidy-ready || { cd "$ORIG_DIR"; return 1; }

  # Check for legacy cluster and handle migration
  check_legacy_cluster || { cd "$ORIG_DIR"; return 1; }

  # Synthesize nixidy manifests
  nixidy-synth "kind" || { cd "$ORIG_DIR"; return 1; }

  echo "🚀 Creating cluster with idpbuilder..."

  # Generate kind-config.yaml from template with current STACKS_DIR
  generate-kind-config

  # Allow idpbuilder to manage its own self-signed certificates
  # Check if Linux deployment script exists and use it
  if [ -f "$DEPLOY_DIR/scripts/deploy-linux-ssh.sh" ]; then
    echo "Using Linux deployment script with direct key mounting and Azure integration..."
    cd "$DEPLOY_DIR/scripts" && ./deploy-linux-ssh.sh \
      --package "$NIXIDY_DIR/result/" \
      "$@"
  else
    # Fallback to standard idpbuilder with post-setup JWKS sync
    command -v idpbuilder >/dev/null 2>&1 || { echo "❌ idpbuilder not found. Please install it first."; cd "$ORIG_DIR"; return 1; }

    # Use hostname as cluster name
    local CLUSTER_NAME="$(detect_cluster_name)"
    echo "🏷️  Creating cluster: ${CLUSTER_NAME}"

    idpbuilder create \
      --name "${CLUSTER_NAME}" \
      -p "$NIXIDY_DIR/result/" \
      --package-custom-file "nginx:${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml" \
      --kind-config "$DEPLOY_DIR/config/kind-config.yaml" \
      --dev-password "$@"

    # Sync JWKS after cluster creation (now in deployment/scripts)
    if [ -f "$DEPLOY_DIR/scripts/sync-jwks-to-azure.sh" ]; then
      echo "🔄 Syncing JWKS to Azure for External Secrets..."
      cd "$DEPLOY_DIR/scripts" && ./sync-jwks-to-azure.sh
    fi
  fi

  local result=$?

  # Note: Docker Hub auth is now configured via Kind mount (containerd/certs.d)
  # The generate-docker-registry-config.sh script runs before cluster creation
  # and the Kind config mounts the generated config at /etc/containerd/certs.d

  # Initialize ArgoCD authentication and save token to 1Password after successful deployment
  if [ $result -eq 0 ] && [ "${SKIP_ARGOCD_INIT:-}" != "true" ]; then
    echo ""
    echo "🔐 Initializing ArgoCD authentication and saving token..."

    # Wait a moment for ArgoCD to be fully ready
    sleep 5

    # Initialize and save token
    if command -v argocd &>/dev/null && [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
      if argocd-auth-init; then
        echo "✅ ArgoCD authentication configured and token saved to 1Password"
      else
        echo "⚠️  ArgoCD authentication initialization failed (may retry later)"
      fi
    fi
  fi

  # Generate Tailscale remote access token after deployment
  if [ $result -eq 0 ] && [ "${SKIP_TAILSCALE_TOKEN:-}" != "true" ]; then
    local TAILSCALE_KUBECONFIG_SCRIPT="$STACKS_DIR/deployment/scripts/tailscale/tailscale-kubeconfig.sh"
    if [ -f "$TAILSCALE_KUBECONFIG_SCRIPT" ]; then
      echo ""
      echo "🔑 Generating Tailscale remote access token..."

      # Wait for k8s-api-tailscale-serve to be ready
      # Note: With init containers waiting for ESO secrets, this can take 5-10 minutes
      # The init container approach prevents CreateContainerConfigError but requires patience
      echo "   Waiting for k8s-api-tailscale-serve pod (may take 5-10 min due to ESO sync)..."

      # Show progress while waiting
      local TIMEOUT=600  # 10 minutes
      local INTERVAL=30
      local ELAPSED=0
      local READY=false

      while [ $ELAPSED -lt $TIMEOUT ]; do
        if kubectl wait --for=condition=available deployment/k8s-api-tailscale-serve -n tailscale --timeout=${INTERVAL}s &>/dev/null; then
          READY=true
          break
        fi
        ELAPSED=$((ELAPSED + INTERVAL))

        # Show status update
        local POD_STATUS
        POD_STATUS=$(kubectl get pods -n tailscale -l app.kubernetes.io/name=k8s-api-tailscale-serve -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
        local INIT_STATUS
        INIT_STATUS=$(kubectl get pods -n tailscale -l app.kubernetes.io/name=k8s-api-tailscale-serve -o jsonpath='{.items[0].status.initContainerStatuses[0].state}' 2>/dev/null | grep -o 'running\|waiting\|terminated' | head -1 || echo "unknown")
        echo "   ... still waiting (${ELAPSED}s/${TIMEOUT}s) - Pod: $POD_STATUS, Init: $INIT_STATUS"
      done

      if [ "$READY" = true ]; then
        sleep 5  # Additional wait for ServiceAccount to be ready
        if "$TAILSCALE_KUBECONFIG_SCRIPT" generate &>/dev/null; then
          echo "✅ Tailscale remote access token generated and stored in Azure Key Vault"
          echo "   Kubeconfig: ~/.kube/tailscale-cluster.yaml"
        else
          echo "⚠️  Tailscale token generation failed (may retry with: tailscale-kubeconfig.sh generate)"
        fi
      else
        echo "⚠️  k8s-api-tailscale-serve not ready after ${TIMEOUT}s"
        echo "   This is expected during first deployment while ESO syncs secrets from Azure Key Vault"
        echo "   Retry later with: tailscale-kubeconfig.sh generate"
      fi
    fi
  fi

  cd "$ORIG_DIR"
  return $result
}

cluster-synth() {
  local NIXIDY_DIR="$STACKS_DIR/nixidy"
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

  # Ensure nixidy is ready
  echo "🔍 Checking nixidy dependencies..."
  ensure-nixidy-ready || { cd "$ORIG_DIR"; return 1; }

  # Synthesize nixidy manifests
  nixidy-synth "$ENV"
  local result=$?

  cd "$ORIG_DIR"
  return $result
}

cluster-recreate() {
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

  # Detect cluster name from hostname
  local CLUSTER_NAME="$(detect_cluster_name)"
  if [ $? -ne 0 ] || [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Failed to detect cluster name"
    return 1
  fi

  echo "🗑️  Deleting cluster: ${CLUSTER_NAME}..."
  idpbuilder delete --name "${CLUSTER_NAME}"

  # Clear cached ArgoCD token since cluster is being recreated
  unset ARGOCD_AUTH_TOKEN

  echo ""
  echo "🔨 Creating fresh cluster..."
  # cluster-deploy will handle ArgoCD initialization automatically
  SKIP_AZURE_CHECK=true cluster-deploy "$@"
}

cluster-update-gum() {
  # Interactive gum-based update with real-time feedback
  if ! command -v gum &>/dev/null; then
    echo "❌ gum is required for interactive mode"
    echo "Install with: nix-env -iA nixpkgs.gum"
    echo "Or use: cluster-update (non-interactive)"
    return 1
  fi

  local NIXIDY_DIR="$STACKS_DIR/nixidy"
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

  # Ensure nixidy is ready
  gum spin --spinner dot --title "🔍 Checking nixidy dependencies..." -- \
    env STACKS_DIR="$STACKS_DIR" bash -lc "source '$CLUSTER_MENU_SCRIPT'; ensure-nixidy-ready >/dev/null 2>&1"

  if [ $? -ne 0 ]; then
    gum style --foreground 196 "❌ Failed to ensure nixidy is ready"
    return 1
  fi

  # Step 1: Synthesize with spinner
  gum spin --spinner dot --title "🔨 Synthesizing nixidy manifests..." -- \
    bash -lc "cd '$NIXIDY_DIR' && nix develop -c nixidy build .#kind >/dev/null 2>&1"

  if [ $? -ne 0 ]; then
    gum style --foreground 196 "❌ Nixidy synthesis failed"
    cd "$NIXIDY_DIR" && nix develop -c nixidy build .#kind
    cd "$ORIG_DIR"
    return 1
  fi

  gum style --foreground 82 "✅ Synthesis complete"

  # Generate kind-config.yaml from template with current STACKS_DIR
  generate-kind-config

  # Step 2: Update cluster with spinner
  gum spin --spinner dot --title "🚀 Updating cluster: ${CLUSTER_NAME} (idempotent)..." -- \
    bash -lc "idpbuilder create --name '$CLUSTER_NAME' -p '$NIXIDY_DIR/result/' --package-custom-file 'nginx:${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml' --kind-config '$DEPLOY_DIR/config/kind-config.yaml' --dev-password >/dev/null 2>&1"

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
  local NIXIDY_DIR="$STACKS_DIR/nixidy"
  local HOST_CONTEXT="$(detect_host_context)"
  local NO_EXIT=""
  local ORIG_DIR="$(pwd)"

  # Check for --no-exit flag
  if [[ "$1" == "--no-exit" ]]; then
    NO_EXIT="--no-exit"
    shift
  fi

  # Mirror deploy workflow by validating Azure authentication up front
  if [ "${SKIP_AZURE_CHECK:-}" != "true" ]; then
    echo "🔐 Checking Azure authentication..."
    check-azure-auth || return 1
    echo ""
  fi

  # Source environment files FIRST (kind.env for KIND clusters)
  [ -f "$STACKS_DIR/.env-files/kind.env" ] && {
    echo "📋 Loading environment from kind.env..."
    source "$STACKS_DIR/.env-files/kind.env"
  }

  # Export hostname for CDK8s synthesis (host-aware Tailscale names)
  export CLUSTER_HOST="$(detect_hostname)" || return 1
  local CLUSTER_NAME="$CLUSTER_HOST"
  echo "🏷️  Detected host: ${CLUSTER_HOST}"

  # Load 1Password service account token for automated secret access
  if command -v op &>/dev/null; then
    load-1password-token && echo "✅ 1Password service account token loaded"
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
    echo "❌ No cluster found. Please create a cluster first with 'cld' or 'cluster-deploy'"
    return 1
  fi

  if [ -n "$HOST_CONTEXT" ]; then
    kubectl config use-context "$HOST_CONTEXT" >/dev/null 2>&1 || true
  fi

  # Ensure nixidy is ready
  echo "🔍 Checking nixidy dependencies..."
  ensure-nixidy-ready || return 1

  # Step 1: Synthesize nixidy manifests
  echo "🔨 Synthesizing nixidy manifests..."

  # Run synthesis
  cd "$NIXIDY_DIR"
  nix develop -c nixidy build .#kind || {
    echo "❌ Nixidy synthesis failed"
    cd "$ORIG_DIR"
    return 1
  }

  echo "✅ Synthesis complete. Manifests in: $NIXIDY_DIR/result/"

  # Step 2: Update cluster using idpbuilder
  echo ""
  echo "🚀 Updating cluster: ${CLUSTER_NAME} (idempotent)..."
  echo ""

  # Generate kind-config.yaml from template with current STACKS_DIR
  generate-kind-config

  local DEPLOY_DIR="$STACKS_DIR/deployment"
  idpbuilder create \
    --name "${CLUSTER_NAME}" \
    -p "$NIXIDY_DIR/result/" \
    --package-custom-file "nginx:${STACKS_DIR}/deployment/overrides/nginx-hostnetwork-no-hostport.yaml" \
    --kind-config "$DEPLOY_DIR/config/kind-config.yaml" \
    --dev-password

  if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Cluster update failed"
    cd "$ORIG_DIR"
    return 1
  fi

  echo ""
  echo "✅ Cluster update complete"

  # Step 3: Show ArgoCD application status
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
    echo "  cluster-synth (cls)    - Synthesize manifests"
    echo "  cluster-deploy (cld)   - Deploy cluster"
    echo "  cluster-update (clu)   - Update cluster"
    echo "  cluster-recreate (clr) - Recreate cluster"
    echo "  cluster-status (clst)  - Show status"
    return 1
  fi

  local CLUSTER_MENU_SCRIPT="$STACKS_DIR/deployment/scripts/cluster-menu.sh"

  while true; do
    local choice=$(gum choose \
      "Synthesize Only" \
      "Update Cluster (idempotent)" \
      "Synthesize & Deploy" \
      "Synthesize & Deploy (with spinner)" \
      "Recreate Cluster" \
      "Show Status" \
      "Exit")

    case "$choice" in
      "Synthesize Only")
        cluster-synth
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
      "Synthesize & Deploy")
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
alias cls="cluster-synth"
alias cld="cluster-deploy"
alias clu="cluster-update"
alias cluw="cluster-update --no-exit"
alias clug="cluster-update-gum"
alias clr="cluster-recreate"
alias clst="cluster-status"
alias clm="cluster-menu"
# NixOS aliases (clnix, clnix-force, clnix-github, etc.) defined in nixos-kubevirt.sh

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

# If script is being run directly (not sourced), show help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "🎯 Cluster Management Functions"
  echo ""
  echo "Usage:"
  echo "  Source this file: source cluster-menu.sh"
  echo "  Or run directly to execute cluster-menu: ./cluster-menu.sh"
  echo ""
  echo "Available functions:"
  echo "  cluster-synth (cls)      - Synthesize CDK8s manifests"
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

  # If gum is available, run the menu directly
  if command -v gum &>/dev/null; then
    cluster-menu
  fi
fi
