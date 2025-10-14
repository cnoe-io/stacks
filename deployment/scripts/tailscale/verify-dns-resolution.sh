#!/usr/bin/env bash
#
# verify-dns-resolution.sh - Verify DNS resolution for Tailscale cluster access
#
# This script tests DNS resolution from both external (Mac/remote machine) and
# internal (cluster pods) perspectives.
#
# Usage:
#   ./verify-dns-resolution.sh [kubeconfig-path]
#
# Example:
#   ./verify-dns-resolution.sh ~/remote-kubeconfig.yaml
#

set -euo pipefail

# Configuration
KUBECONFIG_PATH="${1:-$HOME/remote-kubeconfig.yaml}"
TAILSCALE_HOSTNAME="${2:-kind-operator-13.tail286401.ts.net}"
CLUSTER_DOMAIN="cnoe.localtest.me"

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

echo "=========================================="
echo "DNS Resolution Verification"
echo "=========================================="
echo ""

# Test 1: External DNS - Tailscale hostname
log_test "Test 1: External DNS - Tailscale Operator Hostname"
echo "Testing: $TAILSCALE_HOSTNAME"

if command -v dig &> /dev/null; then
    DIG_OUTPUT=$(dig +short "$TAILSCALE_HOSTNAME" A 2>&1 || true)
    if [ -n "$DIG_OUTPUT" ]; then
        log_info "✓ Resolved to: $DIG_OUTPUT"
        TAILSCALE_IP=$(echo "$DIG_OUTPUT" | head -1)
    else
        log_error "✗ Failed to resolve Tailscale hostname"
        TAILSCALE_IP=""
    fi
else
    log_warn "dig not available, trying ping..."
    if ping -c 1 "$TAILSCALE_HOSTNAME" > /dev/null 2>&1; then
        log_info "✓ Hostname is reachable"
        TAILSCALE_IP="(ping successful)"
    else
        log_error "✗ Hostname not reachable"
        TAILSCALE_IP=""
    fi
fi

# Test 2: External DNS - Cluster ingress domains
log_test "Test 2: External DNS - Cluster Ingress Domains"
echo "Testing: argocd.$CLUSTER_DOMAIN"

if command -v dig &> /dev/null; then
    DIG_OUTPUT=$(dig +short "argocd.$CLUSTER_DOMAIN" A 2>&1 || true)
    if [ -n "$DIG_OUTPUT" ]; then
        log_info "✓ Resolved to: $DIG_OUTPUT (should be 127.0.0.1 for localtest.me)"
    else
        log_warn "✗ No resolution (expected for .localtest.me from remote machines)"
    fi
else
    log_warn "dig not available, skipping ingress DNS test"
fi

# Test 3: Internal DNS - Kubernetes services
if [ -f "$KUBECONFIG_PATH" ]; then
    log_test "Test 3: Internal DNS - Kubernetes Services"
    echo "Testing from cluster perspective..."

    # Test if we can run a test pod
    if kubectl --kubeconfig="$KUBECONFIG_PATH" get ns default > /dev/null 2>&1; then
        log_info "Creating test pod for internal DNS verification..."

        # Create a temporary pod for DNS testing
        kubectl --kubeconfig="$KUBECONFIG_PATH" run dns-test-pod \
            --image=busybox:latest \
            --restart=Never \
            --rm -i --quiet -- sh -c "
                echo 'Testing kubernetes.default.svc resolution:'
                nslookup kubernetes.default.svc 2>&1 || echo 'Failed'
                echo ''
                echo 'Testing argocd-server.argocd.svc resolution:'
                nslookup argocd-server.argocd.svc 2>&1 || echo 'Failed'
            " 2>&1 | while IFS= read -r line; do
                echo "  $line"
            done

        log_info "✓ Internal DNS test complete"
    else
        log_error "✗ Cannot access cluster to test internal DNS"
    fi
else
    log_warn "Kubeconfig not found, skipping internal DNS tests"
fi

echo ""
echo "=========================================="
echo "📊 DNS Resolution Summary"
echo "=========================================="
echo ""

if [ -n "$TAILSCALE_IP" ]; then
    echo "✓ External DNS (Tailscale): Working"
    echo "  Hostname: $TAILSCALE_HOSTNAME"
    echo "  IP: $TAILSCALE_IP"
else
    echo "✗ External DNS (Tailscale): Failed"
    echo "  Check:"
    echo "  - Tailscale MagicDNS is enabled"
    echo "  - Tailscale is running and authenticated"
    echo "  - Operator pod has completed initial handshake"
fi

echo ""
echo "Expected behavior:"
echo "  - External: Tailscale hostname → 100.x.x.x (Tailscale IP)"
echo "  - External: *.cnoe.localtest.me → 127.0.0.1 (for local kind cluster)"
echo "  - Internal: *.svc.cluster.local → cluster IPs (10.96.x.x)"
echo ""

echo "Troubleshooting:"
echo "  1. Verify Tailscale status: tailscale status"
echo "  2. Check MagicDNS: tailscale status | grep MagicDNS"
echo "  3. Ping operator: ping $TAILSCALE_HOSTNAME"
echo "  4. Check operator logs: kubectl logs -n tailscale deployment/tailscale-operator"
echo ""
