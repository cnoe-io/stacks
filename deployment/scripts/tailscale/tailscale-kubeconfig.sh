#!/usr/bin/env bash
#
# tailscale-kubeconfig.sh - Generate/retrieve remote kubeconfig for Tailscale Services access
#
# This script manages remote kubectl access via Tailscale Services (k8s-api.<tailnet>.ts.net).
# It uses the k8s-remote-access ServiceAccount created by the K8sApiTailscaleServeChart.
#
# Token is stored in Azure Key Vault for persistence across cluster recreations.
# Kubeconfig can optionally be stored in 1Password for easy distribution.
#
# Usage:
#   ./tailscale-kubeconfig.sh [command]
#
# Commands:
#   generate    Generate new token and store in Key Vault (after cluster recreation)
#   get         Get kubeconfig (retrieves token from Key Vault)
#   save-op     Save kubeconfig to 1Password
#   test        Test remote access
#
# Environment Variables:
#   AZURE_KEYVAULT_NAME     Key Vault name (default: keyvault-thcmfmoo5oeow)
#   TAILNET_NAME            Tailnet name (default: tail286401)
#   SERVICE_NAME            k8s-api service name (default: k8s-api)
#   OUTPUT_FILE             Output kubeconfig file (default: ~/.kube/tailscale-cluster.yaml)
#
# 1Password Integration:
#   OP_VAULT                Target vault (default: CLI)
#   OP_TITLE                Item title (default: K8s Remote Access)
#

set -euo pipefail

# Configuration
AZURE_KEYVAULT_NAME="${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}"
TAILNET_NAME="${TAILNET_NAME:-tail286401}"
SERVICE_NAME="${SERVICE_NAME:-k8s-api}"
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/.kube/tailscale-cluster.yaml}"

# 1Password configuration
OP_VAULT="${OP_VAULT:-CLI}"
OP_TITLE="${OP_TITLE:-K8s Remote Access}"
OP_ITEM_ID="${OP_ITEM_ID:-}"  # Will be set after first creation

# ServiceAccount details (must match cdk8s chart)
SA_NAME="k8s-remote-access"
SA_NAMESPACE="tailscale"
TOKEN_DURATION="8760h"  # 1 year

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check prerequisites
check_prereqs() {
    local missing=()

    command -v kubectl &>/dev/null || missing+=("kubectl")
    command -v az &>/dev/null || missing+=("az CLI")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites: ${missing[*]}"
        exit 1
    fi
}

# Generate new token and store in Azure Key Vault
generate_token() {
    log_step "Generating new remote access token..."

    # Check if ServiceAccount exists
    if ! kubectl get sa "$SA_NAME" -n "$SA_NAMESPACE" &>/dev/null; then
        log_error "ServiceAccount $SA_NAME not found in namespace $SA_NAMESPACE"
        log_info "Ensure k8s-api-tailscale-serve chart is deployed with createStaticTokenSecret: true"
        exit 1
    fi

    # Generate token
    local token
    token=$(kubectl create token "$SA_NAME" -n "$SA_NAMESPACE" --duration="$TOKEN_DURATION")

    if [ -z "$token" ]; then
        log_error "Failed to generate token"
        exit 1
    fi

    log_info "Token generated (valid for 1 year)"

    # Store in Azure Key Vault
    log_step "Storing token in Azure Key Vault ($AZURE_KEYVAULT_NAME)..."

    if az keyvault secret set \
        --vault-name "$AZURE_KEYVAULT_NAME" \
        --name "K8S-REMOTE-ACCESS-TOKEN" \
        --value "$token" \
        --output none 2>/dev/null; then
        log_info "Token stored in Key Vault as K8S-REMOTE-ACCESS-TOKEN"
    else
        log_error "Failed to store token in Key Vault"
        log_warn "Token (save manually): $token"
        exit 1
    fi

    echo "$token"
}

# Get token from Azure Key Vault
get_token() {
    local token
    token=$(az keyvault secret show \
        --vault-name "$AZURE_KEYVAULT_NAME" \
        --name "K8S-REMOTE-ACCESS-TOKEN" \
        --query value -o tsv 2>/dev/null || true)

    if [ -z "$token" ]; then
        log_error "Token not found in Key Vault"
        log_info "Run '$0 generate' after cluster creation to generate a new token"
        exit 1
    fi

    echo "$token"
}

# Generate kubeconfig file
generate_kubeconfig() {
    local token="$1"
    local output="${2:-$OUTPUT_FILE}"

    mkdir -p "$(dirname "$output")"

    cat > "$output" << EOF
apiVersion: v1
kind: Config
clusters:
- name: tailscale-cluster
  cluster:
    server: https://${SERVICE_NAME}.${TAILNET_NAME}.ts.net
contexts:
- name: tailscale-cluster
  context:
    cluster: tailscale-cluster
    user: tailscale-admin
current-context: tailscale-cluster
users:
- name: tailscale-admin
  user:
    token: ${token}
EOF

    chmod 600 "$output"
    log_info "Kubeconfig written to: $output"
}

