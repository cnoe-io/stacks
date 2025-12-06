#!/usr/bin/env bash
#
# Generate remote kubeconfig for Tailscale access
# Feature: 102-bootstrap-talos-argocd
#
# This script generates a kubeconfig file configured to access the cluster
# via Tailscale Services, enabling kubectl access from any Tailscale-connected device.
#
# Usage:
#   ./scripts/generate-remote-kubeconfig.sh [cluster-name] [tailnet] [output-file]
#
# Example:
#   ./scripts/generate-remote-kubeconfig.sh talos-cluster tail12345 ./remote-kubeconfig.yaml
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/talos.sh"

# Parse arguments
CLUSTER_NAME="${1:-talos-cluster}"
TAILNET="${2:-${TAILSCALE_TAILNET:-}}"
OUTPUT_FILE="${3:-./remote-kubeconfig.yaml}"

# Main execution
main() {
    print_header "Generate Remote Kubeconfig"

    # Validate tailnet
    if [[ -z "$TAILNET" ]]; then
        log_error "Tailnet not specified"
        echo ""
        echo "Usage: $0 [cluster-name] [tailnet] [output-file]"
        echo ""
        echo "Or set TAILSCALE_TAILNET environment variable"
        exit 1
    fi

    log_info "Cluster: $CLUSTER_NAME"
    log_info "Tailnet: $TAILNET"
    log_info "Output:  $OUTPUT_FILE"
    echo ""

    # Generate the kubeconfig
    generate_remote_kubeconfig "$CLUSTER_NAME" "$TAILNET" "$OUTPUT_FILE"

    echo ""
    print_completion "Remote kubeconfig generation" "success"

    echo ""
    echo "Test your remote kubeconfig:"
    echo "  kubectl --kubeconfig=$OUTPUT_FILE get nodes"
    echo ""
    echo "Copy to remote machine:"
    echo "  scp $OUTPUT_FILE user@machine:~/.kube/"
    echo ""
}

# Run main function
main "$@"
