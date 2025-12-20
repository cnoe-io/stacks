# Research: LGTM Stack Configuration

**Feature**: 111-configure-k8s-observability
**Date**: 2025-12-19
**Status**: Complete

## Overview

This document captures research findings for deploying the Grafana LGTM stack (Loki, Grafana, Tempo, Mimir) plus Pyroscope on a single-node K3s cluster. All components use monolithic/single-binary deployment mode for simplicity.

---

## 1. Grafana Mimir (Metrics)

### Decision: Monolithic Mode with Filesystem Storage

**Rationale**: Single-node K3s cluster doesn't need distributed mode. Monolithic mode runs all components in a single process, reducing complexity and resource usage.

**Alternatives Considered**:
- Distributed mode with S3: Overkill for homelab, requires additional MinIO/S3 setup
- Prometheus: No long-term storage, Mimir provides Prometheus-compatible API with retention

### Configuration

```yaml
# Mimir monolithic configuration for single-node K3s
multitenancy_enabled: false

server:
  http_listen_port: 9009
  grpc_listen_port: 9095
  log_level: warn

blocks_storage:
  backend: filesystem
  bucket_store:
    sync_dir: /data/tsdb-sync
  filesystem:
    dir: /data/tsdb
  tsdb:
    dir: /data/tsdb

compactor:
  data_dir: /data/compactor
  sharding_ring:
    kvstore:
      store: memberlist

distributor:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: memberlist

ingester:
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: memberlist
    replication_factor: 1

ruler_storage:
  backend: filesystem
  filesystem:
    dir: /data/rules

store_gateway:
  sharding_ring:
    replication_factor: 1

limits:
  # 30-day retention
  compactor_blocks_retention_period: 720h
```

### Key Findings

- **Port**: 9009 (HTTP), 9095 (gRPC)
- **Storage**: 20Gi PVC at `/data`
- **Remote Write Endpoint**: `http://mimir:9009/api/v1/push` (for OTEL Collector)
- **Query Endpoint**: `http://mimir:9009/prometheus` (for Grafana Prometheus datasource)
- **Image**: `grafana/mimir:2.14.0`

---

## 2. Grafana Loki (Logs)

### Decision: Single Binary Mode with Filesystem Storage

**Rationale**: SingleBinary deployment mode is ideal for small-scale deployments with < 100GB/day log volume.

**Alternatives Considered**:
- SimpleScalable mode: Requires MinIO, adds complexity
- Distributed mode: Overkill for homelab workload

### Configuration

```yaml
# Loki single binary configuration
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096
  log_level: warn

common:
  path_prefix: /data/loki
  storage:
    filesystem:
      chunks_directory: /data/loki/chunks
      rules_directory: /data/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ingester:
  chunk_encoding: snappy
  wal:
    dir: /data/loki/wal

querier:
  max_concurrent: 4

limits_config:
  # 30-day retention
  retention_period: 720h
  allow_structured_metadata: true
  volume_enabled: true

compactor:
  working_directory: /data/loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
```

### Key Findings

- **Port**: 3100 (HTTP), 9096 (gRPC)
- **Storage**: 20Gi PVC at `/data/loki`
- **Push Endpoint**: `http://loki:3100/loki/api/v1/push` (for OTEL Collector loki exporter)
- **Query Endpoint**: `http://loki:3100` (for Grafana Loki datasource)
- **Image**: `grafana/loki:3.3.0`

---

## 3. Grafana Tempo (Traces)

### Decision: Monolithic Mode with Local Filesystem

**Rationale**: Single-binary deployment suitable for development and small production workloads.

**Alternatives Considered**:
- Scalable mode with S3: Requires object storage, adds complexity
- Jaeger: Already have it for Langfuse, but Tempo integrates better with LGTM stack

### Configuration

