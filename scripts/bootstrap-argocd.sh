#!/usr/bin/env bash
#
# Simplified ArgoCD Bootstrap for Talos Linux
# Feature: 106-consolidate-bootstrap-between
#
# This is the ONE COMMAND you need after cluster creation.
# It installs ArgoCD and applies the root application - ArgoCD auto-sync handles the rest.
#
# What this script does:
#   1. Remove control-plane taints (for CP-only clusters)
#   2. Sync JWKS to Azure Storage (for Workload Identity)
#   3. Install ArgoCD via Helm
#   4. Apply root ArgoCD Application
#   5. Done! ArgoCD auto-sync handles everything else via sync waves
#
# Usage:
#   ./scripts/bootstrap-argocd.sh [OPTIONS]
#
# Options:
#   --skip-jwks    Skip JWKS sync (if Azure Storage already configured)
#   --force        Force reinstall even if already installed
#   -h, --help     Show this help message
#
# Prerequisites:
#   - Talos cluster with kubectl access
#   - Azure infrastructure set up (storage account, AD app, Key Vault)
#   - Kustomize manifests built and pushed to Git
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Configuration
ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.3.0}"
ARGOCD_VALUES_FILE="${SCRIPT_DIR}/../deployment/config/argocd-values.yaml"

# Git configuration (from environment)
GIT_REPO_URL="${GIT_REPO_URL:-https://github.com/PittampalliOrg/stacks.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_PATH="${GIT_PATH:-packages/dist/talos}"

# Parse arguments
SKIP_JWKS=false
FORCE_REINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-jwks)
            SKIP_JWKS=true
            shift
            ;;
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Bootstrap ArgoCD and GitOps for Talos Linux cluster"
            echo ""
            echo "Options:"
            echo "  --skip-jwks    Skip JWKS sync to Azure Storage"
            echo "  --force        Force reinstall even if ArgoCD already installed"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "This script:"
            echo "  1. Removes control-plane taints (CP-only clusters)"
            echo "  2. Syncs JWKS to Azure Storage (Workload Identity)"
            echo "  3. Installs ArgoCD via Helm"
            echo "  4. Applies root ArgoCD Application"
            echo "  5. ArgoCD auto-sync handles everything else!"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

#
# Load environment variables
#
load_environment() {
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "Loading environment from: ${SCRIPT_DIR}/.env"
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    else
        log_warn "No .env file found at ${SCRIPT_DIR}/.env"
        log_info "Using environment variables or defaults"
    fi
}

#
# Validate prerequisites
#
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check required tools
    for cmd in kubectl helm; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Ensure KUBECONFIG is set correctly"
        exit 1
    fi

    # Check nodes are ready
    local ready_nodes
    ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    if [[ "$ready_nodes" -eq 0 ]]; then
        log_error "No Ready nodes in cluster"
        exit 1
    fi
    log_info "Found $ready_nodes ready node(s)"

    log_success "Prerequisites validated"
}

#
# Remove control-plane taints for CP-only clusters
#
remove_control_plane_taints() {
    log_info "Checking control-plane taints..."

    local tainted_nodes total_nodes
    tainted_nodes=$(kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].key}' 2>/dev/null | wc -w || echo "0")
    total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

    if [[ "$tainted_nodes" -eq "$total_nodes" ]] && [[ "$total_nodes" -gt 0 ]]; then
        log_warn "All $total_nodes nodes have control-plane taint (CP-only cluster)"
        log_info "Removing taints to allow workload scheduling..."

        if kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null; then
            log_success "Control-plane taints removed"
        else
            log_info "Taints already removed or not present"
        fi
    else
        log_info "Cluster has dedicated workers or taints already removed"
    fi
}

