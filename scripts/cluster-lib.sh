#!/usr/bin/env bash
# Unified Cluster Setup Helper Functions Library
# This library provides functions for setting up workload identity and GitOps on both KIND and AKS clusters

set -Eeuo pipefail
log() { printf '[%(%T)T] %s\n' -1 "$*"; }

# Set up kubectl command with context if provided
KUBECTL_CMD="kubectl"
if [[ -n "${KUBECTL_CONTEXT:-}" ]]; then
    KUBECTL_CMD="kubectl --context $KUBECTL_CONTEXT"
fi

# ──────────────────────── Helper Functions ────────────────────────────

# Detect cluster type based on context or explicit setting
detect_cluster_type() {
  # First check if CLUSTER_TYPE is already set by Makefile
  if [[ -n "${CLUSTER_TYPE:-}" ]]; then
    echo "$CLUSTER_TYPE"
    return
  fi
  
  # Otherwise, detect from kubectl context server URL
  local server_url="${KUBECTL_SERVER:-}"
  if [[ -z "$server_url" ]] && [[ -n "${KUBECTL_CONTEXT:-}" ]]; then
    server_url=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$KUBECTL_CONTEXT')].cluster.server}" 2>/dev/null || echo "")
  fi
  
  # Check server URL patterns
  if [[ "$server_url" == *"azmk8s.io"* ]]; then
    echo "aks"
  elif [[ "$server_url" == *"127.0.0.1"* ]] || [[ "$server_url" == *"localhost"* ]]; then
    echo "kind"
  else
    # Fallback to context name patterns
    local context="${KUBECTL_CONTEXT:-$(kubectl config current-context 2>/dev/null || echo "")}"
    if [[ "$context" == *"kind"* ]]; then
      echo "kind"
    elif [[ "$context" == *"aks"* ]] || [[ "$context" == *"azure"* ]]; then
      echo "aks"
    else
      echo "unknown"
    fi
  fi
}

# Check DNS resolution
require_dns() {
  local h=${1:-login.microsoftonline.com}
  for _ in {1..30}; do getent hosts "$h" &>/dev/null && return; sleep 2; done
  log "❌  DNS lookup for $h failed"; return 1
}

# Get OIDC issuer URL from Azure storage account
get_oidc_issuer_from_azure() {
  local resource_group="${RESOURCE_GROUP:-${AKS_RESOURCE_GROUP:-}}"
  local quiet="${1:-false}"
  
  if [[ -z "$resource_group" ]]; then
    [[ "$quiet" != "true" ]] && log "❌ RESOURCE_GROUP not set"
    return 1
  fi
  
  [[ "$quiet" != "true" ]] && log "🔍 Looking for OIDC storage account in resource group '$resource_group'..."
  
  # Find OIDC storage account with tags or by prefix
  local storage_account=$(az storage account list -g "$resource_group" \
    --query "[?starts_with(name, 'oidcissuer') && tags.purpose=='workload-identity-oidc'].name | [0]" -o tsv 2>/dev/null)
  
  # If no tagged account found, try any account with oidcissuer prefix
  if [[ -z "$storage_account" ]]; then
    storage_account=$(az storage account list -g "$resource_group" \
      --query "[?starts_with(name, 'oidcissuer')].name | [0]" -o tsv 2>/dev/null)
  fi
  
  if [[ -n "$storage_account" ]]; then
    local issuer=$(az storage account show -n "$storage_account" -g "$resource_group" \
      --query "primaryEndpoints.web" -o tsv 2>/dev/null)
    if [[ -n "$issuer" ]]; then
      [[ "$quiet" != "true" ]] && log "✅ Found OIDC issuer: $issuer"
      echo "$issuer"
      return 0
    fi
  fi
  
  [[ "$quiet" != "true" ]] && log "❌ No OIDC storage account found in resource group '$resource_group'"
  return 1
}

