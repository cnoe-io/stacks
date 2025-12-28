/**
 * CaipeMilvusChart - Milvus vector database for CAIPE
 *
 * Deploys Milvus in standalone mode with Woodpecker enabled (no PulsarV3)
 * for resource-constrained environments (16GB RAM shared).
 *
 * Provides vector similarity search for RAG document embeddings.
 */

import { Chart, ChartProps, Helm } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  CAIPE_NAMESPACE,
  CAIPE_SYNC_WAVES,
  CAIPE_PORTS,
  CAIPE_IMAGE_VERSIONS,
  CAIPE_RESOURCE_LIMITS,
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

    // Deploy Milvus via Helm chart in standalone mode
    new Helm(this, 'milvus', {
      chart: 'milvus',
      repo: 'https://zilliztech.github.io/milvus-helm/',
      version: '4.2.0',
      namespace: namespace,
      releaseName: 'milvus',
      values: {
        // Standalone mode - single node
        cluster: {
          enabled: false,
        },
        standalone: {
          enabled: true,
          resources: {
            requests: {
              memory: '2Gi',
              cpu: '500m',
            },
            limits: {
              memory: CAIPE_RESOURCE_LIMITS.milvus.memory,
              cpu: CAIPE_RESOURCE_LIMITS.milvus.cpu,
            },
          },
          persistence: {
            enabled: true,
            storageClass: storageClassName,
            size: storageSize,
          },
        },

        // CRITICAL: Disable PulsarV3 for 16GB RAM environments
        pulsar: {
          enabled: false,
        },

        // Enable Woodpecker as lightweight message broker alternative
        woodpecker: {
          enabled: true,
        },

        // MinIO for object storage
        minio: {
          enabled: true,
          mode: 'standalone',
          persistence: {
            enabled: true,
            storageClass: storageClassName,
            size: '10Gi',
          },
          resources: {
            requests: {
              memory: '256Mi',
              cpu: '100m',
            },
            limits: {
              memory: '512Mi',
              cpu: '500m',
            },
          },
        },

        // etcd for metadata
        etcd: {
          enabled: true,
          replicaCount: 1,
          persistence: {
            enabled: true,
            storageClass: storageClassName,
            size: '2Gi',
          },
          resources: {
            requests: {
              memory: '128Mi',
              cpu: '100m',
            },
            limits: {
              memory: '256Mi',
              cpu: '500m',
            },
          },
        },

        // Service configuration
        service: {
          type: 'ClusterIP',
          port: CAIPE_PORTS.milvus,
        },

        // Labels
        extraLabels: labels,
      },
    });

    // Service for internal access (in case Helm chart doesn't create one properly)
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
        selector: {
          'app.kubernetes.io/name': 'milvus',
          'app.kubernetes.io/instance': 'milvus',
        },
        ports: [
          {
            name: 'grpc',
            port: CAIPE_PORTS.milvus,
            targetPort: k8s.IntOrString.fromNumber(CAIPE_PORTS.milvus),
            protocol: 'TCP',
          },
        ],
        type: 'ClusterIP',
      },
    });
  }
}
