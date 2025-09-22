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

log "🔧 Setting up agent secrets based on active agents"

# Setup Vault connection
VAULT_TOKEN=$(kubectl get secret vault-root-token -n vault -o jsonpath='{.data.token}' | base64 -d)
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN

# Start port forward
log "🔗 Starting Vault port forward..."
kubectl port-forward -n vault svc/vault 8200:8200 &
VAULT_PID=$!
sleep 3

# Helper function to prompt with env var hint
prompt_with_env() {
    local prompt="$1"
    local var_name="$2"
    local is_secret="$3"
    local env_value="${!var_name}"
    local result=""
    
    # Strip newlines from env value
    if [[ -n "$env_value" ]]; then
        env_value=$(echo "$env_value" | tr -d '\n\r' | sed 's/\\n//g' | sed 's/\\r//g' | xargs)
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
        if [[ "$is_secret" == "true" ]]; then
            read -p "$prompt: " -s result
            echo ""
        else
            read -p "$prompt: " result
        fi
    fi
    # Strip newlines and whitespace from result
    result=$(echo "$result" | tr -d '\n\r' | sed 's/\\n//g' | sed 's/\\r//g' | xargs)
    echo "$result"
}

# Check which agents are active
log "🔍 Checking active agents..."
active_agents=()

# Check for GitHub agent (look for GitHub-related deployments or configs)
if kubectl get deployment -n ai-platform-engineering github-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i github >/dev/null 2>&1; then
    active_agents+=("github")
    log "✅ GitHub agent detected"
fi

# Check for GitLab agent
if kubectl get deployment -n ai-platform-engineering gitlab-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i gitlab >/dev/null 2>&1; then
    active_agents+=("gitlab")
    log "✅ GitLab agent detected"
fi

# Check for Jira agent
if kubectl get deployment -n ai-platform-engineering jira-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i jira >/dev/null 2>&1; then
    active_agents+=("jira")
    log "✅ Jira agent detected"
fi

# Check for Slack agent
if kubectl get deployment -n ai-platform-engineering slack-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i slack >/dev/null 2>&1; then
    active_agents+=("slack")
    log "✅ Slack agent detected"
fi

# Check for AWS agent
if kubectl get deployment -n ai-platform-engineering aws-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i aws >/dev/null 2>&1; then
    active_agents+=("aws")
    log "✅ AWS agent detected"
fi

# If no agents detected, ask user to select
if [[ ${#active_agents[@]} -eq 0 ]]; then
    log "🤔 No active agents detected. Please select which agents to configure:"
    echo ""
    echo "Available agents:"
    echo "1) GitHub"
    echo "2) GitLab" 
    echo "3) Jira"
    echo "4) Slack"
    echo "5) AWS"
    echo "6) All of the above"
    echo ""
    read -p "Select agents (comma-separated numbers, e.g., 1,3,4): " agent_selection
    
    IFS=',' read -ra selected <<< "$agent_selection"
    for choice in "${selected[@]}"; do
        case $choice in
            1) active_agents+=("github") ;;
            2) active_agents+=("gitlab") ;;
            3) active_agents+=("jira") ;;
            4) active_agents+=("slack") ;;
            5) active_agents+=("aws") ;;
            6) active_agents=("github" "gitlab" "jira" "slack" "aws") ;;
        esac
    done
fi

log "📝 Configuring secrets for agents: ${active_agents[*]}"
echo ""
log "🔒 Note: Sensitive credentials will not be displayed on screen"

# Initialize all fields as empty
GITHUB_PERSONAL_ACCESS_TOKEN=""
GITHUB_WEBHOOK_SECRET=""
GITLAB_PERSONAL_ACCESS_TOKEN=""
GITLAB_WEBHOOK_SECRET=""
JIRA_API_TOKEN=""
JIRA_BASE_URL=""
JIRA_USERNAME=""
SLACK_BOT_TOKEN=""
SLACK_APP_TOKEN=""
SLACK_SIGNING_SECRET=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_REGION=""

