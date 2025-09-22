#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log "❌ kubectl is required but not installed"
    exit 1
fi

# Check if vault CLI is available
if ! command -v vault &> /dev/null; then
    log "❌ vault CLI is required but not installed"
    exit 1
fi

log "🔧 Setting up LLM credentials for AI Platform Engineering"

# Get vault token and setup connection
VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN

# Start port forward in background
log "🔗 Starting Vault port forward..."
kubectl port-forward -n vault svc/vault 8200:8200 &
VAULT_PID=$!
sleep 3

# Prompt for LLM provider
echo ""
echo "Supported LLM Providers:"
echo "1) azure-openai"
echo "2) openai"
echo "3) aws-bedrock"
echo "4) google-gemini"
echo "5) gcp-vertex"
echo ""
read -p "Select LLM provider (1-5): " provider_choice

case $provider_choice in
    1) LLM_PROVIDER="azure-openai" ;;
    2) LLM_PROVIDER="openai" ;;
    3) LLM_PROVIDER="aws-bedrock" ;;
    4) LLM_PROVIDER="google-gemini" ;;
    5) LLM_PROVIDER="gcp-vertex" ;;
    *) log "❌ Invalid choice"; kill $VAULT_PID 2>/dev/null; exit 1 ;;
esac

log "📝 Selected provider: $LLM_PROVIDER"

# Initialize all fields as empty
AZURE_OPENAI_API_KEY=""
AZURE_OPENAI_ENDPOINT=""
AZURE_OPENAI_API_VERSION=""
AZURE_OPENAI_DEPLOYMENT=""
OPENAI_API_KEY=""
OPENAI_ENDPOINT=""
OPENAI_MODEL_NAME=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_REGION=""
AWS_BEDROCK_MODEL_ID=""
AWS_BEDROCK_PROVIDER=""
GOOGLE_API_KEY=""
GOOGLE_MODEL_NAME=""
GCP_PROJECT_ID=""
GCP_LOCATION=""
GCP_MODEL_NAME=""

# Collect credentials based on provider
case $LLM_PROVIDER in
    "azure-openai")
        echo ""
        read -p "Azure OpenAI API Key: " -s AZURE_OPENAI_API_KEY
        echo ""
        read -p "Azure OpenAI Endpoint: " AZURE_OPENAI_ENDPOINT
        read -p "Azure OpenAI API Version (default: 2024-02-15-preview): " AZURE_OPENAI_API_VERSION
        AZURE_OPENAI_API_VERSION=${AZURE_OPENAI_API_VERSION:-"2024-02-15-preview"}
        read -p "Azure OpenAI Deployment Name: " AZURE_OPENAI_DEPLOYMENT
        ;;
    "openai")
        echo ""
        read -p "OpenAI API Key: " -s OPENAI_API_KEY
        echo ""
        read -p "OpenAI Endpoint (default: https://api.openai.com/v1): " OPENAI_ENDPOINT
        OPENAI_ENDPOINT=${OPENAI_ENDPOINT:-"https://api.openai.com/v1"}
        read -p "OpenAI Model Name (default: gpt-4): " OPENAI_MODEL_NAME
        OPENAI_MODEL_NAME=${OPENAI_MODEL_NAME:-"gpt-4"}
        ;;
    "aws-bedrock")
        echo ""
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
        read -p "AWS Secret Access Key: " -s AWS_SECRET_ACCESS_KEY
        echo ""
        read -p "AWS Region (default: us-east-1): " AWS_REGION
        AWS_REGION=${AWS_REGION:-"us-east-1"}
        read -p "AWS Bedrock Model ID (default: anthropic.claude-3-sonnet-20240229-v1:0): " AWS_BEDROCK_MODEL_ID
        AWS_BEDROCK_MODEL_ID=${AWS_BEDROCK_MODEL_ID:-"anthropic.claude-3-sonnet-20240229-v1:0"}
        read -p "AWS Bedrock Provider (default: anthropic): " AWS_BEDROCK_PROVIDER
        AWS_BEDROCK_PROVIDER=${AWS_BEDROCK_PROVIDER:-"anthropic"}
        ;;
    "google-gemini")
        echo ""
        read -p "Google API Key: " -s GOOGLE_API_KEY
        echo ""
        read -p "Google Model Name (default: gemini-pro): " GOOGLE_MODEL_NAME
        GOOGLE_MODEL_NAME=${GOOGLE_MODEL_NAME:-"gemini-pro"}
        ;;
    "gcp-vertex")
        echo ""
        read -p "GCP Project ID: " GCP_PROJECT_ID
        read -p "GCP Location (default: us-central1): " GCP_LOCATION
        GCP_LOCATION=${GCP_LOCATION:-"us-central1"}
        read -p "GCP Model Name (default: gemini-pro): " GCP_MODEL_NAME
        GCP_MODEL_NAME=${GCP_MODEL_NAME:-"gemini-pro"}
        ;;
esac

# Store credentials in Vault
log "💾 Storing credentials in Vault..."
vault kv put secret/ai-platform-engineering/global \
    LLM_PROVIDER="$LLM_PROVIDER" \
    AZURE_OPENAI_API_KEY="$AZURE_OPENAI_API_KEY" \
    AZURE_OPENAI_ENDPOINT="$AZURE_OPENAI_ENDPOINT" \
    AZURE_OPENAI_API_VERSION="$AZURE_OPENAI_API_VERSION" \
    AZURE_OPENAI_DEPLOYMENT="$AZURE_OPENAI_DEPLOYMENT" \
    OPENAI_API_KEY="$OPENAI_API_KEY" \
    OPENAI_ENDPOINT="$OPENAI_ENDPOINT" \
    OPENAI_MODEL_NAME="$OPENAI_MODEL_NAME" \
    AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    AWS_REGION="$AWS_REGION" \
    AWS_BEDROCK_MODEL_ID="$AWS_BEDROCK_MODEL_ID" \
    AWS_BEDROCK_PROVIDER="$AWS_BEDROCK_PROVIDER" \
    GOOGLE_API_KEY="$GOOGLE_API_KEY" \
    GOOGLE_MODEL_NAME="$GOOGLE_MODEL_NAME" \
    GCP_PROJECT_ID="$GCP_PROJECT_ID" \
    GCP_LOCATION="$GCP_LOCATION" \
    GCP_MODEL_NAME="$GCP_MODEL_NAME" >/dev/null

log "✅ LLM credentials successfully stored in Vault"
log "🔍 You can verify at: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fglobal"

# Cleanup
kill $VAULT_PID 2>/dev/null
log "🎉 Setup complete!"
