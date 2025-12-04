#!/usr/bin/env bash
# init-langfuse-secrets.sh - Initialize Langfuse headless secrets in Azure Key Vault
#
# This script creates the secrets required for Langfuse headless initialization,
# which allows the Langfuse UI to be pre-configured with a default organization,
# project, user, and API keys without manual setup.
#
# Usage:
#   ./init-langfuse-secrets.sh [VAULT_NAME]
#
# Environment variables:
#   VAULT_NAME: Azure Key Vault name (default: pittampalli-akv)
#   LANGFUSE_ORG_ID: Organization ID (default: speckit)
#   LANGFUSE_ORG_NAME: Organization display name (default: SpecKit)
#   LANGFUSE_PROJECT_ID: Project ID (default: speckit-agents)
#   LANGFUSE_PROJECT_NAME: Project display name (default: SpecKit Agents)
#   LANGFUSE_USER_EMAIL: Admin user email (default: admin@speckit.local)
#   LANGFUSE_USER_NAME: Admin user display name (default: SpecKit Admin)
#   LANGFUSE_USER_PASSWORD: Admin user password (auto-generated if not set)
#   LANGFUSE_PUBLIC_KEY: API public key (auto-generated if not set)
#   LANGFUSE_SECRET_KEY: API secret key (auto-generated if not set)
#
# The API keys are used both for:
# 1. Langfuse headless initialization (LANGFUSE_INIT_PROJECT_PUBLIC_KEY, LANGFUSE_INIT_PROJECT_SECRET_KEY)
# 2. Agent SDK configuration (LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
VAULT_NAME="${1:-${VAULT_NAME:-keyvault-thcmfmoo5oeow}}"
LANGFUSE_ORG_ID="${LANGFUSE_ORG_ID:-speckit}"
LANGFUSE_ORG_NAME="${LANGFUSE_ORG_NAME:-SpecKit}"
LANGFUSE_PROJECT_ID="${LANGFUSE_PROJECT_ID:-speckit-agents}"
LANGFUSE_PROJECT_NAME="${LANGFUSE_PROJECT_NAME:-SpecKit Agents}"
LANGFUSE_USER_EMAIL="${LANGFUSE_USER_EMAIL:-admin@speckit.local}"
LANGFUSE_USER_NAME="${LANGFUSE_USER_NAME:-SpecKit Admin}"

# Generate random strings for secrets if not provided
generate_random() {
    openssl rand -base64 "$1" | tr -dc 'a-zA-Z0-9' | head -c "$1"
}

# Generate API keys with Langfuse format prefix
LANGFUSE_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY:-lf_pk_$(generate_random 24)}"
LANGFUSE_SECRET_KEY="${LANGFUSE_SECRET_KEY:-lf_sk_$(generate_random 32)}"
LANGFUSE_USER_PASSWORD="${LANGFUSE_USER_PASSWORD:-$(generate_random 16)}"

echo -e "${GREEN}=== Langfuse Headless Initialization Secrets ===${NC}"
echo -e "Vault: ${YELLOW}${VAULT_NAME}${NC}"
echo ""
echo "Configuration:"
echo "  Organization ID:   ${LANGFUSE_ORG_ID}"
echo "  Organization Name: ${LANGFUSE_ORG_NAME}"
echo "  Project ID:        ${LANGFUSE_PROJECT_ID}"
echo "  Project Name:      ${LANGFUSE_PROJECT_NAME}"
echo "  User Email:        ${LANGFUSE_USER_EMAIL}"
echo "  User Name:         ${LANGFUSE_USER_NAME}"
echo ""

# Check if az CLI is available
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI (az) not found. Please install it first.${NC}"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${RED}Error: Not logged in to Azure. Run 'az login' first.${NC}"
    exit 1
fi

