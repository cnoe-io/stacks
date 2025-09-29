#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check dependencies
for cmd in kubectl vault jq; do
    if ! command -v $cmd &> /dev/null; then
        log "❌ $cmd is required but not installed"
        exit 1
    fi
done

log "🔧 Setting up LLM credentials and agent secrets"

# Load environment variables from .env files
load_env_file() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        log "📄 Loading environment variables from $env_file"
        # Export variables from .env file, ignoring comments and empty lines
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Export the variable
            if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                export "$line"
            fi
        done < "$env_file"
        return 0
    fi
    return 1
}

# Check for .env files in home directory and current directory
ENV_LOADED=false
if load_env_file "$HOME/.env"; then
    ENV_LOADED=true
fi
if load_env_file ".env"; then
    ENV_LOADED=true
fi

if [[ "$ENV_LOADED" == "true" ]]; then
    log "✅ Environment variables loaded from .env file(s)"

    # Show which variables are available from .env
    log "📋 Available variables from .env:"
    for var in GITHUB_PERSONAL_ACCESS_TOKEN ATLASSIAN_TOKEN ATLASSIAN_API_URL ATLASSIAN_EMAIL ATLASSIAN_VERIFY_SSL \
               SLACK_BOT_TOKEN SLACK_TOKEN SLACK_APP_TOKEN SLACK_SIGNING_SECRET SLACK_CLIENT_SECRET SLACK_TEAM_ID \
               AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION ARGOCD_TOKEN ARGOCD_API_URL ARGOCD_VERIFY_SSL \
               BACKSTAGE_API_TOKEN BACKSTAGE_URL PAGERDUTY_API_KEY PAGERDUTY_API_URL CONFLUENCE_API_URL \
               SPLUNK_TOKEN SPLUNK_API_URL WEBEX_TOKEN KOMODOR_TOKEN KOMODOR_API_URL \
               AZURE_OPENAI_API_KEY AZURE_OPENAI_ENDPOINT AZURE_OPENAI_DEPLOYMENT AZURE_OPENAI_API_VERSION \
               OPENAI_API_KEY OPENAI_ENDPOINT OPENAI_MODEL_NAME AWS_BEDROCK_MODEL_ID AWS_BEDROCK_PROVIDER \
               GOOGLE_API_KEY GOOGLE_MODEL_NAME GCP_PROJECT_ID GCP_LOCATION GCP_MODEL_NAME; do
        if [[ -n "${!var}" ]]; then
            if [[ "$var" =~ (TOKEN|KEY|SECRET) ]]; then
                log "  🔐 $var: ${!var:0:8}..."
            else
                log "  📝 $var: ${!var}"
            fi
        fi
    done
    echo ""
else
    log "ℹ️  No .env files found, will prompt for all values"
fi

# Setup Vault connection
VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN

# Start port forward
log "🔗 Starting Vault port forward..."
kubectl port-forward -n vault svc/vault 8200:8200 &
VAULT_PID=$!
sleep 3

# Single-line, exact-byte prompt helper (no newline added, no stripping)
# Usage: prompt_with_env "<Prompt>" VAR_NAME is_secret
prompt_with_env() {
  local prompt="$1" var_name="$2" is_secret="$3"
  local env_value="${!var_name}" result

  if [[ -n "$env_value" ]]; then
    if [[ "$is_secret" == "true" ]]; then
      local hint="${env_value:0:5}..."
      printf "%s (from .env: %s) [Enter to use, type new]: " "$prompt" "$hint" > /dev/tty
      IFS= read -r choice < /dev/tty
      if [[ -z "$choice" ]]; then
        result="$env_value"
        printf "✅ Using value from .env file\n" > /dev/tty
      else
        IFS= read -rs -p "$prompt: " result < /dev/tty
        printf "\n" > /dev/tty
      fi
    else
      IFS= read -r -p "$prompt (from .env: $env_value) [Enter to use, type new]: " choice < /dev/tty
      if [[ -z "$choice" ]]; then
        result="$env_value"
        printf "✅ Using value from .env file\n" > /dev/tty
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

  # Output EXACTLY the bytes, no newline
  printf '%s' "$result"
}

