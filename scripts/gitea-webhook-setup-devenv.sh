#!/usr/bin/env bash
#
# Register devenv webhook listener with all Gitea repositories
#
# This script creates webhooks on all gitops-* repos to send push events
# to the local devenv webhook listener for real-time change notifications.
#
# Usage:
#   gitea-webhook-setup
#
# Environment Variables:
#   GITEA_URL       - Gitea server URL (default: https://gitea.cnoe.localtest.me:8443)
#   GITEA_USERNAME  - Gitea username (default: giteaadmin)
#   GITEA_PASSWORD  - Gitea password/token (required)
#   GITEA_WEBHOOK_PORT   - Webhook listener port (default: 9999)
#   GITEA_WEBHOOK_SECRET - Shared secret for signature verification (optional)
#

set -euo pipefail

# Configuration
GITEA_URL="${GITEA_URL:-https://gitea.cnoe.localtest.me:8443}"
GITEA_USER="${GITEA_USERNAME:-giteaadmin}"
GITEA_TOKEN="${GITEA_PASSWORD:-}"
WEBHOOK_PORT="${GITEA_WEBHOOK_PORT:-9999}"
WEBHOOK_SECRET="${GITEA_WEBHOOK_SECRET:-}"

# Webhook URL - uses in-cluster service (KIND on Linux can't reach host.docker.internal)
WEBHOOK_URL="http://webhook-receiver.gitea.svc.cluster.local:9999/webhook"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_dim() { echo -e "${DIM}$1${NC}"; }

# Check for required credentials
if [[ -z "$GITEA_TOKEN" ]]; then
    # Try to get from cluster
    log_info "GITEA_PASSWORD not set, attempting to extract from cluster..."
    if command -v kubectl &>/dev/null; then
        GITEA_TOKEN=$(kubectl get secret gitea-credential -n gitea \
            -o jsonpath='{.data.password}' 2>/dev/null | base64 -d) || true
    fi

    if [[ -z "$GITEA_TOKEN" ]]; then
        log_error "GITEA_PASSWORD not set and could not extract from cluster"
        log_dim "Set GITEA_PASSWORD environment variable or ensure cluster access"
        exit 1
    fi
    log_info "Got credentials from cluster"
fi

echo ""
log_info "Gitea Webhook Setup for devenv"
log_dim "Server: $GITEA_URL"
log_dim "Webhook URL: $WEBHOOK_URL"
echo ""

# Get all repositories
log_info "Fetching repository list..."
repos_response=$(curl -s -k -u "$GITEA_USER:$GITEA_TOKEN" \
    "$GITEA_URL/api/v1/repos/search?limit=200" 2>/dev/null)

if [[ -z "$repos_response" ]]; then
    log_error "Failed to fetch repositories from Gitea"
    exit 1
fi

# Filter to gitops repos only
repos=$(echo "$repos_response" | jq -r '.data[].full_name' 2>/dev/null | grep "gitops-" || true)

if [[ -z "$repos" ]]; then
    log_warn "No gitops-* repositories found"
    exit 0
fi

repo_count=$(echo "$repos" | wc -l)
log_info "Found $repo_count gitops repositories"
echo ""

# Track results
created=0
exists=0
failed=0

# Register webhook for each repo
while IFS= read -r repo; do
    [[ -z "$repo" ]] && continue

    app_name=$(echo "$repo" | sed 's/.*gitops-[^-]*-//')

    # Check if webhook already exists
    existing_hooks=$(curl -s -k -u "$GITEA_USER:$GITEA_TOKEN" \
        "$GITEA_URL/api/v1/repos/$repo/hooks" 2>/dev/null)

    # Check if our webhook URL is already registered
    if echo "$existing_hooks" | jq -e ".[] | select(.config.url == \"$WEBHOOK_URL\")" &>/dev/null; then
        log_dim "  ✓ $app_name (already registered)"
        ((++exists))
        continue
    fi

    # Build webhook config
    webhook_config="{
        \"type\": \"gitea\",
        \"config\": {
            \"url\": \"$WEBHOOK_URL\",
            \"content_type\": \"json\"
        },
        \"events\": [\"push\"],
        \"active\": true
    }"

    # Add secret if configured
    if [[ -n "$WEBHOOK_SECRET" ]]; then
        webhook_config=$(echo "$webhook_config" | jq ".config.secret = \"$WEBHOOK_SECRET\"")
    fi

    # Create webhook
    result=$(curl -s -k -X POST \
        -u "$GITEA_USER:$GITEA_TOKEN" \
        -H "Content-Type: application/json" \
        "$GITEA_URL/api/v1/repos/$repo/hooks" \
        -d "$webhook_config" 2>/dev/null)

    if echo "$result" | jq -e '.id' &>/dev/null; then
        echo -e "  ${GREEN}+${NC} $app_name"
        ((++created))
    else
        error_msg=$(echo "$result" | jq -r '.message // "unknown error"' 2>/dev/null)
        log_warn "  Failed: $app_name ($error_msg)"
        ((++failed))
    fi

done <<< "$repos"

echo ""
log_info "Summary:"
log_dim "  Created: $created"
log_dim "  Already exists: $exists"
if [[ $failed -gt 0 ]]; then
    log_warn "  Failed: $failed"
fi

echo ""
if [[ $created -gt 0 || $exists -gt 0 ]]; then
    log_info "Webhooks configured. Start listener with: gitea-listen"
    log_dim "Or use 'devenv up' to start automatically"
fi