# Get Azure AD app ID from environment files
get_azure_app_id() {
  local quiet="${1:-false}"
  
  # Use AZURE_CLIENT_ID from environment (loaded from env files)
  if [[ -n "${AZURE_CLIENT_ID:-}" ]]; then
    [[ "$quiet" != "true" ]] && log "✅ Using AZURE_CLIENT_ID: ${AZURE_CLIENT_ID}"
    echo "${AZURE_CLIENT_ID}"
    return 0
  fi
  
  # Fallback to APP_ID if AZURE_CLIENT_ID not set
  if [[ -n "${APP_ID:-}" ]]; then
    [[ "$quiet" != "true" ]] && log "✅ Using APP_ID: ${APP_ID}"
    echo "${APP_ID}"
    return 0
  fi
  
  [[ "$quiet" != "true" ]] && log "❌ No AZURE_CLIENT_ID or APP_ID found in environment"
  return 1
}

# Get Azure Key Vault name from resource group
get_keyvault_name() {
  local resource_group="${RESOURCE_GROUP:-${AKS_RESOURCE_GROUP:-}}"
  
  if [[ -z "$resource_group" ]]; then
    log "❌ RESOURCE_GROUP not set"
    return 1
  fi
  
  log "🔍 Looking for Key Vault in resource group '$resource_group'..."
  
  local kv_name=$(az keyvault list --resource-group "$resource_group" \
    --query "[0].name" -o tsv 2>/dev/null)
  
  if [[ -n "$kv_name" ]]; then
    log "✅ Found Key Vault: $kv_name"
    echo "$kv_name"
    return 0
  fi
  
  log "❌ No Key Vault found in resource group '$resource_group'"
  return 1
}

# Ensure Azure CLI login
require_az_login() {
  require_dns || return 1
  
  # Check if already logged in
  if az account show -o none &>/dev/null; then
    log "✅ Already logged in to Azure"
    return 0
  fi
  
  # Try to login
  log "🔑 Logging in to Azure CLI..."
  if ! az login --output none; then
    log "❌ Azure login failed"
    return 1
  fi
  
  # Set the subscription if provided
  if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    log "✅ Set subscription to $AZURE_SUBSCRIPTION_ID"
  fi
  
  return 0
}

# Ensure service account issuer is set
require_service_account_issuer() {
  [[ -n "${SERVICE_ACCOUNT_ISSUER:-}" ]] && return 0
  
  local cluster_type=$(detect_cluster_type)
  
  if [[ "$cluster_type" == "kind" ]]; then
    # For KIND, get from Azure storage account
    [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]] || { log "❌ ERROR: AZURE_STORAGE_ACCOUNT is not set."; return 1; }
    [[ -n "${RESOURCE_GROUP:-}" ]] || { log "❌ ERROR: RESOURCE_GROUP is not set."; return 1; }
    
    SERVICE_ACCOUNT_ISSUER=$(az storage account show \
          -n "$AZURE_STORAGE_ACCOUNT" -g "$RESOURCE_GROUP" \
          --query "primaryEndpoints.web" -otsv 2>/dev/null)
    if [[ -z "$SERVICE_ACCOUNT_ISSUER" ]]; then
      log "❌ ERROR: Failed to retrieve service account issuer URL for storage account '$AZURE_STORAGE_ACCOUNT'."
      return 1
    fi
  fi
  # For AKS, SERVICE_ACCOUNT_ISSUER should already be in env file
  
  export SERVICE_ACCOUNT_ISSUER
  log "ℹ️ Service Account Issuer set to: ${SERVICE_ACCOUNT_ISSUER}"
}

# ──────────────────────── Cluster Connection Functions ────────────────────────────

# Ensure connected to cluster
ensure_cluster_connected() {
  local cluster_type=$(detect_cluster_type)
  
  log "ℹ️  Detected cluster type: $cluster_type"
  
  if [[ "$cluster_type" == "kind" ]]; then
    # KIND clusters are connected via kubeconfig already
    if ! $KUBECTL_CMD cluster-info &>/dev/null; then
      log "❌ Cannot connect to KIND cluster. Ensure cluster is created."
      return 1
    fi
    log "✅ Connected to KIND cluster"
  else
    # AKS clusters need credentials
    log "ℹ️  Attempting to get AKS credentials for cluster: ${CLUSTER_NAME:-unknown}"
    get_aks_credentials || return 1
  fi
  
  return 0
}