# Check which agents are active
log "🔍 Checking active agents..."
active_agents=()

# Check for GitHub agent (look for GitHub-related deployments or configs)
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-github 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i github >/dev/null 2>&1; then
    active_agents+=("github")
    log "✅ GitHub agent detected"
fi

# Check for GitLab agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-gitlab 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i gitlab >/dev/null 2>&1; then
    active_agents+=("gitlab")
    log "✅ GitLab agent detected"
fi

# Check for Jira agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-jira 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i jira >/dev/null 2>&1; then
    active_agents+=("jira")
    log "✅ Jira agent detected"
fi

# Check for Slack agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-slack 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i slack >/dev/null 2>&1; then
    active_agents+=("slack")
    log "✅ Slack agent detected"
fi

# Check for AWS agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-aws 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i aws >/dev/null 2>&1; then
    active_agents+=("aws")
    log "✅ AWS agent detected"
fi

# Check for ArgoCD agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-argocd 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i argocd >/dev/null 2>&1; then
    active_agents+=("argocd")
    log "✅ ArgoCD agent detected"
fi

# Check for Backstage agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-backstage 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i backstage >/dev/null 2>&1; then
    active_agents+=("backstage")
    log "✅ Backstage agent detected"
fi

# Check for PagerDuty agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-pagerduty 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i pagerduty >/dev/null 2>&1; then
    active_agents+=("pagerduty")
    log "✅ PagerDuty agent detected"
fi

# Check for Confluence agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-confluence 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i confluence >/dev/null 2>&1; then
    active_agents+=("confluence")
    log "✅ Confluence agent detected"
fi

# Check for Splunk agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-splunk 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i splunk >/dev/null 2>&1; then
    active_agents+=("splunk")
    log "✅ Splunk agent detected"
fi

# Check for Webex agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-webex 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i webex >/dev/null 2>&1; then
    active_agents+=("webex")
    log "✅ Webex agent detected"
fi

# Check for Komodor agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-komodor 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i komodor >/dev/null 2>&1; then
    active_agents+=("komodor")
    log "✅ Komodor agent detected"
fi

# If no agents detected, ask user to select
if [[ ${#active_agents[@]} -eq 0 ]]; then
    log "🤔 No active agents detected. Please select which agents to configure:"
    echo ""
    echo "Available agents:"
    echo "1) GitHub"
    echo "2) Jira"
    echo "3) Slack"
    echo "4) AWS"
    echo "5) ArgoCD"
    echo "6) Backstage"
    echo "7) PagerDuty"
    echo "8) Confluence"
    echo "9) Splunk"
    echo "10) Webex"
    echo "11) Komodor"
    echo "12) All of the above"
    echo ""
    read -p "Select agents (comma-separated numbers, e.g., 1,3,4): " agent_selection

    IFS=',' read -ra selected <<< "$agent_selection"
    for choice in "${selected[@]}"; do
        case $choice in
            1) active_agents+=("github") ;;
            2) active_agents+=("jira") ;;
            3) active_agents+=("slack") ;;
            4) active_agents+=("aws") ;;
            5) active_agents+=("argocd") ;;
            6) active_agents+=("backstage") ;;
            7) active_agents+=("pagerduty") ;;
            8) active_agents+=("confluence") ;;
            9) active_agents+=("splunk") ;;
            10) active_agents+=("webex") ;;
            11) active_agents+=("komodor") ;;
            12) active_agents=("github" "jira" "slack" "aws" "argocd" "backstage" "pagerduty" "confluence" "splunk" "webex" "komodor") ;;
        esac
    done
fi

log "📝 Configuring secrets for agents: ${active_agents[*]}"
echo ""

# Prompt for LLM provider (only if not already set from .env)
if [[ -z "$LLM_PROVIDER" ]]; then
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
else
    # Validate LLM_PROVIDER from .env
    case $LLM_PROVIDER in
        "azure-openai"|"openai"|"aws-bedrock"|"google-gemini"|"gcp-vertex")
            log "📝 Using LLM provider from .env: $LLM_PROVIDER"
            ;;
        *)
            log "❌ Invalid LLM_PROVIDER from .env: $LLM_PROVIDER"
            log "Supported providers: azure-openai, openai, aws-bedrock, google-gemini, gcp-vertex"
            kill $VAULT_PID 2>/dev/null
            exit 1
            ;;
    esac
