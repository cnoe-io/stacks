/**
 * ArgocdClusterSecretChart - Generates ArgoCD cluster secret for spoke cluster registration
 *
 * This chart creates an ArgoCD cluster secret that references credentials synced
 * from Azure Key Vault via External Secrets Operator. The secret enables ArgoCD
 * on the hub cluster to manage applications on spoke clusters.
 *
 * ArgoCD discovers clusters via the `argocd.argoproj.io/secret-type: cluster` label.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeSecret } from '../../imports/k8s';
import {
  SpokeClusterName,
  getSpokeCluster,
  getClusterSecretName,
  isSpokeCluster,
} from '../../lib/cluster-registry';

export interface ArgocdClusterSecretChartProps extends ChartProps {
  /**
   * Spoke cluster name to register
   */
  clusterName: SpokeClusterName;

  /**
   * ArgoCD namespace where the cluster secret will be created
   * @default 'argocd'
   */
  argocdNamespace?: string;

  /**
   * Name of the Kubernetes secret containing the synced credentials
   * This secret is created by ArgocdClusterCredentialsChart via ExternalSecret
   * @default 'cluster-<clusterName>-credentials'
   */
  credentialsSecretName?: string;

  /**
   * ArgoCD sync wave for the cluster secret
   * Should be after ESO syncs credentials (-75 > -80)
   * @default '-75'
   */
  syncWave?: string;

  /**
   * Additional labels for the cluster secret
   */
  additionalLabels?: Record<string, string>;
}

/**
 * ArgoCD Cluster Secret Chart
 *
 * Creates a cluster secret that ArgoCD uses to connect to spoke clusters.
 * The actual credentials (bearerToken, caData) come from a separate
 * credentials secret synced by ESO from Azure Key Vault.
 */
export class ArgocdClusterSecretChart extends Chart {
  public readonly secretName: string;

  constructor(scope: Construct, id: string, props: ArgocdClusterSecretChartProps) {
    super(scope, id, props);

    const {
      clusterName,
      argocdNamespace = 'argocd',
      credentialsSecretName,
      syncWave = '-75',
      additionalLabels = {},
    } = props;

    // Validate cluster name
    if (!isSpokeCluster(clusterName)) {
      throw new Error(
        `Invalid spoke cluster name: ${clusterName}. ` +
          `Valid names: hetzner, thinkpad, ryzen, talos`
      );
    }

    const spokeConfig = getSpokeCluster(clusterName);
    this.secretName = getClusterSecretName(clusterName);
    const credsSecretName = credentialsSecretName || `${this.secretName}-credentials`;

    // Create the ArgoCD cluster secret
    // The config JSON is constructed from the credentials secret using templating
    // This secret will be populated by an init container or external process
    // that reads from the credentials secret and formats the config JSON
    new KubeSecret(this, 'cluster-secret', {
      metadata: {
        name: this.secretName,
        namespace: argocdNamespace,
        labels: {
          // Required label for ArgoCD to discover this as a cluster
          'argocd.argoproj.io/secret-type': 'cluster',
          // Custom labels for filtering and organization
          'cluster-host': clusterName,
          'cluster-type': spokeConfig.environment,
          'managed-by': 'cdk8s',
          'app.kubernetes.io/name': this.secretName,
          'app.kubernetes.io/component': 'cluster-registration',
          'app.kubernetes.io/part-of': 'hub-spoke',
          ...spokeConfig.labels,
          ...additionalLabels,
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
          'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          // Track the credentials source
          'hub-spoke/credentials-secret': credsSecretName,
          'hub-spoke/server-url': spokeConfig.serverUrl,
        },
      },
      type: 'Opaque',
      // Note: stringData values will be base64 encoded automatically by Kubernetes
      // The actual values will be populated by the ExternalSecret -> Secret chain
      stringData: {
        // Human-readable cluster name (appears in ArgoCD UI)
        name: clusterName,
        // Kubernetes API server URL via Tailscale
        server: spokeConfig.serverUrl,
        // Connection configuration JSON
        // This is templated and will be replaced by ArgocdClusterCredentialsChart
        // which uses ExternalSecret to pull from Azure Key Vault
        config: JSON.stringify(
          {
            tlsClientConfig: {
              insecure: false,
              // Placeholder - actual CA from credentials secret
              caData: '{{ .caData }}',
            },
            // Placeholder - actual token from credentials secret
            bearerToken: '{{ .bearerToken }}',
          },
          null,
          2
        ),
      },
    });
  }
}
