# Implementation Plan: Kubernetes LGTM Observability Stack

**Branch**: `111-configure-k8s-observability` | **Date**: 2025-12-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/111-configure-k8s-observability/spec.md`

## Summary

Replace the existing ClickHouse-based OpenTelemetry stack with Grafana's LGTM stack (Loki, Grafana, Tempo, Mimir) plus Pyroscope. This provides purpose-built backends for each telemetry signal (metrics, logs, traces, profiles) with native Grafana integration, superior query languages (PromQL, LogQL, TraceQL), and cross-signal correlation. The stack receives OTLP from NixOS workstations via Tailscale and provides unified visualization through Grafana.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s charts)
**Primary Dependencies**: CDK8s, cdk8s-plus-32, Kubernetes API imports
**Storage**: Persistent Volume Claims via local-path-provisioner (K3s default)
**Testing**: kubectl diff, ArgoCD sync verification, OTEL test data injection
**Target Platform**: Kubernetes (K3s on Ryzen homelab)
**Project Type**: Infrastructure-as-Code (CDK8s charts generating Kubernetes manifests)
**Performance Goals**: Metrics visible in 30s, traces in 5s, logs in 30s (per spec SC-001/002/003)
**Constraints**: Single-node cluster, 8GB RAM budget, 100GB storage, 30-day retention
**Scale/Scope**: 5+ concurrent workstations, ~7 new CDK8s charts, ~3 Tailscale services

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**No constitution file found** - proceeding without constitution gates. This is acceptable for infrastructure projects following established CDK8s patterns in this repository.

**Implicit Gates Applied**:
- ✅ Follow existing chart patterns in `cdk8s/charts/infra/`
- ✅ Use `TailscaleServeChart` for service exposure (established pattern)
- ✅ Register all charts in `applications.ts` with proper sync waves
- ✅ Maintain Langfuse coexistence (FR-020, FR-021)

## Project Structure

### Documentation (this feature)

```
specs/111-configure-k8s-observability/
├── plan.md              # This file
├── research.md          # Phase 0 output - LGTM component configuration research
├── data-model.md        # Phase 1 output - Kubernetes resource definitions
├── quickstart.md        # Phase 1 output - Deployment and testing guide
├── contracts/           # Phase 1 output - API/protocol definitions
│   ├── otel-collector-config.yaml    # OTEL Collector routing configuration
│   ├── grafana-datasources.yaml      # Grafana datasource provisioning
│   └── grafana-dashboards.yaml       # Dashboard provisioning config
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   ├── infra/
│   │   ├── lgtm-mimir-chart.ts         # NEW: Mimir deployment (metrics)
│   │   ├── lgtm-loki-chart.ts          # NEW: Loki deployment (logs)
│   │   ├── lgtm-tempo-chart.ts         # NEW: Tempo deployment (traces)
│   │   ├── lgtm-pyroscope-chart.ts     # NEW: Pyroscope deployment (profiles)
│   │   ├── lgtm-grafana-chart.ts       # NEW: Grafana with LGTM datasources
│   │   ├── lgtm-otel-collector-chart.ts # NEW: OTEL Collector for LGTM routing
│   │   ├── otel-stack-chart.ts         # DELETE: Legacy ClickHouse stack
│   │   └── observability-namespace-chart.ts  # KEEP: Namespace definition
│   └── platform/
│       ├── tailscale-serve-chart.ts    # KEEP: Generic serve chart (reuse)
│       └── ...
├── config/
│   └── applications.ts                 # MODIFY: Add LGTM apps, remove otel-stack
└── lib/
    └── lgtm-helpers.ts                 # NEW: Shared LGTM configuration helpers
