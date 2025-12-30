/**
 * CAIPE Helpers - Shared utilities for CAIPE (AI Platform Engineering) charts
 *
 * This module provides common constants, labels, and helper functions
 * used across all CAIPE-related charts.
 */

// =============================================================================
// Constants
// =============================================================================

/** Default namespace for all CAIPE components */
export const CAIPE_NAMESPACE = 'ai-platform-engineering';

/** Default ClusterSecretStore for Azure Key Vault */
export const CAIPE_SECRET_STORE = 'azure-keyvault-store';

/** Default secret refresh interval */
export const CAIPE_REFRESH_INTERVAL = '1h';

/** Helm chart version for ai-platform-engineering */
export const CAIPE_HELM_VERSION = '0.3.0';

/** Container image versions */
export const CAIPE_IMAGE_VERSIONS = {
  supervisorAgent: 'latest',
  agentArgocd: 'latest',
  agentGithub: 'latest',
  agentBackstage: 'latest',
  ragServer: 'latest',
  ragWebui: 'latest',
  nexigraph: 'latest',
  milvus: '2.6.0',
  neo4j: '5.18.0',
  redis: '7.2.4',
} as const;

/** Service ports for CAIPE components */
export const CAIPE_PORTS = {
  supervisorAgent: 8000,
  ragServer: 9446,
  ragWebui: 80,
  agentOntology: 8098,
  neo4jBolt: 7687,
  neo4jHttp: 7474,
  redis: 6379,
  milvus: 19530,
  mcpHttp: 8000,
} as const;

/** Sync wave ordering for CAIPE components */
export const CAIPE_SYNC_WAVES = {
  namespace: '-110',
  secrets: '-80',
  storage: '-50',
  ragStack: '0',
  supervisor: '50',
  agents: '100',
} as const;

// =============================================================================
// Label Helpers
// =============================================================================

/** Common labels applied to all CAIPE resources */
export function getCaipeCommonLabels(component: string): Record<string, string> {
  return {
    'app.kubernetes.io/name': 'caipe',
    'app.kubernetes.io/component': component,
    'app.kubernetes.io/part-of': 'ai-platform-engineering',
    'app.kubernetes.io/managed-by': 'cdk8s',
  };
}

/** Labels for storage tier components (Milvus, Neo4j, Redis) */
export function getCaipeStorageLabels(storageType: string): Record<string, string> {
  return {
    ...getCaipeCommonLabels(storageType),
    'tier': 'storage',
  };
}

/** Labels for RAG tier components (RAG Server, RAG WebUI, NexiGraph) */
export function getCaipeRagLabels(ragComponent: string): Record<string, string> {
  return {
    ...getCaipeCommonLabels(ragComponent),
    'tier': 'rag',
  };
}

/** Labels for agent tier components (supervisor, sub-agents) */
export function getCaipeAgentLabels(agentName: string): Record<string, string> {
  return {
    ...getCaipeCommonLabels(agentName),
    'tier': 'agent',
  };
}

// =============================================================================
// Azure Key Vault Secret Keys
// =============================================================================

/** Azure Key Vault secret key names for CAIPE (shared across clusters) */
export const CAIPE_KEYVAULT_KEYS = {
  // LLM Provider (shared - same Azure OpenAI instance)
  llmProvider: 'CAIPE-LLM-PROVIDER',
  azureOpenaiApiKey: 'AZURE-OPENAI-API-KEY',
  azureOpenaiEndpoint: 'AZURE-OPENAI-ENDPOINT',
  azureOpenaiApiVersion: 'AZURE-OPENAI-API-VERSION',
  azureOpenaiDeployment: 'AZURE-OPENAI-DEPLOYMENT',

  // ArgoCD Agent (cluster-specific - use getClusterSpecificKeyVaultKey())
  argocdToken: 'CAIPE-ARGOCD-TOKEN',
  argocdApiUrl: 'CAIPE-ARGOCD-API-URL',
  argocdVerifySsl: 'CAIPE-ARGOCD-VERIFY-SSL',

  // GitHub Agent (shared - same GitHub PAT)
  githubPat: 'CAIPE-GITHUB-PAT',

  // Backstage Agent (cluster-specific - use getClusterSpecificKeyVaultKey())
  backstageApiToken: 'CAIPE-BACKSTAGE-API-TOKEN',
  backstageUrl: 'CAIPE-BACKSTAGE-URL',

  // Neo4j (shared - same password across clusters)
  neo4jPassword: 'CAIPE-NEO4J-PASSWORD',

  // Embeddings (reuses Azure OpenAI)
  embeddingsApiKey: 'AZURE-OPENAI-API-KEY',
  embeddingsEndpoint: 'AZURE-OPENAI-ENDPOINT',

  // Langfuse (reuses observability Langfuse keys)
  langfusePublicKey: 'LANGFUSE-PUBLIC-KEY',
  langfuseSecretKey: 'LANGFUSE-SECRET-KEY',
} as const;

