/**
 * LangfuseRedisChart - Redis for Langfuse v3
 *
 * Deploys Redis single-node for Langfuse v3 caching.
 * - PVC for persistent data storage (optional)
 * - Service for internal cluster access
 *
 * Sync wave: -70 (before Langfuse at -60)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface LangfuseRedisChartProps extends ChartProps {
  /**
   * Namespace for Redis deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Redis image version
   * @default '7-alpine'
   */
  imageVersion?: string;

  /**
   * Enable persistence
   * @default false (cache only, no persistence needed for Langfuse)
   */
  enablePersistence?: boolean;

  /**
   * PVC storage size (if persistence enabled)
   * @default '1Gi'
   */
  storageSize?: string;
}

export class LangfuseRedisChart extends Chart {
  constructor(scope: Construct, id: string, props?: LangfuseRedisChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'observability';
    const imageVersion = props?.imageVersion || '7-alpine';
    const enablePersistence = props?.enablePersistence || false;
    const storageSize = props?.storageSize || '1Gi';

    const labels = {
      'app': 'langfuse-redis',
      'app.kubernetes.io/name': 'redis',
      'app.kubernetes.io/component': 'cache',
      'app.kubernetes.io/part-of': 'langfuse',
    };

    // PersistentVolumeClaim for Redis data (optional)
    if (enablePersistence) {
      new k8s.KubePersistentVolumeClaim(this, 'pvc', {
        metadata: {
          name: 'langfuse-redis-pvc',
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
    }

    // Redis Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'langfuse-redis',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'langfuse-redis',
          },
        },
        template: {
          metadata: {
            labels,
          },
          spec: {
            securityContext: {
              runAsNonRoot: true,
              runAsUser: 999,
              runAsGroup: 999,
              fsGroup: 999,
            },
            containers: [
              {
                name: 'redis',
                image: `redis:${imageVersion}`,
                args: ['--appendonly', enablePersistence ? 'yes' : 'no'],
                ports: [
                  { containerPort: 6379, name: 'redis', protocol: 'TCP' },
                ],
                volumeMounts: enablePersistence ? [
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ] : [],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('128Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('512Mi'),
                    cpu: k8s.Quantity.fromString('500m'),
                  },
                },
                readinessProbe: {
                  exec: {
                    command: ['redis-cli', 'ping'],
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                },
                livenessProbe: {
                  exec: {
                    command: ['redis-cli', 'ping'],
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                },
              },
            ],
            volumes: enablePersistence ? [
              {
                name: 'data',
                persistentVolumeClaim: {
                  claimName: 'langfuse-redis-pvc',
                },
              },
            ] : [],
          },
        },
      },
    });

    // Redis Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'langfuse-redis',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'langfuse-redis' },
        ports: [
          {
            name: 'redis',
            port: 6379,
            targetPort: k8s.IntOrString.fromNumber(6379),
            protocol: 'TCP',
          },
        ],
      },
    });
  }
}
