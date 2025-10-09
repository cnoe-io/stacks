# Data Model: kagent & kmcp CRDs

**Feature**: Kubernetes-Native AI Agent Platform
**Date**: 2025-10-08
**Purpose**: Document custom resource definitions (CRDs) for agents and tool servers

## Overview

kagent and kmcp introduce three primary custom resources to Kubernetes:
1. **Agent** (`agents.kagent.dev/v1alpha2`) - Defines autonomous AI agents with tools and system instructions
2. **MCPServer** (`mcpservers.kmcp.dev/v1alpha1`) - Defines tool servers exposing capabilities to agents
3. **ModelConfig** (`modelconfigs.kagent.dev/v1alpha1`) - Defines LLM provider configurations

## Entity Relationships

```
┌─────────────────┐
│   ModelConfig   │  (LLM provider settings)
└────────┬────────┘
         │ references
         ▼
┌─────────────────┐       uses        ┌──────────────┐
│     Agent       │◄────────────────►│  MCPServer   │
└─────────────────┘                   └──────────────┘
         │                                    │
         │ creates                            │ exposes
         ▼                                    ▼
┌─────────────────┐                   ┌──────────────┐
│  Agent Pod      │                   │  Tool Pods   │
└─────────────────┘                   └──────────────┘
```

## Agent CRD (`agents.kagent.dev/v1alpha2`)

### Purpose
Defines an autonomous AI agent with natural language instructions, assigned tools, and LLM configuration.

### Schema

```typescript
interface Agent {
  apiVersion: 'kagent.dev/v1alpha2';
  kind: 'Agent';
  metadata: ObjectMeta;
  spec: AgentSpec;
  status?: AgentStatus;
}

interface AgentSpec {
  description: string;                    // Human-readable agent description
  type: 'Declarative' | 'Code';           // Agent type (Declarative for YAML-defined)
  declarative?: DeclarativeAgentSpec;     // For type: Declarative
  code?: CodeAgentSpec;                   // For type: Code (not used in initial impl)
}

interface DeclarativeAgentSpec {
  modelConfig: string;                    // Reference to ModelConfig name
  systemMessage: string;                  // System instructions for agent behavior
  tools: ToolReference[];                 // List of tools agent can use
  a2aConfig?: A2AConfig;                  // Optional Agent-to-Agent protocol config
}

interface ToolReference {
  type: 'McpServer' | 'BuiltIn';
  mcpServer?: {
    name: string;                         // MCPServer resource name
    kind: 'MCPServer' | 'RemoteMCPServer';
    toolNames?: string[];                 // Specific tools to use (or all if omitted)
  };
  builtIn?: {
    toolName: string;                     // Built-in tool name (e.g., 'k8s_get_resources')
  };
}

interface A2AConfig {
  skills: Skill[];                        // Exposed skills for A2A protocol
}

interface Skill {
  id: string;
  name: string;
  description: string;
  inputModes: string[];                   // e.g., ['text']
  outputModes: string[];                  // e.g., ['text']
  tags: string[];                         // e.g., ['k8s', 'resources']
}

interface AgentStatus {
  phase: 'Pending' | 'Running' | 'Failed';
  conditions: Condition[];
  endpoint?: string;                      // A2A protocol endpoint if enabled
}
```

### Validation Rules
- `spec.description` must be non-empty
- `spec.declarative.systemMessage` must be non-empty
- `spec.declarative.tools` must contain at least one tool
- `spec.declarative.modelConfig` must reference an existing ModelConfig

### State Transitions
1. **Pending**: Agent resource created, waiting for controller to provision pod
2. **Running**: Agent pod is running and ready to accept requests
3. **Failed**: Agent pod failed to start or crashed

### Example Usage
```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: k8s-agent
  namespace: kagent
spec:
  description: Kubernetes resource query agent
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |
      You are a Kubernetes expert agent. Use available tools to query cluster resources
      and provide helpful information to users.
    tools:
      - type: McpServer
        mcpServer:
          name: kagent-tool-server
          kind: RemoteMCPServer
          toolNames:
            - k8s_get_resources
            - k8s_get_available_api_resources
```

## MCPServer CRD (`mcpservers.kmcp.dev/v1alpha1`)

### Purpose
Defines a Model Context Protocol server exposing one or more tools that agents can invoke.

### Schema

```typescript
interface MCPServer {
  apiVersion: 'kmcp.dev/v1alpha1';
  kind: 'MCPServer';
  metadata: ObjectMeta;
  spec: MCPServerSpec;
  status?: MCPServerStatus;
}

interface MCPServerSpec {
  deployment: DeploymentSpec;             // How to run the tool server
  transportType: 'stdio' | 'http';        // Communication protocol
  stdioTransport?: StdioTransportConfig;
  httpTransport?: HttpTransportConfig;
  secrets?: SecretsConfig;                // Optional secrets for tool server
}

interface DeploymentSpec {
  cmd: string;                            // Command to run (e.g., 'uvx', 'python')
  args: string[];                         // Arguments (e.g., ['mcp-server-fetch'])
  port?: number;                          // Port for HTTP transport
  env?: EnvVar[];                         // Environment variables
}

interface StdioTransportConfig {
  // Empty for stdio (communication via stdin/stdout)
}

interface HttpTransportConfig {
  endpoint: string;                       // HTTP endpoint path
}

interface SecretsConfig {
  enabled: boolean;
  provider: 'kubernetes' | 'vault';
  secretName?: string;                    // Kubernetes secret name
  namespace?: string;
}

interface MCPServerStatus {
  phase: 'Pending' | 'Running' | 'Failed';
  availableTools: string[];               // List of tools exposed by server
  endpoint?: string;                      // Service endpoint for HTTP transport
}
```

