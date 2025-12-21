/**
 * LGTM Stack Helper Functions and Constants
 *
 * Shared configuration generators, labels, and naming utilities for the
 * Grafana LGTM observability stack (Loki, Grafana, Tempo, Mimir) plus Pyroscope.
 *
 * Feature: 111-configure-k8s-observability
 */

import * as k8s from '../imports/k8s';

// =============================================================================
// Constants
// =============================================================================

/**
 * Default namespace for all LGTM components
 */
export const LGTM_NAMESPACE = 'observability';

/**
 * Default retention period for all signals (30 days in hours)
 */
export const LGTM_RETENTION_HOURS = '720h';

/**
 * LGTM Component image versions - centralized for easy updates
 */
export const LGTM_IMAGES = {
  mimir: 'grafana/mimir:2.14.0',
  loki: 'grafana/loki:3.3.0',
  tempo: 'grafana/tempo:2.6.1',
  pyroscope: 'grafana/pyroscope:1.10.0',
  grafana: 'grafana/grafana:11.3.0',
  otelCollector: 'otel/opentelemetry-collector-contrib:0.114.0',
} as const;

/**
 * Default storage sizes per component
 */
export const LGTM_STORAGE = {
  mimir: '20Gi',
  loki: '20Gi',
  tempo: '20Gi',
  pyroscope: '10Gi',
} as const;

/**
 * Default resource configurations per component
 */
export const LGTM_RESOURCES = {
  mimir: {
    requests: { cpu: '100m', memory: '512Mi' },
    limits: { cpu: '1000m', memory: '2Gi' },
  },
  loki: {
    requests: { cpu: '100m', memory: '256Mi' },
    limits: { cpu: '500m', memory: '1Gi' },
  },
  tempo: {
    requests: { cpu: '100m', memory: '256Mi' },
    limits: { cpu: '500m', memory: '1Gi' },
  },
  pyroscope: {
    requests: { cpu: '50m', memory: '128Mi' },
    limits: { cpu: '250m', memory: '512Mi' },
  },
  grafana: {
    requests: { cpu: '50m', memory: '128Mi' },
    limits: { cpu: '250m', memory: '256Mi' },
  },
  otelCollector: {
    requests: { cpu: '100m', memory: '256Mi' },
    limits: { cpu: '500m', memory: '512Mi' },
  },
} as const;

// =============================================================================
// Label Generators
// =============================================================================

/**
 * Base labels for all LGTM stack components
 */
export function getLgtmBaseLabels(): Record<string, string> {
  return {
    'app.kubernetes.io/part-of': 'lgtm-stack',
    'app.kubernetes.io/managed-by': 'cdk8s',
  };
}

/**
 * Generate labels for a specific LGTM component
 *
 * @param name - Component name (e.g., 'mimir', 'loki', 'tempo')
 * @param component - Component type (e.g., 'metrics-backend', 'logs-backend')
 */
export function getLgtmComponentLabels(
  name: string,
  component: string
): Record<string, string> {
  return {
    ...getLgtmBaseLabels(),
    'app.kubernetes.io/name': name,
    'app.kubernetes.io/component': component,
  };
}

/**
 * Generate selector labels for a LGTM component
 *
 * @param name - Component name (e.g., 'mimir', 'loki')
 */
export function getLgtmSelectorLabels(name: string): Record<string, string> {
  return {
    'app.kubernetes.io/name': name,
    'app.kubernetes.io/part-of': 'lgtm-stack',
  };
}

// =============================================================================
// Resource Helpers
// =============================================================================

/**
 * Convert resource configuration to Kubernetes Quantity objects
 */
export function toK8sResources(config: {
  requests?: { cpu?: string; memory?: string };
  limits?: { cpu?: string; memory?: string };
}): k8s.ResourceRequirements {
  return {
    requests: {
      ...(config.requests?.cpu && { cpu: k8s.Quantity.fromString(config.requests.cpu) }),
      ...(config.requests?.memory && { memory: k8s.Quantity.fromString(config.requests.memory) }),
    },
    limits: {
      ...(config.limits?.cpu && { cpu: k8s.Quantity.fromString(config.limits.cpu) }),
      ...(config.limits?.memory && { memory: k8s.Quantity.fromString(config.limits.memory) }),
    },
  };
}

// =============================================================================
// Configuration Generators
// =============================================================================