# Get kubeconfig (retrieve from Key Vault and generate file)
cmd_get() {
    log_step "Retrieving token from Azure Key Vault..."
    local token
    token=$(get_token)

    log_step "Generating kubeconfig..."
    generate_kubeconfig "$token"

    echo ""
    echo "=========================================="
    echo "Kubeconfig ready: $OUTPUT_FILE"
    echo "=========================================="
    echo ""
    echo "Usage:"
    echo "  kubectl --kubeconfig=$OUTPUT_FILE get nodes"
    echo ""
    echo "Or set as default:"
    echo "  export KUBECONFIG=$OUTPUT_FILE"
    echo "  kubectl get nodes"
    echo ""
}

# Generate new token (after cluster recreation)
cmd_generate() {
    check_prereqs

    # Check cluster access
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot access Kubernetes cluster"
        exit 1
    fi

    local token
    token=$(generate_token)

    log_step "Generating kubeconfig..."
    generate_kubeconfig "$token"

    echo ""
    echo "=========================================="
    echo "Remote access configured!"
    echo "=========================================="
    echo ""
    echo "Token stored in: Azure Key Vault ($AZURE_KEYVAULT_NAME)"
    echo "Kubeconfig at:   $OUTPUT_FILE"
    echo ""
    echo "Test with:"
    echo "  kubectl --kubeconfig=$OUTPUT_FILE get nodes"
    echo ""
}

# Save kubeconfig to 1Password
cmd_save_op() {
    if ! command -v op &>/dev/null; then
        log_error "1Password CLI (op) not installed"
        exit 1
    fi

    log_step "Retrieving token from Azure Key Vault..."
    local token
    token=$(get_token)

    # Generate temporary kubeconfig
    local tmp_config
    tmp_config=$(mktemp)
    generate_kubeconfig "$token" "$tmp_config"

    log_step "Saving to 1Password..."

    # Check if item exists
    if [ -n "$OP_ITEM_ID" ] && op item get "$OP_ITEM_ID" --vault "$OP_VAULT" &>/dev/null 2>&1; then
        # Update existing document
        if op document edit "$OP_ITEM_ID" "$tmp_config" --vault "$OP_VAULT" &>/dev/null; then
            log_info "Updated kubeconfig in 1Password: $OP_TITLE"
        else
            log_warn "Failed to update document, creating new..."
            op document create "$tmp_config" --title "$OP_TITLE" --vault "$OP_VAULT" --tags "kubernetes,tailscale,remote-access"
        fi
    else
        # Create new document
        if op document create "$tmp_config" --title "$OP_TITLE" --vault "$OP_VAULT" --tags "kubernetes,tailscale,remote-access"; then
            log_info "Kubeconfig saved to 1Password: $OP_TITLE (vault: $OP_VAULT)"
        else
            log_error "Failed to save to 1Password"
            rm -f "$tmp_config"
            exit 1
        fi
    fi

    rm -f "$tmp_config"

    echo ""
    echo "=========================================="
    echo "Kubeconfig saved to 1Password!"
    echo "=========================================="
    echo ""
    echo "Retrieve on remote machine:"
    echo "  op document get '$OP_TITLE' --vault '$OP_VAULT' > ~/.kube/tailscale-cluster.yaml"
    echo ""
}

# Push kubeconfig to remote machine via SSH
cmd_push() {
    local remote_host="${1:-}"
    local remote_path="${2:-~/.kube/tailscale-cluster.yaml}"

    if [ -z "$remote_host" ]; then
        log_error "Usage: $0 push <remote-host> [remote-path]"
        echo ""
        echo "Examples:"
        echo "  $0 push m1                          # Push to m1:~/.kube/tailscale-cluster.yaml"
        echo "  $0 push user@host ~/.kube/config    # Push to custom path"
        exit 1
    fi

    log_step "Retrieving token from Azure Key Vault..."
    local token
    token=$(get_token)

    # Generate temporary kubeconfig
    local tmp_config
    tmp_config=$(mktemp)
    generate_kubeconfig "$token" "$tmp_config"

    log_step "Pushing kubeconfig to $remote_host:$remote_path..."

    # Ensure remote directory exists and copy file
    ssh "$remote_host" "mkdir -p ~/.kube"
    scp "$tmp_config" "$remote_host:$remote_path"
    ssh "$remote_host" "chmod 600 $remote_path"

    rm -f "$tmp_config"

    log_info "Kubeconfig pushed to $remote_host:$remote_path"

    echo ""
    echo "=========================================="
    echo "Kubeconfig deployed to $remote_host"
    echo "=========================================="
    echo ""
    echo "Test from $remote_host:"
    echo "  kubectl --kubeconfig=$remote_path get nodes"
    echo ""
    echo "Or set as default context:"
    echo "  export KUBECONFIG=$remote_path"
    echo ""
}

