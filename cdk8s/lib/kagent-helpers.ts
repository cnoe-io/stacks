/**
 * Helper functions for creating kagent-related Kubernetes resources
 * Provides reusable builders for Agent, ModelConfig, SecurityContext, and resource limits
 */

import {
  Agent,
  AgentSpec,
  ModelConfig,
  ModelConfigSpec,
  ModelConfigSpecProvider,
} from '../imports/kagent.dev';
import { Construct } from 'constructs';
import * as k8s from '../imports/k8s';

/**
 * Creates a SecurityContext for kagent/kmcp pods following Security by Default principles
 * - runAsNonRoot: true (never run as root)
 * - allowPrivilegeEscalation: false (prevent privilege escalation)
 * - readOnlyRootFilesystem: true where feasible (minimize write surface)
 */
export function createKagentSecurityContext(readOnlyRootFilesystem: boolean = true) {
  return {
    runAsNonRoot: true,
    allowPrivilegeEscalation: false,
    readOnlyRootFilesystem,
    capabilities: {
      drop: ['ALL'],
    },
  };
}

/**
 * Creates resource limits for kagent/kmcp components
 *
 * @param componentType - Type of component: 'controller' | 'engine' | 'mcp-server' | 'dashboard'
 * @returns Resource limits and requests
 *
 * Defaults:
 * - controller: 500MB limit / 250MB request
 * - engine: 1GB limit / 512MB request
 * - mcp-server: 512MB limit / 256MB request
 * - dashboard: 512MB limit / 256MB request
 */
export function createKagentResourceLimits(componentType: 'controller' | 'engine' | 'mcp-server' | 'dashboard') {
  const resourceMap = {
    controller: {
      limits: { memory: k8s.Quantity.fromString('500Mi'), cpu: k8s.Quantity.fromString('500m') },
      requests: { memory: k8s.Quantity.fromString('250Mi'), cpu: k8s.Quantity.fromString('100m') },
    },
    engine: {
      limits: { memory: k8s.Quantity.fromString('1Gi'), cpu: k8s.Quantity.fromString('1000m') },
      requests: { memory: k8s.Quantity.fromString('512Mi'), cpu: k8s.Quantity.fromString('250m') },
    },
    'mcp-server': {
      limits: { memory: k8s.Quantity.fromString('512Mi'), cpu: k8s.Quantity.fromString('500m') },
      requests: { memory: k8s.Quantity.fromString('256Mi'), cpu: k8s.Quantity.fromString('100m') },
    },
    dashboard: {
      limits: { memory: k8s.Quantity.fromString('512Mi'), cpu: k8s.Quantity.fromString('500m') },
      requests: { memory: k8s.Quantity.fromString('256Mi'), cpu: k8s.Quantity.fromString('100m') },
    },
  };

  return resourceMap[componentType];
}

/**
 * Creates a kagent ModelConfig resource
 *
 * @param scope - CDK8s construct scope
 * @param name - Resource name
 * @param namespace - Kubernetes namespace
 * @param provider - LLM provider type
 * @param apiKeySecret - Kubernetes secret name containing API key
 * @param apiKeySecretKey - Key within secret (e.g., 'OPENAI_API_KEY')
 * @param model - Model name (optional, uses provider default if not specified)
 * @returns ModelConfig resource
 */
