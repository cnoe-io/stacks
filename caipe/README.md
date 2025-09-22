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

### 3. Access Services

After deployment, access the platform services:

- **ArgoCD**: https://cnoe.localtest.me:8443/argocd
- **Backstage**: https://cnoe.localtest.me:8443/backstage
- **Vault**: https://vault.cnoe.localtest.me:8443/ui
- **Gitea**: https://gitea.cnoe.localtest.me:8443

### 4. Verify Setup

Check that your LLM credentials are properly stored:

1. Access Vault UI: https://vault.cnoe.localtest.me:8443/ui
2. Navigate to: `secret/ai-platform-engineering/global`
3. Verify your LLM provider configuration

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

## Raw Script Access

You can also download and run the setup script directly:

```bash
curl -sSL https://raw.githubusercontent.com/sriaradhyula/stacks/main/caipe/setup-llm-credentials.sh | bash
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
