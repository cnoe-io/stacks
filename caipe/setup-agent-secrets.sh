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

# Check for ArgoCD agent
if kubectl get deployment -n ai-platform-engineering argocd-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i argocd >/dev/null 2>&1; then
    active_agents+=("argocd")
    log "✅ ArgoCD agent detected"
fi

# Check for Backstage agent
if kubectl get deployment -n ai-platform-engineering backstage-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i backstage >/dev/null 2>&1; then
    active_agents+=("backstage")
    log "✅ Backstage agent detected"
fi

# Check for PagerDuty agent
if kubectl get deployment -n ai-platform-engineering pagerduty-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i pagerduty >/dev/null 2>&1; then
    active_agents+=("pagerduty")
    log "✅ PagerDuty agent detected"
fi

# Check for Confluence agent
if kubectl get deployment -n ai-platform-engineering confluence-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i confluence >/dev/null 2>&1; then
    active_agents+=("confluence")
    log "✅ Confluence agent detected"
fi

# Check for Splunk agent
if kubectl get deployment -n ai-platform-engineering splunk-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i splunk >/dev/null 2>&1; then
    active_agents+=("splunk")
    log "✅ Splunk agent detected"
fi

# Check for Webex agent
if kubectl get deployment -n ai-platform-engineering webex-agent 2>/dev/null || \
   kubectl get configmap -n ai-platform-engineering | grep -i webex >/dev/null 2>&1; then
    active_agents+=("webex")
    log "✅ Webex agent detected"
fi

# Check for Komodor agent
if kubectl get deployment -n ai-platform-engineering komodor-agent 2>/dev/null || \
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

# Collect credentials based on active agents
for agent in "${active_agents[@]}"; do
    case $agent in
        "github")
            echo ""
            log "🐙 Configuring GitHub agent secrets..."
            GITHUB_PERSONAL_ACCESS_TOKEN=$(prompt_with_env "GitHub Personal Access Token" "GITHUB_PERSONAL_ACCESS_TOKEN" "true")
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
            ARGOCD_TOKEN=$(prompt_with_env "ArgoCD Token" "ARGOCD_TOKEN" "true")
            ARGOCD_API_URL=$(prompt_with_env "ArgoCD API URL" "ARGOCD_API_URL" "false" "http://argocd-server.argocd.svc.cluster.local")
            ARGOCD_VERIFY_SSL=$(prompt_with_env "Verify SSL (true/false)" "ARGOCD_VERIFY_SSL" "false" "false")
            ;;
        "backstage")
            echo ""
            log "🎭 Configuring Backstage agent secrets..."
            BACKSTAGE_API_TOKEN=$(prompt_with_env "Backstage API Token" "BACKSTAGE_API_TOKEN" "true")
            BACKSTAGE_URL=$(prompt_with_env "Backstage URL" "BACKSTAGE_URL" "false" "http://backstage.backstage.svc.cluster.local:7007")
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
                vault kv put secret/ai-platform-engineering/argocd-agent-secret \
                    ARGOCD_TOKEN="$ARGOCD_TOKEN" \
                    ARGOCD_API_URL="$ARGOCD_API_URL" \
                    ARGOCD_VERIFY_SSL="$ARGOCD_VERIFY_SSL" >/dev/null
                log "✅ ArgoCD secrets stored"
            fi
            ;;
        "backstage")
            if [[ -n "$BACKSTAGE_API_TOKEN" ]]; then
                vault kv put secret/ai-platform-engineering/backstage-agent-secret \
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
        "argocd") log "  🚀 ArgoCD: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fargocd-agent-secret" ;;
        "backstage") log "  🎭 Backstage: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fbackstage-agent-secret" ;;
        "pagerduty") log "  📟 PagerDuty: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fpagerduty-secret" ;;
        "confluence") log "  📚 Confluence: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fconfluence-secret" ;;
        "splunk") log "  🔍 Splunk: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fsplunk-secret" ;;
        "webex") log "  📹 Webex: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fwebex-secret" ;;
        "komodor") log "  🔧 Komodor: https://vault.cnoe.localtest.me:8443/ui/vault/secrets/secret/kv/ai-platform-engineering%2Fkomodor-secret" ;;
    esac
done

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
    --dry-run=client -o yaml | kubectl apply -f -

log "✅ Kubernetes secret created/updated"

# Summary
echo ""
log "📊 Configuration Summary:"
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
log "🎉 Agent secrets setup complete!"
