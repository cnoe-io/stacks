#!/bin/bash
# create-azure-ad-app.sh - Creates Azure AD app registration early in the setup process
# This script creates only the Azure AD app and service principal, without federated credentials
# Federated credentials will be added later when service accounts are created

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT is one level up from scripts/
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Determine environment file based on cluster type
if [[ -n "${ENV_FILE:-}" ]]; then
    # Use provided ENV_FILE
    ENV_FILE="$ENV_FILE"
elif [[ "${CLUSTER_TYPE:-}" = "aks" ]]; then
    # For AKS clusters, use production env file
    ENV_FILE="${PROJECT_ROOT}/.env-files/production.env"
else
    # Default to kind.env for KIND clusters
    ENV_FILE="${PROJECT_ROOT}/.env-files/kind.env"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ Error: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}"
}

# Load environment variables
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    error "Environment file not found at $ENV_FILE"
fi

# Validate required variables
if [[ -z "${AZURE_TENANT_ID:-}" ]] || [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    error "Missing required Azure configuration in $ENV_FILE"
fi

# Check Azure CLI login
log "Checking Azure CLI login status..."
if ! az account show &>/dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
fi

# Set subscription
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# Determine app name based on kubectl context
# Use KUBECTL_CONTEXT if provided, otherwise use CLUSTER
CONTEXT_TO_USE="${KUBECTL_CONTEXT:-${CLUSTER:-}}"

if [[ -n "$CONTEXT_TO_USE" ]]; then
    # Detect cluster type by looking at the server URL
    SERVER=$(kubectl config view --context="$CONTEXT_TO_USE" -o jsonpath="{.clusters[?(@.name=='$CONTEXT_TO_USE')].cluster.server}" 2>/dev/null || echo "")
    
    if [[ "$SERVER" =~ azmk8s\.io ]]; then
        # AKS cluster
        APP_NAME="gitops-aks-${CONTEXT_TO_USE}"
    elif [[ "$SERVER" =~ (127\.0\.0\.1|localhost) ]]; then
        # KIND cluster
        APP_NAME="gitops-${CONTEXT_TO_USE}"
    else
        # Unknown cluster type, use context as-is
        APP_NAME="gitops-${CONTEXT_TO_USE}"
    fi
    log "Using cluster context: $CONTEXT_TO_USE"
else
    # No context available, use default
    APP_NAME="gitops-app"
    log "No kubectl context found, using default app name"
fi

log "Using Azure AD app name: $APP_NAME"

APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -z "$APP_ID" ]]; then
    log "Creating new Azure AD app: $APP_NAME"
    APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
    success "Created Azure AD app with ID: $APP_ID"
    
    # Create service principal
    log "Creating service principal for app..."
    SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
    if [[ -n "$SP_ID" ]]; then
        success "Created service principal: $SP_ID"
    else
        log "Service principal may already exist"
    fi
else
    success "Using existing Azure AD app: $APP_ID"
    
    # Ensure service principal exists
    SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
    if [[ -z "$SP_ID" ]]; then
        log "Creating service principal for existing app..."
        SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
        success "Created service principal: $SP_ID"
    else
        success "Service principal already exists: $SP_ID"
    fi
fi

# Update environment file with APP_ID and AZURE_CLIENT_ID
log "Updating $ENV_FILE with APP_ID and AZURE_CLIENT_ID..."

# Update or add APP_ID (legacy support)
if grep -q "^APP_ID=" "$ENV_FILE"; then
    sed -i "s/^APP_ID=.*/APP_ID=$APP_ID/" "$ENV_FILE"
else
    echo "APP_ID=$APP_ID" >> "$ENV_FILE"
fi

# Update or add AZURE_CLIENT_ID (preferred)
if grep -q "^AZURE_CLIENT_ID=" "$ENV_FILE"; then
    sed -i "s/^AZURE_CLIENT_ID=.*/AZURE_CLIENT_ID=$APP_ID/" "$ENV_FILE"
else
    echo "AZURE_CLIENT_ID=$APP_ID" >> "$ENV_FILE"
fi

success "Azure AD app registration complete!"
echo ""
echo "App Name: $APP_NAME"
echo "App ID: $APP_ID"
echo ""
echo "This app will be used for workload identity federation later in the setup process."