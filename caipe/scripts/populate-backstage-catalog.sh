#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "⚠️  $1"
}

log "🔧 Registering CAIPE catalog location in Backstage"

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

# Register GitHub catalog-info.yaml as a location
log "📍 Registering CAIPE catalog location..."

location_data='{
  "type": "url",
  "target": "https://raw.githubusercontent.com/sriaradhyula/stacks/main/caipe/catalog-info.yaml"
}'

response=$(backstage_api "POST" "/api/catalog/locations" "$location_data")

if echo "$response" | jq -e '.location.id' >/dev/null 2>&1; then
    location_id=$(echo "$response" | jq -r '.location.id')
    log "✅ Successfully registered CAIPE catalog location: $location_id"
else
    log "⚠️  Location registration response: $response"
fi

# Trigger catalog refresh to process the new location
log "🔄 Triggering catalog refresh..."
refresh_response=$(backstage_api "POST" "/api/catalog/refresh")
log "✅ Catalog refresh triggered"

# Wait a moment for processing
sleep 5

# Check current locations
log "📋 Checking registered locations..."
locations=$(backstage_api "GET" "/api/catalog/locations")
github_locations=$(echo "$locations" | jq -r '.[] | select(.target | contains("github.com/sriaradhyula/stacks")) | .target' 2>/dev/null || echo "")

if [[ -n "$github_locations" ]]; then
    log "✅ Found GitHub CAIPE location:"
    echo "$github_locations"
else
    log "⚠️  GitHub CAIPE location not found in registered locations"
fi

# List all entities to see if CAIPE components are now available
log "📊 Checking catalog entities..."
all_entities=$(backstage_api "GET" "/api/catalog/entities")
total_entities=$(echo "$all_entities" | jq '. | length' 2>/dev/null || echo "0")
log "📊 Total entities in catalog: $total_entities"

# Look for CAIPE entities
caipe_entities=$(echo "$all_entities" | jq -r '.[] | select(.metadata.labels.platform == "caipe") | "\(.kind): \(.metadata.name) - \(.metadata.description // "No description")"' 2>/dev/null || echo "")

if [[ -n "$caipe_entities" ]]; then
    log "✅ Found CAIPE entities:"
    echo "$caipe_entities"
else
    log "⚠️  CAIPE entities not yet visible (may take a few minutes to process)"
    # Show any entities that might be related
    echo "$all_entities" | jq -r '.[] | select(.metadata.name | contains("caipe") or contains("agent")) | "\(.kind): \(.metadata.name)"' 2>/dev/null | head -5 || echo "No related entities found"
fi

# Cleanup
kill $BACKSTAGE_PID 2>/dev/null || true

echo ""
echo "✅ CAIPE CATALOG REGISTRATION COMPLETE:"
echo "- Location: https://raw.githubusercontent.com/sriaradhyula/stacks/main/caipe/catalog-info.yaml"
echo "- Entities will appear in UI within a few minutes"
echo "- Web UI: https://cnoe.localtest.me:8443/backstage/catalog"
echo "- Filter by: platform=caipe"

log "🎉 Backstage catalog location registration complete!"
