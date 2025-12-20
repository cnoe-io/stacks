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

- **FR-001**: System MUST deploy OpenTelemetry Collector as the ingestion gateway
- **FR-002**: System MUST configure OTEL Collector to receive OTLP on port 4318
- **FR-003**: System MUST deploy Grafana Mimir for long-term metrics storage
- **FR-004**: System MUST deploy Grafana Loki for log aggregation
- **FR-005**: System MUST deploy Grafana Tempo for distributed tracing
- **FR-006**: System MUST deploy Grafana for visualization
- **FR-007**: System MUST deploy Pyroscope for continuous profiling
- **FR-008**: System MUST configure OTEL Collector to route metrics to Mimir, logs to Loki, traces to Tempo
- **FR-009**: System MUST expose all services via Tailscale with MagicDNS names
- **FR-010**: System MUST configure 30-day retention for all telemetry signals
- **FR-011**: System MUST use persistent volume claims for all stateful services
- **FR-012**: System MUST configure Grafana with data sources for Mimir, Loki, Tempo, Pyroscope
- **FR-013**: System MUST support receiving telemetry from multiple workstations simultaneously
- **FR-014**: System MUST preserve existing observability namespace and Langfuse deployment

### Key Entities

- **OTEL Collector**: Gateway service receiving OTLP and routing to backends
- **Mimir**: Prometheus-compatible metrics backend with long-term storage
- **Loki**: Log aggregation service with label-based querying
- **Tempo**: Distributed tracing backend with trace correlation
- **Grafana**: Visualization and dashboard platform
- **Pyroscope**: Continuous profiling with flame graph visualization
- **Tailscale Service**: Kubernetes service exposed via Tailscale operator

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Metrics from workstations appear in Grafana within 30 seconds of generation
- **SC-002**: Traces are searchable in Tempo within 5 seconds of receipt
- **SC-003**: Logs are queryable in Loki within 30 seconds of receipt
- **SC-004**: All services accessible via Tailscale MagicDNS from any tailnet device
- **SC-005**: Data retention of 30 days is enforced for all signals
- **SC-006**: System handles telemetry from 5+ workstations simultaneously without degradation
- **SC-007**: Grafana dashboards show unified view across all hosts
- **SC-008**: Service restarts preserve all historical data (persistent storage)

## Assumptions

1. Kubernetes cluster (K3s on Ryzen) is operational and accessible
2. Tailscale operator is installed and configured in the cluster
3. Tailscale tailnet includes both workstations and cluster
4. Persistent storage (local-path-provisioner or similar) is available
5. Cluster has sufficient resources (4GB RAM, 50GB storage minimum)
6. ArgoCD is used for GitOps deployment (manifests in dist/ directory)
7. Existing observability namespace with Langfuse should be preserved

## Out of Scope

- High availability / multi-replica deployments (single-node cluster)
- Authentication/authorization for Grafana (internal use only)
- Alerting rules and notification channels
- Custom Grafana dashboards (use community dashboards initially)
- Cross-cluster federation
- Cost monitoring or usage quotas
