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

# Parse command line arguments
OVERRIDE_ALL=false
ENV_FILE=""
auto_populated_vars=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --override-all)
            OVERRIDE_ALL=true
            shift
            ;;
        --envFile)
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--override-all] [--envFile <path>]"
            echo ""
            echo "Options:"
            echo "  --override-all       Prompt for ArgoCD and Backstage secrets even if they exist"
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
                            # log "  ✓ Loaded $var_name from env file"
                        fi
                    fi
                fi
            done < "$env_file"
        else
            # log "⚠️  Environment file not found: $env_file"
            exit 1
        fi
    fi
}

log "🔧 Setting up agent secrets based on active agents"

# Setup Vault connection
VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN

# Start port forward
log "🔗 Starting Vault port forward..."
kubectl port-forward -n vault svc/vault 8200:8200 > /dev/null 2>&1 &
VAULT_PID=$!
sleep 3

# Single-line, exact-byte prompt helper (no newline added, no stripping)
# Usage: prompt_with_env "<Prompt>" VAR_NAME is_secret [default_value]
prompt_with_env() {
  local prompt="$1" var_name="$2" is_secret="$3" default_value="$4"
  local env_value="${!var_name}" result

  # If we have an env file and the variable has a value, auto-populate
  if [[ -n "$ENV_FILE" && -n "$env_value" ]]; then
    auto_populated_vars+=("$var_name")
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

# Helper function to fetch existing secrets from Vault
# Usage: fetch_vault_secret "<vault_path>" "<field_name>"
fetch_vault_secret() {
  local vault_path="$1" field_name="$2"
  local value

  # Try to fetch the secret, suppress errors if it doesn't exist
  value=$(vault kv get -field="$field_name" "$vault_path" >/dev/null || echo "")
  printf '%s' "$value"
}

# Helper function to confirm override when value exists
# Usage: confirm_override "<field_description>"
# Returns: 0 if user wants to override, 1 if not
confirm_override() {
  local field_desc="$1"
  local choice

  printf "%s is already populated. Are you sure you want to override? (Y/N): " "$field_desc" > /dev/tty
  IFS= read -r choice < /dev/tty

  case "${choice,,}" in  # Convert to lowercase
    y|yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Check which agents are active
log "🔍 Checking active agents..."
active_agents=()

# Check for GitHub agent (look for GitHub-related deployments or configs)
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-github >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i github >/dev/null 2>&1; then
    active_agents+=("github")
    # log "✅ GitHub agent detected"
fi

# Check for GitLab agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-gitlab >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i gitlab >/dev/null 2>&1; then
    active_agents+=("gitlab")
    # log "✅ GitLab agent detected"
fi

# Check for Jira agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-jira >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i jira >/dev/null 2>&1; then
    active_agents+=("jira")
    # log "✅ Jira agent detected"
fi

# Check for Slack agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-slack >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i slack >/dev/null 2>&1; then
    active_agents+=("slack")
    # log "✅ Slack agent detected"
fi

# Check for AWS agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-aws >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i aws >/dev/null 2>&1; then
    active_agents+=("aws")
    # log "✅ AWS agent detected"
fi

# Check for ArgoCD agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-argocd >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i argocd >/dev/null 2>&1; then
    active_agents+=("argocd")
    # log "✅ ArgoCD agent detected"
fi

# Check for Backstage agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-backstage >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i backstage >/dev/null 2>&1; then
    active_agents+=("backstage")
    # log "✅ Backstage agent detected"
fi

# Check for PagerDuty agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-pagerduty >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i pagerduty >/dev/null 2>&1; then
    active_agents+=("pagerduty")
    # log "✅ PagerDuty agent detected"
fi

# Check for Confluence agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-confluence >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i confluence >/dev/null 2>&1; then
    active_agents+=("confluence")
    # log "✅ Confluence agent detected"
fi

# Check for Splunk agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-splunk >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i splunk >/dev/null 2>&1; then
    active_agents+=("splunk")
    # log "✅ Splunk agent detected"
fi

# Check for Webex agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-webex >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i webex >/dev/null 2>&1; then
    active_agents+=("webex")
    # log "✅ Webex agent detected"
fi

# Check for Komodor agent
if kubectl get deployment -n ai-platform-engineering ai-platform-engineering-agent-komodor >/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i komodor >/dev/null 2>&1; then
    active_agents+=("komodor")
    # log "✅ Komodor agent detected"
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

# Load environment file if specified (after initialization)
load_env_file "$ENV_FILE"

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
            AWS_ACCESS_KEY_ID=$(prompt_with_env "AWS Access Key ID" "AWS_ACCESS_KEY_ID" "false")
            AWS_SECRET_ACCESS_KEY=$(prompt_with_env "AWS Secret Access Key" "AWS_SECRET_ACCESS_KEY" "true")
            AWS_REGION=$(prompt_with_env "AWS Region" "AWS_REGION" "false" "us-east-1")
            ;;
        "argocd")
            echo ""
            log "🚀 Configuring ArgoCD agent secrets..."

            # Try to fetch existing secrets from Vault first
            existing_token=$(fetch_vault_secret "secret/ai-platform-engineering/argocd-secret" "ARGOCD_TOKEN")
            existing_api_url=$(fetch_vault_secret "secret/ai-platform-engineering/argocd-secret" "ARGOCD_API_URL")
            existing_verify_ssl=$(fetch_vault_secret "secret/ai-platform-engineering/argocd-secret" "ARGOCD_VERIFY_SSL")

            # Handle ArgoCD Token
            should_prompt_token=false
            if [[ -z "$existing_token" ]]; then
                should_prompt_token=true
            elif [[ "$OVERRIDE_ALL" == "true" ]]; then
                # Check if we have env file value and should use it
                if [[ -n "$ENV_FILE" && -n "${ARGOCD_TOKEN:-}" ]]; then
                    log "  Using ArgoCD Token from env file (override-all mode)"
                    # Value already loaded from env file
                else
                    if confirm_override "ArgoCD Token"; then
                        should_prompt_token=true
                    else
                        log "  Keeping existing ArgoCD Token from Vault"
                        ARGOCD_TOKEN="$existing_token"
                    fi
                fi
            else
                log "  Using existing ArgoCD Token from Vault"
                ARGOCD_TOKEN="$existing_token"
            fi

            if [[ "$should_prompt_token" == "true" ]]; then
                [[ -n "$existing_token" ]] && export ARGOCD_TOKEN="$existing_token"
                ARGOCD_TOKEN=$(prompt_with_env "ArgoCD Token" "ARGOCD_TOKEN" "true")
            fi

            # Handle ArgoCD API URL
            should_prompt_url=false
            if [[ -z "$existing_api_url" ]]; then
                should_prompt_url=true
            elif [[ "$OVERRIDE_ALL" == "true" ]]; then
                # Check if we have env file value and should use it
                if [[ -n "$ENV_FILE" && -n "${ARGOCD_API_URL:-}" ]]; then
                    log "  Using ArgoCD API URL from env file (override-all mode)"
                    # Value already loaded from env file
                else
                    if confirm_override "ArgoCD API URL"; then
                        should_prompt_url=true
                    else
                        log "  Keeping existing ArgoCD API URL from Vault"
                        ARGOCD_API_URL="$existing_api_url"
                    fi
                fi
            else
                log "  Using existing ArgoCD API URL from Vault"
                ARGOCD_API_URL="$existing_api_url"
            fi

            if [[ "$should_prompt_url" == "true" ]]; then
                [[ -n "$existing_api_url" ]] && export ARGOCD_API_URL="$existing_api_url"
                ARGOCD_API_URL=$(prompt_with_env "ArgoCD API URL" "ARGOCD_API_URL" "false")
                [[ -z "$ARGOCD_API_URL" ]] && ARGOCD_API_URL="http://argocd-server.argocd.svc.cluster.local"
            fi

            # Handle ArgoCD Verify SSL
            should_prompt_ssl=false
            if [[ -z "$existing_verify_ssl" ]]; then
                should_prompt_ssl=true
            elif [[ "$OVERRIDE_ALL" == "true" ]]; then
                # Check if we have env file value and should use it
                if [[ -n "$ENV_FILE" && -n "${ARGOCD_VERIFY_SSL:-}" ]]; then
                    log "  Using ArgoCD Verify SSL setting from env file (override-all mode)"
                    # Value already loaded from env file
                else
                    if confirm_override "ArgoCD Verify SSL setting"; then
                        should_prompt_ssl=true
                    else
                        log "  Keeping existing ArgoCD Verify SSL setting from Vault"
                        ARGOCD_VERIFY_SSL="$existing_verify_ssl"
                    fi
                fi
            else
                log "  Using existing ArgoCD Verify SSL setting from Vault"
                ARGOCD_VERIFY_SSL="$existing_verify_ssl"
            fi

            if [[ "$should_prompt_ssl" == "true" ]]; then
                [[ -n "$existing_verify_ssl" ]] && export ARGOCD_VERIFY_SSL="$existing_verify_ssl"
                ARGOCD_VERIFY_SSL=$(prompt_with_env "Verify SSL (true/false)" "ARGOCD_VERIFY_SSL" "false")
                [[ -z "$ARGOCD_VERIFY_SSL" ]] && ARGOCD_VERIFY_SSL="false"
            fi
            ;;
        "backstage")
            echo ""
            log "🎭 Configuring Backstage agent secrets..."

            # Try to fetch existing secrets from Vault first
            existing_api_token=$(fetch_vault_secret "secret/ai-platform-engineering/backstage-secret" "BACKSTAGE_API_TOKEN")
            existing_url=$(fetch_vault_secret "secret/ai-platform-engineering/backstage-secret" "BACKSTAGE_URL")

            # Handle Backstage API Token
            should_prompt_token=false
            if [[ -z "$existing_api_token" ]]; then
                should_prompt_token=true
            elif [[ "$OVERRIDE_ALL" == "true" ]]; then
                # Check if we have env file value and should use it
                if [[ -n "$ENV_FILE" && -n "${BACKSTAGE_API_TOKEN:-}" ]]; then
                    log "  Using Backstage API Token from env file (override-all mode)"
                    # Value already loaded from env file
                else
                    if confirm_override "Backstage API Token"; then
                        should_prompt_token=true
                    else
                        log "  Keeping existing Backstage API Token from Vault"
                        BACKSTAGE_API_TOKEN="$existing_api_token"
                    fi
                fi
            else
                log "  Using existing Backstage API Token from Vault"
                BACKSTAGE_API_TOKEN="$existing_api_token"
            fi

            if [[ "$should_prompt_token" == "true" ]]; then
                [[ -n "$existing_api_token" ]] && export BACKSTAGE_API_TOKEN="$existing_api_token"
                BACKSTAGE_API_TOKEN=$(prompt_with_env "Backstage API Token" "BACKSTAGE_API_TOKEN" "true")
            fi

            # Handle Backstage URL
            should_prompt_url=false
            if [[ -z "$existing_url" ]]; then
                should_prompt_url=true
            elif [[ "$OVERRIDE_ALL" == "true" ]]; then
                # Check if we have env file value and should use it
                if [[ -n "$ENV_FILE" && -n "${BACKSTAGE_URL:-}" ]]; then
                    log "  Using Backstage URL from env file (override-all mode)"
                    # Value already loaded from env file
                else
                    if confirm_override "Backstage URL"; then
                        should_prompt_url=true
                    else
                        log "  Keeping existing Backstage URL from Vault"
                        BACKSTAGE_URL="$existing_url"
                    fi
                fi
            else
                log "  Using existing Backstage URL from Vault"
                BACKSTAGE_URL="$existing_url"
            fi

            if [[ "$should_prompt_url" == "true" ]]; then
                [[ -n "$existing_url" ]] && export BACKSTAGE_URL="$existing_url"
                BACKSTAGE_URL=$(prompt_with_env "Backstage URL" "BACKSTAGE_URL" "false")
                [[ -z "$BACKSTAGE_URL" ]] && BACKSTAGE_URL="http://backstage.backstage.svc.cluster.local:7007"
            fi
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
log "💾 Storing agent secrets in Vault..."

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
log "🔍 You can verify individual agent secrets at the Vault UI: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/list/ai-platform-engineering/"

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
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null

log "✅ Kubernetes secret created/updated"

# Summary
echo ""
if [[ ${#auto_populated_vars[@]} -gt 0 ]]; then
    log "✓ Auto-populated variables from env file: $(IFS=,; echo "${auto_populated_vars[*]}")"
    echo ""
fi
log "📊 Configuration Summary:"
log "  Configured agents: $(IFS=,; echo "${active_agents[*]}")"

# Cleanup
kill $VAULT_PID >/dev/null
log "🎉 Agent secrets setup complete!"
