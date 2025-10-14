/**
 * TailscaleVmSecretsChart - Manages Tailscale VM auth key via External Secrets Operator
 *
 * This chart creates an ExternalSecret resource that syncs the Tailscale auth key
 * from Azure Key Vault into a Kubernetes secret for use by KubeVirt VMs.
 *
 * The auth key is used for automatic Tailscale authentication during VM boot via cloud-init.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

export interface TailscaleVmSecretsChartProps extends ChartProps {
  /**
   * Target namespace for the secret
   * @default "default"
   */
  namespace?: string;

  /**
   * ArgoCD sync wave for secret creation
   * @default "0"
   */
  syncWave?: string;
}

export class TailscaleVmSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: TailscaleVmSecretsChartProps = {}) {
    super(scope, id, props);

    const {
      namespace = 'default',
      syncWave = '0',
    } = props;

    // ExternalSecret for Tailscale VM Auth Key
    new ExternalSecret(this, 'tailscale-vm-auth', {
      metadata: {
        name: 'tailscale-vm-auth-key',
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
          name: 'tailscale-vm-auth-key',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            data: {
              // Export auth key for use in cloud-init
              'authkey': '{{ .tailscale_vm_auth_key }}',
            },
          },
        },
        data: [
          {
            secretKey: 'tailscale_vm_auth_key',
            remoteRef: {
              key: 'TAILSCALE-VM-AUTH-KEY',
            },
          },
        ],
      },
    });
  }
}