fi
echo ""
log "🔒 Note: Sensitive credentials will not be displayed on screen"

# Initialize all fields as empty
GITHUB_PERSONAL_ACCESS_TOKEN=""
ATLASSIAN_TOKEN=""
ATLASSIAN_API_URL=""
ATLASSIAN_EMAIL=""
ATLASSIAN_VERIFY_SSL=""
SLACK_BOT_TOKEN=""
SLACK_TOKEN=""
SLACK_APP_TOKEN=""
SLACK_SIGNING_SECRET=""
SLACK_CLIENT_SECRET=""
SLACK_TEAM_ID=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_REGION=""
ARGOCD_TOKEN=""
ARGOCD_API_URL=""
ARGOCD_VERIFY_SSL=""
BACKSTAGE_API_TOKEN=""
BACKSTAGE_URL=""
PAGERDUTY_API_URL=""
PAGERDUTY_API_KEY=""
CONFLUENCE_API_URL=""
SPLUNK_API_URL=""
SPLUNK_TOKEN=""
WEBEX_TOKEN=""
KOMODOR_TOKEN=""
KOMODOR_API_URL=""
AZURE_OPENAI_API_KEY=""
AZURE_OPENAI_ENDPOINT=""
AZURE_OPENAI_DEPLOYMENT=""
AZURE_OPENAI_API_VERSION=""
OPENAI_API_KEY=""
OPENAI_ENDPOINT=""
OPENAI_MODEL_NAME=""
AWS_BEDROCK_MODEL_ID=""
AWS_BEDROCK_PROVIDER=""
GOOGLE_API_KEY=""
GOOGLE_MODEL_NAME=""
GCP_PROJECT_ID=""
GCP_LOCATION=""
GCP_MODEL_NAME=""

# Collect LLM credentials based on provider
log "🤖 Configuring LLM credentials..."
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