# Get AKS credentials
get_aks_credentials() {
  local cluster_name="${AKS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
  local resource_group="${AKS_RESOURCE_GROUP:-${RESOURCE_GROUP:-}}"
  
  # Skip if it looks like a KIND cluster name
  if [[ "$cluster_name" == "kind" ]] || [[ -z "$cluster_name" ]]; then
    log "❌ Invalid cluster name for AKS: $cluster_name"
    return 1
  fi
  
  if [[ -z "$resource_group" ]]; then
    log "❌ RESOURCE_GROUP must be set for AKS clusters"
    return 1
  fi
  
  log "📥 Getting AKS cluster credentials..."
  if ! az aks get-credentials --name "$cluster_name" --resource-group "$resource_group" --overwrite-existing; then
    log "❌ Failed to get AKS credentials"
    return 1
  fi
  
  log "✅ Successfully retrieved AKS credentials"
  return 0
}

# ──────────────────────── Workload Identity Functions ────────────────────────────

# Install or verify workload identity
setup_workload_identity() {
  local cluster_type=$(detect_cluster_type)
  
  if [[ "$cluster_type" == "kind" ]]; then
    install_workload_identity_webhook || return 1
  else
    verify_aks_workload_identity || return 1
  fi
  
  return 0
}

# Install Azure Workload Identity webhook (KIND only)
install_workload_identity_webhook() {
  log "📦 Installing Azure Workload-Identity webhook for KIND cluster"
  
  # Check cluster connectivity
  if ! $KUBECTL_CMD cluster-info &> /dev/null; then
    log "❌ Cannot connect to Kubernetes cluster. Check KUBECONFIG"
    return 1
  fi
  
  # Add helm repo
  helm repo add azure-workload-identity https://azure.github.io/azure-workload-identity/charts >/dev/null || true
  helm repo update >/dev/null
  
  # Install webhook
  if ! helm upgrade --install workload-identity-webhook azure-workload-identity/workload-identity-webhook \
      --namespace azure-workload-identity-system --create-namespace \
      --set "azureTenantID=${AZURE_TENANT_ID}" --wait; then
    log "❌ Failed to install Azure Workload Identity webhook"
    return 1
  fi
  
  log "✅ Azure Workload Identity webhook installed"
  return 0
}

# Verify AKS workload identity is enabled
verify_aks_workload_identity() {
  local cluster_name="${AKS_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
  local resource_group="${AKS_RESOURCE_GROUP:-${RESOURCE_GROUP:-}}"
  
  log "🔍 Verifying AKS Workload Identity configuration"
  
  OIDC_ENABLED=$(az aks show -n "$cluster_name" -g "$resource_group" --query "oidcIssuerProfile.enabled" -o tsv 2>/dev/null || echo "false")
  WI_ENABLED=$(az aks show -n "$cluster_name" -g "$resource_group" --query "securityProfile.workloadIdentity.enabled" -o tsv 2>/dev/null || echo "false")
  
  if [[ "$OIDC_ENABLED" == "true" ]] && [[ "$WI_ENABLED" == "true" ]]; then
    log "✅ Workload Identity is enabled on the AKS cluster"
  else
    log "❌ Workload Identity is not fully enabled on the cluster"
    log "Please enable it with: az aks update -n $cluster_name -g $resource_group --enable-oidc-issuer --enable-workload-identity"
    return 1
  fi
  
  return 0
}

# ──────────────────────── External Secrets Functions ────────────────────────────

# Install External Secrets Operator
install_external_secrets_operator() {
  local namespace="${ESO_NAMESPACE:-external-secrets}"
  
  log "📦 Installing External Secrets Operator into namespace '$namespace'"
  
  # Add helm repo
  helm repo add external-secrets https://charts.external-secrets.io >/dev/null || true
  helm repo update >/dev/null
  
  # Install ESO
  if ! helm upgrade --install external-secrets external-secrets/external-secrets \
       -n "$namespace" --create-namespace --wait; then
    log "❌ Failed to install External Secrets Operator"
    return 1
  fi
  
  log "✅ External Secrets Operator installed"
  
  # Annotate service account with workload identity for AKS clusters
  local cluster_type=$(detect_cluster_type)
  if [[ "$cluster_type" == "aks" ]]; then
    local app_id="${AZURE_CLIENT_ID:-${APP_ID}}"
    if [[ -n "$app_id" ]]; then
      log "🔧 Annotating External Secrets service account for workload identity"
      if $KUBECTL_CMD annotate serviceaccount external-secrets \
        -n "$namespace" \
        "azure.workload.identity/client-id=$app_id" \
        --overwrite; then
        log "✅ Service account annotated with client ID: $app_id"
        # Restart deployment to pick up the annotation
        $KUBECTL_CMD rollout restart deployment external-secrets -n "$namespace"
        $KUBECTL_CMD rollout status deployment external-secrets -n "$namespace"
      else
        log "⚠️  Failed to annotate service account (may already be configured)"
      fi
    fi
  fi
  
  return 0
}

