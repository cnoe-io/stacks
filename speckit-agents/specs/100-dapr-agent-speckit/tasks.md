# Tasks: SpecKit Agent Observability

**Feature ID:** 100-dapr-agent-speckit-observability
**Branch:** 100-dapr-agent-speckit
**Generated:** 2025-12-03

---

## Task Summary

| Phase | Description | Task Count |
|-------|-------------|------------|
| Phase 1 | Setup & Prerequisites | 3 |
| Phase 2 | Foundational Infrastructure | 6 |
| Phase 3 | FR-1: Distributed Tracing (Jaeger) | 4 |
| Phase 4 | FR-2: LLM Observability (Langfuse) | 5 |
| Phase 5 | FR-3: Dapr Tracing Configuration | 3 |
| Phase 6 | FR-4/FR-5: Access (Ingress & Tailscale) | 2 |
| Phase 7 | FR-7: Agent Instrumentation | 4 |
| Phase 8 | Polish & Verification | 4 |
| **Total** | | **31** |

---

## Phase 1: Setup & Prerequisites

**Goal:** Prepare secrets and validate environment before infrastructure deployment.

### Tasks

- [x] T001 Generate Langfuse secrets and add to Azure Key Vault using `az keyvault secret set` commands
- [x] T002 Verify External Secrets Operator is healthy with `kubectl get pods -n external-secrets`
- [x] T003 Verify Tailscale Operator is healthy with `kubectl get pods -n tailscale`

### Completion Criteria
- All 7 Langfuse secrets exist in Azure Key Vault
- ESO and Tailscale operators are Running

---

## Phase 2: Foundational Infrastructure

**Goal:** Create namespace and secrets chart that other components depend on.

### Tasks

- [x] T004 [P] Create observability namespace chart in `cdk8s/charts/infra/observability-namespace-chart.ts`
- [x] T005 [P] Create observability secrets chart with ExternalSecrets in `cdk8s/charts/secrets/observability-secrets-chart.ts`
- [x] T006 Add ObservabilityNamespaceChart application config to `cdk8s/config/applications.ts` with syncWave -70
- [x] T007 Add ObservabilitySecretsChart application config to `cdk8s/config/applications.ts` with syncWave -75
- [x] T008 Register ObservabilityNamespaceChart in `cdk8s/lib/idpbuilder-chart-factory.ts` (auto-registered)
- [x] T009 Register ObservabilitySecretsChart in `cdk8s/lib/idpbuilder-chart-factory.ts` (auto-registered)

### Completion Criteria
- `npx ts-node main-v2.ts` succeeds
- `dist/observability-namespace/` and `dist/observability-secrets/` generated

---

## Phase 3: FR-1 - Distributed Tracing with Jaeger

**Goal:** Deploy Jaeger all-in-one with persistent Badger storage.

**Maps to:** FR-1.1, FR-1.2, FR-1.6 (Jaeger collector, query UI, sampling config)

### Tasks

- [x] T010 [P] [FR1] Create Jaeger chart with PVC, Deployment, Services in `cdk8s/charts/infra/jaeger-chart.ts`
- [x] T011 [FR1] Add JaegerChart application config to `cdk8s/config/applications.ts` with syncWave -65
- [x] T012 [FR1] Register JaegerChart in `cdk8s/lib/idpbuilder-chart-factory.ts` (auto-registered)
- [x] T013 [FR1] Add Jaeger Ingress resource to jaeger-chart.ts for `jaeger-<cluster>.cnoe.localtest.me`

### Completion Criteria
- Jaeger deployment YAML includes: PVC (10Gi), Deployment (jaegertracing/all-in-one:1.66.0), Services (query:16686, collector:9411)
- Badger environment variables configured for 7-day retention
- Ingress routes to jaeger-query service

---

## Phase 4: FR-2 - LLM Observability with Langfuse

**Goal:** Deploy Langfuse self-hosted with dedicated PostgreSQL.

**Maps to:** FR-2.1 (Langfuse server stores LLM data)

### Tasks

