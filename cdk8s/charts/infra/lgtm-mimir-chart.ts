/**
 * LgtmMimirChart - Grafana Mimir Deployment for Metrics Storage
 *
 * Deploys Mimir in monolithic mode with filesystem storage for single-node K3s.
 * Provides Prometheus-compatible long-term metrics storage with PromQL query support.
 *
 * Feature: 111-configure-k8s-observability
 * Sync wave: -60 (after namespace)
 *
 * Ports:
 * - 9009: HTTP API (Prometheus remote write, PromQL query)
 * - 9095: gRPC (internal)
 *
 * Endpoints:
 * - Remote Write: http://mimir:9009/api/v1/push
 * - Query: http://mimir:9009/prometheus
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
  generateMimirConfig,
} from '../../lib/lgtm-helpers';

export interface LgtmMimirChartProps extends ChartProps {
  /**
   * Namespace for Mimir deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Storage size for Mimir TSDB data
   * @default '20Gi'
   */
  storageSize?: string;

  /**
   * Mimir container image
   * @default 'grafana/mimir:2.14.0'
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

export class LgtmMimirChart extends Chart {
  constructor(scope: Construct, id: string, props?: LgtmMimirChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || LGTM_NAMESPACE;
    const storageSize = props?.storageSize || LGTM_STORAGE.mimir;
    const image = props?.image || LGTM_IMAGES.mimir;
    const retentionHours = props?.retentionHours || LGTM_RETENTION_HOURS;
    const resources = props?.resources || LGTM_RESOURCES.mimir;

    const labels = getLgtmComponentLabels('mimir', 'metrics-backend');
    const selectorLabels = getLgtmSelectorLabels('mimir');

    // ConfigMap with Mimir configuration
    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'mimir-config',
        namespace,
        labels,
      },
      data: {
        'config.yaml': generateMimirConfig(retentionHours),
      },
    });

    // PersistentVolumeClaim for Mimir data
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'mimir-data',
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
        name: 'mimir',
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
                name: 'mimir',
                image,
                args: ['-config.file=/etc/mimir/config.yaml', '-target=all'],
                ports: [
                  { containerPort: 9009, name: 'http' },
                  { containerPort: 9095, name: 'grpc' },
                ],
                volumeMounts: [
                  {
                    name: 'config',
                    mountPath: '/etc/mimir',
                  },
                  {
                    name: 'data',
                    mountPath: '/data',
                  },
                ],
                resources: toK8sResources(resources),
                readinessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(9009),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(9009),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                },
              },
            ],
            volumes: [
              {
                name: 'config',
                configMap: { name: 'mimir-config' },
              },
              {
                name: 'data',
                persistentVolumeClaim: { claimName: 'mimir-data' },
              },
            ],
          },
        },
      },
    });

    // Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'mimir',
        namespace,
        labels,
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 9009,
            targetPort: k8s.IntOrString.fromNumber(9009),
          },
          {
            name: 'grpc',
            port: 9095,
            targetPort: k8s.IntOrString.fromNumber(9095),
          },
        ],
        selector: selectorLabels,
      },
    });
  }
}
