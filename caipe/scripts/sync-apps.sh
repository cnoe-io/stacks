#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if argocd CLI is available
if ! command -v argocd &> /dev/null; then
    warn "argocd CLI not found, will use kubectl for ArgoCD operations"
    USE_KUBECTL=true
else
    USE_KUBECTL=false
fi

# ArgoCD applications to sync
APPS=(
    "backstage"
    "vault"
    "argocd"
    "ai-platform-engineering"
    "external-secrets"
    "ingress-nginx"
    "gitea"
)

# Function to check if app exists
app_exists() {
    local app_name="$1"
    kubectl get application "$app_name" -n argocd >/dev/null 2>&1
}

# Function to get app sync status
get_app_status() {
    local app_name="$1"
    kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown"
}

# Function to get app health status
get_app_health() {
    local app_name="$1"
    kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown"
}

# Function to sync app using kubectl
sync_app_kubectl() {
    local app_name="$1"
    log "Syncing $app_name using kubectl..."

    # Trigger sync by adding annotation
    kubectl annotate application "$app_name" -n argocd argocd.argoproj.io/refresh=normal --overwrite

    # Wait a moment for the annotation to take effect
    sleep 2

    # Remove the annotation
    kubectl annotate application "$app_name" -n argocd argocd.argoproj.io/refresh- || true
}

# Function to sync app using argocd CLI
sync_app_argocd() {
    local app_name="$1"
    log "Syncing $app_name using argocd CLI..."

    # Login to ArgoCD (assuming port-forward is available)
    argocd login argocd.cnoe.localtest.me:8443 --username admin --password "$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)" --insecure

    # Sync the application
    argocd app sync "$app_name" --timeout 300
}

# Function to wait for app to be synced and healthy
wait_for_app_sync() {
    local app_name="$1"
    local timeout=300
    local count=0

    log "Waiting for $app_name to sync and become healthy..."

    while [[ $count -lt $timeout ]]; do
        local sync_status=$(get_app_status "$app_name")
        local health_status=$(get_app_health "$app_name")

        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            success "$app_name is synced and healthy"
            return 0
        fi

        if [[ $((count % 30)) -eq 0 ]]; then
            log "$app_name status: sync=$sync_status, health=$health_status"
        fi

        sleep 5
        ((count+=5))
    done

    warn "$app_name did not become synced and healthy within ${timeout}s"
    return 1
}

# Main sync process
log "Starting ArgoCD application sync process..."

# Check if ArgoCD is available
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    error "ArgoCD namespace not found. Is ArgoCD installed?"
    exit 1
fi

echo ""
log "Checking application status before sync..."

# Show current status
for app in "${APPS[@]}"; do
    if app_exists "$app"; then
        sync_status=$(get_app_status "$app")
        health_status=$(get_app_health "$app")
        log "$app: sync=$sync_status, health=$health_status"
    else
        warn "$app: Application not found"
    fi
done

echo ""
log "Starting sync process..."

# Sync each application
for app in "${APPS[@]}"; do
    if app_exists "$app"; then
        echo ""
        log "Processing application: $app"

        if [[ "$USE_KUBECTL" == "true" ]]; then
            sync_app_kubectl "$app"
        else
            sync_app_argocd "$app"
        fi

        # Wait for sync to complete
        wait_for_app_sync "$app"
    else
        warn "Skipping $app - application not found"
    fi
done

echo ""
log "Final application status check..."

# Show final status
for app in "${APPS[@]}"; do
    if app_exists "$app"; then
        sync_status=$(get_app_status "$app")
        health_status=$(get_app_health "$app")

        if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
            success "$app: sync=$sync_status, health=$health_status"
        else
            warn "$app: sync=$sync_status, health=$health_status"
        fi
    fi
done

echo ""
success "Application sync process completed!"
log "All available applications have been processed"
