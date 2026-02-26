#!/usr/bin/env bash
#
# Register a spoke cluster with the hub ArgoCD
#
# Creates a ServiceAccount on the spoke cluster, generates a long-lived token,
# and stores both the token and CA certificate in Azure Key Vault for the hub
# to consume via ExternalSecrets.
#
# Prerequisites:
#   - kubectl configured to the SPOKE cluster
#   - az cli authenticated with Key Vault access
#   - AZURE_KEY_VAULT_NAME set
#
# Usage:
#   ./spoke-register.sh <spoke-name>
#   ./spoke-register.sh ryzen
#   ./spoke-register.sh thinkpad
#   ./spoke-register.sh talos

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true

SPOKE_NAME="${1:?Usage: $0 <spoke-name>}"
AZURE_KEY_VAULT_NAME="${AZURE_KEY_VAULT_NAME:-keyvault-thcmfmoo5oeow}"
SA_NAME="argocd-remote-manager"
SA_NAMESPACE="kube-system"
TOKEN_DURATION="8760h" # 1 year

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Registering spoke cluster: ${SPOKE_NAME}"

# Step 1: Create ServiceAccount and ClusterRoleBinding on spoke
log "Creating ServiceAccount ${SA_NAME} in ${SA_NAMESPACE}..."
kubectl apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${SA_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${SA_NAMESPACE}
YAML

# Step 2: Generate a long-lived token
log "Generating token (duration: ${TOKEN_DURATION})..."
TOKEN=$(kubectl create token "${SA_NAME}" -n "${SA_NAMESPACE}" --duration="${TOKEN_DURATION}")

# Step 3: Extract CA certificate
log "Extracting cluster CA certificate..."
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Step 4: Store in Azure Key Vault
SPOKE_UPPER=$(echo "${SPOKE_NAME}" | tr '[:lower:]' '[:upper:]')

log "Storing token in Key Vault as ARGOCD-CLUSTER-${SPOKE_UPPER}-TOKEN..."
az keyvault secret set \
  --vault-name "${AZURE_KEY_VAULT_NAME}" \
  --name "ARGOCD-CLUSTER-${SPOKE_UPPER}-TOKEN" \
  --value "${TOKEN}" \
  --output none

log "Storing CA in Key Vault as ARGOCD-CLUSTER-${SPOKE_UPPER}-CA..."
az keyvault secret set \
  --vault-name "${AZURE_KEY_VAULT_NAME}" \
  --name "ARGOCD-CLUSTER-${SPOKE_UPPER}-CA" \
  --value "${CA_DATA}" \
  --output none

log "Spoke ${SPOKE_NAME} registered successfully"
log ""
log "Key Vault secrets created:"
log "  ARGOCD-CLUSTER-${SPOKE_UPPER}-TOKEN"
log "  ARGOCD-CLUSTER-${SPOKE_UPPER}-CA"
log ""
log "The hub ExternalSecret will sync these to ArgoCD cluster secrets."
log "Verify on hub: kubectl get secret cluster-${SPOKE_NAME} -n argocd"