# Collect credentials based on active agents
for agent in "${active_agents[@]}"; do
    case $agent in
        "github")
            echo ""
            log "🐙 Configuring GitHub agent secrets..."
            GITHUB_PERSONAL_ACCESS_TOKEN="$(prompt_with_env 'GitHub Personal Access Token' 'GITHUB_PERSONAL_ACCESS_TOKEN' 'true')"
            ;;
        "jira")
            echo ""
            log "🎫 Configuring Jira agent secrets..."
            ATLASSIAN_TOKEN=$(prompt_with_env "Atlassian API Token" "ATLASSIAN_TOKEN" "true")
            ATLASSIAN_API_URL=$(prompt_with_env "Atlassian API URL (e.g., https://company.atlassian.net)" "ATLASSIAN_API_URL" "false")
            ATLASSIAN_EMAIL=$(prompt_with_env "Atlassian Email" "ATLASSIAN_EMAIL" "false")
            ATLASSIAN_VERIFY_SSL=$(prompt_with_env "Verify SSL (true/false)" "ATLASSIAN_VERIFY_SSL" "false" "true")
            ;;
        "slack")
            echo ""
            log "💬 Configuring Slack agent secrets..."
            SLACK_BOT_TOKEN=$(prompt_with_env "Slack Bot Token (xoxb-...)" "SLACK_BOT_TOKEN" "true")
            SLACK_TOKEN=$(prompt_with_env "Slack Token" "SLACK_TOKEN" "true")
            SLACK_APP_TOKEN=$(prompt_with_env "Slack App Token (xapp-...)" "SLACK_APP_TOKEN" "true")
            SLACK_SIGNING_SECRET=$(prompt_with_env "Slack Signing Secret" "SLACK_SIGNING_SECRET" "true")
            SLACK_CLIENT_SECRET=$(prompt_with_env "Slack Client Secret" "SLACK_CLIENT_SECRET" "true")
            SLACK_TEAM_ID=$(prompt_with_env "Slack Team ID" "SLACK_TEAM_ID" "false")
            ;;
        "aws")
            echo ""
            log "☁️  Configuring AWS agent secrets..."
            # Only prompt for AWS credentials if not already collected for LLM
            if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
                AWS_ACCESS_KEY_ID=$(prompt_with_env "AWS Access Key ID" "AWS_ACCESS_KEY_ID" "false")
                AWS_SECRET_ACCESS_KEY=$(prompt_with_env "AWS Secret Access Key" "AWS_SECRET_ACCESS_KEY" "true")
                AWS_REGION=$(prompt_with_env "AWS Region" "AWS_REGION" "false" "us-east-1")
            else
                log "✅ AWS credentials already collected for LLM provider"
            fi
            ;;
        "argocd")
            echo ""
            log "🚀 Populating ArgoCD secrets with local ArgoCD set up and grab following values:"
            log "1. ARGOCD_TOKEN will be from k8s secret argocd-admin-token in namespace vault, key: token"
            log "2. ARGOCD_API_URL will be from the same k8s secret but key: apiUrl"
            log "3. ARGOCD_VERIFY_SSL set to 'false'"

            # Get ArgoCD token from Kubernetes secret
            ARGOCD_TOKEN=$(kubectl get secret -n vault argocd-admin-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [[ -z "$ARGOCD_TOKEN" ]]; then
                log "⚠️  Could not retrieve ARGOCD_TOKEN from secret argocd-admin-token in vault namespace"
            else
                log "✅ ARGOCD_TOKEN retrieved from Kubernetes secret"
            fi

            # Get ArgoCD API URL from Kubernetes secret
            ARGOCD_API_URL=$(kubectl get secret -n vault argocd-admin-token -o jsonpath='{.data.apiUrl}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [[ -z "$ARGOCD_API_URL" ]]; then
                log "⚠️  Could not retrieve ARGOCD_API_URL from secret argocd-admin-token in vault namespace"
                ARGOCD_API_URL="http://argocd-server.argocd.svc.cluster.local"
                log "📝 Using default ARGOCD_API_URL: $ARGOCD_API_URL"
            else
                log "✅ ARGOCD_API_URL retrieved from Kubernetes secret: $ARGOCD_API_URL"
            fi

            # Set ArgoCD SSL verification to false
            ARGOCD_VERIFY_SSL="false"
            log "✅ ARGOCD_VERIFY_SSL set to: $ARGOCD_VERIFY_SSL"
            ;;
        "backstage")
            echo ""
            log "🎭 Populating Backstage secrets with local Backstage set up and grab following values:"
            log "1. BACKSTAGE_API_TOKEN from k8s secret backstage-auth-secrets in namespace backstage, key: AUTH_API_TOKEN_TEST"
            log "2. BACKSTAGE_URL set to http://backstage.backstage.svc.cluster.local:7007"

            # Get Backstage API token from Kubernetes secret
            BACKSTAGE_API_TOKEN=$(kubectl get secret -n backstage backstage-auth-secrets -o jsonpath='{.data.AUTH_API_TOKEN_TEST}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            if [[ -z "$BACKSTAGE_API_TOKEN" ]]; then
                log "⚠️  Could not retrieve BACKSTAGE_API_TOKEN from secret backstage-auth-secrets in backstage namespace"
            else
                log "✅ BACKSTAGE_API_TOKEN retrieved from Kubernetes secret"
            fi

            # Set Backstage URL
            BACKSTAGE_URL="http://backstage.backstage.svc.cluster.local:7007"
            log "✅ BACKSTAGE_URL set to: $BACKSTAGE_URL"
            ;;
        "pagerduty")
            echo ""
            log "📟 Configuring PagerDuty agent secrets..."
            PAGERDUTY_API_KEY=$(prompt_with_env "PagerDuty API Key" "PAGERDUTY_API_KEY" "true")
            PAGERDUTY_API_URL=$(prompt_with_env "PagerDuty API URL" "PAGERDUTY_API_URL" "false" "https://api.pagerduty.com")
            ;;
        "confluence")
            echo ""
            log "📚 Configuring Confluence agent secrets..."
            CONFLUENCE_API_URL=$(prompt_with_env "Confluence API URL (e.g., https://company.atlassian.net/wiki)" "CONFLUENCE_API_URL" "false")
            if [[ -z "$ATLASSIAN_TOKEN" ]]; then
                ATLASSIAN_TOKEN=$(prompt_with_env "Atlassian API Token" "ATLASSIAN_TOKEN" "true")
                ATLASSIAN_EMAIL=$(prompt_with_env "Atlassian Email" "ATLASSIAN_EMAIL" "false")
                ATLASSIAN_VERIFY_SSL=$(prompt_with_env "Verify SSL (true/false)" "ATLASSIAN_VERIFY_SSL" "false" "true")
            fi
            ;;
        "splunk")
            echo ""
            log "🔍 Configuring Splunk agent secrets..."
            SPLUNK_TOKEN=$(prompt_with_env "Splunk Token" "SPLUNK_TOKEN" "true")
            SPLUNK_API_URL=$(prompt_with_env "Splunk API URL (e.g., https://splunk.company.com)" "SPLUNK_API_URL" "false")
            ;;
        "webex")
            echo ""
            log "📹 Configuring Webex agent secrets..."
            WEBEX_TOKEN=$(prompt_with_env "Webex Token" "WEBEX_TOKEN" "true")
            ;;
        "komodor")
            echo ""
            log "🔧 Configuring Komodor agent secrets..."
            KOMODOR_TOKEN=$(prompt_with_env "Komodor Token" "KOMODOR_TOKEN" "true")
            KOMODOR_API_URL=$(prompt_with_env "Komodor API URL" "KOMODOR_API_URL" "false" "https://api.komodor.com")
            ;;
    esac
