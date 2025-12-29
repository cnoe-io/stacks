/**
 * FlagdChart - OpenFeature flagd deployment
 *
 * Deploys flagd as a centralized feature flag evaluation service.
 * - gRPC endpoint (8013) for OpenFeature SDK evaluations
 * - OFREP HTTP endpoint (8016) for REST-based evaluations
 * - Metrics endpoint (8015) for Prometheus scraping
 * - Syncs with Flipt via gRPC for flag configurations
 *
 * Sync wave: -75 (after secrets, before applications)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface FlagdChartProps extends ChartProps {
  /**
   * Namespace for flagd deployment
   * @default 'feature-flags'
   */
  namespace?: string;

  /**
   * flagd image version
   * @default '0.11.0'
   */
  imageVersion?: string;

  /**
   * Flipt host for sync source
   * @default 'flipt.feature-flags.svc.cluster.local'
   */
  fliptHost?: string;

  /**
   * Flipt port for sync source
   * @default 8080
   */
  fliptPort?: number;

  /**
   * OpenTelemetry collector endpoint
   * @default 'otel-collector.observability.svc.cluster.local:4317'
   */
  otelCollectorEndpoint?: string;

  /**
   * CPU request
   * @default '50m'
   */
  cpuRequest?: string;

  /**
   * CPU limit
   * @default '200m'
   */
  cpuLimit?: string;

  /**
   * Memory request
   * @default '64Mi'
   */
  memoryRequest?: string;

  /**
   * Memory limit
   * @default '128Mi'
   */
  memoryLimit?: string;
}

export class FlagdChart extends Chart {
  constructor(scope: Construct, id: string, props?: FlagdChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'feature-flags';
    const imageVersion = props?.imageVersion || '0.11.0';
    const fliptHost = props?.fliptHost || 'flipt.feature-flags.svc.cluster.local';
    const fliptPort = props?.fliptPort || 8080;
    const otelCollectorEndpoint = props?.otelCollectorEndpoint || 'otel-collector.observability.svc.cluster.local:4317';

    const cpuRequest = props?.cpuRequest || '50m';
    const cpuLimit = props?.cpuLimit || '200m';
    const memoryRequest = props?.memoryRequest || '64Mi';
    const memoryLimit = props?.memoryLimit || '128Mi';

    const labels = {
      'app': 'flagd',
      'app.kubernetes.io/name': 'flagd',
      'app.kubernetes.io/component': 'evaluation-engine',
      'app.kubernetes.io/part-of': 'feature-flags',
    };

    const syncWave = '-75';

    // ConfigMap for flagd configuration
    new k8s.KubeConfigMap(this, 'config', {
      metadata: {
        name: 'flagd-config',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      data: {
        'flagd.json': JSON.stringify({
          '$schema': 'https://flagd.dev/schema/v0/flags.json',
          'flags': {
            'new-checkout-flow': {
              'state': 'ENABLED',
              'variants': {
                'on': true,
                'off': false,
              },
              'defaultVariant': 'off',
            },
            'dark-mode': {
              'state': 'ENABLED',
              'variants': {
                'on': true,
                'off': false,
              },
              'defaultVariant': 'on',
            },
          },
        }, null, 2),
      },
    });

    // Deployment
    new k8s.KubeDeployment(this, 'deployment', {
      metadata: {
        name: 'flagd',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            'app': 'flagd',
          },
        },
        template: {
          metadata: {
            labels,
            annotations: {
              // Enable Prometheus scraping
              'prometheus.io/scrape': 'true',
              'prometheus.io/port': '8015',
              'prometheus.io/path': '/metrics',
            },
          },
          spec: {
            securityContext: {
              runAsNonRoot: true,
              runAsUser: 65532,
              runAsGroup: 65532,
              fsGroup: 65532,
            },
            containers: [
              {
                name: 'flagd',
                image: `ghcr.io/open-feature/flagd:v${imageVersion}`,
                args: [
                  'start',
                  // Use ConfigMap as flag source - Flipt is for management UI only
                  '--uri', 'file:/etc/flagd/flagd.json',
                  '--management-port', '8015',
                  '--port', '8013',
                  '--ofrep-port', '8016',
                ],
                ports: [
                  { containerPort: 8013, name: 'grpc', protocol: 'TCP' },
                  { containerPort: 8015, name: 'metrics', protocol: 'TCP' },
                  { containerPort: 8016, name: 'ofrep', protocol: 'TCP' },
                ],
                env: [
                  // OpenTelemetry configuration
                  { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: `http://${otelCollectorEndpoint}` },
                  { name: 'OTEL_SERVICE_NAME', value: 'flagd' },
                  { name: 'OTEL_TRACES_EXPORTER', value: 'otlp' },
                  { name: 'OTEL_METRICS_EXPORTER', value: 'otlp' },
                ],
                resources: {
                  requests: {
                    cpu: k8s.Quantity.fromString(cpuRequest),
                    memory: k8s.Quantity.fromString(memoryRequest),
                  },
                  limits: {
                    cpu: k8s.Quantity.fromString(cpuLimit),
                    memory: k8s.Quantity.fromString(memoryLimit),
                  },
                },
                volumeMounts: [
                  {
                    name: 'flagd-config',
                    mountPath: '/etc/flagd',
                    readOnly: true,
                  },
                ],
                securityContext: {
                  allowPrivilegeEscalation: false,
                  readOnlyRootFilesystem: true,
                  capabilities: {
                    drop: ['ALL'],
                  },
                },
                livenessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(8013),
                  },
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                  failureThreshold: 3,
                },
                readinessProbe: {
                  tcpSocket: {
                    port: k8s.IntOrString.fromNumber(8013),
                  },
                  initialDelaySeconds: 5,
                  periodSeconds: 5,
                  failureThreshold: 3,
                },
              },
            ],
            volumes: [
              {
                name: 'flagd-config',
                configMap: {
                  name: 'flagd-config',
                },
              },
            ],
          },
        },
      },
    });

    // Service for gRPC and OFREP
    new k8s.KubeService(this, 'service', {
      metadata: {
        name: 'flagd',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        type: 'ClusterIP',
        selector: { 'app': 'flagd' },
        ports: [
          {
            name: 'grpc',
            port: 8013,
            targetPort: k8s.IntOrString.fromNumber(8013),
            protocol: 'TCP',
          },
          {
            name: 'ofrep',
            port: 8016,
            targetPort: k8s.IntOrString.fromNumber(8016),
            protocol: 'TCP',
          },
          {
            name: 'metrics',
            port: 8015,
            targetPort: k8s.IntOrString.fromNumber(8015),
            protocol: 'TCP',
          },
        ],
      },
    });

    // ServiceMonitor for Prometheus Operator (if available)
    // Note: This requires the Prometheus Operator CRD
    // Commenting out for now - can be enabled when ServiceMonitor CRD is imported
    /*
    new k8s.KubeCustomResource(this, 'service-monitor', {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: 'flagd',
        namespace,
        labels,
        annotations: {
          'argocd.argoproj.io/sync-wave': syncWave,
        },
      },
      spec: {
        selector: {
          matchLabels: {
            'app': 'flagd',
          },
        },
        endpoints: [
          {
            port: 'metrics',
            interval: '30s',
          },
        ],
      },
    });
    */
  }
}
