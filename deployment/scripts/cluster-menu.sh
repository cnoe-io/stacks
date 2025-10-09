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

# Azure authentication helper functions
detect_host_context() {
  local ctx
  ctx=$(kubectl config get-contexts -o name 2>/dev/null | grep '^kind-' | tail -1)
  if [ -z "$ctx" ]; then
    ctx=$(kubectl config current-context 2>/dev/null || echo "")
  fi
  echo "$ctx"
}

# Derive the Kind cluster name from the host context (e.g., kind-localdev -> localdev)
detect_cluster_name() {
  local ctx="$(detect_host_context)"
  if [[ "$ctx" == kind-* ]]; then
    echo "${ctx#kind-}"
  elif [ -n "$ctx" ]; then
    echo "$ctx"
  else
    echo "localdev"
  fi
}

check-azure-auth() {
  # Check Azure authentication status - only prompts if not automated
  local token_expiry=$(az account get-access-token --query "expiresOn" -o tsv 2>/dev/null || echo "")

  if [ -z "$token_expiry" ]; then
    # Not logged in
    echo "❌ Azure authentication required"
    echo "💡 Please authenticate with: az login"
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

# Base functions - always non-interactive
cluster-deploy() {
  # Check if being called internally (skip auth check if SKIP_AZURE_CHECK is set)
  if [ "${SKIP_AZURE_CHECK:-}" != "true" ]; then
    echo "🔐 Checking Azure authentication..."
    check-azure-auth || return 1
    echo ""
  fi

  local CDK8S_DIR="$STACKS_DIR/cdk8s"
  local REF_DIR="$STACKS_DIR/ref-implementation"
  local DEPLOY_DIR="$STACKS_DIR/deployment"
  local ORIG_DIR="$(pwd)"

  # Source environment files FIRST (before any operations that need them)
  [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"

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

  echo "🔨 Synthesizing CDK8s manifests..."
  cd "$CDK8S_DIR" && npm run synth || { cd "$ORIG_DIR"; return 1; }

  echo "🚀 Creating cluster with idpbuilder..."

  # Allow idpbuilder to manage its own self-signed certificates
  # Check if Linux deployment script exists and use it
  if [ -f "$DEPLOY_DIR/scripts/deploy-linux-ssh.sh" ]; then
    echo "Using Linux deployment script with direct key mounting and Azure integration..."
    cd "$DEPLOY_DIR/scripts" && ./deploy-linux-ssh.sh \
      --package "$CDK8S_DIR/dist/" \
      --package "$REF_DIR/" \
      "$@"
  else
    # Fallback to standard idpbuilder with post-setup JWKS sync
    command -v idpbuilder >/dev/null 2>&1 || { echo "❌ idpbuilder not found. Please install it first."; cd "$ORIG_DIR"; return 1; }
    idpbuilder create \
      -p "$CDK8S_DIR/dist/" \
      -p "$REF_DIR/" \
      --kind-config "$DEPLOY_DIR/config/kind-config-linux-ssh.yaml" \
      --dev-password "$@"

    # Sync JWKS after cluster creation
    if [ -f "$REF_DIR/azure-workload-identity/sync-jwks-to-azure.sh" ]; then
      echo "🔄 Syncing JWKS to Azure for External Secrets..."
      cd "$REF_DIR/azure-workload-identity" && ./sync-jwks-to-azure.sh
    fi
  fi

  local result=$?

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

  cd "$ORIG_DIR"
  return $result
}

cluster-synth() {
  local CDK8S_DIR="$STACKS_DIR/cdk8s"
  local ORIG_DIR="$(pwd)"

  # Clear any WSL Docker environment variables
  # Check if we have a native Docker socket
  if [[ -S /var/run/docker.sock ]]; then
    unset DOCKER_HOST
    unset DOCKER_TLS_VERIFY
    unset DOCKER_CERT_PATH
    export DOCKER_HOST=""
  fi

  [ -f "$STACKS_DIR/.env-files/wi.env" ] && source "$STACKS_DIR/.env-files/wi.env"

  cd "$CDK8S_DIR" && npm run synth
  local result=$?
  [ $result -eq 0 ] && echo "✅ Synthesis complete. Manifests in: $CDK8S_DIR/dist/"

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

  echo "🗑️  Deleting existing cluster..."
  idpbuilder delete

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

  local REF_DIR="$STACKS_DIR/ref-implementation"
  local CDK8S_DIR="$STACKS_DIR/cdk8s"
  local HOST_CONTEXT="$(detect_host_context)"
  local ORIG_DIR="$(pwd)"

  # Source environment files FIRST
  [ -f "$STACKS_DIR/.env-files/wi.env" ] && {
    gum style --foreground 45 "📋 Loading environment from wi.env..."
    source "$STACKS_DIR/.env-files/wi.env"
  }

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

  # Step 1: Synthesize with spinner
  gum spin --spinner dot --title "🔨 Synthesizing CDK8s manifests..." -- \
    bash -c "cd $CDK8S_DIR && npm run synth >/dev/null 2>&1"

  if [ $? -ne 0 ]; then
    gum style --foreground 196 "❌ CDK8s synthesis failed"
    cd "$CDK8S_DIR" && npm run synth
    cd "$ORIG_DIR"
    return 1
  fi

  gum style --foreground 82 "✅ Synthesis complete"

  # Step 2: Update cluster with spinner
  local DEPLOY_DIR="$STACKS_DIR/deployment"
  gum spin --spinner dot --title "🚀 Updating cluster (idempotent)..." -- \
    bash -c "cd $REF_DIR && idpbuilder create -p $CDK8S_DIR/dist/ -p $REF_DIR/ --kind-config $DEPLOY_DIR/config/kind-config-linux-ssh.yaml --dev-password >/dev/null 2>&1"

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
  local REF_DIR="$STACKS_DIR/ref-implementation"
  local CDK8S_DIR="$STACKS_DIR/cdk8s"
  local HOST_CONTEXT="$(detect_host_context)"
  local NO_EXIT=""
  local ORIG_DIR="$(pwd)"

  # Check for --no-exit flag
  if [[ "$1" == "--no-exit" ]]; then
    NO_EXIT="--no-exit"
    shift
  fi

  # Source environment files FIRST (needed for CDK8s synthesis)
  [ -f "$STACKS_DIR/.env-files/wi.env" ] && {
    echo "📋 Loading environment from wi.env..."
    source "$STACKS_DIR/.env-files/wi.env"
  }

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

  # Step 1: Synthesize CDK8s manifests (with environment variables)
  echo "🔨 Synthesizing CDK8s manifests..."

  # Initialize git in dist if not already present (for change tracking)
  if [ ! -d "$CDK8S_DIR/dist/.git" ]; then
    cd "$CDK8S_DIR/dist" && git init -q && git add -A && git commit -q -m "Initial commit" 2>/dev/null || true
    cd "$ORIG_DIR"
  fi

  # Save current state of manifests for comparison
  cd "$CDK8S_DIR/dist"
  git add -A 2>/dev/null || true
  git commit -q -m "Pre-synthesis state" 2>/dev/null || true

  # Run synthesis
  cd "$CDK8S_DIR"
  npm run synth || {
    echo "❌ CDK8s synthesis failed"
    cd "$ORIG_DIR"
    return 1
  }

  # Check for changes and display them immediately
  cd "$CDK8S_DIR/dist"
  local DIFF_FILE="/tmp/cluster-update-diff-$$.txt"
  local CHANGES=""

  # Capture the diff and show summary immediately
  if git diff HEAD 2>/dev/null | head -1000 > "$DIFF_FILE" && [ -s "$DIFF_FILE" ]; then
    CHANGES="yes"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 MANIFEST CHANGES DETECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Show summary immediately
    git diff --stat HEAD | head -20

    # Save full summary for later
    echo "=== MANIFEST CHANGES SUMMARY ===" > "${DIFF_FILE}.summary"
    git diff --stat HEAD >> "${DIFF_FILE}.summary" 2>/dev/null
    echo "" >> "${DIFF_FILE}.summary"

    # Offer immediate diff viewing (non-watch mode only)
    if [[ "$NO_EXIT" != "--no-exit" ]]; then
      echo ""
      echo -n "View detailed diff now? [y/N] "
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

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Commit the changes
    git add -A 2>/dev/null || true
    git commit -q -m "Post-synthesis state" 2>/dev/null || true
  else
    echo ""
    echo "✅ No changes detected in manifests"
    echo ""
  fi

  # Step 2: Update cluster using idpbuilder
  echo "🚀 Updating cluster (idempotent)..."
  echo ""

  local DEPLOY_DIR="$STACKS_DIR/deployment"
  cd "$REF_DIR"
  idpbuilder create \
    -p "$CDK8S_DIR/dist/" \
    -p "$REF_DIR/" \
    --kind-config "$DEPLOY_DIR/config/kind-config-linux-ssh.yaml" \
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
        gum spin --spinner dot --title "Deploying cluster..." -- cluster-deploy >/dev/null 2>&1
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

# ArgoCD Aliases (if argocd-auth.sh is loaded)
if [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
  alias argo-status="argocd-status"
  alias argo-sync="argocd-sync"
  alias argo-sync-all="argocd-sync-all"
  alias argo-outofsync="argocd-list-outofsync"
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

  # If gum is available, run the menu directly
  if command -v gum &>/dev/null; then
    cluster-menu
  fi
fi
