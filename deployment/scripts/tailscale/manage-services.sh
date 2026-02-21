#!/usr/bin/env bash
set -euo pipefail

# Manage Tailscale Services via API v2
# Usage: ./manage-services.sh <command> [args]
#
# Commands:
#   list                  List all Tailscale Services
#   create <name> [port]  Create a service (default port: tcp:443)
#   delete <name>         Delete a service
#   hosts <name>          List hosts for a service
#   cleanup               Delete all offline devices matching flowise-*/workflow-builder-* patterns
#   create-all            Create all expected services in batch

TAILNET="${TAILSCALE_TAILNET:-tail286401.ts.net}"
API_BASE="https://api.tailscale.com/api/v2"

# Services to create in batch
SERVICES=(
  "svc:workflow-builder-thinkpad tcp:443"
  "svc:workflow-builder-ryzen    tcp:443"
  "svc:flowise-thinkpad          tcp:443"
  "svc:flowise-ryzen             tcp:443"
)

# Cleanup patterns: match flowise and workflow-builder device names
CLEANUP_PATTERNS=(
  "^flowise$"
  "^flowise-.*"
  "^workflow-builder$"
  "^workflow-builder-.*"
)

usage() {
  echo "Usage: $0 <command> [args]"
  echo ""
  echo "Commands:"
  echo "  list                  List all Tailscale Services"
  echo "  create <name> [port]  Create a service (default port: tcp:443)"
  echo "  delete <name>         Delete a service"
  echo "  hosts <name>          List hosts for a service"
  echo "  cleanup               Delete all offline flowise/workflow-builder devices"
  echo "  create-all            Create all expected services in batch"
  exit 1
}

# --- Credential Loading (shared with cleanup-old-devices.sh) ---
load_credentials() {
  CLIENT_ID=""
  CLIENT_SECRET=""

  # 1. In-cluster: K8s secret
  if kubectl get secret -n tailscale tailscale-oauth &>/dev/null; then
    echo "Using OAuth credentials from Kubernetes"
    CLIENT_ID=$(kubectl get secret -n tailscale tailscale-oauth -o jsonpath='{.data.clientId}' | base64 -d)
    CLIENT_SECRET=$(kubectl get secret -n tailscale tailscale-oauth -o jsonpath='{.data.clientSecret}' | base64 -d)
    return
  fi

  # 2. Azure Key Vault
  if command -v az &>/dev/null && az account show &>/dev/null 2>&1; then
    VAULT_NAME="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
    CLIENT_ID=$(az keyvault secret show --vault-name "$VAULT_NAME" --name "TAILSCALE-OAUTH-CLIENT-ID" --query value -o tsv 2>/dev/null || echo "")
    CLIENT_SECRET=$(az keyvault secret show --vault-name "$VAULT_NAME" --name "TAILSCALE-OAUTH-CLIENT-SECRET" --query value -o tsv 2>/dev/null || echo "")
    if [[ -n "$CLIENT_ID" ]] && [[ -n "$CLIENT_SECRET" ]]; then
      echo "Using credentials from Azure Key Vault"
      return
    fi
  fi

  # 3. 1Password
  if command -v op &>/dev/null && op account get &>/dev/null 2>&1; then
    CLIENT_ID=$(op read "op://Private/tailscale-oauth/client-id" 2>/dev/null || echo "")
    CLIENT_SECRET=$(op read "op://Private/tailscale-oauth/client-secret" 2>/dev/null || echo "")
    if [[ -n "$CLIENT_ID" ]] && [[ -n "$CLIENT_SECRET" ]]; then
      echo "Using credentials from 1Password"
      return
    fi
  fi

  # 4. Environment variables
  CLIENT_ID="${TAILSCALE_CLIENT_ID:-}"
  CLIENT_SECRET="${TAILSCALE_CLIENT_SECRET:-}"
  if [[ -n "$CLIENT_ID" ]] && [[ -n "$CLIENT_SECRET" ]]; then
    echo "Using credentials from environment variables"
    return
  fi

  echo "Error: Tailscale OAuth credentials not found"
  echo ""
  echo "Tried:"
  echo "  1. Kubernetes secret: tailscale-oauth (in cluster only)"
  echo "  2. Azure Key Vault: TAILSCALE-OAUTH-CLIENT-ID/SECRET"
  echo "  3. 1Password: op://Private/tailscale-oauth/*"
  echo "  4. Environment: TAILSCALE_CLIENT_ID/SECRET"
  exit 1
}

