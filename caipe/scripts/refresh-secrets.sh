#!/bin/bash

set -euo pipefail

echo "🚀 Starting AI Platform Engineering cleanup process..."
echo ""

echo "🔑 Deleting all secrets in ai-platform-engineering namespace..."
kubectl delete secret --all -n ai-platform-engineering > /dev/null

echo ""
echo "⏱️  Waiting 1 second for cleanup to complete..."
sleep 1

echo ""
echo "📝 Command executed: kubectl delete secret --all -n ai-platform-engineering"
echo ""

echo "🗑️ Deleting all pods in ai-platform-engineering namespace..."
kubectl delete pod --all -n ai-platform-engineering > /dev/null

echo ""
echo "⏳ Sleep for 5s to wait for the new pods to get ready"
sleep 5

echo ""
echo "📊 Current pods in ai-platform-engineering namespace:"
echo "=================================================="
kubectl get pods -n ai-platform-engineering | awk 'NR==1 || !/Running/'

echo ""
echo "✅ Cleanup process completed successfully!"
echo "🎯 All secrets and pods have been refreshed in the ai-platform-engineering namespace"