# Collect credentials based on active agents
for agent in "${active_agents[@]}"; do
    case $agent in
        "github")
            echo ""
            log "🐙 Configuring GitHub agent secrets..."
            GITHUB_PERSONAL_ACCESS_TOKEN=$(prompt_with_env "GitHub Personal Access Token" "GITHUB_PERSONAL_ACCESS_TOKEN" "true")
            GITHUB_WEBHOOK_SECRET=$(prompt_with_env "GitHub Webhook Secret (optional)" "GITHUB_WEBHOOK_SECRET" "true")
            ;;
        "gitlab")
            echo ""
            log "🦊 Configuring GitLab agent secrets..."
            GITLAB_PERSONAL_ACCESS_TOKEN=$(prompt_with_env "GitLab Personal Access Token" "GITLAB_PERSONAL_ACCESS_TOKEN" "true")
            GITLAB_WEBHOOK_SECRET=$(prompt_with_env "GitLab Webhook Secret (optional)" "GITLAB_WEBHOOK_SECRET" "true")
            ;;
        "jira")
            echo ""
            log "🎫 Configuring Jira agent secrets..."
            JIRA_API_TOKEN=$(prompt_with_env "Jira API Token" "JIRA_API_TOKEN" "true")
            JIRA_BASE_URL=$(prompt_with_env "Jira Base URL (e.g., https://company.atlassian.net)" "JIRA_BASE_URL" "false")
            JIRA_USERNAME=$(prompt_with_env "Jira Username/Email" "JIRA_USERNAME" "false")
            ;;
        "slack")
            echo ""
            log "💬 Configuring Slack agent secrets..."
            SLACK_BOT_TOKEN=$(prompt_with_env "Slack Bot Token (xoxb-...)" "SLACK_BOT_TOKEN" "true")
            SLACK_APP_TOKEN=$(prompt_with_env "Slack App Token (xapp-...)" "SLACK_APP_TOKEN" "true")
            SLACK_SIGNING_SECRET=$(prompt_with_env "Slack Signing Secret" "SLACK_SIGNING_SECRET" "true")
            ;;
        "aws")
            echo ""
            log "☁️  Configuring AWS agent secrets..."
            AWS_ACCESS_KEY_ID=$(prompt_with_env "AWS Access Key ID" "AWS_ACCESS_KEY_ID" "false")
            AWS_SECRET_ACCESS_KEY=$(prompt_with_env "AWS Secret Access Key" "AWS_SECRET_ACCESS_KEY" "true")
            AWS_REGION=$(prompt_with_env "AWS Region" "AWS_REGION" "false" "us-east-1")
            ;;
    esac
done

# Store all secrets in Vault
log "💾 Storing agent secrets in Vault..."
vault kv put secret/ai-platform-engineering/agent-secrets \
    GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN" \
    GITHUB_WEBHOOK_SECRET="$GITHUB_WEBHOOK_SECRET" \
    GITLAB_PERSONAL_ACCESS_TOKEN="$GITLAB_PERSONAL_ACCESS_TOKEN" \
    GITLAB_WEBHOOK_SECRET="$GITLAB_WEBHOOK_SECRET" \
    JIRA_API_TOKEN="$JIRA_API_TOKEN" \
    JIRA_BASE_URL="$JIRA_BASE_URL" \
    JIRA_USERNAME="$JIRA_USERNAME" \
    SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
    SLACK_APP_TOKEN="$SLACK_APP_TOKEN" \
    SLACK_SIGNING_SECRET="$SLACK_SIGNING_SECRET" \
    AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    AWS_REGION="$AWS_REGION" >/dev/null

log "✅ Agent secrets successfully stored in Vault"
log "🔍 You can verify at: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fagent-secrets"

# Create Kubernetes secret for agents
log "🔄 Creating Kubernetes secret for agents..."
kubectl create secret generic agent-secrets -n ai-platform-engineering \
    --from-literal=GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN" \
    --from-literal=GITHUB_WEBHOOK_SECRET="$GITHUB_WEBHOOK_SECRET" \
    --from-literal=GITLAB_PERSONAL_ACCESS_TOKEN="$GITLAB_PERSONAL_ACCESS_TOKEN" \
    --from-literal=GITLAB_WEBHOOK_SECRET="$GITLAB_WEBHOOK_SECRET" \
    --from-literal=JIRA_API_TOKEN="$JIRA_API_TOKEN" \
    --from-literal=JIRA_BASE_URL="$JIRA_BASE_URL" \
    --from-literal=JIRA_USERNAME="$JIRA_USERNAME" \
    --from-literal=SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
    --from-literal=SLACK_APP_TOKEN="$SLACK_APP_TOKEN" \
    --from-literal=SLACK_SIGNING_SECRET="$SLACK_SIGNING_SECRET" \
    --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    --from-literal=AWS_REGION="$AWS_REGION" \
    --dry-run=client -o yaml | kubectl apply -f -

log "✅ Kubernetes secret created/updated"

# Summary
echo ""
log "📊 Configuration Summary:"
for agent in "${active_agents[@]}"; do
    case $agent in
        "github") log "  🐙 GitHub: Personal Access Token configured" ;;
        "gitlab") log "  🦊 GitLab: Personal Access Token configured" ;;
        "jira") log "  🎫 Jira: API Token and Base URL configured" ;;
        "slack") log "  💬 Slack: Bot Token and App Token configured" ;;
        "aws") log "  ☁️  AWS: Access Keys and Region configured" ;;
    esac
done

# Cleanup
kill $VAULT_PID 2>/dev/null
log "🎉 Agent secrets setup complete!"
