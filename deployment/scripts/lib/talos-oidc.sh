#!/usr/bin/env bash
#
# Talos OIDC helper functions for Azure Workload Identity
# Feature: 102-bootstrap-talos-argocd
#
# This library provides functions for:
# - Generating Talos configs with custom OIDC issuer
# - Patching existing Talos clusters with OIDC issuer
# - Verifying OIDC issuer configuration
# - Syncing JWKS to Azure Storage
#

set -euo pipefail

# Source common functions (only if not already loaded)
if [[ -z "${_COMMON_SH_LOADED:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_LIB_DIR}/common.sh"
fi

#
# Generate Talos OIDC patch file
#
# Usage: generate_oidc_patch <issuer_url> [output_file]
#
generate_oidc_patch() {
    local issuer_url="${1:?OIDC issuer URL required}"
    local output_file="${2:-/tmp/oidc-patch.yaml}"

    # Ensure trailing slash on issuer URL
    if [[ "${issuer_url}" != */ ]]; then
        issuer_url="${issuer_url}/"
    fi

    cat > "$output_file" << EOF
cluster:
  apiServer:
    extraArgs:
      service-account-issuer: ${issuer_url}
EOF

    log_info "Generated OIDC patch: $output_file"
    echo "$output_file"
}

#
# Apply OIDC issuer patch to Talos control plane nodes
#
# Usage: apply_oidc_patch <issuer_url> <node_ips...>
#
apply_oidc_patch() {
    local issuer_url="${1:?OIDC issuer URL required}"
    shift
    local node_ips=("$@")

    if [[ ${#node_ips[@]} -eq 0 ]]; then
        log_error "At least one node IP required"
        return 1
    fi

    # Ensure trailing slash on issuer URL
    if [[ "${issuer_url}" != */ ]]; then
        issuer_url="${issuer_url}/"
    fi

    log_info "Applying OIDC issuer patch to ${#node_ips[@]} nodes..."
    log_info "Issuer URL: $issuer_url"

    local patch_json="[{\"op\": \"add\", \"path\": \"/cluster/apiServer/extraArgs\", \"value\": {\"service-account-issuer\": \"${issuer_url}\"}}]"

    for node_ip in "${node_ips[@]}"; do
        log_info "Patching node: $node_ip"
        talosctl patch mc \
            --endpoints "$node_ip" \
            --nodes "$node_ip" \
            --mode no-reboot \
            --patch "$patch_json"
    done

    log_success "OIDC issuer patch applied to all nodes"
    log_info "Changes take effect immediately (no reboot required)"
    log_warn "Remember to restart pods that need new tokens:"
    log_warn "  kubectl rollout restart daemonset/kube-proxy -n kube-system"
    log_warn "  kubectl rollout restart deployment -n external-secrets --all"
}

#
# Get current cluster OIDC issuer
#
# Usage: get_cluster_oidc_issuer
# Returns: OIDC issuer URL or empty string
#
get_cluster_oidc_issuer() {
    kubectl get --raw /.well-known/openid-configuration 2>/dev/null | jq -r '.issuer' || echo ""
}

#
# Verify OIDC issuer matches expected URL
#
# Usage: verify_oidc_issuer <expected_issuer>
# Returns: 0 if match, 1 if mismatch
#
verify_oidc_issuer() {
    local expected_issuer="${1:?Expected OIDC issuer URL required}"

    local actual_issuer
    actual_issuer=$(get_cluster_oidc_issuer)

    if [[ -z "$actual_issuer" ]]; then
        log_error "Cannot retrieve cluster OIDC issuer"
        return 1
    fi

    # Normalize URLs (remove trailing slashes)
    local expected_normalized="${expected_issuer%/}"
    local actual_normalized="${actual_issuer%/}"

    if [[ "$expected_normalized" == "$actual_normalized" ]]; then
        log_success "OIDC issuer verified: $actual_issuer"
        return 0
    else
        log_error "OIDC issuer mismatch"
        log_error "  Expected: $expected_issuer"
        log_error "  Actual:   $actual_issuer"
        return 1
    fi
}

#
# Check if cluster is using default IP-based OIDC issuer
#
# Usage: is_default_oidc_issuer
# Returns: 0 if using default (IP-based), 1 otherwise
#
is_default_oidc_issuer() {
    local issuer
    issuer=$(get_cluster_oidc_issuer)

    if [[ "$issuer" =~ ^https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:6443$ ]]; then
        return 0
    else
        return 1
    fi
}

#
# Generate Talos configs with OIDC issuer pre-configured
#
# Usage: generate_talos_config_with_oidc <cluster_name> <endpoint> <oidc_issuer> [options...]
#
# Options are passed directly to talosctl gen config
#
generate_talos_config_with_oidc() {
    local cluster_name="${1:?Cluster name required}"
    local endpoint="${2:?Cluster endpoint required}"
    local oidc_issuer="${3:?OIDC issuer URL required}"
    shift 3
    local extra_options=("$@")

    # Ensure trailing slash
    if [[ "${oidc_issuer}" != */ ]]; then
        oidc_issuer="${oidc_issuer}/"
    fi

    # Generate OIDC patch
    local patch_file
    patch_file=$(mktemp)
    cat > "$patch_file" << EOF
cluster:
  apiServer:
    extraArgs:
      service-account-issuer: ${oidc_issuer}
EOF

    log_info "Generating Talos configs with OIDC issuer: $oidc_issuer"

    talosctl gen config "$cluster_name" "$endpoint" \
        --config-patch "@${patch_file}" \
        "${extra_options[@]}"

    rm -f "$patch_file"

    log_success "Talos configs generated with OIDC issuer pre-configured"
}

#
# Restart pods that need new tokens after OIDC issuer change
#
# Usage: restart_pods_for_new_tokens
#
restart_pods_for_new_tokens() {
    log_info "Restarting pods to obtain new tokens..."

    # Restart kube-proxy (critical for cluster networking)
    log_info "Restarting kube-proxy..."
    kubectl rollout restart daemonset/kube-proxy -n kube-system || true

    # Restart CoreDNS
    log_info "Restarting CoreDNS..."
    kubectl rollout restart deployment/coredns -n kube-system || true

    # Restart External Secrets Operator (if installed)
    if kubectl get deployment -n external-secrets external-secrets &>/dev/null; then
        log_info "Restarting External Secrets Operator..."
        kubectl rollout restart deployment -n external-secrets --all || true
    fi

    # Wait for rollouts to complete
    log_info "Waiting for rollouts to complete..."
    kubectl rollout status daemonset/kube-proxy -n kube-system --timeout=120s || true
    kubectl rollout status deployment/coredns -n kube-system --timeout=120s || true

    if kubectl get deployment -n external-secrets external-secrets &>/dev/null; then
        kubectl rollout status deployment/external-secrets -n external-secrets --timeout=120s || true
    fi

    log_success "Pods restarted with new tokens"
}

#
# Full OIDC setup workflow for existing cluster
#
# Usage: setup_oidc_for_cluster <oidc_issuer> <node_ips...>
#
setup_oidc_for_cluster() {
    local oidc_issuer="${1:?OIDC issuer URL required}"
    shift
    local node_ips=("$@")

    print_header "Setting up OIDC Issuer for Azure Workload Identity"

    # Check current issuer
    local current_issuer
    current_issuer=$(get_cluster_oidc_issuer)
    log_info "Current OIDC issuer: ${current_issuer:-<not retrievable>}"

    # Normalize for comparison
    local expected_normalized="${oidc_issuer%/}"
    local current_normalized="${current_issuer%/}"

    if [[ "$expected_normalized" == "$current_normalized" ]]; then
        log_success "OIDC issuer already configured correctly"
        return 0
    fi

    # Apply patch
    apply_oidc_patch "$oidc_issuer" "${node_ips[@]}"

    # Wait for API server to restart
    log_info "Waiting for API server to update..."
    sleep 10

    # Verify
    if verify_oidc_issuer "$oidc_issuer"; then
        # Restart pods
        restart_pods_for_new_tokens
        log_success "OIDC setup complete!"
    else
        log_error "OIDC issuer verification failed after patch"
        return 1
    fi
}
