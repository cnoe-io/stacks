# Data Model: LGTM Observability Stack

**Feature**: 111-configure-k8s-observability
**Date**: 2025-12-19
**Status**: Complete

## Overview

This document defines the Kubernetes resources for the LGTM observability stack. Each component is deployed as an independent CDK8s chart with its own sync wave.

---

## 1. Namespace

**Chart**: `observability-namespace-chart.ts` (existing)
**Sync Wave**: -70

| Resource | Name | Notes |
|----------|------|-------|
| Namespace | observability | Shared with Langfuse |

---

## 2. Mimir (Metrics Backend)

**Chart**: `lgtm-mimir-chart.ts` (new)
**Sync Wave**: -60
**Namespace**: observability

### Kubernetes Resources

| Resource Type | Name | Purpose |
|---------------|------|---------|
| ConfigMap | mimir-config | Mimir YAML configuration |
| PersistentVolumeClaim | mimir-data | 20Gi storage for TSDB |
| Deployment | mimir | Single replica, monolithic mode |
| Service | mimir | ClusterIP, ports 9009 (HTTP), 9095 (gRPC) |

### Configuration Properties

```typescript
interface LgtmMimirChartProps extends ChartProps {
  namespace?: string;              // default: 'observability'
  storageSize?: string;            // default: '20Gi'
  image?: string;                  // default: 'grafana/mimir:2.14.0'
  retentionDays?: number;          // default: 30
  resources?: ResourceRequirements; // CPU/memory limits
}
```

### Labels

```yaml
app.kubernetes.io/name: mimir
app.kubernetes.io/component: metrics-backend
app.kubernetes.io/part-of: lgtm-stack
app.kubernetes.io/managed-by: cdk8s
```

---

## 3. Loki (Logs Backend)

**Chart**: `lgtm-loki-chart.ts` (new)
**Sync Wave**: -60
**Namespace**: observability

### Kubernetes Resources

| Resource Type | Name | Purpose |
|---------------|------|---------|
| ConfigMap | loki-config | Loki YAML configuration |
| PersistentVolumeClaim | loki-data | 20Gi storage for chunks/WAL |
| Deployment | loki | Single replica, single binary mode |
| Service | loki | ClusterIP, ports 3100 (HTTP), 9096 (gRPC) |

### Configuration Properties

```typescript
interface LgtmLokiChartProps extends ChartProps {
  namespace?: string;              // default: 'observability'
  storageSize?: string;            // default: '20Gi'
  image?: string;                  // default: 'grafana/loki:3.3.0'
  retentionDays?: number;          // default: 30
  resources?: ResourceRequirements;
}
```

### Labels

```yaml
app.kubernetes.io/name: loki
app.kubernetes.io/component: logs-backend
app.kubernetes.io/part-of: lgtm-stack
app.kubernetes.io/managed-by: cdk8s
```

---

## 4. Tempo (Traces Backend)

**Chart**: `lgtm-tempo-chart.ts` (new)
**Sync Wave**: -60
**Namespace**: observability

### Kubernetes Resources

| Resource Type | Name | Purpose |
|---------------|------|---------|
| ConfigMap | tempo-config | Tempo YAML configuration |
| PersistentVolumeClaim | tempo-data | 20Gi storage for traces/WAL |
| Deployment | tempo | Single replica, monolithic mode |
| Service | tempo | ClusterIP, ports 3200 (HTTP), 4317 (OTLP gRPC), 4318 (OTLP HTTP) |

### Configuration Properties

```typescript
interface LgtmTempoChartProps extends ChartProps {
  namespace?: string;              // default: 'observability'
  storageSize?: string;            // default: '20Gi'
  image?: string;                  // default: 'grafana/tempo:2.6.1'
  retentionDays?: number;          // default: 30
  mimirEndpoint?: string;          // default: 'http://mimir:9009/api/v1/push'
  resources?: ResourceRequirements;
}
```

### Labels

```yaml
app.kubernetes.io/name: tempo
app.kubernetes.io/component: traces-backend
app.kubernetes.io/part-of: lgtm-stack
app.kubernetes.io/managed-by: cdk8s
```

---

## 5. Pyroscope (Profiles Backend)

**Chart**: `lgtm-pyroscope-chart.ts` (new)
**Sync Wave**: -60
**Namespace**: observability

### Kubernetes Resources

| Resource Type | Name | Purpose |
|---------------|------|---------|
| PersistentVolumeClaim | pyroscope-data | 10Gi storage for profiles |
| Deployment | pyroscope | Single replica |
| Service | pyroscope | ClusterIP, port 4040 (HTTP) |

### Configuration Properties

```typescript
interface LgtmPyroscopeChartProps extends ChartProps {
  namespace?: string;              // default: 'observability'
  storageSize?: string;            // default: '10Gi'
  image?: string;                  // default: 'grafana/pyroscope:1.10.0'
  resources?: ResourceRequirements;
}
```

### Labels

```yaml
app.kubernetes.io/name: pyroscope
app.kubernetes.io/component: profiles-backend
app.kubernetes.io/part-of: lgtm-stack
app.kubernetes.io/managed-by: cdk8s
```

---

## 6. OTEL Collector (Ingestion Gateway)

**Chart**: `lgtm-otel-collector-chart.ts` (new)
**Sync Wave**: -55
**Namespace**: observability

### Kubernetes Resources

| Resource Type | Name | Purpose |
|---------------|------|---------|
| ConfigMap | otel-collector-config | Collector YAML configuration |
| Deployment | otel-collector | Single replica, stateless |
| Service | otel-collector | ClusterIP, ports 4317 (gRPC), 4318 (HTTP), 8888 (metrics) |

### Configuration Properties