# Get kubeconfig from 1Password (for machines without Azure CLI)
cmd_get_op() {
    if ! command -v op &>/dev/null; then
        log_error "1Password CLI (op) not installed"
        exit 1
    fi

    log_step "Retrieving kubeconfig from 1Password..."

    mkdir -p "$(dirname "$OUTPUT_FILE")"

    if op document get "$OP_TITLE" --vault "$OP_VAULT" --out-file "$OUTPUT_FILE" 2>/dev/null; then
        chmod 600 "$OUTPUT_FILE"
        log_info "Kubeconfig retrieved from 1Password: $OUTPUT_FILE"
    else
        log_error "Failed to retrieve kubeconfig from 1Password"
        echo ""
        echo "Ensure the kubeconfig was saved with:"
        echo "  $0 save-op"
        exit 1
    fi

    echo ""
    echo "=========================================="
    echo "Kubeconfig ready: $OUTPUT_FILE"
    echo "=========================================="
    echo ""
    echo "Usage:"
    echo "  kubectl --kubeconfig=$OUTPUT_FILE get nodes"
    echo ""
}

# Test remote access
cmd_test() {
    local kubeconfig="${1:-$OUTPUT_FILE}"

    if [ ! -f "$kubeconfig" ]; then
        log_warn "Kubeconfig not found at $kubeconfig, generating..."
        cmd_get
    fi

    log_step "Testing remote access..."
    echo ""

    if kubectl --kubeconfig="$kubeconfig" get nodes --request-timeout=30s; then
        echo ""
        log_info "Remote access working!"
    else
        echo ""
        log_error "Remote access failed"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Ensure k8s-api-tailscale-serve pod is running:"
        echo "     kubectl get pods -n tailscale -l app.kubernetes.io/name=k8s-api-tailscale-serve"
        echo ""
        echo "  2. Check Tailscale service status:"
        echo "     kubectl logs -n tailscale -l app.kubernetes.io/name=k8s-api-tailscale-serve -c tailscale-serve"
        echo ""
        echo "  3. Verify Tailscale ACL grants access to svc:k8s-api"
        echo ""
        exit 1
    fi
}

# Show help
show_help() {
    cat << EOF
Tailscale Services Remote Kubeconfig Manager

Manages remote kubectl access via Tailscale Services (k8s-api.<tailnet>.ts.net).
Token is stored in Azure Key Vault for persistence across cluster recreations.

Usage:
  $0 <command>

Commands:
  generate    Generate new token and store in Key Vault (run after cluster recreation)
  get         Retrieve token from Key Vault and generate kubeconfig file
  push        Push kubeconfig to remote machine via SSH (run from cluster host)
  get-op      Get kubeconfig from 1Password (for machines without Azure CLI)
  save-op     Save kubeconfig to 1Password for easy distribution
  test        Test remote kubectl access

Examples:
  # After cluster recreation (on cluster host):
  $0 generate

  # Push kubeconfig to remote machine (from cluster host):
  $0 push m1                    # Push to m1:~/.kube/tailscale-cluster.yaml
  $0 push m1 ~/.kube/config     # Push to default kubeconfig location

  # On remote machine with Azure CLI:
  $0 get

  # On remote machine with 1Password CLI (no Azure CLI needed):
  $0 get-op

  # Test access:
  $0 test

Environment Variables:
  AZURE_KEYVAULT_NAME   Azure Key Vault name (default: keyvault-thcmfmoo5oeow)
  TAILNET_NAME          Tailscale tailnet (default: tail286401)
  SERVICE_NAME          Service name (default: k8s-api)
  OUTPUT_FILE           Output file (default: ~/.kube/tailscale-cluster.yaml)
  OP_VAULT              1Password vault (default: CLI)
  OP_TITLE              1Password item title (default: K8s Remote Access)

Token Management:
  - Token is stored in Azure Key Vault as K8S-REMOTE-ACCESS-TOKEN
  - Token duration: 1 year (regenerate before expiration)
  - ServiceAccount: k8s-remote-access (namespace: tailscale)
EOF
}

# Main
case "${1:-help}" in
    generate)
        cmd_generate
        ;;
    get)
        cmd_get
        ;;
    push)
        shift || true
        cmd_push "$@"
        ;;
    get-op|get-1password)
        cmd_get_op
        ;;
    save-op|save-1password)
        cmd_save_op
        ;;
    test)
        shift || true
        cmd_test "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
