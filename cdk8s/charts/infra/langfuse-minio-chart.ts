/**
 * LangfuseMinioChart - MinIO for Langfuse v3 Blob Storage
 *
 * Deploys MinIO single-node for Langfuse v3 blob storage (multimodal traces, attachments).
 * - PVC for persistent data storage
 * - Service for internal cluster access
 * - Default bucket created on startup
 *
 * Sync wave: -70 (before Langfuse at -60)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface LangfuseMinioChartProps extends ChartProps {
  /**
   * Namespace for MinIO deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * MinIO image version
   * @default 'RELEASE.2024-01-18T22-51-28Z'
   */
  imageVersion?: string;

  /**
   * PVC storage size
   * @default '10Gi'
   */
  storageSize?: string;

  /**
   * Credentials secret name
   * @default 'langfuse-minio-credentials'
   */
  credentialsSecretName?: string;

  /**
   * Default bucket name
   * @default 'langfuse'
   */
  bucketName?: string;
}

export class LangfuseMinioChart extends Chart {
  constructor(scope: Construct, id: string, props?: LangfuseMinioChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'observability';
    const imageVersion = props?.imageVersion || 'RELEASE.2024-01-18T22-51-28Z';
    const storageSize = props?.storageSize || '10Gi';
    const credentialsSecretName = props?.credentialsSecretName || 'langfuse-minio-credentials';
    const bucketName = props?.bucketName || 'langfuse';

    const labels = {
      'app': 'langfuse-minio',
      'app.kubernetes.io/name': 'minio',
      'app.kubernetes.io/component': 'blob-storage',
      'app.kubernetes.io/part-of': 'langfuse',
    };

    // Credentials Secret
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
        'MINIO_ROOT_USER': 'minioadmin',
        'MINIO_ROOT_PASSWORD': 'minio_langfuse_password',
      },
    });

    // PersistentVolumeClaim for MinIO data
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'langfuse-minio-pvc',
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

    // MinIO Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'langfuse-minio',
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
            'app': 'langfuse-minio',
          },
        },
        template: {
          metadata: {
            labels,
          },
          spec: {
            securityContext: {
              runAsNonRoot: true,
              runAsUser: 1000,
              runAsGroup: 1000,
              fsGroup: 1000,
            },
            initContainers: [
              {
                name: 'create-bucket',
                image: `minio/minio:${imageVersion}`,
                command: ['sh', '-c', `mkdir -p /data/${bucketName}`],
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ],
              },
            ],
            containers: [
              {
                name: 'minio',
                image: `minio/minio:${imageVersion}`,
                args: ['server', '/data', '--console-address', ':9001'],
                ports: [
                  { containerPort: 9000, name: 'api', protocol: 'TCP' },
                  { containerPort: 9001, name: 'console', protocol: 'TCP' },
                ],
                env: [
                  {
                    name: 'MINIO_ROOT_USER',
                    valueFrom: {
                      secretKeyRef: {
                        name: credentialsSecretName,
                        key: 'MINIO_ROOT_USER',
                      },
                    },
                  },
                  {
                    name: 'MINIO_ROOT_PASSWORD',
                    valueFrom: {
                      secretKeyRef: {
                        name: credentialsSecretName,
                        key: 'MINIO_ROOT_PASSWORD',
                      },
                    },
                  },
                ],
                volumeMounts: [
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ],
                resources: {
                  requests: {
                    memory: k8s.Quantity.fromString('256Mi'),
                    cpu: k8s.Quantity.fromString('100m'),
                  },
                  limits: {
                    memory: k8s.Quantity.fromString('1Gi'),
                    cpu: k8s.Quantity.fromString('500m'),
                  },
                },
                readinessProbe: {
                  httpGet: {
                    path: '/minio/health/ready',
                    port: k8s.IntOrString.fromNumber(9000),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 5,
                },
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
                  claimName: 'langfuse-minio-pvc',
                },
              },
            ],
          },
        },
      },
    });

    // MinIO Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'langfuse-minio',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70',
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'langfuse-minio' },
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