done

# Store all secrets in Vault
log "💾 Storing secrets in Vault..."

# Store global LLM credentials
log "🤖 Storing global LLM credentials in Vault..."
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
log "✅ Global LLM credentials stored"

# Store secrets individually for each active agent
for agent in "${active_agents[@]}"; do
    case $agent in
        "github")
            if [[ -n "$GITHUB_PERSONAL_ACCESS_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/github-secret \
                    GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN" >/dev/null
                log "✅ GitHub secrets stored"
            fi
            ;;
        "jira")
            if [[ -n "$ATLASSIAN_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/jira-secret \
                    ATLASSIAN_TOKEN="$ATLASSIAN_TOKEN" \
                    ATLASSIAN_API_URL="$ATLASSIAN_API_URL" \
                    ATLASSIAN_EMAIL="$ATLASSIAN_EMAIL" \
                    ATLASSIAN_VERIFY_SSL="$ATLASSIAN_VERIFY_SSL" >/dev/null
                log "✅ Jira secrets stored"
            fi
            ;;
        "slack")
            if [[ -n "$SLACK_BOT_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/slack-secret \
                    SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
                    SLACK_TOKEN="$SLACK_TOKEN" \
                    SLACK_APP_TOKEN="$SLACK_APP_TOKEN" \
                    SLACK_SIGNING_SECRET="$SLACK_SIGNING_SECRET" \
                    SLACK_CLIENT_SECRET="$SLACK_CLIENT_SECRET" \
                    SLACK_TEAM_ID="$SLACK_TEAM_ID" >/dev/null
                log "✅ Slack secrets stored"
            fi
            ;;
        "aws")
            if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
                vault kv put secret/ai-platform-engineering/aws-secret \
                    AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
                    AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
                    AWS_REGION="$AWS_REGION" >/dev/null
                log "✅ AWS secrets stored"
            fi
            ;;
        "argocd")
            if [[ -n "$ARGOCD_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/argocd-secret \
                    ARGOCD_TOKEN="$ARGOCD_TOKEN" \
                    ARGOCD_API_URL="$ARGOCD_API_URL" \
                    ARGOCD_VERIFY_SSL="$ARGOCD_VERIFY_SSL" >/dev/null
                log "✅ ArgoCD secrets stored"
            fi
            ;;
        "backstage")
            if [[ -n "$BACKSTAGE_API_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/backstage-secret \
                    BACKSTAGE_API_TOKEN="$BACKSTAGE_API_TOKEN" \
                    BACKSTAGE_URL="$BACKSTAGE_URL" >/dev/null
                log "✅ Backstage secrets stored"
            fi
            ;;
        "pagerduty")
            if [[ -n "$PAGERDUTY_API_KEY" ]]; then
                vault kv put secret/ai-platform-engineering/pagerduty-secret \
                    PAGERDUTY_API_KEY="$PAGERDUTY_API_KEY" \
                    PAGERDUTY_API_URL="$PAGERDUTY_API_URL" >/dev/null
                log "✅ PagerDuty secrets stored"
            fi
            ;;
        "confluence")
            if [[ -n "$CONFLUENCE_API_URL" ]]; then
                vault kv put secret/ai-platform-engineering/confluence-secret \
                    CONFLUENCE_API_URL="$CONFLUENCE_API_URL" \
                    ATLASSIAN_TOKEN="$ATLASSIAN_TOKEN" \
                    ATLASSIAN_EMAIL="$ATLASSIAN_EMAIL" \
                    ATLASSIAN_VERIFY_SSL="$ATLASSIAN_VERIFY_SSL" >/dev/null
                log "✅ Confluence secrets stored"
            fi
            ;;
        "splunk")
            if [[ -n "$SPLUNK_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/splunk-secret \
                    SPLUNK_TOKEN="$SPLUNK_TOKEN" \
                    SPLUNK_API_URL="$SPLUNK_API_URL" >/dev/null
                log "✅ Splunk secrets stored"
            fi
            ;;
        "webex")
            if [[ -n "$WEBEX_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/webex-secret \
                    WEBEX_TOKEN="$WEBEX_TOKEN" >/dev/null
                log "✅ Webex secrets stored"
            fi
            ;;
        "komodor")
            if [[ -n "$KOMODOR_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/komodor-secret \
                    KOMODOR_TOKEN="$KOMODOR_TOKEN" \
                    KOMODOR_API_URL="$KOMODOR_API_URL" >/dev/null
                log "✅ Komodor secrets stored"
            fi
            ;;
    esac
done

log "✅ Agent secrets successfully stored in Vault"
echo ""
log "🔍 You can verify individual agent secrets at:"
for agent in "${active_agents[@]}"; do
    case $agent in
        "github") log "  🐙 GitHub: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fgithub-secret" ;;
        "jira") log "  🎫 Jira: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fjira-secret" ;;
        "slack") log "  💬 Slack: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fslack-secret" ;;
        "aws") log "  ☁️  AWS: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Faws-secret" ;;
        "argocd") log "  🚀 ArgoCD: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fargocd-secret" ;;
        "backstage") log "  🎭 Backstage: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fbackstage-secret" ;;
        "pagerduty") log "  📟 PagerDuty: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fpagerduty-secret" ;;
        "confluence") log "  📚 Confluence: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fconfluence-secret" ;;
        "splunk") log "  🔍 Splunk: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fsplunk-secret" ;;
        "webex") log "  📹 Webex: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fwebex-secret" ;;
        "komodor") log "  🔧 Komodor: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fkomodor-secret" ;;
    esac
