#!/usr/bin/env bash
set -euo pipefail

# Cleanup old offline Tailscale devices for platform services
# Usage: ./cleanup-old-devices.sh [--wait]

WAIT_FOR_GRACE_PERIOD=false
if [[ "${1:-}" == "--wait" ]]; then
  WAIT_FOR_GRACE_PERIOD=true
fi

# Service patterns to match (exact hostnames only, not suffixed versions)
SERVICE_PATTERNS=(
  "^kagent$"
  "^gitea$"
  "^argocd$"
  "^agentgateway$"
  "^keycloak$"
  "^headlamp$"
  "^cnoe$"
  "^kargo$"
  "^kargo-webhooks$"
  "^nixos-dev-vm$"
)

echo "=== Tailscale Device Cleanup ==="
echo "Looking for offline devices matching platform services..."

# Check if running in cluster (kubectl available)
IN_CLUSTER=false
if kubectl get secret -n tailscale tailscale-oauth &>/dev/null; then
  IN_CLUSTER=true
  echo "✓ Running in cluster context, using OAuth credentials from Kubernetes"

  # Get OAuth credentials from Kubernetes secret
  CLIENT_ID=$(kubectl get secret -n tailscale tailscale-oauth -o jsonpath='{.data.clientId}' | base64 -d)
  CLIENT_SECRET=$(kubectl get secret -n tailscale tailscale-oauth -o jsonpath='{.data.clientSecret}' | base64 -d)
else
  echo "✓ Running outside cluster, checking for credentials..."

  # Try to get from Azure Key Vault first (if az CLI is authenticated)
  if command -v az &>/dev/null && az account show &>/dev/null 2>&1; then
    echo "  Trying Azure Key Vault..."
    VAULT_NAME="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
    CLIENT_ID=$(az keyvault secret show --vault-name "$VAULT_NAME" --name "TAILSCALE-OAUTH-CLIENT-ID" --query value -o tsv 2>/dev/null || echo "")
    CLIENT_SECRET=$(az keyvault secret show --vault-name "$VAULT_NAME" --name "TAILSCALE-OAUTH-CLIENT-SECRET" --query value -o tsv 2>/dev/null || echo "")

    if [[ -n "$CLIENT_ID" ]] && [[ -n "$CLIENT_SECRET" ]]; then
      echo "  ✓ Using credentials from Azure Key Vault"
    fi
  fi

  # Fall back to 1Password if Azure Key Vault didn't work
  if [[ -z "$CLIENT_ID" ]] || [[ -z "$CLIENT_SECRET" ]]; then
    if command -v op &>/dev/null && op account get &>/dev/null 2>&1; then
      echo "  Trying 1Password..."
      CLIENT_ID=$(op read "op://Private/tailscale-oauth/client-id" 2>/dev/null || echo "")
      CLIENT_SECRET=$(op read "op://Private/tailscale-oauth/client-secret" 2>/dev/null || echo "")

      if [[ -n "$CLIENT_ID" ]] && [[ -n "$CLIENT_SECRET" ]]; then
        echo "  ✓ Using credentials from 1Password"
      fi
    fi
  fi

  # Final fallback to environment variables
  if [[ -z "$CLIENT_ID" ]] || [[ -z "$CLIENT_SECRET" ]]; then
    CLIENT_ID="${TAILSCALE_CLIENT_ID:-}"
    CLIENT_SECRET="${TAILSCALE_CLIENT_SECRET:-}"

    if [[ -n "$CLIENT_ID" ]] && [[ -n "$CLIENT_SECRET" ]]; then
      echo "  ✓ Using credentials from environment variables"
    fi
  fi
fi

if [[ -z "$CLIENT_ID" ]] || [[ -z "$CLIENT_SECRET" ]]; then
  echo "Error: Tailscale OAuth credentials not found"
  echo ""
  echo "Tried:"
  echo "  1. Kubernetes secret: tailscale-oauth (in cluster only)"
  echo "  2. Azure Key Vault: TAILSCALE-OAUTH-CLIENT-ID/SECRET"
  echo "  3. 1Password: op://Private/tailscale-oauth/*"
  echo "  4. Environment: TAILSCALE_CLIENT_ID/SECRET"
  echo ""
  echo "Solutions:"
  echo "  - Set environment variables: export TAILSCALE_CLIENT_ID=... TAILSCALE_CLIENT_SECRET=..."
  echo "  - Authenticate with Azure: az login"
  echo "  - Authenticate with 1Password: eval \$(op signin)"
  exit 1
fi

# Get OAuth token
echo "Getting OAuth token..."
TOKEN_RESPONSE=$(curl -s -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  https://api.tailscale.com/api/v2/oauth/token)

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [[ "$ACCESS_TOKEN" == "null" ]] || [[ -z "$ACCESS_TOKEN" ]]; then
  echo "Error: Failed to get access token"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

echo "✓ OAuth token obtained"

# Get list of offline devices matching our patterns
echo "Searching for offline devices..."
PATTERN_REGEX=$(IFS='|'; echo "${SERVICE_PATTERNS[*]}")
DEVICES=$(tailscale status --json | jq -r --arg pattern "$PATTERN_REGEX" '
  .Peer[] |
  select(.HostName | test($pattern)) |
  select(.Online == false) |
  "\(.ID) \(.HostName) \(.TailscaleIPs[0])"
')

if [[ -z "$DEVICES" ]]; then
  echo "✓ No offline devices found matching patterns"
  exit 0
fi

echo "Found offline devices:"
echo "$DEVICES" | while read -r id hostname ip; do
  echo "  - $hostname ($ip) - ID: $id"
done

# Delete each device
DEVICE_COUNT=0
echo ""
echo "Deleting devices..."
while read -r DEVICE_ID HOSTNAME IP; do
  echo -n "  Deleting $HOSTNAME ($DEVICE_ID)... "

  RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://api.tailscale.com/api/v2/device/${DEVICE_ID}")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "204" ]]; then
    echo "✓ Deleted"
    ((DEVICE_COUNT++)) || true
  else
    echo "✗ Error (HTTP $HTTP_CODE)"
    if [[ -n "$BODY" ]]; then
      echo "    Response: $BODY"
    fi
  fi

  sleep 0.5
done <<< "$DEVICES"

echo ""
echo "=== Summary ==="
echo "Deleted $DEVICE_COUNT device(s)"

if [[ "$WAIT_FOR_GRACE_PERIOD" == "true" ]]; then
  echo ""
  echo "Waiting for Tailscale grace period (120 seconds) to fully release hostnames..."
  echo "This ensures new devices can claim the canonical names without -1 suffix."

  for i in {120..1}; do
    printf "\r  Time remaining: %3d seconds" "$i"
    sleep 1
  done
  echo ""
  echo "✓ Grace period complete. You can now recreate Tailscale resources."
fi

echo ""
echo "Done!"
