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
echo ""
log "🔒 Note: Sensitive credentials will not be displayed on screen"

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

# Helper function to prompt with env var hint
prompt_with_env() {
    local prompt="$1"
    local var_name="$2"
    local is_secret="$3"
    local default="$4"
    local env_value="${!var_name}"
    local result=""
    
    # Strip newlines from env value too
    if [[ -n "$env_value" ]]; then
        env_value=$(echo "$env_value" | tr -d '\n\r' | xargs)
    fi
    
    if [[ -n "$env_value" ]]; then
        if [[ "$is_secret" == "true" ]]; then
            local hint="${env_value:0:5}..."
            read -p "$prompt (env: $hint) [Enter to use, or type new]: " -s result
            echo ""
        else
            read -p "$prompt (env: $env_value) [Enter to use, or type new]: " result
        fi
        if [[ -z "$result" ]]; then
            result="$env_value"
        fi
    else
        if [[ -n "$default" ]]; then
            if [[ "$is_secret" == "true" ]]; then
                read -p "$prompt (default: $default): " -s result
                echo ""
            else
                read -p "$prompt (default: $default): " result
            fi
            result=${result:-"$default"}
        else
            if [[ "$is_secret" == "true" ]]; then
                read -p "$prompt: " -s result
                echo ""
            else
                read -p "$prompt: " result
            fi
        fi
    fi
    # Strip newlines and whitespace from result
    result=$(echo "$result" | tr -d '\n\r' | xargs)
    echo "$result"
}

# Collect credentials based on provider
case $LLM_PROVIDER in
    "azure-openai")
        echo ""
        AZURE_OPENAI_API_KEY=$(prompt_with_env "Azure OpenAI API Key" "AZURE_OPENAI_API_KEY" "true")
        AZURE_OPENAI_ENDPOINT=$(prompt_with_env "Azure OpenAI Endpoint" "AZURE_OPENAI_ENDPOINT" "false")
        AZURE_OPENAI_API_VERSION=$(prompt_with_env "Azure OpenAI API Version" "AZURE_OPENAI_API_VERSION" "false" "2024-02-15-preview")
        AZURE_OPENAI_DEPLOYMENT=$(prompt_with_env "Azure OpenAI Deployment Name" "AZURE_OPENAI_DEPLOYMENT" "false")
        ;;
    "openai")
        echo ""
        OPENAI_API_KEY=$(prompt_with_env "OpenAI API Key" "OPENAI_API_KEY" "true")
        OPENAI_ENDPOINT=$(prompt_with_env "OpenAI Endpoint" "OPENAI_ENDPOINT" "false" "https://api.openai.com/v1")
        OPENAI_MODEL_NAME=$(prompt_with_env "OpenAI Model Name" "OPENAI_MODEL_NAME" "false" "gpt-4")
        ;;
    "aws-bedrock")
        echo ""
        AWS_ACCESS_KEY_ID=$(prompt_with_env "AWS Access Key ID" "AWS_ACCESS_KEY_ID" "false")
        AWS_SECRET_ACCESS_KEY=$(prompt_with_env "AWS Secret Access Key" "AWS_SECRET_ACCESS_KEY" "true")
        AWS_REGION=$(prompt_with_env "AWS Region" "AWS_REGION" "false" "us-east-1")
        AWS_BEDROCK_MODEL_ID=$(prompt_with_env "AWS Bedrock Model ID" "AWS_BEDROCK_MODEL_ID" "false" "anthropic.claude-3-sonnet-20240229-v1:0")
        AWS_BEDROCK_PROVIDER=$(prompt_with_env "AWS Bedrock Provider" "AWS_BEDROCK_PROVIDER" "false" "anthropic")
        ;;
    "google-gemini")
        echo ""
        GOOGLE_API_KEY=$(prompt_with_env "Google API Key" "GOOGLE_API_KEY" "true")
        GOOGLE_MODEL_NAME=$(prompt_with_env "Google Model Name" "GOOGLE_MODEL_NAME" "false" "gemini-pro")
        ;;
    "gcp-vertex")
        echo ""
        GCP_PROJECT_ID=$(prompt_with_env "GCP Project ID" "GCP_PROJECT_ID" "false")
        GCP_LOCATION=$(prompt_with_env "GCP Location" "GCP_LOCATION" "false" "us-central1")
        GCP_MODEL_NAME=$(prompt_with_env "GCP Model Name" "GCP_MODEL_NAME" "false" "gemini-pro")
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
