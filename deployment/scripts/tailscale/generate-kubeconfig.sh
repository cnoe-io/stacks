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

# Defaults / tunables
CLUSTER_NAME="${1:-kind}"
TAILNET_NAME="${2:-tail286401}"
OUTPUT_FILE="remote-kubeconfig.yaml"

# Optional modes via env (kept lightweight to avoid breaking callers)
# USE_SERVICE_ACCOUNT=true   -> generate kubeconfig with a cluster-admin service account token instead of client certs
# SA_NAME=tailscale-remote    -> name for the service account/CRB
# KUBEADMIN_CONTAINER_HINT    -> override autodetected kind control-plane container name
# OP_UPLOAD=true              -> upload the generated kubeconfig to 1Password via `op document create`
# OP_VAULT=Shared             -> target 1Password vault (defaults to account default)
# OP_TITLE=remote-kubeconfig  -> document title

USE_SERVICE_ACCOUNT=${USE_SERVICE_ACCOUNT:-false}
SA_NAME=${SA_NAME:-tailscale-remote}
OP_UPLOAD=${OP_UPLOAD:-false}
OP_VAULT=${OP_VAULT:-}
OP_TITLE=${OP_TITLE:-remote-kubeconfig}

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

# Helper: try to switch to kind's admin.conf if current kubeconfig lacks client creds
TEMP_KUBECONFIG=""
maybe_use_kind_admin_conf() {
    if [ -n "$TEMP_KUBECONFIG" ]; then
        return
    fi
    if ! command -v docker >/dev/null 2>&1; then
        log_warn "Docker not available; cannot auto-pull admin.conf from kind"
        return
    fi
    local kind_container
    kind_container=${KUBEADMIN_CONTAINER_HINT:-$(docker ps --format '{{.Names}}' | grep -E 'control-plane$' | head -1)}
    if [ -z "$kind_container" ]; then
        log_warn "Could not find kind control-plane container"
        return
    fi
    TEMP_KUBECONFIG=$(mktemp /tmp/kind-admin-XXXX.yaml)
    if docker exec "$kind_container" cat /etc/kubernetes/admin.conf > "$TEMP_KUBECONFIG" 2>/dev/null; then
        export KUBECONFIG="$TEMP_KUBECONFIG"
        log_info "✓ Pulled admin.conf from ${kind_container}"
    else
        log_warn "Failed to read admin.conf from ${kind_container}"
        rm -f "$TEMP_KUBECONFIG"
        TEMP_KUBECONFIG=""
    fi
}

cleanup_tmp() {
    if [ -n "$TEMP_KUBECONFIG" ] && [ -f "$TEMP_KUBECONFIG" ]; then
        rm -f "$TEMP_KUBECONFIG"
    fi
}
trap cleanup_tmp EXIT

CLIENT_CERT=""
CLIENT_KEY=""
CURRENT_USER=""
CA_CERT=""
TOKEN=""

if [ "$USE_SERVICE_ACCOUNT" != "true" ]; then
    log_info "Extracting client certificate..."
    CLIENT_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null || true)
    if [ -z "$CLIENT_CERT" ]; then
        log_warn "No client cert found in current kubeconfig; attempting to pull admin.conf from kind"
        maybe_use_kind_admin_conf
        CLIENT_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null || true)
    fi

    if [ -z "$CLIENT_CERT" ]; then
        log_error "Failed to extract client certificate from kubeconfig"
        exit 1
    fi

    log_info "Extracting client key..."
    CLIENT_KEY=$(kubectl config view --raw --minify --flatten -o jsonpath='{.users[0].user.client-key-data}' 2>/dev/null || true)
    if [ -z "$CLIENT_KEY" ]; then
        log_warn "No client key found; attempting to pull admin.conf from kind"
        maybe_use_kind_admin_conf
        CLIENT_KEY=$(kubectl config view --raw --minify --flatten -o jsonpath='{.users[0].user.client-key-data}' 2>/dev/null || true)
    fi

    if [ -z "$CLIENT_KEY" ]; then
        log_error "Failed to extract client key from kubeconfig"
        exit 1
    fi

    CURRENT_USER=$(kubectl config view --minify -o jsonpath='{.users[0].name}')
else
    log_info "Service account mode enabled (USE_SERVICE_ACCOUNT=true)"
    # Ensure SA + CRB exist
    kubectl create namespace tailscale --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    kubectl create serviceaccount "$SA_NAME" -n tailscale --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${SA_NAME}
  namespace: tailscale
EOF
    TOKEN=$(kubectl create token "$SA_NAME" -n tailscale --duration=87600h)
    CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    CURRENT_USER="$SA_NAME"
    if [ -z "$TOKEN" ] || [ -z "$CA_CERT" ]; then
        log_error "Failed to obtain service account token/CA"
        exit 1
    fi
    log_info "✓ Generated long-lived service account token"
fi

# Generate kubeconfig
log_info "Generating kubeconfig file: ${OUTPUT_FILE}"

cat > "${OUTPUT_FILE}" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${OPERATOR_HOSTNAME}:443
$(if [ "$USE_SERVICE_ACCOUNT" = "true" ]; then
  echo "    certificate-authority-data: ${CA_CERT}"
else
  echo "    insecure-skip-tls-verify: true"
fi)
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
$(if [ "$USE_SERVICE_ACCOUNT" = "true" ]; then
  echo "    token: ${TOKEN}"
else
  cat <<INNER
    client-certificate-data: ${CLIENT_CERT}
    client-key-data: ${CLIENT_KEY}
INNER
fi)
EOF

if [ "$OP_UPLOAD" = "true" ]; then
    if command -v op >/dev/null 2>&1; then
        log_info "Uploading kubeconfig to 1Password..."
        if op document create "${OUTPUT_FILE}" --title "${OP_TITLE}" ${OP_VAULT:+--vault "$OP_VAULT"} --tags tailscale,kubeconfig >/dev/null 2>&1; then
            log_info "✓ Stored in 1Password as '${OP_TITLE}'${OP_VAULT:+ (vault: $OP_VAULT)}"
        else
            log_warn "1Password upload failed (is 'op signin' active?)"
        fi
    else
        log_warn "op CLI not found; skipping 1Password upload"
    fi
fi

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
