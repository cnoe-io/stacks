/**
 * CloudflareIssuerChart - Creates cert-manager ClusterIssuer with Cloudflare DNS-01 solver
 *
 * This chart creates a ClusterIssuer that uses Cloudflare DNS-01 challenges for
 * Let's Encrypt certificate issuance. DNS-01 challenges work regardless of whether
 * port 80 is accessible externally, making them ideal for Talos clusters.
 *
 * Prerequisites:
 * - cert-manager installed in cluster
 * - Cloudflare API token secret created (see cert-manager-secrets-chart.ts)
 *
 * Usage:
 * Ingresses should use annotation: cert-manager.io/cluster-issuer: letsencrypt-cloudflare
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { ClusterIssuer } from '../../imports/cert-manager.io';

export interface CloudflareIssuerChartProps extends ChartProps {
  /**
   * Email address for ACME registration
   * @default "admin@ai401kchat.com"
   */
  email?: string;

  /**
   * Name of the ClusterIssuer
   * @default "letsencrypt-cloudflare"
   */
  issuerName?: string;

  /**
   * Name of the Kubernetes secret containing Cloudflare API token
   * @default "cloudflare-api-token-secret"
   */
  cloudflareSecretName?: string;

  /**
   * Key in the secret containing the API token
   * @default "api-token"
   */
  cloudflareSecretKey?: string;

  /**
   * ArgoCD sync wave
   * @default "-80"
   */
  syncWave?: string;

  /**
   * Use Let's Encrypt staging server (for testing)
   * @default false
   */
  staging?: boolean;
}

export class CloudflareIssuerChart extends Chart {
  constructor(scope: Construct, id: string, props: CloudflareIssuerChartProps = {}) {
    super(scope, id, props);

    const {
      email = 'admin@ai401kchat.com',
      issuerName = 'letsencrypt-cloudflare',
      cloudflareSecretName = 'cloudflare-api-token-secret',
      cloudflareSecretKey = 'api-token',
      syncWave = '-80',
      staging = false,
    } = props;

    const acmeServer = staging
      ? 'https://acme-staging-v02.api.letsencrypt.org/directory'
      : 'https://acme-v02.api.letsencrypt.org/directory';

    // Create ClusterIssuer with Cloudflare DNS-01 solver
    new ClusterIssuer(this, 'letsencrypt-cloudflare', {
      metadata: {
        name: issuerName,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
        labels: {
          'app.kubernetes.io/name': 'cert-manager',
          'app.kubernetes.io/component': 'cluster-issuer',
          'app.kubernetes.io/part-of': 'cert-manager',
        },
      },
      spec: {
        acme: {
          // ACME server
          server: acmeServer,

          // Email for certificate notifications
          email: email,

          // Secret to store ACME account private key
          privateKeySecretRef: {
            name: `${issuerName}-account-key`,
          },

          // DNS-01 solver using Cloudflare
          solvers: [
            {
              dns01: {
                cloudflare: {
                  // Reference to the Cloudflare API token secret
                  apiTokenSecretRef: {
                    name: cloudflareSecretName,
                    key: cloudflareSecretKey,
                  },
                },
              },
              // Optional: selector to match specific domains
              // selector: {
              //   dnsZones: ['ai401kchat.com'],
              // },
            },
          ],
        },
      },
    });
  }
}
