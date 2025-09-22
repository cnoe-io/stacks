#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "⚠️  $1"
}

# Check dependencies
for cmd in kubectl vault jq curl; do
    if ! command -v $cmd &> /dev/null; then
        log "❌ $cmd is required but not installed"
        exit 1
    fi
done

log "🔧 Populating Backstage catalog with ArgoCD deployment details"

# Setup Vault connection
VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN

# Start port forward
log "🔗 Starting Vault port forward..."
kubectl port-forward -n vault svc/vault 8200:8200 &
VAULT_PID=$!
sleep 3

# Get ArgoCD admin password and Backstage tokens
log "🔑 Retrieving API credentials..."
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
ARGOCD_USERNAME="admin"

# Try to get Backstage credentials from Vault, fallback to defaults
if vault kv get secret/ai-platform-engineering/backstage-agent-secret >/dev/null 2>&1; then
    BACKSTAGE_TOKEN=$(vault kv get -field=BACKSTAGE_API_TOKEN secret/ai-platform-engineering/backstage-agent-secret 2>/dev/null || echo "")
    BACKSTAGE_URL=$(vault kv get -field=BACKSTAGE_URL secret/ai-platform-engineering/backstage-agent-secret 2>/dev/null || echo "http://backstage.backstage.svc.cluster.local:7007")
else
    warn "Backstage secrets not found in Vault, using defaults"
    BACKSTAGE_TOKEN=""
    BACKSTAGE_URL="http://backstage.backstage.svc.cluster.local:7007"
fi

# Start ArgoCD port forward
log "🔗 Starting ArgoCD port forward..."
kubectl port-forward -n argocd svc/argocd-server 8080:80 &
ARGOCD_PID=$!
sleep 3

# Start Backstage port forward
log "🔗 Starting Backstage port forward..."
kubectl port-forward -n backstage svc/backstage 7007:7007 &
BACKSTAGE_PID=$!
sleep 3

# Function to call ArgoCD API
argocd_api() {
    local endpoint="$1"
    curl -s -u "$ARGOCD_USERNAME:$ARGOCD_PASSWORD" \
         -H "Content-Type: application/json" \
         "http://localhost:8080$endpoint"
}

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

# Get ArgoCD applications
log "📊 Fetching ArgoCD applications..."
applications=$(argocd_api "/api/v1/applications")

if [[ -z "$applications" ]]; then
    log "❌ Failed to fetch ArgoCD applications"
    kill $VAULT_PID $BACKSTAGE_PID 2>/dev/null
    exit 1
fi

# Process each application
echo "$applications" | jq -r '.items[] | @base64' | while IFS= read -r app_data; do
    app=$(echo "$app_data" | base64 -d)
    
    app_name=$(echo "$app" | jq -r '.metadata.name')
    app_namespace=$(echo "$app" | jq -r '.metadata.namespace // "argocd"')
    sync_status=$(echo "$app" | jq -r '.status.sync.status // "Unknown"')
    health_status=$(echo "$app" | jq -r '.status.health.status // "Unknown"')
    repo_url=$(echo "$app" | jq -r '.spec.source.repoURL // "Unknown"')
    target_revision=$(echo "$app" | jq -r '.spec.source.targetRevision // "HEAD"')
    path=$(echo "$app" | jq -r '.spec.source.path // "."')
    
    log "📝 Processing application: $app_name"
    
    # Create Backstage catalog entity
    catalog_entity=$(cat <<EOF
{
  "apiVersion": "backstage.io/v1alpha1",
  "kind": "Component",
  "metadata": {
    "name": "$app_name",
    "title": "$app_name",
    "description": "ArgoCD managed application: $app_name",
    "annotations": {
      "argocd.argoproj.io/app-name": "$app_name",
      "argocd.argoproj.io/app-namespace": "$app_namespace",
      "backstage.io/managed-by-location": "argocd:$app_name",
      "backstage.io/source-location": "url:$repo_url"
    },
    "tags": [
      "argocd",
      "gitops",
      "kubernetes",
      "deployment"
    ],
    "links": [
      {
        "url": "https://cnoe.localtest.me:8443/argocd/applications/$app_name",
        "title": "ArgoCD Application",
        "icon": "dashboard"
      }
    ]
  },
  "spec": {
    "type": "service",
    "lifecycle": "production",
    "owner": "platform-team",
    "system": "caipe-platform",
    "providesApis": [],
    "consumesApis": [],
    "dependsOn": []
  },
  "status": {
    "argocd": {
      "syncStatus": "$sync_status",
      "healthStatus": "$health_status",
      "repoUrl": "$repo_url",
      "targetRevision": "$target_revision",
      "path": "$path",
      "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  }
}
EOF
)

    # Register with Backstage catalog
    response=$(backstage_api "POST" "/api/catalog/entities" "$catalog_entity")
    
    if echo "$response" | jq -e '.metadata.name' >/dev/null 2>&1; then
        log "✅ Successfully registered $app_name in Backstage catalog"
    else
        log "⚠️  Failed to register $app_name: $response"
    fi
    
    sleep 1  # Rate limiting
done

# Create system entity for CAIPE platform
log "🏗️  Creating CAIPE platform system entity..."
system_entity=$(cat <<EOF
{
  "apiVersion": "backstage.io/v1alpha1",
  "kind": "System",
  "metadata": {
    "name": "caipe-platform",
    "title": "CAIPE Platform",
    "description": "Cloud AI Platform Engineering - Complete internal developer platform",
    "annotations": {
      "backstage.io/managed-by-location": "argocd:caipe-platform"
    },
    "tags": [
      "platform",
      "ai",
      "gitops",
      "kubernetes"
    ]
  },
  "spec": {
    "owner": "platform-team",
    "domain": "platform-engineering"
  }
}
EOF
)

backstage_api "POST" "/api/catalog/entities" "$system_entity"
log "✅ CAIPE platform system entity created"

# Cleanup
kill $VAULT_PID $BACKSTAGE_PID $ARGOCD_PID 2>/dev/null
log "🎉 Backstage catalog population complete!"
log "🔍 View catalog at: https://cnoe.localtest.me:8443/backstage/catalog"
