#!/usr/bin/env bash
#
# Install ArgoCD via Helm on Talos Linux cluster
# Feature: 102-bootstrap-talos-argocd
#
# This script performs Phase 1 of the bootstrap:
# - Adds the Argo Helm repository
# - Installs ArgoCD in the argocd namespace
# - Waits for all pods to be ready
#
# Prerequisites:
# - kubectl configured and connected to cluster
# - helm v3 installed
# - CNI (Cilium) ready
#
# Usage:
#   ./scripts/01-install-argocd.sh [--force]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper libraries
source "${SCRIPT_DIR}/lib/common.sh"

# Configuration
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.3.0}"
ARGOCD_RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argocd}"
ARGOCD_VALUES_FILE="${ARGOCD_VALUES_FILE:-${SCRIPT_DIR}/../cdk8s/values/argocd-values.yaml}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
POD_READY_TIMEOUT="${POD_READY_TIMEOUT:-300}"

# Parse arguments
FORCE_REINSTALL=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

#
# Check if ArgoCD is already installed (idempotency)
#
check_argocd_installed() {
    if helm_release_exists "$ARGOCD_RELEASE_NAME" "$ARGOCD_NAMESPACE"; then
        log_success "ArgoCD Helm release already exists"
        return 0
    fi
    return 1
}

#
# Check and remove control-plane taints if running CP-only cluster
# This is critical for CP-only clusters where all nodes have the taint
#
handle_control_plane_taints() {
    log_info "Checking control-plane taints..."

    # Count nodes with control-plane taint
    local tainted_nodes total_nodes
    tainted_nodes=$(kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].key}' 2>/dev/null | wc -w || echo "0")
    total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

    if [[ "$tainted_nodes" -eq "$total_nodes" ]] && [[ "$total_nodes" -gt 0 ]]; then
        log_warn "All $total_nodes nodes have control-plane taint (CP-only cluster)"
        log_info "Removing control-plane taints to allow workload scheduling..."

        if kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null; then
            log_success "Control-plane taints removed from all nodes"
        else
            log_warn "Could not remove taints (may already be removed)"
        fi
    else
        log_info "Cluster has dedicated worker nodes or taints already removed"
    fi
}

#
# Check if ArgoCD pods are healthy
#
check_argocd_health() {
    log_info "Checking ArgoCD pod health..."

    # Check if argocd namespace exists
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
        log_warn "Namespace $ARGOCD_NAMESPACE does not exist"
        return 1
    fi

    # Count running pods
    local total ready
    total=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l)
    ready=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || true)

    if [[ "$total" -gt 0 ]] && [[ "$ready" -eq "$total" ]]; then
        log_success "All $total ArgoCD pods are running"
        return 0
    fi

    log_warn "ArgoCD pods: $ready/$total running"
    return 1
}

#
# Add Argo Helm repository
#
add_helm_repo() {
    log_info "Adding Argo Helm repository..."

    if helm repo list 2>/dev/null | grep -q "^argo"; then
        log_info "Argo repo already added, updating..."
        helm repo update argo
    else
        helm repo add argo https://argoproj.github.io/argo-helm
        helm repo update
    fi

    log_success "Argo Helm repository ready"
}

#
# Install ArgoCD via Helm
#
install_argocd() {
    log_info "Installing ArgoCD via Helm..."
    log_info "  Release: $ARGOCD_RELEASE_NAME"
    log_info "  Namespace: $ARGOCD_NAMESPACE"
    log_info "  Chart version: $ARGOCD_CHART_VERSION"

    # Build Helm install command
    local helm_cmd=(
        helm install "$ARGOCD_RELEASE_NAME" argo/argo-cd
        --namespace "$ARGOCD_NAMESPACE"
        --create-namespace
        --version "$ARGOCD_CHART_VERSION"
        --wait
        --timeout "$HELM_TIMEOUT"
    )

    # Add values file if it exists
    if [[ -f "$ARGOCD_VALUES_FILE" ]]; then
        log_info "  Using values: $ARGOCD_VALUES_FILE"
        helm_cmd+=(--values "$ARGOCD_VALUES_FILE")
    else
        log_warn "Values file not found: $ARGOCD_VALUES_FILE"
        log_info "Using default chart values"
    fi

    # Execute Helm install
    "${helm_cmd[@]}"

    log_success "ArgoCD Helm install completed"
}

