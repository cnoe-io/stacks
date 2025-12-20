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
 */
export function generateOtelCollectorConfig(
  mimirEndpoint: string = 'http://mimir:9009/api/v1/push',
  lokiEndpoint: string = 'http://loki:3100/loki/api/v1/push',
  tempoEndpoint: string = 'tempo:4317'
): object {
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
    exporters: {
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
    },
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
          exporters: ['otlp/tempo'],
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
          exemplarTraceIdDestinations: [
            {
              name: 'trace_id',
              datasourceUid: 'tempo',
              urlDisplayLabel: 'View trace',
            },
          ],
        },
      },
      {
        name: 'Loki',
        type: 'loki',
        access: 'proxy',
        url: lokiUrl,
        uid: 'loki',
        jsonData: {
          maxLines: 1000,
          derivedFields: [
            {
              datasourceUid: 'tempo',
              matcherRegex: '(?:trace_id|traceId|TraceId)[=:]?\\s*"?([a-fA-F0-9]{32})"?',
              matcherType: 'regex',
              name: 'TraceID',
              url: '${__value.raw}',
            },
            {
              datasourceUid: 'tempo',
              matcherRegex: '"trace_id"\\s*:\\s*"([a-fA-F0-9]{32})"',
              matcherType: 'regex',
              name: 'TraceID (JSON)',
              url: '${__value.raw}',
            },
          ],
        },
      },
      {
        name: 'Tempo',
        type: 'tempo',
        access: 'proxy',
        url: tempoUrl,
        uid: 'tempo',
        jsonData: {
          httpMethod: 'GET',
          serviceMap: {
            datasourceUid: 'mimir',
          },
          nodeGraph: {
            enabled: true,
          },
          search: {
            hide: false,
          },
          lokiSearch: {
            datasourceUid: 'loki',
          },
          tracesToLogs: {
            datasourceUid: 'loki',
            spanStartTimeShift: '-1h',
            spanEndTimeShift: '1h',
            filterByTraceID: true,
            filterBySpanID: true,
            mapTagNamesEnabled: true,
            mappedTags: [
              { key: 'service.name', value: 'service_name' },
              { key: 'host.name', value: 'host' },
            ],
          },
          tracesToMetrics: {
            datasourceUid: 'mimir',
            spanStartTimeShift: '-1h',
            spanEndTimeShift: '1h',
            tags: [
              { key: 'service.name', value: 'service' },
              { key: 'host.name', value: 'instance' },
            ],
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
                name: 'Duration (p95)',
                query: 'histogram_quantile(0.95, sum(rate(traces_spanmetrics_latency_bucket{$__tags}[5m])) by (le))',
              },
            ],
          },
          tracesToProfiles: {
            datasourceUid: 'pyroscope',
            profileTypeId: 'process_cpu:cpu:nanoseconds:cpu:nanoseconds',
            customQuery: true,
            query: '{service_name="${__span.tags["service.name"]}"}',
          },
        },
      },
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
