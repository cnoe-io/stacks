/**
 * LgtmTempoChart - Grafana Tempo Deployment for Distributed Tracing
 *
 * Deploys Tempo in monolithic mode with local filesystem storage.
 * Provides distributed tracing with OTLP receiver and TraceQL query support.
 *
 * Feature: 111-configure-k8s-observability
 * Sync wave: -60 (after namespace)
 *
 * Ports:
 * - 3200: HTTP API (query, search)
 * - 4317: OTLP gRPC receiver
 * - 4318: OTLP HTTP receiver
 * - 9095: gRPC (internal)
 *
 * Endpoints:
 * - Query: http://tempo:3200
 * - OTLP gRPC: tempo:4317
 * - OTLP HTTP: tempo:4318
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
  generateTempoConfig,
} from '../../lib/lgtm-helpers';

export interface LgtmTempoChartProps extends ChartProps {
  /**
   * Namespace for Tempo deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * Storage size for Tempo traces and WAL
   * @default '20Gi'
   */
  storageSize?: string;

  /**
   * Tempo container image
   * @default 'grafana/tempo:2.6.1'
   */
  image?: string;

  /**
   * Retention period in hours
   * @default '720h' (30 days)
   */
  retentionHours?: string;

  /**
   * Mimir endpoint for metrics_generator remote write
   * @default 'http://mimir:9009/api/v1/push'
   */
  mimirEndpoint?: string;

  /**
   * Resource requests and limits
   */
  resources?: {
    requests?: { cpu?: string; memory?: string };
    limits?: { cpu?: string; memory?: string };
  };
}

export class LgtmTempoChart extends Chart {
  constructor(scope: Construct, id: string, props?: LgtmTempoChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || LGTM_NAMESPACE;
    const storageSize = props?.storageSize || LGTM_STORAGE.tempo;
    const image = props?.image || LGTM_IMAGES.tempo;
    const retentionHours = props?.retentionHours || LGTM_RETENTION_HOURS;
    const mimirEndpoint = props?.mimirEndpoint || 'http://mimir:9009/api/v1/push';
    const resources = props?.resources || LGTM_RESOURCES.tempo;

    const labels = getLgtmComponentLabels('tempo', 'traces-backend');
    const selectorLabels = getLgtmSelectorLabels('tempo');

    // ConfigMap with Tempo configuration
    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'tempo-config',
        namespace,
        labels,
      },
      data: {
        'config.yaml': generateTempoConfig(mimirEndpoint, retentionHours),
      },
    });

    // PersistentVolumeClaim for Tempo data
    new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: {
        name: 'tempo-data',
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
        name: 'tempo',
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
                name: 'tempo',
                image,
                args: ['-config.file=/etc/tempo/config.yaml', '-target=all'],
                ports: [
                  { containerPort: 3200, name: 'http' },
                  { containerPort: 4317, name: 'otlp-grpc' },
                  { containerPort: 4318, name: 'otlp-http' },
                  { containerPort: 9095, name: 'grpc' },
                ],
                volumeMounts: [
                  {
                    name: 'config',
                    mountPath: '/etc/tempo',
                  },
                  {
                    name: 'data',
                    mountPath: '/data/tempo',
                  },
                ],
                resources: toK8sResources(resources),
                readinessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(3200),
                  },
                  initialDelaySeconds: 15,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/ready',
                    port: k8s.IntOrString.fromNumber(3200),
                  },
                  initialDelaySeconds: 30,
                  periodSeconds: 30,
                },
              },
            ],
            volumes: [
              {
                name: 'config',
                configMap: { name: 'tempo-config' },
              },
              {
                name: 'data',
                persistentVolumeClaim: { claimName: 'tempo-data' },
              },
            ],
          },
        },
      },
    });

    // Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'tempo',
        namespace,
        labels,
      },
      spec: {
        type: 'ClusterIP',
        ports: [
          {
            name: 'http',
            port: 3200,
            targetPort: k8s.IntOrString.fromNumber(3200),
          },
          {
            name: 'otlp-grpc',
            port: 4317,
            targetPort: k8s.IntOrString.fromNumber(4317),
          },
          {
            name: 'otlp-http',
            port: 4318,
            targetPort: k8s.IntOrString.fromNumber(4318),
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