/**
 * Generate Mimir monolithic mode configuration
 *
 * @param retentionHours - Retention period in hours (default: 720h = 30 days)
 */
export function generateMimirConfig(retentionHours: string = LGTM_RETENTION_HOURS): string {
  const config = {
    multitenancy_enabled: false,
    server: {
      http_listen_port: 9009,
      grpc_listen_port: 9095,
      log_level: 'warn',
    },
    activity_tracker: {
      filepath: '/data/activity.log',
    },
    blocks_storage: {
      backend: 'filesystem',
      bucket_store: {
        sync_dir: '/data/bucket-sync',
      },
      filesystem: {
        dir: '/data/blocks',
      },
      tsdb: {
        dir: '/data/tsdb',
      },
    },
    compactor: {
      data_dir: '/data/compactor',
      sharding_ring: {
        kvstore: {
          store: 'memberlist',
        },
      },
    },
    distributor: {
      ring: {
        instance_addr: '127.0.0.1',
        kvstore: {
          store: 'memberlist',
        },
      },
    },
    ingester: {
      ring: {
        instance_addr: '127.0.0.1',
        kvstore: {
          store: 'memberlist',
        },
        replication_factor: 1,
      },
    },
    ruler: {
      rule_path: '/data/rules-temp',
    },
    ruler_storage: {
      backend: 'filesystem',
      filesystem: {
        dir: '/data/rules',
      },
    },
    store_gateway: {
      sharding_ring: {
        replication_factor: 1,
      },
    },
    limits: {
      compactor_blocks_retention_period: retentionHours,
    },
  };

  return toYamlString(config);
}

/**
 * Generate Loki single-binary mode configuration
 *
 * @param retentionHours - Retention period in hours (default: 720h = 30 days)
 */
export function generateLokiConfig(retentionHours: string = LGTM_RETENTION_HOURS): string {
  const config = {
    auth_enabled: false,
    server: {
      http_listen_port: 3100,
      grpc_listen_port: 9096,
      log_level: 'warn',
    },
    common: {
      path_prefix: '/data/loki',
      storage: {
        filesystem: {
          chunks_directory: '/data/loki/chunks',
          rules_directory: '/data/loki/rules',
        },
      },
      replication_factor: 1,
      ring: {
        instance_addr: '127.0.0.1',
        kvstore: {
          store: 'inmemory',
        },
      },
    },
    schema_config: {
      configs: [
        {
          from: '2024-01-01',
          store: 'tsdb',
          object_store: 'filesystem',
          schema: 'v13',
          index: {
            prefix: 'index_',
            period: '24h',
          },
        },
      ],
    },
    ingester: {
      chunk_encoding: 'snappy',
      wal: {
        dir: '/data/loki/wal',
      },
    },
    querier: {
      max_concurrent: 4,
    },
    limits_config: {
      retention_period: retentionHours,
      allow_structured_metadata: true,
      volume_enabled: true,
    },
    compactor: {
      working_directory: '/data/loki/compactor',
      retention_enabled: true,
      delete_request_store: 'filesystem',
    },
  };

  return toYamlString(config);
}

/**
 * Generate Tempo monolithic mode configuration
 *
 * @param mimirEndpoint - Mimir remote write endpoint for metrics_generator
 * @param retentionHours - Retention period in hours (default: 720h = 30 days)
 */
export function generateTempoConfig(
  mimirEndpoint: string = 'http://mimir:9009/api/v1/push',
  retentionHours: string = LGTM_RETENTION_HOURS
): string {
  const config = {
    server: {
      http_listen_port: 3200,
      grpc_listen_port: 9095,
      log_level: 'warn',
    },
    distributor: {
      receivers: {
        otlp: {
          protocols: {
            grpc: {
              endpoint: '0.0.0.0:4317',
            },
            http: {
              endpoint: '0.0.0.0:4318',
            },
          },
        },
      },
    },
    ingester: {
      trace_idle_period: '10s',
      max_block_bytes: 1_000_000,
      max_block_duration: '5m',
    },
    compactor: {
      compaction: {
        block_retention: retentionHours,
      },
    },
    storage: {
      trace: {
        backend: 'local',
        local: {
          path: '/data/tempo/traces',
        },
        wal: {
          path: '/data/tempo/wal',
        },
      },
    },
    querier: {
      frontend_worker: {
        frontend_address: '127.0.0.1:9095',
      },
    },
    metrics_generator: {
      registry: {
        external_labels: {
          source: 'tempo',
        },
      },
      storage: {
        path: '/data/tempo/generator/wal',
        remote_write: [
          {
            url: mimirEndpoint,
            send_exemplars: true,
          },
        ],
      },
    },
  };

  return toYamlString(config);
}

