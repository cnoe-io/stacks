#!/usr/bin/env bash
# Script to sync JWKS from Kind cluster to Azure storage for Workload Identity
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="$(dirname "${SCRIPT_DIR}")"

# Source environment variables from wi.env if it exists
if [ -f "${STACKS_DIR}/.env-files/wi.env" ]; then
    echo "Loading environment from ${STACKS_DIR}/.env-files/wi.env"
    source "${STACKS_DIR}/.env-files/wi.env"
fi

# Configuration from environment or defaults (wi.env takes precedence)
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-oidcissuer65846b7df97b}"
SERVICE_ACCOUNT_ISSUER="${SERVICE_ACCOUNT_ISSUER:-https://${AZURE_STORAGE_ACCOUNT}.z13.web.core.windows.net/}"
# Use AZURE_SUBSCRIPTION_ID from wi.env, fallback to subscription name
if [ -n "${AZURE_SUBSCRIPTION_ID}" ]; then
    AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION_ID}"
else
    AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION:-Subscription 2}"
fi

echo "======================================"
echo "Syncing JWKS to Azure Storage"
echo "======================================"
echo "Storage Account: ${AZURE_STORAGE_ACCOUNT}"
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Service Account Issuer: ${SERVICE_ACCOUNT_ISSUER}"
echo "Subscription ID: ${AZURE_SUBSCRIPTION}"
echo ""

# Ensure we're using the correct subscription
echo "Setting Azure subscription..."
if az account set --subscription "${AZURE_SUBSCRIPTION}" 2>/dev/null; then
    echo "✅ Using subscription: $(az account show --query name -o tsv) (${AZURE_SUBSCRIPTION})"
else
    echo "⚠️  Warning: Could not set subscription to ${AZURE_SUBSCRIPTION}"
    echo "   Current subscription: $(az account show --query name -o tsv)"
    echo "   You may need to run: az account set --subscription '${AZURE_SUBSCRIPTION}'"
    exit 1
fi

# Check Azure authentication first
echo "Checking Azure authentication..."
if ! az account show &>/dev/null; then
    echo "❌ Error: Not logged in to Azure"
    echo "Please run: az login"
    echo "Then re-run this script"
    exit 1
fi

# Check if token is valid (not expired or about to expire in next minute)
TOKEN_EXPIRY=$(az account get-access-token --query "expiresOn" -o tsv 2>/dev/null || echo "")
if [ -n "$TOKEN_EXPIRY" ]; then
    CURRENT_TIME=$(date +%s)
    EXPIRY_TIME=$(date -d "$TOKEN_EXPIRY" +%s 2>/dev/null || echo 0)
    TIME_DIFF=$((EXPIRY_TIME - CURRENT_TIME))
    
    if [ $TIME_DIFF -lt 60 ]; then
        echo "❌ Error: Azure token expired or about to expire"
        echo "Token expires at: $TOKEN_EXPIRY"
        echo "Please run: az login"
        exit 1
    else
        ACCOUNT=$(az account show --query "user.name" -o tsv)
        echo "✅ Authenticated as: $ACCOUNT"
        echo "   Token valid until: $TOKEN_EXPIRY"
    fi
else
    echo "⚠️  Warning: Could not verify token expiry"
fi
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "Error: kubectl is not configured or cluster is not accessible"
    echo "Please ensure you have a running Kind cluster and kubectl is configured"
    exit 1
fi

# Extract JWKS from the cluster
echo "Extracting JWKS from cluster..."
kubectl get --raw /openid/v1/jwks | jq > "${SCRIPT_DIR}/jwks.json"

# Display the key ID for verification
KID=$(jq -r '.keys[0].kid' "${SCRIPT_DIR}/jwks.json")
echo "Extracted JWKS with key ID: ${KID}"

# Check if we're in nix-shell or if az is available
if ! command -v az &> /dev/null; then
    echo "Azure CLI not found in current environment"
    echo "Attempting to use nix-shell..."
    
    if [ -f "${SCRIPT_DIR}/../shell.nix" ]; then
        echo "Running with nix-shell..."
        nix-shell "${SCRIPT_DIR}/../shell.nix" --run "\
            az storage blob upload \
                --container-name '\$web' \
                --file '${SCRIPT_DIR}/jwks.json' \
                --name 'openid/v1/jwks' \
                --account-name '${AZURE_STORAGE_ACCOUNT}' \
                --auth-mode login \
                --overwrite \
                --output table"
    else
        echo "Error: Azure CLI not available and shell.nix not found"
        echo "Please install Azure CLI or run this script from the stacks directory"
        exit 1
    fi
else
    echo "Uploading JWKS to Azure storage using Azure AD authentication..."
    az storage blob upload \
        --container-name '$web' \
        --file "${SCRIPT_DIR}/jwks.json" \
        --name "openid/v1/jwks" \
        --account-name "${AZURE_STORAGE_ACCOUNT}" \
        --auth-mode login \
        --overwrite \
        --output table
fi

# Verify the upload
echo ""
echo "Verifying JWKS upload..."
REMOTE_KID=$(curl -s "${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks" | jq -r '.keys[0].kid')

if [ "${KID}" == "${REMOTE_KID}" ]; then
    echo "✅ Success! JWKS synced to Azure storage"
    echo "   Key ID in cluster: ${KID}"
    echo "   Key ID in Azure:  ${REMOTE_KID}"
else
    echo "❌ Error: JWKS mismatch"
    echo "   Key ID in cluster: ${KID}"
    echo "   Key ID in Azure:  ${REMOTE_KID}"
    exit 1
fi

# Check if OpenID configuration exists
echo ""
echo "Checking OpenID configuration..."
if curl -sf "${SERVICE_ACCOUNT_ISSUER}.well-known/openid-configuration" > /dev/null; then
    echo "✅ OpenID configuration is accessible"
else
    echo "⚠️  Warning: OpenID configuration not found at ${SERVICE_ACCOUNT_ISSUER}.well-known/openid-configuration"
    echo "   You may need to upload the openid-configuration.json file"
    
    # Create the OpenID configuration file
    cat > "${SCRIPT_DIR}/openid-configuration.json" <<EOF
{
  "issuer": "${SERVICE_ACCOUNT_ISSUER}",
  "jwks_uri": "${SERVICE_ACCOUNT_ISSUER}openid/v1/jwks",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ]
}
EOF
    echo "   Created openid-configuration.json - upload it to .well-known/openid-configuration"
fi

echo ""
echo "======================================"
echo "JWKS sync completed successfully!"
echo "======================================"
echo ""
echo "External Secrets Operator should now be able to authenticate with Azure Key Vault"
echo "using the workload identity federation."