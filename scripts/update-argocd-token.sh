#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}➜${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error_exit() { echo -e "${RED}✖${NC} $1" >&2; exit 1; }

SERVER=${ARGOCD_SERVER:-argocd.cnoe.localtest.me:8443}
ADMIN_USER=${ARGOCD_ADMIN_USER:-admin}
TARGET_ACCOUNT=${ARGOCD_TARGET_ACCOUNT:-developer}
VAULT_NAME=${ONEPASSWORD_VAULT:-Personal}
ITEM_TITLE=${ONEPASSWORD_ARGOCD_ITEM:-Argo CD (localdev)}
ITEM_CATEGORY=${ONEPASSWORD_ARGOCD_CATEGORY:-"API Credential"}

ensure_binary() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error_exit "Required command '$1' not found"
  fi
}

ensure_binary kubectl
ensure_binary argocd

log "Retrieving ArgoCD admin password"
ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
if [ -z "$ADMIN_PASSWORD" ]; then
  error_exit "Unable to read argocd-initial-admin-secret"
fi

log "Logging into ArgoCD as $ADMIN_USER"
argocd login "$SERVER" \
  --username "$ADMIN_USER" \
  --password "$ADMIN_PASSWORD" \
  --insecure >/dev/null 2>&1 || error_exit "Failed to login to ArgoCD"

log "Generating token for service account '$TARGET_ACCOUNT'"
TOKEN=$(argocd account generate-token --account "$TARGET_ACCOUNT" --server "$SERVER")
if [ -z "$TOKEN" ]; then
  error_exit "Failed to generate token"
fi

log "ArgoCD token generated"

update_onepassword() {
  local token="$1"
  if ! command -v op >/dev/null 2>&1; then
    warn "1Password CLI not found; token not stored."
    return 1
  fi

  if ! op account list >/dev/null 2>&1; then
    warn "1Password CLI not signed in; skipping token storage."
    return 1
  fi

  local address="$SERVER"
  local auth_field="auth token[concealed]=$token"
  local address_field="address=$address"
  local username_field="username=$TARGET_ACCOUNT"
  local url_field="url=https://$SERVER"

  if op item get "$ITEM_TITLE" --vault "$VAULT_NAME" >/dev/null 2>&1; then
    log "Updating existing 1Password item '$ITEM_TITLE'"
    op item edit "$ITEM_TITLE" --vault "$VAULT_NAME" 'credential[delete]' '"auth token"[delete]' >/dev/null 2>&1 || true
    op item edit "$ITEM_TITLE" --vault "$VAULT_NAME" \
      "$username_field" \
      "$auth_field" \
      "$address_field" \
      "$url_field" >/dev/null
  else
    log "Creating 1Password item '$ITEM_TITLE'"
    op item create \
      --title "$ITEM_TITLE" \
      --vault "$VAULT_NAME" \
      --category "$ITEM_CATEGORY" \
      "$username_field" \
      "$auth_field" \
      "$address_field" \
      "$url_field" >/dev/null
  fi
  log "Stored ArgoCD token in 1Password vault '$VAULT_NAME'"
  return 0
}

if ! update_onepassword "$TOKEN"; then
  log "Token value:" 
  echo "$TOKEN"
fi

log "Completed ArgoCD token setup"
