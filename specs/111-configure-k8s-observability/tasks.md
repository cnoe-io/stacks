# Tasks: Kubernetes LGTM Observability Stack

**Input**: Design documents from `/specs/111-configure-k8s-observability/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested - test tasks omitted per spec.

**Organization**: Tasks grouped by user story for independent implementation.

## Format: `[ID] [P?] [Story?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US5)
- Paths are relative to repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and helper utilities

- [ ] T001 Create shared LGTM configuration helpers in `cdk8s/lib/lgtm-helpers.ts`
- [ ] T002 [P] Create LGTM label constants and resource naming utilities in `cdk8s/lib/lgtm-helpers.ts`

---

## Phase 2: Foundational (LGTM Backends)

**Purpose**: Deploy stateful backends that MUST be running before OTEL Collector can route data

**⚠️ CRITICAL**: User stories cannot be verified until these backends are deployed

### Storage Backend Charts

- [ ] T003 [P] Create Mimir chart skeleton in `cdk8s/charts/infra/lgtm-mimir-chart.ts` with ChartProps interface
- [ ] T004 [P] Create Loki chart skeleton in `cdk8s/charts/infra/lgtm-loki-chart.ts` with ChartProps interface
- [ ] T005 [P] Create Tempo chart skeleton in `cdk8s/charts/infra/lgtm-tempo-chart.ts` with ChartProps interface
- [ ] T006 [P] Create Pyroscope chart skeleton in `cdk8s/charts/infra/lgtm-pyroscope-chart.ts` with ChartProps interface

### Mimir Implementation (Metrics Storage)

- [ ] T007 Implement Mimir ConfigMap with monolithic mode config in `cdk8s/charts/infra/lgtm-mimir-chart.ts`
- [ ] T008 Implement Mimir PVC (20Gi) in `cdk8s/charts/infra/lgtm-mimir-chart.ts`
- [ ] T009 Implement Mimir Deployment with volume mounts in `cdk8s/charts/infra/lgtm-mimir-chart.ts`
- [ ] T010 Implement Mimir Service (ports 9009, 9095) in `cdk8s/charts/infra/lgtm-mimir-chart.ts`

### Loki Implementation (Logs Storage)

- [ ] T011 Implement Loki ConfigMap with single-binary config in `cdk8s/charts/infra/lgtm-loki-chart.ts`
- [ ] T012 Implement Loki PVC (20Gi) in `cdk8s/charts/infra/lgtm-loki-chart.ts`
- [ ] T013 Implement Loki Deployment with volume mounts in `cdk8s/charts/infra/lgtm-loki-chart.ts`
- [ ] T014 Implement Loki Service (ports 3100, 9096) in `cdk8s/charts/infra/lgtm-loki-chart.ts`

### Tempo Implementation (Traces Storage)

- [ ] T015 Implement Tempo ConfigMap with monolithic config in `cdk8s/charts/infra/lgtm-tempo-chart.ts`
- [ ] T016 Implement Tempo PVC (20Gi) in `cdk8s/charts/infra/lgtm-tempo-chart.ts`
- [ ] T017 Implement Tempo Deployment with metrics_generator remote_write to Mimir in `cdk8s/charts/infra/lgtm-tempo-chart.ts`
- [ ] T018 Implement Tempo Service (ports 3200, 4317, 4318) in `cdk8s/charts/infra/lgtm-tempo-chart.ts`

### Pyroscope Implementation (Profiles Storage)

- [ ] T019 Implement Pyroscope PVC (10Gi) in `cdk8s/charts/infra/lgtm-pyroscope-chart.ts`
- [ ] T020 Implement Pyroscope Deployment with filesystem storage in `cdk8s/charts/infra/lgtm-pyroscope-chart.ts`
- [ ] T021 Implement Pyroscope Service (port 4040) in `cdk8s/charts/infra/lgtm-pyroscope-chart.ts`

### Chart Registration

- [ ] T022 Register all 4 backend charts in `cdk8s/lib/auto-register-charts.ts`
- [ ] T023 Add backend applications to `cdk8s/config/applications.ts` with syncWave -60

**Checkpoint**: Backends ready - OTEL Collector can now route data to them

---

## Phase 3: User Story 5 - Tailscale Network Exposure (Priority: P1) 🎯 MVP-CRITICAL

**Goal**: Expose OTEL Collector and Grafana via Tailscale for workstation telemetry ingestion

**Independent Test**: Run `curl -I https://otel-collector-<cluster>.tail286401.ts.net/v1/traces` from a Tailscale-connected device

**Why First**: Without Tailscale exposure, workstations cannot send data. Must be deployed alongside OTEL Collector.

### Implementation for User Story 5