- [x] T014 [P] [FR2] Create Langfuse PostgreSQL chart with PVC, Deployment, Service in `cdk8s/charts/infra/langfuse-postgres-chart.ts`
- [x] T015 [P] [FR2] Create Langfuse chart with Deployment, Service in `cdk8s/charts/infra/langfuse-chart.ts`
- [x] T016 [FR2] Add LangfusePostgresChart application config to `cdk8s/config/applications.ts` with syncWave -65
- [x] T017 [FR2] Add LangfuseChart application config to `cdk8s/config/applications.ts` with syncWave -60
- [x] T018 [FR2] Register LangfusePostgresChart and LangfuseChart in `cdk8s/lib/idpbuilder-chart-factory.ts` (auto-registered)

### Completion Criteria
- PostgreSQL deployment with 20Gi PVC, postgres:16-alpine image
- Langfuse deployment with langfuse/langfuse:2.95.1 image (v2.x, PostgreSQL-only, no ClickHouse)
- Langfuse has DATABASE_URL, NEXTAUTH_URL, NEXTAUTH_SECRET, SALT, ENCRYPTION_KEY env vars from secrets
- Ingress routes to langfuse service on port 3000

---

## Phase 5: FR-3 - Dapr Tracing Configuration

**Goal:** Configure Dapr to emit traces to Jaeger via Zipkin protocol.

**Maps to:** FR-3.1, FR-3.2, FR-3.3, FR-3.4, FR-3.5

### Tasks

- [x] T019 [FR3] Create Dapr tracing config chart with Configuration CRD in `cdk8s/charts/infra/dapr-tracing-config-chart.ts`
- [x] T020 [FR3] Add DaprTracingConfigChart application config to `cdk8s/config/applications.ts` with syncWave -55
- [x] T021 [FR3] Register DaprTracingConfigChart in `cdk8s/lib/idpbuilder-chart-factory.ts` (auto-registered)

### Completion Criteria
- Dapr Configuration CRD created in `dapr-agents` namespace
- samplingRate set to "1" (100%)
- Zipkin endpoint points to `jaeger-collector.observability.svc.cluster.local:9411`

---

## Phase 6: FR-4/FR-5 - Access (Ingress & Tailscale)

**Goal:** Enable local and remote access to observability UIs.

**Maps to:** FR-4.1, FR-4.2, FR-5.1, FR-5.2

### Tasks

- [x] T022 [P] [FR4] Add Jaeger and Langfuse Ingress resources to their respective charts (done in T013/T015)
- [x] T023 [FR5] Update ingress-tailscale-publish-chart.ts to add jaeger and langfuse hosts in `cdk8s/charts/platform/ingress-tailscale-publish-chart.ts`

### Completion Criteria
- Ingresses created for jaeger-<cluster>.cnoe.localtest.me and langfuse-<cluster>.cnoe.localtest.me
- Tailscale LoadBalancer services created: ts-jaeger-ingress, ts-langfuse-ingress

---

## Phase 7: FR-7 - Agent Instrumentation

**Goal:** Instrument SpecKit agents to emit Langfuse traces for LLM calls.

**Maps to:** FR-7.1, FR-7.2, FR-7.3, FR-7.4, FR-7.5

### Tasks

- [x] T024 [FR7] Add langfuse>=2.50.0 to `speckit-agents/requirements.txt`
- [x] T025 [FR7] Create observability module with Langfuse client in `speckit-agents/src/common/observability.py`
- [x] T026 [FR7] Update agent base class to use @observe() decorator in `speckit-agents/src/agents/base.py` (NOTE: observe_llm_call imported; dapr-agents SDK handles LLM calls internally via DurableAgent)
- [x] T027 [FR7] Update speckit-agents-chart.ts to add dapr.io/config annotation in `cdk8s/charts/apps/speckit-agents-chart.ts`

### Completion Criteria
- Agents have LANGFUSE_HOST, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY env vars
- Agents reference `speckit-tracing` Dapr Configuration
- LLM calls wrapped with @observe() decorator

---

## Phase 8: Polish & Verification

**Goal:** Deploy, verify, and validate all success criteria.

### Tasks

- [x] T028 Synthesize all charts with `npx ts-node main-v2.ts` in cdk8s directory
- [x] T029 Deploy observability stack with `cluster-update` command
- [x] T030 Verify Jaeger UI loads at https://jaeger-<cluster>.cnoe.localtest.me:8443 and shows services
- [x] T031 Verify Langfuse UI loads at https://langfuse-<cluster>.cnoe.localtest.me:8443 and shows traces after workflow

### Completion Criteria
- All pods in observability namespace are Running
- Jaeger shows SpecKit agent services
- Langfuse shows LLM generations
- Remote access works via Tailscale