#
# Upgrade existing ArgoCD installation
#
upgrade_argocd() {
    log_info "Upgrading ArgoCD via Helm..."

    # Build Helm upgrade command
    local helm_cmd=(
        helm upgrade "$ARGOCD_RELEASE_NAME" argo/argo-cd
        --namespace "$ARGOCD_NAMESPACE"
        --version "$ARGOCD_CHART_VERSION"
        --wait
        --timeout "$HELM_TIMEOUT"
    )

    # Add values file if it exists
    if [[ -f "$ARGOCD_VALUES_FILE" ]]; then
        helm_cmd+=(--values "$ARGOCD_VALUES_FILE")
    fi

    # Execute Helm upgrade
    "${helm_cmd[@]}"

    log_success "ArgoCD Helm upgrade completed"
}

#
# Wait for ArgoCD pods to be ready
#
wait_for_argocd_ready() {
    log_info "Waiting for ArgoCD pods to be ready (timeout: ${POD_READY_TIMEOUT}s)..."

    # Wait for argocd-server deployment
    log_info "  Waiting for argocd-server..."
    kubectl wait --for=condition=Available deployment/argocd-server \
        -n "$ARGOCD_NAMESPACE" \
        --timeout="${POD_READY_TIMEOUT}s"

    # Wait for argocd-repo-server deployment
    log_info "  Waiting for argocd-repo-server..."
    kubectl wait --for=condition=Available deployment/argocd-repo-server \
        -n "$ARGOCD_NAMESPACE" \
        --timeout="${POD_READY_TIMEOUT}s"

    # Wait for argocd-application-controller
    log_info "  Waiting for argocd-application-controller..."
    kubectl wait --for=condition=Available deployment/argocd-application-controller \
        -n "$ARGOCD_NAMESPACE" \
        --timeout="${POD_READY_TIMEOUT}s" 2>/dev/null || \
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller \
        -n "$ARGOCD_NAMESPACE" \
        --timeout="${POD_READY_TIMEOUT}s"

    log_success "All ArgoCD deployments are ready"
}

#
# Print ArgoCD access information
#
print_access_info() {
    echo ""
    log_info "ArgoCD Installation Summary"
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo "Namespace: $ARGOCD_NAMESPACE"
    echo "Version:   $ARGOCD_CHART_VERSION"
    echo ""

    # Get admin password
    local admin_password
    admin_password=$(kubectl get secret argocd-initial-admin-secret \
        -n "$ARGOCD_NAMESPACE" \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || true

    if [[ -n "$admin_password" ]]; then
        echo "Admin credentials:"
        echo "  Username: admin"
        echo "  Password: $admin_password"
        echo ""
    fi

    echo "Access ArgoCD:"
    echo "  Port-forward: kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo "  Open:         https://localhost:8080"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
}

#
# Main execution
#
main() {
    print_header "Installing ArgoCD"

    # Check prerequisites
    require_command "kubectl" "Install from https://kubernetes.io/docs/tasks/tools/"
    require_command "helm" "Install from https://helm.sh/docs/intro/install/"

    # Handle control-plane taints for CP-only clusters
    # This MUST happen before ArgoCD install or Helm will timeout waiting for pods
    handle_control_plane_taints

    # Check if already installed (idempotency)
    if check_argocd_installed; then
        if [[ "$FORCE_REINSTALL" == "true" ]]; then
            log_info "Force flag set, upgrading ArgoCD..."
            add_helm_repo
            upgrade_argocd
            wait_for_argocd_ready
        elif check_argocd_health; then
            log_success "ArgoCD already installed and healthy, skipping"
            print_access_info
            return 0
        else
            log_warn "ArgoCD installed but unhealthy, attempting repair..."
            add_helm_repo
            upgrade_argocd
            wait_for_argocd_ready
        fi
    else
        # Fresh install
        add_helm_repo
        install_argocd
        wait_for_argocd_ready
    fi

    print_access_info
    print_completion "ArgoCD Installation" "success"
}

# Run main
main "$@"
