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
log "🔍 Verifying all pods are in Ready state..."
echo "=================================================="
kubectl get pods -n ai-platform-engineering

echo ""
log "📋 Checking pod readiness details..."
echo "=================================================="
kubectl get pods -n ai-platform-engineering -o wide

echo ""
log "🔬 Detailed pod status check..."
echo "=================================================="
kubectl get pods -n ai-platform-engineering -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].ready}{"\n"}{end}' | column -t -s $'\t'

echo ""
log "🔍 Checking for pods that are not ready..."
echo "=================================================="
not_ready_pods=$(kubectl get pods -n ai-platform-engineering --field-selector=status.phase=Running -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{"\n"}{end}')

if [[ -n "$not_ready_pods" ]]; then
    log "⚠️  Found pods that are Running but not Ready:"
    echo "$not_ready_pods"
    echo ""

    log "🔍 Checking pod events for troubleshooting..."
    echo "=================================================="
    for pod in $not_ready_pods; do
        log "📋 Events for pod: $pod"
        kubectl describe pod $pod -n ai-platform-engineering | grep -A 10 "Events:"
        echo ""
    done

    log "🔍 Checking container logs for troubleshooting..."
    echo "=================================================="
    for pod in $not_ready_pods; do
        log "📋 Logs for pod: $pod"
        kubectl logs $pod -n ai-platform-engineering --tail=20
        echo ""
    done

    log "⏳ Waiting additional time for readiness checks..."
    sleep 30

    log "🔍 Re-checking pod status after additional wait..."
    echo "=================================================="
    kubectl get pods -n ai-platform-engineering

    # Check if still not ready
    still_not_ready=$(kubectl get pods -n ai-platform-engineering --field-selector=status.phase=Running -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{"\n"}{end}')

    if [[ -n "$still_not_ready" ]]; then
        log "⚠️  Some pods are still not ready after extended wait:"
        echo "$still_not_ready"
        log "💡 You may need to check the application configuration or logs manually"
    else
        log "✅ All pods are now ready after extended wait!"
    fi
else
    log "✅ All pods are in Ready state!"
fi

echo ""
log "⏳ Final readiness verification..."
# Wait a bit more and check again to ensure stability
sleep 5
kubectl get pods -n ai-platform-engineering

echo ""
log "📊 Final status summary..."
echo "=================================================="
kubectl get pods -n ai-platform-engineering -o wide

echo ""
log "✅ Refresh process completed successfully!"
log "🎯 All secrets have been refreshed and deployments restarted in the ai-platform-engineering namespace"
