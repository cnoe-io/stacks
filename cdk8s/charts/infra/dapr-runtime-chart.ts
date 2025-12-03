/**
 * DaprRuntimeChart - Deploys Dapr control plane via Helm chart
 *
 * This chart deploys Dapr v1.16 with:
 * - dapr-operator (manages Dapr components)
 * - dapr-sidecar-injector (auto-injects Dapr sidecars)
 * - dapr-placement (actor placement service)
 * - dapr-sentry (mTLS certificate authority)
 * - dapr-dashboard (optional web UI)
 *
 * Prerequisites:
 * - Kubernetes cluster with Helm support
 *
 * Usage:
 * - Enable HA mode for production deployments
 * - Dashboard is enabled by default for development
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import { KubeNamespace } from '../../imports/k8s';

export interface DaprRuntimeChartProps extends ChartProps {
  /**
   * Dapr Helm chart version
   * @default '1.16'
   */
  version?: string;

  /**
   * Enable High Availability mode
   * @default false
   */
  enableHA?: boolean;

  /**
   * Enable Dapr Dashboard
   * @default true
   */
  enableDashboard?: boolean;

  /**
   * Log level for Dapr components
   * @default 'info'
   */
  logLevel?: 'debug' | 'info' | 'warn' | 'error';
}

export class DaprRuntimeChart extends Chart {
  constructor(scope: Construct, id: string, props: DaprRuntimeChartProps = {}) {
    super(scope, id, props);

    const version = props.version || '1.16';
    const enableHA = props.enableHA || false;
    const enableDashboard = props.enableDashboard !== false; // Default true
    const logLevel = props.logLevel || 'info';

    // Create dapr-system namespace
    new KubeNamespace(this, 'dapr-system', {
      metadata: {
        name: 'dapr-system',
        labels: {
          'app.kubernetes.io/name': 'dapr',
          'app.kubernetes.io/managed-by': 'cdk8s',
          'app.kubernetes.io/part-of': 'dapr-agents',
        },
      },
    });

    // Deploy Dapr via Helm
    new Helm(this, 'dapr', {
      chart: 'dapr',
      repo: 'https://dapr.github.io/helm-charts/',
      version: version,
      namespace: 'dapr-system',
      releaseName: 'dapr',
      values: {
        global: {
          // High availability mode
          ha: {
            enabled: enableHA,
            replicaCount: enableHA ? 3 : 1,
          },
          // Logging configuration
          logAsJson: true,
          logLevel: logLevel,
          // Enable Prometheus metrics
          prometheus: {
            enabled: true,
          },
          // mTLS configuration
          mtls: {
            enabled: true,
            workloadCertTTL: '24h',
            allowedClockSkew: '15m',
          },
        },
        // Operator configuration
        dapr_operator: {
          replicaCount: enableHA ? 3 : 1,
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '200m',
              memory: '256Mi',
            },
          },
        },
        // Sidecar injector configuration
        dapr_sidecar_injector: {
          replicaCount: enableHA ? 3 : 1,
          // Sidecar defaults
          sidecarImagePullPolicy: 'IfNotPresent',
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '200m',
              memory: '256Mi',
            },
          },
        },
        // Placement service (for actors)
        dapr_placement: {
          replicaCount: enableHA ? 3 : 1,
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '200m',
              memory: '256Mi',
            },
          },
        },
        // Sentry (certificate authority)
        dapr_sentry: {
          replicaCount: enableHA ? 3 : 1,
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '200m',
              memory: '256Mi',
            },
          },
        },
        // Scheduler (for jobs/workflows)
        dapr_scheduler: {
          replicaCount: enableHA ? 3 : 1,
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '200m',
              memory: '256Mi',
            },
          },
        },
      },
    });

    // Optionally deploy Dapr Dashboard
    if (enableDashboard) {
      const baseHost = process.env.INGRESS_HOST || 'cnoe.localtest.me';
      const dashboardHost = `dapr.${baseHost}`;

      new Helm(this, 'dapr-dashboard', {
        chart: 'dapr-dashboard',
        repo: 'https://dapr.github.io/helm-charts/',
        namespace: 'dapr-system',
        releaseName: 'dapr-dashboard',
        values: {
          replicaCount: 1,
          serviceType: 'ClusterIP',
          ingress: {
            enabled: true,
            className: 'nginx',
            hosts: [
              {
                host: dashboardHost,
                paths: [
                  {
                    path: '/',
                    pathType: 'Prefix',
                  },
                ],
              },
            ],
          },
          resources: {
            requests: {
              cpu: '50m',
              memory: '64Mi',
            },
            limits: {
              cpu: '200m',
              memory: '256Mi',
            },
          },
        },
      });
    }
  }
}