/**
 * Generate OTEL Collector configuration for LGTM stack routing
 *
 * @param mimirEndpoint - Mimir Prometheus remote write endpoint
 * @param lokiEndpoint - Loki push endpoint
 * @param tempoEndpoint - Tempo OTLP gRPC endpoint
 * @param langfuseEndpoint - Langfuse OTLP HTTP endpoint
 */
export function generateOtelCollectorConfig(
  mimirEndpoint: string = 'http://mimir:9009/api/v1/push',
  lokiEndpoint: string = 'http://loki:3100/loki/api/v1/push',
  tempoEndpoint: string = 'tempo:4317',
  langfuseEndpoint?: string
): object {
  const exporters: any = {
    prometheusremotewrite: {
      endpoint: mimirEndpoint,
      resource_to_telemetry_conversion: {
        enabled: true,
      },
      external_labels: {
        cluster: 'homelab',
        source: 'otel-collector',
      },
    },
    loki: {
      endpoint: lokiEndpoint,
      default_labels_enabled: {
        exporter: false,
        job: true,
        instance: true,
        level: true,
      },
    },
    'otlp/tempo': {
      endpoint: tempoEndpoint,
      tls: {
        insecure: true,
      },
    },
  };

  const traceExporters = ['otlp/tempo'];

  // Add Langfuse exporter if endpoint is provided
  if (langfuseEndpoint) {
    exporters['otlphttp/langfuse'] = {
      endpoint: langfuseEndpoint,
      // Langfuse expects traces at /api/public/otel
      // If endpoint already includes it, don't append
      headers: {
        // Authorization header will be injected from environment variable
        // LANGFUSE_AUTH should be "Basic <base64(public_key:secret_key)>"
        Authorization: '${env:LANGFUSE_AUTH}',
      },
    };
    traceExporters.push('otlphttp/langfuse');
  }

  return {
    receivers: {
      otlp: {
        protocols: {
          grpc: {
            endpoint: '0.0.0.0:4317',
          },
          http: {
            endpoint: '0.0.0.0:4318',
          },
        },
      },
    },
    processors: {
      memory_limiter: {
        check_interval: '1s',
        limit_mib: 512,
        spike_limit_mib: 128,
      },
      batch: {
        timeout: '5s',
        send_batch_size: 1000,
        send_batch_max_size: 1500,
      },
      resource: {
        attributes: [
          {
            key: 'service.instance.id',
            from_attribute: 'host.name',
            action: 'insert',
          },
          {
            key: 'deployment.environment',
            value: 'homelab',
            action: 'insert',
          },
        ],
      },
    },
    exporters,
    extensions: {
      health_check: {
        endpoint: '0.0.0.0:13133',
      },
      pprof: {
        endpoint: '0.0.0.0:1777',
      },
      zpages: {
        endpoint: '0.0.0.0:55679',
      },
    },
    service: {
      extensions: ['health_check', 'pprof', 'zpages'],
      pipelines: {
        metrics: {
          receivers: ['otlp'],
          processors: ['memory_limiter', 'batch', 'resource'],
          exporters: ['prometheusremotewrite'],
        },
        logs: {
          receivers: ['otlp'],
          processors: ['memory_limiter', 'batch', 'resource'],
          exporters: ['loki'],
        },
        traces: {
          receivers: ['otlp'],
          processors: ['memory_limiter', 'batch', 'resource'],
          exporters: traceExporters,
        },
      },
      telemetry: {
        logs: {
          level: 'warn',
        },
        metrics: {
          address: '0.0.0.0:8888',
          level: 'basic',
        },
      },
    },
  };
}

/**
 * Generate Grafana datasources provisioning configuration
 *
 * @param mimirUrl - Mimir Prometheus API URL
 * @param lokiUrl - Loki API URL
 * @param tempoUrl - Tempo API URL
 * @param pyroscopeUrl - Pyroscope API URL
 */
