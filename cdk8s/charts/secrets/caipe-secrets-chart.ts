/**
 * CaipeSecretsChart - External Secrets for CAIPE (AI Platform Engineering)
 *
 * This chart creates ExternalSecret resources to sync CAIPE secrets
 * from Azure Key Vault via External Secrets Operator.
 *
 * Creates the following secrets in ai-platform-engineering namespace:
 * 1. llm-secret - Azure OpenAI credentials for embeddings and LLM calls
 * 2. agent-argocd-secret - ArgoCD API credentials for agent-argocd
 * 3. agent-github-secret - GitHub PAT for agent-github
 * 4. agent-backstage-secret - Backstage API credentials for agent-backstage
 * 5. neo4j-secret - Neo4j database password
 * 6. embeddings-secret - Embeddings provider (reuses Azure OpenAI)
 * 7. langfuse-api-keys - Langfuse tracing API credentials
 *
 * Uses Azure Workload Identity via ClusterSecretStore
 */

import { Chart, ChartProps, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';
import {
  CAIPE_NAMESPACE,
  CAIPE_SECRET_STORE,
  CAIPE_REFRESH_INTERVAL,
  CAIPE_SYNC_WAVES,
  CAIPE_KEYVAULT_KEYS,
  getCaipeCommonLabels,
} from '../../lib/caipe-helpers';

export interface CaipeSecretsChartProps extends ChartProps {
  /**
   * Namespace for CAIPE secrets
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * ClusterSecretStore name
   * @default 'azure-keyvault-store'
   */
  clusterSecretStoreName?: string;

  /**
   * Secret refresh interval
   * @default '1h'
   */
  refreshInterval?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '-80'
   */
  syncWave?: string;
}

export class CaipeSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const clusterSecretStoreName = props.clusterSecretStoreName || CAIPE_SECRET_STORE;
    const refreshInterval = props.refreshInterval || CAIPE_REFRESH_INTERVAL;
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.secrets;

    const commonLabels = getCaipeCommonLabels('secrets');

    // ==========================================================================
    // LLM Secret - Azure OpenAI credentials
    // ==========================================================================

    const llmSecret = new ExternalSecret(this, 'llm-secret', {
      metadata: {
        name: 'llm-secret',
        namespace: namespace,
        labels: commonLabels,
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'llm-secret',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: commonLabels,
            },
          },
        },
        data: [
          {
            secretKey: 'LLM_PROVIDER',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.llmProvider },
          },
          {
            secretKey: 'AZURE_OPENAI_API_KEY',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.azureOpenaiApiKey },
          },
          {
            secretKey: 'AZURE_OPENAI_ENDPOINT',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.azureOpenaiEndpoint },
          },
          {
            secretKey: 'AZURE_OPENAI_API_VERSION',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.azureOpenaiApiVersion },
          },
          {
            secretKey: 'OPENAI_API_VERSION',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.azureOpenaiApiVersion },
          },
          {
            secretKey: 'AZURE_OPENAI_DEPLOYMENT',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.azureOpenaiDeployment },
          },
        ],
      },
    });
    llmSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ==========================================================================
    // Agent ArgoCD Secret
    // ==========================================================================

    const argocdSecret = new ExternalSecret(this, 'agent-argocd-secret', {
      metadata: {
        name: 'agent-argocd-secret',
        namespace: namespace,
        labels: { ...commonLabels, 'app.kubernetes.io/component': 'agent-argocd' },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'agent-argocd-secret',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: { ...commonLabels, 'app.kubernetes.io/component': 'agent-argocd' },
            },
          },
        },
        data: [
          {
            secretKey: 'ARGOCD_TOKEN',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.argocdToken },
          },
          {
            secretKey: 'ARGOCD_API_URL',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.argocdApiUrl },
          },
          {
            secretKey: 'ARGOCD_VERIFY_SSL',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.argocdVerifySsl },
          },
        ],
      },
    });
    argocdSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ==========================================================================
    // Agent GitHub Secret
    // ==========================================================================

    const githubSecret = new ExternalSecret(this, 'agent-github-secret', {
      metadata: {
        name: 'agent-github-secret',
        namespace: namespace,
        labels: { ...commonLabels, 'app.kubernetes.io/component': 'agent-github' },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'agent-github-secret',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: { ...commonLabels, 'app.kubernetes.io/component': 'agent-github' },
            },
          },
        },
        data: [
          {
            secretKey: 'GITHUB_PERSONAL_ACCESS_TOKEN',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.githubPat },
          },
        ],
      },
    });
    githubSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ==========================================================================
    // Agent Backstage Secret
    // ==========================================================================

    const backstageSecret = new ExternalSecret(this, 'agent-backstage-secret', {
      metadata: {
        name: 'agent-backstage-secret',
        namespace: namespace,
        labels: { ...commonLabels, 'app.kubernetes.io/component': 'agent-backstage' },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'agent-backstage-secret',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: { ...commonLabels, 'app.kubernetes.io/component': 'agent-backstage' },
            },
          },
        },
        data: [
          {
            secretKey: 'BACKSTAGE_API_TOKEN',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.backstageApiToken },
          },
          {
            secretKey: 'BACKSTAGE_URL',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.backstageUrl },
          },
        ],
      },
    });
    backstageSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ==========================================================================
    // Neo4j Secret
    // ==========================================================================

    const neo4jSecret = new ExternalSecret(this, 'neo4j-secret', {
      metadata: {
        name: 'neo4j-secret',
        namespace: namespace,
        labels: { ...commonLabels, 'app.kubernetes.io/component': 'neo4j' },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'neo4j-secret',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: { ...commonLabels, 'app.kubernetes.io/component': 'neo4j' },
            },
            data: {
              // Neo4j expects NEO4J_AUTH in format: username/password (for neo4j server)
              'NEO4J_AUTH': 'neo4j/{{ .password }}',
              // NEO4J_PASSWORD is for clients (rag-server, nexigraph) that need separate password
              'NEO4J_PASSWORD': '{{ .password }}',
            },
          },
        },
        data: [
          {
            secretKey: 'password',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.neo4jPassword },
          },
        ],
      },
    });
    neo4jSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ==========================================================================
    // Embeddings Secret (reuses Azure OpenAI for text-embedding-3-small)
    // ==========================================================================

    const embeddingsSecret = new ExternalSecret(this, 'embeddings-secret', {
      metadata: {
        name: 'embeddings-secret',
        namespace: namespace,
        labels: { ...commonLabels, 'app.kubernetes.io/component': 'embeddings' },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'embeddings-secret',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: { ...commonLabels, 'app.kubernetes.io/component': 'embeddings' },
            },
          },
        },
        data: [
          {
            secretKey: 'EMBEDDINGS_API_KEY',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.embeddingsApiKey },
          },
          {
            secretKey: 'EMBEDDINGS_ENDPOINT',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.embeddingsEndpoint },
          },
        ],
      },
    });
    embeddingsSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));

    // ==========================================================================
    // Langfuse API Keys - For LLM observability/tracing
    // ==========================================================================

    const langfuseSecret = new ExternalSecret(this, 'langfuse-api-keys', {
      metadata: {
        name: 'langfuse-api-keys',
        namespace: namespace,
        labels: { ...commonLabels, 'app.kubernetes.io/component': 'tracing' },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'langfuse-api-keys',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: { ...commonLabels, 'app.kubernetes.io/component': 'tracing' },
            },
          },
        },
        data: [
          {
            secretKey: 'LANGFUSE_PUBLIC_KEY',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.langfusePublicKey },
          },
          {
            secretKey: 'LANGFUSE_SECRET_KEY',
            remoteRef: { key: CAIPE_KEYVAULT_KEYS.langfuseSecretKey },
          },
        ],
      },
    });
    langfuseSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));
  }
}
