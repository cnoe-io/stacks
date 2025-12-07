# 'scripts/wi-kind-lib.sh'
#!/usr/bin/env bash
# ------------------------------------------------------------------
#  wi-kind-lib.sh – helper library (NO side-effects when sourced)
# ------------------------------------------------------------------
set -Eeuo pipefail
log() { printf '[%(%T)T] %s\n' -1 "$*"; }

# Use docker (default provider)

# ──────────────────────── tiny helpers ────────────────────────────
require_dns() {
  local h=${1:-login.microsoftonline.com}
  for _ in {1..30}; do getent hosts "$h" &>/dev/null && return; sleep 2; done
  log "❌  DNS lookup for $h failed"; return 1
}

require_az_login() {
  require_dns || return 1
  local sp_secret _trace_on
  [[ $- == *x* ]] && _trace_on=1 || _trace_on=0
  set +x
  for _ in {1..3}; do
    if az account show -o none &>/dev/null; then
      ((_trace_on)) && set -x || set +x; return 0
    fi
    if [[ -n "${SP_CLIENT_SECRET:-}" ]] && [[ -n "${SP_CLIENT_ID:-}" ]]; then
      log "🔑  No Azure session – logging in with service-principal credentials from env"
      AZURE_HTTP_USER_AGENT="wi-kind-bootstrap" \
      az login --service-principal --username "$SP_CLIENT_ID" --password "$SP_CLIENT_SECRET" --tenant "${AZURE_TENANT_ID:-0c4da9c5-40ea-4e7d-9c7a-e7308d4f8e38}" --output none --allow-no-subscriptions &>/dev/null && { ((_trace_on)) && set -x || set +x; return 0; }
    fi
    # Skip LastPass fallback - we're using 1Password or environment variables
    log "⏳ Azure login attempt $_ failed. Retrying in 3s..."
    sleep 3
  done
  if ! az account show -o none &>/dev/null; then
    ((_trace_on)) && set -x || set +x
    log "❌  Azure login failed after multiple attempts."; return 1
  fi
  ((_trace_on)) && set -x || set +x # Should not be reached if successful
  return 0 # Should be caught by the success condition above
}

require_service_account_issuer() {
  [[ -n "${SERVICE_ACCOUNT_ISSUER:-}" ]] && return 0
  [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]] || { log "❌ ERROR: AZURE_STORAGE_ACCOUNT is not set. Cannot get service account issuer."; return 1; }
  [[ -n "${RESOURCE_GROUP:-}" ]] || { log "❌ ERROR: RESOURCE_GROUP is not set. Cannot get service account issuer."; return 1; }
  SERVICE_ACCOUNT_ISSUER=$(az storage account show \
        -n "$AZURE_STORAGE_ACCOUNT" -g "$RESOURCE_GROUP" \
        --query "primaryEndpoints.web" -otsv 2>/dev/null)
  if [[ -z "$SERVICE_ACCOUNT_ISSUER" ]]; then
    log "❌ ERROR: Failed to retrieve service account issuer URL for storage account '$AZURE_STORAGE_ACCOUNT'."
    return 1
  fi
  export SERVICE_ACCOUNT_ISSUER # Export it for other scripts/subshells if needed
  log "ℹ️ Service Account Issuer set to: ${SERVICE_ACCOUNT_ISSUER}"
}

_require_dns()      { require_dns      "$@"; }
_require_az_login() { require_az_login "$@"; }

# ───────────────────────── constants & exports ──────────────────────────────
export SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# KIND node image version - upgraded to v1.31.6 to address DNS stability issues
# Previous: v1.29.14 (had intermittent DNS resolution problems)
# See: https://github.com/kubernetes-sigs/kind/releases for available versions
export KIND_IMAGE_VERSION="${KIND_IMAGE_VERSION:-v1.31.6}"
export KIND_IMAGE_SHA256="${KIND_IMAGE_SHA256:-28b7cbb993dfe093c76641a0c95807637213c9109b761f1d422c2400e22b8e87}"
export AZURE_STORAGE_CONTAINER='$web' # Note: single quotes prevent shell expansion if $web is also a var
# PROJECT_ROOT is one level up from scripts/
PROJECT_ROOT="$(dirname "${SCRIPT_PATH}")"

# vcluster configuration
export VCLUSTER_NAME="${VCLUSTER_NAME:-dev}"
export VCLUSTER_NAMESPACE="${VCLUSTER_NAMESPACE:-vcluster-${VCLUSTER_NAME}}"
export VCLUSTER_VERSION="${VCLUSTER_VERSION:-0.19.5}"

export WI_ENV="${PROJECT_ROOT}/.env-files/wi.env"
export DEPLOY_DIR="${DEPLOY_DIR:-${PROJECT_ROOT}/deployments}"
export KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-gitops}" # Default Kind cluster name
export APP_NAME="${APP_NAME:-gitops-app}"  # AAD App display name for Workload Identity

