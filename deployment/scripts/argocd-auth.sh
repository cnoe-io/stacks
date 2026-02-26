#!/usr/bin/env bash
# ArgoCD Authentication Helper
# Provides non-interactive authentication for ArgoCD CLI using service account tokens
#
# IMPORTANT: 1Password Integration
# This script uses item IDs instead of item names in op:// references for two reasons:
# 1. Stability: Item IDs don't change even if the item is renamed
# 2. Special characters: Item names with special characters (e.g., parentheses, spaces)
#    can cause parsing issues in op:// secret references
#
# Example: "Argo CD (localdev)" → ka3qjgk3attw67urtws44uoc2m
# To get item ID: op item list --vault CLI --format json | jq '.[] | {title, id}'
# To get field IDs: op item get <item-id> --format json | jq '.fields[] | {label, id}'

# ArgoCD server configuration
export ARGOCD_OPTS="--port-forward --port-forward-namespace argocd"
export ARGOCD_SERVER=$(kubectl get ingress argocd-tailscale -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost:8080")

# Token storage location (in 1Password)
# Using item ID instead of name to avoid special character issues (e.g., parentheses)
# Item: "Argo CD (localdev)" - ID: ka3qjgk3attw67urtws44uoc2m
# Field: "credential"
ARGOCD_TOKEN_OP_PATH="${ARGOCD_TOKEN_OP_PATH:-op://CLI/ka3qjgk3attw67urtws44uoc2m/credential}"

# Get ArgoCD authentication token
# Priority: 1) ARGOCD_AUTH_TOKEN env var, 2) 1Password, 3) Generate new token
argocd-get-token() {
  # Check if token is already set
  if [ -n "$ARGOCD_AUTH_TOKEN" ]; then
    echo "$ARGOCD_AUTH_TOKEN"
    return 0
  fi

  # Try to get token from 1Password (with service account support)
  if command -v op &>/dev/null; then
    # Check if using service account (OP_SERVICE_ACCOUNT_TOKEN set) or user account
    local token

    # Try to read token - works with both service account and user account
    if token=$(op read "$ARGOCD_TOKEN_OP_PATH" 2>/dev/null); then
      echo "$token"
      return 0
    fi

    # If service account token is set but read failed, it might not exist yet
    # Fall through to generate new token
  fi

  # Fall back to generating new token from cluster
  argocd-generate-token
}

# Generate new ArgoCD token for developer account
argocd-generate-token() {
  local admin_pass

  # Get admin password from cluster
  admin_pass=$(kubectl get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -z "$admin_pass" ]; then
    echo "❌ Could not retrieve ArgoCD admin password" >&2
    return 1
  fi

  # Login as admin
  if ! argocd login --port-forward --port-forward-namespace argocd \
    --username admin \
    --password "$admin_pass" &>/dev/null; then
    echo "❌ Failed to login to ArgoCD" >&2
    return 1
  fi

  # Generate token for developer account
  local token
  local retries=5
  while [ $retries -gt 0 ]; do
    token=$(argocd account generate-token \
      --account developer \
      --port-forward --port-forward-namespace argocd 2>/dev/null)
    
    if [ -n "$token" ]; then
      break
    fi
    
    retries=$((retries - 1))
    sleep 2
  done

  if [ -z "$token" ]; then
    echo "❌ Failed to generate ArgoCD token" >&2
    return 1
  fi

  echo "$token"
}

# Save ArgoCD token to 1Password
argocd-save-token() {
  local token="$1"

  if [ -z "$token" ]; then
    echo "Usage: argocd-save-token <token>" >&2
    return 1
  fi

  if ! command -v op &>/dev/null; then
    echo "⚠️  1Password CLI not installed. Token not saved." >&2
    echo "Token: $token" >&2
    return 0
  fi

  # Check if 1Password is accessible (service account or user account)
  # If service account token is set, skip op whoami check (it would prompt for password)
  if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    # No service account token, check if user is signed in
    if ! op whoami &>/dev/null 2>&1; then
      echo "⚠️  Not signed into 1Password and no service account token set." >&2
      echo "Token: $token" >&2
      return 0
    fi
  fi

  # Check if item exists (using item ID for stability)
  # Item ID: ka3qjgk3attw67urtws44uoc2m = "Argo CD (localdev)"
  if op item get ka3qjgk3attw67urtws44uoc2m --vault CLI &>/dev/null 2>&1; then
    # Update existing item - update the "credential" field
    if op item edit ka3qjgk3attw67urtws44uoc2m --vault CLI "credential=$token" &>/dev/null 2>&1; then
      echo "✅ ArgoCD token updated in 1Password" >&2
    else
      echo "⚠️  Failed to update token in 1Password" >&2
      echo "Token: $token" >&2
    fi
  else
    # Create new item
    if op item create \
      --category "Server" \
      --title "Argo CD (localdev)" \
      --vault CLI \
      "auth token=$token" \
      "address=$ARGOCD_SERVER" \
      "username=developer" \
      --tags "argocd,automation,localdev" &>/dev/null 2>&1; then
      echo "✅ ArgoCD token saved to 1Password" >&2
    else
      echo "⚠️  Failed to save token to 1Password" >&2
      echo "Token: $token" >&2
    fi
  fi
}

# Initialize ArgoCD authentication (non-interactive)
argocd-auth-init() {
  local token

  echo "🔐 Initializing ArgoCD authentication..." >&2

  # Try to get existing token
  token=$(argocd-get-token)

  # If no token found, generate one
  if [ -z "$token" ]; then
    echo "📝 Generating new ArgoCD token..." >&2
    token=$(argocd-generate-token)

    if [ -z "$token" ]; then
      echo "❌ Failed to initialize ArgoCD authentication" >&2
      return 1
    fi

    # Save to 1Password if available
    argocd-save-token "$token"
  fi

  # Export token for use
  export ARGOCD_AUTH_TOKEN="$token"

  # Test authentication
  if argocd app list $ARGOCD_OPTS &>/dev/null; then
    echo "✅ ArgoCD authentication successful" >&2
    return 0
  else
    echo "⚠️  Authentication may have failed. Retrying with new token..." >&2
    unset ARGOCD_AUTH_TOKEN
    token=$(argocd-generate-token)

    if [ -n "$token" ]; then
      export ARGOCD_AUTH_TOKEN="$token"
      argocd-save-token "$token"

      if argocd app list $ARGOCD_OPTS &>/dev/null; then
        echo "✅ ArgoCD authentication successful" >&2
        return 0
      fi
    fi

    echo "❌ ArgoCD authentication failed" >&2
    return 1
  fi
}

# Ensure authentication is initialized (call this before using argocd)
argocd-ensure-auth() {
  if [ -z "$ARGOCD_AUTH_TOKEN" ]; then
    argocd-auth-init >/dev/null 2>&1 || return 1
  fi
  return 0
}

# Show ArgoCD application status
argocd-status() {
  argocd-ensure-auth || return 1

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 ARGOCD APPLICATION STATUS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  argocd app list $ARGOCD_OPTS

  echo ""
  echo "💡 ArgoCD UI: https://$ARGOCD_SERVER"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Sync specific ArgoCD application
argocd-sync() {
  argocd-ensure-auth || return 1
  local app="$1"

  if [ -z "$app" ]; then
    echo "Usage: argocd-sync <app-name>" >&2
    echo "Available apps:" >&2
    argocd app list -o name $ARGOCD_OPTS 2>/dev/null | sed 's/^/  /' >&2
    return 1
  fi

  echo "🔄 Syncing ArgoCD application: $app" >&2
  argocd app sync "$app" --prune $ARGOCD_OPTS
}

# Sync all ArgoCD applications
argocd-sync-all() {
  argocd-ensure-auth || return 1
  echo "🔄 Syncing all ArgoCD applications..." >&2
  argocd app sync --all --prune $ARGOCD_OPTS
}

# Get ArgoCD application details
argocd-app-info() {
  argocd-ensure-auth || return 1
  local app="$1"

  if [ -z "$app" ]; then
    echo "Usage: argocd-app-info <app-name>" >&2
    return 1
  fi

  argocd app get "$app" $ARGOCD_OPTS
}

# List out-of-sync applications
argocd-list-outofsync() {
  argocd-ensure-auth || return 1
  echo "⚠️  Out of Sync Applications:" >&2
  argocd app list -o name --output json $ARGOCD_OPTS 2>/dev/null | \
    jq -r '.[] | select(.status.sync.status != "Synced") | "\(.metadata.name) - \(.status.sync.status)"'
}

# If script is sourced, export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f argocd-get-token
  export -f argocd-generate-token
  export -f argocd-save-token
  export -f argocd-auth-init
  export -f argocd-ensure-auth
  export -f argocd-status
  export -f argocd-sync
  export -f argocd-sync-all
  export -f argocd-app-info
  export -f argocd-list-outofsync
fi

# If script is run directly, show help or execute command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-help}" in
    init)
      argocd-auth-init
      ;;
    status)
      argocd-status
      ;;
    sync)
      shift
      argocd-sync "$@"
      ;;
    sync-all)
      argocd-sync-all
      ;;
    list)
      argocd-ensure-auth && argocd app list $ARGOCD_OPTS
      ;;
    outofsync)
      argocd-list-outofsync
      ;;
    *)
      cat <<EOF
ArgoCD Authentication Helper

Automatically sets ARGOCD_AUTH_TOKEN for native argocd CLI usage.

Usage:
  source argocd-auth.sh              # Load into shell
  ./argocd-auth.sh <command> [args]  # Run directly

Commands:
  init                 Initialize authentication
  status              Show application status
  sync <app>          Sync specific application
  sync-all            Sync all applications
  list                List all applications
  outofsync           List out-of-sync applications

Functions (when sourced):
  argocd-auth-init     Initialize auth (sets ARGOCD_AUTH_TOKEN)
  argocd-ensure-auth   Ensure token is set
  argocd-status       Show formatted status
  argocd-sync         Sync specific application
  argocd-sync-all     Sync all applications
  argocd-app-info     Get application details
  argocd-list-outofsync  List out-of-sync apps

After sourcing, use native argocd commands:
  source argocd-auth.sh
  argocd app list --insecure        # Token already set!
  argocd-status                     # Or use helper functions

Environment Variables:
  ARGOCD_SERVER       Server address
  ARGOCD_AUTH_TOKEN   Token (auto-generated)
  ARGOCD_OPTS         Default options (--insecure)
EOF
      ;;
  esac
fi
