# Feature Specification: Kubernetes LGTM Observability Stack

**Feature Branch**: `111-configure-k8s-observability`
**Created**: 2025-12-19
**Status**: Draft
**Input**: User description: "Create a spec that implements the kubernetes resources associated with the observability pipeline"

## Background

This feature deploys the Grafana LGTM stack (Loki, Grafana, Tempo, Mimir) plus Pyroscope to the Kubernetes cluster to receive telemetry from NixOS workstations. The workstations run Grafana Alloy which sends:

- **Metrics** → Mimir (Prometheus-compatible long-term storage)
- **Logs** → Loki (log aggregation and search)
- **Traces** → Tempo (distributed tracing)
- **Profiles** → Pyroscope (continuous profiling)

An OpenTelemetry Collector acts as the ingestion gateway, receiving OTLP from workstations via Tailscale and routing to the appropriate backends.

**Note**: This feature fully replaces the existing ClickHouse-based OTEL stack (`otel-stack-chart.ts`) with the optimal Grafana LGTM architecture. Legacy ClickHouse-based observability resources will be removed.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster (Ryzen/K3s)                         │
│                         Namespace: observability                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    OTEL Collector (Gateway)                          │   │
│  │              Receives OTLP on :4318 via Tailscale                    │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │ OTLP Receiver│  │Batch Processor│ │ Multi-Export │               │   │
│  │  │  (port 4318) │→ │   (buffer)   │→ │  (routing)   │               │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │   │
│  └──────────────────────────────┬───────────────────────────────────────┘   │
│                                 │                                           │
│         ┌───────────────────────┼───────────────────────┐                   │
│         ▼                       ▼                       ▼                   │
│  ┌─────────────┐         ┌─────────────┐         ┌─────────────┐           │
│  │    MIMIR    │         │    LOKI     │         │    TEMPO    │           │
│  │  (Metrics)  │         │   (Logs)    │         │  (Traces)   │           │
│  │   :9009     │         │   :3100     │         │   :3200     │           │
│  │   30d ret   │         │   30d ret   │         │   30d ret   │           │
│  └──────┬──────┘         └──────┬──────┘         └──────┬──────┘           │
│         │                       │                       │                   │
│         └───────────────────────┼───────────────────────┘                   │
│                                 ▼                                           │
│                          ┌─────────────┐                                    │
│                          │   GRAFANA   │                                    │
│                          │  Dashboard  │                                    │
│                          │   :3000     │                                    │
│                          └─────────────┘                                    │
│                                 │                                           │
│                          ┌──────┴──────┐                                    │
│                          │  PYROSCOPE  │                                    │
│                          │  (Profiles) │                                    │
│                          │   :4040     │                                    │
│                          └─────────────┘                                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Tailscale Proxy Service                          │   │
│  │         Exposes services to Tailscale network as MagicDNS           │   │
│  │                                                                      │   │
│  │  otel-collector.tail286401.ts.net:4318 → OTEL Collector             │   │
│  │  mimir.tail286401.ts.net:9009 → Mimir                               │   │
│  │  loki.tail286401.ts.net:3100 → Loki                                 │   │
│  │  grafana.tail286401.ts.net:3000 → Grafana                           │   │
│  │  pyroscope.tail286401.ts.net:4040 → Pyroscope                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## User Scenarios & Testing *(mandatory)*

### User Story 1 - System Metrics Dashboard (Priority: P1)

As a system administrator, I want to view real-time and historical system metrics from all workstations in a unified Grafana dashboard, so I can monitor health and resource usage across my infrastructure.

**Why this priority**: Core observability capability - metrics are the foundation for monitoring and alerting.

**Independent Test**: Deploy OTEL Collector and Mimir, send test metrics from a workstation, verify they appear in Grafana within 30 seconds.

**Acceptance Scenarios**:

1. **Given** the LGTM stack is deployed, **When** a workstation sends Prometheus metrics via OTLP, **Then** metrics are stored in Mimir and queryable in Grafana
2. **Given** Mimir is running, **When** I query for `node_cpu_seconds_total{host="thinkpad"}`, **Then** I see CPU metrics for the thinkpad workstation
3. **Given** metrics are being collected, **When** I open the Node Exporter dashboard in Grafana, **Then** I see CPU, memory, disk, and network graphs for each host
4. **Given** 30 days of metrics exist, **When** I query historical data, **Then** all data is available (retention policy working)

