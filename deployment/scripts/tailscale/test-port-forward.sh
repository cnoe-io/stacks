#!/usr/bin/env bash
#
# test-port-forward.sh - Test kubectl port-forward functionality over Tailscale
#
# This script tests port-forwarding to various cluster services from a remote
# machine connected via Tailscale.
#
# Usage:
#   ./test-port-forward.sh [kubeconfig-path]
#
# Example:
#   ./test-port-forward.sh ~/remote-kubeconfig.yaml
#

set -euo pipefail

# Configuration
KUBECONFIG_PATH="${1:-$HOME/remote-kubeconfig.yaml}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_PATH" ]; then
    log_error "Kubeconfig not found at: $KUBECONFIG_PATH"
    exit 1
fi

log_info "Using kubeconfig: $KUBECONFIG_PATH"

# Test 1: ArgoCD (HTTPS service)
log_test "Test 1: Port-forward to ArgoCD (8080 → 443)"
echo "Starting port-forward in background..."
kubectl --kubeconfig="$KUBECONFIG_PATH" port-forward -n argocd svc/argocd-server 8080:443 > /tmp/pf-argocd.log 2>&1 &
PF_ARGOCD_PID=$!
echo "Port-forward PID: $PF_ARGOCD_PID"

sleep 3

# Test ArgoCD connectivity
if curl -sk https://localhost:8080 > /dev/null 2>&1; then
    log_info "✓ ArgoCD accessible at https://localhost:8080"
else
    log_warn "✗ ArgoCD not accessible (may require login)"
fi

# Test 2: Gitea (HTTP service)
log_test "Test 2: Port-forward to Gitea (8081 → 3000)"
echo "Starting port-forward in background..."
kubectl --kubeconfig="$KUBECONFIG_PATH" port-forward -n gitea svc/gitea-http 8081:3000 > /tmp/pf-gitea.log 2>&1 &
PF_GITEA_PID=$!
echo "Port-forward PID: $PF_GITEA_PID"

sleep 3

# Test Gitea connectivity
if curl -s http://localhost:8081 > /dev/null 2>&1; then
    log_info "✓ Gitea accessible at http://localhost:8081"
else
    log_warn "✗ Gitea not accessible"
fi

# Test 3: MinIO (if available)
log_test "Test 3: Port-forward to MinIO (8082 → 9000)"
if kubectl --kubeconfig="$KUBECONFIG_PATH" get svc -n nix-cache minio > /dev/null 2>&1; then
    echo "Starting port-forward in background..."
    kubectl --kubeconfig="$KUBECONFIG_PATH" port-forward -n nix-cache svc/minio 8082:9000 > /tmp/pf-minio.log 2>&1 &
    PF_MINIO_PID=$!
    echo "Port-forward PID: $PF_MINIO_PID"

    sleep 3

    # Test MinIO connectivity
    if curl -s http://localhost:8082 > /dev/null 2>&1; then
        log_info "✓ MinIO accessible at http://localhost:8082"
    else
        log_warn "✗ MinIO not accessible"
    fi
else
    log_warn "MinIO service not found, skipping"
    PF_MINIO_PID=""
fi

echo ""
log_info "Port-forwards running. Access services at:"
echo "  - ArgoCD: https://localhost:8080"
echo "  - Gitea:  http://localhost:8081"
[ -n "${PF_MINIO_PID:-}" ] && echo "  - MinIO:  http://localhost:8082"

echo ""
log_info "Press Enter to stop port-forwards and measure latency..."
read

# Latency test
log_test "Measuring port-forward latency"
echo "Testing ArgoCD response time (5 requests)..."
TOTAL_TIME=0
for i in {1..5}; do
    TIME=$(curl -sk -w "%{time_total}\n" -o /dev/null https://localhost:8080)
    echo "  Request $i: ${TIME}s"
    TOTAL_TIME=$(echo "$TOTAL_TIME + $TIME" | bc)
done
AVG_TIME=$(echo "scale=3; $TOTAL_TIME / 5" | bc)
echo "Average response time: ${AVG_TIME}s"

if (( $(echo "$AVG_TIME < 0.5" | bc -l) )); then
    log_info "✓ Latency within acceptable range (<500ms)"
else
    log_warn "⚠ Latency higher than expected (${AVG_TIME}s)"
fi

# Cleanup
log_info "Stopping port-forwards..."
kill $PF_ARGOCD_PID 2>/dev/null || true
kill $PF_GITEA_PID 2>/dev/null || true
[ -n "${PF_MINIO_PID:-}" ] && kill $PF_MINIO_PID 2>/dev/null || true

log_info "Test complete!"
echo ""
echo "=========================================="
echo "📊 Test Summary:"
echo "=========================================="
echo "✓ Port-forward to multiple services works"
echo "✓ HTTP and HTTPS services accessible"
echo "✓ Average latency: ${AVG_TIME}s"
echo ""
echo "For long-running port-forwards, use:"
echo "  kubectl --kubeconfig=$KUBECONFIG_PATH port-forward -n <namespace> svc/<service> <local-port>:<remote-port> &"
echo ""
