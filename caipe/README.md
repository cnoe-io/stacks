# CAIPE - Cloud AI Platform Engineering

CAIPE provides AI-powered platform engineering capabilities with support for multiple LLM providers and automated secret management.

## Quick Start

### 1. Deploy CAIPE Platform

```bash
# Deploy the basic peer-to-peer configuration
./idpbuilder create --name caipe-basic-p2p \
  --use-path-routing \
  --package https://github.com/cnoe-io/stacks//ref-implementation \
  --package https://github.com/sriaradhyula/stacks//caipe/caipe-basic-p2p
```

### 2. Setup LLM Credentials

Run the interactive setup script to configure your LLM provider:

```bash
# Make the script executable
chmod +x setup-llm-credentials.sh

# Run the setup script
./setup-llm-credentials.sh
```

**Note**: The script uses clean input handling - simply type or paste your credentials and press Enter. No special key combinations needed.

The script supports the following LLM providers:

#### Azure OpenAI
- API Key
- Endpoint URL
- API Version (default: 2024-02-15-preview)
- Deployment Name

#### OpenAI
- API Key
- Endpoint (default: https://api.openai.com/v1)
- Model Name (default: gpt-4)

#### AWS Bedrock
- Access Key ID
- Secret Access Key
- Region (default: us-east-1)
- Model ID (default: anthropic.claude-3-sonnet-20240229-v1:0)
- Provider (default: anthropic)

#### Google Gemini
- API Key
- Model Name (default: gemini-pro)

#### GCP Vertex AI
- Project ID
- Location (default: us-central1)
- Model Name (default: gemini-pro)

### 3. Setup Agent Secrets

Configure API keys and tokens for active agents:

```bash
# Make the script executable
chmod +x setup-agent-secrets.sh

# Run the setup script
./setup-agent-secrets.sh
```

**Note**: The script uses clean input handling - simply type or paste your credentials and press Enter. No special key combinations needed.

The script supports the following agents and their required credentials:

#### GitHub Agent
- **Personal Access Token**: GitHub API access token with repo permissions
- **Webhook Secret**: Optional secret for webhook validation

#### GitLab Agent  
- **Personal Access Token**: GitLab API access token
- **Webhook Secret**: Optional secret for webhook validation

#### Jira Agent
- **API Token**: Jira API token for authentication
- **Base URL**: Jira instance URL (e.g., https://company.atlassian.net)
- **Username**: Jira username/email

#### Slack Agent
- **Bot Token**: Slack bot token (xoxb-...)
- **App Token**: Slack app token (xapp-...)
- **Signing Secret**: Slack signing secret for request verification

#### AWS Agent
- **Access Key ID**: AWS access key ID
- **Secret Access Key**: AWS secret access key
- **Region**: AWS region (default: us-east-1)

### 4. Access Services

After deployment, access the platform services:

- **ArgoCD**: https://cnoe.localtest.me:8443/argocd
- **Backstage**: https://cnoe.localtest.me:8443/backstage
- **Vault**: https://vault.cnoe.localtest.me:8443/ui
- **Gitea**: https://gitea.cnoe.localtest.me:8443

### 5. Verify Setup

Check that your credentials are properly stored:

#### LLM Credentials
1. Access Vault UI: https://vault.cnoe.localtest.me:8443/ui
2. Navigate to: `secret/ai-platform-engineering/global`
3. Verify your LLM provider configuration

#### Agent Secrets
1. Access Vault UI: https://vault.cnoe.localtest.me:8443/ui
2. Navigate to: `secret/ai-platform-engineering/agent-secrets`
3. Verify your agent API keys and tokens

## Architecture

CAIPE includes:

- **Vault**: Secret management with automated token rotation
- **ArgoCD**: GitOps deployment with API token automation
- **Backstage**: Developer portal with API authentication
- **External Secrets**: Kubernetes secret synchronization
- **AI Agents**: Platform engineering automation

## Security Features

- Automated ArgoCD API token generation and rotation
- Vault-based secret management
- Secure credential storage with encryption
- RBAC for cross-namespace access
- No secrets exposed in logs

## Utility Scripts

### Refresh Secrets and Restart Deployments

After updating secrets in Vault, use this script to refresh Kubernetes secrets and restart deployments:

```bash
# Make the script executable
chmod +x refresh-secrets.sh

# Run the refresh script
./refresh-secrets.sh
```

This script will:
- Check if Vault secrets exist and have data
- Delete Kubernetes secrets and wait for External Secrets to recreate them
- Restart corresponding deployments with rollout status verification

### Sync ArgoCD Applications

Ensure all ArgoCD applications are synced and healthy:

```bash
# Make the script executable
chmod +x sync-apps.sh

# Run the sync script
./sync-apps.sh
```

This script will sync:
- **backstage** - Developer portal
- **vault** - Secret management  
- **argocd** - GitOps controller
- **ai-platform-engineering** - CAIPE stack
- **external-secrets** - Secret synchronization
- **ingress-nginx** - Ingress controller
- **gitea** - Git repository

## Raw Script Access

Download and run the setup scripts directly:

### LLM Credentials Setup
```bash
# Download the script
curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/main/caipe/setup-llm-credentials.sh -o setup-llm-credentials.sh

# Make it executable and run
chmod +x setup-llm-credentials.sh
./setup-llm-credentials.sh
```

### Agent Secrets Setup
```bash
# Download the script
curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/main/caipe/setup-agent-secrets.sh -o setup-agent-secrets.sh

# Make it executable and run
chmod +x setup-agent-secrets.sh
./setup-agent-secrets.sh
```

**Note**: Both scripts use clean input handling - simply type or paste your credentials and press Enter. No special key combinations needed.

### Utility Scripts

#### Refresh Secrets
```bash
curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/main/caipe/refresh-secrets.sh -o refresh-secrets.sh
chmod +x refresh-secrets.sh
./refresh-secrets.sh
```

#### Sync Applications
```bash
curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/main/caipe/sync-apps.sh -o sync-apps.sh
chmod +x sync-apps.sh
./sync-apps.sh
```

## Troubleshooting

### Prerequisites
- `kubectl` CLI installed and configured
- `vault` CLI installed
- Access to the CAIPE cluster

### Common Issues

1. **Vault connection failed**: Ensure port-forward is working and Vault is running
2. **Permission denied**: Check that you have access to the vault namespace
3. **Invalid provider**: Select a number from 1-5 for supported providers

### Support

For issues and questions, please refer to the [CNOE documentation](https://cnoe.io/docs/) or open an issue in the repository.
