/**
 * DaprAgentsRedisChart - Deploys Redis for Dapr Agents state and messaging
 *
 * This chart deploys a dedicated Redis instance for Dapr Agents:
 * - State stores (workflow state, agent registry, memory)
 * - Pub/Sub messaging between agents
 *
 * Separate from the nextjs Redis to ensure isolation and independent scaling.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface DaprAgentsRedisChartProps extends ChartProps {
  /**
   * Namespace for Redis deployment
   * @default 'dapr-agents'
   */
  namespace?: string;

  /**
   * Number of replicas
   * @default 1
   */
  replicas?: number;

  /**
   * Storage size for Redis data persistence
   * @default '1Gi'
   */
  storageSize?: string;

  /**
   * Enable data persistence via PVC
   * @default false (for dev environment)
   */
  enablePersistence?: boolean;
}

export class DaprAgentsRedisChart extends Chart {
  constructor(scope: Construct, id: string, props: DaprAgentsRedisChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || 'dapr-agents';
    const replicas = props.replicas ?? 1;
    const storageSize = props.storageSize || '1Gi';
    const enablePersistence = props.enablePersistence || false;

    const labels = {
      app: 'dapr-agents-redis',
      'app.kubernetes.io/name': 'redis',
      'app.kubernetes.io/component': 'state-store',
      'app.kubernetes.io/part-of': 'dapr-agents',
    };

    // Create namespace
    new k8s.KubeNamespace(this, 'namespace', {
      metadata: {
        name: namespace,
        labels: {
          'app.kubernetes.io/name': 'dapr-agents',
          'app.kubernetes.io/managed-by': 'cdk8s',
        },
      },
    });

    // Create PVC if persistence is enabled
    if (enablePersistence) {
      new k8s.KubePersistentVolumeClaim(this, 'redis-pvc', {
        metadata: {
          name: 'dapr-agents-redis-data',
          namespace: namespace,
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

    // Volume configuration
    const volumes: k8s.Volume[] = enablePersistence
      ? [
          {
            name: 'redis-data',
            persistentVolumeClaim: {
              claimName: 'dapr-agents-redis-data',
            },
          },
        ]
      : [
          {
            name: 'redis-data',
            emptyDir: {},
          },
        ];

    // Create deployment for Redis
    new k8s.KubeDeployment(this, 'redis-deployment', {
      metadata: {
        name: 'dapr-agents-redis',
        namespace: namespace,
        labels: labels,
      },
      spec: {
        replicas: replicas,
        selector: {
          matchLabels: {
            app: 'dapr-agents-redis',
          },
        },
        template: {
          metadata: {
            labels: labels,
          },
          spec: {
            containers: [
              {
                name: 'redis',
                image: 'redis:7-alpine',
                imagePullPolicy: 'IfNotPresent',
                command: ['redis-server'],
                args: [
                  '--appendonly', 'yes',
                  '--appendfsync', 'everysec',
                  '--maxmemory', '200mb',
                  '--maxmemory-policy', 'allkeys-lru',
                ],
                ports: [{ containerPort: 6379, name: 'redis' }],
                volumeMounts: [
                  {
                    name: 'redis-data',
                    mountPath: '/data',
                  },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString('50m'),
                    memory: k8s.Quantity.fromString('128Mi'),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString('200m'),
                    memory: k8s.Quantity.fromString('256Mi'),
                  },
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(6379),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                  failureThreshold: 3,
                },
                readinessProbe: {
                  exec: {
                    command: ['redis-cli', 'ping'],
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                  timeoutSeconds: 3,
                  successThreshold: 1,
                  failureThreshold: 3,
                },
                startupProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(6379),
                  },
                  initialDelaySeconds: 0,
                  periodSeconds: 10,
                  timeoutSeconds: 5,
                  successThreshold: 1,
                  failureThreshold: 30,
                },
              },
            ],
            volumes: volumes,
          },
        },
      },
    });

    // Create service
    new k8s.KubeService(this, 'redis-service', {
      metadata: {
        name: 'redis-service',
        namespace: namespace,
        labels: labels,
      },
      spec: {
        selector: {
          app: 'dapr-agents-redis',
        },
        ports: [
          {
            port: 6379,
            targetPort: k8s.IntOrString.fromNumber(6379),
            name: 'redis',
          },
        ],
      },
    });
  }
}
