#!/bin/bash
# spoke-helpers.sh - Helper functions for spoke cluster credential management
#
# This library provides functions for:
# - Creating ServiceAccounts on spoke clusters for ArgoCD management
# - Generating long-lived tokens
# - Exporting credentials to Azure Key Vault
# - Validating spoke cluster connectivity
#
# Usage:
#   source scripts/lib/spoke-helpers.sh
#   create_spoke_service_account "thinkpad"
#   export_credentials_to_keyvault "thinkpad"

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_SA_NAME="argocd-remote-manager"
DEFAULT_SA_NAMESPACE="kube-system"
DEFAULT_TOKEN_DURATION="8760h"  # 1 year
DEFAULT_KEYVAULT_NAME="${AZURE_KEYVAULT_NAME:-}"

# Valid spoke cluster names
VALID_SPOKES=("hetzner" "thinkpad" "ryzen" "talos")

# ============================================================================
# Validation Functions
# ============================================================================

# Validate spoke cluster name
validate_spoke_name() {
  local spoke_name="$1"
  for valid in "${VALID_SPOKES[@]}"; do
    if [[ "$spoke_name" == "$valid" ]]; then
      return 0
    fi
  done
  echo -e "${RED}Error: Invalid spoke name '$spoke_name'${NC}"
  echo "Valid spoke names: ${VALID_SPOKES[*]}"
  return 1
}

# Check if kubectl context exists for spoke
validate_kubectl_context() {
  local spoke_name="$1"
  if ! kubectl config get-contexts "$spoke_name" &>/dev/null; then
    echo -e "${YELLOW}Warning: kubectl context '$spoke_name' not found${NC}"
    echo "Available contexts:"
    kubectl config get-contexts -o name
    return 1
  fi
  return 0
}

# Check Azure CLI is logged in and has Key Vault access
validate_azure_access() {
  if [[ -z "$DEFAULT_KEYVAULT_NAME" ]]; then
    echo -e "${RED}Error: AZURE_KEYVAULT_NAME environment variable not set${NC}"
    return 1
  fi

  if ! az account show &>/dev/null; then
    echo -e "${RED}Error: Not logged in to Azure CLI${NC}"
    echo "Run: az login"
    return 1
  fi

  if ! az keyvault show --name "$DEFAULT_KEYVAULT_NAME" &>/dev/null; then
    echo -e "${RED}Error: Cannot access Key Vault '$DEFAULT_KEYVAULT_NAME'${NC}"
    return 1
  fi

  return 0
}

# ============================================================================
# Credential Functions
# ============================================================================

# Get Azure Key Vault secret key names for a spoke
get_keyvault_keys() {
  local spoke_name="$1"
  local upper_name
  upper_name=$(echo "$spoke_name" | tr '[:lower:]' '[:upper:]')

  echo "TOKEN_KEY=ARGOCD-CLUSTER-${upper_name}-TOKEN"
  echo "CA_KEY=ARGOCD-CLUSTER-${upper_name}-CA"
}

# Create ServiceAccount on spoke cluster for ArgoCD management
create_spoke_service_account() {
  local spoke_name="$1"
  local sa_name="${2:-$DEFAULT_SA_NAME}"
  local sa_namespace="${3:-$DEFAULT_SA_NAMESPACE}"

  validate_spoke_name "$spoke_name" || return 1
  validate_kubectl_context "$spoke_name" || return 1

  echo -e "${GREEN}Creating ServiceAccount '$sa_name' on spoke '$spoke_name'...${NC}"

  kubectl --context="$spoke_name" apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $sa_name
  namespace: $sa_namespace
  labels:
    app.kubernetes.io/name: $sa_name
    app.kubernetes.io/component: hub-spoke-integration
    app.kubernetes.io/managed-by: spoke-helpers
  annotations:
    description: "ServiceAccount for hub ArgoCD to manage this spoke cluster"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $sa_name
  labels:
    app.kubernetes.io/name: $sa_name
    app.kubernetes.io/component: hub-spoke-integration
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: $sa_name
    namespace: $sa_namespace
EOF

  echo -e "${GREEN}ServiceAccount created successfully${NC}"
}

# Generate long-lived token for ServiceAccount
generate_spoke_token() {
  local spoke_name="$1"
  local sa_name="${2:-$DEFAULT_SA_NAME}"
  local sa_namespace="${3:-$DEFAULT_SA_NAMESPACE}"
  local duration="${4:-$DEFAULT_TOKEN_DURATION}"

  validate_spoke_name "$spoke_name" || return 1
  validate_kubectl_context "$spoke_name" || return 1

  echo -e "${GREEN}Generating token for '$sa_name' on spoke '$spoke_name' (duration: $duration)...${NC}"

  local token
  token=$(kubectl --context="$spoke_name" create token "$sa_name" \
    -n "$sa_namespace" \
    --duration="$duration")

  echo "$token"
}

