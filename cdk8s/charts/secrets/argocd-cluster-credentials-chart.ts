/**
 * ArgocdClusterCredentialsChart - Syncs spoke cluster credentials from Azure Key Vault
 *
 * This chart creates an ExternalSecret that syncs spoke cluster credentials
 * (bearer token and CA certificate) from Azure Key Vault and formats them
 * as an ArgoCD cluster secret ready for use.
 *
 * The synced secret is directly usable by ArgoCD for cluster registration.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';
import {
  SpokeClusterName,
  getSpokeCluster,
  getClusterSecretName,
  getExternalSecretName,
  getAzureKeyVaultSecretNames,
  isSpokeCluster,
} from '../../lib/cluster-registry';

export interface ArgocdClusterCredentialsChartProps extends ChartProps {
  /**
   * Spoke cluster name to create credentials for
   */
  clusterName: SpokeClusterName;

  /**
   * Namespace where the secret will be created
   * @default 'argocd'
   */
  namespace?: string;

  /**
   * ClusterSecretStore name for Azure Key Vault
   * @default 'azure-keyvault-store'
   */
  secretStoreName?: string;

  /**
   * Refresh interval for credentials
   * @default '1h'
   */
  refreshInterval?: string;

  /**
   * ArgoCD sync wave for the external secret
   * Should be before cluster secret (-80 < -75)
   * @default '-80'
   */
  syncWave?: string;
}

/**
 * ArgoCD Cluster Credentials Chart
 *
 * Creates an ExternalSecret that:
 * 1. Pulls bearer token from Azure Key Vault (ARGOCD-CLUSTER-<NAME>-TOKEN)
 * 2. Pulls CA certificate from Azure Key Vault (ARGOCD-CLUSTER-<NAME>-CA)
 * 3. Templates them into an ArgoCD-compatible cluster secret format
 */
export class ArgocdClusterCredentialsChart extends Chart {
  public readonly secretName: string;
  public readonly externalSecretName: string;

  constructor(scope: Construct, id: string, props: ArgocdClusterCredentialsChartProps) {
    super(scope, id, props);

    const {
      clusterName,
      namespace = 'argocd',
      secretStoreName = 'azure-keyvault-store',
      refreshInterval = '1h',
      syncWave = '-80',
    } = props;

    // Validate cluster name
    if (!isSpokeCluster(clusterName)) {
      throw new Error(
        `Invalid spoke cluster name: ${clusterName}. ` +
          `Valid names: hetzner, thinkpad, ryzen, talos`
      );
    }

    const spokeConfig = getSpokeCluster(clusterName);
    const keyVaultKeys = getAzureKeyVaultSecretNames(clusterName);
    this.secretName = getClusterSecretName(clusterName);
    this.externalSecretName = getExternalSecretName(clusterName);

    // Create ExternalSecret that syncs credentials and templates ArgoCD cluster secret
    new ExternalSecret(this, 'cluster-credentials', {
      metadata: {
        name: this.externalSecretName,
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app.kubernetes.io/managed-by': 'cdk8s',
          'app.kubernetes.io/name': this.externalSecretName,
          'app.kubernetes.io/component': 'cluster-credentials',
          'app.kubernetes.io/part-of': 'hub-spoke',
          'cluster-host': clusterName,
        },
      },
      spec: {
        refreshInterval,
        secretStoreRef: {
          name: secretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: this.secretName,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                // Required label for ArgoCD cluster discovery
                'argocd.argoproj.io/secret-type': 'cluster',
                'cluster-host': clusterName,
                'cluster-type': spokeConfig.environment,
                'managed-by': 'external-secrets',
                ...spokeConfig.labels,
              },
              annotations: {
                'external-secrets.io/managed-by': 'external-secrets',
              },
            },
            data: {
              // Human-readable cluster name
              name: clusterName,
              // Kubernetes API server URL via Tailscale
              server: spokeConfig.serverUrl,
              // Connection configuration JSON
              // Uses Go template syntax for ExternalSecret templating
              config: `{
  "tlsClientConfig": {
    "insecure": false,
    "caData": "{{ .caData }}"
  },
  "bearerToken": "{{ .bearerToken }}"
}`,
            },
          },
        },
        data: [
          {
            // Bearer token for ServiceAccount authentication
            secretKey: 'bearerToken',
            remoteRef: {
              key: keyVaultKeys.tokenKey,
            },
          },
          {
            // CA certificate for TLS verification
            secretKey: 'caData',
            remoteRef: {
              key: keyVaultKeys.caKey,
            },
          },
        ],
      },
    });
  }
}