#
# Sync JWKS to Azure Storage (for Workload Identity)
#
sync_jwks() {
    if [[ "$SKIP_JWKS" == "true" ]]; then
        log_info "Skipping JWKS sync (--skip-jwks flag)"
        return 0
    fi

    if [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
        log_warn "AZURE_STORAGE_ACCOUNT not set, skipping JWKS sync"
        log_info "Set this in .env if you need Azure Workload Identity"
        return 0
    fi

    log_info "Syncing JWKS to Azure Storage..."

    if [[ -x "${SCRIPT_DIR}/02-sync-jwks.sh" ]]; then
        "${SCRIPT_DIR}/02-sync-jwks.sh" || {
            log_warn "JWKS sync failed, but continuing with bootstrap"
            log_info "You can re-run: ${SCRIPT_DIR}/02-sync-jwks.sh"
        }
    else
        log_warn "JWKS sync script not found: ${SCRIPT_DIR}/02-sync-jwks.sh"
    fi
}

#
# Install ArgoCD via Helm
#
install_argocd() {
    log_info "Installing ArgoCD..."

    # Check if already installed
    if helm list -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -q "argocd"; then
        if [[ "$FORCE_REINSTALL" != "true" ]]; then
            log_success "ArgoCD already installed"

            # Check if pods are healthy
            local ready
            ready=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            if [[ "$ready" -gt 0 ]]; then
                log_info "ArgoCD pods running: $ready"
                return 0
            else
                log_warn "ArgoCD pods not healthy, attempting upgrade..."
            fi
        else
            log_info "Force flag set, upgrading ArgoCD..."
        fi
    fi

    # Add Helm repo
    log_info "Adding Argo Helm repository..."
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update argo

    # Build install command
    local helm_args=(
        --namespace "$ARGOCD_NAMESPACE"
        --create-namespace
        --version "$ARGOCD_CHART_VERSION"
        --wait
        --timeout 10m
    )

    if [[ -f "$ARGOCD_VALUES_FILE" ]]; then
        log_info "Using values file: $ARGOCD_VALUES_FILE"
        helm_args+=(--values "$ARGOCD_VALUES_FILE")
    fi

    # Install or upgrade
    if helm list -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -q "argocd"; then
        log_info "Upgrading ArgoCD..."
        helm upgrade argocd argo/argo-cd "${helm_args[@]}"
    else
        log_info "Installing ArgoCD..."
        helm install argocd argo/argo-cd "${helm_args[@]}"
    fi

    log_success "ArgoCD installed successfully"
}

#
# Apply root ArgoCD Application (App-of-Apps)
#
apply_root_application() {
    log_info "Applying root ArgoCD Application..."

    # Generate manifest
    cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-bootstrap
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: bootstrap-script
    app.kubernetes.io/name: argocd-bootstrap
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GIT_REPO_URL}
    path: ${GIT_PATH}
    targetRevision: ${GIT_BRANCH}
    directory:
      recurse: false
      include: '*.yaml'
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ARGOCD_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - PrunePropagationPolicy=foreground
EOF

    log_success "Root application applied"
    log_info "ArgoCD will now auto-sync all child applications via sync waves"
}

#
# Print access information
#
print_access_info() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ArgoCD Bootstrap Complete!"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    log_success "ArgoCD is now managing your cluster via GitOps"
    echo ""
    echo "What happens next:"
    echo "  - ArgoCD auto-syncs applications in sync wave order"
    echo "  - First: argocd-config (Ingress health checks)"
    echo "  - Then: local-path-provisioner, external-secrets-operator"
    echo "  - Then: workload-identity-patch, cluster-secret-store"
    echo "  - Finally: All other platform applications"
    echo ""
    echo "Access ArgoCD:"
    echo "  Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  URL:          https://localhost:8080"
    echo ""

    # Get admin password
    local password
    password=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || true
    if [[ -n "$password" ]]; then
        echo "Credentials:"
        echo "  Username: admin"
        echo "  Password: $password"
        echo ""
    fi

    echo "Monitor applications:"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl get applications -n argocd -w  # watch for changes"
    echo ""

    if [[ -n "${TAILSCALE_TAILNET:-}" ]]; then
        echo "Tailscale URLs (after Tailscale services sync):"
        echo "  ArgoCD:  https://argocd-${CLUSTER_NAME:-<cluster>}.${TAILSCALE_TAILNET}.ts.net"
        echo "  K8s API: https://k8s-api-${CLUSTER_NAME:-<cluster>}.${TAILSCALE_TAILNET}.ts.net"
        echo ""
    fi

    echo "════════════════════════════════════════════════════════════════════"
}

#
# Main execution
#
main() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  ArgoCD Bootstrap for Talos Linux"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""

    load_environment
    validate_prerequisites
    remove_control_plane_taints
    sync_jwks
    install_argocd
    apply_root_application
    print_access_info
}

# Run main
main "$@"
