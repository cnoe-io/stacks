# OpenTelemetry Stack Documentation

This document describes the OpenTelemetry observability stack deployed in the Kubernetes cluster, including how to send telemetry from both in-cluster applications and external systems (like NixOS machines via Tailscale).

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                           Kubernetes Cluster                                    │
│                                                                                 │
│  ┌─────────────────┐      ┌─────────────────────┐      ┌──────────────────┐   │
│  │   Application   │      │   OTEL Collector    │      │    ClickHouse    │   │
│  │     (Pod)       │─────▶│                     │─────▶│   (Database)     │   │
│  └─────────────────┘      │  Receives on:       │      │                  │   │
│                           │  - 4317 (gRPC)      │      │  Stores in:      │   │
│  ┌─────────────────┐      │  - 4318 (HTTP)      │      │  - otel_traces   │   │
│  │   Application   │─────▶│                     │      │  - otel_logs     │   │
│  │     (Pod)       │      │  Exports to:        │      │  - otel_metrics  │   │
│  └─────────────────┘      │  - ClickHouse:9000  │      └────────┬─────────┘   │
│                           │  - debug (logs)     │               │             │
│                           └─────────────────────┘               │             │
│                                     ▲                           ▼             │
│                                     │                 ┌──────────────────┐   │
│                                     │                 │     Grafana      │   │
│                                     │                 │  (Visualization) │   │
│                                     │                 │                  │   │
│                                     │                 │  Queries via:    │   │
│                                     │                 │  - HTTP :8123    │   │
│                                     │                 │  - Native :9000  │   │
│                                     │                 └──────────────────┘   │
│                                     │                                         │
│  ┌──────────────────────────────────┴──────────────────────────────────────┐ │
│  │                    Tailscale Serve Proxy                                 │ │
│  │  Exposes: https://svc-otel-collector-<cluster>.tail286401.ts.net (port 443) │ │
│  │  Forwards: TLS termination → socat:8080 → collector:4318                │ │
│  └──────────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ HTTPS (port 443)
                                      │
┌─────────────────────────────────────┴──────────────────────────────────────────┐
│                         External Systems (via Tailscale)                        │
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                │
│  │  NixOS Machine  │  │  NixOS Machine  │  │  NixOS Machine  │                │
│  │    (Hetzner)    │  │    (Ryzen)      │  │   (ThinkPad)    │                │
│  │                 │  │                 │  │                 │                │
│  │  Claude Code    │  │  Claude Code    │  │  Claude Code    │                │
│  │  Gemini CLI     │  │  Gemini CLI     │  │  Gemini CLI     │                │
│  │  Codex CLI      │  │  Codex CLI      │  │  Codex CLI      │                │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                │
└────────────────────────────────────────────────────────────────────────────────┘
```

## Endpoints Summary

### In-Cluster Access (for Kubernetes pods)

| Purpose                | Endpoint                                        | Protocol     |
|------------------------|-------------------------------------------------|--------------|
| Apps → Collector       | `otel-collector.observability.svc:4317`         | gRPC (OTLP)  |
| Apps → Collector       | `otel-collector.observability.svc:4318`         | HTTP (OTLP)  |
| Collector → ClickHouse | `otel-clickhouse.observability.svc:9000`        | TCP (Native) |
| Grafana → ClickHouse   | `otel-clickhouse.observability.svc:8123`        | HTTP         |

### External Access (via Tailscale)

| Purpose                   | Endpoint                                    | Protocol     |
|---------------------------|---------------------------------------------|--------------|
| External → Collector      | `https://svc-otel-collector-<cluster>.tail286401.ts.net`  | HTTPS (443)  |
| Grafana Dashboard (Traces)| `https://svc-grafana-<cluster>.tail286401.ts.net/d/otel-traces` | HTTPS |
| Grafana Dashboard (Logs)  | `https://svc-grafana-<cluster>.tail286401.ts.net/d/otel-logs`   | HTTPS |
| Grafana Dashboard (Metrics)| `https://svc-grafana-<cluster>.tail286401.ts.net/d/otel-metrics`| HTTPS |
| Grafana Dashboard (Overview)| `https://svc-grafana-<cluster>.tail286401.ts.net/d/otel-overview`| HTTPS |

**Important:** External access uses HTTPS on port 443 (NOT HTTP on port 4318). The Tailscale serve proxy terminates TLS and forwards to the in-cluster collector.

**Cluster suffix:** `<cluster>` is the cluster identifier (e.g., `thinkpad`, `ryzen`, `hub`) used in Tailscale Service names to prevent collisions when multiple clusters share one tailnet.

## Data Flow

### In-Cluster Data Flow

```
Application Pod
    │
    ▼ OTLP (gRPC :4317 or HTTP :4318)
OTEL Collector (otel-collector.observability.svc)
    │
    ▼ ClickHouse Native Protocol (:9000)
ClickHouse (otel-clickhouse.observability.svc)
    │
    ▼ ClickHouse Native/HTTP (:9000/:8123)
Grafana (grafana.observability.svc)
```

### External Data Flow (NixOS → K8s)

```
AI Assistant (Claude Code, Gemini CLI, Codex)
    │
    ▼ OTLP HTTP (:4318)
Local OTEL Collector (NixOS systemd service)
    │
    ├──▶ otel-ai-monitor (local EWW widget, :4320)
    │
    └──▶ Tailscale HTTPS (:443)
         │
         ▼
    Tailscale Serve Proxy (svc-otel-collector-<cluster>.tail286401.ts.net)
         │
         ▼ socat TCP forward
    OTEL Collector (otel-collector.observability.svc:4318)
         │
         ▼ ClickHouse Native Protocol
    ClickHouse (persistent storage)
```