# ──────────────────────── Service Account Functions ────────────────────────────

# Check if federated identity credential exists
# Returns 0 (success) if an identical FIC already exists, 1 otherwise
fic_exists() {
  local app_object_id="$1"   # objectId (not clientId) of the AAD app
  local issuer="$2"          # e.g. "$SERVICE_ACCOUNT_ISSUER"
  local subject="$3"         # e.g. "system:serviceaccount:${ns}:${sa}"
  az ad app federated-credential list \
       --id   "$app_object_id" \
       --query "[?issuer=='${issuer}' && subject=='${subject}']" \
       -o tsv 2>/dev/null | grep -q .
}

# Create service account with workload identity using azwi
create_eso_service_account() {
  local namespace="${ESO_NAMESPACE:-external-secrets}"
  local sa_name="${ESO_SA_NAME:-keyvault}"
  
  # Try to get app ID dynamically first
  local app_id=$(get_azure_app_id true 2>/dev/null)
  if [[ -z "$app_id" ]]; then
    # Fallback to environment variables
    app_id="${AZURE_CLIENT_ID:-${APP_ID}}"
    if [[ -z "$app_id" ]]; then
      log "❌ Could not determine Azure AD app ID"
      return 1
    fi
  fi
  
  # Get app name for azwi
  local app_name=$(az ad app show --id "$app_id" --query displayName -o tsv 2>/dev/null)
  if [[ -z "$app_name" ]]; then
    log "❌ Could not determine Azure AD app name"
    return 1
  fi
  
  # Try to get issuer dynamically
  local issuer=$(get_oidc_issuer_from_azure true 2>/dev/null)
  if [[ -z "$issuer" ]]; then
    # Fallback to environment variable
    issuer="${SERVICE_ACCOUNT_ISSUER}"
    if [[ -z "$issuer" ]]; then
      log "❌ Could not determine OIDC issuer URL"
      return 1
    fi
  fi
  
  log "🔧 Creating service account '$sa_name' in namespace '$namespace' using azwi"
  log "   App Name: $app_name"
  log "   App ID: $app_id"
  log "   Issuer: $issuer"
  
  # Create namespace if needed
  $KUBECTL_CMD create namespace "$namespace" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
  
  # Wait for namespace to be ready
  local max_attempts=10
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if $KUBECTL_CMD get namespace "$namespace" >/dev/null 2>&1; then
      log "✅ Namespace $namespace is ready"
      break
    fi
    log "⏳ Waiting for namespace $namespace to be ready (attempt $attempt/$max_attempts)..."
    sleep 1
    ((attempt++))
  done
  
  if [ $attempt -gt $max_attempts ]; then
    log "❌ Namespace $namespace failed to become ready"
    return 1
  fi
  
  # Use azwi to create service account with workload identity
  log "📦 Creating service account with azwi..."
  if ! azwi serviceaccount create phase service-account \
    --service-account-namespace "$namespace" \
    --service-account-name "$sa_name" \
    --aad-application-client-id "$app_id"; then
    log "❌ Failed to create service account with azwi"
    return 1
  fi
  
  # Check if federated credential already exists
  local app_object_id=$(az ad app show --id "$app_id" --query id -o tsv 2>/dev/null)
  if [[ -z "$app_object_id" ]]; then
    log "❌ Could not get Azure AD app object ID"
    return 1
  fi
  
  local subject="system:serviceaccount:${namespace}:${sa_name}"
  
  if fic_exists "$app_object_id" "$issuer" "$subject"; then
    log "✅ Federated credential already exists for ${subject} - skipping creation"
  else
    # Create federated credential with azwi
    log "🔑 Creating federated credential with azwi..."
    if ! azwi serviceaccount create phase federated-identity \
      --service-account-namespace "$namespace" \
      --service-account-name "$sa_name" \
      --aad-application-name "$app_name" \
      --service-account-issuer-url "$issuer"; then
      log "❌ Failed to create federated credential with azwi"
      return 1
    fi
  fi
  
  log "✅ Service account created and configured with azwi"
  return 0
}