---

## Dependency Graph

```
Phase 1 (Setup)
    │
    ▼
Phase 2 (Foundational) ─────────────────────────────────────────────┐
    │                                                                │
    ├─────────────┬─────────────┬─────────────┐                     │
    ▼             ▼             ▼             ▼                     │
Phase 3       Phase 4       Phase 5       Phase 6                   │
(Jaeger)     (Langfuse)    (Dapr Config)  (Access)                  │
    │             │             │             │                     │
    └─────────────┴─────────────┴─────────────┘                     │
                        │                                           │
                        ▼                                           │
                    Phase 7 ◄───────────────────────────────────────┘
              (Agent Instrumentation)
                        │
                        ▼
                    Phase 8
                  (Verification)
```

---

## Parallel Execution Opportunities

### Within Phase 2 (Foundational)
```bash
# These can run in parallel (different files, no dependencies)
T004: observability-namespace-chart.ts  # [P]
T005: observability-secrets-chart.ts    # [P]
```

### Within Phase 3-4 (Infrastructure)
```bash
# After Phase 2 completes, these can run in parallel
T010: jaeger-chart.ts        # [P] [FR1]
T014: langfuse-postgres-chart.ts  # [P] [FR2]
T015: langfuse-chart.ts      # [P] [FR2]
```

### Cross-Phase Parallelism
```bash
# Phase 3, 4, 5, 6 can all proceed in parallel after Phase 2
# Only Phase 7 requires all infrastructure to be registered
```

---

## Implementation Strategy

### MVP Scope (Minimum Viable Observability)
**Phases 1-3 only:** Deploy Jaeger for distributed tracing

- Provides immediate value: trace visualization
- No agent code changes required
- Can verify Dapr tracing is working
- Langfuse can be added incrementally

### Incremental Delivery
1. **Week 1:** Phases 1-3 (Jaeger + Dapr tracing)
2. **Week 2:** Phases 4-5 (Langfuse infrastructure)
3. **Week 3:** Phases 6-7 (Access + Agent instrumentation)
4. **Week 4:** Phase 8 (Polish + Verification)

---

## File Summary

### New Files (CDK8s) - 6 files
| File | Phase | FR |
|------|-------|-----|
| `cdk8s/charts/infra/observability-namespace-chart.ts` | 2 | - |
| `cdk8s/charts/secrets/observability-secrets-chart.ts` | 2 | - |
| `cdk8s/charts/infra/jaeger-chart.ts` | 3 | FR-1 |
| `cdk8s/charts/infra/langfuse-postgres-chart.ts` | 4 | FR-2 |
| `cdk8s/charts/infra/langfuse-chart.ts` | 4 | FR-2 |
| `cdk8s/charts/infra/dapr-tracing-config-chart.ts` | 5 | FR-3 |

### Modified Files (CDK8s) - 3 files
| File | Tasks |
|------|-------|
| `cdk8s/config/applications.ts` | T006, T007, T011, T016, T017, T020 |
| `cdk8s/lib/idpbuilder-chart-factory.ts` | T008, T009, T012, T018, T021 |
| `cdk8s/charts/platform/ingress-tailscale-publish-chart.ts` | T023 |

### New Files (Agents) - 1 file
| File | Phase | FR |
|------|-------|-----|
| `speckit-agents/src/common/observability.py` | 7 | FR-7 |

### Modified Files (Agents) - 2 files
| File | Tasks |
|------|-------|
| `speckit-agents/requirements.txt` | T024 |
| `speckit-agents/src/agents/base.py` | T026 |

### Modified Files (CDK8s Agents) - 1 file
| File | Tasks |
|------|-------|
| `cdk8s/charts/apps/speckit-agents-chart.ts` | T027 |

---

## Validation Checklist

After completing all tasks, verify:

- [ ] All 31 tasks completed
- [ ] All 6 new CDK8s chart files created
- [ ] All 3 CDK8s config files updated
- [ ] 1 new Python module created
- [ ] 2 Python files updated
- [ ] `npx ts-node main-v2.ts` succeeds without errors
- [ ] `cluster-update` deploys all observability components
- [ ] Jaeger UI accessible locally and via Tailscale
- [ ] Langfuse UI accessible locally and via Tailscale
- [ ] Traces appear in Jaeger after workflow submission
- [ ] LLM generations appear in Langfuse after workflow submission