# Function to set a secret in Key Vault
set_secret() {
    local name="$1"
    local value="$2"
    local description="$3"

    echo -n "  Setting ${name}... "
    if az keyvault secret set \
        --vault-name "$VAULT_NAME" \
        --name "$name" \
        --value "$value" \
        --description "$description" \
        --output none 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

echo -e "${GREEN}Creating secrets in Azure Key Vault...${NC}"
echo ""

# Organization secrets
echo "Organization configuration:"
set_secret "LANGFUSE-INIT-ORG-ID" "$LANGFUSE_ORG_ID" "Langfuse organization ID for headless init"
set_secret "LANGFUSE-INIT-ORG-NAME" "$LANGFUSE_ORG_NAME" "Langfuse organization display name"

# Project secrets
echo ""
echo "Project configuration:"
set_secret "LANGFUSE-INIT-PROJECT-ID" "$LANGFUSE_PROJECT_ID" "Langfuse project ID for headless init"
set_secret "LANGFUSE-INIT-PROJECT-NAME" "$LANGFUSE_PROJECT_NAME" "Langfuse project display name"

# User secrets
echo ""
echo "User configuration:"
set_secret "LANGFUSE-INIT-USER-EMAIL" "$LANGFUSE_USER_EMAIL" "Langfuse admin user email"
set_secret "LANGFUSE-INIT-USER-NAME" "$LANGFUSE_USER_NAME" "Langfuse admin user display name"
set_secret "LANGFUSE-INIT-USER-PASSWORD" "$LANGFUSE_USER_PASSWORD" "Langfuse admin user password"

# API keys (shared between headless init and SDK)
echo ""
echo "API keys (used for both headless init and SDK):"
set_secret "LANGFUSE-PUBLIC-KEY" "$LANGFUSE_PUBLIC_KEY" "Langfuse API public key"
set_secret "LANGFUSE-SECRET-KEY" "$LANGFUSE_SECRET_KEY" "Langfuse API secret key"

echo ""
echo -e "${GREEN}=== Secrets Created Successfully ===${NC}"
echo ""
echo "Next steps:"
echo "1. Sync External Secrets in the cluster:"
echo "   kubectl rollout restart deployment -n external-secrets external-secrets"
echo ""
echo "2. Wait for secrets to sync to observability namespace:"
echo "   kubectl get externalsecrets -n observability"
echo ""
echo "3. Restart Langfuse to pick up the new init secrets:"
echo "   kubectl rollout restart deployment -n observability langfuse"
echo ""
echo "4. Access Langfuse UI:"
echo "   https://langfuse.cnoe.localtest.me:8443"
echo ""
echo "   Login credentials:"
echo "   Email:    ${LANGFUSE_USER_EMAIL}"
echo "   Password: ${LANGFUSE_USER_PASSWORD}"
echo ""
echo "5. Verify agents are sending traces:"
echo "   The SpecKit agents will automatically use these API keys:"
echo "   Public Key: ${LANGFUSE_PUBLIC_KEY}"
echo ""

# Save credentials to a local file for reference
CREDS_FILE="/tmp/langfuse-credentials.txt"
cat > "$CREDS_FILE" << EOF
Langfuse Credentials
====================
Generated: $(date -Iseconds)
Vault: ${VAULT_NAME}

Organization:
  ID:   ${LANGFUSE_ORG_ID}
  Name: ${LANGFUSE_ORG_NAME}

Project:
  ID:   ${LANGFUSE_PROJECT_ID}
  Name: ${LANGFUSE_PROJECT_NAME}

Admin User:
  Email:    ${LANGFUSE_USER_EMAIL}
  Name:     ${LANGFUSE_USER_NAME}
  Password: ${LANGFUSE_USER_PASSWORD}

API Keys:
  Public:  ${LANGFUSE_PUBLIC_KEY}
  Secret:  ${LANGFUSE_SECRET_KEY}

URL: https://langfuse.cnoe.localtest.me:8443
EOF

echo -e "${YELLOW}Credentials saved to: ${CREDS_FILE}${NC}"
echo -e "${RED}WARNING: Delete this file after noting the credentials!${NC}"
