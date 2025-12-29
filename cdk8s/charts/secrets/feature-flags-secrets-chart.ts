/**
 * FeatureFlagsSecretsChart - External Secrets for Feature Flags
 *
 * This chart creates ExternalSecret resources to sync Flipt secrets
 * from Azure Key Vault via External Secrets Operator.
 *
 * Syncs the following secrets:
 * - FLIPT-OIDC-CLIENT-SECRET: Keycloak OIDC client secret for Flipt
 * - FLIPT-GIT-TOKEN: Git token for repository access (optional)
 *
 * Uses Azure Workload Identity via ClusterSecretStore.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
  ExternalSecretSpecDataSourceRefStoreRefKind,
} from '../../imports/external-secrets.io';

export interface FeatureFlagsSecretsChartProps extends ChartProps {
  /**
   * Namespace for the secrets
   * @default 'feature-flags'
   */
  namespace?: string;

  /**
   * ClusterSecretStore name for Azure Key Vault
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
   * @default '-85'
   */
  syncWave?: string;
}

export class FeatureFlagsSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: FeatureFlagsSecretsChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'feature-flags';
    const clusterSecretStoreName = props.clusterSecretStoreName || 'azure-keyvault-store';
    const refreshInterval = props.refreshInterval || '1h';
    const syncWave = props.syncWave || '-85';

    // Base host for Keycloak URL
    const baseHost = process.env.INGRESS_HOST || 'cnoe.localtest.me';
    const isKind = baseHost === 'cnoe.localtest.me';
    const portSuffix = isKind ? ':8443' : '';

    // Keycloak OIDC URLs
    const keycloakUrl = isKind
      ? `https://${baseHost}${portSuffix}/keycloak/realms/cnoe`
      : `http://keycloak.keycloak.svc.cluster.local:8080/keycloak/realms/cnoe`;

    // ExternalSecret: Flipt OIDC credentials from Keycloak ClusterSecretStore
    // This expects a 'flipt' client to be created in the cnoe realm
    new ExternalSecret(this, 'flipt-oidc', {
      metadata: {
        name: 'flipt-oidc',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'flipt',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'feature-flags',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        // Use 1m refresh to handle race condition where keycloak-clients secret
        // may not exist yet (created by keycloak-config PostSync Job)
        refreshInterval: '1m',
        secretStoreRef: {
          name: 'keycloak',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'flipt-oidc',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'flipt',
                'app.kubernetes.io/component': 'secrets',
              },
            },
            data: {
              // Flipt OIDC configuration
              'FLIPT_AUTHENTICATION_METHODS_OIDC_METHOD_KEYCLOAK_ENABLED': 'true',
              'FLIPT_AUTHENTICATION_METHODS_OIDC_METHOD_KEYCLOAK_CLIENT_ID': 'flipt',
              'FLIPT_AUTHENTICATION_METHODS_OIDC_METHOD_KEYCLOAK_CLIENT_SECRET': '{{ .FLIPT_CLIENT_SECRET }}',
              'FLIPT_AUTHENTICATION_METHODS_OIDC_METHOD_KEYCLOAK_ISSUER_URL': keycloakUrl,
              'FLIPT_AUTHENTICATION_METHODS_OIDC_METHOD_KEYCLOAK_REDIRECT_ADDRESS': `https://flipt.${baseHost}${portSuffix}`,
              // Scopes for role mapping
              'FLIPT_AUTHENTICATION_METHODS_OIDC_METHOD_KEYCLOAK_SCOPES': 'openid,profile,email,roles',
            },
          },
        },
        data: [
          {
            secretKey: 'FLIPT_CLIENT_SECRET',
            remoteRef: {
              key: 'keycloak-clients',
              property: 'FLIPT_CLIENT_SECRET',
            },
          },
        ],
      },
    });

    // ExternalSecret: Git credentials for Flipt Git backend
    // This allows Flipt to read/write flag configurations from Git
    new ExternalSecret(this, 'flipt-git-credentials', {
      metadata: {
        name: 'flipt-git-credentials',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'flipt',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'feature-flags',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        refreshInterval: '0',  // Static credential
        secretStoreRef: {
          name: 'gitea',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'flipt-git-credentials',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'flipt',
                'app.kubernetes.io/component': 'secrets',
              },
            },
            data: {
              // Git credentials for Flipt storage backend
              'FLIPT_STORAGE_GIT_AUTHENTICATION_BASIC_USERNAME': '{{ .username }}',
              'FLIPT_STORAGE_GIT_AUTHENTICATION_BASIC_PASSWORD': '{{ .password }}',
            },
          },
        },
        data: [
          {
            secretKey: 'username',
            remoteRef: {
              key: 'gitea-credential',
              property: 'username',
            },
          },
          {
            secretKey: 'password',
            remoteRef: {
              key: 'gitea-credential',
              property: 'password',
            },
          },
        ],
      },
    });

    // ExternalSecret: Flipt database credentials (optional, for audit logs)
    // Using Azure Key Vault for stable secrets
    new ExternalSecret(this, 'flipt-db-credentials', {
      metadata: {
        name: 'flipt-db-credentials',
        namespace: namespace,
        labels: {
          'app.kubernetes.io/name': 'flipt',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'feature-flags',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: clusterSecretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'flipt-db-credentials',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app.kubernetes.io/name': 'flipt',
                'app.kubernetes.io/component': 'secrets',
              },
            },
          },
        },
        data: [
          {
            secretKey: 'FLIPT_DB_URL',
            remoteRef: {
              key: 'FLIPT-DB-URL',
            },
          },
        ],
      },
    });
  }
}
