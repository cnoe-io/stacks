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
      syncWave = '-70',
    } = props;

    // ExternalSecret for Tailscale Auth Key (used by Tailscale Serve pods)
    new ExternalSecret(this, 'tailscale-auth-key', {
      metadata: {
        name: 'tailscale-auth-key',
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        refreshInterval: '24h',  // Refresh daily
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'tailscale-auth-key',
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
  }
}