# Get cluster CA certificate (base64 encoded)
get_spoke_ca() {
  local spoke_name="$1"

  validate_spoke_name "$spoke_name" || return 1
  validate_kubectl_context "$spoke_name" || return 1

  echo -e "${GREEN}Extracting CA certificate from spoke '$spoke_name'...${NC}" >&2

  local ca_data
  ca_data=$(kubectl --context="$spoke_name" config view --raw \
    -o jsonpath='{.clusters[?(@.name=="'"$spoke_name"'")].cluster.certificate-authority-data}')

  # If not found by exact name, try to get from current context cluster
  if [[ -z "$ca_data" ]]; then
    ca_data=$(kubectl --context="$spoke_name" config view --raw \
      -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
  fi

  echo "$ca_data"
}

# Export credentials to Azure Key Vault
export_credentials_to_keyvault() {
  local spoke_name="$1"
  local sa_name="${2:-$DEFAULT_SA_NAME}"
  local sa_namespace="${3:-$DEFAULT_SA_NAMESPACE}"

  validate_spoke_name "$spoke_name" || return 1
  validate_azure_access || return 1

  local upper_name
  upper_name=$(echo "$spoke_name" | tr '[:lower:]' '[:upper:]')

  echo -e "${GREEN}Exporting credentials for spoke '$spoke_name' to Azure Key Vault...${NC}"

  # Generate token
  local token
  token=$(generate_spoke_token "$spoke_name" "$sa_name" "$sa_namespace")
  if [[ -z "$token" ]]; then
    echo -e "${RED}Error: Failed to generate token${NC}"
    return 1
  fi

  # Get CA certificate
  local ca_data
  ca_data=$(get_spoke_ca "$spoke_name")
  if [[ -z "$ca_data" ]]; then
    echo -e "${RED}Error: Failed to get CA certificate${NC}"
    return 1
  fi

  # Store token in Key Vault
  echo "Storing token in Key Vault..."
  az keyvault secret set \
    --vault-name "$DEFAULT_KEYVAULT_NAME" \
    --name "ARGOCD-CLUSTER-${upper_name}-TOKEN" \
    --value "$token" \
    --output none

  # Store CA in Key Vault
  echo "Storing CA certificate in Key Vault..."
  az keyvault secret set \
    --vault-name "$DEFAULT_KEYVAULT_NAME" \
    --name "ARGOCD-CLUSTER-${upper_name}-CA" \
    --value "$ca_data" \
    --output none

  echo -e "${GREEN}Credentials exported successfully to Key Vault '$DEFAULT_KEYVAULT_NAME'${NC}"
  echo "  Token key: ARGOCD-CLUSTER-${upper_name}-TOKEN"
  echo "  CA key:    ARGOCD-CLUSTER-${upper_name}-CA"
}

# Verify spoke connectivity from hub cluster
verify_spoke_connectivity() {
  local spoke_name="$1"
  local hub_context="${2:-}"

  validate_spoke_name "$spoke_name" || return 1

  local server_url="https://k8s-api-${spoke_name}.tail286401.ts.net"

  echo -e "${GREEN}Verifying connectivity to spoke '$spoke_name'...${NC}"
  echo "Server URL: $server_url"

  # Test DNS resolution
  local host="k8s-api-${spoke_name}.tail286401.ts.net"
  if ! host "$host" &>/dev/null && ! dig +short "$host" &>/dev/null; then
    echo -e "${YELLOW}Warning: DNS resolution failed for $host${NC}"
    echo "This may be expected if not on Tailscale network"
  else
    echo "DNS resolution: OK"
  fi

  # If hub context specified, test from hub
  if [[ -n "$hub_context" ]]; then
    echo "Testing connectivity from hub cluster..."
    kubectl --context="$hub_context" run test-spoke-connectivity \
      --rm -it --restart=Never \
      --image=curlimages/curl \
      -- curl -sk "$server_url/healthz" || true
  fi
}

# List all spoke credentials in Key Vault
list_spoke_credentials() {
  validate_azure_access || return 1

  echo -e "${GREEN}Listing spoke credentials in Key Vault '$DEFAULT_KEYVAULT_NAME'...${NC}"
  echo ""

  for spoke in "${VALID_SPOKES[@]}"; do
    local upper_name
    upper_name=$(echo "$spoke" | tr '[:lower:]' '[:upper:]')

    local token_exists="❌"
    local ca_exists="❌"

    if az keyvault secret show --vault-name "$DEFAULT_KEYVAULT_NAME" \
        --name "ARGOCD-CLUSTER-${upper_name}-TOKEN" &>/dev/null; then
      token_exists="✅"
    fi

    if az keyvault secret show --vault-name "$DEFAULT_KEYVAULT_NAME" \
        --name "ARGOCD-CLUSTER-${upper_name}-CA" &>/dev/null; then
      ca_exists="✅"
    fi

    echo "  $spoke: Token=$token_exists  CA=$ca_exists"
  done
}

# ============================================================================
# Main (when run directly)
# ============================================================================

# If script is run directly (not sourced), show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "spoke-helpers.sh - Helper functions for spoke cluster credential management"
  echo ""
  echo "Usage:"
  echo "  source scripts/lib/spoke-helpers.sh"
  echo ""
  echo "Available functions:"
  echo "  create_spoke_service_account <spoke_name>     - Create ServiceAccount on spoke"
  echo "  generate_spoke_token <spoke_name>             - Generate long-lived token"
  echo "  get_spoke_ca <spoke_name>                     - Get cluster CA certificate"
  echo "  export_credentials_to_keyvault <spoke_name>   - Export credentials to Key Vault"
  echo "  verify_spoke_connectivity <spoke_name>        - Verify spoke connectivity"
  echo "  list_spoke_credentials                        - List credentials in Key Vault"
  echo ""
  echo "Valid spoke names: ${VALID_SPOKES[*]}"
  echo ""
  echo "Environment variables:"
  echo "  AZURE_KEYVAULT_NAME - Azure Key Vault name for credential storage"
fi
