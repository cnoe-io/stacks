#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "⚠️  $1"
}

log "🔧 Populating Backstage catalog with CAIPE components from ArgoCD"

# Get Backstage API token from Kubernetes secret
log "🔑 Retrieving Backstage API token..."
BACKSTAGE_TOKEN=$(kubectl get secret backstage-api-token -n backstage -o jsonpath='{.data.BACKSTAGE_API_TOKEN}' | base64 -d)

if [[ -z "$BACKSTAGE_TOKEN" ]]; then
    warn "No Backstage API token found"
    exit 1
else
    log "✅ Backstage API token retrieved (${#BACKSTAGE_TOKEN} chars)"
fi

# Start Backstage port forward
log "🔗 Starting Backstage port forward..."
kubectl port-forward -n backstage svc/backstage 7007:7007 &
BACKSTAGE_PID=$!
sleep 3

# Function to call Backstage API
backstage_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    if [[ -n "$data" ]]; then
        curl -s -X "$method" \
             -H "Authorization: Bearer $BACKSTAGE_TOKEN" \
             -H "Content-Type: application/json" \
             -d "$data" \
             "http://localhost:7007$endpoint"
    else
        curl -s -X "$method" \
             -H "Authorization: Bearer $BACKSTAGE_TOKEN" \
             -H "Content-Type: application/json" \
             "http://localhost:7007$endpoint"
    fi
}

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
      "platform": "caipe",
      "environment": "production"
    },
    "annotations": {
      "argocd/app-name": "ai-platform-engineering"
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
elif echo "$response" | grep -q "already exists"; then
    log "✅ CAIPE platform system entity already exists"
else
    log "⚠️  System entity response: $response"
fi

# Define CAIPE components based on actual ArgoCD deployments
log "🏗️  Creating CAIPE component entities..."

declare -A CAIPE_COMPONENTS=(
    ["agent-argocd"]="ArgoCD Agent - GitOps deployment automation and management"
    ["agent-argocd-mcp"]="ArgoCD MCP Agent - Model Context Protocol integration for ArgoCD"
    ["agent-backstage"]="Backstage Agent - Developer portal integration and catalog management"
    ["agent-backstage-mcp"]="Backstage MCP Agent - Model Context Protocol integration for Backstage"
    ["agent-github"]="GitHub Agent - Repository management and automation"
    ["backstage-plugin-agent-forge"]="Agent Forge Plugin - Backstage plugin for AI agent management"
    ["supervisor-agent"]="Supervisor Agent - Orchestrates and monitors all CAIPE agents"
)

for component_name in "${!CAIPE_COMPONENTS[@]}"; do
    description="${CAIPE_COMPONENTS[$component_name]}"
    
    log "📦 Creating component: $component_name"
    
    catalog_entity=$(cat <<EOF
{
  "apiVersion": "backstage.io/v1alpha1",
  "kind": "Component",
  "metadata": {
    "name": "$component_name",
    "description": "$description",
    "labels": {
      "platform": "caipe",
      "environment": "production",
      "component-type": "agent"
    },
    "annotations": {
      "backstage.io/managed-by-location": "url:https://github.com/sriaradhyula/stacks/tree/main/caipe",
      "argocd/app-name": "ai-platform-engineering",
      "kubernetes.io/deployment": "ai-platform-engineering-$component_name"
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
        log "✅ Successfully registered $component_name in Backstage catalog"
    elif echo "$response" | grep -q "already exists"; then
        log "✅ Component $component_name already exists in catalog"
    else
        log "⚠️  Response for $component_name: $response"
    fi
    
    sleep 1  # Rate limiting
done

# Test API access and list entities
log "📋 Listing CAIPE entities from catalog..."
all_entities=$(backstage_api "GET" "/api/catalog/entities")
caipe_entities=$(echo "$all_entities" | jq -r '.[] | select(.metadata.labels.platform == "caipe") | "\(.kind): \(.metadata.name) - \(.metadata.description // "No description")"' 2>/dev/null || echo "")

if [[ -n "$caipe_entities" ]]; then
    log "✅ Found CAIPE entities:"
    echo "$caipe_entities"
else
    log "⚠️  No CAIPE entities found via API"
fi

# Show total entity count
total_entities=$(echo "$all_entities" | jq '. | length' 2>/dev/null || echo "0")
log "📊 Total entities in catalog: $total_entities"

# Cleanup
kill $BACKSTAGE_PID 2>/dev/null || true

echo ""
echo "✅ CAIPE COMPONENTS ADDED:"
echo "- System: caipe-platform"
echo "- Agents: agent-argocd, agent-backstage, agent-github"
echo "- MCP Agents: agent-argocd-mcp, agent-backstage-mcp"
echo "- Plugins: backstage-plugin-agent-forge"
echo "- Orchestration: supervisor-agent"

echo ""
echo "🔍 VIEW ENTITIES:"
echo "Web UI: https://cnoe.localtest.me:8443/backstage/catalog"
echo "Filter by: platform=caipe"

log "🎉 Backstage catalog population complete!"
