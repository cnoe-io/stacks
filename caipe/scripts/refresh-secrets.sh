#!/bin/bash

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting AI Platform Engineering refresh process..."
echo ""

log "🔑 Deleting all secrets in ai-platform-engineering namespace..."
kubectl delete secret --all -n ai-platform-engineering

echo ""
log "⏱️  Waiting 2 seconds for cleanup to complete..."
sleep 2

echo ""
log "🔄 Restarting all deployments in ai-platform-engineering namespace..."
kubectl rollout restart deployment -n ai-platform-engineering

echo ""
log "⏳ Waiting for all deployments to be ready..."
kubectl rollout status deployment -n ai-platform-engineering --timeout=300s

echo ""
log "🔍 Checking deployment status..."
echo "=================================================="
kubectl get deployments -n ai-platform-engineering

echo ""
log "📊 Current pods in ai-platform-engineering namespace:"
echo "=================================================="
kubectl get pods -n ai-platform-engineering

echo ""
log "⏳ Waiting for all pods to be running and ready..."
kubectl wait --for=condition=ready pod --all -n ai-platform-engineering --timeout=300s

echo ""
log "✅ Final status check..."
echo "=================================================="
kubectl get pods -n ai-platform-engineering

echo ""
log "✅ Refresh process completed successfully!"
log "🎯 All secrets have been refreshed and deployments restarted in the ai-platform-engineering namespace"
