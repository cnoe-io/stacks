/**
 * LangfuseClickhouseChart - ClickHouse for Langfuse v3
 *
 * Deploys ClickHouse single-node for Langfuse v3 analytics storage.
 * - PVC for persistent data storage
 * - Default credentials from secret
 * - Service for internal cluster access
 *
 * Sync wave: -70 (before Langfuse at -60)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface LangfuseClickhouseChartProps extends ChartProps {
  /**
   * Namespace for ClickHouse deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * ClickHouse image version
   * @default '24.3'
   */
  imageVersion?: string;

  /**
   * PVC storage size
   * @default '10Gi'
   */
  storageSize?: string;

  /**
   * Credentials secret name
   * @default 'langfuse-clickhouse-credentials'
   */
  credentialsSecretName?: string;
}

export class LangfuseClickhouseChart extends Chart {
  constructor(scope: Construct, id: string, props?: LangfuseClickhouseChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'observability';
    const imageVersion = props?.imageVersion || '24.3';
    const storageSize = props?.storageSize || '10Gi';
    const credentialsSecretName = props?.credentialsSecretName || 'langfuse-clickhouse-credentials';

    const labels = {
      'app': 'langfuse-clickhouse',
      'app.kubernetes.io/name': 'clickhouse',
      'app.kubernetes.io/component': 'database',
      'app.kubernetes.io/part-of': 'langfuse',
    };

    // Credentials Secret (created inline - should be synced from external secrets in production)
    new k8s.KubeSecret(this, 'credentials', {
      metadata: {
        name: credentialsSecretName,
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-75',
        },
      },
      type: 'Opaque',
      stringData: {
        'CLICKHOUSE_USER': 'default',
        'CLICKHOUSE_PASSWORD': 'clickhouse_langfuse_password',
      },
    });

    // PersistentVolumeClaim for ClickHouse data
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'langfuse-clickhouse-pvc',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString(storageSize),
          },
        },
      },
    });

    // ClickHouse Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'langfuse-clickhouse',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        replicas: 1,
        strategy: {
          type: 'Recreate', // Required for single PVC
        },
        selector: {
          matchLabels: {
            'app': 'langfuse-clickhouse',
          },
        },
        template: {
          metadata: {
            labels,
          },
          spec: {
            securityContext: {
              fsGroup: 101, // clickhouse group
            },
            containers: [
              {
                name: 'clickhouse',
                image: `clickhouse/clickhouse-server:${imageVersion}`,
                ports: [
                  { containerPort: 8123, name: 'http', protocol: 'TCP' },
                  { containerPort: 9000, name: 'native', protocol: 'TCP' },
                ],
                env: [
                  {
                    name: 'CLICKHOUSE_USER',
                    valueFrom: {
                      secretKeyRef: {
                        name: credentialsSecretName,
                        key: 'CLICKHOUSE_USER',
                      },
                    },
                  },
                  {
                    name: 'CLICKHOUSE_PASSWORD',
                    valueFrom: {
                      secretKeyRef: {
                        name: credentialsSecretName,
                        key: 'CLICKHOUSE_PASSWORD',
                      },
                    },
                  },
                  {
                    name: 'CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT',
                    value: '1',
                  },
                ],
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/var/lib/clickhouse',
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('512Mi'),
                    cpu: k8s.Quantity.fromString('250m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('2Gi'),
                    cpu: k8s.Quantity.fromString('1000m'),
                  },
                },
                readinessProbe: {
                  httpGet: {
                    path: '/ping',
                    port: k8s.IntOrString.fromNumber(8123),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 5,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/ping',
                    port: k8s.IntOrString.fromNumber(8123),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                },
              },
            ],
            volumes: [
              {
                name: 'data',
                persistentVolumeClaim: {
                  claimName: 'langfuse-clickhouse-pvc',
                },
              },
            ],
          },
        },
      },
    });

    // ClickHouse Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'langfuse-clickhouse',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'langfuse-clickhouse' },
        ports: [
          {
            name: 'http',
            port: 8123,
            targetPort: k8s.IntOrString.fromNumber(8123),
            protocol: 'TCP',
          },
          {
            name: 'native',
            port: 9000,
            targetPort: k8s.IntOrString.fromNumber(9000),
            protocol: 'TCP',
          },
        ],
      },
    });
  }
}
