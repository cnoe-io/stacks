#!/usr/bin/env bash
#
# generate-kubeconfig.sh - Generate remote kubeconfig for Tailscale cluster access
#
# This script extracts client certificates from the local cluster and generates
# a kubeconfig file configured to use the Tailscale operator endpoint.
#
# Usage:
#   ./generate-kubeconfig.sh [cluster-name] [tailnet-name]
#
# Example:
#   ./generate-kubeconfig.sh kind tail286401
#
# Output: remote-kubeconfig.yaml (in current directory)
#

set -euo pipefail

# Defaults
CLUSTER_NAME="${1:-kind}"
TAILNET_NAME="${2:-tail286401}"
OUTPUT_FILE="remote-kubeconfig.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot access Kubernetes cluster. Ensure kubectl is configured for local cluster access."
    exit 1
fi

log_info "Generating remote kubeconfig for cluster: ${CLUSTER_NAME}"

# Detect actual Tailscale operator hostname from logs
log_info "Detecting Tailscale operator hostname..."
OPERATOR_HOSTNAME=$(kubectl logs -n tailscale deployment/tailscale-operator --since=24h 2>/dev/null | \
    grep -o 'u=[a-z0-9-]*\.tail[0-9]*\.ts\.net' | \
    tail -1 | \
    sed 's/u=//')

if [ -z "$OPERATOR_HOSTNAME" ]; then
    log_warn "Could not detect operator hostname from logs, using default: ${CLUSTER_NAME}-operator.${TAILNET_NAME}.ts.net"
    OPERATOR_HOSTNAME="${CLUSTER_NAME}-operator.${TAILNET_NAME}.ts.net"
else
    log_info "✓ Detected operator hostname: $OPERATOR_HOSTNAME"
fi

log_info "Tailscale operator endpoint: https://${OPERATOR_HOSTNAME}:443"

# Extract client certificate
log_info "Extracting client certificate..."
CLIENT_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.users[0].user.client-certificate-data}')

if [ -z "$CLIENT_CERT" ]; then
    log_error "Failed to extract client certificate from kubeconfig"
    exit 1
fi

# Extract client key
log_info "Extracting client key..."
CLIENT_KEY=$(kubectl config view --raw --minify --flatten -o jsonpath='{.users[0].user.client-key-data}')

if [ -z "$CLIENT_KEY" ]; then
    log_error "Failed to extract client key from kubeconfig"
    exit 1
fi

# Get current username from kubeconfig
CURRENT_USER=$(kubectl config view --minify -o jsonpath='{.users[0].name}')

# Generate kubeconfig
log_info "Generating kubeconfig file: ${OUTPUT_FILE}"

cat > "${OUTPUT_FILE}" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${OPERATOR_HOSTNAME}:443
  name: ${CLUSTER_NAME}-tailscale
contexts:
- context:
    cluster: ${CLUSTER_NAME}-tailscale
    user: ${CURRENT_USER}
  name: ${CLUSTER_NAME}-tailscale
current-context: ${CLUSTER_NAME}-tailscale
users:
- name: ${CURRENT_USER}
  user:
    client-certificate-data: ${CLIENT_CERT}
    client-key-data: ${CLIENT_KEY}
EOF

log_info "Kubeconfig generated successfully: ${OUTPUT_FILE}"
echo ""
echo "=========================================="
echo "📋 Next Steps:"
echo "=========================================="
echo ""
echo "1. Copy this file to your remote machine:"
echo "   scp ${OUTPUT_FILE} remote-machine:~/remote-kubeconfig.yaml"
echo ""
echo "2. On the remote machine, test connectivity:"
echo "   kubectl --kubeconfig=~/remote-kubeconfig.yaml get nodes --request-timeout=60s"
echo ""
echo "   ⚠️  NOTE: First connection may take 30-60 seconds for Tailscale HTTPS certificate provisioning"
echo ""
echo "3. Verify subsequent commands are fast (<2 seconds):"
echo "   kubectl --kubeconfig=~/remote-kubeconfig.yaml get pods -A"
echo ""
echo "4. (Optional) Set as default kubeconfig:"
echo "   export KUBECONFIG=~/remote-kubeconfig.yaml"
echo ""
echo "=========================================="
echo "🔧 Troubleshooting:"
echo "=========================================="
echo ""
echo "• Certificate validation errors:"
echo "  - Ensure Tailscale HTTPS is enabled in admin console"
echo "  - Wait for certificate provisioning on first connection"
echo "  - See docs/tailscale-cluster-access.md for cluster CA distribution alternative"
echo ""
echo "• Connection timeout:"
echo "  - Verify Tailscale operator pod is running: kubectl get pods -n tailscale"
echo "  - Check operator logs: kubectl logs -n tailscale deployment/tailscale-operator"
echo "  - Confirm Tailscale connectivity from remote machine: ping ${OPERATOR_HOSTNAME}"
echo ""
echo "• Unauthorized errors:"
echo "  - Verify client certificates are valid: openssl x509 -in <(echo \$CLIENT_CERT | base64 -d) -text -noout"
echo "  - Check RBAC configuration in cluster"
echo ""
