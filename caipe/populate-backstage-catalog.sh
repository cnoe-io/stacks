#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "⚠️  $1"
}

# Check dependencies
for cmd in kubectl jq curl; do
    if ! command -v $cmd &> /dev/null; then
        log "❌ $cmd is required but not installed"
        exit 1
    fi
done

log "🔧 Populating Backstage catalog with basic CAIPE entities"

# Get Backstage API token from Kubernetes secret
log "🔑 Retrieving Backstage API token..."
BACKSTAGE_TOKEN=$(kubectl get secret backstage-api-token -n backstage -o jsonpath='{.data.BACKSTAGE_API_TOKEN}' | base64 -d)

if [[ -z "$BACKSTAGE_TOKEN" ]]; then
    warn "No Backstage API token found, API calls may fail"
else
    log "✅ Backstage API token retrieved (${#BACKSTAGE_TOKEN} chars)"
fi

# Start Backstage port forward
log "🔗 Starting Backstage port forward..."
kubectl port-forward -n backstage svc/backstage 3000:7007 &
BACKSTAGE_PID=$!
sleep 3

# Function to call Backstage API
backstage_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    local auth_header=""
    if [[ -n "$BACKSTAGE_TOKEN" ]]; then
        auth_header="-H \"Authorization: Bearer $BACKSTAGE_TOKEN\""
    fi
    
    if [[ -n "$data" ]]; then
        eval curl -s -X "$method" \
             $auth_header \
             -H "Content-Type: application/json" \
             -d "'$data'" \
             "http://localhost:3000$endpoint"
    else
        eval curl -s -X "$method" \
             $auth_header \
             -H "Content-Type: application/json" \
             "http://localhost:3000$endpoint"
    fi
}

# Create basic CAIPE applications as Backstage components
log "🏗️  Creating CAIPE application components..."

# Define basic CAIPE applications
declare -A CAIPE_APPS=(
    ["ai-platform-engineering"]="AI Platform Engineering - Main CAIPE stack"
    ["github-agent"]="GitHub Agent - Repository management"
    ["jira-agent"]="Jira Agent - Issue tracking integration"
    ["slack-agent"]="Slack Agent - Team communication"
    ["aws-agent"]="AWS Agent - Cloud resource management"
    ["argocd-agent"]="ArgoCD Agent - GitOps deployment"
    ["backstage-agent"]="Backstage Agent - Developer portal integration"
)

for app_name in "${!CAIPE_APPS[@]}"; do
    description="${CAIPE_APPS[$app_name]}"
    
    log "📦 Creating component: $app_name"
    
    catalog_entity=$(cat <<EOF
{
  "apiVersion": "backstage.io/v1alpha1",
  "kind": "Component",
  "metadata": {
    "name": "$app_name",
    "description": "$description",
    "labels": {
      "platform": "caipe",
      "environment": "production"
    },
    "annotations": {
      "backstage.io/managed-by-location": "url:https://github.com/sriaradhyula/stacks/tree/main/caipe",
      "argocd/app-name": "$app_name"
    }
  },
  "spec": {
    "type": "service",
    "lifecycle": "production",
    "owner": "platform-team",
    "system": "caipe-platform"
  }
}
EOF
)

    # Register with Backstage catalog
    response=$(backstage_api "POST" "/api/catalog/entities" "$catalog_entity")
    
    if echo "$response" | jq -e '.metadata.name' >/dev/null 2>&1; then
        log "✅ Successfully registered $app_name in Backstage catalog"
    else
        log "⚠️  Response for $app_name: $response"
    fi
    
    sleep 1  # Rate limiting
done

# Create CAIPE platform system entity
log "🏗️  Creating CAIPE platform system entity..."

system_entity=$(cat <<EOF
{
  "apiVersion": "backstage.io/v1alpha1",
  "kind": "System",
  "metadata": {
    "name": "caipe-platform",
    "description": "Cloud AI Platform Engineering - Complete AI-powered platform engineering solution",
    "labels": {
      "platform": "caipe"
    }
  },
  "spec": {
    "owner": "platform-team",
    "domain": "platform-engineering"
  }
}
EOF
)

response=$(backstage_api "POST" "/api/catalog/entities" "$system_entity")
if echo "$response" | jq -e '.metadata.name' >/dev/null 2>&1; then
    log "✅ CAIPE platform system entity created"
else
    log "⚠️  System entity response: $response"
fi

# Cleanup
kill $BACKSTAGE_PID 2>/dev/null || true
log "🎉 Backstage catalog population complete!"
log "🔍 View catalog at: https://cnoe.localtest.me:8443/backstage/catalog"