## Configuration

### In-Cluster Applications (Kubernetes)

Configure your application's OTEL SDK:

```yaml
# Pod environment variables
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector.observability.svc:4318"
  - name: OTEL_SERVICE_NAME
    value: "your-service-name"
  - name: OTEL_TRACES_EXPORTER
    value: "otlp"
  - name: OTEL_LOGS_EXPORTER
    value: "otlp"
  - name: OTEL_METRICS_EXPORTER
    value: "otlp"
```

Or using specific endpoints:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
    value: "http://otel-collector.observability.svc:4318/v1/traces"
  - name: OTEL_EXPORTER_OTLP_LOGS_ENDPOINT
    value: "http://otel-collector.observability.svc:4318/v1/logs"
  - name: OTEL_EXPORTER_OTLP_METRICS_ENDPOINT
    value: "http://otel-collector.observability.svc:4318/v1/metrics"
```

### External Applications (NixOS)

The NixOS OTEL collector (`otel-ai-collector.nix`) is configured to forward to the K8s cluster:

```nix
# In configurations/{hetzner,ryzen,thinkpad}.nix
services.otel-ai-collector = {
  enable = true;
  enableK8sExporter = true;
  # Endpoint uses HTTPS on port 443 (NOT HTTP on 4318!)
  # k8sExporterEndpoint defaults to https://svc-otel-collector-<cluster>.tail286401.ts.net
};
```

AI assistants (Claude Code, Gemini CLI, Codex) send telemetry to `localhost:4318`, which is received by the local OTEL collector and forwarded to both:
1. Local `otel-ai-monitor` service (for EWW widget real-time display)
2. K8s OTEL stack (for persistent storage and Grafana dashboards)

### Python SDK Example

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# In-cluster
exporter = OTLPSpanExporter(
    endpoint="http://otel-collector.observability.svc:4318/v1/traces"
)

# External (via Tailscale) - note HTTPS and no path suffix needed
exporter = OTLPSpanExporter(
    endpoint="https://svc-otel-collector-<cluster>.tail286401.ts.net/v1/traces"
)

provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

## Components

### OTEL Collector

- **Image:** `otel/opentelemetry-collector-contrib:0.142.0`
- **Receivers:** OTLP (gRPC :4317, HTTP :4318)
- **Exporters:** ClickHouse (native :9000), Debug (logs)
- **Pipelines:** traces, logs, metrics (all → ClickHouse)

### ClickHouse

- **Image:** `clickhouse/clickhouse-server:24.3`
- **Database:** `otel`
- **Tables:**
  - `otel_traces` - Span data with TraceId, SpanId, ServiceName, Duration, etc.
  - `otel_logs` - Log records with Timestamp, SeverityText, Body, TraceId
  - `otel_metrics_gauge`, `otel_metrics_sum`, `otel_metrics_histogram` - Metric data
- **Ports:** 8123 (HTTP), 9000 (Native)
- **Storage:** 20Gi PVC

### Grafana

- **Image:** `grafana/grafana:11.3.0`
- **Datasource:** ClickHouse with OTEL schema configuration
- **Dashboards:**
  - `otel-traces` - Trace analysis, span duration, service dependencies
  - `otel-logs` - Log volume, severity breakdown, log stream
  - `otel-metrics` - Gauge, sum, and histogram metrics
  - `otel-overview` - High-level overview with error rates and service stats

### Tailscale Serve Proxy

- **Purpose:** Expose OTEL collector to external systems via Tailscale
- **Flow:** HTTPS :443 → TLS termination → socat :8080 → collector :4318
- **Hostname:** `svc-otel-collector-<cluster>.tail286401.ts.net`

## Troubleshooting

### Verify Collector is Receiving Data

```bash
# Check collector logs
kubectl logs -n observability -l app.kubernetes.io/name=otel-collector -f

# Check for debug output
kubectl logs -n observability -l app.kubernetes.io/name=otel-collector | grep -i "trace\|span\|log"
```

### Verify ClickHouse Has Data

```bash
# Port-forward to ClickHouse
kubectl port-forward -n observability svc/otel-clickhouse 8123:8123

# Query traces
curl "http://localhost:8123" --data "SELECT count() FROM otel.otel_traces"

# Query logs
curl "http://localhost:8123" --data "SELECT count() FROM otel.otel_logs"
```

### Verify External Access (Tailscale)

```bash
# Test from NixOS machine
curl -v https://svc-otel-collector-<cluster>.tail286401.ts.net/v1/traces \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{}'

# Check Tailscale serve status
kubectl exec -n tailscale \
  $(kubectl get pods -n tailscale -l app.kubernetes.io/name=otel-collector-tailscale-serve -o name) \
  -- tailscale serve status
```

### Check NixOS Collector Status

```bash
# On NixOS machine
sudo systemctl status opentelemetry-collector
journalctl -u opentelemetry-collector -f

# Verify K8s exporter is enabled
grep -A5 "otlphttp/k8s" /etc/opentelemetry-collector/config.yaml
```

## Related Documentation

- [OTEL Stack Chart](/home/vpittamp/repos/PittampalliOrg/stacks/main/cdk8s/charts/infra/otel-stack-chart.ts) - CDK8s chart definition
- [NixOS OTEL Collector](/home/vpittamp/repos/vpittamp/nixos-config/main/modules/services/otel-ai-collector.nix) - NixOS module
- [OTEL AI Monitor](/home/vpittamp/repos/vpittamp/nixos-config/main/home-modules/services/otel-ai-monitor.nix) - EWW widget service
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [ClickHouse OTEL Exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/clickhouseexporter)
