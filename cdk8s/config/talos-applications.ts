/**
 * Application Configuration for Talos Linux Cluster
 * Feature: 102-bootstrap-talos-argocd
 *
 * Defines all applications to be managed by ArgoCD in the Talos cluster.
 * Applications are deployed in sync wave order (lower = earlier).
 *
 * Sync Wave Ordering:
 *   -110: Foundation (CNI, critical infra)
 *   -105: Storage (local-path-provisioner)
 *   -100: Operators (ESO, Tailscale)
 *    -94: Identity (Workload Identity patches)
 *    -92: Stores (ClusterSecretStore)
 *    -85: Secrets (ExternalSecrets for auth)
 *    -80: Access (Tailscale operator)
 *    -60: Services (Tailscale serve pods)
 *      0: Platform (ArgoCD self-managed)
 *     10: Applications (User workloads)
 */

import { ApplicationConfig } from '../lib/idpbuilder-types';
import { SYNC_WAVES } from '../lib/sync-waves';

// Re-export for backward compatibility
export { SYNC_WAVES } from '../lib/sync-waves';

/**
 * Environment variable helpers with defaults
 */
const env = {
  get: (name: string, defaultValue?: string): string => {
    const value = process.env[name] || defaultValue;
    if (!value) {
      throw new Error(`Required environment variable not set: ${name}`);
    }
    return value;
  },
  getOptional: (name: string, defaultValue: string): string => {
    return process.env[name] || defaultValue;
  },
};

/**
 * Talos cluster application configurations
 * Ordered by sync wave for deployment sequencing
 */
