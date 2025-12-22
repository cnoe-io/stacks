#!/usr/bin/env bash
#
# Talosctl helper functions for Talos GitOps bootstrap
# Feature: 102-bootstrap-talos-argocd
#

set -euo pipefail

# Source common functions (only if not already loaded)
if [[ -z "${_COMMON_SH_LOADED:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_LIB_DIR}/common.sh"
fi

# Default Talos configuration
export TALOSCONFIG="${TALOSCONFIG:-$HOME/.talos/config}"

# Validate talosctl is available and configured
validate_talosctl() {
    log_info "Validating talosctl configuration..."

    require_command "talosctl" "Install from https://www.talos.dev/latest/talos-guides/install/talosctl/"

    if [[ ! -f "$TALOSCONFIG" ]]; then
        log_error "Talos config not found: $TALOSCONFIG"
        log_info "Generate with: talosctl gen config <cluster-name> <endpoint>"
        return 1
    fi

    log_success "talosctl configured: $TALOSCONFIG"
}

# Get the control plane endpoint from talosconfig
get_control_plane_endpoint() {
    talosctl config info --output json 2>/dev/null | jq -r '.endpoints[0]' || {
        log_error "Cannot determine control plane endpoint"
        return 1
    }
}

# Check cluster health via talosctl or kubectl
check_cluster_health() {
    log_info "Checking Talos cluster health..."

    # Try talosctl health first, but fall back to kubectl if talosctl fails
    # (talosctl health requires port 50000 access to all nodes which may not be available)
    if talosctl health --wait-timeout 30s &>/dev/null; then
        log_success "Talos cluster is healthy (via talosctl)"
        return 0
    fi

    log_warn "talosctl health check failed, falling back to kubectl..."

    # Check cluster via kubectl as fallback
    if kubectl cluster-info &>/dev/null; then
        local ready_nodes
        ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
        if [[ "$ready_nodes" -gt 0 ]]; then
            log_success "Cluster is healthy via kubectl ($ready_nodes nodes ready)"
            return 0
        fi
    fi

    log_error "Cluster health check failed"
    return 1
}

# Generate kubeconfig from Talos
generate_kubeconfig() {
    local output_path="${1:-$HOME/.kube/talos-cluster.yaml}"

    log_info "Generating kubeconfig to: $output_path"

    mkdir -p "$(dirname "$output_path")"

    talosctl kubeconfig --force "$output_path"

    chmod 600 "$output_path"

    log_success "Kubeconfig generated: $output_path"
    echo "$output_path"
}

# Export kubeconfig and set KUBECONFIG
setup_kubeconfig() {
    local kubeconfig_path="${1:-$HOME/.kube/talos-cluster.yaml}"

    # Quick check with short timeout - if current kubectl works, use it
    if timeout 5 kubectl get nodes --no-headers &>/dev/null; then
        log_info "Using existing kubeconfig (kubectl access confirmed)"
        return 0
    fi

    # Try the specified path with short timeout
    if [[ -f "$kubeconfig_path" ]]; then
        if KUBECONFIG="$kubeconfig_path" timeout 5 kubectl get nodes --no-headers &>/dev/null; then
            export KUBECONFIG="$kubeconfig_path"
            log_info "Using existing kubeconfig: $KUBECONFIG"
            return 0
        fi
    fi

    # Generate new kubeconfig as last resort
    log_warn "No working kubeconfig found, generating new one..."
    generate_kubeconfig "$kubeconfig_path"
    export KUBECONFIG="$kubeconfig_path"
    log_info "KUBECONFIG set to: $KUBECONFIG"
}

# Wait for Kubernetes API to be ready
wait_for_kubernetes_api() {
    local timeout="${1:-300}"

    log_info "Waiting for Kubernetes API to be ready..."

    wait_for "Kubernetes API" "kubectl cluster-info" "$timeout"
}

# Check if CNI is ready (supports Flannel or Cilium)
check_cni_ready() {
    log_info "Checking CNI readiness..."

    # Try Flannel first (default in Talos config)
    if kubectl get pods -n kube-system -l app=flannel --no-headers 2>/dev/null | grep -q "Running"; then
        log_info "Detected Flannel CNI, checking pods..."
        if kubectl wait --for=condition=Ready pod \
            -l app=flannel \
            -n kube-system \
            --timeout=60s &>/dev/null; then
            log_success "Flannel CNI is ready"
            return 0
        fi
    fi

    # Try kube-flannel label (alternative)
    if kubectl get pods -n kube-system -l app.kubernetes.io/name=flannel --no-headers 2>/dev/null | grep -q "Running"; then
        log_info "Detected Flannel CNI (alt label), checking pods..."
        if kubectl wait --for=condition=Ready pod \
            -l app.kubernetes.io/name=flannel \
            -n kube-system \
            --timeout=60s &>/dev/null; then
            log_success "Flannel CNI is ready"
            return 0
        fi
    fi

    # Try Cilium (alternative CNI)
    if kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -q "Running"; then
        log_info "Detected Cilium CNI, checking pods..."
        if kubectl wait --for=condition=Ready pod \
            -l k8s-app=cilium \
            -n kube-system \
            --timeout=60s &>/dev/null; then
            log_success "Cilium CNI is ready"
            return 0
        fi
    fi

    # Check if nodes are Ready (CNI is working even if we can't identify it)
    local ready_nodes
    ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
    if [[ "$ready_nodes" -gt 0 ]]; then
        log_warn "Could not identify CNI type, but $ready_nodes nodes are Ready"
        log_info "CNI appears to be functional"
        return 0
    fi

    log_error "CNI not ready - no Flannel or Cilium pods found, and nodes are not Ready"
    log_info "Check: kubectl get pods -n kube-system"
    log_info "If using Flannel (built into Talos), check firewall allows port 4789/UDP between nodes"
    return 1
}

# Verify all nodes are ready
check_nodes_ready() {
    log_info "Checking node readiness..."

    local not_ready
    not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -cv " Ready " || true)

    if [[ "$not_ready" -gt 0 ]]; then
        log_error "$not_ready nodes are not ready"
        kubectl get nodes
        return 1
    fi

    local node_count
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    log_success "All $node_count nodes are ready"
}

# Extract OIDC JWKS from cluster
extract_jwks() {
    local output_file="${1:-/tmp/jwks.json}"

    log_info "Extracting OIDC JWKS from cluster..."

    kubectl get --raw /openid/v1/jwks | jq > "$output_file"

    log_success "JWKS extracted to: $output_file"
    echo "$output_file"
}

# Generate remote kubeconfig for Tailscale access
generate_remote_kubeconfig() {
    local cluster_name="${1:-talos-cluster}"
    local tailnet="${2:-$TAILSCALE_TAILNET}"
    local output_path="${3:-./remote-kubeconfig.yaml}"

    if [[ -z "$tailnet" ]]; then
        log_error "TAILSCALE_TAILNET environment variable not set"
        return 1
    fi

    local cluster_id="${CLUSTER_NAME:-${CLUSTER_HOST:-$cluster_name}}"
    local api_server="https://k8s-api-${cluster_id}.${tailnet}.ts.net"

    log_info "Generating remote kubeconfig for: $api_server"

    # Extract user credentials from existing kubeconfig
    local client_cert client_key
    client_cert=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
    client_key=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}')

    cat > "$output_path" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: ${api_server}
    # TLS handled by Tailscale HTTPS (Let's Encrypt)
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: ${cluster_name}-admin
  name: ${cluster_name}
current-context: ${cluster_name}
users:
- name: ${cluster_name}-admin
  user:
    client-certificate-data: ${client_cert}
    client-key-data: ${client_key}
EOF

    chmod 600 "$output_path"

    log_success "Remote kubeconfig generated: $output_path"
    log_info "Use from any Tailscale-connected device:"
    log_info "  kubectl --kubeconfig=$output_path get nodes"

    echo "$output_path"
}

# Validate Talos cluster prerequisites
validate_talos_prerequisites() {
    print_header "Validating Talos Cluster Prerequisites"

    validate_talosctl
    check_cluster_health
    setup_kubeconfig
    wait_for_kubernetes_api
    check_cni_ready
    check_nodes_ready

    print_completion "Talos validation" "success"
}