done
log "  🤖 Global LLM: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fglobal"

# Create Kubernetes secret for agents
log "🔄 Creating Kubernetes secret for agents..."
kubectl create secret generic agent-secrets -n ai-platform-engineering \
    --from-literal=GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN" \
    --from-literal=ATLASSIAN_TOKEN="$ATLASSIAN_TOKEN" \
    --from-literal=ATLASSIAN_API_URL="$ATLASSIAN_API_URL" \
    --from-literal=ATLASSIAN_EMAIL="$ATLASSIAN_EMAIL" \
    --from-literal=ATLASSIAN_VERIFY_SSL="$ATLASSIAN_VERIFY_SSL" \
    --from-literal=SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
    --from-literal=SLACK_TOKEN="$SLACK_TOKEN" \
    --from-literal=SLACK_APP_TOKEN="$SLACK_APP_TOKEN" \
    --from-literal=SLACK_SIGNING_SECRET="$SLACK_SIGNING_SECRET" \
    --from-literal=SLACK_CLIENT_SECRET="$SLACK_CLIENT_SECRET" \
    --from-literal=SLACK_TEAM_ID="$SLACK_TEAM_ID" \
    --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    --from-literal=AWS_REGION="$AWS_REGION" \
    --from-literal=ARGOCD_TOKEN="$ARGOCD_TOKEN" \
    --from-literal=ARGOCD_API_URL="$ARGOCD_API_URL" \
    --from-literal=ARGOCD_VERIFY_SSL="$ARGOCD_VERIFY_SSL" \
    --from-literal=BACKSTAGE_API_TOKEN="$BACKSTAGE_API_TOKEN" \
    --from-literal=BACKSTAGE_URL="$BACKSTAGE_URL" \
    --from-literal=PAGERDUTY_API_KEY="$PAGERDUTY_API_KEY" \
    --from-literal=PAGERDUTY_API_URL="$PAGERDUTY_API_URL" \
    --from-literal=CONFLUENCE_API_URL="$CONFLUENCE_API_URL" \
    --from-literal=SPLUNK_TOKEN="$SPLUNK_TOKEN" \
    --from-literal=SPLUNK_API_URL="$SPLUNK_API_URL" \
    --from-literal=WEBEX_TOKEN="$WEBEX_TOKEN" \
    --from-literal=KOMODOR_TOKEN="$KOMODOR_TOKEN" \
    --from-literal=KOMODOR_API_URL="$KOMODOR_API_URL" \
    --from-literal=AZURE_OPENAI_API_KEY="$AZURE_OPENAI_API_KEY" \
    --from-literal=AZURE_OPENAI_ENDPOINT="$AZURE_OPENAI_ENDPOINT" \
    --from-literal=AZURE_OPENAI_DEPLOYMENT="$AZURE_OPENAI_DEPLOYMENT" \
    --from-literal=AZURE_OPENAI_API_VERSION="$AZURE_OPENAI_API_VERSION" \
    --from-literal=OPENAI_API_KEY="$OPENAI_API_KEY" \
    --from-literal=OPENAI_ENDPOINT="$OPENAI_ENDPOINT" \
    --from-literal=OPENAI_MODEL_NAME="$OPENAI_MODEL_NAME" \
    --from-literal=AWS_BEDROCK_MODEL_ID="$AWS_BEDROCK_MODEL_ID" \
    --from-literal=AWS_BEDROCK_PROVIDER="$AWS_BEDROCK_PROVIDER" \
    --from-literal=GOOGLE_API_KEY="$GOOGLE_API_KEY" \
    --from-literal=GOOGLE_MODEL_NAME="$GOOGLE_MODEL_NAME" \
    --from-literal=GCP_PROJECT_ID="$GCP_PROJECT_ID" \
    --from-literal=GCP_LOCATION="$GCP_LOCATION" \
    --from-literal=GCP_MODEL_NAME="$GCP_MODEL_NAME" \
    --dry-run=client -o yaml | kubectl apply -f -

log "✅ Kubernetes secret created/updated"

# Summary
echo ""
log "📊 Configuration Summary:"
log "  🤖 Global LLM: $LLM_PROVIDER credentials configured"
for agent in "${active_agents[@]}"; do
    case $agent in
        "github") log "  🐙 GitHub: Personal Access Token configured" ;;
        "jira") log "  🎫 Jira: Atlassian Token and API URL configured" ;;
        "slack") log "  💬 Slack: Bot Token, App Token, and additional tokens configured" ;;
        "aws") log "  ☁️  AWS: Access Keys and Region configured" ;;
        "argocd") log "  🚀 ArgoCD: Token and API URL configured" ;;
        "backstage") log "  🎭 Backstage: API Token and URL configured" ;;
        "pagerduty") log "  📟 PagerDuty: API Key and URL configured" ;;
        "confluence") log "  📚 Confluence: API URL and Atlassian credentials configured" ;;
        "splunk") log "  🔍 Splunk: Token and API URL configured" ;;
        "webex") log "  📹 Webex: Token configured" ;;
        "komodor") log "  🔧 Komodor: Token and API URL configured" ;;
    esac
done

# Cleanup
kill $VAULT_PID 2>/dev/null
log "🎉 Combined secrets setup complete!"
