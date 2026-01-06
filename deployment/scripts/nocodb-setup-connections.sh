#!/usr/bin/env bash
# NoCoDB External Database Connection Setup
#
# Usage:
#   1. Log into NoCoDB at https://nocodb.cnoe.localtest.me:8443
#   2. Go to Account Settings > API Tokens > Create Token
#   3. Run: ./nocodb-setup-connections.sh <your-api-token>
#
# This script creates two external database connections:
#   - Backstage Catalog (PostgreSQL)
#   - Langfuse Observability (PostgreSQL)

set -euo pipefail

NOCODB_URL="${NOCODB_URL:-https://nocodb.cnoe.localtest.me:8443}"
API_TOKEN="${1:-}"

if [[ -z "$API_TOKEN" ]]; then
    echo "Usage: $0 <api-token>"
    echo ""
    echo "To get an API token:"
    echo "  1. Open $NOCODB_URL"
    echo "  2. Click your avatar (bottom-left) > Account Settings"
    echo "  3. Go to 'Tokens' tab"
    echo "  4. Click 'Add new token'"
    echo "  5. Copy the token and run this script again"
    exit 1
fi

echo "=== NoCoDB External Database Setup ==="
echo ""

# Function to create external database connection
create_base() {
    local name="$1"
    local host="$2"
    local port="$3"
    local database="$4"
    local user="$5"
    local password="$6"

    echo "Creating base: $name..."

    # Create a new base with external PostgreSQL connection
    response=$(curl -s -X POST "$NOCODB_URL/api/v2/meta/bases" \
        -H "xc-token: $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"title\": \"$name\",
            \"sources\": [{
                \"type\": \"pg\",
                \"config\": {
                    \"client\": \"pg\",
                    \"connection\": {
                        \"host\": \"$host\",
                        \"port\": $port,
                        \"user\": \"$user\",
                        \"password\": \"$password\",
                        \"database\": \"$database\"
                    }
                }
            }]
        }")

    if echo "$response" | grep -q '"id"'; then
        base_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "  ✓ Created base: $name (ID: $base_id)"
    else
        echo "  ✗ Failed to create base: $name"
        echo "    Response: $response"
    fi
}

# Backstage Catalog Database
create_base \
    "Backstage Catalog" \
    "postgresql.backstage.svc.cluster.local" \
    5432 \
    "backstage_plugin_catalog" \
    "backstage" \
    'mhWvo3/+AtRQazkcQwhFj02V5leKQPCyPAEs'

# Langfuse Observability Database
create_base \
    "Langfuse Observability" \
    "langfuse-postgres.observability.svc.cluster.local" \
    5432 \
    "langfuse" \
    "langfuse" \
    "pWPkjDbXJdj2jjjYMvBTUw4SGQWX8dbT"

echo ""
echo "=== Setup Complete ==="
echo "Open $NOCODB_URL to view your new database connections."
echo ""
echo "Available tables:"
echo "  Backstage Catalog:"
echo "    - final_entities (catalog items)"
echo "    - relations (entity relationships)"
echo "    - locations (source locations)"
echo ""
echo "  Langfuse Observability:"
echo "    - traces, observations, scores"
echo "    - prompts, projects, datasets"
echo "    - users, api_keys, and more"