# Create federated identity credential
create_federated_credential() {
  local namespace="$1"
  local sa_name="$2"
  
  # Try to get app ID dynamically first
  local app_id=$(get_azure_app_id true 2>/dev/null)
  if [[ -z "$app_id" ]]; then
    # Fallback to environment variables
    app_id="${AZURE_CLIENT_ID:-${APP_ID}}"
    if [[ -z "$app_id" ]]; then
      log "❌ Could not determine Azure AD app ID"
      return 1
    fi
  fi
  
  # Try to get issuer dynamically
  local issuer=$(get_oidc_issuer_from_azure true 2>/dev/null)
  if [[ -z "$issuer" ]]; then
    # Fallback to environment variable
    issuer="${SERVICE_ACCOUNT_ISSUER}"
    if [[ -z "$issuer" ]]; then
      log "❌ Could not determine OIDC issuer URL"
      return 1
    fi
  fi
  
  log "🔑 Creating federated credential for $namespace:$sa_name"
  log "   App ID: $app_id"
  log "   Issuer: $issuer"
  
  # Get app object ID
  local app_object_id=$(az ad app show --id "$app_id" --query id -o tsv)
  if [[ -z "$app_object_id" ]]; then
    log "❌ Could not get Azure AD app object ID"
    return 1
  fi
  
  # Create federated credential
  local fic_name="${namespace}-${sa_name}"
  local subject="system:serviceaccount:${namespace}:${sa_name}"
  
  # Check if credential already exists with the correct issuer
  local existing=$(az ad app federated-credential list --id "$app_object_id" \
    --query "[?subject=='${subject}' && issuer=='${issuer}'].name" -o tsv 2>/dev/null || echo "")
  
  if [[ -n "$existing" ]]; then
    log "ℹ️  Federated credential already exists with correct issuer: $existing"
    return 0
  fi
  
  # Check if credential exists with wrong issuer and delete it
  local wrong_issuer=$(az ad app federated-credential list --id "$app_object_id" \
    --query "[?subject=='${subject}' && issuer!='${issuer}'].name" -o tsv 2>/dev/null || echo "")
  
  if [[ -n "$wrong_issuer" ]]; then
    log "⚠️  Found federated credential with wrong issuer, deleting: $wrong_issuer"
    az ad app federated-credential delete --id "$app_object_id" \
      --federated-credential-id "$wrong_issuer" >/dev/null
  fi
  
  # Create the credential
  az ad app federated-credential create --id "$app_object_id" --parameters '{
    "name": "'$fic_name'",
    "issuer": "'$issuer'",
    "subject": "'$subject'",
    "audiences": ["api://AzureADTokenExchange"]
  }' >/dev/null
  
  log "✅ Federated credential created: $fic_name"
  return 0
}

