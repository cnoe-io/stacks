/**
 * CaipeMilvusChart - Milvus vector database for CAIPE
 *
 * Deploys Milvus in standalone mode using direct Kubernetes resources
 * following the official docker-compose pattern with separate etcd and minio.
 *
 * Provides vector similarity search for RAG document embeddings.
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_RESOURCE_LIMITS,
  CAIPE_IMAGE_VERSIONS,
  getCaipeStorageLabels,
} from '../../lib/caipe-helpers';

export interface CaipeMilvusChartProps extends ChartProps {
  /**
   * Namespace for Milvus
   * @default 'ai-platform-engineering'
   */
  namespace?: string;

  /**
   * Storage size for Milvus data
   * @default '20Gi'
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

export class CaipeMilvusChart extends Chart {
  constructor(scope: Construct, id: string, props: CaipeMilvusChartProps = {}) {
    super(scope, id, props);

    const namespace = props.namespace || CAIPE_NAMESPACE;
    const storageSize = props.storageSize || '20Gi';
    const storageClassName = props.storageClassName || 'standard';
    const syncWave = props.syncWave || CAIPE_SYNC_WAVES.storage;

    const labels = getCaipeStorageLabels('milvus');

    // =====================================================
    // ETCD - Separate pod for metadata storage
    // =====================================================
    const etcdSelectorLabels = {
      'app.kubernetes.io/name': 'milvus',
      'app.kubernetes.io/component': 'etcd',
    };
    const etcdLabels = {
      ...labels,
      ...etcdSelectorLabels,
    };

    new k8s.KubePersistentVolumeClaim(this, 'etcd-pvc', {
      metadata: {
        name: 'milvus-etcd-data',
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
            storage: k8s.Quantity.fromString('2Gi'),
          },
        },
      },
    });

    new k8s.KubeDeployment(this, 'etcd', {
      metadata: {
        name: 'milvus-etcd',
        namespace: namespace,
        labels: etcdLabels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: etcdSelectorLabels,
        },
        template: {
          metadata: {
            labels: etcdLabels,
          },
          spec: {
            containers: [
              {
                name: 'etcd',
                image: 'quay.io/coreos/etcd:v3.5.5',
                command: ['etcd'],
                args: [
                  '-advertise-client-urls=http://127.0.0.1:2379',
                  '-listen-client-urls=http://0.0.0.0:2379',
                  '--data-dir=/etcd',
                  '--quota-backend-bytes=4294967296',
                  '--auto-compaction-mode=revision',
                  '--auto-compaction-retention=1000',
                  '--snapshot-count=50000',
                ],
                ports: [
                  { name: 'client', containerPort: 2379, protocol: 'TCP' },
                  { name: 'peer', containerPort: 2380, protocol: 'TCP' },
                ],
                volumeMounts: [
                  { name: 'etcd-data', mountPath: '/etcd' },
                ],
                resources: {
                  requests: { memory: k8s.Quantity.fromString('256Mi'), cpu: k8s.Quantity.fromString('100m') },
                  limits: { memory: k8s.Quantity.fromString('512Mi'), cpu: k8s.Quantity.fromString('500m') },
                },
                livenessProbe: {
                  exec: { command: ['etcdctl', 'endpoint', 'health'] },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                  failureThreshold: 3,
                },
                readinessProbe: {
                  exec: { command: ['etcdctl', 'endpoint', 'health'] },
                  initialDelaySeconds: 5,
                  periodSeconds: 10,
                },
              },
            ],
            volumes: [
              { name: 'etcd-data', persistentVolumeClaim: { claimName: 'milvus-etcd-data' } },
            ],
          },
        },
      },
    });

    new k8s.KubeService(this, 'etcd-svc', {
      metadata: {
        name: 'milvus-etcd',
        namespace: namespace,
        labels: etcdLabels,
        annotations: { 'argocd.argoproj.io/sync-wave': syncWave },
      },
      spec: {
        selector: etcdSelectorLabels,
        ports: [{ name: 'client', port: 2379, targetPort: k8s.IntOrString.fromNumber(2379) }],
        type: 'ClusterIP',
      },
    });

    // =====================================================
    // MinIO - Separate pod for object storage
    // =====================================================
    const minioSelectorLabels = {
      'app.kubernetes.io/name': 'milvus',
      'app.kubernetes.io/component': 'minio',
    };
    const minioLabels = {
      ...labels,
      ...minioSelectorLabels,
    };

    new k8s.KubePersistentVolumeClaim(this, 'minio-pvc', {
      metadata: {
        name: 'milvus-minio-data',
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
            storage: k8s.Quantity.fromString('10Gi'),
          },
        },
      },
    });

    new k8s.KubeDeployment(this, 'minio', {
      metadata: {
        name: 'milvus-minio',
        namespace: namespace,
        labels: minioLabels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: minioSelectorLabels,
        },
        template: {
          metadata: {
            labels: minioLabels,
          },
          spec: {
            containers: [
              {
                name: 'minio',
                image: 'minio/minio:RELEASE.2023-03-20T20-16-18Z',
                args: ['server', '/minio_data', '--console-address', ':9001'],
                env: [
                  { name: 'MINIO_ACCESS_KEY', value: 'minioadmin' },
                  { name: 'MINIO_SECRET_KEY', value: 'minioadmin' },
                ],
                ports: [
                  { name: 'api', containerPort: 9000, protocol: 'TCP' },
                  { name: 'console', containerPort: 9001, protocol: 'TCP' },
                ],
                volumeMounts: [
                  { name: 'minio-data', mountPath: '/minio_data' },
                ],
                resources: {
                  requests: { memory: k8s.Quantity.fromString('256Mi'), cpu: k8s.Quantity.fromString('100m') },
                  limits: { memory: k8s.Quantity.fromString('512Mi'), cpu: k8s.Quantity.fromString('500m') },
                },
                livenessProbe: {
                  httpGet: { path: '/minio/health/live', port: k8s.IntOrString.fromNumber(9000) },
                  initialDelaySeconds: 10,
                  periodSeconds: 30,
                },
                readinessProbe: {
                  httpGet: { path: '/minio/health/ready', port: k8s.IntOrString.fromNumber(9000) },
                  initialDelaySeconds: 5,
                  periodSeconds: 10,
                },
              },
            ],
            volumes: [
              { name: 'minio-data', persistentVolumeClaim: { claimName: 'milvus-minio-data' } },
            ],
          },
        },
      },
    });

    new k8s.KubeService(this, 'minio-svc', {
      metadata: {
        name: 'milvus-minio',
        namespace: namespace,
        labels: minioLabels,
        annotations: { 'argocd.argoproj.io/sync-wave': syncWave },
      },
      spec: {
        selector: minioSelectorLabels,
        ports: [{ name: 'api', port: 9000, targetPort: k8s.IntOrString.fromNumber(9000) }],
        type: 'ClusterIP',
      },
    });

    // =====================================================
    // Milvus Standalone - Main vector database
    // =====================================================
    const milvusSelectorLabels = {
      'app.kubernetes.io/name': 'milvus',
      'app.kubernetes.io/component': 'standalone',
    };
    const milvusLabels = {
      ...labels,
      ...milvusSelectorLabels,
    };

    new k8s.KubePersistentVolumeClaim(this, 'milvus-pvc', {
      metadata: {
        name: 'milvus-data',
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

    new k8s.KubeDeployment(this, 'milvus-standalone', {
      metadata: {
        name: 'milvus-standalone',
        namespace: namespace,
        labels: milvusLabels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: milvusSelectorLabels,
        },
        strategy: { type: 'Recreate' },
        template: {
          metadata: {
            labels: milvusLabels,
          },
          spec: {
            // Wait for etcd and minio to be ready
            initContainers: [
              {
                name: 'wait-for-deps',
                image: 'busybox:1.36',
                command: ['sh', '-c', `
                  echo "Waiting for etcd..."
                  until nc -z milvus-etcd 2379; do sleep 2; done
                  echo "Waiting for minio..."
                  until nc -z milvus-minio 9000; do sleep 2; done
                  echo "Dependencies ready!"
                `],
              },
            ],
            containers: [
              {
                name: 'milvus',
                image: `milvusdb/milvus:v${CAIPE_IMAGE_VERSIONS.milvus}`,
                args: ['milvus', 'run', 'standalone'],
                env: [
                  { name: 'ETCD_ENDPOINTS', value: 'milvus-etcd:2379' },
                  { name: 'MINIO_ADDRESS', value: 'milvus-minio:9000' },
                ],
                ports: [
                  { name: 'grpc', containerPort: 19530, protocol: 'TCP' },
                  { name: 'metrics', containerPort: 9091, protocol: 'TCP' },
                ],
                volumeMounts: [
                  { name: 'milvus-data', mountPath: '/var/lib/milvus' },
                ],
                resources: {
                  requests: { memory: k8s.Quantity.fromString('2Gi'), cpu: k8s.Quantity.fromString('500m') },
                  limits: {
                    memory: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.milvus.memory),
                    cpu: k8s.Quantity.fromString(CAIPE_RESOURCE_LIMITS.milvus.cpu),
                  },
                },
                livenessProbe: {
                  httpGet: { path: '/healthz', port: k8s.IntOrString.fromString('metrics') },
                  initialDelaySeconds: 90,
                  periodSeconds: 30,
                  failureThreshold: 5,
                },
                readinessProbe: {
                  httpGet: { path: '/healthz', port: k8s.IntOrString.fromString('metrics') },
                  initialDelaySeconds: 90,
                  periodSeconds: 10,
                  failureThreshold: 5,
                },
              },
            ],
            volumes: [
              { name: 'milvus-data', persistentVolumeClaim: { claimName: 'milvus-data' } },
            ],
          },
        },
      },
    });

    // Service for internal access
    new k8s.KubeService(this, 'milvus-svc', {
      metadata: {
        name: 'milvus',
        namespace: namespace,
        labels: labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: milvusSelectorLabels,
        ports: [
          {
            name: 'grpc',
            port: CAIPE_PORTS.milvus,
            targetPort: k8s.IntOrString.fromNumber(19530),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });
  }
}
