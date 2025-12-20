/**
 * LgtmLokiChart - Grafana Loki Deployment for Log Aggregation
 *
 * Deploys Loki in single-binary mode with filesystem storage for single-node K3s.
 * Provides log aggregation with LogQL query language and label-based indexing.
 *
 * Feature: 111-configure-k8s-observability
 * Sync wave: -60 (after namespace)
 *
 * Ports:
 * - 3100: HTTP API (push, query)
 * - 9096: gRPC (internal)
 *
 * Endpoints:
 * - Push: http://loki:3100/loki/api/v1/push
 * - Query: http://loki:3100
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  LGTM_NAMESPACE,
  LGTM_IMAGES,
  LGTM_STORAGE,
  LGTM_RESOURCES,
  LGTM_RETENTION_HOURS,
  getLgtmComponentLabels,
  getLgtmSelectorLabels,
  toK8sResources,
  generateLokiConfig,
} from '../../lib/lgtm-helpers';

export interface LgtmLokiChartProps extends ChartProps {
  /**
   * Namespace for Loki deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Storage size for Loki chunks and WAL
   * @default '20Gi'
   */
  storageSize?: string;

  /**
   * Loki container image
   * @default 'grafana/loki:3.3.0'
   */
  image?: string;

  /**
   * Retention period in hours
   * @default '720h' (30 days)
   */
  retentionHours?: string;

  /**
   * Resource requests and limits
   */
  resources?: {
    requests?: { cpu?: string; memory?: string };
    limits?: { cpu?: string; memory?: string };
  };
}

export class LgtmLokiChart extends Chart {
  constructor(scope: Construct, id: string, props?: LgtmLokiChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || LGTM_NAMESPACE;
    const storageSize = props?.storageSize || LGTM_STORAGE.loki;
    const image = props?.image || LGTM_IMAGES.loki;
    const retentionHours = props?.retentionHours || LGTM_RETENTION_HOURS;
    const resources = props?.resources || LGTM_RESOURCES.loki;

    const labels = getLgtmComponentLabels('loki', 'logs-backend');
    const selectorLabels = getLgtmSelectorLabels('loki');

    // ConfigMap with Loki configuration
    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'loki-config',
        namespace,
        labels,
      },
      data: {
        'config.yaml': generateLokiConfig(retentionHours),
      },
    });

    // PersistentVolumeClaim for Loki data
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'loki-data',
        namespace,
        labels,
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

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'loki',
        namespace,
        labels,
      },
      spec: {
        replicas: 1,
        strategy: { type: 'Recreate' }, // Required for single-node with PVC
        selector: { matchLabels: selectorLabels },
        template: {
          metadata: { labels },
          spec: {
            securityContext: {
              fsGroup: 10001,
              runAsUser: 10001,
              runAsNonRoot: true,
            },
            containers: [
              {
                name: 'loki',
                image,
                args: ['-config.file=/etc/loki/config.yaml', '-target=all'],
                ports: [
                  { containerPort: 3100, name: 'http' },
                  { containerPort: 9096, name: 'grpc' },
                ],
                volumeMounts: [
                  {
                    name: 'config',
                    mountPath: '/etc/loki',
                  },
                  {
                    name: 'data',
                    mountPath: '/data/loki',
                  },
                ],
                resources: toK8sResources(resources),
                readinessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(3100),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(3100),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                },
              },
            ],
            volumes: [
              {
                name: 'config',
                configMap: { name: 'loki-config' },
              },
              {
                name: 'data',
                persistentVolumeClaim: { claimName: 'loki-data' },
              },
            ],
          },
        },
      },
    });

    // Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'loki',
        namespace,
        labels,
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 3100,
            targetPort: k8s.IntOrString.fromNumber(3100),
          },
          {
            name: 'grpc',
            port: 9096,
            targetPort: k8s.IntOrString.fromNumber(9096),
          },
        ],
        selector: selectorLabels,
      },
    });
  }
}