# Reconcile all federated credentials to use correct issuer
reconcile_federated_credentials() {
  log "🔄 Reconciling federated credentials..."
  
  # Get app ID and issuer dynamically
  local app_id=$(get_azure_app_id true)
  if [[ -z "$app_id" ]]; then
    log "❌ Could not determine Azure AD app ID"
    return 1
  fi
  
  local current_issuer=$(get_oidc_issuer_from_azure true)
  if [[ -z "$current_issuer" ]]; then
    log "❌ Could not determine current OIDC issuer"
    return 1
  fi
  
  log "   App ID: $app_id"
  log "   Current issuer: $current_issuer"
  
  # Get app object ID
  local app_object_id=$(az ad app show --id "$app_id" --query id -o tsv)
  if [[ -z "$app_object_id" ]]; then
    log "❌ Could not get Azure AD app object ID"
    return 1
  fi
  
  # List all federated credentials
  local creds=$(az ad app federated-credential list --id "$app_object_id" -o json)
  
  # Process each credential
  echo "$creds" | jq -c '.[]' | while IFS= read -r cred; do
    local name=$(echo "$cred" | jq -r '.name')
    local issuer=$(echo "$cred" | jq -r '.issuer')
    local subject=$(echo "$cred" | jq -r '.subject')
    
    if [[ "$issuer" != "$current_issuer" ]]; then
      log "⚠️  Found credential with wrong issuer: $name"
      log "    Old issuer: $issuer"
      log "    Subject: $subject"
      
      # Delete old credential
      log "🗑️  Deleting old credential..."
      az ad app federated-credential delete --id "$app_object_id" \
        --federated-credential-id "$name" >/dev/null
      
      # Recreate with correct issuer
      log "➕ Creating new credential with correct issuer..."
      az ad app federated-credential create --id "$app_object_id" --parameters '{
        "name": "'$name'",
        "issuer": "'$current_issuer'",
        "subject": "'$subject'",
        "audiences": ["api://AzureADTokenExchange"]
      }' >/dev/null
      
      log "✅ Recreated credential: $name"
    else
      log "✅ Credential already has correct issuer: $name"
    fi
  done
  
  log "✅ Federated credentials reconciliation complete"
  return 0
}

# Setup workload identity for Key Vault access
setup_keyvault_workload_identity() {
  log "🔧 Setting up workload identity for Key Vault access"
  
  # Create external-secrets service account in external-secrets namespace
  # Note: We use the ESO default service account name to match the ClusterSecretStore configuration
  ESO_SA_NAME=external-secrets create_eso_service_account
  
  log "✅ Key Vault workload identity configured"
  return 0
}

# ──────────────────────── ArgoCD Functions ────────────────────────────

# Install ArgoCD
install_argocd() {
  local namespace="${ARGOCD_NAMESPACE:-argocd}"
  local version="${ARGOCD_VERSION:-stable}"
  
  log "📦 Installing ArgoCD in namespace '$namespace'"
  
  # Create namespace
  $KUBECTL_CMD create namespace "$namespace" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
  
  # Install ArgoCD
  if ! $KUBECTL_CMD apply -n "$namespace" -f "https://raw.githubusercontent.com/argoproj/argo-cd/$version/manifests/install.yaml"; then
    log "❌ Failed to install ArgoCD"
    return 1
  fi
  
  # Wait for ArgoCD to be ready
  log "⏳ Waiting for ArgoCD components..."
  $KUBECTL_CMD -n "$namespace" wait --for=condition=available --timeout=300s deployment/argocd-server || return 1
  $KUBECTL_CMD -n "$namespace" wait --for=condition=available --timeout=300s deployment/argocd-repo-server || return 1
  
  log "✅ ArgoCD installed successfully"
  return 0
}

# Configure ArgoCD
configure_argocd() {
  local namespace="${ARGOCD_NAMESPACE:-argocd}"
  
  log "🔧 Configuring ArgoCD..."
  
  # Enable insecure mode for development
  $KUBECTL_CMD -n "$namespace" patch configmap argocd-cm --type merge \
    -p '{"data":{"application.instanceLabelKey":"argocd.argoproj.io/instance"}}' || true
  
  $KUBECTL_CMD -n "$namespace" patch configmap argocd-cmd-params-cm --type merge \
    -p '{"data":{"server.insecure":"true"}}' || true
  
  # Restart ArgoCD server
  log "🔄 Restarting ArgoCD server..."
  $KUBECTL_CMD -n "$namespace" rollout restart deployment/argocd-server
  $KUBECTL_CMD -n "$namespace" rollout status deployment/argocd-server --timeout=180s
  
  log "✅ ArgoCD configured"
  return 0
}

# ──────────────────────── ACR Functions ────────────────────────────