export function generateGrafanaDatasources(
  mimirUrl: string = 'http://mimir:9009/prometheus',
  lokiUrl: string = 'http://loki:3100',
  tempoUrl: string = 'http://tempo:3200',
  pyroscopeUrl: string = 'http://pyroscope:4040'
): object {
  return {
    apiVersion: 1,
    deleteDatasources: [
      { name: 'ClickHouse', orgId: 1 },
      { name: 'ClickHouse-OTEL', orgId: 1 },
    ],
    datasources: [
      // =======================================================================
      // MIMIR - Metrics Backend with Exemplar Support (Metrics → Traces)
      // =======================================================================
      {
        name: 'Mimir',
        type: 'prometheus',
        access: 'proxy',
        url: mimirUrl,
        isDefault: true,
        uid: 'mimir',
        jsonData: {
          httpMethod: 'POST',
          prometheusType: 'Mimir',
          prometheusVersion: '2.14.0',
          timeInterval: '15s',
          // METRICS → TRACES: Click exemplars to jump to trace
          exemplarTraceIdDestinations: [
            {
              name: 'trace_id',
              datasourceUid: 'tempo',
              urlDisplayLabel: 'View trace in Tempo',
            },
          ],
        },
      },
      // =======================================================================
      // LOKI - Logs Backend with Derived Fields (Logs → Traces)
      // =======================================================================
      {
        name: 'Loki',
        type: 'loki',
        access: 'proxy',
        url: lokiUrl,
        uid: 'loki',
        jsonData: {
          maxLines: 1000,
          // LOGS → TRACES: Extract trace_id from logs and link to Tempo
          derivedFields: [
            // Standard OTEL format: trace_id=abc123 or trace_id: abc123
            {
              datasourceUid: 'tempo',
              matcherRegex: '(?:trace_id|traceId|TraceId|traceid)[=:]\\s*"?([a-fA-F0-9]{32})"?',
              matcherType: 'regex',
              name: 'TraceID',
              url: '${__value.raw}',
            },
            // JSON format: "trace_id": "abc123"
            {
              datasourceUid: 'tempo',
              matcherRegex: '"trace_id"\\s*:\\s*"([a-fA-F0-9]{32})"',
              matcherType: 'regex',
              name: 'TraceID (JSON)',
              url: '${__value.raw}',
            },
            // W3C Trace Context format: 00-abc123...-def456-01
            {
              datasourceUid: 'tempo',
              matcherRegex: '(?:traceparent)[=:]\\s*"?00-([a-fA-F0-9]{32})-[a-fA-F0-9]{16}-[0-9]{2}"?',
              matcherType: 'regex',
              name: 'TraceID (W3C)',
              url: '${__value.raw}',
            },
            // Span ID extraction for span-level correlation
            {
              datasourceUid: 'tempo',
              matcherRegex: '(?:span_id|spanId|SpanId)[=:]\\s*"?([a-fA-F0-9]{16})"?',
              matcherType: 'regex',
              name: 'SpanID',
              url: '${__value.raw}',
            },
          ],
        },
      },
      // =======================================================================
      // TEMPO - Tracing Backend with Full Correlation Support
      // =======================================================================
      {
        name: 'Tempo',
        type: 'tempo',
        access: 'proxy',
        url: tempoUrl,
        uid: 'tempo',
        jsonData: {
          httpMethod: 'GET',
          // Service dependency graph visualization
          serviceMap: {
            datasourceUid: 'mimir',
          },
          // Span hierarchy visualization
          nodeGraph: {
            enabled: true,
          },
          // Search interface
          search: {
            hide: false,
          },
          // Search logs by trace ID
          lokiSearch: {
            datasourceUid: 'loki',
          },
          // Span links between traces
          spanBar: {
            type: 'Tag',
            tag: 'http.status_code',
          },
          // =====================================================================
          // TRACES → LOGS: Click span to see related logs
          // =====================================================================
          tracesToLogs: {
            datasourceUid: 'loki',
            spanStartTimeShift: '-1h',
            spanEndTimeShift: '1h',
            filterByTraceID: true,
            filterBySpanID: true,
            mapTagNamesEnabled: true,
            // Map OTEL span attributes to Loki labels (dots → underscores)
            mappedTags: [
              { key: 'service.name', value: 'service_name' },
              { key: 'host.name', value: 'host' },
              { key: 'k8s.pod.name', value: 'k8s_pod_name' },
              { key: 'k8s.namespace.name', value: 'k8s_namespace_name' },
              { key: 'container.id', value: 'container_id' },
              { key: 'deployment.environment', value: 'deployment_environment' },
            ],
          },
          // =====================================================================
          // TRACES → METRICS: Click span to see related metrics
          // =====================================================================
          tracesToMetrics: {
            datasourceUid: 'mimir',
            spanStartTimeShift: '-1h',
            spanEndTimeShift: '1h',
            // Map span attributes to metric label dimensions
            tags: [
              { key: 'service.name', value: 'service' },
              { key: 'host.name', value: 'instance' },
              { key: 'http.method', value: 'http_method' },
              { key: 'http.status_code', value: 'http_status_code' },
              { key: 'k8s.namespace.name', value: 'namespace' },
            ],
            // Pre-configured metric queries accessible from trace view
            queries: [
              {
                name: 'Request rate',
                query: 'sum(rate(traces_spanmetrics_calls_total{$__tags}[5m]))',
              },
              {
                name: 'Error rate',
                query: 'sum(rate(traces_spanmetrics_calls_total{$__tags,status_code="STATUS_CODE_ERROR"}[5m]))',
              },
              {
                name: 'Duration (p50)',
                query: 'histogram_quantile(0.50, sum(rate(traces_spanmetrics_latency_bucket{$__tags}[5m])) by (le))',
              },
              {
                name: 'Duration (p95)',
                query: 'histogram_quantile(0.95, sum(rate(traces_spanmetrics_latency_bucket{$__tags}[5m])) by (le))',
              },
              {
                name: 'Duration (p99)',
                query: 'histogram_quantile(0.99, sum(rate(traces_spanmetrics_latency_bucket{$__tags}[5m])) by (le))',
              },
              {
                name: 'Throughput (req/s)',
                query: 'sum(rate(traces_spanmetrics_calls_total{$__tags}[5m]))',
              },
              {
                name: 'Error ratio',
                query: 'sum(rate(traces_spanmetrics_calls_total{$__tags,status_code="STATUS_CODE_ERROR"}[5m])) / sum(rate(traces_spanmetrics_calls_total{$__tags}[5m]))',
              },
              {
                name: 'Span size distribution',
                query: 'sum(rate(traces_spanmetrics_size_total{$__tags}[5m])) by (span_name)',
              },
            ],
          },
          // =====================================================================
          // TRACES → PROFILES: Click span to see CPU/memory profiles
          // =====================================================================
          tracesToProfiles: {
            datasourceUid: 'pyroscope',
            // Multiple profile types for comprehensive analysis
            profileTypeId: 'process_cpu:cpu:nanoseconds:cpu:nanoseconds',
            customQuery: true,
            query: '{service_name="${__span.tags["service.name"]}"}',
            // Additional profile types available via dropdown
            // - process_cpu:cpu:nanoseconds:cpu:nanoseconds (CPU time)
            // - memory:alloc_objects:count:space:bytes (Allocations)
            // - memory:inuse_objects:count:space:bytes (Heap)
            // - goroutine:goroutine:count:goroutine:count (Goroutines)
            // - block:contentions:count:delay:nanoseconds (Block profile)
            // - mutex:contentions:count:delay:nanoseconds (Mutex profile)
          },
        },
      },
      // =======================================================================
      // PYROSCOPE - Continuous Profiling Backend
      // =======================================================================
      {
        name: 'Pyroscope',
        type: 'grafana-pyroscope-datasource',
        access: 'proxy',
        url: pyroscopeUrl,
        uid: 'pyroscope',
        jsonData: {
          backendType: 'pyroscope',
        },
      },
    ],
  };
}

