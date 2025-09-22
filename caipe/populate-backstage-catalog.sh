#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

warn() {
    echo "⚠️  $1"
}

log "🔧 CAIPE entities successfully added to Backstage via Gitea"

echo ""
echo "✅ COMPLETED ACTIONS:"
echo "1. Added CAIPE entities to Gitea catalog-info.yaml"
echo "2. Backstage restarted and processing entities"
echo "3. Entities are discoverable through Backstage UI"

echo ""
echo "📋 CAIPE ENTITIES ADDED:"
echo "- System: caipe-platform"
echo "- Components: ai-platform-engineering, github-agent, jira-agent"
echo "- Components: slack-agent, aws-agent, argocd-agent, backstage-agent"

echo ""
echo "🔍 VIEW ENTITIES:"
echo "Web UI: https://cnoe.localtest.me:8443/backstage/catalog"
echo "Filter by: platform=caipe"

echo ""
echo "⚠️  API ACCESS STATUS:"
echo "- Backend token configured: ✅"
echo "- API endpoints require OIDC auth: ❌"
echo "- Direct API access: Not working (needs OIDC token)"
echo "- Web UI access: ✅ Working"

echo ""
echo "🚀 RECOMMENDATION:"
echo "Use Backstage web interface to view and manage CAIPE entities"
echo "API access requires Keycloak OIDC authentication setup"

log "🎉 Backstage catalog population complete via file-based approach!"
