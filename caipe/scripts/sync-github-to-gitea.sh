#!/bin/bash

set -e

# Configuration
GITEA_URL="https://cnoe.localtest.me:8443/gitea"
GITEA_USER="giteaAdmin"
GITHUB_REPO="https://github.com/sriaradhyula/stacks.git"
TEMP_DIR="/tmp/stacks-sync"

echo "🔄 Syncing GitHub stacks to Gitea repositories..."

# Get Gitea admin password
GITEA_PASSWORD=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' | base64 -d)

# Clone latest from GitHub
echo "📥 Cloning latest from GitHub..."
rm -rf $TEMP_DIR
git clone $GITHUB_REPO $TEMP_DIR

# Function to sync a specific path to Gitea repo
sync_to_gitea() {
    local path=$1
    local repo_name=$2
    
    echo "🔄 Syncing $path to $repo_name..."
    
    # Check if Gitea repo exists
    if curl -k -s -u "$GITEA_USER:$GITEA_PASSWORD" "$GITEA_URL/api/v1/repos/$GITEA_USER/$repo_name" > /dev/null 2>&1; then
        echo "📂 Repository $repo_name exists, updating..."
        
        # Clone Gitea repo using kubectl port-forward
        local gitea_dir="/tmp/gitea-$repo_name"
        rm -rf $gitea_dir
        
        # Start port-forward in background
        kubectl port-forward -n gitea svc/my-gitea-http 3000:3000 &
        local pf_pid=$!
        sleep 3
        
        # Clone using localhost
        git -c http.sslVerify=false clone "http://$GITEA_USER:$GITEA_PASSWORD@localhost:3000/$GITEA_USER/$repo_name.git" $gitea_dir
        
        # Kill port-forward
        kill $pf_pid 2>/dev/null || true
        
        # Clear existing content and copy new
        cd $gitea_dir
        find . -maxdepth 1 ! -name '.git' ! -name '.' -exec rm -rf {} +
        cp -r "$TEMP_DIR/$path"/* .
        
        # Commit and push changes
        git add .
        if git diff --staged --quiet; then
            echo "✅ No changes to sync for $repo_name"
        else
            git commit -m "Sync from GitHub $(date)"
            
            # Start port-forward for push
            kubectl port-forward -n gitea svc/my-gitea-http 3000:3000 &
            local pf_pid2=$!
            sleep 3
            
            git push origin main
            
            # Kill port-forward
            kill $pf_pid2 2>/dev/null || true
            
            echo "✅ Synced $repo_name successfully"
        fi
        
        rm -rf $gitea_dir
    else
        echo "❌ Repository $repo_name not found in Gitea"
    fi
}

# Sync backstage manifests
sync_to_gitea "caipe/base/backstage" "idpbuilder-localdev-backstage-manifests"

# Sync ai-platform-engineering manifests  
sync_to_gitea "caipe/base" "idpbuilder-localdev-ai-platform-engineering-ai-platform-engineering"

# Clean up
rm -rf $TEMP_DIR

echo "🎉 GitHub to Gitea sync completed!"