```

**Structure Decision**: CDK8s infrastructure charts following established patterns. Each LGTM component gets its own chart for independent sync waves and clear separation of concerns. Charts prefixed with `lgtm-` for easy identification.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 6 new charts (vs 1 monolithic) | Each LGTM component has independent lifecycle, different storage needs, can be disabled individually | Monolithic chart would be 2000+ lines, harder to maintain, all-or-nothing deployment |
| Separate Grafana chart (lgtm-grafana vs existing otel-stack grafana) | Need LGTM datasources, trace-to-logs correlation, different provisioning | Reusing existing would require complex conditional logic |

## Phase 0: Research Tasks

The following unknowns require research before implementation:

### Research Areas

1. **Mimir Monolithic Mode Configuration**
   - Single-binary deployment suitable for single-node K3s
   - Storage backend (filesystem vs object storage)
   - Retention policy configuration (30 days)
   - OTLP write endpoint (otlphttp exporter)

2. **Loki Single-Binary Configuration**
   - Filesystem storage for single-node
   - Label indexing strategy for host/service labels
   - LogQL retention settings
   - OTLP log receiver format

3. **Tempo Monolithic Mode Configuration**
   - Trace storage on filesystem
   - OTLP receiver configuration
   - Trace-to-logs via trace ID correlation
   - 30-day retention

4. **Pyroscope Configuration**
   - Standalone deployment mode
   - Profile storage
   - Grafana datasource integration

5. **OTEL Collector Multi-Backend Routing**
   - Processor pipeline for signal separation
   - Exporters for Mimir (Prometheus remote write), Loki (loki exporter), Tempo (OTLP)
   - Batching and retry configuration

6. **Grafana LGTM Datasource Integration**
   - Provisioning YAML for all datasources
   - Trace-to-logs and logs-to-traces correlation
   - Explore integration for each signal

**Output**: See `research.md` for detailed findings and configurations.

## Phase 1: Design Artifacts

### data-model.md Entities

| Entity | Kubernetes Resources | Storage | Ports |
|--------|---------------------|---------|-------|
| OTEL Collector | Deployment, Service, ConfigMap | None (stateless) | 4317 (gRPC), 4318 (HTTP) |
| Mimir | Deployment, Service, ConfigMap, PVC | 20Gi | 9009 |
| Loki | Deployment, Service, ConfigMap, PVC | 20Gi | 3100 |
| Tempo | Deployment, Service, ConfigMap, PVC | 20Gi | 3200, 4317 |
| Pyroscope | Deployment, Service, PVC | 10Gi | 4040 |
| Grafana | Deployment, Service, ConfigMap | None (provisioning only) | 3000 |
| Tailscale Services | 3x TailscaleServeChart | 1Gi each (optional) | 443 (https) |

### contracts/ Contents

1. **otel-collector-config.yaml**: Complete OTEL Collector configuration with:
   - OTLP receivers (gRPC + HTTP)
   - Batch processor configuration
   - Exporters: prometheusremotewrite (Mimir), loki, otlp (Tempo)
   - Service pipelines routing each signal

2. **grafana-datasources.yaml**: Provisioning configuration for:
   - Prometheus (Mimir) datasource
   - Loki datasource with derived fields for trace correlation
   - Tempo datasource
   - Pyroscope datasource

3. **grafana-dashboards.yaml**: Dashboard provisioning for Node Exporter and LGTM overview

### quickstart.md Contents

- Prerequisites check (K3s running, Tailscale operator, storage)
- Step-by-step deployment via ArgoCD sync
- Verification commands for each component
- Test data injection (otel-cli for traces, promtool for metrics)
- Troubleshooting guide

## Implementation Phases Summary

| Phase | Output | Status |
|-------|--------|--------|
| 0: Research | research.md | Pending |
| 1: Design | data-model.md, contracts/*, quickstart.md | Pending |
| 2: Tasks | tasks.md | Generated via /speckit.tasks |

## Next Steps

1. Generate `research.md` with LGTM component configurations
2. Generate `data-model.md` with Kubernetes resource specifications
3. Generate `contracts/` with OTEL and Grafana configurations
4. Generate `quickstart.md` with deployment guide
5. Run `/speckit.tasks` to generate implementation tasks