/**
 * Get cluster-specific Key Vault key name
 * Appends cluster identifier to avoid naming collisions when multiple clusters
 * push to the same Azure Key Vault.
 *
 * @param baseKey Base key name (e.g., 'CAIPE-ARGOCD-TOKEN')
 * @param clusterId Cluster identifier (e.g., 'localdev', 'talos')
 * @returns Cluster-specific key (e.g., 'CAIPE-ARGOCD-TOKEN-LOCALDEV')
 */
export function getClusterSpecificKeyVaultKey(baseKey: string, clusterId: string): string {
  if (!clusterId) {
    return baseKey;
  }
  // Normalize cluster ID to uppercase for Key Vault naming convention
  const normalizedClusterId = clusterId.toUpperCase().replace(/[^A-Z0-9-]/g, '-');
  return `${baseKey}-${normalizedClusterId}`;
}

// =============================================================================
// URL Helpers
// =============================================================================

/**
 * Generate ingress host for CAIPE components
 * @param component Component name (e.g., 'rag-webui', 'ai-platform-engineering')
 * @param baseHost Base host (e.g., 'cnoe.localtest.me')
 */
export function getCaipeIngressHost(component: string, baseHost: string): string {
  return `${component}.${baseHost}`;
}

/**
 * Generate external URL for CAIPE supervisor-agent
 * @param baseHost Base host
 * @param isKind Whether running on KIND (adds port suffix)
 */
export function getCaipeSupervisorUrl(baseHost: string, isKind: boolean): string {
  const portSuffix = isKind ? ':8443' : '';
  return `https://ai-platform-engineering.${baseHost}${portSuffix}`;
}

/**
 * Generate internal service URL for CAIPE components
 * @param serviceName Service name
 * @param port Service port
 * @param namespace Namespace (defaults to ai-platform-engineering)
 */
export function getCaipeServiceUrl(
  serviceName: string,
  port: number,
  namespace: string = CAIPE_NAMESPACE
): string {
  return `http://${serviceName}.${namespace}.svc.cluster.local:${port}`;
}

// =============================================================================
// Resource Helpers
// =============================================================================

/** Memory resource limits for 16GB RAM environments */
export const CAIPE_RESOURCE_LIMITS = {
  neo4j: {
    heap: '1g',
    pagecache: '512m',
    memory: '2Gi',
    cpu: '1000m',
  },
  milvus: {
    memory: '4Gi',
    cpu: '2000m',
  },
  redis: {
    memory: '256Mi',
    cpu: '200m',
  },
  ragServer: {
    memory: '512Mi',
    cpu: '500m',
  },
  supervisorAgent: {
    memory: '1Gi',
    cpu: '500m',
  },
  agentOntology: {
    memory: '3Gi',
    cpu: '1000m',
  },
} as const;

// =============================================================================
// Environment Variable Helpers
// =============================================================================

/**
 * Generate environment variables for supervisor-agent
 */
export function getSupervisorAgentEnvVars(externalUrl: string): Record<string, string> {
  return {
    EXTERNAL_URL: externalUrl,
    RAG_AGENT_PORT: String(CAIPE_PORTS.agentOntology - 1), // 8097 for RAG agent
    AGENT_CONNECTIVITY_ENABLE_BACKGROUND: 'true',
    SKIP_AGENT_CONNECTIVITY_CHECK: 'false',
    FORCE_DEEP_AGENT_ORCHESTRATION: 'true',
    STREAM_SUB_AGENT_TOOL_OUTPUT: 'true',
    ENABLE_ARTIFACT_STREAMING: 'true',
    // Enable sub-agents - agent registry checks for ENABLE_<AGENT_NAME>
    ENABLE_ARGOCD: 'true',
    ENABLE_GITHUB: 'true',
    ENABLE_BACKSTAGE: 'true',
  };
}

/**
 * Generate environment variables for RAG server
 * Uses official CAIPE env var names from docker-compose.yaml
 */
