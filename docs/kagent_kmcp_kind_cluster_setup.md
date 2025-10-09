# Kagent & KMCP Documentation for Kind Cluster

## Prerequisites

- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) for local Kubernetes cluster
- [Helm](https://helm.sh/docs/intro/install/) for installing charts
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster interaction
- [OpenAI API key](https://platform.openai.com/account/api-keys) for agent LLMs
- [uv](https://docs.astral.sh/uv/getting-started/installation/) for FastMCP servers
- [Docker](https://docs.docker.com/desktop/) for MCP server images

---

## Installing kagent

### Using CLI (Recommended)

```bash
export OPENAI_API_KEY="your-api-key-here"
curl https://raw.githubusercontent.com/kagent-dev/kagent/refs/heads/main/scripts/get-kagent | bash
kagent install
```

### Using Helm

```bash
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds --namespace kagent --create-namespace
export OPENAI_API_KEY="your-api-key-here"
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent --namespace kagent --set providers.default=openAI --set providers.openAI.apiKey=$OPENAI_API_KEY
```

---

## Accessing the kagent Dashboard

```bash
kagent dashboard
# Opens http://localhost:8082
```

---

## Creating Your First Agent

1. Open dashboard: `kagent dashboard`
2. Click + Create > New Agent
3. Fill in agent name, namespace (`kagent`), description, and instructions
4. Add tools (e.g., `k8s_get_available_api_resources`, `k8s_get_resources`)
5. Click Create Agent
6. Interact with the agent in the UI or via CLI:
   ```bash
   kagent invoke -t "What Helm charts are in my cluster?" --agent helm-agent
   ```

---

## Adding MCP Tools to Your Agent

1. Create MCPServer resource:
   ```yaml
   apiVersion: kagent.dev/v1alpha1
   kind: MCPServer
   metadata:
     name: mcp-website-fetcher
     namespace: kagent
   spec:
     deployment:
       args:
         - mcp-server-fetch
       cmd: uvx
       port: 3000
     stdioTransport: {}
     transportType: stdio
   ```
2. Create Agent resource referencing MCPServer:
   ```yaml
   apiVersion: kagent.dev/v1alpha2
   kind: Agent
   metadata:
     name: simple-fetch-agent
     namespace: kagent
   spec:
     description: This agent can use a single tool to retrieve the contents of a webpage.
     type: Declarative
     declarative:
       modelConfig: default-model-config
       systemMessage: |
         You're a friendly and helpful agent that uses the fetch tool to retrieve webpage contents.
       tools:
         - type: McpServer
           mcpServer:
             name: mcp-website-fetcher
             kind: MCPServer
             toolNames:
               - fetch
   ```

---

## Exposing Agents via A2A Protocol

1. Create agent with A2A config:
   ```yaml
   apiVersion: kagent.dev/v1alpha2
   kind: Agent
   metadata:
     name: k8s-a2a-agent
     namespace: kagent
   spec:
     description: An example A2A agent that knows how to use Kubernetes tools.
     type: Declarative
     declarative:
       modelConfig: default-model-config
       systemMessage: |
         You are an expert Kubernetes agent that uses tools to help users.
       tools:
         - type: McpServer
           mcpServer:
             name: kagent-tool-server
             kind: RemoteMCPServer
             toolNames:
               - k8s_get_resources
               - k8s_get_available_api_resources
       a2aConfig:
         skills:
           - id: get-resources-skill
             name: Get Resources
             description: Get resources in the Kubernetes cluster
             inputModes:
               - text
             outputModes:
               - text
             tags:
               - k8s
               - resources
   ```
2. Port-forward the kagent controller service:
   ```bash
   kubectl port-forward svc/kagent-controller 8083:8083 -n kagent
   curl localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json
   ```

---

## Integrating with Slack

- Create Slack App, set up OAuth scopes (`chat:write`, `commands`)
- Clone [A2A Slack template](https://github.com/kagent-dev/a2a-slack-template.git)
- Set tokens in `.env`, run bot with `uv run main.py`
- Deploy agent and port-forward as above
- Set `KAGENT_A2A_URL` in `.env` to agent's A2A URL
- Use `/mykagent` command in Slack to interact
- To send messages from kagent to Slack, deploy Slack MCP server and add tool to agent

---

## Integrating with Discord

- Create Discord bot, set token in `.env`
- Clone [kagent-a2a-discord](https://github.com/lekkerelou/kagent-a2a-discord)
- Set `KAGENT_A2A_URL` to agent's A2A URL
- Run bot with `uv run main.py` or Docker

---

## Creating and Deploying MCP Servers with KMCP

1. Install kmcp CLI:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/kagent-dev/kmcp/refs/heads/main/scripts/get-kmcp.sh | bash
   kmcp --help
   ```
2. Scaffold FastMCP Python server:
   ```bash
   kmcp init python my-mcp-server
   kmcp run --project-dir my-mcp-server
   ```
3. Create kind cluster:
   ```bash
   kind create cluster
   ```
4. Install kmcp CRDs and controller:
   ```bash
   helm install kmcp-crds oci://ghcr.io/kagent-dev/kmcp/helm/kmcp-crds --namespace kmcp-system --create-namespace
   kmcp install
   kubectl get pods -n kmcp-system
   ```
5. Build and deploy MCP server:
   ```bash
   kmcp build --project-dir my-mcp-server -t my-mcp-server:latest --kind-load-cluster kind
   kmcp deploy --file my-mcp-server/kmcp.yaml --image my-mcp-server:latest
   ```

---

## Managing Secrets for MCP Servers

1. Edit `kmcp.yaml` to enable staging environment:
   ```yaml
   secrets:
     staging:
       enabled: true
       provider: kubernetes
       secretName: my-mcp-server-secrets-staging
       namespace: default
   ```
2. Create `.env.staging` file with environment variables:
   ```bash
   cat << EOF > my-mcp-server/.env.staging
   API_KEY=your-api-key-here
   DATABASE_URL=postgresql://user:pass@host:5432/db
   EOF
   ```
3. Sync secrets to Kubernetes:
   ```bash
   kmcp secrets sync staging --from-file my-mcp-server/.env.staging --project-dir my-mcp-server
   ```
4. Deploy with secrets:
   ```bash
   kmcp deploy --environment staging --file my-mcp-server/kmcp.yaml --image my-mcp-server:latest
   ```

---

## Alternative LLM Providers

### Anthropic

```bash
export ANTHROPIC_API_KEY="your-api-key-here"
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=anthropic \
  --set providers.anthropic.apiKey=$ANTHROPIC_API_KEY
```

### Gemini

```bash
export GEMINI_API_KEY="your-api-key-here"
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=gemini \
  --set providers.gemini.apiKey=$GEMINI_API_KEY
```

### Azure OpenAI

```bash
export OPENAI_API_KEY="your-api-key-here"
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=openAI \
  --set providers.azureOpenAI.apiKey=$OPENAI_API_KEY
```

### Ollama (Local)

```bash
helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent \
  --set providers.default=ollama
```

---

## Uninstalling

### Remove kagent

```bash
kagent uninstall
# Or with Helm:
helm uninstall kagent -n kagent
helm uninstall kagent-crds -n kagent  # Deletes all kagent resources
```

### Remove kmcp

```bash
helm uninstall kmcp -n kmcp-system
helm uninstall kmcp-crds -n kmcp-system
```

---

## Architecture Overview

- **Controller**: Kubernetes controller (Go) managing Agent & MCP CRDs
- **Engine/App**: Python application running agent conversation loop (built on ADK)
- **CLI**: Command-line interface for managing resources
- **Dashboard**: Web UI for agent management (port-forward on 8082)
- **A2A Protocol**: Agent-to-Agent communication protocol for interoperability

---

## Key Concepts

- **Tools**: MCP-style functions agents use to interact with systems (built-in K8s, Istio, Prometheus tools available)
- **Agents**: Autonomous systems that plan, execute, and analyze tasks using tools
- **MCP Servers**: Services exposing tools via Model Context Protocol
- **A2A Protocol**: Enables agents to communicate with each other and external systems
- **Declarative Agents**: Defined via YAML manifests with system messages and tool references

---

## References & Community

- [Kagent GitHub](https://github.com/kagent-dev/kagent)
- [KMCP GitHub](https://github.com/kagent-dev/kmcp)
- [Discord](https://discord.gg/Fu3k65f2k3)
- [FAQ](https://kagent.dev/docs/kagent/resources/faq)
- [Documentation](https://kagent.dev/docs/kagent)

---

This file summarizes the official documentation for implementing kagent and kmcp in a kind cluster. For more details, visit https://kagent.dev/docs/kagent and https://kagent.dev/docs/kmcp.
