#!/usr/bin/env bash
#
# export-cluster-ca.sh - Export cluster CA certificate for remote kubectl access
#
# This script extracts the cluster CA certificate from your local kubeconfig,
# which is needed when NOT using Tailscale HTTPS (e.g., free Tailscale plans,
# air-gapped environments, CI/CD pipelines).
#
# Usage:
#   ./export-cluster-ca.sh [output-file]
#
# Example:
#   ./export-cluster-ca.sh ~/cluster-ca.crt
#
# The exported CA certificate can be distributed to remote machines and used
# with --certificate-authority flag or embedded in kubeconfig files.
#

set -euo pipefail

# Configuration
OUTPUT_FILE="${1:-cluster-ca.crt}"
CLUSTER_NAME="${CLUSTER_NAME:-kind-localdev}"

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

echo "=========================================="
echo "Cluster CA Certificate Export"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info > /dev/null 2>&1; then
    log_error "Cannot access cluster. Ensure kubectl is configured correctly."
    exit 1
fi

log_info "Extracting CA certificate from cluster: $CLUSTER_NAME"

# Extract CA certificate from kubeconfig
CA_DATA=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

if [ -z "$CA_DATA" ]; then
    log_error "No CA certificate found in kubeconfig."
    log_error "This cluster may be using insecure-skip-tls-verify or external CA."
    exit 1
fi

# Decode base64 and write to file
echo "$CA_DATA" | base64 -d > "$OUTPUT_FILE"

if [ -f "$OUTPUT_FILE" ]; then
    log_info "✓ CA certificate exported to: $OUTPUT_FILE"

    # Verify certificate
    if command -v openssl &> /dev/null; then
        echo ""
        log_info "Certificate details:"
        openssl x509 -in "$OUTPUT_FILE" -noout -text | grep -E "(Issuer|Subject|Not Before|Not After)" || true
    fi

    echo ""
    log_info "Distribution instructions:"
    echo "  1. Copy this file to remote machines:"
    echo "     scp $OUTPUT_FILE user@remote-machine:~/"
    echo ""
    echo "  2. Use with kubectl --certificate-authority flag:"
    echo "     kubectl --certificate-authority=~/$OUTPUT_FILE --server=https://... get nodes"
    echo ""
    echo "  3. Or embed in kubeconfig:"
    echo "     certificate-authority-data: \$(cat $OUTPUT_FILE | base64 -w 0)"
    echo ""

    log_warn "Security note:"
    echo "  - This CA certificate is public (not sensitive)"
    echo "  - Still need client certificates or tokens for authentication"
    echo "  - Consider using Tailscale HTTPS for automatic TLS (recommended)"
    echo ""
else
    log_error "Failed to create CA certificate file."
    exit 1
fi

# Additional cluster information
echo "=========================================="
echo "Cluster Information"
echo "=========================================="
echo ""

CLUSTER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
log_info "Cluster endpoint: $CLUSTER_ENDPOINT"

echo ""
log_info "For Tailscale access (recommended):"
echo "  Use generate-kubeconfig.sh instead - no CA certificate needed!"
echo "  Tailscale HTTPS provides automatic Let's Encrypt certificates."
echo ""

log_info "Export complete!"