# Ensure ACR pull role
ensure_acr_pull_role() {
  local app_id="${AZURE_CLIENT_ID:-${APP_ID}}"
  local acr_name="${ACR_NAME}"
  local acr_rg="${ACR_RG}"
  
  log "🔧 Ensuring ACR pull permissions for app $app_id"
  
  # Get ACR resource ID
  local acr_id=$(az acr show --name "$acr_name" --resource-group "$acr_rg" --query id -o tsv 2>/dev/null)
  if [[ -z "$acr_id" ]]; then
    log "❌ Could not find ACR: $acr_name"
    return 1
  fi
  
  # Check if role assignment exists
  local existing=$(az role assignment list --assignee "$app_id" --scope "$acr_id" --role AcrPull --query "[0].id" -o tsv 2>/dev/null || echo "")
  
  if [[ -n "$existing" ]]; then
    log "ℹ️  AcrPull role already assigned"
    return 0
  fi
  
  # Create role assignment
  if ! az role assignment create --assignee "$app_id" --scope "$acr_id" --role AcrPull >/dev/null; then
    log "❌ Failed to assign AcrPull role"
    return 1
  fi
  
  log "✅ AcrPull role assigned"
  return 0
}

# ──────────────────────── Key Vault Functions ────────────────────────────

# Resolve Key Vault name and ensure it exists
resolve_keyvault() {
  if [[ -n "${AZURE_KEYVAULT_NAME:-}" ]]; then
    log "ℹ️  Using Key Vault: $AZURE_KEYVAULT_NAME"
    return 0
  fi
  
  log "❌ AZURE_KEYVAULT_NAME not set in environment"
  return 1
}

# Ensure Key Vault access for the app
ensure_keyvault_access() {
  local app_id="${AZURE_CLIENT_ID:-${APP_ID}}"
  local keyvault_name="${AZURE_KEYVAULT_NAME}"
  
  log "🔧 Ensuring Key Vault access for app $app_id"
  
  # Get Key Vault resource ID
  local vault_id=$(az keyvault show --name "$keyvault_name" --query id -o tsv 2>/dev/null)
  if [[ -z "$vault_id" ]]; then
    log "❌ Could not find Key Vault: $keyvault_name"
    return 1
  fi
  
  # Check if role assignment exists
  local existing=$(az role assignment list --assignee "$app_id" --scope "$vault_id" --role "Key Vault Secrets User" --query "[0].id" -o tsv 2>/dev/null || echo "")
  
  if [[ -n "$existing" ]]; then
    log "✅ Key Vault Secrets User role already assigned"
    return 0
  fi
  
  # Create role assignment
  if ! az role assignment create --assignee "$app_id" --scope "$vault_id" --role "Key Vault Secrets User" >/dev/null; then
    log "❌ Failed to assign Key Vault Secrets User role"
    return 1
  fi
  
  log "✅ Granted Key Vault Secrets User role to app"
  return 0
}

# ──────────────────────── Export Functions ────────────────────────────

# Export common environment setup
export_env() {
  export AZURE_TENANT_ID="${AZURE_TENANT_ID}"
  export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
  export AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-${APP_ID}}"
  export APP_ID="${AZURE_CLIENT_ID:-${APP_ID}}"  # Backward compatibility
  export SERVICE_ACCOUNT_ISSUER="${SERVICE_ACCOUNT_ISSUER}"
  export CLUSTER_NAME="${CLUSTER_NAME:-${AKS_CLUSTER_NAME:-kind}}"
  export ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
  export ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
  export AZURE_KEYVAULT_NAME="${AZURE_KEYVAULT_NAME}"
  export ACR_NAME="${ACR_NAME}"
  export ACR_RG="${ACR_RG}"
  export RESOURCE_GROUP="${RESOURCE_GROUP}"
}

# ──────────────────────── Constants ────────────────────────────

# KIND specific constants
export KIND_IMAGE_VERSION="${KIND_IMAGE_VERSION:-v1.31.6}"
export KIND_IMAGE_SHA256="${KIND_IMAGE_SHA256:-28b7cbb993dfe093c76641a0c95807637213c9109b761f1d422c2400e22b8e87}"
export AZURE_STORAGE_CONTAINER='$web'

# Project paths
export SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT is one level up from scripts/
PROJECT_ROOT="$(dirname "${SCRIPT_PATH}")"
export PROJECT_ROOT