- [ ] T024 [US5] Add otel-collector-tailscale-serve entry in `cdk8s/config/applications.ts` using TailscaleServeChart
- [ ] T025 [US5] Add grafana-tailscale-serve entry in `cdk8s/config/applications.ts` using TailscaleServeChart
- [ ] T026 [US5] Add mimir-tailscale-serve entry in `cdk8s/config/applications.ts` using TailscaleServeChart
- [ ] T027 [US5] Verify Tailscale serve chart props match service names and ports in data-model.md

**Checkpoint**: Tailscale services configured - external access will work once services deploy

---

## Phase 4: User Story 1 - System Metrics Dashboard (Priority: P1) 🎯 MVP

**Goal**: View real-time and historical system metrics from all workstations in Grafana

**Independent Test**: Send test metrics via OTLP, query `test_counter{host="thinkpad"}` in Grafana within 30s

### OTEL Collector (Metrics Pipeline)

- [ ] T028 [US1] Create OTEL Collector chart skeleton in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`
- [ ] T029 [US1] Implement OTEL Collector ConfigMap with prometheusremotewrite exporter to Mimir in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`
- [ ] T030 [US1] Implement OTEL Collector Deployment (stateless) in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`
- [ ] T031 [US1] Implement OTEL Collector Service (ports 4317, 4318, 8888) in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`
- [ ] T032 [US1] Register OTEL Collector chart in `cdk8s/lib/auto-register-charts.ts`
- [ ] T033 [US1] Add lgtm-otel-collector application to `cdk8s/config/applications.ts` with syncWave -55

### Grafana (Metrics Visualization)

- [ ] T034 [US1] Create Grafana chart skeleton in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T035 [US1] Implement Grafana datasources ConfigMap with Mimir (Prometheus) datasource in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T036 [US1] Implement Grafana Deployment with datasource provisioning volume in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T037 [US1] Implement Grafana Service (port 3000) in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T038 [US1] Register Grafana chart in `cdk8s/lib/auto-register-charts.ts`
- [ ] T039 [US1] Add lgtm-grafana application to `cdk8s/config/applications.ts` with syncWave -50

**Checkpoint**: Metrics pipeline complete - workstations can send metrics, viewable in Grafana

---

## Phase 5: User Story 2 - Distributed Tracing (Priority: P1)

**Goal**: View distributed traces from applications and AI assistant sessions

**Independent Test**: Send trace via OTLP, search by trace ID in Grafana Tempo within 5s

### OTEL Collector (Traces Pipeline)

- [ ] T040 [US2] Add otlp/tempo exporter to OTEL Collector ConfigMap in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`
- [ ] T041 [US2] Add traces pipeline to OTEL Collector service.pipelines in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`

### Grafana (Traces Visualization)

- [ ] T042 [US2] Add Tempo datasource to Grafana datasources ConfigMap in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T043 [US2] Configure tracesToLogs correlation in Tempo datasource jsonData in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T044 [US2] Configure tracesToMetrics correlation in Tempo datasource jsonData in `cdk8s/charts/infra/lgtm-grafana-chart.ts`

**Checkpoint**: Traces pipeline complete - traces visible in Grafana with correlation to logs/metrics

---

## Phase 6: User Story 3 - Centralized Log Search (Priority: P2)

**Goal**: Search and analyze logs from all workstations in one place

**Independent Test**: Send log entry via OTLP, search `{host="thinkpad"}` in Loki within 30s

### OTEL Collector (Logs Pipeline)

