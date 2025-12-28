/**
 * CaipeRedisChart - Redis for CAIPE
 *
 * Deploys Redis for session caching and temporary data storage.
 * Configured with minimal resources for 16GB shared environments.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_RESOURCE_LIMITS,
  getCaipeStorageLabels,
} from '../../lib/caipe-helpers';

export interface CaipeRedisChartProps extends ChartProps {
  /**
   * Namespace for Redis
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Storage size for Redis data
   * @default '1Gi'
   */
  storageSize?: string;

  /**
   * Storage class name
   * @default 'standard'
   */
  storageClassName?: string;

  /**
   * Sync wave for ArgoCD ordering
   * @default '-50'
   */
  syncWave?: string;
}

export class CaipeRedisChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeRedisChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const storageSize = props.storageSize || '1Gi';
    const storageClassName = props.storageClassName || 'standard';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.storage;

    const labels = getCaipeStorageLabels('redis');
    const selectorLabels = {
      'app.kubernetes.io/name': 'redis',
      'app.kubernetes.io/instance': 'caipe-redis',
    };

    // PersistentVolumeClaim for Redis data
    new k8s.KubePersistentVolumeClaim(this, 'redis-pvc', {
      metadata: {
        name: 'redis-data',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        storageClassName: storageClassName,
        resources: {
          requests: {
            storage: k8s.Quantity.fromString(storageSize),
          },
        },
      },
    });

    // Deployment for Redis
    new k8s.KubeDeployment(this, 'redis', {
      metadata: {
        name: 'redis',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: selectorLabels,
        },
        template: {
          metadata: {
            labels: { ...labels, ...selectorLabels },
          },
          spec: {
            securityContext: {
              fsGroup: 1000,
              runAsUser: 1000,
              runAsGroup: 1000,
            },
            containers: [
              {
                name: 'redis',
                image: `redis:${CAIPE_RESOURCE_LIMITS.redis ? '7.2.4' : '7.2.4'}-alpine`,
                ports: [
                  {
                    name: 'redis',
                    containerPort: CAIPE_PORTS.redis,
                  },
                ],
                args: [
                  'redis-server',
                  '--appendonly', 'yes',
                  '--maxmemory', '200mb',
                  '--maxmemory-policy', 'allkeys-lru',
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('128Mi'),
                    cpu: k8s.Quantity.fromString('50m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.redis.memory),
                    cpu: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.redis.cpu),
                  },
                },
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ],
                livenessProbe: {
                  exec: {
                    command: ['redis-cli', 'ping'],
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                },
                readinessProbe: {
                  exec: {
                    command: ['redis-cli', 'ping'],
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                  timeoutSeconds: 3,
                },
              },
            ],
            volumes: [
              {
                name: 'data',
                persistentVolumeClaim: {
                  claimName: 'redis-data',
                },
              },
            ],
          },
        },
      },
    });

    // Service for Redis
    new k8s.KubeService(this, 'redis-svc', {
      metadata: {
        name: 'redis',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: selectorLabels,
        ports: [
          {
            name: 'redis',
            port: CAIPE_PORTS.redis,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.redis),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });
  }
}
