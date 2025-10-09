# Quickstart: kagent & kmcp Deployment

**Feature**: Kubernetes-Native AI Agent Platform
**Audience**: Platform Engineers
**Time to Complete**: ~20 minutes

## Prerequisites

### Required
- Local kind cluster (or existing Kubernetes 1.27+ cluster)
- `kubectl` configured to access cluster
- `idpbuilder` CLI installed
- ArgoCD running in cluster (installed by idpbuilder)
- External Secrets Operator running (existing Stacks deployment)
- Azure Key Vault with LLM provider API keys:
  - Path: `llm-providers/openai` with property `api_key`
  - Path: `llm-providers/anthropic` with property `api_key`

### Optional
- `argocd` CLI for monitoring sync progress
- Anthropic, Gemini, or Azure OpenAI API keys (for alternative LLM providers)

## Step 1: Prepare LLM Provider API Keys

### Option A: OpenAI (Recommended for Quickstart)

1. Obtain OpenAI API key from https://platform.openai.com/account/api-keys
2. Store in Azure Key Vault:
   ```bash
   az keyvault secret set \
     --vault-name <your-vault> \
     --name "llm-providers-openai" \
     --value '{"api_key": "sk-YOUR-KEY-HERE"}'
   ```

### Option B: Anthropic

1. Obtain Anthropic API key from https://console.anthropic.com/
2. Store in Azure Key Vault:
   ```bash
   az keyvault secret set \
     --vault-name <your-vault> \
     --name "llm-providers-anthropic" \
     --value '{"api_key": "sk-ant-YOUR-KEY-HERE"}'
   ```

### Option C: Local Ollama (No API Key Required)