### Validation Rules
- `spec.deployment.cmd` must be non-empty
- `spec.deployment.args` must be non-empty array
- `spec.transportType` must be 'stdio' or 'http'
- If `transportType: 'http'`, `spec.deployment.port` is required

### State Transitions
1. **Pending**: MCPServer resource created, controller provisioning pod
2. **Running**: Tool server pod running, tools discoverable
3. **Failed**: Tool server failed to start or crashed

### Example Usage
```yaml
apiVersion: kmcp.dev/v1alpha1
kind: MCPServer
metadata:
  name: mcp-website-fetcher
  namespace: kagent
spec:
  deployment:
    cmd: uvx
    args: ['mcp-server-fetch']
    port: 3000
  transportType: stdio
  stdioTransport: {}
```

## ModelConfig CRD (`modelconfigs.kagent.dev/v1alpha1`)

### Purpose
Configures LLM provider settings (API endpoints, authentication, model selection).

### Schema

```typescript
interface ModelConfig {
  apiVersion: 'kagent.dev/v1alpha1';
  kind: 'ModelConfig';
  metadata: ObjectMeta;
  spec: ModelConfigSpec;
}

interface ModelConfigSpec {
  provider: 'openAI' | 'anthropic' | 'gemini' | 'azureOpenAI' | 'ollama';
  openAI?: OpenAIConfig;
  anthropic?: AnthropicConfig;
  gemini?: GeminiConfig;
  azureOpenAI?: AzureOpenAIConfig;
  ollama?: OllamaConfig;
}

interface OpenAIConfig {
  apiKeySecret: string;                   // Kubernetes secret name
  apiKeySecretKey: string;                // Key within secret (e.g., 'OPENAI_API_KEY')
  model?: string;                         // Model name (default: 'gpt-4')
  baseURL?: string;                       // Custom API endpoint
}

interface AnthropicConfig {
  apiKeySecret: string;
  apiKeySecretKey: string;
  model?: string;                         // Model name (default: 'claude-3-5-sonnet-20241022')
}

interface GeminiConfig {
  apiKeySecret: string;
  apiKeySecretKey: string;
  model?: string;                         // Model name (default: 'gemini-pro')
}

interface AzureOpenAIConfig {
  apiKeySecret: string;
  apiKeySecretKey: string;
  endpoint: string;                       // Azure OpenAI endpoint
  deploymentName: string;                 // Azure deployment name
}

interface OllamaConfig {
  baseURL: string;                        // Ollama server URL (e.g., 'http://ollama:11434')
  model: string;                          // Model name (e.g., 'llama2')
}
```

### Validation Rules
- `spec.provider` must match one of the supported providers
- Corresponding provider config must be present (e.g., if `provider: 'openAI'`, `spec.openAI` required)
- `apiKeySecret` must reference an existing Kubernetes secret
- For `ollama` provider, `baseURL` and `model` are required

### Example Usage
```yaml
apiVersion: kagent.dev/v1alpha1
kind: ModelConfig
metadata:
  name: default-model-config
  namespace: kagent
spec:
  provider: openAI
  openAI:
    apiKeySecret: kagent-llm-providers
    apiKeySecretKey: OPENAI_API_KEY
    model: gpt-4-turbo-preview
```

## Composite Example: Agent with Custom MCP Server

```yaml
---
# 1. MCPServer: Web content fetcher
apiVersion: kmcp.dev/v1alpha1
kind: MCPServer
metadata:
  name: mcp-website-fetcher
  namespace: kagent
spec:
  deployment:
    cmd: uvx
    args: ['mcp-server-fetch']
    port: 3000
  transportType: stdio
  stdioTransport: {}

---
# 2. Agent: Uses web fetcher tool
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: fetch-agent
  namespace: kagent
spec:
  description: Agent that can fetch and summarize web content
  type: Declarative
  declarative:
    modelConfig: default-model-config
    systemMessage: |
      You are a helpful agent that can retrieve web content using the fetch tool.
      When asked about a website, use the fetch tool to retrieve its content, then
      summarize the key information for the user.
    tools:
      - type: McpServer
        mcpServer:
          name: mcp-website-fetcher
          kind: MCPServer
          toolNames: ['fetch']
```

## Index and Query Patterns

### Common Queries
- **List all agents**: `kubectl get agents -n kagent`
- **Get agent details**: `kubectl describe agent k8s-agent -n kagent`
- **List MCPServers**: `kubectl get mcpservers -n kagent`
- **Check agent status**: `kubectl get agent k8s-agent -n kagent -o jsonpath='{.status.phase}'`
- **Get A2A endpoint**: `kubectl get agent a2a-agent -n kagent -o jsonpath='{.status.endpoint}'`

### Indexed Fields (for efficient queries)
- `metadata.name` - Agent/MCPServer name
- `metadata.namespace` - Deployment namespace
- `spec.type` - Agent type (Declarative/Code)
- `spec.provider` - ModelConfig provider type
- `status.phase` - Current resource state

## Migration Considerations

**From Helm-based deployment** → **CDK8s-based deployment**:
- Existing Agent/MCPServer/ModelConfig resources are preserved (CRDs are backwards compatible)
- Controller pods are replaced (new images from CDK8s manifests)
- Secrets must be migrated to ExternalSecrets (one-time manual step)
- No downtime required: new controllers can manage existing agent resources

**Version Upgrades**:
- CRD schema changes may require resource updates
- Agent conversation state is ephemeral (no migration needed)
- ModelConfig changes require agent pod restarts (handled by controller)
