/**
 * CertManagerSecretsChart - Manages cert-manager secrets via External Secrets Operator
 *
 * This chart creates an ExternalSecret resource that syncs the Cloudflare API token
 * from Azure Key Vault into a Kubernetes secret for use by cert-manager.
 *
 * The API token is used for DNS-01 challenge validation with Cloudflare.
 *
 * Prerequisites:
 * - Create Cloudflare API token with Zone:DNS:Edit permissions for your domain
 * - Store token in Azure Key Vault as: CLOUDFLARE-API-TOKEN
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import {
  ExternalSecret,
  ExternalSecretSpecSecretStoreRefKind,
  ExternalSecretSpecTargetCreationPolicy,
} from '../../imports/external-secrets.io';
import { addExternalSecretsWebhookGate } from '../../lib/external-secrets-hooks';

export interface CertManagerSecretsChartProps extends ChartProps {
  /**
   * Target namespace for the secret
   * @default "cert-manager"
   */
  namespace?: string;

  /**
   * ArgoCD sync wave for secret creation
   * @default "-85"
   */
  syncWave?: string;

  /**
   * Name of the target Kubernetes secret
   * @default "cloudflare-api-token-secret"
   */
  secretName?: string;
}

export class CertManagerSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: CertManagerSecretsChartProps = {}) {
    super(scope, id, props);

    const {
      namespace = 'cert-manager',
      syncWave = '-85',
      secretName = 'cloudflare-api-token-secret',
    } = props;

    addExternalSecretsWebhookGate(this, namespace);

    // ExternalSecret for Cloudflare API Token (used by cert-manager ClusterIssuer)
    new ExternalSecret(this, 'cloudflare-api-token', {
      metadata: {
        name: secretName,
        namespace,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app.kubernetes.io/name': 'cert-manager',
          'app.kubernetes.io/component': 'secrets',
          'app.kubernetes.io/part-of': 'cert-manager',
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
              // Key must be 'api-token' as expected by cert-manager Cloudflare solver
              'api-token': '{{ .cloudflare_api_token }}',
            },
          },
        },
        data: [
          {
            secretKey: 'cloudflare_api_token',
            remoteRef: {
              key: 'CLOUDFLARE-API-TOKEN',
            },
          },
        ],
      },
    });
  }
}
