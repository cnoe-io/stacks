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

# Check if vault is available
if ! command -v vault &> /dev/null; then
    error "vault is not installed or not in PATH"
    exit 1
fi

# Setup Vault connection
log "Setting up Vault connection..."
kubectl port-forward -n vault svc/vault 8200:8200 &
VAULT_PID=$!
sleep 3

VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN

# Define secret mappings: vault_path:k8s_secret_name:namespace:deployment_names
SECRET_MAPPINGS=(
    "secret/ai-platform-engineering/github-secret:github-secret:ai-platform-engineering:github-agent"
    "secret/ai-platform-engineering/jira-secret:jira-secret:ai-platform-engineering:jira-agent"
    "secret/ai-platform-engineering/slack-secret:slack-secret:ai-platform-engineering:slack-agent"
    "secret/ai-platform-engineering/aws-secret:aws-secret:ai-platform-engineering:aws-agent"
    "secret/ai-platform-engineering/argocd-agent-secret:argocd-agent-secret:ai-platform-engineering:argocd-agent"
    "secret/ai-platform-engineering/backstage-agent-secret:backstage-agent-secret:ai-platform-engineering:backstage-agent"
    "secret/ai-platform-engineering/pagerduty-secret:pagerduty-secret:ai-platform-engineering:pagerduty-agent"
    "secret/ai-platform-engineering/confluence-secret:confluence-secret:ai-platform-engineering:confluence-agent"
    "secret/ai-platform-engineering/splunk-secret:splunk-secret:ai-platform-engineering:splunk-agent"
    "secret/ai-platform-engineering/webex-secret:webex-secret:ai-platform-engineering:webex-agent"
    "secret/ai-platform-engineering/komodor-secret:komodor-secret:ai-platform-engineering:komodor-agent"
    "secret/llm-credentials:llm-credentials:ai-platform-engineering:llm-service,chat-service"
)

# Function to check if Vault secret exists and has data
check_vault_secret() {
    local vault_path="$1"
    if vault kv get "$vault_path" >/dev/null 2>&1; then
        local data=$(vault kv get -format=json "$vault_path" | jq -r '.data.data | keys | length')
        if [[ "$data" -gt 0 ]]; then
            return 0
        fi
    fi
    return 1
}

# Function to delete and wait for K8s secret recreation
refresh_k8s_secret() {
    local secret_name="$1"
    local namespace="$2"
    
    log "Checking if secret $secret_name exists in namespace $namespace..."
    if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        log "Deleting K8s secret $secret_name in namespace $namespace..."
        kubectl delete secret "$secret_name" -n "$namespace"
        
        log "Waiting for External Secrets to recreate $secret_name..."
        local timeout=60
        local count=0
        while [[ $count -lt $timeout ]]; do
            if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
                success "Secret $secret_name recreated successfully"
                return 0
            fi
            sleep 2
            ((count+=2))
        done
        
        warn "Secret $secret_name not recreated within ${timeout}s"
        return 1
    else
        warn "Secret $secret_name does not exist in namespace $namespace"
        return 1
    fi
}

# Function to restart deployments
restart_deployments() {
    local deployments="$1"
    local namespace="$2"
    
    IFS=',' read -ra DEPLOY_ARRAY <<< "$deployments"
    for deployment in "${DEPLOY_ARRAY[@]}"; do
        log "Checking if deployment $deployment exists in namespace $namespace..."
        if kubectl get deployment "$deployment" -n "$namespace" >/dev/null 2>&1; then
            log "Restarting deployment $deployment in namespace $namespace..."
            kubectl rollout restart deployment/"$deployment" -n "$namespace"
            kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout=300s
            success "Deployment $deployment restarted successfully"
        else
            warn "Deployment $deployment does not exist in namespace $namespace"
        fi
    done
}

# Main processing loop
log "Starting secret refresh process..."

for mapping in "${SECRET_MAPPINGS[@]}"; do
    IFS=':' read -r vault_path k8s_secret namespace deployments <<< "$mapping"
    
    echo ""
    log "Processing: $vault_path -> $k8s_secret"
    
    # Check if Vault secret exists and has data
    if check_vault_secret "$vault_path"; then
        success "Vault secret $vault_path exists and has data"
        
        # Refresh K8s secret
        if refresh_k8s_secret "$k8s_secret" "$namespace"; then
            # Restart deployments
            restart_deployments "$deployments" "$namespace"
        else
            error "Failed to refresh secret $k8s_secret, skipping deployment restart"
        fi
    else
        warn "Vault secret $vault_path does not exist or has no data, skipping..."
    fi
done

# Cleanup
kill $VAULT_PID 2>/dev/null || true

echo ""
success "Secret refresh process completed!"
log "All secrets have been refreshed and deployments restarted where applicable"