// =============================================================================
// Dashboard Definitions
// =============================================================================

/**
 * Community dashboard IDs from Grafana.com
 * These are downloaded at runtime via init container
 */
export const GRAFANA_COMMUNITY_DASHBOARDS = {
  nodeExporter: { id: 1860, revision: 37, name: 'Node Exporter Full' },
  beylaRed: { id: 19923, revision: 1, name: 'Beyla RED Metrics' },
  otelCollector: { id: 15983, revision: 1, name: 'OpenTelemetry Collector' },
} as const;

/**
 * Generate the GenAI CLI Monitor dashboard JSON
 * Tracks LLM token usage, latency, and active sessions
 */
export function generateGenAiDashboard(): object {
  return {
    title: 'GenAI CLI Monitor',
    uid: 'genai-monitor',
    editable: true,
    tags: ['genai', 'llm', 'claude', 'openai'],
    time: { from: 'now-1h', to: 'now' },
    refresh: '30s',
    panels: [
      {
        id: 1,
        title: 'Tokens Per Second (5m)',
        type: 'timeseries',
        gridPos: { h: 8, w: 12, x: 0, y: 0 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(rate(gen_ai_client_token_usage_total[5m])) by (tool, type)',
            legendFormat: '{{tool}} - {{type}}',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            unit: 'tokens/s',
            custom: { lineWidth: 2, fillOpacity: 10 },
          },
        },
      },
      {
        id: 2,
        title: 'LLM API Latency (P95)',
        type: 'timeseries',
        gridPos: { h: 8, w: 12, x: 12, y: 0 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'histogram_quantile(0.95, sum by (le, tool) (rate(gen_ai_client_operation_duration_seconds_bucket[5m])))',
            legendFormat: '{{tool}} P95',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            unit: 's',
            custom: { lineWidth: 2, fillOpacity: 10 },
          },
        },
      },
      {
        id: 3,
        title: 'Active Sessions',
        type: 'stat',
        gridPos: { h: 4, w: 6, x: 0, y: 8 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'count(count by (session_id, tool) (rate(gen_ai_client_token_usage_total[5m]) > 0))',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            thresholds: {
              mode: 'absolute',
              steps: [
                { color: 'green', value: null },
                { color: 'yellow', value: 5 },
                { color: 'red', value: 10 },
              ],
            },
          },
        },
      },
      {
        id: 4,
        title: 'Total Tokens (24h)',
        type: 'stat',
        gridPos: { h: 4, w: 6, x: 6, y: 8 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(increase(gen_ai_client_token_usage_total[24h]))',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            unit: 'short',
            thresholds: {
              mode: 'absolute',
              steps: [
                { color: 'green', value: null },
                { color: 'yellow', value: 100000 },
                { color: 'red', value: 500000 },
              ],
            },
          },
        },
      },
      {
        id: 5,
        title: 'Token Usage by Model',
        type: 'piechart',
        gridPos: { h: 8, w: 6, x: 0, y: 12 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum by (model) (increase(gen_ai_client_token_usage_total[24h]))',
            legendFormat: '{{model}}',
            refId: 'A',
          },
        ],
      },
      {
        id: 6,
        title: 'Request Rate by Tool',
        type: 'timeseries',
        gridPos: { h: 8, w: 6, x: 6, y: 12 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(rate(gen_ai_client_operation_duration_seconds_count[5m])) by (tool)',
            legendFormat: '{{tool}}',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            unit: 'reqps',
            custom: { lineWidth: 2, fillOpacity: 10 },
          },
        },
      },
      {
        id: 7,
        title: 'Error Rate',
        type: 'timeseries',
        gridPos: { h: 8, w: 12, x: 12, y: 8 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(rate(gen_ai_client_operation_duration_seconds_count{status="error"}[5m])) by (tool)',
            legendFormat: '{{tool}} errors',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            unit: 'reqps',
            custom: { lineWidth: 2, fillOpacity: 10 },
            color: { mode: 'palette-classic' },
          },
        },
      },
    ],
  };
}

