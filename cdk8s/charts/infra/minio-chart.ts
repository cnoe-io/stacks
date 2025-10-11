import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface MinioChartProps extends ChartProps {
  storageSize?: string;
  rootUser?: string;
  rootPassword?: string;
  resources?: {
    requests?: { memory?: string; cpu?: string };
    limits?: { memory?: string; cpu?: string };
  };
}

// Helper function to generate random password
function generateRandomPassword(length: number): string {
  const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let password = '';
  for (let i = 0; i < length; i++) {
    password += charset.charAt(Math.floor(Math.random() * charset.length));
  }
  return password;
}

export class MinioChart extends Chart {
  constructor(scope: Construct, id: string, props?: MinioChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'nix-cache';
    const storageSize = props?.storageSize || '100Gi';
    const rootUser = props?.rootUser || 'admin';
    const rootPassword = props?.rootPassword || generateRandomPassword(32);

    // Default resource configuration
    const resourceRequests = props?.resources?.requests || { memory: '512Mi', cpu: '500m' };
    const resourceLimits = props?.resources?.limits || { memory: '2Gi', cpu: '1000m' };

    // T008: PersistentVolumeClaim for MinIO data storage
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'minio-storage',
        namespace,
        labels: {
          'app': 'minio',
          'app.kubernetes.io/name': 'minio',
          'app.kubernetes.io/component': 'object-storage',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100',
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

    // T009: Secret for MinIO credentials
    new k8s.KubeSecret(this, 'secret', {
      metadata: {
        name: 'minio-credentials',
        namespace,
        labels: {
          'app': 'minio',
          'app.kubernetes.io/name': 'minio',
          'app.kubernetes.io/component': 'object-storage',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100',
        },
      },
      type: 'Opaque',
      stringData: {
        'access-key': rootUser,
        'secret-key': rootPassword,
      },
    });

    // T010-T016: MinIO Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'minio',
        namespace,
        labels: {
          'app': 'minio',
          'app.kubernetes.io/name': 'minio',
          'app.kubernetes.io/component': 'object-storage',
          'app.kubernetes.io/part-of': 'nix-cache',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'minio',
          },
        },
        template: {
          metadata: {
            labels: {
              'app': 'minio',
              'app.kubernetes.io/name': 'minio',
              'app.kubernetes.io/component': 'object-storage',
            },
          },
          spec: {
            // T014: Security context - run as non-root
            securityContext: {
              runAsUser: 1000,
              runAsGroup: 1000,
              fsGroup: 1000,
              runAsNonRoot: true,
            },
            containers: [
              {
                name: 'minio',
                image: 'quay.io/minio/minio:latest',
                args: ['server', '/data', '--console-address', ':9001'],
                ports: [
                  {
                    containerPort: 9000,
                    name: 'api',
                    protocol: 'TCP',
                  },
                  {
                    containerPort: 9001,
                    name: 'console',
                    protocol: 'TCP',
                  },
                ],
                // T011: Environment variables from Secret
                env: [
                  {
                    name: 'MINIO_ROOT_USER',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'minio-credentials',
                        key: 'access-key',
                      },
                    },
                  },
                  {
                    name: 'MINIO_ROOT_PASSWORD',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'minio-credentials',
                        key: 'secret-key',
                      },
                    },
                  },
                ],
                // T012: Volume mounts
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ],
                // T013: Resource limits
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString(resourceRequests.memory || '512Mi'),
                    cpu: k8s.Quantity.fromString(resourceRequests.cpu || '500m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString(resourceLimits.memory || '2Gi'),
                    cpu: k8s.Quantity.fromString(resourceLimits.cpu || '1000m'),
                  },
                },
                // T015: Readiness probe
                readinessProbe: {
                  httpGet: {
                    path: '/minio/health/ready',
                    port: k8s.IntOrString.fromNumber(9000),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 5,
                },
                // T016: Liveness probe
                livenessProbe: {
                  httpGet: {
                    path: '/minio/health/live',
                    port: k8s.IntOrString.fromNumber(9000),
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
                  claimName: 'minio-storage',
                },
              },
            ],
          },
        },
      },
    });

    // T017: MinIO Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'minio',
        namespace,
        labels: {
          'app': 'minio',
          'app.kubernetes.io/name': 'minio',
          'app.kubernetes.io/component': 'object-storage',
        },
        annotations: {
          'argocd.argoproj.io/sync-wave': '-100',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: {
          'app': 'minio',
        },
        ports: [
          {
            name: 'api',
            port: 9000,
            targetPort: k8s.IntOrString.fromNumber(9000),
            protocol: 'TCP',
          },
          {
            name: 'console',
            port: 9001,
            targetPort: k8s.IntOrString.fromNumber(9001),
            protocol: 'TCP',
          },
        ],
      },
    });
  }
}