- [ ] T045 [US3] Add loki exporter to OTEL Collector ConfigMap in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`
- [ ] T046 [US3] Add logs pipeline to OTEL Collector service.pipelines in `cdk8s/charts/infra/lgtm-otel-collector-chart.ts`

### Grafana (Logs Visualization)

- [ ] T047 [US3] Add Loki datasource to Grafana datasources ConfigMap in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T048 [US3] Configure derivedFields for trace_id extraction in Loki datasource in `cdk8s/charts/infra/lgtm-grafana-chart.ts`

**Checkpoint**: Logs pipeline complete - logs searchable in Grafana with trace correlation

---

## Phase 7: User Story 4 - Performance Profiling (Priority: P3)

**Goal**: View CPU and memory profiles for Python services

**Independent Test**: Configure app with Pyroscope SDK, verify flame graph in Grafana

### Grafana (Profiles Visualization)

- [ ] T049 [US4] Add Pyroscope datasource to Grafana datasources ConfigMap in `cdk8s/charts/infra/lgtm-grafana-chart.ts`
- [ ] T050 [US4] Configure tracesToProfiles correlation in Tempo datasource in `cdk8s/charts/infra/lgtm-grafana-chart.ts`

**Checkpoint**: Profiles pipeline complete - flame graphs visible in Grafana

---

## Phase 8: Legacy Removal & Cleanup

**Purpose**: Remove ClickHouse-based OTEL stack per FR-016 to FR-019

### Legacy Code Removal

- [ ] T051 Delete `cdk8s/charts/infra/otel-stack-chart.ts` (legacy ClickHouse-based stack)
- [ ] T052 Remove otel-stack application entry from `cdk8s/config/applications.ts`
- [ ] T053 Remove any otel-stack imports from `cdk8s/lib/auto-register-charts.ts`

### Verification

- [ ] T054 Run `npm run synth` in `cdk8s/` to verify all charts compile
- [ ] T055 Verify generated manifests in `cdk8s/dist/lgtm-*/` contain expected resources
- [ ] T056 Run `kubectl diff -f cdk8s/dist/lgtm-mimir/manifests/` to preview deployment changes

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T057 [P] Validate OTEL Collector config matches `specs/111-configure-k8s-observability/contracts/otel-collector-config.yaml`
- [ ] T058 [P] Validate Grafana datasources match `specs/111-configure-k8s-observability/contracts/grafana-datasources.yaml`
- [ ] T059 Run quickstart.md verification steps to confirm deployment works
- [ ] T060 Verify Langfuse applications remain unaffected in `cdk8s/config/applications.ts`

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1: Setup
    ↓
Phase 2: Foundational (backends) ─────────────────────────┐
    ↓                                                      │
Phase 3: US5 (Tailscale) ──────────────────────────────────┤
    ↓                                                      │
Phase 4: US1 (Metrics) - Requires OTEL Collector + Grafana │
    ↓                                                      │
Phase 5: US2 (Traces) - Extends OTEL + Grafana configs     │
    ↓                                                      │
Phase 6: US3 (Logs) - Extends OTEL + Grafana configs       │
    ↓                                                      │
Phase 7: US4 (Profiles) - Extends Grafana config only      │
    ↓                                                      │
Phase 8: Legacy Removal ───────────────────────────────────┘
    ↓
Phase 9: Polish
```

### User Story Dependencies

- **US5 (Tailscale)**: Can start after Phase 2 - REQUIRED for external access
- **US1 (Metrics)**: Can start after Phase 2 - Creates OTEL Collector + Grafana charts
- **US2 (Traces)**: Depends on US1 - Extends existing OTEL/Grafana configs
- **US3 (Logs)**: Depends on US1 - Extends existing OTEL/Grafana configs
- **US4 (Profiles)**: Depends on US1 - Extends Grafana config only

### Parallel Opportunities

Phase 2 (Backend Charts):
```bash
# All backend chart skeletons can be created in parallel:
Task: T003 - Create Mimir chart skeleton
Task: T004 - Create Loki chart skeleton
Task: T005 - Create Tempo chart skeleton
Task: T006 - Create Pyroscope chart skeleton
```

Phase 3 (Tailscale):
```bash
# All Tailscale entries can be added in parallel:
Task: T024 - Add otel-collector-tailscale-serve
Task: T025 - Add grafana-tailscale-serve
Task: T026 - Add mimir-tailscale-serve
```

---

## Implementation Strategy

### MVP First (US1 + US5 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational - All 4 backends (T003-T023)
3. Complete Phase 3: US5 Tailscale (T024-T027)
4. Complete Phase 4: US1 Metrics (T028-T039)
5. **STOP and VALIDATE**: Deploy via ArgoCD, send test metrics, verify in Grafana
6. Deploy/demo MVP with metrics working

### Incremental Delivery

1. MVP → Metrics + Tailscale working
2. Add US2 (Traces) → Test trace search → Deploy
3. Add US3 (Logs) → Test log search → Deploy
4. Add US4 (Profiles) → Test flame graphs → Deploy
5. Phase 8: Remove legacy ClickHouse stack
6. Phase 9: Final validation

### Single Developer Strategy

Execute in phase order:
1. Phases 1-2: Foundation (~30 minutes)
2. Phases 3-4: MVP delivery (~45 minutes)
3. Phases 5-7: Full LGTM stack (~30 minutes)
4. Phases 8-9: Cleanup + validation (~15 minutes)

Total estimated time: ~2 hours for full implementation

---

## Summary

| Phase | Tasks | Parallel Tasks | Story Coverage |
|-------|-------|----------------|----------------|
| 1: Setup | 2 | 1 | Foundation |
| 2: Foundational | 21 | 4 | All backends |
| 3: US5 Tailscale | 4 | 3 | P1 |
| 4: US1 Metrics | 12 | 0 | P1 |
| 5: US2 Traces | 5 | 0 | P1 |
| 6: US3 Logs | 4 | 0 | P2 |
| 7: US4 Profiles | 2 | 0 | P3 |
| 8: Legacy Removal | 6 | 0 | FR-016-019 |
| 9: Polish | 4 | 2 | Validation |
| **Total** | **60** | **10** | **All 5 stories** |

**MVP Scope**: Phases 1-4 (39 tasks) deliver working metrics pipeline with Tailscale access

**Suggested Execution**: Complete Phases 1-4 first, validate, then continue to remaining phases