export function getRagServerEnvVars(namespace: string = CAIPE_NAMESPACE): Record<string, string> {
  return {
    // Milvus connection - pymilvus expects http:// prefix for URI format
    MILVUS_URI: `http://milvus.${namespace}.svc.cluster.local:${CAIPE_PORTS.milvus}`,
    // Neo4j connection - uses neo4j:// protocol and ADDR env var name
    NEO4J_ADDR: `neo4j://neo4j.${namespace}.svc.cluster.local:${CAIPE_PORTS.neo4jBolt}`,
    // Neo4j ontology connection - using same instance as main (shares Neo4j with nexigraph)
    NEO4J_ONTOLOGY_ADDR: `neo4j://neo4j.${namespace}.svc.cluster.local:${CAIPE_PORTS.neo4jBolt}`,
    NEO4J_USERNAME: 'neo4j',
    // Redis connection
    REDIS_URL: `redis://redis.${namespace}.svc.cluster.local:${CAIPE_PORTS.redis}/0`,
    // Agent ontology connection for GraphRAG
    ONTOLOGY_AGENT_RESTAPI_ADDR: `http://nexigraph.${namespace}.svc.cluster.local:${CAIPE_PORTS.agentOntology}`,
  };
}

/**
 * Generate environment variables for Agent Ontology (nexigraph)
 * Uses official CAIPE env var names from docker-compose.yaml
 */
export function getAgentOntologyEnvVars(namespace: string = CAIPE_NAMESPACE): Record<string, string> {
  return {
    // Neo4j connection (main graph)
    NEO4J_ADDR: `neo4j://neo4j.${namespace}.svc.cluster.local:${CAIPE_PORTS.neo4jBolt}`,
    // Neo4j ontology connection (using same instance as main for now)
    // In docker-compose, this is a separate neo4j-ontology:7688 but we share one instance
    NEO4J_ONTOLOGY_ADDR: `neo4j://neo4j.${namespace}.svc.cluster.local:${CAIPE_PORTS.neo4jBolt}`,
    NEO4J_USERNAME: 'neo4j',
    // Redis connection
    REDIS_URL: `redis://redis.${namespace}.svc.cluster.local:${CAIPE_PORTS.redis}/0`,
    // Sync interval in seconds (24 hours)
    SYNC_INTERVAL: '86400',
  };
}

// =============================================================================
// Observability Configuration
// =============================================================================

/**
 * CAIPE Observability configuration for Langfuse and OpenTelemetry
 *
 * Traces are routed to BOTH:
 * - Langfuse: LLM-specific insights (token usage, costs, conversation flows)
 * - Tempo: Infrastructure correlation via OTEL Collector
 */
export const CAIPE_OBSERVABILITY = {
  /** Langfuse LLM observability platform */
  langfuse: {
    /** Internal Langfuse service URL */
    host: 'http://langfuse.observability.svc.cluster.local:3000',
    /** Enable Langfuse tracing */
    enabled: 'true',
  },
  /** OpenTelemetry Collector endpoints */
  otel: {
    /** gRPC endpoint for OTEL SDK (port 4317) */
    grpcEndpoint: 'http://otel-collector.observability.svc.cluster.local:4317',
    /** HTTP endpoint for OTEL SDK (port 4318) */
    httpEndpoint: 'http://otel-collector.observability.svc.cluster.local:4318',
  },
  /** Tracing configuration */
  tracing: {
    /** Enable distributed tracing via cnoe-agent-utils */
    enabled: 'true',
  },
  /** Metrics configuration */
  metrics: {
    /** Enable Prometheus metrics export */
    enabled: 'true',
  },
} as const;

/**
 * Generate observability environment variables for CAIPE agents
 * @param serviceName The OTEL service name (e.g., 'caipe-supervisor-agent')
 */
export function getCaipeObservabilityEnvVars(serviceName: string): Record<string, string> {
  return {
    // cnoe-agent-utils tracing control
    ENABLE_TRACING: CAIPE_OBSERVABILITY.tracing.enabled,
    // OpenTelemetry configuration
    OTEL_EXPORTER_OTLP_ENDPOINT: CAIPE_OBSERVABILITY.otel.grpcEndpoint,
    OTEL_SERVICE_NAME: serviceName,
    // Langfuse configuration
    LANGFUSE_ENABLED: CAIPE_OBSERVABILITY.langfuse.enabled,
    LANGFUSE_HOST: CAIPE_OBSERVABILITY.langfuse.host,
    // Prometheus metrics
    METRICS_ENABLED: CAIPE_OBSERVABILITY.metrics.enabled,
  };
}