```typescript
interface LgtmOtelCollectorChartProps extends ChartProps {
  namespace?: string;              // default: 'observability'
  image?: string;                  // default: 'otel/opentelemetry-collector-contrib:0.115.0'
  mimirEndpoint?: string;          // default: 'http://mimir:9009/api/v1/push'
  lokiEndpoint?: string;           // default: 'http://loki:3100/loki/api/v1/push'
  tempoEndpoint?: string;          // default: 'tempo:4317'
  resources?: ResourceRequirements;
}
```

### Labels

```yaml
app.kubernetes.io/name: otel-collector
app.kubernetes.io/component: ingestion-gateway
app.kubernetes.io/part-of: lgtm-stack
app.kubernetes.io/managed-by: cdk8s
```

---

## 7. Grafana (Visualization)

**Chart**: `lgtm-grafana-chart.ts` (new)
**Sync Wave**: -50
**Namespace**: observability

### Kubernetes Resources

| Resource Type | Name | Purpose |
|---------------|------|---------|
| ConfigMap | grafana-datasources | Datasource provisioning YAML |
| ConfigMap | grafana-dashboards-provider | Dashboard provider config |
| ConfigMap | grafana-dashboards | Dashboard JSON files |
| Deployment | grafana | Single replica, stateless |
| Service | grafana | ClusterIP, port 3000 (HTTP) |

### Configuration Properties

```typescript
interface LgtmGrafanaChartProps extends ChartProps {
  namespace?: string;              // default: 'observability'
  image?: string;                  // default: 'grafana/grafana:11.3.0'
  mimirUrl?: string;               // default: 'http://mimir:9009/prometheus'
  lokiUrl?: string;                // default: 'http://loki:3100'
  tempoUrl?: string;               // default: 'http://tempo:3200'
  pyroscopeUrl?: string;           // default: 'http://pyroscope:4040'
  resources?: ResourceRequirements;
}
```

### Labels

```yaml
app.kubernetes.io/name: grafana
app.kubernetes.io/component: visualization
app.kubernetes.io/part-of: lgtm-stack
app.kubernetes.io/managed-by: cdk8s
```

---

## 8. Tailscale Services

**Chart**: Reuse `tailscale-serve-chart.ts` (existing)
**Sync Wave**: -45
**Namespace**: tailscale

### Services to Create

| Application Name | Service Name | Backend Host | Backend Port |
|------------------|--------------|--------------|--------------|
| otel-collector-tailscale-serve | otel-collector | otel-collector.observability.svc.cluster.local | 4318 |
| grafana-tailscale-serve | grafana | grafana.observability.svc.cluster.local | 3000 |
| mimir-tailscale-serve | mimir | mimir.observability.svc.cluster.local | 9009 |

**Note**: These will replace/update the existing tailscale-serve entries in applications.ts.

---

## 9. Applications.ts Updates

### Applications to Remove

```typescript
// DELETE: Legacy ClickHouse-based stack
{
  name: 'otel-stack',
  namespace: 'observability',
  // ...
}
```

### Applications to Add

```typescript
// Mimir (Metrics)
{
  name: 'lgtm-mimir',
  namespace: 'observability',
  chart: { type: 'LgtmMimirChart' },
  argocd: { syncWave: '-60' }
}

// Loki (Logs)
{
  name: 'lgtm-loki',
  namespace: 'observability',
  chart: { type: 'LgtmLokiChart' },
  argocd: { syncWave: '-60' }
}

// Tempo (Traces)
{
  name: 'lgtm-tempo',
  namespace: 'observability',
  chart: { type: 'LgtmTempoChart' },
  argocd: { syncWave: '-60' }
}

// Pyroscope (Profiles)
{
  name: 'lgtm-pyroscope',
  namespace: 'observability',
  chart: { type: 'LgtmPyroscopeChart' },
  argocd: { syncWave: '-60' }
}

// OTEL Collector
{
  name: 'lgtm-otel-collector',
  namespace: 'observability',
  chart: { type: 'LgtmOtelCollectorChart' },
  argocd: { syncWave: '-55' }
}

// Grafana
{
  name: 'lgtm-grafana',
  namespace: 'observability',
  chart: { type: 'LgtmGrafanaChart' },
  argocd: { syncWave: '-50' }
}
```

---

## 10. File Structure

```
cdk8s/charts/infra/
├── lgtm-mimir-chart.ts         # NEW
├── lgtm-loki-chart.ts          # NEW
├── lgtm-tempo-chart.ts         # NEW
├── lgtm-pyroscope-chart.ts     # NEW
├── lgtm-otel-collector-chart.ts # NEW
├── lgtm-grafana-chart.ts       # NEW
├── otel-stack-chart.ts         # DELETE
└── observability-namespace-chart.ts  # KEEP

cdk8s/lib/
└── lgtm-helpers.ts             # NEW: Shared configuration generators
```

---

## Entity Relationships

```
                    ┌─────────────────┐
                    │ NixOS Workstation│
                    │  (Grafana Alloy) │
                    └────────┬────────┘
                             │ OTLP (4317/4318)
                             ▼
                    ┌─────────────────┐
                    │  OTEL Collector │
                    │   (Gateway)     │
                    └───────┬─────────┘
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
    ┌───────────┐    ┌───────────┐    ┌───────────┐
    │   Mimir   │    │   Loki    │    │   Tempo   │
    │ (Metrics) │    │  (Logs)   │    │ (Traces)  │
    └─────┬─────┘    └─────┬─────┘    └─────┬─────┘
          │                │                │
          └────────────────┼────────────────┘
                           │
                    ┌──────┴──────┐
                    │   Grafana   │
                    │ (Dashboard) │
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │  Pyroscope  │
                    │ (Profiles)  │
                    └─────────────┘
```
