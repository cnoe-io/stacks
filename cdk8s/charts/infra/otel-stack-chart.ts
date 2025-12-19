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
   * @default 'otel/opentelemetry-collector-contrib:0.142.0'
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
    const otelCollectorImage = props?.otelCollectorImage || 'otel/opentelemetry-collector-contrib:0.142.0';
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

    // ConfigMap for ClickHouse user configuration (match Docker image default password)
    const clickhouseUsersXml = `<?xml version="1.0"?>
<clickhouse>
  <users>
    <default>
      <password>clickhouse_langfuse_password</password>
      <networks>
        <ip>::/0</ip>
      </networks>
      <profile>default</profile>
      <quota>default</quota>
      <access_management>1</access_management>
    </default>
  </users>
</clickhouse>`;

    new k8s.KubeConfigMap(this, 'clickhouse-users-config', {
      metadata: {
        name: 'otel-clickhouse-users',
        namespace,
        labels: clickhouseLabels,
      },
      data: {
        'default.xml': clickhouseUsersXml,
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
              env: [
                // Allow default user without password
                { name: 'CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT', value: '1' },
                { name: 'ALLOW_EMPTY_PASSWORD', value: 'yes' },
              ],
              volumeMounts: [
                {
                  name: 'data',
                  mountPath: '/var/lib/clickhouse',
                },
                {
                  name: 'config',
                  mountPath: '/etc/clickhouse-server/users.d/default.xml',
                  subPath: 'default.xml',
                },
              ],
              resources: {
                requests: { memory: k8s.Quantity.fromString('1Gi'), cpu: k8s.Quantity.fromString('500m') },
                limits: { memory: k8s.Quantity.fromString('4Gi'), cpu: k8s.Quantity.fromString('2') },
              },
            }],
            volumes: [
              {
                name: 'data',
                persistentVolumeClaim: { claimName: 'otel-clickhouse-pvc' },
              },
              {
                name: 'config',
                configMap: { name: 'otel-clickhouse-users' },
              },
            ],
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
          username: 'default',
          password: 'clickhouse_langfuse_password',
          timeout: '5s',
          retry_on_failure: { enabled: true },
          create_schema: true,
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

    // Grafana Datasource Provisioning - ClickHouse with OTEL settings for correlation
    const datasourceConfig = {
      apiVersion: 1,
      datasources: [
        {
          name: 'ClickHouse-OTEL',
          type: 'grafana-clickhouse-datasource',
          uid: 'clickhouse-otel',
          access: 'proxy',
          url: 'http://otel-clickhouse:8123',
          isDefault: true,
          jsonData: {
            host: 'otel-clickhouse',
            port: 9000,
            protocol: 'native',
            secure: false,
            username: 'default',
            defaultDatabase: 'otel',
            // Traces configuration for OTEL exporter schema
            traces: {
              defaultDatabase: 'otel',
              defaultTable: 'otel_traces',
              otelEnabled: true,
              otelVersion: 'latest',
              traceIdColumn: 'TraceId',
              spanIdColumn: 'SpanId',
              operationNameColumn: 'SpanName',
              parentSpanIdColumn: 'ParentSpanId',
              serviceNameColumn: 'ServiceName',
              durationTimeColumn: 'Duration',
              durationUnit: 'nanoseconds',
              startTimeColumn: 'Timestamp',
              tagsColumn: 'SpanAttributes',
              serviceTagsColumn: 'ResourceAttributes',
            },
            // Logs configuration for OTEL exporter schema
            logs: {
              defaultDatabase: 'otel',
              defaultTable: 'otel_logs',
              otelEnabled: true,
              otelVersion: 'latest',
              timeColumn: 'Timestamp',
              levelColumn: 'SeverityText',
              messageColumn: 'Body',
            },
          },
          secureJsonData: {
            password: 'clickhouse_langfuse_password',
          },
        },
      ],
    };

    new k8s.KubeConfigMap(this, 'grafana-datasources', {
      metadata: {
        name: 'grafana-datasources',
        namespace,
        labels: grafanaLabels,
      },
      data: {
        'datasources.yaml': JSON.stringify(datasourceConfig, null, 2),
      },
    });

    // Grafana Dashboard Provisioning Config
    const dashboardProvisionerConfig = {
      apiVersion: 1,
      providers: [
        {
          name: 'OTEL Dashboards',
          orgId: 1,
          folder: 'OpenTelemetry',
          type: 'file',
          disableDeletion: false,
          editable: true,
          options: {
            path: '/var/lib/grafana/dashboards',
          },
        },
      ],
    };

    new k8s.KubeConfigMap(this, 'grafana-dashboard-provisioner', {
      metadata: {
        name: 'grafana-dashboard-provisioner',
        namespace,
        labels: grafanaLabels,
      },
      data: {
        'dashboards.yaml': JSON.stringify(dashboardProvisionerConfig, null, 2),
      },
    });

    // OTEL Traces Dashboard with Log Correlation
    const tracesDashboard = createTracesDashboard();
    const logsDashboard = createLogsDashboard();
    const metricsDashboard = createMetricsDashboard();
    const overviewDashboard = createOverviewDashboard();

    new k8s.KubeConfigMap(this, 'grafana-dashboards', {
      metadata: {
        name: 'grafana-dashboards',
        namespace,
        labels: grafanaLabels,
      },
      data: {
        'otel-traces.json': JSON.stringify(tracesDashboard),
        'otel-logs.json': JSON.stringify(logsDashboard),
        'otel-metrics.json': JSON.stringify(metricsDashboard),
        'otel-overview.json': JSON.stringify(overviewDashboard),
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
                // Install ClickHouse plugin
                { name: 'GF_INSTALL_PLUGINS', value: 'grafana-clickhouse-datasource' },
                // Enable feature toggles for better tracing
                { name: 'GF_FEATURE_TOGGLES_ENABLE', value: 'traceToLogs,traceToMetrics' },
              ],
              volumeMounts: [
                { name: 'data', mountPath: '/var/lib/grafana' },
                { name: 'datasources', mountPath: '/etc/grafana/provisioning/datasources' },
                { name: 'dashboard-provisioner', mountPath: '/etc/grafana/provisioning/dashboards' },
                { name: 'dashboards', mountPath: '/var/lib/grafana/dashboards' },
              ],
            }],
            volumes: [
              { name: 'data', persistentVolumeClaim: { claimName: 'grafana-pvc' } },
              { name: 'datasources', configMap: { name: 'grafana-datasources' } },
              { name: 'dashboard-provisioner', configMap: { name: 'grafana-dashboard-provisioner' } },
              { name: 'dashboards', configMap: { name: 'grafana-dashboards' } },
            ],
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

// --- Dashboard Definitions ---

function createTracesDashboard(): object {
  return {
    title: 'OpenTelemetry Traces',
    uid: 'otel-traces',
    tags: ['opentelemetry', 'traces', 'clickhouse'],
    timezone: 'browser',
    schemaVersion: 39,
    version: 1,
    refresh: '30s',
    time: { from: 'now-1h', to: 'now' },
    templating: {
      list: [
        {
          name: 'service',
          type: 'query',
          datasource: { uid: 'clickhouse-otel' },
          query: 'SELECT DISTINCT ServiceName FROM otel.otel_traces WHERE $__timeFilter(Timestamp)',
          refresh: 2,
          includeAll: true,
          multi: true,
        },
      ],
    },
    panels: [
      {
        id: 1,
        title: 'Trace Count by Service',
        type: 'timeseries',
        gridPos: { x: 0, y: 0, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            toStartOfInterval(Timestamp, INTERVAL 1 minute) as time,
            ServiceName,
            count() as count
          FROM otel.otel_traces
          WHERE $__timeFilter(Timestamp)
            AND $__conditionalAll(ServiceName IN ($service), $service)
          GROUP BY time, ServiceName
          ORDER BY time`,
          format: 1,
          refId: 'A',
        }],
      },
      {
        id: 2,
        title: 'Average Span Duration by Service',
        type: 'timeseries',
        gridPos: { x: 12, y: 0, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            toStartOfInterval(Timestamp, INTERVAL 1 minute) as time,
            ServiceName,
            avg(Duration) / 1000000 as avg_duration_ms
          FROM otel.otel_traces
          WHERE $__timeFilter(Timestamp)
            AND $__conditionalAll(ServiceName IN ($service), $service)
          GROUP BY time, ServiceName
          ORDER BY time`,
          format: 1,
          refId: 'A',
        }],
        fieldConfig: {
          defaults: { unit: 'ms' },
        },
      },
      {
        id: 3,
        title: 'Recent Traces',
        type: 'table',
        gridPos: { x: 0, y: 8, w: 24, h: 10 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            Timestamp,
            TraceId,
            SpanId,
            ServiceName,
            SpanName,
            Duration / 1000000 as duration_ms,
            StatusCode
          FROM otel.otel_traces
          WHERE $__timeFilter(Timestamp)
            AND $__conditionalAll(ServiceName IN ($service), $service)
          ORDER BY Timestamp DESC
          LIMIT 100`,
          format: 2,
          refId: 'A',
        }],
        options: {
          showHeader: true,
        },
        fieldConfig: {
          overrides: [
            {
              matcher: { id: 'byName', options: 'TraceId' },
              properties: [{
                id: 'links',
                value: [{
                  title: 'View Trace Spans',
                  url: '/d/otel-traces?var-traceId=${__value.text}',
                }],
              }],
            },
          ],
        },
      },
      {
        id: 4,
        title: 'Trace Details',
        type: 'table',
        gridPos: { x: 0, y: 18, w: 24, h: 12 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            TraceId,
            SpanId,
            ParentSpanId,
            ServiceName,
            SpanName,
            SpanKind,
            Duration / 1000000 as duration_ms,
            StatusCode,
            Timestamp
          FROM otel.otel_traces
          WHERE $__timeFilter(Timestamp)
            AND $__conditionalAll(ServiceName IN ($service), $service)
          ORDER BY Timestamp DESC, Duration DESC
          LIMIT 200`,
          format: 2,
          refId: 'A',
        }],
        options: {
          showHeader: true,
          cellHeight: 'sm',
        },
        fieldConfig: {
          defaults: {},
          overrides: [
            {
              matcher: { id: 'byName', options: 'duration_ms' },
              properties: [{ id: 'unit', value: 'ms' }],
            },
          ],
        },
      },
    ],
    // Links for correlation
    links: [
      {
        title: 'View Logs',
        type: 'link',
        icon: 'doc',
        url: '/d/otel-logs',
        tooltip: 'Jump to Logs Dashboard',
      },
    ],
  };
}

