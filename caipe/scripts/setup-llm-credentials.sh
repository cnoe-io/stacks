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

ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --envFile)
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--envFile <path>]"
            echo ""
            echo "Options:"
            echo "  --envFile <path>     Read environment variables from specified file"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to read and load environment variables from file
load_env_file() {
    local env_file="$1"
    if [[ -n "$env_file" ]]; then
        if [[ -f "$env_file" ]]; then
            log "📄 Loading environment variables from: $env_file"
            # Read the file line by line and export variables
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Skip empty lines and comments
                if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                    # Check if line contains =
                    if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
                        local var_name="${BASH_REMATCH[1]// /}"  # Remove spaces
                        local var_value="${BASH_REMATCH[2]}"

                        # Remove quotes if present
                        if [[ "$var_value" =~ ^\"(.*)\"$ ]] || [[ "$var_value" =~ ^\'(.*)\'$ ]]; then
                            var_value="${BASH_REMATCH[1]}"
                        fi

                        # Export the variable if it's not already set or if we have a value
                        if [[ -n "$var_value" ]]; then
                            export "$var_name"="$var_value"
                            log "  ✓ Loaded $var_name from env file"
                        fi
                    fi
                fi
            done < "$env_file"
        else
            log "⚠️  Environment file not found: $env_file"
            exit 1
        fi
    fi
}

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

if [[ -n "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
fi

# see if LLM_PROVIDER is set in the env file
if [[ -n "${LLM_PROVIDER:-}" ]]; then
    LLM_PROVIDER="$LLM_PROVIDER"
    log "📝 Using provider from env file: $LLM_PROVIDER"
else
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
fi

echo ""
log "🔒 Note: Sensitive credentials will not be displayed on screen"

# Load environment file if specified (after initialization)
load_env_file "$ENV_FILE"

# Single-line, exact-byte prompt helper (no newline added, no stripping)
# Usage: prompt_with_env "<Prompt>" VAR_NAME is_secret
prompt_with_env() {
  local prompt="$1" var_name="$2" is_secret="$3" default_value="$4"
  local env_value="${!var_name}" result

  # If we have an env file and the variable has a value, auto-populate
  if [[ -n "$ENV_FILE" && -n "$env_value" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ✓ Using existing value detected for $prompt in env file. Auto-populating..." >&2
    result="$env_value"
  elif [[ -n "$env_value" ]]; then
    if [[ "$is_secret" == "true" ]]; then
      local hint="${env_value:0:5}..."
      printf "%s (env: %s) [Enter to use, type new]: " "$prompt" "$hint" > /dev/tty
      IFS= read -r choice < /dev/tty
      if [[ -z "$choice" ]]; then
        result="$env_value"
      else
        IFS= read -rs -p "$prompt: " result < /dev/tty
        printf "\n" > /dev/tty
      fi
    else
      IFS= read -r -p "$prompt (env: $env_value) [Enter to use, type new]: " choice < /dev/tty
      if [[ -z "$choice" ]]; then
        result="$env_value"
      else
        IFS= read -r -p "$prompt: " result < /dev/tty
      fi
    fi
  else
    if [[ "$is_secret" == "true" ]]; then
      IFS= read -rs -p "$prompt: " result < /dev/tty
      printf "\n" > /dev/tty
    else
      IFS= read -r -p "$prompt: " result < /dev/tty
    fi
  fi

  # Normalize only a trailing CR (some terminals send \r)
  result=${result%$'\r'}

  # Use default value if result is empty and default is provided
  if [[ -z "$result" && -n "$default_value" ]]; then
    result="$default_value"
  fi

  # Output EXACTLY the bytes, no newline
  printf '%s' "$result"
}

# Collect credentials based on provider
case $LLM_PROVIDER in
    "azure-openai")
        echo ""
        AZURE_OPENAI_API_KEY="$(prompt_with_env 'Azure OpenAI API Key' 'AZURE_OPENAI_API_KEY' 'true')"
        AZURE_OPENAI_ENDPOINT="$(prompt_with_env 'Azure OpenAI Endpoint' 'AZURE_OPENAI_ENDPOINT' 'false')"
        AZURE_OPENAI_API_VERSION="$(prompt_with_env 'Azure OpenAI API Version' 'AZURE_OPENAI_API_VERSION' 'false')"
        AZURE_OPENAI_DEPLOYMENT="$(prompt_with_env 'Azure OpenAI Deployment Name' 'AZURE_OPENAI_DEPLOYMENT' 'false')"
        ;;
    "openai")
        echo ""
        OPENAI_API_KEY="$(prompt_with_env 'OpenAI API Key' 'OPENAI_API_KEY' 'true')"
        OPENAI_ENDPOINT="$(prompt_with_env 'OpenAI Endpoint' 'OPENAI_ENDPOINT' 'false')"
        OPENAI_MODEL_NAME="$(prompt_with_env 'OpenAI Model Name' 'OPENAI_MODEL_NAME' 'false')"
        ;;
    "aws-bedrock")
        echo ""
        AWS_ACCESS_KEY_ID="$(prompt_with_env 'AWS Access Key ID' 'AWS_ACCESS_KEY_ID' 'false')"
        AWS_SECRET_ACCESS_KEY="$(prompt_with_env 'AWS Secret Access Key' 'AWS_SECRET_ACCESS_KEY' 'true')"
        AWS_REGION="$(prompt_with_env 'AWS Region' 'AWS_REGION' 'false')"
        AWS_BEDROCK_MODEL_ID="$(prompt_with_env 'AWS Bedrock Model ID' 'AWS_BEDROCK_MODEL_ID' 'false')"
        AWS_BEDROCK_PROVIDER="$(prompt_with_env 'AWS Bedrock Provider' 'AWS_BEDROCK_PROVIDER' 'false')"
        ;;
    "google-gemini")
        echo ""
        GOOGLE_API_KEY="$(prompt_with_env 'Google API Key' 'GOOGLE_API_KEY' 'true')"
        GOOGLE_MODEL_NAME="$(prompt_with_env 'Google Model Name' 'GOOGLE_MODEL_NAME' 'false')"
        ;;
    "gcp-vertex")
        echo ""
        GCP_PROJECT_ID="$(prompt_with_env 'GCP Project ID' 'GCP_PROJECT_ID' 'false')"
        GCP_LOCATION="$(prompt_with_env 'GCP Location' 'GCP_LOCATION' 'false')"
        GCP_MODEL_NAME="$(prompt_with_env 'GCP Model Name' 'GCP_MODEL_NAME' 'false')"
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
