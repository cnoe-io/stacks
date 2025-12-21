/**
 * LgtmOtelCollectorChart - OpenTelemetry Collector for LGTM Stack
 *
 * Deploys OTEL Collector as the unified ingestion gateway.
 * Routes metrics to Mimir, logs to Loki, and traces to Tempo.
 *
 * Feature: 111-configure-k8s-observability
 * Sync wave: -55 (after backends)
 *
 * Ports:
 * - 4317: OTLP gRPC receiver
 * - 4318: OTLP HTTP receiver
 * - 8888: Internal metrics
 * - 13133: Health check
 *
 * Endpoints:
 * - OTLP gRPC: otel-collector:4317
 * - OTLP HTTP: otel-collector:4318
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import {
  LGTM_NAMESPACE,
  LGTM_IMAGES,
  LGTM_RESOURCES,
  getLgtmComponentLabels,
  getLgtmSelectorLabels,
  toK8sResources,
  generateOtelCollectorConfig,
} from '../../lib/lgtm-helpers';

export interface LgtmOtelCollectorChartProps extends ChartProps {
  /**
   * Namespace for OTEL Collector deployment
   * @default 'observability'
   */
  namespace?: string;

  /**
   * OTEL Collector container image
   * @default 'otel/opentelemetry-collector-contrib:0.115.0'
   */
  image?: string;

  /**
   * Mimir Prometheus remote write endpoint
   * @default 'http://mimir:9009/api/v1/push'
   */
  mimirEndpoint?: string;

  /**
   * Loki push endpoint
   * @default 'http://loki:3100/loki/api/v1/push'
   */
  lokiEndpoint?: string;

  /**
   * Tempo OTLP gRPC endpoint
   * @default 'tempo:4317'
   */
  tempoEndpoint?: string;

  /**
   * Langfuse OTLP HTTP endpoint
   * @default 'http://langfuse:3000/api/public/otlp'
   */
  langfuseEndpoint?: string;

  /**
   * Secret name containing LANGFUSE_AUTH
   * @default 'langfuse-api'
   */
  langfuseAuthSecret?: string;

  /**
   * Resource requests and limits
   */
  resources?: {
    requests?: { cpu?: string; memory?: string };
    limits?: { cpu?: string; memory?: string };
  };
}

export class LgtmOtelCollectorChart extends Chart {
  constructor(scope: Construct, id: string, props?: LgtmOtelCollectorChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || LGTM_NAMESPACE;
    const image = props?.image || LGTM_IMAGES.otelCollector;
    const mimirEndpoint = props?.mimirEndpoint || 'http://mimir:9009/api/v1/push';
    const lokiEndpoint = props?.lokiEndpoint || 'http://loki:3100/loki/api/v1/push';
    const tempoEndpoint = props?.tempoEndpoint || 'tempo:4317';
    const langfuseEndpoint = props?.langfuseEndpoint;
    const langfuseAuthSecret = props?.langfuseAuthSecret || 'langfuse-api';
    const resources = props?.resources || LGTM_RESOURCES.otelCollector;

    const labels = getLgtmComponentLabels('otel-collector', 'ingestion-gateway');
    const selectorLabels = getLgtmSelectorLabels('otel-collector');

    // ConfigMap with OTEL Collector configuration
    const collectorConfig = generateOtelCollectorConfig(mimirEndpoint, lokiEndpoint, tempoEndpoint, langfuseEndpoint);

    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'otel-collector-config',
        namespace,
        labels,
      },
      data: {
        'config.yaml': JSON.stringify(collectorConfig, null, 2),
      },
    });

    // Env vars for collector
    const env: k8s.EnvVar[] = [];
    if (langfuseEndpoint) {
      env.push({
        name: 'LANGFUSE_AUTH',
        valueFrom: {
          secretKeyRef: {
            name: langfuseAuthSecret,
            key: 'LANGFUSE_AUTH',
          },
        },
      });
    }

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'otel-collector',
        namespace,
        labels,
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: selectorLabels },
        template: {
          metadata: { labels },
          spec: {
            containers: [
              {
                name: 'otel-collector',
                image,
                command: ['/otelcol-contrib', '--config=/conf/config.yaml'],
                ports: [
                  { containerPort: 4317, name: 'otlp-grpc' },
                  { containerPort: 4318, name: 'otlp-http' },
                  { containerPort: 8888, name: 'metrics' },
                  { containerPort: 13133, name: 'health' },
                ],
                env,
                volumeMounts: [
                  {
                    name: 'config',
                    mountPath: '/conf',
                  },
                ],
                resources: toK8sResources(resources),
                readinessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(13133),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 10,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/',
                    port: k8s.IntOrString.fromNumber(13133),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 30,
                },
              },
            ],
            volumes: [
              {
                name: 'config',
                configMap: { name: 'otel-collector-config' },
              },
            ],
          },
        },
      },
    });

    // Service
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'otel-collector',
        namespace,
        labels,
      },
      spec: {
        type: 'ClusterIP',
        ports: [
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
            name: 'metrics',
            port: 8888,
            targetPort: k8s.IntOrString.fromNumber(8888),
          },
        ],
        selector: selectorLabels,
      },
    });
  }
}
