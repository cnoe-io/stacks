#!/bin/bash

set -e

echo "🔄 Updating Gitea repositories with latest GitHub changes..."

# Clone latest from GitHub
TEMP_DIR="/tmp/stacks-sync"
rm -rf $TEMP_DIR
git clone https://github.com/sriaradhyula/stacks.git $TEMP_DIR

# Function to update ArgoCD application source
update_argocd_app() {
    local app_name=$1
    echo "🔄 Refreshing $app_name application..."
    kubectl patch application $app_name -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true"]}}}'
    kubectl patch application $app_name -n argocd --type merge -p '{"spec":{"source":{"targetRevision":"HEAD"}}}'
}

# Force ArgoCD to refresh from source
echo "🔄 Forcing ArgoCD to refresh applications..."
kubectl patch application backstage -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
kubectl patch application ai-platform-engineering -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Trigger manual sync
echo "🔄 Triggering manual sync..."
kubectl patch application backstage -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true"]}}}'
kubectl patch application ai-platform-engineering -n argocd --type merge -p '{"operation":{"sync":{"syncOptions":["CreateNamespace=true"]}}}'

echo "✅ Repository refresh completed!"
echo "ℹ️  Note: Changes will only appear if the source repositories in Gitea are updated."
echo "ℹ️  For full sync, consider running: ./recreate-idpbuilder.sh"

# Clean up
rm -rf $TEMP_DIR