export function createModelConfig(
  scope: Construct,
  name: string,
  namespace: string,
  provider: 'openAI' | 'anthropic' | 'gemini' | 'azureOpenAI' | 'ollama',
  apiKeySecret: string,
  apiKeySecretKey: string,
  model?: string
): ModelConfig {
  let spec: ModelConfigSpec;

  // Add provider-specific configuration
  // Note: apiKeySecret and apiKeySecretKey are top-level properties in the spec
  switch (provider) {
    case 'openAI':
      spec = {
        provider: ModelConfigSpecProvider.OPEN_AI,
        apiKeySecretRef: apiKeySecret,
        apiKeySecretKey: apiKeySecretKey,
        model: model || 'gpt-4',
      };
      break;
    case 'anthropic':
      spec = {
        provider: ModelConfigSpecProvider.ANTHROPIC,
        apiKeySecretRef: apiKeySecret,
        apiKeySecretKey: apiKeySecretKey,
        model: model || 'claude-3-5-sonnet-20241022',
      };
      break;
    case 'gemini':
      spec = {
        provider: ModelConfigSpecProvider.GEMINI,
        apiKeySecretRef: apiKeySecret,
        apiKeySecretKey: apiKeySecretKey,
        model: model || 'gemini-pro', // Required for Gemini
      };
      break;
    case 'azureOpenAI':
      spec = {
        provider: ModelConfigSpecProvider.AZURE_OPEN_AI,
        apiKeySecretRef: apiKeySecret,
        apiKeySecretKey: apiKeySecretKey,
        model: model || 'gpt-4',
        azureOpenAi: {
          apiVersion: '2024-02-01',
          azureEndpoint: '', // Must be provided by caller
          azureDeployment: '', // Must be provided by caller
        },
      };
      break;
    case 'ollama':
      spec = {
        provider: ModelConfigSpecProvider.OLLAMA,
        model: model || 'llama2',
        ollama: {
          host: 'http://ollama:11434', // Default Ollama host
        },
      };
      break;
    default:
      throw new Error(`Unsupported provider: ${provider}`);
  }

  return new ModelConfig(scope, `modelconfig-${name}`, {
    metadata: {
      name,
      namespace,
    },
    spec,
  });
}

/**
 * Creates a kagent Agent resource
 *
 * @param scope - CDK8s construct scope
 * @param name - Agent name
 * @param namespace - Kubernetes namespace
 * @param description - Human-readable agent description
 * @param systemMessage - System instructions for agent behavior
 * @param tools - List of tools the agent can use
 * @param modelConfig - Name of ModelConfig resource
 * @param a2aConfig - Optional A2A protocol configuration
 * @returns Agent resource
 */
export function createAgent(
  scope: Construct,
  name: string,
  namespace: string,
  description: string,
  systemMessage: string,
  tools: Array<{ type: 'McpServer' | 'BuiltIn'; mcpServer?: { name: string; kind: string; toolNames?: string[] }; builtIn?: { toolName: string } }>,
  modelConfig: string,
  a2aConfig?: {
    skills: Array<{
      id: string;
      name: string;
      description: string;
      inputModes: string[];
      outputModes: string[];
      tags: string[];
    }>;
  }
): Agent {
  const spec: AgentSpec = {
    description,
    modelConfig,
    systemMessage,
    tools,
    ...(a2aConfig ? { a2AConfig: a2aConfig } : {}),
  };

  return new Agent(scope, `agent-${name}`, {
    metadata: {
      name,
      namespace,
      labels: {
        'app.kubernetes.io/name': name,
        'app.kubernetes.io/component': 'agent',
      },
    },
    spec,
  });
}

/**
 * Creates an A2A skill definition
 *
 * @param id - Skill ID (kebab-case)
 * @param name - Human-readable skill name
 * @param description - Skill description
 * @param tags - Skill tags for discovery
 * @returns Skill object
 */
export function createA2ASkill(
  id: string,
  name: string,
  description: string,
  tags: string[]
) {
  return {
    id,
    name,
    description,
    inputModes: ['text'],
    outputModes: ['text'],
    tags,
  };
}

/**
 * Creates an A2A configuration for an agent
 *
 * @param skills - Array of skill definitions
 * @returns A2A configuration object
 */
export function createA2AConfig(skills: Array<ReturnType<typeof createA2ASkill>>) {
  return {
    skills,
  };
}

/**
 * Creates sync wave annotation for ArgoCD resource ordering
 * Kagent-specific sync waves:
 * - CRDs: -110
 * - Namespace: -100
 * - RBAC (ServiceAccount, Role, RoleBinding): -90
 * - Secrets (ExternalSecret): -70
 * - Controllers (Deployment, Service): 0
 * - Agents/MCPServers: 50
 * - Ingress: 100
 */
export function kagentSyncWave(wave: number): Record<string, string> {
  return {
    'argocd.argoproj.io/sync-wave': wave.toString(),
  };
}