---

### User Story 2 - Distributed Tracing (Priority: P1)

As a developer, I want to view distributed traces from my applications and AI assistant sessions, so I can debug performance issues and understand request flow.

**Why this priority**: Equal to metrics - tracing is essential for debugging AI assistant interactions.

**Independent Test**: Send a trace span via OTLP to the collector, verify it appears in Grafana Tempo within 5 seconds.

**Acceptance Scenarios**:

1. **Given** Tempo is deployed, **When** a trace is sent via OTLP, **Then** the trace is stored and searchable
2. **Given** traces exist, **When** I search by trace ID in Grafana, **Then** I see the full span hierarchy with timing
3. **Given** Claude Code sends traces, **When** I search for `service.name=claude-code`, **Then** I find all Claude Code API request spans
4. **Given** multiple workstations send traces, **When** I filter by `host`, **Then** traces are correctly attributed to source

---

### User Story 3 - Centralized Log Search (Priority: P2)

As a system administrator, I want to search and analyze logs from all workstations in one place, so I can troubleshoot issues without SSHing to each machine.

**Why this priority**: Important but secondary to metrics/traces - logs provide context for debugging.

**Independent Test**: Send a log entry via OTLP, search for it in Grafana Loki within 30 seconds.

**Acceptance Scenarios**:

1. **Given** Loki is deployed, **When** journald logs are sent via OTLP, **Then** logs are stored and searchable
2. **Given** logs from multiple hosts, **When** I filter by `host=thinkpad`, **Then** I see only thinkpad logs
3. **Given** a trace ID exists, **When** I click "logs for this trace" in Grafana, **Then** correlated logs appear
4. **Given** an error occurred, **When** I search `level=error` in the last hour, **Then** I find the relevant log entries

---

### User Story 4 - Performance Profiling (Priority: P3)

As a developer, I want to view CPU and memory profiles for my Python services, so I can identify performance bottlenecks.

**Why this priority**: Advanced debugging feature - valuable after core observability is working.

**Independent Test**: Configure a Python app with Pyroscope SDK, verify flame graph appears in Grafana.

**Acceptance Scenarios**:

1. **Given** Pyroscope is deployed, **When** an application sends profiles, **Then** flame graphs are viewable in Grafana
2. **Given** profiles exist, **When** I select a time range, **Then** I can compare before/after profiles
3. **Given** continuous profiling is running, **When** high CPU usage occurs, **Then** I can identify the hot functions

---

### User Story 5 - Tailscale Network Exposure (Priority: P1)

As an infrastructure operator, I want all observability services accessible via Tailscale MagicDNS, so workstations can send telemetry without public internet exposure.

**Why this priority**: Critical infrastructure - without Tailscale exposure, workstations cannot send data.

**Independent Test**: Deploy Tailscale proxy, verify `otel-collector.tail286401.ts.net:4318` resolves and accepts OTLP.

**Acceptance Scenarios**:

1. **Given** Tailscale operator is configured, **When** services are annotated for exposure, **Then** MagicDNS names resolve within the tailnet
2. **Given** OTEL Collector is exposed, **When** a workstation sends OTLP to `otel-collector.tail286401.ts.net:4318`, **Then** data is received
3. **Given** Grafana is exposed, **When** I browse to `grafana.tail286401.ts.net:3000`, **Then** I can access dashboards

---

### Edge Cases

- What happens when storage fills up? Oldest data is automatically pruned per retention policy (30 days)
- What happens when a backend is temporarily unavailable? OTEL Collector queues data in memory (100MB limit), retries with exponential backoff
- What happens when Tailscale connectivity is lost? Services remain available within cluster, external access fails gracefully
- What happens when Mimir/Loki/Tempo restarts? Persistent volume claims preserve data, service resumes after restart

## Requirements *(mandatory)*

### Functional Requirements

#### Core LGTM Stack Deployment

- **FR-001**: System MUST deploy OpenTelemetry Collector as the ingestion gateway
- **FR-002**: System MUST configure OTEL Collector to receive OTLP on port 4318 (HTTP) and 4317 (gRPC)
- **FR-003**: System MUST deploy Grafana Mimir for Prometheus-compatible long-term metrics storage
- **FR-004**: System MUST deploy Grafana Loki for log aggregation and label-based querying
- **FR-005**: System MUST deploy Grafana Tempo for distributed tracing with trace correlation
- **FR-006**: System MUST deploy Grafana for unified visualization of all telemetry signals
- **FR-007**: System MUST deploy Pyroscope for continuous profiling with flame graph visualization
- **FR-008**: System MUST configure OTEL Collector to route metrics to Mimir, logs to Loki, traces to Tempo

