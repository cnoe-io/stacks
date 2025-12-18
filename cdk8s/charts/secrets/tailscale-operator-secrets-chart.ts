/**
 * TailscaleOperatorSecretsChart - Manages Tailscale OAuth credentials via External Secrets Operator
 *
 * This chart creates an ExternalSecret resource that syncs the Tailscale OAuth client credentials
 * from Azure Key Vault into a Kubernetes secret for use by the Tailscale Kubernetes Operator.
 *
 * The OAuth credentials are used for operator authentication to manage Tailscale resources.
 *
 * Prerequisites:
 * - Create OAuth client in Tailscale Admin Console with scopes: Devices Core, Auth Keys, Services
 * - Store credentials in Azure Key Vault as:
 *   - TAILSCALE-OAUTH-CLIENT-ID
 *   - TAILSCALE-OAUTH-CLIENT-SECRET
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';
import { addExternalSecretsWebhookGate } from '../../lib/external-secrets-hooks';

export interface TailscaleOperatorSecretsChartProps extends ChartProps {
  /**
   * Target namespace for the secret
   * @default "tailscale"
   */
  namespace?: string;

  /**
   * ArgoCD sync wave for secret creation
   * @default "-85"
   */
  syncWave?: string;

  /**
   * Name of the target Kubernetes secret
   * @default "operator-oauth" - matches Helm chart default
   */
  secretName?: string;
}

export class TailscaleOperatorSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleOperatorSecretsChartProps = {}) {
    super(scope, id, props);

    const {
      namespace = 'tailscale',
      syncWave = '-85',
      secretName = 'operator-oauth',  // Must match Helm chart default
    } = props;

    addExternalSecretsWebhookGate(this, namespace);

    // ExternalSecret for Tailscale OAuth credentials (used by Tailscale Operator)
    new ExternalSecret(this, 'tailscale-operator-oauth', {
      metadata: {
        name: secretName,
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app.kubernetes.io/name': 'tailscale-operator',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'tailscale',
        },
      },
      spec: {
        refreshInterval: '24h',  // Refresh daily
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: secretName,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            data: {
              // OAuth client credentials for Tailscale Operator
              // Keys must be 'client_id' and 'client_secret' (underscores) to match Helm chart expectations
              'client_id': '{{ .oauth_client_id }}',
              'client_secret': '{{ .oauth_client_secret }}',
            },
          },
        },
        data: [
          {
            secretKey: 'oauth_client_id',
            remoteRef: {
              key: 'TAILSCALE-OAUTH-CLIENT-ID',
            },
          },
          {
            secretKey: 'oauth_client_secret',
            remoteRef: {
              key: 'TAILSCALE-OAUTH-CLIENT-SECRET',
            },
          },
        ],
      },
    });
  }
}