/**
 * Generate LGTM Stack Overview dashboard
 * Shows health and performance of Mimir, Loki, Tempo, Pyroscope
 */
export function generateLgtmOverviewDashboard(): object {
  return {
    title: 'LGTM Stack Overview',
    uid: 'lgtm-overview',
    editable: true,
    tags: ['lgtm', 'observability', 'infrastructure'],
    time: { from: 'now-1h', to: 'now' },
    refresh: '30s',
    panels: [
      {
        id: 1,
        title: 'Mimir - Ingestion Rate',
        type: 'timeseries',
        gridPos: { h: 6, w: 6, x: 0, y: 0 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(rate(cortex_ingester_ingested_samples_total[5m]))',
            legendFormat: 'samples/s',
            refId: 'A',
          },
        ],
      },
      {
        id: 2,
        title: 'Loki - Log Ingestion Rate',
        type: 'timeseries',
        gridPos: { h: 6, w: 6, x: 6, y: 0 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(rate(loki_distributor_lines_received_total[5m]))',
            legendFormat: 'lines/s',
            refId: 'A',
          },
        ],
      },
      {
        id: 3,
        title: 'Tempo - Traces Received',
        type: 'timeseries',
        gridPos: { h: 6, w: 6, x: 12, y: 0 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(rate(tempo_distributor_spans_received_total[5m]))',
            legendFormat: 'spans/s',
            refId: 'A',
          },
        ],
      },
      {
        id: 4,
        title: 'OTEL Collector - Throughput',
        type: 'timeseries',
        gridPos: { h: 6, w: 6, x: 18, y: 0 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(rate(otelcol_receiver_accepted_metric_points[5m]))',
            legendFormat: 'metrics',
            refId: 'A',
          },
          {
            expr: 'sum(rate(otelcol_receiver_accepted_log_records[5m]))',
            legendFormat: 'logs',
            refId: 'B',
          },
          {
            expr: 'sum(rate(otelcol_receiver_accepted_spans[5m]))',
            legendFormat: 'traces',
            refId: 'C',
          },
        ],
      },
      {
        id: 5,
        title: 'Storage Used',
        type: 'bargauge',
        gridPos: { h: 6, w: 12, x: 0, y: 6 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(kubelet_volume_stats_used_bytes{namespace="observability"}) by (persistentvolumeclaim)',
            legendFormat: '{{persistentvolumeclaim}}',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            unit: 'bytes',
            max: 21474836480, // 20Gi
            thresholds: {
              mode: 'percentage',
              steps: [
                { color: 'green', value: null },
                { color: 'yellow', value: 70 },
                { color: 'red', value: 90 },
              ],
            },
          },
        },
      },
      {
        id: 6,
        title: 'Component Memory Usage',
        type: 'timeseries',
        gridPos: { h: 6, w: 12, x: 12, y: 6 },
        datasource: { type: 'prometheus', uid: 'mimir' },
        targets: [
          {
            expr: 'sum(container_memory_working_set_bytes{namespace="observability", container!=""}) by (pod)',
            legendFormat: '{{pod}}',
            refId: 'A',
          },
        ],
        fieldConfig: {
          defaults: {
            unit: 'bytes',
          },
        },
      },
    ],
  };
}