function createLogsDashboard(): object {
  return {
    title: 'OpenTelemetry Logs',
    uid: 'otel-logs',
    tags: ['opentelemetry', 'logs', 'clickhouse'],
    timezone: 'browser',
    schemaVersion: 39,
    version: 1,
    refresh: '30s',
    time: { from: 'now-1h', to: 'now' },
    templating: {
      list: [
        {
          name: 'service',
          type: 'query',
          datasource: { uid: 'clickhouse-otel' },
          query: 'SELECT DISTINCT ServiceName FROM otel.otel_logs WHERE $__timeFilter(Timestamp)',
          refresh: 2,
          includeAll: true,
          multi: true,
        },
        {
          name: 'severity',
          type: 'query',
          datasource: { uid: 'clickhouse-otel' },
          query: 'SELECT DISTINCT SeverityText FROM otel.otel_logs WHERE $__timeFilter(Timestamp)',
          refresh: 2,
          includeAll: true,
          multi: true,
        },
      ],
    },
    panels: [
      {
        id: 1,
        title: 'Log Volume by Severity',
        type: 'timeseries',
        gridPos: { x: 0, y: 0, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            toStartOfInterval(Timestamp, INTERVAL 1 minute) as time,
            SeverityText,
            count() as count
          FROM otel.otel_logs
          WHERE $__timeFilter(Timestamp)
            AND $__conditionalAll(ServiceName IN ($service), $service)
            AND $__conditionalAll(SeverityText IN ($severity), $severity)
          GROUP BY time, SeverityText
          ORDER BY time`,
          format: 1,
          refId: 'A',
        }],
        fieldConfig: {
          overrides: [
            { matcher: { id: 'byName', options: 'ERROR' }, properties: [{ id: 'color', value: { mode: 'fixed', fixedColor: 'red' } }] },
            { matcher: { id: 'byName', options: 'WARN' }, properties: [{ id: 'color', value: { mode: 'fixed', fixedColor: 'yellow' } }] },
            { matcher: { id: 'byName', options: 'INFO' }, properties: [{ id: 'color', value: { mode: 'fixed', fixedColor: 'green' } }] },
          ],
        },
      },
      {
        id: 2,
        title: 'Log Volume by Service',
        type: 'timeseries',
        gridPos: { x: 12, y: 0, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            toStartOfInterval(Timestamp, INTERVAL 1 minute) as time,
            ServiceName,
            count() as count
          FROM otel.otel_logs
          WHERE $__timeFilter(Timestamp)
            AND $__conditionalAll(ServiceName IN ($service), $service)
          GROUP BY time, ServiceName
          ORDER BY time`,
          format: 1,
          refId: 'A',
        }],
      },
      {
        id: 3,
        title: 'Log Stream',
        type: 'table',
        gridPos: { x: 0, y: 8, w: 24, h: 14 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            Timestamp as timestamp,
            Body as content,
            SeverityText as level,
            ServiceName as service,
            TraceId as traceId,
            SpanId as spanId
          FROM otel.otel_logs
          WHERE $__timeFilter(Timestamp)
            AND $__conditionalAll(ServiceName IN ($service), $service)
            AND $__conditionalAll(SeverityText IN ($severity), $severity)
          ORDER BY Timestamp DESC
          LIMIT 500`,
          format: 2,
          refId: 'A',
        }],
        options: {
          showLabels: true,
          showTime: true,
          wrapLogMessage: true,
          enableLogDetails: true,
        },
      },
    ],
    // Links for correlation - jump to trace from log
    links: [
      {
        title: 'View Traces',
        type: 'link',
        icon: 'gf-traces',
        url: '/d/otel-traces',
        tooltip: 'Jump to Traces Dashboard',
      },
    ],
  };
}

function createMetricsDashboard(): object {
  return {
    title: 'OpenTelemetry Metrics',
    uid: 'otel-metrics',
    tags: ['opentelemetry', 'metrics', 'clickhouse'],
    timezone: 'browser',
    schemaVersion: 39,
    version: 1,
    refresh: '30s',
    time: { from: 'now-1h', to: 'now' },
    templating: {
      list: [
        {
          name: 'metric',
          type: 'query',
          datasource: { uid: 'clickhouse-otel' },
          query: 'SELECT DISTINCT MetricName FROM otel.otel_metrics_sum WHERE $__timeFilter(TimeUnix)',
          refresh: 2,
          includeAll: false,
        },
      ],
    },
    panels: [
      {
        id: 1,
        title: 'Gauge Metrics',
        type: 'timeseries',
        gridPos: { x: 0, y: 0, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            toStartOfInterval(TimeUnix, INTERVAL 1 minute) as time,
            MetricName,
            avg(Value) as value
          FROM otel.otel_metrics_gauge
          WHERE $__timeFilter(TimeUnix)
          GROUP BY time, MetricName
          ORDER BY time
          LIMIT 1000`,
          format: 1,
          refId: 'A',
        }],
      },
      {
        id: 2,
        title: 'Sum Metrics (Counters)',
        type: 'timeseries',
        gridPos: { x: 12, y: 0, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            toStartOfInterval(TimeUnix, INTERVAL 1 minute) as time,
            MetricName,
            sum(Value) as value
          FROM otel.otel_metrics_sum
          WHERE $__timeFilter(TimeUnix)
          GROUP BY time, MetricName
          ORDER BY time
          LIMIT 1000`,
          format: 1,
          refId: 'A',
        }],
      },
      {
        id: 3,
        title: 'Histogram Metrics (p50, p90, p99)',
        type: 'timeseries',
        gridPos: { x: 0, y: 8, w: 24, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            toStartOfInterval(TimeUnix, INTERVAL 1 minute) as time,
            MetricName,
            quantile(0.50)(Sum / Count) as p50,
            quantile(0.90)(Sum / Count) as p90,
            quantile(0.99)(Sum / Count) as p99
          FROM otel.otel_metrics_histogram
          WHERE $__timeFilter(TimeUnix)
            AND Count > 0
          GROUP BY time, MetricName
          ORDER BY time
          LIMIT 1000`,
          format: 1,
          refId: 'A',
        }],
      },
      {
        id: 4,
        title: 'Available Metrics',
        type: 'table',
        gridPos: { x: 0, y: 16, w: 24, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            'gauge' as type, MetricName, count() as samples
          FROM otel.otel_metrics_gauge
          WHERE $__timeFilter(TimeUnix)
          GROUP BY MetricName
          UNION ALL
          SELECT
            'sum' as type, MetricName, count() as samples
          FROM otel.otel_metrics_sum
          WHERE $__timeFilter(TimeUnix)
          GROUP BY MetricName
          UNION ALL
          SELECT
            'histogram' as type, MetricName, count() as samples
          FROM otel.otel_metrics_histogram
          WHERE $__timeFilter(TimeUnix)
          GROUP BY MetricName
          ORDER BY type, MetricName`,
          format: 2,
          refId: 'A',
        }],
      },
    ],
  };
}

function createOverviewDashboard(): object {
  return {
    title: 'OpenTelemetry Overview',
    uid: 'otel-overview',
    tags: ['opentelemetry', 'overview', 'clickhouse'],
    timezone: 'browser',
    schemaVersion: 39,
    version: 1,
    refresh: '30s',
    time: { from: 'now-1h', to: 'now' },
    panels: [
      {
        id: 1,
        title: 'Total Traces',
        type: 'stat',
        gridPos: { x: 0, y: 0, w: 6, h: 4 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT count(DISTINCT TraceId) as traces FROM otel.otel_traces WHERE $__timeFilter(Timestamp)`,
          format: 2,
          refId: 'A',
        }],
        options: { colorMode: 'value', graphMode: 'area' },
        fieldConfig: { defaults: { color: { mode: 'palette-classic' } } },
      },
      {
        id: 2,
        title: 'Total Spans',
        type: 'stat',
        gridPos: { x: 6, y: 0, w: 6, h: 4 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT count() as spans FROM otel.otel_traces WHERE $__timeFilter(Timestamp)`,
          format: 2,
          refId: 'A',
        }],
        options: { colorMode: 'value', graphMode: 'area' },
      },
      {
        id: 3,
        title: 'Total Logs',
        type: 'stat',
        gridPos: { x: 12, y: 0, w: 6, h: 4 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT count() as logs FROM otel.otel_logs WHERE $__timeFilter(Timestamp)`,
          format: 2,
          refId: 'A',
        }],
        options: { colorMode: 'value', graphMode: 'area' },
      },
      {
        id: 4,
        title: 'Error Logs',
        type: 'stat',
        gridPos: { x: 18, y: 0, w: 6, h: 4 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT count() as errors FROM otel.otel_logs WHERE $__timeFilter(Timestamp) AND SeverityText = 'ERROR'`,
          format: 2,
          refId: 'A',
        }],
        options: { colorMode: 'value', graphMode: 'area' },
        fieldConfig: { defaults: { color: { mode: 'fixed', fixedColor: 'red' } } },
      },
      {
        id: 5,
        title: 'Services',
        type: 'piechart',
        gridPos: { x: 0, y: 4, w: 8, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT ServiceName, count() as count FROM otel.otel_traces WHERE $__timeFilter(Timestamp) GROUP BY ServiceName ORDER BY count DESC LIMIT 10`,
          format: 2,
          refId: 'A',
        }],
      },
      {
        id: 6,
        title: 'Telemetry Volume Over Time',
        type: 'timeseries',
        gridPos: { x: 8, y: 4, w: 16, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [
          {
            queryType: 'sql',
            rawSql: `SELECT toStartOfInterval(Timestamp, INTERVAL 1 minute) as time, 'traces' as type, count() as count FROM otel.otel_traces WHERE $__timeFilter(Timestamp) GROUP BY time ORDER BY time`,
            format: 1,
            refId: 'A',
          },
          {
            queryType: 'sql',
            rawSql: `SELECT toStartOfInterval(Timestamp, INTERVAL 1 minute) as time, 'logs' as type, count() as count FROM otel.otel_logs WHERE $__timeFilter(Timestamp) GROUP BY time ORDER BY time`,
            format: 1,
            refId: 'B',
          },
        ],
      },
      {
        id: 7,
        title: 'Slowest Operations (p99)',
        type: 'table',
        gridPos: { x: 0, y: 12, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            ServiceName,
            SpanName,
            quantile(0.99)(Duration) / 1000000 as p99_ms,
            count() as count
          FROM otel.otel_traces
          WHERE $__timeFilter(Timestamp)
          GROUP BY ServiceName, SpanName
          HAVING count() > 10
          ORDER BY p99_ms DESC
          LIMIT 20`,
          format: 2,
          refId: 'A',
        }],
        fieldConfig: {
          overrides: [
            { matcher: { id: 'byName', options: 'p99_ms' }, properties: [{ id: 'unit', value: 'ms' }] },
          ],
        },
      },
      {
        id: 8,
        title: 'Error Rate by Service',
        type: 'table',
        gridPos: { x: 12, y: 12, w: 12, h: 8 },
        datasource: { uid: 'clickhouse-otel' },
        targets: [{
          queryType: 'sql',
          rawSql: `SELECT
            ServiceName,
            countIf(StatusCode = 'STATUS_CODE_ERROR') as errors,
            count() as total,
            round(countIf(StatusCode = 'STATUS_CODE_ERROR') * 100.0 / count(), 2) as error_rate
          FROM otel.otel_traces
          WHERE $__timeFilter(Timestamp)
          GROUP BY ServiceName
          HAVING total > 0
          ORDER BY error_rate DESC`,
          format: 2,
          refId: 'A',
        }],
        fieldConfig: {
          overrides: [
            { matcher: { id: 'byName', options: 'error_rate' }, properties: [{ id: 'unit', value: 'percent' }] },
          ],
        },
      },
    ],
    // Navigation links
    links: [
      { title: 'Traces', type: 'link', icon: 'gf-traces', url: '/d/otel-traces', tooltip: 'Detailed Traces' },
      { title: 'Logs', type: 'link', icon: 'doc', url: '/d/otel-logs', tooltip: 'Log Explorer' },
      { title: 'Metrics', type: 'link', icon: 'graph-bar', url: '/d/otel-metrics', tooltip: 'Metrics Dashboard' },
    ],
  };
}
