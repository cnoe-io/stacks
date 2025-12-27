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
 *
 * Uses Azure Workload Identity via ClusterSecretStore
 */

import { Chart, ChartProps, JsonPatch } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

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
   * @default '-75'
   */
  syncWave?: string;
}

export class CaipeSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'ai-platform-engineering';
    const clusterSecretStoreName = props.clusterSecretStoreName || 'azure-keyvault-store';
    const refreshInterval = props.refreshInterval || '1h';
    const syncWave = props.syncWave || '-75';

    const commonLabels = {
      'app.kubernetes.io/name': 'caipe',
      'app.kubernetes.io/component': 'secrets',
      'app.kubernetes.io/part-of': 'ai-platform-engineering',
    };

    // ==========================================================================
    // Namespace
    // ==========================================================================

    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespace,
        labels: {
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
    });

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
            remoteRef: {
              key: 'CAIPE-LLM-PROVIDER',
            },
          },
          {
            secretKey: 'AZURE_OPENAI_API_KEY',
            remoteRef: {
              key: 'AZURE-OPENAI-API-KEY',
            },
          },
          {
            secretKey: 'AZURE_OPENAI_ENDPOINT',
            remoteRef: {
              key: 'AZURE-OPENAI-ENDPOINT',
            },
          },
          {
            secretKey: 'AZURE_OPENAI_API_VERSION',
            remoteRef: {
              key: 'AZURE-OPENAI-API-VERSION',
            },
          },
          // Also set OPENAI_API_VERSION for compatibility
          {
            secretKey: 'OPENAI_API_VERSION',
            remoteRef: {
              key: 'AZURE-OPENAI-API-VERSION',
            },
          },
          {
            secretKey: 'AZURE_OPENAI_DEPLOYMENT',
            remoteRef: {
              key: 'AZURE-OPENAI-DEPLOYMENT',
            },
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
        labels: commonLabels,
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
              labels: commonLabels,
            },
          },
        },
        data: [
          {
            secretKey: 'ARGOCD_TOKEN',
            remoteRef: {
              key: 'CAIPE-ARGOCD-TOKEN',
            },
          },
          {
            secretKey: 'ARGOCD_API_URL',
            remoteRef: {
              key: 'CAIPE-ARGOCD-API-URL',
            },
          },
          {
            secretKey: 'ARGOCD_VERIFY_SSL',
            remoteRef: {
              key: 'CAIPE-ARGOCD-VERIFY-SSL',
            },
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
        labels: commonLabels,
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
              labels: commonLabels,
            },
          },
        },
        data: [
          {
            secretKey: 'GITHUB_PERSONAL_ACCESS_TOKEN',
            remoteRef: {
              key: 'CAIPE-GITHUB-PAT',
            },
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
        labels: commonLabels,
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
              labels: commonLabels,
            },
          },
        },
        data: [
          {
            secretKey: 'BACKSTAGE_API_TOKEN',
            remoteRef: {
              key: 'CAIPE-BACKSTAGE-API-TOKEN',
            },
          },
          {
            secretKey: 'BACKSTAGE_URL',
            remoteRef: {
              key: 'CAIPE-BACKSTAGE-URL',
            },
          },
        ],
      },
    });
    backstageSecret.addJsonPatch(JsonPatch.add('/metadata/annotations', { 'argocd.argoproj.io/sync-wave': syncWave }));
  }
}
