/**
 * TailscaleSecretsChart - Manages Tailscale auth key via External Secrets Operator
 *
 * This chart creates an ExternalSecret resource that syncs the Tailscale auth key
 * from Azure Key Vault into a Kubernetes secret for use by Tailscale Services pods.
 *
 * The auth key is used for automatic Tailscale authentication for Tailscale Serve pods.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

export interface TailscaleSecretsChartProps extends ChartProps {
  /**
   * Target namespace for the secret
   * @default "tailscale"
   */
  namespace?: string;

  /**
   * ClusterSecretStore name
   * @default 'azure-keyvault-store'
   */
  secretStoreName?: string;

  /**
   * Target secret name for auth key
   * @default 'tailscale-auth-key'
   */
  authKeySecretName?: string;

  /**
   * Target secret name for OAuth credentials
   * @default 'operator-oauth'
   */
  oauthSecretName?: string;

  /**
   * Refresh interval for secrets
   * @default '24h'
   */
  refreshInterval?: string;

  /**
   * ArgoCD sync wave for secret creation
   * @default "-70"
   */
  syncWave?: string;
}

export class TailscaleSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleSecretsChartProps = {}) {
    super(scope, id, props);

    const {
      namespace = 'tailscale',
      secretStoreName = 'azure-keyvault-store',
      authKeySecretName = 'tailscale-auth-key',
      oauthSecretName = 'operator-oauth',
      refreshInterval = '24h',
      syncWave = '-70',
    } = props;

    // ExternalSecret for Tailscale Auth Key (used by Tailscale Serve pods)
    new ExternalSecret(this, 'tailscale-auth-key', {
      metadata: {
        name: authKeySecretName,
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app.kubernetes.io/managed-by': 'cdk8s',
          'app.kubernetes.io/name': authKeySecretName,
          'app.kubernetes.io/component': 'secrets',
        },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: secretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: authKeySecretName,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            data: {
              // Export auth key for use by Tailscale Serve pods
              'authKey': '{{ .tailscale_auth_key }}',
            },
          },
        },
        data: [
          {
            secretKey: 'tailscale_auth_key',
            remoteRef: {
              key: 'TAILSCALE-AUTH-KEY',
            },
          },
        ],
      },
    });

    // ExternalSecret for Tailscale OAuth credentials (used by Tailscale Operator)
    new ExternalSecret(this, 'operator-oauth', {
      metadata: {
        name: oauthSecretName,
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app.kubernetes.io/managed-by': 'cdk8s',
          'app.kubernetes.io/name': oauthSecretName,
          'app.kubernetes.io/component': 'secrets',
        },
      },
      spec: {
        refreshInterval: refreshInterval,
        secretStoreRef: {
          name: secretStoreName,
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: oauthSecretName,
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            data: {
              // Keys expected by Tailscale Operator Helm chart
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
