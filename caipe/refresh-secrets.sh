#!/bin/bash

set -euo pipefail

echo "🚀 Starting AI Platform Engineering cleanup process..."
echo ""

echo "🔑 Deleting all secrets in ai-platform-engineering namespace..."
kubectl delete secret --all -n ai-platform-engineering

echo ""
echo "⏱️  Waiting 5 second for cleanup to complete..."
sleep 5

echo ""
echo "📝 Command executed: kubectl delete secret --all -n ai-platform-engineering"
echo ""

echo "🗑️  Deleting all pods in ai-platform-engineering namespace..."
kubectl delete pod --all -n ai-platform-engineering

echo ""
echo "📊 Current pods in ai-platform-engineering namespace:"
echo "=================================================="
kubectl get pods -n ai-platform-engineering

echo ""
echo "✅ Cleanup process completed successfully!"
echo "🎯 All secrets and pods have been refreshed in the ai-platform-engineering namespace"
