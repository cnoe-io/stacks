#!/bin/bash

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "[Step 1/5] Starting AI Platform Engineering cleanup process..."

log "[Step 2/5] Deleting all secrets in ai-platform-engineering namespace..."
kubectl delete secret --all -n ai-platform-engineering > /dev/null

log "[Step 3/5] Waiting 1 second for cleanup to complete..."
sleep 1

log "[Step 4/5] Deleting all pods in ai-platform-engineering namespace..."
kubectl delete pod --all -n ai-platform-engineering > /dev/null

log "[Step 5/5] Sleep for 5s to wait for the new pods to get ready"
sleep 5

NON_RUNNING=$(kubectl get pods -n ai-platform-engineering | awk 'NR>1 && !/Running/')
if [ -n "$NON_RUNNING" ]; then
  log "  - Non-healty pods in ai-platform-engineering namespace after waiting 5s:"
  echo "=================================================="
  kubectl get pods -n ai-platform-engineering | awk 'NR==1 || !/Running/'
  log "❗ Please check the logs of the pods and fix the issues."
else
  log "All pods are running 🎉"
fi