# Load wi.env if it exists to get AZURE_CLIENT_ID (previously APP_ID)
if [[ -f "$WI_ENV" ]]; then
  source <(grep -E '^(AZURE_CLIENT_ID|APP_ID|AZURE_STORAGE_ACCOUNT|AZURE_KEYVAULT_NAME|SERVICE_ACCOUNT_ISSUER|AZURE_SUBSCRIPTION_ID)=' "$WI_ENV" | sed 's/^/export /')
  # Handle legacy APP_ID variable
  if [[ -n "${APP_ID:-}" ]] && [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
    export AZURE_CLIENT_ID="$APP_ID"
  fi
fi

# Host ports exposed by the NGINX proxy (managed by kind-proxy.sh)
export ARGO_HTTP_PORT="${ARGO_HTTP_PORT:-30080}"
export ARGO_HTTPS_PORT="${ARGO_HTTPS_PORT:-30443}"
export GRAFANA_UI_PORT="${GRAFANA_UI_PORT:-30001}"
export GRAFANA_DOMAIN="${GRAFANA_DOMAIN:-grafana.localtest.me}"       # Domain for Grafana UI
export PROM_UI_PORT="${PROM_UI_PORT:-30002}"
export LOKI_HTTP_PORT="${LOKI_HTTP_PORT:-31000}"
export TEMPO_HTTP_PORT="${TEMPO_HTTP_PORT:-32000}"
export NEXTJS_DEV_HOST_PORT="${NEXTJS_DEV_HOST_PORT:-30100}"

# Host port for K8s API exposed by NGINX proxy
export K8S_API_PROXY_HOST_PORT="${K8S_API_PROXY_HOST_PORT:-6445}"

# Host port for vcluster API (port forwarding)
export VCLUSTER_PORT="${VCLUSTER_PORT:-8443}"
# ───── Argo Workflows ───────────────────────────────
export ARGO_WORKFLOWS_VERSION="${ARGO_WORKFLOWS_VERSION:-v3.6.5}"  # latest GA
export ARGO_WF_NODE_PORT="${ARGO_WF_NODE_PORT:-32746}"             # host.docker.internal:32746
export ARGO_WF_DOMAIN="${ARGO_WF_DOMAIN:-argo.localtest.me}"       # Domain for Argo Workflows UI



# Azure Service Principal Credentials - try to get from 1Password if not set
if command -v op &>/dev/null; then
  # Check if service account token is available (non-interactive mode)
  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
    log "🔑 Using 1Password service account for authentication..."
    
    # Try to fetch credentials using service account
    if [[ -z "${SP_CLIENT_ID:-}" ]]; then
      export SP_CLIENT_ID=$(op read op://Personal/SP_CLIENT_SECRET/username 2>/dev/null || echo "")
      if [[ -z "${SP_CLIENT_ID:-}" ]]; then
        log "⚠️  Could not find SP_CLIENT_ID in 1Password at op://Personal/SP_CLIENT_SECRET/username"
      else
        log "✅ Successfully retrieved SP_CLIENT_ID from 1Password"
      fi
    fi
    if [[ -z "${SP_CLIENT_SECRET:-}" ]]; then
      export SP_CLIENT_SECRET=$(op read op://Personal/SP_CLIENT_SECRET/password 2>/dev/null || echo "")
      if [[ -z "${SP_CLIENT_SECRET:-}" ]]; then
        log "⚠️  Could not find SP_CLIENT_SECRET in 1Password at op://Personal/SP_CLIENT_SECRET/password"
      else
        log "✅ Successfully retrieved SP_CLIENT_SECRET from 1Password"
      fi
    fi
  else
    # Interactive mode - check if user is logged into 1Password
    if ! op whoami &>/dev/null; then
      log "🔑 1Password CLI not logged in. Please login to access credentials..."
      if op signin; then
        log "✅ Successfully logged into 1Password"
      else
        log "❌ Failed to login to 1Password. Please set SP_CLIENT_ID and SP_CLIENT_SECRET manually:"
        log "   export SP_CLIENT_ID='your-service-principal-client-id'"
        log "   export SP_CLIENT_SECRET='your-service-principal-secret'"
      fi
    fi
    
    # Try to fetch credentials if logged in
    if op whoami &>/dev/null; then
      if [[ -z "${SP_CLIENT_ID:-}" ]]; then
        export SP_CLIENT_ID=$(op read op://Personal/SP_CLIENT_SECRET/username 2>/dev/null || echo "")
        if [[ -z "${SP_CLIENT_ID:-}" ]]; then
          log "⚠️  Could not find SP_CLIENT_ID in 1Password at op://Personal/SP_CLIENT_SECRET/username"
        fi
      fi
      if [[ -z "${SP_CLIENT_SECRET:-}" ]]; then
        export SP_CLIENT_SECRET=$(op read op://Personal/SP_CLIENT_SECRET/password 2>/dev/null || echo "")
        if [[ -z "${SP_CLIENT_SECRET:-}" ]]; then
          log "⚠️  Could not find SP_CLIENT_SECRET in 1Password at op://Personal/SP_CLIENT_SECRET/password"
        fi
      fi
    fi
  fi
else
  log "ℹ️  1Password CLI not installed. Please set SP_CLIENT_ID and SP_CLIENT_SECRET environment variables"
fi

# Set default values for common Azure variables
: "${AZURE_TENANT_ID:=0c4da9c5-40ea-4e7d-9c7a-e7308d4f8e38}"  # Default tenant from require_az_login
# Get current subscription from Azure CLI if not set from wi.env
if [[ -z "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  AZURE_SUBSCRIPTION_ID=$(az account show --query "id" -o tsv 2>/dev/null || echo "")
  if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]; then
    log "❌ ERROR: Could not determine Azure subscription ID. Please ensure you're logged in to Azure."
    exit 1
  fi
fi
: "${RESOURCE_GROUP:=rg3}"                                      # Default resource group
: "${LOCATION:=eastus}"                                          # Default location

# Validate required credentials
: "${SP_CLIENT_ID:?SP_CLIENT_ID (Azure Client ID) must be set}"
: "${SP_CLIENT_SECRET:?SP_CLIENT_SECRET (Azure Client Secret) must be set}"
: "${AZURE_TENANT_ID:?AZURE_TENANT_ID (Azure Tenant ID) must be set}"
: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID must be set}"
: "${RESOURCE_GROUP:?RESOURCE_GROUP (Azure Resource Group) must be set}"
: "${LOCATION:?LOCATION (Azure Location, e.g., eastus) must be set}"


# Defaults for installation namespaces/objects
: "${ESO_NS:=external-secrets}"
: "${SA_NAME:=keyvault}"                   # K8s SA name for ESO
: "${REGISTRY_NS:=nextjs}"                 # Namespace for ACR pull SA (as per logs: nextjs/acr-sa)
: "${REGISTRY_NAME:=acr-sa}"               # K8s SA name for ACR pull (as per logs: nextjs/acr-sa)
: "${TARGET_KV_ROLE:=Key Vault Secrets User}"

if [[ -f "$WI_ENV" ]]; then
  log "ℹ️ Loading persisted settings from $WI_ENV"
  # shellcheck source=/dev/null
  source <(grep -E '^(AZURE_STORAGE_ACCOUNT|AZURE_KEYVAULT_NAME|SERVICE_ACCOUNT_ISSUER|APP_ID|AZURE_CLIENT_ID|AZURE_SUBSCRIPTION_ID)=' "$WI_ENV" | sed 's/^/export /')
fi

# Handle legacy APP_ID variable
if [[ -n "${APP_ID:-}" ]] && [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
  export AZURE_CLIENT_ID="$APP_ID"
fi


# ────────────────── storage-account & OIDC functions ─────────────────────
_storage_oidc_valid() {
  [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]] && return 1
  
  # Check if storage account exists
  if ! az storage account show -n "${AZURE_STORAGE_ACCOUNT}" -g "${RESOURCE_GROUP}" &>/dev/null; then
    return 1
  fi
  
  # Check if static website is enabled (minimum requirement)
  if ! az storage blob service-properties show --account-name "${AZURE_STORAGE_ACCOUNT}" --auth-mode login --query "staticWebsite.enabled" -o tsv 2>/dev/null | grep -q true; then 
    return 1
  fi
  
  # We don't check for OIDC documents here as they may not exist yet
  # The storage account just needs to exist and have static website enabled
  return 0
}

save_azure_client_id() {
  # Save AZURE_CLIENT_ID (and maintain backward compatibility with APP_ID)
  local client_id="${AZURE_CLIENT_ID:-${APP_ID:-}}"
  [[ -z "$client_id" ]] && return 0          # nothing to save
  mkdir -p "$(dirname "$WI_ENV")"
  
  # Save as AZURE_CLIENT_ID
  if grep -q '^AZURE_CLIENT_ID=' "$WI_ENV" 2>/dev/null; then
    sed -i'.bak' "s|^AZURE_CLIENT_ID=.*|AZURE_CLIENT_ID=${client_id}|" "$WI_ENV"
  else
    echo "AZURE_CLIENT_ID=${client_id}" >> "$WI_ENV"
  fi
  
  # Update legacy APP_ID if it exists
  if grep -q '^APP_ID=' "$WI_ENV" 2>/dev/null; then
    sed -i'.bak' "s|^APP_ID=.*|APP_ID=${client_id}|" "$WI_ENV"
  fi
  
  rm -f "${WI_ENV}.bak" 2>/dev/null
}

# Backward compatibility alias
save_app_id() {
  save_azure_client_id "$@"
}


sanity_check_storage() {
  [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]] && { 
    log "ℹ️ No existing storage account reference found in environment"
    return 
  }
  
  log "🔍 Validating existing storage account reference: '$AZURE_STORAGE_ACCOUNT'"
  
  if ! _storage_oidc_valid; then
    log "⚠️  Stored account '$AZURE_STORAGE_ACCOUNT' is invalid or OIDC not properly configured"
    log "🧹 Cleaning up invalid storage account references from $WI_ENV"
    
    # Using sed -i'.bak' for macOS compatibility (GNU sed doesn't need .bak with -i if no extension given)
    sed -i'.bak' '/^AZURE_STORAGE_ACCOUNT=/d' "$WI_ENV" 2>/dev/null || true
    sed -i'.bak' '/^SERVICE_ACCOUNT_ISSUER=/d' "$WI_ENV" 2>/dev/null || true # Also clear issuer if storage changes
    rm -f "${WI_ENV}.bak" 2>/dev/null
    
    unset AZURE_STORAGE_ACCOUNT
    unset SERVICE_ACCOUNT_ISSUER
    
    log "✅ Invalid storage account references cleaned up"
  else
    log "✅ Existing storage account '$AZURE_STORAGE_ACCOUNT' is valid and properly configured"
  fi
}

STG_ARGS=()
[[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]] && STG_ARGS=( --account-name "$AZURE_STORAGE_ACCOUNT" --auth-mode login )

find_existing_oidc_storage_account() {
  log "🔍 Looking for existing OIDC storage accounts in resource group '${RESOURCE_GROUP}'..."
  
  # List all storage accounts with oidcissuer prefix in the resource group
  local accounts
  accounts=$(az storage account list -g "${RESOURCE_GROUP}" --query "[?starts_with(name, 'oidcissuer')].name" -o tsv 2>/dev/null || echo "")
  
  if [[ -z "$accounts" ]]; then
    log "ℹ️  No existing OIDC storage accounts found in resource group '${RESOURCE_GROUP}'"
    return 1
  fi
  
  # Check each account to see if it's valid for reuse
  local account
  for account in $accounts; do
    log "🔍 Checking storage account '$account'..."
    
    # Basic validation: account exists and static website is enabled
    if az storage account show -n "$account" -g "${RESOURCE_GROUP}" &>/dev/null; then
      if az storage blob service-properties show --account-name "$account" --auth-mode login --query "staticWebsite.enabled" -o tsv 2>/dev/null | grep -q true; then
        log "✅ Found valid existing OIDC storage account: '$account'"
        echo "$account"
        return 0
      else
        log "ℹ️  Storage account '$account' exists but static website not enabled"
      fi
    else
      log "⚠️  Storage account '$account' not accessible"
    fi
  done
  
  log "ℹ️  No suitable existing OIDC storage accounts found"
  return 1
}

ensure_blob_contrib() {
  # ... (implementation from previous correct version, ensure assignee-principal-type is robust) ...
  local me sp_appid principal_type
  if az account show --query user.type -o tsv 2>/dev/null | grep -q "user"; then
    me="$(az ad signed-in-user show --query id -o tsv)"
    principal_type="User"
  else
    sp_appid="$(az account show --query user.name -o tsv)" # This is client_id for SP
    me="$(az ad sp show --id "$sp_appid" --query id -o tsv 2>/dev/null)"
    principal_type="ServicePrincipal"
    if [[ -z "$me" ]]; then
        log "ℹ️ Could not find SP by id '$sp_appid', trying by display name if SP_CLIENT_ID was a name (less reliable)."
        me=$(az ad sp list --display-name "$SP_CLIENT_ID" --query "[0].id" -o tsv 2>/dev/null)
    fi
  fi
  [[ -n "$me" ]] || { log "❌ ERROR: Could not determine object ID for role assignment in ensure_blob_contrib."; return 1; }

  if az role assignment list --assignee "$me" --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?roleDefinitionName=='Storage Blob Data Contributor']" -o tsv 2>/dev/null | grep -q . ; then
    log "✅ Storage Blob Data Contributor role already assigned to '$me'."
    return 0
  fi
  log "🔑  Granting *Storage Blob Data Contributor* on RG '$RESOURCE_GROUP' to assignee '$me' (type '$principal_type')..."
  if ! az role assignment create --assignee-object-id "$me" --assignee-principal-type "$principal_type" --role 'Storage Blob Data Contributor' --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" -o none; then
     log "❌ ERROR: Failed to grant Storage Blob Data Contributor role to '$me'."
     return 1
  fi
  log "✅ Storage Blob Data Contributor role granted to '$me'."
}


create_azure_blob_storage_account() {
  log "🔧  Preparing Azure Storage in RG '${RESOURCE_GROUP}', Location '${LOCATION}'..."
  
  # First, check if any existing storage account reference is still valid
  sanity_check_storage
  
  # Ensure group exists
  az group show -n "$RESOURCE_GROUP" -o none 2>/dev/null || az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none

  # Check if a valid AZURE_STORAGE_ACCOUNT is already set (e.g., from wi.env)
  if [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
    log "ℹ️ AZURE_STORAGE_ACCOUNT is set to '${AZURE_STORAGE_ACCOUNT}'. Verifying its status..."
    if az storage account show -n "$AZURE_STORAGE_ACCOUNT" -g "$RESOURCE_GROUP" &>/dev/null; then
      log "✅ Using existing and valid Azure Storage Account: '$AZURE_STORAGE_ACCOUNT'."
      # Verify it's properly configured for OIDC
      if _storage_oidc_valid; then
        log "✅ Storage account '$AZURE_STORAGE_ACCOUNT' is properly configured for OIDC."
        # Skip to configuration steps
        STG_ARGS=( --account-name "$AZURE_STORAGE_ACCOUNT" --auth-mode login )
        ensure_blob_contrib || return 1
        log "✅ Azure Storage Account '$AZURE_STORAGE_ACCOUNT' is ready for use."
        return 0
      else
        log "⚠️ Storage account exists but OIDC configuration is invalid or incomplete."
        # Continue to reconfigure the existing account
      fi
    else
      log "⚠️ Storage account '${AZURE_STORAGE_ACCOUNT}' is not accessible or not found. Will attempt to create a new one."
      AZURE_STORAGE_ACCOUNT="" # Unset to force creation of a new one
    fi
  fi

  # If AZURE_STORAGE_ACCOUNT is not set or was invalid, try to find an existing one
  if [[ -z "${AZURE_STORAGE_ACCOUNT:-}" ]]; then
    # First, try to find an existing OIDC storage account
    if existing_account=$(find_existing_oidc_storage_account); then
      export AZURE_STORAGE_ACCOUNT="$existing_account"
      log "♻️  Reusing existing OIDC storage account: '$AZURE_STORAGE_ACCOUNT'"
      # The account exists and has static website enabled, we just need to ensure blob contrib role
      STG_ARGS=( --account-name "$AZURE_STORAGE_ACCOUNT" --auth-mode login )
      ensure_blob_contrib || return 1
      
      # Persist to wi.env
      if grep -q '^AZURE_STORAGE_ACCOUNT=' "$WI_ENV" 2>/dev/null; then
        sed -i'.bak' "s|^AZURE_STORAGE_ACCOUNT=.*|AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT}|" "$WI_ENV"
      else
        echo "AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT}" >> "$WI_ENV"
      fi
      rm -f "${WI_ENV}.bak" 2>/dev/null
      log "✅ AZURE_STORAGE_ACCOUNT='${AZURE_STORAGE_ACCOUNT}' persisted to '$WI_ENV'."
      return 0
    fi
    
    # No existing account found, create a new one
    log "ℹ️  No existing OIDC storage account found, creating a new one..."
    local candidate=""
    local created_successfully=false
    for i in {1..5}; do
      # Max length 24. "oidcissuer" is 10.
      # openssl rand -hex 6 => 12 random chars. Total 10 + 12 = 22 chars. (Valid)
      # openssl rand -hex 7 => 14 random chars. Total 10 + 14 = 24 chars. (Valid)
      candidate="oidcissuer$(openssl rand -hex 6)" # Generate new candidate name each iteration
      log "ℹ️ Attempting to use/create storage account: '$candidate' (attempt $i/5)"

      if az storage account check-name --name "$candidate" --query nameAvailable -o tsv 2>/dev/null | grep -q true; then
        log "✅ Storage account name '$candidate' is available. Creating..."
        # Attempt to create the storage account
        if az storage account create \
            -n "$candidate" \
            -g "$RESOURCE_GROUP" \
            -l "$LOCATION" \
            --kind StorageV2 \
            --sku Standard_LRS \
            --allow-blob-public-access true \
            --tags purpose=workload-identity-oidc cluster-type=kind \
            -o none; then
          export AZURE_STORAGE_ACCOUNT="$candidate" # Set the successfully created account name
          log "✅ Storage account '$AZURE_STORAGE_ACCOUNT' created successfully."
          created_successfully=true
          break # Exit loop on successful creation
        else
          log "⚠️ Failed to create storage account '$candidate' even though name was available. This might be a permission issue or a transient Azure problem."
        fi
      else
        log "ℹ️ Storage account name '$candidate' not available or 'check-name' command failed (possibly due to strict naming rules or transient error)."
      fi

      # If not successful and not the last attempt, sleep before retrying
      if ! $created_successfully && [[ $i -lt 5 ]]; then
        log "⏳ Retrying storage account creation in 3 seconds..."
        sleep 3
      fi
    done

    if ! $created_successfully; then
      log "❌ ERROR: Could not create a unique Azure Storage Account after 5 attempts."
      return 1
    fi
  fi

  # At this point, AZURE_STORAGE_ACCOUNT should be set to a valid, existing account name
  STG_ARGS=( --account-name "$AZURE_STORAGE_ACCOUNT" --auth-mode login )

  log "ℹ️ Configuring static website for storage account '$AZURE_STORAGE_ACCOUNT'..."
  if ! az storage blob service-properties update "${STG_ARGS[@]}" --static-website --index-document "index.html" --404-document "error.html" -o none; then
    log "❌ ERROR: Failed to enable static website properties for '$AZURE_STORAGE_ACCOUNT'."
    return 1
  fi

  log "ℹ️ Ensuring '$AZURE_STORAGE_CONTAINER' container exists and has public blob access..."
  # Attempt to create the container; ignore error if it already exists.
  az storage container create --name "$AZURE_STORAGE_CONTAINER" "${STG_ARGS[@]}" --public-access blob -o none 2>/dev/null || \
    log "ℹ️ Storage container '$AZURE_STORAGE_CONTAINER' likely already exists."

  # Verify container existence (optional, but good for diagnostics)
  if ! az storage container show --name "$AZURE_STORAGE_CONTAINER" "${STG_ARGS[@]}" -o none &>/dev/null; then
      log "⚠️ WARN: Storage container '$AZURE_STORAGE_CONTAINER' could not be verified after creation attempt. This might cause issues with OIDC document upload."
      # Depending on strictness, you might 'return 1' here.
  fi

  log "✅ Azure Storage Account '$AZURE_STORAGE_ACCOUNT' is configured for OIDC."

  ensure_blob_contrib || return 1 # This is a critical step

  # Persist AZURE_STORAGE_ACCOUNT to WI_ENV file
  if grep -q '^AZURE_STORAGE_ACCOUNT=' "$WI_ENV" 2>/dev/null; then
    # Use sed -i'.bak' for macOS compatibility (GNU sed -i without extension is fine)
    sed -i'.bak' "s|^AZURE_STORAGE_ACCOUNT=.*|AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT}|" "$WI_ENV"
  else
    echo "AZURE_STORAGE_ACCOUNT=${AZURE_STORAGE_ACCOUNT}" >> "$WI_ENV"
  fi
  rm -f "${WI_ENV}.bak" 2>/dev/null # Clean up .bak file if created
  log "✅ AZURE_STORAGE_ACCOUNT='${AZURE_STORAGE_ACCOUNT}' persisted to '$WI_ENV'."
  return 0
}

apply_template() {
  local tpl=$1 rendered
  rendered="${tpl%.tpl}"               # strip final “.tpl” for kubectl apply --dry-run
  if ! command -v envsubst >/dev/null 2>&1; then
    log "ℹ️  Installing gettext-base (envsubst) — not found in PATH"
    apt-get update -qq && apt-get install -y -qq gettext-base
  fi
  log "🖋️   Rendering template $tpl → (stdin)"
  envsubst <"$tpl" | kubectl apply -f -
}



SERVICE_ACCOUNT_ISSUER="" # Ensure it's reset or correctly scoped
upload_or_replace() {
  # ... (implementation from previous correct version) ...
  az storage blob upload "${STG_ARGS[@]}" -c "$AZURE_STORAGE_CONTAINER" -f "$1" -n "$2" --overwrite true --only-show-errors
}

save_issuer() {
  # ... (implementation from previous correct version) ...
  if grep -q '^SERVICE_ACCOUNT_ISSUER=' "$WI_ENV" 2>/dev/null; then
    sed -i'.bak' "s|^SERVICE_ACCOUNT_ISSUER=.*|SERVICE_ACCOUNT_ISSUER=${SERVICE_ACCOUNT_ISSUER}|" "$WI_ENV"
  else
    echo "SERVICE_ACCOUNT_ISSUER=${SERVICE_ACCOUNT_ISSUER}" >> "$WI_ENV"
  fi
  rm -f "${WI_ENV}.bak" 2>/dev/null
}

upload_openid_docs() {
  # ... (implementation from previous correct version, with error checks) ...
  [[ -n "${AZURE_STORAGE_ACCOUNT:-}" ]] || { log "❌ ERROR: AZURE_STORAGE_ACCOUNT not set for OIDC upload."; return 1; }
  SERVICE_ACCOUNT_ISSUER=$(az storage account show -n "$AZURE_STORAGE_ACCOUNT" -g "$RESOURCE_GROUP" -o json | jq -r '.primaryEndpoints.web')
  [[ -n "$SERVICE_ACCOUNT_ISSUER" ]] || { log "❌ ERROR: Failed to get SERVICE_ACCOUNT_ISSUER for OIDC docs."; return 1; }
  export SERVICE_ACCOUNT_ISSUER # Export for other functions/scripts
  save_issuer

  local openid_config_file="${SCRIPT_PATH}/openid-configuration.json"
  local jwks_file="${SCRIPT_PATH}/jwks.json"
  cat >"$openid_config_file" <<EOF
{
  "issuer": "${SERVICE_ACCOUNT_ISSUER}",
  "jwks_uri": "${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
EOF
  upload_or_replace "$openid_config_file" ".well-known/openid-configuration"
  log "ℹ️ Attempting to fetch JWKS from current cluster context via 'kubectl get --raw /openid/v1/jwks'..."
  
  # Check if we're in a vcluster context
  local current_context
  current_context=$(kubectl config current-context 2>/dev/null || echo "")
  if [[ "$current_context" == vcluster_* ]]; then
    log "ℹ️ Detected vcluster context: $current_context. Fetching JWKS from vcluster..."
  fi
  
  if kubectl get --raw /openid/v1/jwks 2>/dev/null | jq -c . >"$jwks_file"; then # Requires KUBECONFIG to be set and working
    log "✅ Fetched JWKS from Kubernetes API server (context: $current_context)."
  else
    log "⚠️ Could not fetch JWKS from cluster (API server might not be ready or OIDC feature not enabled/working). Creating empty JWKS set."
    echo '{ "keys": [] }' >"$jwks_file"
  fi
  upload_or_replace "$jwks_file" "openid/v1/jwks"
  log "✅ OpenID discovery documents uploaded to Azure Storage."
}

###############################################################################
# 5. Kind + proxy helpers
###############################################################################
create_kind_cluster() {
  require_service_account_issuer # Ensure SERVICE_ACCOUNT_ISSUER is set
  [[ -n "$SERVICE_ACCOUNT_ISSUER" ]] || { log "❌ ERROR: SERVICE_ACCOUNT_ISSUER is not set, cannot create Kind cluster."; return 1; }

  log "☸️  (Re)creating Kind cluster '$KIND_CLUSTER_NAME' with image 'kindest/node:${KIND_IMAGE_VERSION}'"
  kind delete cluster --name "$KIND_CLUSTER_NAME" &>/dev/null || true

  log "ℹ️  Kind cluster configuration details:"
  log "    Service Account Issuer for K8s API server: ${SERVICE_ACCOUNT_ISSUER}"
  log "    This will be the base cluster hosting vcluster '$VCLUSTER_NAME'"
  log "    NGINX proxy (managed by kind-proxy.sh) will handle ALL host port mappings for K8s API and applications."
  log "    K8s API server will be accessible on host port ${K8S_API_PROXY_HOST_PORT} (via NGINX proxy)."
  log "    ArgoCD HTTP will be accessible on host port ${ARGO_HTTP_PORT} (via NGINX proxy)."
  # Add more logs for other services if desired.

  # Check if we're in a devcontainer environment
  if [[ -n "${CODESPACES:-}" ]] || [[ -f "/.dockerenv" ]] || [[ -n "${REMOTE_CONTAINERS:-}" ]]; then
    # In devcontainer: Still need port mappings for NGINX ingress controller
    cat <<EOF | kind create cluster --name "$KIND_CLUSTER_NAME" --image "kindest/node:${KIND_IMAGE_VERSION}@sha256:${KIND_IMAGE_SHA256}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    # Port mappings for NGINX ingress controller (required for proxy to work)
    extraPortMappings:
    - containerPort: 30080
      hostPort: 30080
      protocol: TCP
    - containerPort: 30443
      hostPort: 30443
      protocol: TCP
    # Backstage NodePort
    - containerPort: 30007
      hostPort: 30007
      protocol: TCP
    # Backstage NodePort (new)
    - containerPort: 30009
      hostPort: 30009
      protocol: TCP
    # Headlamp NodePort
    - containerPort: 30003
      hostPort: 30003
      protocol: TCP
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            service-account-issuer: ${SERVICE_ACCOUNT_ISSUER}
          certSANs:
          - host.docker.internal
          - localhost
          - 127.0.0.1
EOF
  else
    # Direct port mappings when not in devcontainer
    cat <<EOF | kind create cluster --name "$KIND_CLUSTER_NAME" --image "kindest/node:${KIND_IMAGE_VERSION}@sha256:${KIND_IMAGE_SHA256}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
    - containerPort: 30080
      hostPort: 30080
      protocol: TCP
    - containerPort: 30443
      hostPort: 30443
      protocol: TCP
    # Backstage NodePort
    - containerPort: 30007
      hostPort: 30007
      protocol: TCP
    # Backstage NodePort (new)
    - containerPort: 30009
      hostPort: 30009
      protocol: TCP
    # Headlamp NodePort
    - containerPort: 30003
      hostPort: 30003
      protocol: TCP
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            service-account-issuer: ${SERVICE_ACCOUNT_ISSUER}
          certSANs:
          - host.docker.internal
          - localhost
          - 127.0.0.1
EOF
  fi
  log "✅ Kind cluster '$KIND_CLUSTER_NAME' creation initiated (will host vcluster '$VCLUSTER_NAME')."
}

###############################################################################
# 6. vcluster helpers
###############################################################################
create_vcluster() {
  log "🚀 Creating vcluster '$VCLUSTER_NAME' in namespace '$VCLUSTER_NAMESPACE'..."
  
  # Ensure we're connected to the base Kind cluster
  if ! kubectl cluster-info >/dev/null 2>&1; then
    log "❌ ERROR: Cannot connect to base Kind cluster. Ensure Kind cluster is running and kubeconfig is set."
    return 1
  fi
  
  # Check if vcluster already exists
  if vcluster list | grep -q "^${VCLUSTER_NAME}[[:space:]]"; then
    log "ℹ️ vcluster '$VCLUSTER_NAME' already exists. Checking if it's running..."
    if kubectl get namespace "$VCLUSTER_NAMESPACE" >/dev/null 2>&1 && \
       kubectl get statefulset -n "$VCLUSTER_NAMESPACE" "${VCLUSTER_NAME}" >/dev/null 2>&1; then
      log "✅ vcluster '$VCLUSTER_NAME' is already running"
    else
      log "⚠️ vcluster '$VCLUSTER_NAME' exists but may not be running. Attempting to start..."
      vcluster connect "$VCLUSTER_NAME" --namespace "$VCLUSTER_NAMESPACE" &
      sleep 5
      pkill -f "vcluster connect" 2>/dev/null || true
    fi
  else
    log "📦 Creating new vcluster '$VCLUSTER_NAME'..."
    if ! vcluster create "$VCLUSTER_NAME" \
        --namespace "$VCLUSTER_NAMESPACE" \
        --connect=false; then
      log "❌ ERROR: Failed to create vcluster '$VCLUSTER_NAME'"; return 1
    fi
    log "✅ vcluster '$VCLUSTER_NAME' created successfully"
  fi
  
  # Wait for vcluster to be ready
  log "⏳ Waiting for vcluster '$VCLUSTER_NAME' to be ready..."
  if ! kubectl wait --for=condition=ready pod -l app=vcluster \
       -n "$VCLUSTER_NAMESPACE" --timeout=300s; then
    log "❌ ERROR: vcluster '$VCLUSTER_NAME' did not become ready"; return 1
  fi
  
  # Update kubeconfig for vcluster
  setup_vcluster_kubeconfig || return 1
  
  log "✅ vcluster '$VCLUSTER_NAME' is ready and configured"
}

setup_vcluster_kubeconfig() {
  log "🔧 Setting up kubeconfig for vcluster '$VCLUSTER_NAME'..."
  local vcluster_kubeconfig="$HOME/.kube/config-vcluster"
  local vcluster_context="vcluster_${VCLUSTER_NAME}_${VCLUSTER_NAMESPACE}_kind-${KIND_CLUSTER_NAME}"
  
  # Get vcluster kubeconfig
  if ! vcluster connect "$VCLUSTER_NAME" \
      --namespace "$VCLUSTER_NAMESPACE" \
      --print > "$vcluster_kubeconfig"; then
    log "❌ ERROR: Failed to get vcluster kubeconfig"; return 1
  fi
  
  # Merge vcluster config into main kubeconfig
  local main_kubeconfig="$HOME/.kube/config"
  local backup_kubeconfig="${main_kubeconfig}.backup-$(date +%s)"
  
  log "📋 Backing up current kubeconfig to $backup_kubeconfig"
  cp "$main_kubeconfig" "$backup_kubeconfig"
  
  # Get the actual context name from the vcluster kubeconfig before merging
  local actual_context=$(kubectl --kubeconfig="$vcluster_kubeconfig" config current-context)
  
  log "🔀 Merging vcluster kubeconfig into main kubeconfig..."
  KUBECONFIG="$main_kubeconfig:$vcluster_kubeconfig" kubectl config view --flatten > "${main_kubeconfig}.tmp"
  mv "${main_kubeconfig}.tmp" "$main_kubeconfig"
  rm -f "$vcluster_kubeconfig"
  
  # Set vcluster as current context
  if ! kubectl config use-context "$actual_context"; then
    log "❌ ERROR: Failed to switch to vcluster context '$actual_context'"; return 1
  fi
  
  # Set up manual port forwarding for consistent port usage
  log "🔌 Setting up port forwarding for vcluster..."
  local vcluster_port="${VCLUSTER_PORT:-8443}"
  
  # Kill any existing port forwards
  pkill -f "kubectl port-forward.*$VCLUSTER_NAMESPACE" 2>/dev/null || true
  sleep 2
  
  # Start port forwarding in background with nohup to survive script exit
  nohup kubectl port-forward -n "$VCLUSTER_NAMESPACE" svc/"$VCLUSTER_NAME" "$vcluster_port":443 >/dev/null 2>&1 &
  local pf_pid=$!
  echo $pf_pid > "/tmp/vcluster-port-forward-${VCLUSTER_NAME}.pid"
  sleep 5
  
  # Update kubeconfig to use the correct port
  kubectl config set-cluster "vcluster_${VCLUSTER_NAME}_${VCLUSTER_NAMESPACE}_kind-rg4" --server="https://127.0.0.1:${vcluster_port}"
  
  log "ℹ️ vcluster port forwarding running on localhost:${vcluster_port}"
  
  # Note: Port forwarding connection will be established by vcluster-connect target
  log "✅ Vcluster kubeconfig setup complete. Use 'make vcluster-connect' to establish port forwarding."
  
  # Export the vcluster context for use by subsequent functions
  export VCLUSTER_CONTEXT="$vcluster_context"
  export KUBECONFIG="$main_kubeconfig"
  
  log "✅ vcluster kubeconfig configured. Current context: $vcluster_context"
  log "ℹ️ All subsequent operations will target the vcluster"
}

# Source kind-proxy.sh which contains launch_kind_api_proxy and patch_kubeconfigs
# This needs to be after port variables are defined and exported.
# shellcheck source=./kind-proxy.sh
# NOTE: Commented out as proxy functionality is now handled by setup-nginx-proxy.sh
# source "${SCRIPT_PATH}/kind-proxy.sh"

# Stub function to prevent errors - actual proxy setup is handled by setup-nginx-proxy.sh
launch_kind_api_proxy() {
  log "ℹ️  Proxy setup is handled by setup-nginx-proxy.sh, skipping legacy launch_kind_api_proxy"
  return 0
}

retry_proxy() {
  # Check if we're in a devcontainer environment
  if [[ -n "${CODESPACES:-}" ]] || [[ -f "/.dockerenv" ]] || [[ -n "${REMOTE_CONTAINERS:-}" ]]; then
    log "🔌  Detected devcontainer environment. Attempting to launch Kind NGINX proxy..."
    log "ℹ️  NGINX proxy should expose K8s API on host port: ${K8S_API_PROXY_HOST_PORT}"
    log "ℹ️  NGINX proxy should expose ArgoCD on host port: ${ARGO_HTTP_PORT}"

    if launch_kind_api_proxy; then # launch_kind_api_proxy should return 0 on success
      log "✅ Kind NGINX proxy launched successfully."
      return 0
    else
      log "❌ ERROR: Kind NGINX proxy failed to launch. Check detailed logs from kind-proxy.sh and Docker daemon."
      return 1
    fi
  else
    log "ℹ️  Running outside devcontainer - skipping NGINX proxy setup."
    log "ℹ️  Services will be accessible via kubectl port-forward or NodePort services."
    return 0
  fi
}

# ... (Rest of the functions: install_workload_identity_webhook, radius, eso, argocd, headlamp etc.)
# Ensure they use the correct variables (ARGO_HTTP_PORT for NGINX proxied access)
# and that APP_ID (Client ID of AAD App for WI) is correctly set and used.
# Add error checks (if ! command; then return 1; fi) to critical steps.

install_workload_identity_webhook() {
  log "📦  Installing Azure Workload-Identity webhook"
  # Helm commands require KUBECONFIG to be correctly set and pointing to a reachable cluster
  if ! kubectl cluster-info &> /dev/null; then # Pre-check connectivity
      log "❌ ERROR: Cannot connect to Kubernetes cluster. Check KUBECONFIG and API server proxy."
      return 1
  fi
  helm repo add azure-workload-identity https://azure.github.io/azure-workload-identity/charts >/dev/null || true
  helm repo update >/dev/null
  if ! helm upgrade --install workload-identity-webhook azure-workload-identity/workload-identity-webhook \
      --namespace azure-workload-identity-system --create-namespace \
      --set "azureTenantID=${AZURE_TENANT_ID}" --wait; then # Use AZURE_TENANT_ID var
      log "❌ ERROR: Failed to install Azure Workload Identity webhook."
      # Provide more Helm debug info if possible
      # helm status workload-identity-webhook -n azure-workload-identity-system
      # kubectl get pods -n azure-workload-identity-system
      return 1
  fi
  log "✅ Azure Workload Identity webhook installed."
}

# RADIUS FUNCTIONS DISABLED - No longer needed
# ensure_radius_app_registration() {
#   require_service_account_issuer || return 1
#   log "ℹ️ Checking AAD App '$APP_NAME' for Radius..."
#   local existing_app_id object_id issuer
#   existing_app_id=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv 2>/dev/null) || true
#   if [[ -z "$existing_app_id" ]]; then
#     log "ℹ️  AAD App '$APP_NAME' for Radius/WI not found. It should be created by 'rad-identity.sh' or 'azwi'."
#     return 0
#   fi
#   object_id=$(az ad app show --id "$existing_app_id" --query id -o tsv 2>/dev/null)
#   if [[ -z "$object_id" ]]; then
#     log "⚠️ WARN: Could not get object ID for existing AAD App '$APP_NAME' (App ID: $existing_app_id)."; return 0;
#   fi
#   # Check a common Radius FIC subject. This is a heuristic.
#   issuer=$(az ad app federated-credential list --id "$object_id" --query "[?subject=='system:serviceaccount:radius-system:controller'].issuer" -o tsv 2>/dev/null || echo "")
#   if [[ -n "$issuer" && "$issuer" != "$SERVICE_ACCOUNT_ISSUER" ]]; then
#     log "⚠️  AAD App '$APP_NAME' federated credential issuer ('$issuer') MISMATCHES expected SA Issuer ('$SERVICE_ACCOUNT_ISSUER')."
#   elif [[ -n "$issuer" ]]; then
#     log "✅  AAD App '$APP_NAME' federated credential issuer matches SA Issuer."
#   else
#     log "ℹ️  No specific FIC found for 'system:serviceaccount:radius-system:controller' on app '$APP_NAME', or issuer could not be determined."
#   fi
# }

# run_rad_identity() {
#   require_service_account_issuer || return 1
#   local sub; sub=$(az account show --query id -o tsv)
#   log "🏃 Running rad-identity.sh to create/update AAD app '$APP_NAME' and FICs..."
#   if ! "${SCRIPT_PATH}/rad-identity.sh" \
#       "$KIND_CLUSTER_NAME" "$RESOURCE_GROUP" "$sub" "$SERVICE_ACCOUNT_ISSUER"; then
#       log "❌ ERROR: rad-identity.sh script failed."; return 1
#   fi
#   # After rad-identity, refresh the global APP_ID (Client ID of $APP_NAME)
#   refresh_app_id || return 1 # This sets global APP_ID
#   save_app_id             
#   log "✅ rad-identity.sh executed. Global APP_ID for '$APP_NAME' is now '${APP_ID:-Not Set}'."
# }

# install_radius() {
#   log "📦  Installing Radius control-plane..."
#   # APP_ID (Client ID of AAD app $APP_NAME) should be set by run_rad_identity via refresh_app_id
#   [[ -n "${APP_ID:-}" ]] || { log "❌ ERROR: APP_ID (Client ID for Radius WI) not set before installing Radius."; return 1; }
#
#   local CTX="kind-${KIND_CLUSTER_NAME}"
#   rm -f "$HOME/.rad/config.yaml" 2>/dev/null || true
#   if ! rad install kubernetes --set global.azureWorkloadIdentity.enabled=true \
#                          --set rp.publicEndpointOverride=localhost:8080; then # This 8080 is internal for Radius
#       log "❌ ERROR: 'rad install kubernetes' failed."; return 1
#   fi
#   for d in applications-rp bicep-de controller ucp; do
#     if ! kubectl --context "$CTX" -n radius-system rollout status deployment/"$d" --timeout=360s; then # Increased timeout
#         log "❌ ERROR: Radius deployment '$d' did not become ready."; return 1
#     fi
#   done
#   log "✅ Radius K8s components installed."
#   log "⚙️  Configuring Radius workspace and credentials..."
#   rad group create local >/dev/null 2>&1 || log "ℹ️ Radius group 'local' may already exist."
#   sleep 1
#   rad env create local --group local >/dev/null 2>&1 || log "ℹ️ Radius env 'local' may already exist."
#   rad workspace create kubernetes --context "$CTX" --group local --environment local >/dev/null 2>&1 || log "ℹ️ Radius workspace for context '$CTX' may already exist."
#   rad env update local --group local --azure-subscription-id "$AZURE_SUBSCRIPTION_ID" \
#         --azure-resource-group "$RESOURCE_GROUP" --workspace "$CTX"
#   if ! rad credential register azure wi --client-id "$APP_ID" --tenant-id "$TENANT_ID" --workspace "$CTX"; then # Uses global APP_ID
#       log "❌ ERROR: 'rad credential register azure wi' failed for client ID '$APP_ID'."; return 1
#   fi
#   log "✅ Radius installed and configured with Workload Identity (Client ID: $APP_ID)."
# }

first_kid() { jq -r '.keys[0].kid // ""' <<<"$1"; }
ensure_cluster_oidc_matches_storage() {
  # ... (implementation from previous correct version with error returns) ...
  require_service_account_issuer || return 1
  local cluster_issuer storage_issuer cluster_jwks storage_jwks current_context
  
  current_context=$(kubectl config current-context 2>/dev/null || echo "")
  log "ℹ️ Verifying OIDC settings for context: $current_context"
  
  cluster_issuer=$(kubectl get --raw /.well-known/openid-configuration 2>/dev/null | jq -r '.issuer // empty')
  [[ -n "$cluster_issuer" ]] || { log "❌ ERROR: Cluster did not expose OIDC discovery document."; return 1; }
  storage_issuer=$(curl -fsSL "${SERVICE_ACCOUNT_ISSUER}.well-known/openid-configuration" | jq -r .issuer)
  [[ -n "$storage_issuer" ]] || { log "❌ ERROR: Could not fetch OIDC discovery from storage issuer '${SERVICE_ACCOUNT_ISSUER}'."; return 1; }
  log "› cluster_issuer : $cluster_issuer"; log "› storage_issuer : $storage_issuer"
  [[ "$cluster_issuer" == "$SERVICE_ACCOUNT_ISSUER" && "$storage_issuer" == "$SERVICE_ACCOUNT_ISSUER" ]] || {
    log "❌ ERROR: Issuer mismatch. Cluster: '$cluster_issuer', Storage: '$storage_issuer', Expected: '$SERVICE_ACCOUNT_ISSUER'"; return 1; }
  cluster_jwks=$(kubectl get --raw /openid/v1/jwks | jq -cS .)
  storage_jwks=$(curl -fsSL "${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks" | jq -cS .)
  if [[ "$(first_kid "$cluster_jwks")" == "" || "$(first_kid "$storage_jwks")" == "" ]]; then
      log "⚠️ WARN: One or both JWKS URIs returned empty keys. This WILL cause WI to fail if not resolved."
      # Consider this a fatal error if WI is critical path immediately after this
      # For now, it's a warning.
  fi
  log "› cluster_kid   : $(first_kid "$cluster_jwks")"; log "› storage_kid   : $(first_kid "$storage_jwks")"
  [[ "$cluster_jwks" == "$storage_jwks" ]] || { log "❌ ERROR: JWKS mismatch between cluster and storage.";
    log "Cluster JWKS: $cluster_jwks"; log "Storage JWKS: $storage_jwks"; return 1; }
  log "🔒  Cluster OIDC settings verified against storage (issuer & keys match) for context: $current_context"
}

resolve_keyvault() {
  local loaded_kv_name=""
  local discovered_kv_name=""
  export AZURE_KEYVAULT_NAME="" # Ensure it's reset before attempting to resolve

  # 1. Try to load AZURE_KEYVAULT_NAME from WI_ENV first
  if [[ -f "$WI_ENV" ]] && grep -q '^AZURE_KEYVAULT_NAME=' "$WI_ENV"; then
    loaded_kv_name=$(grep '^AZURE_KEYVAULT_NAME=' "$WI_ENV" | cut -d'=' -f2 | tr -d '"' | tr -d "'") # Remove potential quotes
    if [[ -n "$loaded_kv_name" ]]; then
      log "ℹ️ Found AZURE_KEYVAULT_NAME='${loaded_kv_name}' in '$WI_ENV'. Verifying its existence in RG '$RESOURCE_GROUP'..."
      if az keyvault show --name "$loaded_kv_name" --query id -o tsv &>/dev/null; then
        log "✅ Verified existing Key Vault '$loaded_kv_name' from '$WI_ENV'."
        export AZURE_KEYVAULT_NAME="$loaded_kv_name"
      else
        log "⚠️ Key Vault '$loaded_kv_name' (from '$WI_ENV') not found or inaccessible in RG '$RESOURCE_GROUP'. Will attempt discovery."
        # AZURE_KEYVAULT_NAME remains empty, triggering discovery
      fi
    fi
  fi

  # 2. If AZURE_KEYVAULT_NAME is still not set (not in wi.env, or the one from wi.env was invalid/not found)
  if [[ -z "${AZURE_KEYVAULT_NAME:-}" ]]; then
    log "ℹ️ AZURE_KEYVAULT_NAME not resolved from '$WI_ENV' or was invalid. Attempting to discover a Key Vault in resource group '$RESOURCE_GROUP'..."
    # Discover the first Key Vault in the resource group
    discovered_kv_name=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null || true) # Suppress error if no KV found
    if [[ -n "$discovered_kv_name" ]]; then
        log "✅ Discovered Key Vault: '$discovered_kv_name' in RG '$RESOURCE_GROUP'."
        export AZURE_KEYVAULT_NAME="$discovered_kv_name"
    else
        log "❌ ERROR: No Key Vault name was provided, any value from '$WI_ENV' was invalid/not found, and no Key Vaults were discovered in RG '$RESOURCE_GROUP'."
        log "           Please ensure a Key Vault exists in '$RESOURCE_GROUP' and is accessible, or set a correct AZURE_KEYVAULT_NAME environment variable/`wi.env` entry."
        return 1
    fi
  fi

  # 3. At this point, AZURE_KEYVAULT_NAME should be set to a valid, existing Key Vault. Fetch its details.
  log "ℹ️ Using Key Vault Name: '$AZURE_KEYVAULT_NAME'. Fetching its ID and URL..."
  # Use a temporary variable for VAULT_ID to check before exporting
  local temp_vault_id
  temp_vault_id=$(az keyvault show --name "$AZURE_KEYVAULT_NAME" --query id -o tsv 2>/dev/null)

  if [[ -z "$temp_vault_id" ]]; then
    log "❌ ERROR: Could not retrieve details (VAULT_ID) for the resolved Key Vault '$AZURE_KEYVAULT_NAME'"
    log "           This can happen if the Key Vault was just deleted or if there are permission issues."
    return 1
  fi
  export VAULT_ID="$temp_vault_id"
  export VAULT_URL="https://${AZURE_KEYVAULT_NAME}.vault.azure.net"

  # 4. Persist the successfully used/validated AZURE_KEYVAULT_NAME to wi.env
  log "ℹ️ Persisting successfully resolved AZURE_KEYVAULT_NAME='${AZURE_KEYVAULT_NAME}' to '$WI_ENV'..."
  # Create WI_ENV directory if it doesn't exist (though it should)
  mkdir -p "$(dirname "$WI_ENV")"
  # Remove existing AZURE_KEYVAULT_NAME line first, then add the new one to ensure it's clean.
  if [[ -f "$WI_ENV" ]]; then
    sed -i'.bak' '/^AZURE_KEYVAULT_NAME=/d' "$WI_ENV" # Delete old entry
    rm -f "${WI_ENV}.bak" 2>/dev/null
  fi
  echo "AZURE_KEYVAULT_NAME=${AZURE_KEYVAULT_NAME}" >> "$WI_ENV" # Add/update with the verified name
  log "✅ Key Vault resolved and persisted: Name='${AZURE_KEYVAULT_NAME}', URL='${VAULT_URL}', ID='${VAULT_ID}'"
  return 0


}

install_external_secrets_operator() {
  # ... (implementation from previous correct version with error returns) ...
  log "📦  Installing External Secrets Operator (ESO) into namespace '$ESO_NS'"
  helm repo add external-secrets https://charts.external-secrets.io >/dev/null || true
  helm repo update >/dev/null
  if ! helm upgrade --install external-secrets external-secrets/external-secrets \
       -n "$ESO_NS" --create-namespace --wait; then
       log "❌ ERROR: Failed to install External Secrets Operator."; return 1
  fi
  log "✅ External Secrets Operator installed."
}

# Hard-limit guard (20 FICs max per app)
has_fic_slot () {
  local obj_id=$1  
  local used total
  used=$(az ad app federated-credential list --id "$obj_id" --query 'length(@)')
  [[ -z "$used" ]] && used=0
  total=20
  (( used < total ))
}


# Returns 0 (success) if an identical FIC already exists, 1 otherwise.
# Returns 0 (success) **iff** an identical FIC already exists, 1 otherwise
fic_exists () {
  local app_object_id="$1"   # ⟵ objectId (not clientId) of the AAD app
  local issuer="$2"          # e.g. "$SERVICE_ACCOUNT_ISSUER"
  local subject="$3"         # e.g. "system:serviceaccount:${ns}:${sa}"

  az ad app federated-credential list \
       --id   "$app_object_id" \
       --query "[?issuer=='${issuer}' && subject=='${subject}']" \
       -o tsv 2>/dev/null | grep -q .
}



# Global APP_ID (Client ID of AAD App $APP_NAME) is set by refresh_app_id (called from run_rad_identity)
# or directly if rad-identity is not run and app exists.
# It's crucial for create_eso_service_account, render_infra_secrets, apply_deployments, ensure_acr_pull_role.
export APP_ID="" # Initialize global APP_ID, will be set by refresh_app_id or create_eso_service_account if app exists.

create_eso_service_account () {
  require_service_account_issuer || return 1
  local app_object_id subject current_app_id sp_object_id existing_assignment

  app_object_id="$(az ad app list --display-name "$APP_NAME" \
                                   --query '[0].id' -o tsv 2>/dev/null)"

  # 0) Check and create Azure FIC if needed
  subject="system:serviceaccount:${ESO_NS}:${SA_NAME}"
  if [[ -n "$app_object_id" ]] && fic_exists "$app_object_id" \
                                      "$SERVICE_ACCOUNT_ISSUER" "$subject"; then
      log "✅  FIC already present for ${subject} in Azure – skipping Azure FIC creation."
  else
      log "🔐  Creating federated identity credential in Azure..."
      azwi serviceaccount create phase federated-identity \
           --aad-application-name      "$APP_NAME" \
           --service-account-namespace "$ESO_NS" \
           --service-account-name      "$SA_NAME" \
           --service-account-issuer-url "$SERVICE_ACCOUNT_ISSUER" \
           --subscription-id           "$SUBSCRIPTION_ID"
  fi

  # 1) Always create the Kubernetes ServiceAccount (it's cluster-specific)
  log "🔐  Creating ServiceAccount in Kubernetes cluster..."
  azwi serviceaccount create phase sa \
       --aad-application-name "$APP_NAME" \
       --service-account-namespace "$ESO_NS" \
       --service-account-name "$SA_NAME" \
       --subscription-id "$AZURE_SUBSCRIPTION_ID"

  ###########################################################################
  # 2) OPTIONAL – ACR pull SA (skip if variables not set)
  ###########################################################################
  if [[ -n "$REGISTRY_NS" && -n "$REGISTRY_NAME" ]]; then
      kubectl get ns "$REGISTRY_NS" >/dev/null 2>&1 || kubectl create ns "$REGISTRY_NS"

      subject="system:serviceaccount:${REGISTRY_NS}:${REGISTRY_NAME}"
      if [[ -n "$app_object_id" ]] && fic_exists "$app_object_id" \
                                          "$SERVICE_ACCOUNT_ISSUER" "$subject"; then
          log "✅  FIC already present for ${subject} in Azure – skipping Azure FIC creation."
      else
          log "🔐  Creating federated identity credential in Azure for ACR..."
          azwi serviceaccount create phase federated-identity \
               --aad-application-name "$APP_NAME" \
               --service-account-namespace "$REGISTRY_NS" \
               --service-account-name "$REGISTRY_NAME" \
               --service-account-issuer-url "$SERVICE_ACCOUNT_ISSUER" \
               --subscription-id "$AZURE_SUBSCRIPTION_ID"
      fi

      # Always create the Kubernetes ServiceAccount (it's cluster-specific)
      log "🔐  Creating ACR ServiceAccount in Kubernetes cluster..."
      azwi serviceaccount create phase sa \
           --aad-application-name "$APP_NAME" \
           --service-account-namespace "$REGISTRY_NS" \
           --service-account-name "$REGISTRY_NAME" \
           --subscription-id "$AZURE_SUBSCRIPTION_ID"
  fi

  ###########################################################################
  # 3) Resolve App ID & Service-Principal Object ID
  ###########################################################################
  current_app_id="$(az ad app show --id "$app_object_id" --query appId -o tsv)"
  [[ -n "$current_app_id" ]] || { log "❌  App ID for '$APP_NAME' not found"; return 1; }

  for i in {1..5}; do
      sp_object_id="$(az ad sp show --id "$current_app_id" --query id -o tsv 2>/dev/null)" && break
      log "⏳  SP lookup retry $i/5"; sleep 10
  done
  [[ -n "$sp_object_id" ]] || { log "❌  SP for App ID '$current_app_id' not found"; return 1; }

  ###########################################################################
  # 4)  Ensure the SP has **Key Vault Secrets User** on the vault
  ###########################################################################
  existing_assignment="$(az role assignment list \
        --assignee "$sp_object_id" --role "$TARGET_KV_ROLE" --scope "$VAULT_ID" \
        --query '[0].id' -o tsv 2>/dev/null)"

  if [[ -z "$existing_assignment" ]]; then
      log "🔐  Granting '$TARGET_KV_ROLE' to SP '$sp_object_id' on Key Vault…"
      az role assignment create --assignee "$sp_object_id" \
          --role "$TARGET_KV_ROLE" --scope "$VAULT_ID" --output none
  else
      log "✅  SP already has '$TARGET_KV_ROLE' on Key Vault"
  fi

  export APP_ID="$current_app_id"   # keep global var in sync

  ###########################################################################
  # 5)  Patch / create the ACR pull SA manifest (idempotent apply)
  ###########################################################################
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${REGISTRY_NAME}
  namespace: ${REGISTRY_NS}
  labels:
    azure.workload.identity/use: "true"
  annotations:
    azure.workload.identity/client-id: ${APP_ID}
    azure.workload.identity/tenant-id: ${AZURE_TENANT_ID}
EOF
  
  # Also ensure the keyvault service account has proper labels
  kubectl label sa -n "${ESO_NS}" "${SA_NAME}" azure.workload.identity/use=true --overwrite || true
  kubectl annotate sa -n "${ESO_NS}" "${SA_NAME}" azure.workload.identity/client-id="${APP_ID}" --overwrite || true
  kubectl annotate sa -n "${ESO_NS}" "${SA_NAME}" azure.workload.identity/tenant-id="${AZURE_TENANT_ID}" --overwrite || true
  log "✅  ESO + ACR ServiceAccounts wired to AAD app '$APP_NAME' (Client ID: $APP_ID)"
  save_app_id
}


render_infra_secrets() {
  resolve_keyvault || return 1
  [[ -n "${VAULT_URL:-}" ]] || { 
      log "❌  VAULT_URL not set — run resolve_keyvault first"; return 1; }

  # (optionally) be equally strict about APP_ID
  [[ -z "${APP_ID:-}" ]] && refresh_app_id
  [[ -n "${APP_ID:-}" ]] || { log "❌  APP_ID not set"; return 1; }

  # ▲ make sure every template variable is exported
  export APP_ID AZURE_TENANT_ID ESO_NS REGISTRY_NAME REGISTRY_NS VAULT_URL VAULT_ID SA_NAME

  log "✏️  Rendering ESO / ACR templates → resources/infra-secrets/base"
  [[ -n "${AZURE_TENANT_ID:-}${VAULT_URL:-}" ]] || {
      log "❌ ERROR: Required vars missing for template rendering"; return 1; }

  export APP_ID AZURE_TENANT_ID ESO_NS REGISTRY_NAME REGISTRY_NS VAULT_URL VAULT_ID SA_NAME
  source "$SCRIPT_PATH/render-deployments.sh" || {
      log "❌ ERROR: Failed to render templates"; return 1; }
  log "✅ Infra secrets templates rendered."
}


apply_deployments() {
  # ... (implementation from previous correct version, ensure APP_ID is used if templates need it via envsubst) ...
  [[ -n "${APP_ID:-}" ]] || { log "❌ ERROR: APP_ID not set before apply_deployments. Critical if templates rely on it."; return 1; }
  log "📦  Applying Kubernetes manifests from $DEPLOY_DIR (including templates)"
  find "$DEPLOY_DIR" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.yaml.tpl' -o -name '*.yml.tpl' \) -print0 |
  while IFS= read -r -d $'\0' file; do
    log "📄 Applying file: $file"
    if [[ "$file" == *.tpl ]]; then
      apply_template "$file" || return 1 # Propagate error from apply_template
    else
      kubectl apply -f "$file" || return 1 # Propagate error from kubectl apply
    fi
  done
  log "✅ All deployments applied."
}

install_argocd() {
  # ... (implementation from previous correct version with error returns) ...
  log "📦  Installing Argo CD into namespace 'argocd'"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  if ! kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml; then
    log "❌ ERROR: Failed to apply ArgoCD manifests."; return 1
  fi
  log "✅ ArgoCD installation manifest applied."
}

install_argo_workflows() {
  local ver="${ARGO_WORKFLOWS_VERSION}"
  log "📦  Installing Argo Workflows ${ver}"

  kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argo \
    -f "https://github.com/argoproj/argo-workflows/releases/download/${ver}/quick-start-minimal.yaml" || {
      log "❌ Failed to apply Argo Workflows manifest"; return 1; }

  # Wait for the core pods
  kubectl -n argo rollout status deploy/workflow-controller --timeout=180s
  kubectl -n argo rollout status deploy/argo-server         --timeout=180s

  # NodePort patching and readiness/secure patches are now handled declaratively by ArgoCD manifest

  if ! command -v argo &>/dev/null; then
    tmp=/tmp/argo
    url="https://github.com/argoproj/argo-workflows/releases/download/${ver}/argo-linux-amd64.gz"
    if curl -fsSL "$url" -o "${tmp}.gz" && gunzip -f "${tmp}.gz"; then
        chmod +x "${tmp}" && mv "${tmp}" /usr/local/bin/argo
        log "✅  argo CLI installed"
    else
        log "❌ ERROR: failed to download or unpack argo CLI"
        return 1
    fi
  fi

  log "✅  Argo Workflows ready – UI: http://localhost:${ARGO_WF_NODE_PORT} or http://argo.localtest.me"
}

# Setup port-forward for Argo Workflows UI with domain name access
setup_argo_workflows_ui_access() {
  log "🌐  Setting up easy access for Argo Workflows UI..."
  
  # Check if the port-forward is already running
  if pgrep -f "kubectl port-forward -n argo svc/argo-workflows-server" > /dev/null; then
    log "ℹ️  Argo Workflows UI port-forward already running"
  else
    log "🔌  Starting port-forward for Argo Workflows UI on port 8080..."
    kubectl port-forward -n argo svc/argo-workflows-server 8080:2746 &>/dev/null &
    sleep 2
  fi
  
  # Verify the port-forward is working
  if ! curl -s http://localhost:8080 > /dev/null; then
    log "⚠️  Port-forward not working, trying again..."
    pkill -f "kubectl port-forward -n argo svc/argo-workflows-server"
    kubectl port-forward -n argo svc/argo-workflows-server 8080:2746 &>/dev/null &
    sleep 2
  fi
  
  log "✅  Argo Workflows UI now accessible at:"
  log "   - http://localhost:8080 (direct access)"
  log "   - http://argo.localtest.me:8080 (name-based access, add to your hosts file if needed)"
  log "   - http://localhost:${ARGO_WF_NODE_PORT} (NodePort access)"
}

# Setup port-forward for Grafana UI with domain name access
setup_grafana_ui_access() {
  log "🌐  Setting up easy access for Grafana UI..."
  
  # Check if the port-forward is already running
  if pgrep -f "kubectl port-forward -n monitoring svc/grafana" > /dev/null; then
    log "ℹ️  Grafana UI port-forward already running"
  else
    log "🔌  Starting port-forward for Grafana UI on port 3001..."
    kubectl port-forward -n monitoring svc/grafana 3001:80 &>/dev/null &
    sleep 2
  fi
  
  # Verify the port-forward is working
  if ! curl -s http://localhost:3001 > /dev/null; then
    log "⚠️  Port-forward not working, trying again..."
    pkill -f "kubectl port-forward -n monitoring svc/grafana"
    kubectl port-forward -n monitoring svc/grafana 3001:80 &>/dev/null &
    sleep 2
  fi
  
  log "✅  Grafana UI now accessible at:"
  log "   - http://localhost:3001 (direct access)"
  log "   - http://grafana.localtest.me:3001 (name-based access, add to your hosts file if needed)"
  log "   - http://localhost:${GRAFANA_UI_PORT} (NodePort access)"
}


enable_argocd_insecure() {
  # ... (implementation from previous correct version with error returns) ...
  log "🔧  Setting ArgoCD server to run with --insecure (via argocd-cmd-params-cm)"
  kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
      -p '{"data":{"server.insecure":"true"}}'
  log "🔄 Restarting argocd-server deployment to apply config changes..."
  kubectl -n argocd rollout restart deploy/argocd-server
  if ! kubectl -n argocd rollout status deploy/argocd-server --timeout=300s; then
     log "❌ ERROR: ArgoCD server deployment did not become ready after restart for insecure mode."; return 1
  fi
  log "✅ ArgoCD server configured for insecure mode."
}

enable_admin_api_key() {
  # ... (implementation from previous correct version with error returns) ...
  log "🔧  Enabling 'apiKey' capability for the ArgoCD admin user (via argocd-cm)"
  kubectl -n argocd patch configmap argocd-cm --type merge \
    -p '{"data":{"accounts.admin":"login, apiKey"}}'
  log "🔄 Restarting argocd-server deployment to apply admin API key capability..."
  kubectl -n argocd rollout restart deployment/argocd-server
  if ! wait_for_argocd; then
     log "❌ ERROR: ArgoCD server deployment did not become ready after enabling admin API key."; return 1
  fi
  log "✅ Admin API key capability enabled for ArgoCD."
}

wait_for_argocd() {
  # ... (implementation from previous correct version with error returns) ...
  log "🕒  Waiting for argocd-server deployment to become Available..."
  if ! kubectl -n argocd rollout status deploy/argocd-server --timeout=300s; then
      log "❌ ERROR: ArgoCD server deployment did not reach Available status."; return 1
  fi
  log "✅ argocd-server deployment is Available."
  log "🕒  Waiting for argocd-server service endpoints..."
  if ! kubectl -n argocd get svc argocd-server &>/dev/null; then
    log "❌ ERROR: Argo CD server service (argocd-server) not found in namespace argocd."; return 1
  fi
  if ! kubectl -n argocd wait --for=jsonpath='{.subsets[0].addresses[0].ip}' endpoints argocd-server --timeout=180s; then
      log "❌ ERROR: Timed out waiting for argocd-server endpoints."; return 1
  fi
  log "✅ argocd-server service has active endpoints."
  return 0
}

patch_argocd_service_nodeport() {
  # ... (implementation from previous correct version with error returns) ...
  log "🔧  Ensuring argocd-server Service is NodePort, using NodePorts ${ARGO_HTTP_PORT} (HTTP) and ${ARGO_HTTPS_PORT} (HTTPS)."
  log "ℹ️  These NodePorts are targeted by the NGINX proxy."
  if ! kubectl -n argocd get svc argocd-server >/dev/null 2>&1; then
    log "❌ ERROR: Service 'argocd-server' not found in 'argocd' before patching."; return 1; fi
  cat <<EOF_SVC | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-server
    app.kubernetes.io/part-of: argocd
    app.kubernetes.io/component: server
spec:
  type: NodePort
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
    nodePort: ${ARGO_HTTP_PORT}
  - name: https
    port: 443
    protocol: TCP
    targetPort: 8080
    nodePort: ${ARGO_HTTPS_PORT}
  selector:
    app.kubernetes.io/name: argocd-server
EOF_SVC
  log "✅ Patched/Applied argocd-server service to NodePort."
  sleep 3 # Allow changes to propagate
}

login_argocd_cli () {
  local CMD pwd

  export ARGOCD_SERVER="localhost:${ARGO_HTTP_PORT}"
  log "🔐  Logging in to Argo CD CLI via NGINX proxy (${ARGOCD_SERVER})"

  pwd=$(kubectl -n argocd get secret argocd-initial-admin-secret \
                -o jsonpath='{.data.password}' | base64 -d)

  # wait until the NodePort responds
  for i in {1..30}; do
     curl -fkLs "http://${ARGOCD_SERVER}/healthz" >/dev/null 2>&1 && break
     sleep 2
  done

  CMD=$(command -v argocd || echo gocd)
  $CMD login "$ARGOCD_SERVER" \
       --username admin --password "$pwd" \
       --grpc-web --insecure || \
       log "⚠️  $CMD login failed"
}


generate_argocd_admin_token() {
  # ... (implementation from previous correct version with error returns) ...
  export ARGOCD_SERVER="host.docker.internal:${ARGO_HTTP_PORT}"
  log "ℹ️  Generating Argo CD admin token using ARGOCD_SERVER: ${ARGOCD_SERVER}"
  local pwd token token_file="${SCRIPT_PATH}/../.tmp/argocd-admin.token"
  mkdir -p "$(dirname "$token_file")"
  pwd=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
  if [[ -z "$pwd" ]]; then log "❌ ERROR: Failed to retrieve ArgoCD initial admin password for token generation."; return 1; fi

  log "🕒  Verifying ArgoCD server health at http://${ARGOCD_SERVER}/healthz before generating token..."
  for i in {1..15}; do
      if curl -kfsSL --max-time 3 "http://${ARGOCD_SERVER}/healthz" >/dev/null 2>&1; then
          log "✅ ArgoCD server healthy for token generation via ${ARGOCD_SERVER}."; break; fi
      log "⏳ ArgoCD server for token gen not ready (attempt $i/15)..."; sleep 2
      if [[ $i -eq 15 ]]; then log "❌ Failed to confirm ArgoCD health for token generation."; return 1; fi
  done
  token=$($CMD account generate-token --server "${ARGOCD_SERVER}" --username admin --password "$pwd" --insecure --plaintext --grpc-web --expires-in 15m 2>/dev/null)
  if [[ -z "$token" ]]; then log "❌ ERROR: Failed to generate ArgoCD admin token."; return 1; fi
  echo -n "$token" >"$token_file"
  log "📮  ArgoCD admin token written to $token_file (expires in 15m)"
}

expose_argocd() {
  # ... (implementation from previous correct version) ...
  local token_file="${SCRIPT_PATH}/../.tmp/argocd-admin.token"
  local argocd_env_file="${SCRIPT_PATH}/../.argocd-env"
  mkdir -p "$(dirname "$argocd_env_file")"
  log "🌐  Argo CD UI accessible at http://localhost:${ARGOCD_HTTP_PORT} (via NGINX proxy)"
  if [[ -f "$token_file" ]]; then
    echo -e "ARGOCD_URL=http://localhost:${ARGOCD_HTTP_PORT}\nARGOCD_TOKEN=$(cat "$token_file")" > "$argocd_env_file"
  else
    echo -e "ARGOCD_URL=http://localhost:${ARGOCD_HTTP_PORT}\nARGOCD_TOKEN=" > "$argocd_env_file"
    log "⚠️ ArgoCD admin token file not found at '$token_file'."
  fi
  log "ℹ️ ArgoCD connection details written to $argocd_env_file"
}

print_argocd_admin_password() {
  # ... (implementation from previous correct version) ...
  log "🔑  Argo CD initial admin password:"
  kubectl -n argocd get secret argocd-initial-admin-secret \
          -o jsonpath='{.data.password}' | base64 -d; echo ""
  log "🌐  Open http://localhost:${ARGO_HTTP_PORT} (via NGINX proxy) and log in with user 'admin'."
  log "CLI: argocd login host.docker.internal:${ARGO_HTTP_PORT} --username admin --grpc-web"
}

apply_app_of_apps() {
  # ... (implementation from previous correct version with error returns) ...
  local APP_FILE="${PROJECT_ROOT}/bootstrap/app-of-apps.yaml"
  log "📦  Applying Argo CD app-of-apps manifest ($APP_FILE)"
  if ! kubectl apply -f "$APP_FILE"; then
    log "❌ ERROR: Failed to apply app-of-apps manifest '$APP_FILE'."; return 1
  fi
  log "✅ App-of-apps manifest applied."
}

ensure_acr_pull_role() {
  [[ -n "${APP_ID:-}" ]] || { log "❌ ERROR: APP_ID not set"; return 1; }
  local acr_name="${ACR_NAME:-vpittamp}"
  local acr_rg="${ACR_RG:-$RESOURCE_GROUP}"

  local acr_id
  acr_id=$(az acr show -n "$acr_name" -g "$acr_rg" --query id -o tsv 2>/dev/null) \
      || { log "❌ ERROR: ACR '$acr_name' not found in RG '$acr_rg'"; return 1; }

  if az role assignment list --assignee "$APP_ID" --role "AcrPull" --scope "$acr_id" --query '[0].id' -o tsv 2>/dev/null | grep -q .; then
    log "✅  AcrPull role already present for AAD App (Client ID '$APP_ID') on ACR '$acr_name'"
  else
    log "🔐  Granting 'AcrPull' role on ACR '$acr_name' to AAD App (Client ID '$APP_ID')..."
    if az role assignment create --assignee "$APP_ID" --role "AcrPull" --scope "$acr_id" -o none; then
      log "✅  'AcrPull' role granted to AAD App (Client ID '$APP_ID') on ACR '$acr_name'."
    else
      log "❌ ERROR: Failed to grant 'AcrPull' role to AAD App (Client ID '$APP_ID') on ACR '$acr_name'."; return 1
    fi
  fi
}

refresh_app_id() { # This sets the global APP_ID variable
  # ... (implementation from previous correct version) ...
  log "🔄  Refreshing global APP_ID (Client ID) for AAD App '$APP_NAME'..."
  local refreshed_app_id
  refreshed_app_id="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv 2>/dev/null)"
  if [[ -n "$refreshed_app_id" ]]; then
    export APP_ID="$refreshed_app_id"
    log "✅  Refreshed global APP_ID for '$APP_NAME' → $APP_ID"
  else # APP_ID could not be refreshed, previous value (if any) is kept.
    log "⚠️ WARN: Could not find AAD App '$APP_NAME' to refresh APP_ID. Previous value: '${APP_ID:-Not Set}'. This might be an issue if it's newly created and needed."
    # Do not return error here, allow script to proceed, subsequent steps will fail if APP_ID is truly needed and missing.
  fi
  save_app_id
}

apply_secret_manifests() {
  log "🔒  Applying YAML files containing 'secret' in their names to Kubernetes cluster"
  local secret_files_found=false
  local project_root="${PROJECT_ROOT}"
  
  # Find all YAML files containing 'secret' in the filename
  find "$project_root" -type f \( -name "*secret*.yaml" -o -name "*secret*.yml" \) -print0 |
  while IFS= read -r -d $'\0' file; do
    secret_files_found=true
    log "📄 Applying secret manifest: $file"
    if ! kubectl apply -f "$file"; then
      log "❌ ERROR: Failed to apply secret manifest '$file'."
      return 1
    fi
  done
  
  if ! $secret_files_found; then
    log "ℹ️  No YAML files containing 'secret' in their names were found."
    return 0
  fi
  
  log "✅ All secret manifests applied successfully."
}

install_headlamp() {
  # ... (implementation from previous correct version with HEADLAMP_NODE_PORT and error returns) ...
  : "${HEADLAMP_NODE_PORT:=30003}" # Default NodePort for Headlamp service
  log "📦 Installing Headlamp..."
  log "ℹ️  Headlamp service in Kind will target NodePort ${HEADLAMP_NODE_PORT}."
  log "    For host access: ensure NGINX proxy in kind-proxy.sh is configured to expose this on a host port,"
  log "    or use 'kubectl -n kube-system port-forward svc/headlamp <local_host_port>:${HEADLAMP_NODE_PORT}'."

  kubectl apply -f https://raw.githubusercontent.com/kinvolk/headlamp/main/kubernetes-headlamp.yaml
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:  name: headlamp-admin; namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:  name: headlamp-admin-binding
roleRef:  apiGroup: rbac.authorization.k8s.io; kind: ClusterRole; name: cluster-admin
subjects:  - kind: ServiceAccount; name: headlamp-admin; namespace: kube-system
EOF
  log "⏳  Waiting for Headlamp pod in kube-system namespace..."
  if ! kubectl -n kube-system wait --for=condition=ready pod -l k8s-app=headlamp --timeout=180s; then
    log "❌ ERROR: Headlamp pod did not become ready."; kubectl -n kube-system get pods -l k8s-app=headlamp; kubectl -n kube-system logs -l k8s-app=headlamp --tail=50 --timestamps; return 1;
  fi
  local headlamp_target_port=4466 # Default internal port Headlamp pod listens on
  log "🔧 Patching Headlamp service to be NodePort, using NodePort ${HEADLAMP_NODE_PORT} for target ${headlamp_target_port}"
  cat <<EOF_HEADLAMP_SVC | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:  name: headlamp; namespace: kube-system
spec:
  type: NodePort
  ports:  - port: ${headlamp_target_port}; targetPort: ${headlamp_target_port}; nodePort: ${HEADLAMP_NODE_PORT}; protocol: TCP
  selector:    k8s-app: headlamp
EOF_HEADLAMP_SVC
  log "🔧  Applying Headlamp Auto‑login plugin ConfigMap"
  kubectl -n kube-system apply -f - <<'CM_EOF'
apiVersion: v1
kind: ConfigMap
metadata:  name: headlamp-autologin-config; namespace: kube-system; labels:    headlamp.dev/plugin: 'true'
data:
  plugin.js: |
    import { registerAuthenticator } from "@kinvolk/headlamp-plugin/lib";
    class AutoLoginAuthenticator {
      name = "Auto‑Login"; token = null;
      async authenticate() {
        if (this.token) return { token: this.token };
        try {
          const resp = await fetch('/api/v1/namespaces/kube-system/serviceaccounts/headlamp-admin/token', {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ apiVersion: 'authentication.k8s.io/v1', kind: 'TokenRequest', spec: { expirationSeconds: 3600 }})});
          if (!resp.ok) throw new Error(await resp.text());
          const data = await resp.json(); this.token = data.status.token; return { token: this.token };
        } catch (err) { console.error('Auto‑Login failed', err); return null; }
      }
      requiresCredentials() { return !this.token; } close() { this.token = null; }
    }
    export default () => registerAuthenticator(new AutoLoginAuthenticator());
CM_EOF
  log "🔧  Patching Headlamp Deployment to mount auto-login plugin"
  kubectl -n kube-system patch deployment headlamp --type json -p "[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/volumes/-\",\"value\":{\"name\":\"plugin-vol\",\"configMap\":{\"name\":\"headlamp-autologin-config\"}}},
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/volumeMounts/-\",\"value\":{\"name\":\"plugin-vol\",\"mountPath\":\"/headlamp/plugins/autologin\"}}]"
  kubectl -n kube-system rollout restart deployment/headlamp
  kubectl -n kube-system wait --for=condition=available deployment/headlamp --timeout=120s
  local token_path="${SCRIPT_PATH}/../.tmp/headlamp-token.txt"; mkdir -p "$(dirname "$token_path")"
  local token_value; token_value=$(kubectl -n kube-system create token headlamp-admin --duration=8760h)
  echo "$token_value" > "$token_path"
  log "🔑 Headlamp admin token saved to: $token_path"
  log "🌐  Headlamp UI is configured. Access via NGINX proxy (if set up for port ${HEADLAMP_NODE_PORT}) or 'kubectl port-forward'."
  log "✅ Headlamp installation and configuration complete."
}