```yaml
# Tempo monolithic configuration
server:
  http_listen_port: 3200
  grpc_listen_port: 9095
  log_level: warn

distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

ingester:
  trace_idle_period: 10s
  max_block_bytes: 1_000_000
  max_block_duration: 5m

compactor:
  compaction:
    block_retention: 720h  # 30 days

storage:
  trace:
    backend: local
    local:
      path: /data/tempo/traces
    wal:
      path: /data/tempo/wal

querier:
  frontend_worker:
    frontend_address: 127.0.0.1:9095

metrics_generator:
  registry:
    external_labels:
      source: tempo
  storage:
    path: /data/tempo/generator/wal
    remote_write:
      - url: http://mimir:9009/api/v1/push
        send_exemplars: true
```

### Key Findings

- **Port**: 3200 (HTTP/API), 4317 (OTLP gRPC), 4318 (OTLP HTTP)
- **Storage**: 20Gi PVC at `/data/tempo`
- **OTLP Endpoint**: `tempo:4317` (gRPC) or `tempo:4318` (HTTP)
- **Query Endpoint**: `http://tempo:3200` (for Grafana Tempo datasource)
- **Image**: `grafana/tempo:2.6.1`
- **Note**: Tempo can receive OTLP directly, but we route through OTEL Collector for unified ingestion

---

## 4. Grafana Pyroscope (Profiles)

### Decision: Standalone Deployment

**Rationale**: Single instance sufficient for homelab profiling needs.

**Alternatives Considered**:
- Parca: Less integrated with Grafana ecosystem
- No profiling: Loses valuable debugging capability

### Configuration

```yaml
# Pyroscope configuration
storage:
  backend: filesystem
  filesystem:
    data_path: /data/pyroscope

server:
  http_listen_port: 4040

# 30-day retention
limits:
  max_query_lookback: 720h
```

### Key Findings

- **Port**: 4040 (HTTP)
- **Storage**: 10Gi PVC at `/data/pyroscope`
- **Push Endpoint**: `http://pyroscope:4040` (for SDK-based instrumentation)
- **Query Endpoint**: `http://pyroscope:4040` (for Grafana Pyroscope datasource)
- **Image**: `grafana/pyroscope:1.10.0`

---

## 5. OpenTelemetry Collector (Ingestion Gateway)

### Decision: OTEL Collector Contrib with Multi-Backend Routing

**Rationale**: Unified ingestion point for all telemetry. Routes metrics to Mimir, logs to Loki, traces to Tempo.

**Alternatives Considered**:
- Grafana Alloy: More complex configuration language (River)
- Direct OTLP to backends: Loses unified processing and batching

### Configuration

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 5s
    send_batch_size: 1000
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  resource:
    attributes:
      - key: service.instance.id
        from_attribute: host.name
        action: insert

exporters:
  # Metrics to Mimir via Prometheus Remote Write
  prometheusremotewrite:
    endpoint: http://mimir:9009/api/v1/push
    resource_to_telemetry_conversion:
      enabled: true

  # Logs to Loki
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    default_labels_enabled:
      exporter: false
      job: true

  # Traces to Tempo via OTLP
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

  # Debug logging (optional, disable in production)
  debug:
    verbosity: basic

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [loki]
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [otlp/tempo]

  telemetry:
    logs:
      level: warn
    metrics:
      address: 0.0.0.0:8888
```

### Key Findings

- **Ports**: 4317 (OTLP gRPC), 4318 (OTLP HTTP), 8888 (internal metrics)
- **Storage**: None (stateless)
- **Image**: `otel/opentelemetry-collector-contrib:0.115.0`
- **Exporters Used**:
  - `prometheusremotewrite`: Metrics to Mimir
  - `loki`: Logs to Loki
  - `otlp`: Traces to Tempo

---

## 6. Grafana (Visualization)

### Decision: Preconfigured with LGTM Datasources

**Rationale**: Single pane of glass for all observability data with cross-signal correlation.

### Datasource Configuration

```yaml
apiVersion: 1

