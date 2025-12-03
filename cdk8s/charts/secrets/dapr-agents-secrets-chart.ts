/**
 * DaprAgentsSecretsChart - External Secrets for LLM Provider API Keys
 *
 * This chart creates ExternalSecret resources to sync LLM API keys
 * from Azure Key Vault via External Secrets Operator for Dapr Agents.
 *
 * Syncs the following secrets:
 * - OPENAI_API_KEY from Azure Key Vault secret OPENAI-API-KEY
 * - ANTHROPIC_API_KEY from Azure Key Vault secret ANTHROPIC-API-KEY
 * - GEMINI_API_KEY from Azure Key Vault secret GEMINI-API-KEY
 *
 * Uses Azure Workload Identity via ClusterSecretStore.
 * These are the same secrets as kagent-secrets-chart but in a different namespace.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

export interface DaprAgentsSecretsChartProps extends ChartProps {
  /**
   * Namespace for the secret
   * @default 'dapr-agents'
   */
  namespace?: string;

  /**
   * Name of the target Kubernetes secret
   * @default 'dapr-agents-llm-providers'
   */
  secretName?: string;

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
}

export class DaprAgentsSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: DaprAgentsSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'dapr-agents';
    const secretName = props.secretName || 'dapr-agents-llm-providers';
    const clusterSecretStoreName = props.clusterSecretStoreName || 'azure-keyvault-store';
    const refreshInterval = props.refreshInterval || '1h';

    // Create ExternalSecret for LLM provider API keys
    new ExternalSecret(this, 'dapr-agents-llm-providers', {
      metadata: {
        name: secretName,
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'dapr-agents',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
      spec: {
        // Refresh interval for secret synchronization
        refreshInterval: refreshInterval,

        // Reference to ClusterSecretStore (Azure Key Vault)
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },

        // Target Kubernetes secret configuration
        target: {
          name: secretName,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'dapr-agents',
                'app.kubernetes.io/component': 'secrets',
              },
            },
          },
        },

        // Data mapping from Azure Key Vault to Kubernetes secret
        data: [
          // OpenAI API Key (fallback LLM)
          {
            secretKey: 'OPENAI_API_KEY',
            remoteRef: {
              key: 'OPENAI-API-KEY',
            },
          },
          // Anthropic API Key (primary LLM - Claude Opus 4.5)
          {
            secretKey: 'ANTHROPIC_API_KEY',
            remoteRef: {
              key: 'ANTHROPIC-API-KEY',
            },
          },
          // Google Gemini API Key (alternative LLM)
          {
            secretKey: 'GEMINI_API_KEY',
            remoteRef: {
              key: 'GEMINI-API-KEY',
            },
          },
        ],
      },
    });
  }
}