export const talosApplications: ApplicationConfig[] = [
  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -105: Storage Infrastructure
  // Must deploy before anything requiring persistent storage
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'local-path-provisioner',
    namespace: 'local-path-storage',
    chart: {
      type: 'LocalPathProvisionerChart',
      props: {
        storagePath: '/opt/local-path-provisioner',
        isDefault: true,
      },
    },
    argocd: {
      syncWave: '-105',
      labels: {
        'app.kubernetes.io/component': 'storage',
        'app.kubernetes.io/part-of': 'infrastructure',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -100: Operators
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'external-secrets-operator',
    namespace: 'external-secrets',
    chart: {
      type: 'EsoHelmChart',
      props: {
        version: '0.9.13',
        installCrds: true,
        enableWebhook: true,
        replicaCount: 2,
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.OPERATORS,
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'platform',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -94: Identity (Workload Identity Configuration)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'workload-identity-patch',
    namespace: 'external-secrets',
    chart: {
      type: 'WorkloadIdentityPatchChart',
      props: {
        clientId: env.getOptional('AZURE_CLIENT_ID', ''),
        tenantId: env.getOptional('AZURE_TENANT_ID', ''),
        serviceAccountName: 'external-secrets',
        serviceAccountNamespace: 'external-secrets',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.IDENTITY,
      labels: {
        'app.kubernetes.io/component': 'identity',
        'app.kubernetes.io/part-of': 'platform',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['ServerSideApply=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -92: Secret Stores
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'cluster-secret-store',
    namespace: 'external-secrets',
    chart: {
      type: 'ClusterSecretStoreChart',
      props: {
        storeName: 'azure-keyvault-store',
        keyVaultName: env.getOptional('AZURE_KEYVAULT_NAME', 'talos-keyvault'),
        serviceAccountRef: {
          name: 'external-secrets',
          namespace: 'external-secrets',
        },
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.STORES,
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'platform',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -85: Secrets (ExternalSecrets for Tailscale)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'tailscale-secrets',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleSecretsChart',
      props: {
        secretStoreName: 'azure-keyvault-store',
        authKeySecretName: 'tailscale-auth-key',
        oauthSecretName: 'operator-oauth',
        refreshInterval: '24h',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.SECRETS,
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -80: Access (Tailscale Operator)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'tailscale-operator',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleOperatorChart',
      props: {
        version: '1.76.1',
        hostname: 'talos-operator',
        enableApiServerProxy: true,
        enableHA: false, // Single node for dev
        tags: ['tag:k8s-operator'],
        oauthSecretName: 'operator-oauth',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.ACCESS,
      labels: {
        'app.kubernetes.io/component': 'networking',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -60: Services (Tailscale Serve Pods)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'k8s-api-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'K8sApiTailscaleServeChart',
      props: {
        serviceName: 'k8s-api',
        backendHost: 'kubernetes.default.svc.cluster.local',
        backendPort: 443,
        enableKubectlProxy: true,
        kubectlProxyPort: 8001,
        authKeySecretName: 'tailscale-auth-key',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.SERVICES,
      labels: {
        'app.kubernetes.io/component': 'access',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'argocd-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'ArgoCDTailscaleServeChart',
      props: {
        serviceName: 'argocd',
        backendHost: 'argocd-server.argocd.svc.cluster.local',
        backendPort: 80,  // ArgoCD HA mode exposes HTTP on port 80
        backendHttps: false,  // Use HTTP, not HTTPS
        authKeySecretName: 'tailscale-auth-key',
      },
    },
    argocd: {
      syncWave: SYNC_WAVES.SERVICES,
      labels: {
        'app.kubernetes.io/component': 'access',
        'app.kubernetes.io/part-of': 'tailscale',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -55 to -40: Observability Stack
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'observability-namespace',
    namespace: 'observability',
    chart: {
      type: 'ObservabilityNamespaceChart',
      props: {
        namespaceName: 'observability',
      },
    },
    argocd: {
      syncWave: '-55',
      labels: {
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true'],
      },
    },
  },

  {
    name: 'observability-secrets',
    namespace: 'observability',
    chart: {
      type: 'ObservabilitySecretsChart',
      props: {
        namespace: 'observability',
        clusterSecretStoreName: 'azure-keyvault-store',
        refreshInterval: '1h',
      },
    },
    argocd: {
      syncWave: '-54',
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=false'],
        retry: {
          limit: 10,
          backoff: {
            duration: '5s',
            factor: 2,
            maxDuration: '3m',
          },
        },
      },
    },
  },

  {
    name: 'langfuse-postgres',
    namespace: 'observability',
    chart: {
      type: 'LangfusePostgresChart',
      props: {
        namespace: 'observability',
        image: 'postgres:16-alpine',
        storageSize: '20Gi',
        databaseName: 'langfuse',
        credentialsSecretName: 'langfuse-postgres-credentials',
      },
    },
    argocd: {
      syncWave: '-53',
      labels: {
        'app.kubernetes.io/component': 'database',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'langfuse-clickhouse',
    namespace: 'observability',
    chart: {
      type: 'LangfuseClickhouseChart',
      props: {
        namespace: 'observability',
        imageVersion: '24.3',
        storageSize: '10Gi',
      },
    },
    argocd: {
      syncWave: '-52',
      labels: {
        'app.kubernetes.io/component': 'database',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'langfuse-redis',
    namespace: 'observability',
    chart: {
      type: 'LangfuseRedisChart',
      props: {
        namespace: 'observability',
        imageVersion: '7-alpine',
        enablePersistence: false,
      },
    },
    argocd: {
      syncWave: '-52',
      labels: {
        'app.kubernetes.io/component': 'cache',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'langfuse-minio',
    namespace: 'observability',
    chart: {
      type: 'LangfuseMinioChart',
      props: {
        namespace: 'observability',
        storageSize: '10Gi',
        bucketName: 'langfuse',
      },
    },
    argocd: {
      syncWave: '-52',
      labels: {
        'app.kubernetes.io/component': 'blob-storage',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'jaeger',
    namespace: 'observability',
    chart: {
      type: 'JaegerChart',
      props: {
        namespace: 'observability',
        imageVersion: '1.66.0',
        storageSize: '10Gi',
        spanStorageTtl: '168h',
      },
    },
    argocd: {
      syncWave: '-50',
      labels: {
        'app.kubernetes.io/component': 'tracing',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'langfuse',
    namespace: 'observability',
    chart: {
      type: 'LangfuseChart',
      props: {
        namespace: 'observability',
        imageVersion: '3',
        postgresHost: 'langfuse-postgres',
        postgresPort: 5432,
        databaseName: 'langfuse',
        clickhouseHost: 'langfuse-clickhouse',
        clickhouseUser: 'default',
        clickhousePassword: 'clickhouse_langfuse_password',
        redisHost: 'langfuse-redis',
        minioHost: 'langfuse-minio',
        minioUser: 'minioadmin',
        minioPassword: 'minio_langfuse_password',
        credentialsSecretName: 'langfuse-postgres-credentials',
        clickhouseCredentialsSecretName: 'langfuse-clickhouse-credentials',
        minioCredentialsSecretName: 'langfuse-minio-credentials',
        authSecretName: 'langfuse-auth',
        // Access via Tailscale pod hostname (legacy mode)
        nextAuthUrl: 'https://langfuse-tailscale-serve.tail286401.ts.net',
      },
    },
    argocd: {
      syncWave: '-45',
      labels: {
        'app.kubernetes.io/component': 'llm-observability',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'langfuse-tailscale-serve',
    namespace: 'tailscale',
    chart: {
      type: 'LangfuseTailscaleServeChart',
      props: {
        serviceName: 'langfuse',
        backendHost: 'langfuse.observability.svc.cluster.local',
        backendPort: 3000,
        authKeySecretName: 'tailscale-auth-key',
      },
    },
    argocd: {
      syncWave: '-44',  // Deploy right after Langfuse
      labels: {
        'app.kubernetes.io/component': 'access',
        'app.kubernetes.io/part-of': 'observability',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -40 to -20: Dapr Runtime and Agents
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'dapr-crds',
    namespace: 'default',
    chart: {
      type: 'DaprCrdsChart',
      props: {
        daprVersion: 'v1.16.3',
      },
    },
    argocd: {
      syncWave: '-40',
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'dapr-agents',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['ServerSideApply=true', 'Replace=true'],
      },
    },
  },

  {
    name: 'dapr-runtime',
    namespace: 'dapr-system',
    chart: {
      type: 'DaprRuntimeChart',
      props: {
        version: '1.16',
        enableHA: false,
        enableDashboard: true,
        logLevel: 'info',
      },
    },
    argocd: {
      syncWave: '-38',
      labels: {
        'app.kubernetes.io/component': 'control-plane',
        'app.kubernetes.io/part-of': 'dapr-agents',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
      },
    },
  },

  {
    name: 'dapr-agents-redis',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprAgentsRedisChart',
      props: {
        namespace: 'dapr-agents',
        replicas: 1,
        enablePersistence: false,
      },
    },
    argocd: {
      syncWave: '-35',
      labels: {
        'app.kubernetes.io/component': 'state-store',
        'app.kubernetes.io/part-of': 'dapr-agents',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true'],
      },
    },
  },

  {
    name: 'dapr-agents-secrets',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprAgentsSecretsChart',
      props: {
        namespace: 'dapr-agents',
        secretName: 'dapr-agents-llm-providers',
        clusterSecretStoreName: 'azure-keyvault-store',
        refreshInterval: '1h',
      },
    },
    argocd: {
      syncWave: '-34',
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'dapr-agents',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        retry: {
          limit: 10,
          backoff: {
            duration: '5s',
            factor: 2,
            maxDuration: '3m',
          },
        },
      },
    },
  },

  {
    name: 'dapr-components',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprComponentsChart',
      props: {
        namespace: 'dapr-agents',
        redisHost: 'redis-service.dapr-agents.svc.cluster.local:6379',
        llmSecretName: 'dapr-agents-llm-providers',
        anthropicModel: 'claude-opus-4-5-20251101',
        cacheTTL: '10m',
      },
    },
    argocd: {
      syncWave: '-32',
      labels: {
        'app.kubernetes.io/component': 'infrastructure',
        'app.kubernetes.io/part-of': 'dapr-agents',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'dapr-tracing-config',
    namespace: 'dapr-agents',
    chart: {
      type: 'DaprTracingConfigChart',
      props: {
        namespace: 'dapr-agents',
        configName: 'speckit-tracing',
        samplingRate: '1',
        zipkinEndpoint: 'http://jaeger-collector.observability.svc.cluster.local:9411/api/v2/spans',
      },
    },
    argocd: {
      syncWave: '-30',
      labels: {
        'app.kubernetes.io/component': 'tracing',
        'app.kubernetes.io/part-of': 'speckit-agents',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  {
    name: 'speckit-agents-rbac',
    namespace: 'dapr-agents',
    chart: {
      type: 'SpecKitAgentsRbacChart',
      props: {
        namespace: 'dapr-agents',
      },
    },
    argocd: {
      syncWave: '-28',
      labels: {
        'app.kubernetes.io/component': 'rbac',
        'app.kubernetes.io/part-of': 'speckit',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -25 to -15: Gateway API and kgateway
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'gateway-api-crds',
    namespace: 'default',
    chart: {
      type: 'GatewayApiCrdsChart',
      props: {
        version: 'v1.4.0',
      },
    },
    argocd: {
      syncWave: '-25',
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'kgateway',
      },
      syncPolicy: {
        automated: { prune: false, selfHeal: true },
        syncOptions: ['ServerSideApply=true'],
      },
    },
  },

  {
    name: 'kgateway-crds',
    namespace: 'kgateway-system',
    chart: {
      type: 'KgatewayCrdsChart',
      props: {
        version: 'v2.1.1',
      },
    },
    argocd: {
      syncWave: '-24',
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'kgateway',
      },
      syncPolicy: {
        automated: { prune: false, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
      },
    },
  },

  {
    name: 'kgateway',
    namespace: 'kgateway-system',
    chart: {
      type: 'KgatewayChart',
      props: {
        version: 'v2.1.1',
        enableAgentGateway: true,
        enableAiExtension: true,
        replicas: 1,
      },
    },
    argocd: {
      syncWave: '-22',
      labels: {
        'app.kubernetes.io/component': 'platform',
        'app.kubernetes.io/part-of': 'kgateway',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE -20 to -10: kagent AI Agent Framework
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'kagent-crds',
    namespace: 'kagent',
    chart: {
      type: 'KagentCrdsChart',
      props: {
        version: '0.7.4',
      },
    },
    argocd: {
      syncWave: '-20',
      labels: {
        'app.kubernetes.io/component': 'crds',
        'app.kubernetes.io/part-of': 'kagent',
      },
      syncPolicy: {
        automated: { prune: false, selfHeal: true },
        syncOptions: ['CreateNamespace=true', 'ServerSideApply=true'],
      },
    },
  },

  {
    name: 'kagent-secrets',
    namespace: 'kagent',
    chart: {
      type: 'KagentSecretsChart',
      props: {
        namespace: 'kagent',
        secretName: 'kagent-llm-providers',
        clusterSecretStoreName: 'azure-keyvault-store',
        refreshInterval: '1h',
      },
    },
    argocd: {
      syncWave: '-18',
      labels: {
        'app.kubernetes.io/component': 'secrets',
        'app.kubernetes.io/part-of': 'kagent',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['CreateNamespace=false'],
        retry: {
          limit: 10,
          backoff: {
            duration: '5s',
            factor: 2,
            maxDuration: '3m',
          },
        },
      },
    },
  },

  {
    name: 'kagent',
    namespace: 'kagent',
    chart: {
      type: 'KagentChart',
      props: {
        version: '0.7.4',
        defaultProvider: 'openAI',
        enableKmcp: true,
        replicas: 1,
      },
    },
    argocd: {
      syncWave: '-15',
      labels: {
        'app.kubernetes.io/component': 'platform',
        'app.kubernetes.io/part-of': 'kagent',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
        syncOptions: ['ServerSideApply=true'],
      },
    },
  },

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE 0: Platform (ArgoCD Self-Managed - FUTURE)
  // ═══════════════════════════════════════════════════════════════════════════
  // Note: ArgoCD is initially installed via Helm, then can self-manage
  // Add ArgoCD Application for self-management here if needed

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC WAVE 10+: Applications (User Workloads)
  // ═══════════════════════════════════════════════════════════════════════════

  {
    name: 'speckit-agents',
    namespace: 'dapr-agents',
    chart: {
      type: 'SpecKitAgentsChart',
      props: {
        namespace: 'dapr-agents',
        agentImage: 'vpittamp23/speckit-agents',
        imageTag: 'claude-sdk-v9',
        teamName: 'speckit',
        pubsubName: 'messagepubsub',
        workflowStateStore: 'workflowstatestore',
        registryStateStore: 'agentregistrystore',
        memoryStore: 'memorystore',
        conversationComponent: 'anthropic',
        llmSecretName: 'dapr-agents-llm-providers',
      },
    },
    argocd: {
      syncWave: '50',
      labels: {
        'app.kubernetes.io/component': 'agents',
        'app.kubernetes.io/part-of': 'speckit',
      },
      syncPolicy: {
        automated: { prune: true, selfHeal: true },
      },
    },
  },
];

/**
 * Get applications by sync wave
 */
export function getApplicationsBySyncWave(wave: string): ApplicationConfig[] {
  return talosApplications.filter((app) => app.argocd?.syncWave === wave);
}

/**
 * Get applications sorted by sync wave (for ordered deployment)
 */
export function getApplicationsSortedBySyncWave(): ApplicationConfig[] {
  return [...talosApplications].sort((a, b) => {
    const waveA = parseInt(a.argocd?.syncWave || '0', 10);
    const waveB = parseInt(b.argocd?.syncWave || '0', 10);
    return waveA - waveB;
  });
}

/**
 * Validate that all required chart types are registered
 */
export function validateChartTypes(registeredTypes: string[]): string[] {
  const requiredTypes = new Set(talosApplications.map((app) => app.chart.type));
  const missingTypes: string[] = [];

  Array.from(requiredTypes).forEach((type) => {
    if (!registeredTypes.includes(type)) {
      missingTypes.push(type);
    }
  });

  return missingTypes;
}