/**
 * Generate all custom dashboards as a map of filename to JSON content
 */
export function generateDashboardConfigs(): Record<string, string> {
  return {
    'genai-monitor.json': JSON.stringify(generateGenAiDashboard(), null, 2),
    'lgtm-overview.json': JSON.stringify(generateLgtmOverviewDashboard(), null, 2),
  };
}

// =============================================================================
// YAML Helpers
// =============================================================================

/**
 * Convert a JavaScript object to a YAML-formatted string.
 * This is a simple implementation that handles basic types.
 */
function toYamlString(obj: object, indent: number = 0): string {
  const spaces = '  '.repeat(indent);
  let result = '';

  for (const [key, value] of Object.entries(obj)) {
    if (value === null || value === undefined) {
      continue;
    }

    if (Array.isArray(value)) {
      if (value.length === 0) {
        result += `${spaces}${key}: []\n`;
      } else if (typeof value[0] === 'object') {
        result += `${spaces}${key}:\n`;
        for (const item of value) {
          const itemStr = toYamlString(item, 0).trim();
          const lines = itemStr.split('\n');
          result += `${spaces}  - ${lines[0]}\n`;
          for (let i = 1; i < lines.length; i++) {
            result += `${spaces}    ${lines[i]}\n`;
          }
        }
      } else {
        result += `${spaces}${key}:\n`;
        for (const item of value) {
          result += `${spaces}  - ${formatValue(item)}\n`;
        }
      }
    } else if (typeof value === 'object') {
      result += `${spaces}${key}:\n`;
      result += toYamlString(value, indent + 1);
    } else {
      result += `${spaces}${key}: ${formatValue(value)}\n`;
    }
  }

  return result;
}

/**
 * Format a primitive value for YAML output
 */
function formatValue(value: unknown): string {
  if (typeof value === 'string') {
    // Quote strings that might be interpreted as other types
    if (
      value === '' ||
      value === 'true' ||
      value === 'false' ||
      value === 'null' ||
      /^\d+$/.test(value) ||
      /^[\d.]+$/.test(value) ||
      value.includes(':') ||
      value.includes('#') ||
      value.includes("'") ||
      value.includes('"') ||
      value.includes('\n')
    ) {
      return `"${value.replace(/"/g, '\\"')}"`;
    }
    return value;
  }
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  if (typeof value === 'number') {
    return String(value);
  }
  return String(value);
}
