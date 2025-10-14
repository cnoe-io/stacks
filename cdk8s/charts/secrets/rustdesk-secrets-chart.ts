/**
 * RustDeskSecretsChart - Manages RustDesk password via External Secrets Operator
 *
 * This chart creates an ExternalSecret resource that syncs the RustDesk permanent password
 * from Azure Key Vault into a Kubernetes secret for use by KubeVirt VMs.
 *
 * The password is used for RustDesk remote desktop authentication. VMs reference this secret
 * via environment variables injected into the VM configuration.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';

export interface RustDeskSecretsChartProps extends ChartProps {
  /**
   * Target namespace for the secret
   * @default "default"
   */
  namespace?: string;

  /**
   * ArgoCD sync wave for secret creation
   * Must be before VM deployment (default wave 0)
   * @default "-70"
   */
  syncWave?: string;
}

export class RustDeskSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: RustDeskSecretsChartProps = {}) {
    super(scope, id, props);

    const {
      namespace = 'default',
      syncWave = '-70',
    } = props;

    // ExternalSecret for RustDesk Password
    new ExternalSecret(this, 'rustdesk-password', {
      metadata: {
        name: 'rustdesk-password',
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app': 'rustdesk',
          'managed-by': 'external-secrets',
        },
      },
      spec: {
        refreshInterval: '1h',  // Refresh every hour to pick up password rotations
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
        },
        target: {
          name: 'rustdesk-password',
          creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
          template: {
            type: 'Opaque',
            metadata: {
              labels: {
                'app': 'rustdesk',
                'managed-by': 'external-secrets',
              },
            },
            data: {
              // Export password for use in VM environment variables
              'password': '{{ .password }}',
            },
          },
        },
        data: [
          {
            secretKey: 'password',
            remoteRef: {
              key: 'RUSTDESK-PASSWORD',  // Azure Key Vault secret name
            },
          },
        ],
      },
    });
  }
}