get_token() {
  TOKEN_RESPONSE=$(curl -s -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    "${API_BASE}/oauth/token")

  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

  if [[ "$ACCESS_TOKEN" == "null" ]] || [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Error: Failed to get access token"
    echo "$TOKEN_RESPONSE"
    exit 1
  fi
}

api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -s -w "\n%{http_code}" -X "$method" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@" \
    "${API_BASE}${path}"
}

# --- Commands ---

cmd_list() {
  echo "=== Tailscale Services ==="
  RESPONSE=$(api GET "/tailnet/${TAILNET}/services")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: HTTP $HTTP_CODE"
    echo "$BODY"
    exit 1
  fi

  echo "$BODY" | jq -r '.services[]? | "\(.name)\t\(.ports | join(","))"' 2>/dev/null | column -t || echo "$BODY" | jq .
}

cmd_create() {
  local name="$1"
  local port="${2:-tcp:443}"

  echo -n "Creating service ${name} (${port})... "
  RESPONSE=$(api PUT "/tailnet/${TAILNET}/services/${name}" \
    -d "{\"ports\":[\"${port}\"]}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "201" ]]; then
    echo "OK"
  else
    echo "Error (HTTP $HTTP_CODE)"
    echo "  $BODY"
  fi
}

cmd_delete() {
  local name="$1"

  echo -n "Deleting service ${name}... "
  RESPONSE=$(api DELETE "/tailnet/${TAILNET}/services/${name}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

  if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "204" ]]; then
    echo "OK"
  else
    BODY=$(echo "$RESPONSE" | head -n-1)
    echo "Error (HTTP $HTTP_CODE)"
    echo "  $BODY"
  fi
}

cmd_hosts() {
  local name="$1"

  echo "=== Hosts for ${name} ==="
  RESPONSE=$(api GET "/tailnet/${TAILNET}/services/${name}/devices")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: HTTP $HTTP_CODE"
    echo "$BODY"
    exit 1
  fi

  echo "$BODY" | jq -r '.devices[]? | "\(.hostname)\t\(.online)\t\(.id)"' 2>/dev/null | column -t || echo "$BODY" | jq .
}

cmd_cleanup() {
  echo "=== Cleaning up stale flowise/workflow-builder devices ==="

  PATTERN_REGEX=$(IFS='|'; echo "${CLEANUP_PATTERNS[*]}")

  # Use API to get all devices (works without tailscale CLI)
  RESPONSE=$(api GET "/tailnet/-/devices")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error fetching devices: HTTP $HTTP_CODE"
    echo "$BODY"
    exit 1
  fi

  DEVICES=$(echo "$BODY" | jq -r --arg pattern "$PATTERN_REGEX" '
    .devices[] |
    select(.hostname | test($pattern)) |
    select(.online == false) |
    "\(.id) \(.hostname)"
  ')

  if [[ -z "$DEVICES" ]]; then
    echo "No offline devices found matching patterns"
    exit 0
  fi

  echo "Found offline devices:"
  echo "$DEVICES" | while read -r id hostname; do
    echo "  - $hostname (ID: $id)"
  done

  echo ""
  DEVICE_COUNT=0
  while read -r DEVICE_ID HOSTNAME; do
    echo -n "  Deleting $HOSTNAME ($DEVICE_ID)... "
    RESPONSE=$(api DELETE "/device/${DEVICE_ID}")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

    if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "204" ]]; then
      echo "OK"
      ((DEVICE_COUNT++)) || true
    else
      BODY=$(echo "$RESPONSE" | head -n-1)
      echo "Error (HTTP $HTTP_CODE): $BODY"
    fi
    sleep 0.5
  done <<< "$DEVICES"

  echo ""
  echo "Deleted $DEVICE_COUNT device(s)"
}

cmd_create_all() {
  echo "=== Creating all services ==="
  for entry in "${SERVICES[@]}"; do
    read -r name port <<< "$entry"
    cmd_create "$name" "$port"
  done
  echo ""
  echo "Done. Run '$0 list' to verify."
}

# --- Main ---

if [[ $# -lt 1 ]]; then
  usage
fi

COMMAND="$1"
shift

load_credentials
get_token

case "$COMMAND" in
  list)       cmd_list ;;
  create)     [[ $# -lt 1 ]] && { echo "Usage: $0 create <name> [port]"; exit 1; }; cmd_create "$@" ;;
  delete)     [[ $# -lt 1 ]] && { echo "Usage: $0 delete <name>"; exit 1; }; cmd_delete "$@" ;;
  hosts)      [[ $# -lt 1 ]] && { echo "Usage: $0 hosts <name>"; exit 1; }; cmd_hosts "$@" ;;
  cleanup)    cmd_cleanup ;;
  create-all) cmd_create_all ;;
  *)          usage ;;
esac