1. Install Ollama locally: https://ollama.ai/download
2. Pull a model: `ollama pull llama2`
3. Update ModelConfig to use Ollama provider (see [Customization](#customization))

## Step 2: Synthesize kagent/kmcp Manifests

```bash
cd /home/vpittamp/stacks/cdk8s

# Install dependencies (if not already done)
npm install

# Import kagent/kmcp CRDs
npm run import -- \
  https://raw.githubusercontent.com/kagent-dev/kagent/main/deploy/crds/kagent.dev_agents.yaml \
  https://raw.githubusercontent.com/kagent-dev/kagent/main/deploy/crds/kagent.dev_modelconfigs.yaml \
  https://raw.githubusercontent.com/kagent-dev/kmcp/main/deploy/crds/kmcp.dev_mcpservers.yaml

# Synthesize all packages
npx ts-node main-v2.ts

# Verify synthesis output
ls -la dist/kagent/manifests/
ls -la dist/kmcp/manifests/
ls -la dist/kagent-agents/manifests/
```

**Expected Output**:
- `dist/kagent/manifests/`: CRDs, controller, engine, dashboard, RBAC, ExternalSecret
- `dist/kmcp/manifests/`: CRDs, controller, RBAC
- `dist/kagent-agents/manifests/`: Example agents (k8s-agent, fetch-agent, a2a-agent), MCP servers

## Step 3: Deploy via IdpBuilder

```bash
# Deploy kagent platform (CRDs + controllers)
idpbuilder create --package cdk8s/dist/kagent

# Deploy kmcp platform (MCP server controller)
idpbuilder create --package cdk8s/dist/kmcp

# Wait for controllers to be ready
kubectl wait --for=condition=ready pod -l app=kagent-controller -n kagent --timeout=300s
kubectl wait --for=condition=ready pod -l app=kmcp-controller -n kagent --timeout=300s

# Deploy example agents and MCP servers
idpbuilder create --package cdk8s/dist/kagent-agents

# Wait for agents to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=agent -n kagent --timeout=300s
```

## Step 4: Verify Deployment

```bash
# Check platform components
kubectl get all -n kagent

# Expected output:
# - Deployments: kagent-controller, kagent-app, kagent-dashboard, kmcp-controller
# - Pods: All in Running state
# - Services: kagent-controller (8083), kagent-dashboard (8082)

# Check CRDs installed
kubectl get crds | grep -E 'kagent|kmcp'

# Expected:
# agents.kagent.dev
# modelconfigs.kagent.dev
# remotemcpservers.kagent.dev
# mcpservers.kmcp.dev

# Check agents deployed
kubectl get agents -n kagent

# Expected:
# NAME         AGE
# k8s-agent    1m
# fetch-agent  1m
# a2a-agent    1m

# Check MCP servers
kubectl get mcpservers -n kagent

# Expected:
# NAME                    AGE
# mcp-website-fetcher     1m

# Check External Secret synced
kubectl get externalsecret kagent-llm-providers -n kagent -o jsonpath='{.status.conditions[0].status}'

# Expected: True (secret synced successfully)
```

## Step 5: Access kagent Dashboard

```bash
# Option A: Port-forward (local dev)
kubectl port-forward -n kagent svc/kagent-dashboard 8082:8082

# Open in browser: http://localhost:8082

# Option B: Ingress (if deployed with --use-path-routing)
# Dashboard available at: https://cnoe.localtest.me:8443/kagent-dashboard
```

**Dashboard Features**:
- View all agents and their status
- See agent conversation history
- Invoke agents via UI
- Monitor tool invocations

## Step 6: Test Agents

### Test k8s-agent (Kubernetes Query Agent)

```bash
# Via kubectl (requires kagent CLI - optional)
# kubectl kagent invoke -n kagent k8s-agent -t "List all pods in the kagent namespace"

# Via port-forward to controller (A2A protocol)
kubectl port-forward -n kagent svc/kagent-controller 8083:8083

# In another terminal:
curl -X POST http://localhost:8083/api/v1/agents/kagent/k8s-agent/invoke \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What deployments are running in the kagent namespace?"}'
```

**Expected Response**: Agent lists deployments (kagent-controller, kagent-app, etc.) with details

### Test fetch-agent (Web Content Agent)

```bash
# Via curl to A2A endpoint
curl -X POST http://localhost:8083/api/v1/agents/kagent/fetch-agent/invoke \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Fetch and summarize the content from https://kubernetes.io"}'
```

**Expected Response**: Agent fetches Kubernetes homepage, provides summary

### Test a2a-agent (A2A Protocol Agent)

```bash
# Query A2A capabilities
curl http://localhost:8083/api/a2a/kagent/a2a-agent/.well-known/agent.json

# Expected: JSON with agent skills, input/output modes, tags

# Invoke via A2A protocol
curl -X POST http://localhost:8083/api/a2a/kagent/a2a-agent/invoke \
  -H "Content-Type: application/json" \
  -d '{"skill_id": "get-resources-skill", "input": {"text": "Show me all services"}}'
```

## Step 7: Monitor with ArgoCD

```bash
# View kagent application sync status
argocd app get argocd/kagent --insecure

# View logs
argocd app logs argocd/kagent --insecure

# Sync if out-of-date
argocd app sync argocd/kagent --prune --insecure
```

## Customization

### Use Different LLM Provider

Edit `cdk8s/charts/infra/kagent-chart.ts` ModelConfig:

```typescript
// Change from OpenAI to Anthropic
new KubeModelConfig(this, 'default-model-config', {
  metadata: { name: 'default-model-config', namespace: 'kagent' },
  spec: {
    provider: 'anthropic',
    anthropic: {
      apiKeySecret: 'kagent-llm-providers',
      apiKeySecretKey: 'ANTHROPIC_API_KEY',
      model: 'claude-3-5-sonnet-20241022',
    },
  },
});
```

### Add Custom MCP Server

Create new MCPServer resource in `cdk8s/charts/apps/kagent-example-mcps-chart.ts`:

```typescript
new KubeMCPServer(this, 'my-custom-mcp', {
  metadata: { name: 'my-custom-mcp', namespace: 'kagent' },
  spec: {
    deployment: {
      cmd: 'python',
      args: ['/app/my_mcp_server.py'],
      port: 3000,
      env: [{
        name: 'MY_API_KEY',
        valueFrom: { secretKeyRef: { name: 'my-mcp-secrets', key: 'api_key' } },
      }],
    },
    transportType: 'stdio',
    stdioTransport: {},
  },
});
```

### Deploy to Production (EKS/AKS)

1. Update ArgoCD Application source from `cnoe://kagent/manifests` to Git URL
2. Add NetworkPolicies for ingress/egress control
3. Configure Keycloak SSO for dashboard authentication
4. Enable OPA Gatekeeper policies for SecurityContext enforcement
5. Set resource limits based on production load

## Troubleshooting

### Agents Stuck in Pending

```bash
# Check agent pod events
kubectl describe agent k8s-agent -n kagent

# Check controller logs
kubectl logs -n kagent deployment/kagent-controller

# Common causes:
# - ModelConfig secret not synced (check ExternalSecret)
# - Insufficient cluster resources (check node capacity)
# - CRDs not installed (verify with kubectl get crds)
```

### MCP Server Not Discovered

```bash
# Check MCPServer status
kubectl describe mcpserver mcp-website-fetcher -n kagent

# Check kmcp controller logs
kubectl logs -n kagent deployment/kmcp-controller

# Verify tool server pod running
kubectl get pods -n kagent -l app.kubernetes.io/component=mcp-server
```

### LLM API Rate Limits

- Agents automatically retry with exponential backoff
- Check controller logs for rate limit errors
- Consider using multiple API keys or switching providers

### External Secret Not Syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret kagent-llm-providers -n kagent -o yaml

# Verify ClusterSecretStore configured
kubectl get clustersecretstore azure-keyvault-store

# Check ESO controller logs
kubectl logs -n external-secrets deployment/external-secrets
```

## Next Steps

- **Create Custom Agents**: Modify `contracts/example-agent-definitions.yaml` with your own system messages and tools
- **Build Custom MCP Servers**: Write Python FastMCP servers for domain-specific tools
- **Integrate with Backstage**: Create Backstage templates for generating Agent resources
- **Enable A2A Integrations**: Connect agents to Slack/Discord via A2A protocol
- **Production Deployment**: Follow Stacks deployment guide for EKS/AKS

## References

- [kagent Documentation](https://kagent.dev/docs/kagent)
- [kmcp Documentation](https://kagent.dev/docs/kmcp)
- [FastMCP Framework](https://github.com/jlowin/fastmcp)
- [Model Context Protocol](https://modelcontextprotocol.io)