#### Data Persistence and Retention

- **FR-009**: System MUST configure 30-day retention for all telemetry signals (metrics, logs, traces, profiles)
- **FR-010**: System MUST use persistent volume claims for all stateful services (Mimir, Loki, Tempo, Pyroscope)

#### Grafana Configuration

- **FR-011**: System MUST configure Grafana with data sources for Mimir (Prometheus), Loki, Tempo, and Pyroscope
- **FR-012**: System MUST enable trace-to-logs and logs-to-traces correlation in Grafana

#### Network Exposure

- **FR-013**: System MUST expose OTEL Collector via Tailscale for workstation telemetry ingestion
- **FR-014**: System MUST expose Grafana via Tailscale for dashboard access
- **FR-015**: System MUST support receiving telemetry from multiple workstations simultaneously

#### Legacy Removal

- **FR-016**: System MUST remove the existing ClickHouse-based OTEL stack (`otel-stack-chart.ts`)
- **FR-017**: System MUST remove ClickHouse deployment from the observability namespace (excluding Langfuse's separate ClickHouse)
- **FR-018**: System MUST remove legacy Grafana dashboards configured for ClickHouse OTEL schema
- **FR-019**: System MUST update ArgoCD application configurations to deploy LGTM stack instead of ClickHouse stack

#### Coexistence with Langfuse

- **FR-020**: System MUST preserve Langfuse deployment and its dedicated infrastructure (PostgreSQL, ClickHouse, Redis, MinIO)
- **FR-021**: Langfuse MUST continue functioning independently of the LGTM observability stack

### Key Entities

- **OTEL Collector**: Gateway service receiving OTLP and routing to LGTM backends
- **Mimir**: Prometheus-compatible metrics backend with long-term storage and PromQL query support
- **Loki**: Log aggregation service with LogQL query language and label-based indexing
- **Tempo**: Distributed tracing backend with TraceQL support and trace correlation
- **Grafana**: Unified visualization platform with LGTM data source integrations
- **Pyroscope**: Continuous profiling backend with flame graph visualization
- **Tailscale Service**: Kubernetes service exposed via Tailscale operator for secure access

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Metrics from workstations appear in Grafana within 30 seconds of generation
- **SC-002**: Traces are searchable in Tempo within 5 seconds of receipt
- **SC-003**: Logs are queryable in Loki within 30 seconds of receipt
- **SC-004**: All services accessible via Tailscale MagicDNS from any tailnet device
- **SC-005**: Data retention of 30 days is enforced for all signals
- **SC-006**: System handles telemetry from 5+ workstations simultaneously without degradation
- **SC-007**: Grafana dashboards show unified view across all hosts with signal correlation
- **SC-008**: Service restarts preserve all historical data (persistent storage verified)
- **SC-009**: Legacy ClickHouse-based OTEL resources are fully removed from the cluster
- **SC-010**: Langfuse continues operating without disruption after migration

## Assumptions

1. Kubernetes cluster (K3s on Ryzen) is operational and accessible
2. Tailscale operator is installed and configured in the cluster
3. Tailscale tailnet includes both workstations and cluster
4. Persistent storage (local-path-provisioner or similar) is available
5. Cluster has sufficient resources (8GB RAM, 100GB storage recommended for LGTM stack)
6. ArgoCD is used for GitOps deployment (manifests in dist/ directory)
7. Langfuse and its infrastructure (langfuse-clickhouse, langfuse-postgres, langfuse-redis, langfuse-minio) are separate from the LGTM observability stack and will be preserved
8. Workstations are configured to send OTLP to the cluster (Grafana Alloy configuration is out of scope for this feature)

## Out of Scope

- High availability / multi-replica deployments (single-node cluster)
- Authentication/authorization for Grafana (internal use only via Tailscale)
- Alerting rules and notification channels
- Custom Grafana dashboards (use community dashboards initially)
- Cross-cluster federation
- Cost monitoring or usage quotas
- Grafana Alloy configuration on workstations (separate feature)
- Langfuse infrastructure modifications
