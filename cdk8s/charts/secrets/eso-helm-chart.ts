/**
 * EsoHelmChart - Deploys External Secrets Operator via Helm
 * Feature: 102-bootstrap-talos-argocd
 *
 * This chart deploys ESO using the official Helm chart which:
 * - Installs ESO controller and webhook
 * - Installs CRDs (ClusterSecretStore, ExternalSecret, etc.)
 * - Configures RBAC for secret management
 *
 * Helm Chart: https://external-secrets.io/latest/introduction/getting-started/
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';

export interface EsoHelmChartProps extends ChartProps {
  /**
   * ESO Helm chart version
   * @default '0.9.13'
   */
  version?: string;

  /**
   * Namespace for ESO deployment
   * @default 'external-secrets'
   */
  namespace?: string;

  /**
   * Install CRDs with Helm
   * @default true
   */
  installCrds?: boolean;

  /**
   * Enable webhook for validation
   * @default true
   */
  enableWebhook?: boolean;

  /**
   * Number of operator replicas
   * @default 2
   */
  replicaCount?: number;

  /**
   * Additional Helm values to merge
   */
  additionalValues?: Record<string, unknown>;
}

export class EsoHelmChart extends Chart {
  constructor(scope: Construct, id: string, props: EsoHelmChartProps = {}) {
    super(scope, id, props);

    const {
      version = '0.9.13',
      namespace = 'external-secrets',
      installCrds = true,
      enableWebhook = true,
      replicaCount = 2,
      additionalValues = {},
    } = props;

    // Base values for ESO
    const baseValues: Record<string, unknown> = {
      // CRD installation
      installCRDs: installCrds,

      // Webhook configuration
      webhook: {
        create: enableWebhook,
        port: 9443,
        resources: {
          requests: {
            cpu: '50m',
            memory: '64Mi',
          },
          limits: {
            cpu: '200m',
            memory: '128Mi',
          },
        },
      },

      // Controller configuration
      replicaCount: replicaCount,
      resources: {
        requests: {
          cpu: '100m',
          memory: '128Mi',
        },
        limits: {
          cpu: '500m',
          memory: '512Mi',
        },
      },

      // Service account
      serviceAccount: {
        create: true,
        name: 'external-secrets',
        automount: true,
      },

      // RBAC
      rbac: {
        create: true,
      },

      // Metrics
      metrics: {
        enabled: true,
        service: {
          enabled: true,
          port: 8080,
        },
      },

      // Pod disruption budget for HA
      podDisruptionBudget: {
        enabled: replicaCount > 1,
        minAvailable: 1,
      },

      // Security context
      podSecurityContext: {
        runAsNonRoot: true,
        seccompProfile: {
          type: 'RuntimeDefault',
        },
      },
    };

    // Merge with additional values
    const mergedValues = { ...baseValues, ...additionalValues };

    // Deploy ESO using official Helm chart
    new Helm(this, 'external-secrets', {
      chart: 'external-secrets',
      repo: 'https://charts.external-secrets.io',
      version: version,
      namespace: namespace,
      releaseName: 'external-secrets',
      values: mergedValues,
    });
  }
}
