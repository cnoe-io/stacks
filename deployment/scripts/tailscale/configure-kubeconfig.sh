#!/usr/bin/env bash
#
# configure-kubeconfig.sh - Merge remote kubeconfig into local ~/.kube/config
#
# This script merges the Tailscale remote kubeconfig with your existing kubeconfig,
# allowing easy context switching between local and remote clusters.
#
# Usage:
#   ./configure-kubeconfig.sh [remote-kubeconfig-path]
#
# Example:
#   ./configure-kubeconfig.sh ~/remote-kubeconfig.yaml
#
# Prerequisites:
#   - kubectl installed
#   - remote-kubeconfig.yaml file exists (generated via generate-kubeconfig.sh)
#   - ~/.kube/config exists (or will be created)
#

set -euo pipefail

# Configuration
REMOTE_KUBECONFIG="${1:-$HOME/remote-kubeconfig.yaml}"
LOCAL_KUBECONFIG="$HOME/.kube/config"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo "=========================================="
echo "📦 Kubeconfig Merge Configuration"
echo "=========================================="
echo ""

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl first."
    exit 1
fi

log_info "kubectl version: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"

# Check if remote kubeconfig exists
if [ ! -f "$REMOTE_KUBECONFIG" ]; then
    log_error "Remote kubeconfig not found: $REMOTE_KUBECONFIG"
    echo ""
    echo "Please ensure you have:"
    echo "  1. Generated remote-kubeconfig.yaml on cluster host:"
    echo "     cd ~/stacks && ./deployment/scripts/tailscale/generate-kubeconfig.sh"
    echo ""
    echo "  2. Copied it to this machine:"
    echo "     scp cluster-host:~/stacks/remote-kubeconfig.yaml ~/remote-kubeconfig.yaml"
    echo ""
    exit 1
fi

log_info "✓ Found remote kubeconfig: $REMOTE_KUBECONFIG"

# Check if local kubeconfig directory exists
if [ ! -d "$HOME/.kube" ]; then
    log_warn "Creating ~/.kube directory..."
    mkdir -p "$HOME/.kube"
fi

# Backup existing kubeconfig if it exists
if [ -f "$LOCAL_KUBECONFIG" ]; then
    BACKUP_FILE="${LOCAL_KUBECONFIG}${BACKUP_SUFFIX}"
    log_step "Backing up existing kubeconfig..."
    cp "$LOCAL_KUBECONFIG" "$BACKUP_FILE"
    log_info "✓ Backup created: $BACKUP_FILE"
else
    log_warn "No existing kubeconfig found at $LOCAL_KUBECONFIG"
    log_info "Will create new kubeconfig with remote context only"
fi

# Merge kubeconfigs
log_step "Merging kubeconfigs..."

if [ -f "$LOCAL_KUBECONFIG" ]; then
    # Merge existing + remote
    KUBECONFIG="$LOCAL_KUBECONFIG:$REMOTE_KUBECONFIG" kubectl config view --flatten > "$LOCAL_KUBECONFIG.new"
else
    # Just use remote (no existing config)
    cp "$REMOTE_KUBECONFIG" "$LOCAL_KUBECONFIG.new"
fi

# Validate merged kubeconfig
if ! kubectl --kubeconfig="$LOCAL_KUBECONFIG.new" config get-contexts &> /dev/null; then
    log_error "Merged kubeconfig validation failed!"
    log_error "Your original kubeconfig is safe at: ${LOCAL_KUBECONFIG}${BACKUP_SUFFIX}"
    rm -f "$LOCAL_KUBECONFIG.new"
    exit 1
fi

# Replace original with merged
mv "$LOCAL_KUBECONFIG.new" "$LOCAL_KUBECONFIG"
log_info "✓ Kubeconfig merged successfully: $LOCAL_KUBECONFIG"

echo ""
echo "=========================================="
echo "📋 Available Contexts:"
echo "=========================================="
echo ""

kubectl config get-contexts

echo ""
echo "=========================================="
echo "🔧 Next Steps:"
echo "=========================================="
echo ""

# Check if kind-tailscale context exists
if kubectl config get-contexts kind-tailscale &> /dev/null; then
    log_step "Switch to Tailscale remote cluster:"
    echo "   kubectl config use-context kind-tailscale"
    echo ""

    log_step "Test connectivity (first connection may take 30-60s for cert provisioning):"
    echo "   kubectl get nodes --request-timeout=60s"
    echo ""

    log_step "Verify authentication:"
    echo "   kubectl auth whoami"
    echo ""

    log_step "Switch back to local cluster (if you have one):"
    echo "   kubectl config get-contexts  # List all contexts"
    echo "   kubectl config use-context <context-name>"
    echo ""
else
    log_warn "Could not find 'kind-tailscale' context in merged config"
    log_info "Available contexts listed above. Use: kubectl config use-context <name>"
fi

echo "=========================================="
echo "💡 Tips:"
echo "=========================================="
echo ""
echo "• View current context:"
echo "  kubectl config current-context"
echo ""
echo "• Quick context switching:"
echo "  kubectl config use-context <context-name>"
echo ""
echo "• Restore from backup (if needed):"
echo "  cp ${LOCAL_KUBECONFIG}${BACKUP_SUFFIX} $LOCAL_KUBECONFIG"
echo ""
echo "• Headlamp Desktop:"
echo "  Will automatically detect all contexts and show a dropdown switcher"
echo ""

log_info "Configuration complete! 🎉"