datasources:
  - name: Mimir
    type: prometheus
    access: proxy
    url: http://mimir:9009/prometheus
    isDefault: true
    jsonData:
      httpMethod: POST
      prometheusType: Mimir
      prometheusVersion: 2.14.0

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: "trace_id=(\\w+)"
          name: TraceID
          url: "$${__value.raw}"

  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    uid: tempo
    jsonData:
      tracesToLogs:
        datasourceUid: loki
        filterByTraceID: true
        filterBySpanID: true
      tracesToMetrics:
        datasourceUid: mimir
      nodeGraph:
        enabled: true
      lokiSearch:
        datasourceUid: loki

  - name: Pyroscope
    type: grafana-pyroscope-datasource
    access: proxy
    url: http://pyroscope:4040
```

### Key Findings

- **Port**: 3000 (HTTP)
- **Storage**: None (stateless, provisioning via ConfigMaps)
- **Image**: `grafana/grafana:11.3.0`
- **Correlation Features**:
  - Trace-to-logs: Click trace → see correlated logs
  - Logs-to-traces: Click trace_id in logs → jump to trace
  - Trace-to-metrics: See related metrics for service

---

## 7. Tailscale Service Exposure

### Decision: Reuse TailscaleServeChart Pattern

**Rationale**: Established pattern in codebase, provides stable URLs via Tailscale Services.

### Services to Expose

| Service | Tailscale Name | Backend | Port |
|---------|----------------|---------|------|
| OTEL Collector | otel-collector | otel-collector.observability.svc.cluster.local | 4318 |
| Grafana | grafana | grafana.observability.svc.cluster.local | 3000 |
| Mimir | mimir | mimir.observability.svc.cluster.local | 9009 |

**Note**: Loki, Tempo, and Pyroscope don't need direct Tailscale exposure - they're accessed via Grafana or internally by OTEL Collector.

---

## 8. Resource Requirements

### Per-Component Resources

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| OTEL Collector | 100m | 500m | 256Mi | 512Mi | - |
| Mimir | 100m | 1000m | 512Mi | 2Gi | 20Gi |
| Loki | 100m | 500m | 256Mi | 1Gi | 20Gi |
| Tempo | 100m | 500m | 256Mi | 1Gi | 20Gi |
| Pyroscope | 50m | 250m | 128Mi | 512Mi | 10Gi |
| Grafana | 50m | 250m | 128Mi | 256Mi | - |

### Total Resources

- **CPU**: 500m request, 3000m limit
- **Memory**: 1.5Gi request, 5.5Gi limit
- **Storage**: 70Gi persistent storage

This fits within the 8GB RAM budget specified in the spec.

---

## 9. Image Versions

| Component | Image | Version |
|-----------|-------|---------|
| OTEL Collector | otel/opentelemetry-collector-contrib | 0.115.0 |
| Mimir | grafana/mimir | 2.14.0 |
| Loki | grafana/loki | 3.3.0 |
| Tempo | grafana/tempo | 2.6.1 |
| Pyroscope | grafana/pyroscope | 1.10.0 |
| Grafana | grafana/grafana | 11.3.0 |

---

## 10. Sync Wave Strategy

| Wave | Components |
|------|------------|
| -70 | Namespace (existing observability-namespace-chart) |
| -65 | PVCs for storage (Mimir, Loki, Tempo, Pyroscope) |
| -60 | Backend services (Mimir, Loki, Tempo, Pyroscope) |
| -55 | OTEL Collector (depends on backends) |
| -50 | Grafana (depends on backends for datasources) |
| -45 | Tailscale serve charts (depends on services) |

---

## References

- [Grafana Mimir Docs](https://grafana.com/docs/mimir/latest/)
- [Grafana Loki Docs](https://grafana.com/docs/loki/latest/)
- [Grafana Tempo Docs](https://grafana.com/docs/tempo/latest/)
- [Grafana Pyroscope Docs](https://grafana.com/docs/pyroscope/latest/)
- [OpenTelemetry Collector Contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [Grafana LGTM Docker](https://github.com/grafana/docker-otel-lgtm) - Reference implementation
