/**
 * OtelStackChart - OpenTelemetry Stack with ClickHouse and Grafana
 *
 * Deploys:
 * - ClickHouse: Persistent storage for metrics, logs, and traces
 * - OTel Collector: Receives telemetry and exports to ClickHouse
 * - Grafana: Visualization with ClickHouse datasource
 *
 * Sync wave: -60 (after namespace and secrets)
 */

import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export interface OtelStackChartProps extends ChartProps {
  /**
   * Namespace for the stack
   * @default 'observability'
   */
  namespace?: string;

  /**
   * ClickHouse storage size
   * @default '20Gi'
   */
  clickhouseStorageSize?: string;

  /**
   * OTel Collector image
   * @default 'otel/opentelemetry-collector-contrib:0.115.0'
   */
  otelCollectorImage?: string;

  /**
   * Grafana image
   * @default 'grafana/grafana:11.3.0'
   */
  grafanaImage?: string;
}

export class OtelStackChart extends Chart {
  constructor(scope: Construct, id: string, props?: OtelStackChartProps) {
    super(scope, id, props);

    const namespace = props?.namespace || 'observability';
    const clickhouseStorageSize = props?.clickhouseStorageSize || '20Gi';
    const otelCollectorImage = props?.otelCollectorImage || 'otel/opentelemetry-collector-contrib:0.115.0';
    const grafanaImage = props?.grafanaImage || 'grafana/grafana:11.3.0';

    const labels = {
      'app.kubernetes.io/part-of': 'otel-stack',
      'app.kubernetes.io/managed-by': 'cdk8s',
    };

    // --- ClickHouse ---

    const clickhouseLabels = {
      ...labels,
      'app.kubernetes.io/name': 'clickhouse',
      'app.kubernetes.io/component': 'database',
    };

    new k8s.KubePersistentVolumeClaim(this, 'clickhouse-pvc', {
      metadata: {
        name: 'otel-clickhouse-pvc',
        namespace,
        labels: clickhouseLabels,
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString(clickhouseStorageSize),
          },
        },
      },
    });

    new k8s.KubeDeployment(this, 'clickhouse-deploy', {
      metadata: {
        name: 'otel-clickhouse',
        namespace,
        labels: clickhouseLabels,
      },
      spec: {
        replicas: 1,
        strategy: { type: 'Recreate' },
        selector: { matchLabels: { 'app.kubernetes.io/name': 'clickhouse' } },
        template: {
          metadata: { labels: clickhouseLabels },
          spec: {
            containers: [{
              name: 'clickhouse',
              image: 'clickhouse/clickhouse-server:24.3',
              ports: [
                { containerPort: 8123, name: 'http' },
                { containerPort: 9000, name: 'native' },
              ],
              volumeMounts: [{
                name: 'data',
                mountPath: '/var/lib/clickhouse',
              }],
              resources: {
                requests: { memory: k8s.Quantity.fromString('1Gi'), cpu: k8s.Quantity.fromString('500m') },
                limits: { memory: k8s.Quantity.fromString('4Gi'), cpu: k8s.Quantity.fromString('2') },
              },
            }],
            volumes: [{
              name: 'data',
              persistentVolumeClaim: { claimName: 'otel-clickhouse-pvc' },
            }],
          },
        },
      },
    });

    new k8s.KubeService(this, 'clickhouse-svc', {
      metadata: {
        name: 'otel-clickhouse',
        namespace,
        labels: clickhouseLabels,
      },
      spec: {
        ports: [
          { name: 'http', port: 8123, targetPort: k8s.IntOrString.fromNumber(8123) },
          { name: 'native', port: 9000, targetPort: k8s.IntOrString.fromNumber(9000) },
        ],
        selector: { 'app.kubernetes.io/name': 'clickhouse' },
      },
    });

    // --- OTel Collector ---

    const collectorLabels = {
      ...labels,
      'app.kubernetes.io/name': 'otel-collector',
      'app.kubernetes.io/component': 'collector',
    };

    const collectorConfig = {
      receivers: {
        otlp: {
          protocols: {
            grpc: { endpoint: '0.0.0.0:4317' },
            http: { endpoint: '0.0.0.0:4318' },
          },
        },
      },
      exporters: {
        clickhouse: {
          endpoint: 'tcp://otel-clickhouse:9000?database=otel',
          timeout: '5s',
          retry_on_failure: { enabled: true },
        },
        debug: { verbosity: 'basic' },
      },
      service: {
        pipelines: {
          traces: {
            receivers: ['otlp'],
            exporters: ['clickhouse', 'debug'],
          },
          metrics: {
            receivers: ['otlp'],
            exporters: ['clickhouse', 'debug'],
          },
          logs: {
            receivers: ['otlp'],
            exporters: ['clickhouse', 'debug'],
          },
        },
      },
    };

    new k8s.KubeConfigMap(this, 'collector-config', {
      metadata: {
        name: 'otel-collector-config',
        namespace,
        labels: collectorLabels,
      },
      data: {
        'relay.yaml': JSON.stringify(collectorConfig),
      },
    });

    new k8s.KubeDeployment(this, 'collector-deploy', {
      metadata: {
        name: 'otel-collector',
        namespace,
        labels: collectorLabels,
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: { 'app.kubernetes.io/name': 'otel-collector' } },
        template: {
          metadata: { labels: collectorLabels },
          spec: {
            containers: [{
              name: 'collector',
              image: otelCollectorImage,
              command: ['/otelcol-contrib', '--config=/conf/relay.yaml'],
              ports: [
                { containerPort: 4317, name: 'otlp-grpc' },
                { containerPort: 4318, name: 'otlp-http' },
              ],
              volumeMounts: [{
                name: 'config',
                mountPath: '/conf',
              }],
            }],
            volumes: [{
              name: 'config',
              configMap: { name: 'otel-collector-config' },
            }],
          },
        },
      },
    });

    new k8s.KubeService(this, 'collector-svc', {
      metadata: {
        name: 'otel-collector',
        namespace,
        labels: collectorLabels,
      },
      spec: {
        ports: [
          { name: 'otlp-grpc', port: 4317, targetPort: k8s.IntOrString.fromNumber(4317) },
          { name: 'otlp-http', port: 4318, targetPort: k8s.IntOrString.fromNumber(4318) },
        ],
        selector: { 'app.kubernetes.io/name': 'otel-collector' },
      },
    });

    // --- Grafana ---

    const grafanaLabels = {
      ...labels,
      'app.kubernetes.io/name': 'grafana',
      'app.kubernetes.io/component': 'visualization',
    };

    new k8s.KubePersistentVolumeClaim(this, 'grafana-pvc', {
      metadata: {
        name: 'grafana-pvc',
        namespace,
        labels: grafanaLabels,
      },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: k8s.Quantity.fromString('2Gi'),
          },
        },
      },
    });

    new k8s.KubeDeployment(this, 'grafana-deploy', {
      metadata: {
        name: 'grafana',
        namespace,
        labels: grafanaLabels,
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: { 'app.kubernetes.io/name': 'grafana' } },
        template: {
          metadata: { labels: grafanaLabels },
          spec: {
            securityContext: {
              fsGroup: 472,
              runAsUser: 472,
            },
            containers: [{
              name: 'grafana',
              image: grafanaImage,
              ports: [{ containerPort: 3000, name: 'http' }],
              env: [
                { name: 'GF_AUTH_ANONYMOUS_ENABLED', value: 'true' },
                { name: 'GF_AUTH_ANONYMOUS_ORG_ROLE', value: 'Admin' },
              ],
              volumeMounts: [{
                name: 'data',
                mountPath: '/var/lib/grafana',
              }],
            }],
            volumes: [{
              name: 'data',
              persistentVolumeClaim: { claimName: 'grafana-pvc' },
            }],
          },
        },
      },
    });

    new k8s.KubeService(this, 'grafana-svc', {
      metadata: {
        name: 'grafana',
        namespace,
        labels: grafanaLabels,
      },
      spec: {
        ports: [{ name: 'http', port: 80, targetPort: k8s.IntOrString.fromNumber(3000) }],
        selector: { 'app.kubernetes.io/name': 'grafana' },
      },
    });
  }
}
