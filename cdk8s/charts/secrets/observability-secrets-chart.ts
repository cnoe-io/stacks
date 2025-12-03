/**
 * ObservabilitySecretsChart - External Secrets for Observability Stack
 *
 * This chart creates ExternalSecret resources to sync Langfuse secrets
 * from Azure Key Vault via External Secrets Operator.
 *
 * Syncs the following secrets:
 * - LANGFUSE-POSTGRES-USER: PostgreSQL username
 * - LANGFUSE-POSTGRES-PASSWORD: PostgreSQL password
 * - LANGFUSE-NEXTAUTH-SECRET: NextAuth.js secret
 * - LANGFUSE-SALT: Langfuse salt
 * - LANGFUSE-ENCRYPTION-KEY: Encryption key
 * - LANGFUSE-PUBLIC-KEY: API public key (for SDK)
 * - LANGFUSE-SECRET-KEY: API secret key (for SDK)
 *
 * Uses Azure Workload Identity via ClusterSecretStore.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

export interface ObservabilitySecretsChartProps extends ChartProps {
  /**
   * Namespace for the secrets
   * @default 'observability'
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
}

export class ObservabilitySecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: ObservabilitySecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'observability';
    const clusterSecretStoreName = props.clusterSecretStoreName || 'azure-keyvault-store';
    const refreshInterval = props.refreshInterval || '1h';

    // ExternalSecret for Langfuse PostgreSQL credentials
    new ExternalSecret(this, 'langfuse-postgres-credentials', {
      metadata: {
        name: 'langfuse-postgres-credentials',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'langfuse-postgres',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'observability',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-75',
        },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'langfuse-postgres-credentials',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'langfuse-postgres',
                'app.kubernetes.io/component': 'secrets',
              },
            },
          },
        },
        data: [
          {
            secretKey: 'POSTGRES_USER',
            remoteRef: {
              key: 'LANGFUSE-POSTGRES-USER',
            },
          },
          {
            secretKey: 'POSTGRES_PASSWORD',
            remoteRef: {
              key: 'LANGFUSE-POSTGRES-PASSWORD',
            },
          },
        ],
      },
    });

    // ExternalSecret for Langfuse auth secrets
    new ExternalSecret(this, 'langfuse-auth', {
      metadata: {
        name: 'langfuse-auth',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'langfuse',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'observability',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-75',
        },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'langfuse-auth',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'langfuse',
                'app.kubernetes.io/component': 'secrets',
              },
            },
          },
        },
        data: [
          {
            secretKey: 'NEXTAUTH_SECRET',
            remoteRef: {
              key: 'LANGFUSE-NEXTAUTH-SECRET',
            },
          },
          {
            secretKey: 'SALT',
            remoteRef: {
              key: 'LANGFUSE-SALT',
            },
          },
          {
            secretKey: 'ENCRYPTION_KEY',
            remoteRef: {
              key: 'LANGFUSE-ENCRYPTION-KEY',
            },
          },
        ],
      },
    });

    // ExternalSecret for Langfuse API keys (for SDK usage in agents)
    new ExternalSecret(this, 'langfuse-api', {
      metadata: {
        name: 'langfuse-api',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'langfuse',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'observability',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-75',
        },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'langfuse-api',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'langfuse',
                'app.kubernetes.io/component': 'secrets',
              },
            },
          },
        },
        data: [
          {
            secretKey: 'PUBLIC_KEY',
            remoteRef: {
              key: 'LANGFUSE-PUBLIC-KEY',
            },
          },
          {
            secretKey: 'SECRET_KEY',
            remoteRef: {
              key: 'LANGFUSE-SECRET-KEY',
            },
          },
        ],
      },
    });
  }
}
