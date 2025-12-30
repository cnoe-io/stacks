# Tasks: Feature Flagging System

**Input**: Design documents from `/specs/115-feature-flags/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in feature specification - test tasks omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md structure:
- CDK8s charts: `cdk8s/charts/infra/`, `cdk8s/charts/secrets/`, `cdk8s/charts/platform/`
- Configuration: `cdk8s/config/applications.ts`
- External repo: `feature-flags/` (created separately for flag configurations)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Namespace creation and project structure validation

- [X] T001 Verify OpenFeature CRD imports exist in cdk8s/imports/core.openfeature.dev.ts
- [X] T002 [P] Create feature-flags namespace chart in cdk8s/charts/infra/feature-flags-namespace-chart.ts
- [X] T003 [P] Add namespace entry to cdk8s/config/applications.ts with syncWave -110

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: External Secrets and Keycloak client configuration that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Create Keycloak client `flipt` in cnoe realm (confidential, OIDC)
- [ ] T005 [P] Store Flipt client secret in Azure Key Vault
- [X] T006 [P] Create feature-flags-secrets chart in cdk8s/charts/secrets/feature-flags-secrets-chart.ts
- [X] T007 Add ExternalSecret for Flipt OIDC client credentials in feature-flags-secrets-chart.ts
- [X] T008 [P] Add ExternalSecret for Git repository credentials in feature-flags-secrets-chart.ts
- [X] T009 Add secrets entry to cdk8s/config/applications.ts with syncWave -85

**Checkpoint**: Foundation ready - flagd and Flipt deployments can now be created

---

## Phase 3: User Story 1 - Platform Operator Deploys Feature Flag Infrastructure (Priority: P1) MVP

**Goal**: Deploy complete feature flagging infrastructure (OpenFeature operator, flagd, Flipt) via single ArgoCD sync

**Independent Test**: Run `kubectl get pods -n feature-flags` and verify flagd and flipt pods are Running; access Flipt UI via port-forward

### Implementation for User Story 1

- [X] T010 [P] [US1] Create flagd Deployment spec in cdk8s/charts/infra/flagd-chart.ts
- [X] T011 [P] [US1] Create Flipt Deployment spec in cdk8s/charts/infra/flipt-chart.ts
- [X] T012 [US1] Add flagd ClusterIP Service (ports 8013, 8016) in flagd-chart.ts
- [X] T013 [US1] Add Flipt ClusterIP Service (port 8080) in flipt-chart.ts
- [X] T014 [US1] Configure flagd sync source to connect to Flipt gRPC in flagd-chart.ts
- [X] T015 [US1] Configure Flipt OIDC authentication with Keycloak in flipt-chart.ts
- [X] T016 [US1] Configure Flipt Git backend storage in flipt-chart.ts
- [X] T017 [US1] Add health probes (liveness, readiness) to flagd deployment in flagd-chart.ts
- [X] T018 [US1] Add health probes (liveness, readiness) to Flipt deployment in flipt-chart.ts
- [X] T019 [US1] Configure resource requests/limits per plan.md specs in both charts
- [X] T020 [P] [US1] Add flagd entry to cdk8s/config/applications.ts with syncWave -75
- [X] T021 [P] [US1] Add flipt entry to cdk8s/config/applications.ts with syncWave -75

**Checkpoint**: At this point, `npm run synth && kubectl apply -f dist/` should deploy working flagd and Flipt

---

## Phase 4: User Story 2 - Developer Creates and Manages Feature Flags via UI (Priority: P1)

**Goal**: Enable developers to create, edit, and manage feature flags through Flipt web interface

**Independent Test**: Log into Flipt UI, create boolean flag "test-flag", verify it appears in flag list

### Implementation for User Story 2

- [X] T022 [US2] Create feature-flags Git repository in Gitea with README.md
- [X] T023 [US2] Add .flipt.yml configuration file to feature-flags repository
- [X] T024 [P] [US2] Create flags/development.yaml with sample flag definition in feature-flags repo
- [X] T025 [P] [US2] Create flags/staging.yaml with sample flag definition in feature-flags repo
- [X] T026 [P] [US2] Create flags/production.yaml with sample flag definition in feature-flags repo
- [X] T027 [US2] Configure Flipt namespaces for development, staging, production in flipt-chart.ts
- [ ] T028 [US2] Configure RBAC: developer role maps to dev/staging write access in flipt-chart.ts
- [ ] T029 [US2] Configure RBAC: platform-team role maps to all environments in flipt-chart.ts
- [ ] T030 [US2] Test flag creation via UI and verify Git commit in repository

**Checkpoint**: Developers can log in, create flags, and see changes committed to Git

---

## Phase 5: User Story 3 - Application Consumes Feature Flags at Runtime (Priority: P1)

**Goal**: Applications can evaluate feature flags at runtime via OpenFeature SDK

**Independent Test**: Deploy sample app, call flagd endpoint, verify correct flag value returned

### Implementation for User Story 3

- [X] T031 [P] [US3] Document SDK integration for Go applications in specs/115-feature-flags/quickstart.md
- [X] T032 [P] [US3] Document SDK integration for TypeScript applications in quickstart.md
- [X] T033 [P] [US3] Document SDK integration for Python applications in quickstart.md
- [X] T034 [US3] Create sample test script to verify flagd gRPC endpoint connectivity
- [X] T035 [US3] Create sample test script to verify flagd OFREP endpoint connectivity
- [X] T036 [US3] Verify flag evaluation returns correct value based on targeting rules
- [X] T037 [US3] Verify SDK fallback to default values when flagd unavailable
- [X] T038 [US3] Verify flag changes propagate within 30 seconds (SC-004)

**Checkpoint**: Applications can connect to flagd and evaluate flags with correct values

---

## Phase 6: User Story 4 - Developer Manages Flags via GitOps Workflow (Priority: P2)

**Goal**: Enable PR-based flag management with automatic sync to Flipt

**Independent Test**: Create PR with flag change, merge, verify Flipt reflects change within 30s

### Implementation for User Story 4

- [X] T039 [US4] Configure Flipt Git sync poll interval (30s) in flipt-chart.ts
- [X] T040 [US4] Document GitOps workflow for flag changes in quickstart.md
- [ ] T041 [US4] Add flag schema validation to feature-flags repository CI
- [ ] T042 [US4] Test PR workflow: create flag change PR, review, merge, verify sync
- [ ] T043 [US4] Configure Flipt read-only mode when Git is source of truth

**Checkpoint**: PR-based flag management works with automatic sync

---

## Phase 7: User Story 5 - Platform Team Views Flag Analytics and Audit Trail (Priority: P2)

**Goal**: Enable observability of flag usage and audit trail of changes

**Independent Test**: Evaluate flags, view metrics in Grafana; change flag, view audit log in Flipt

### Implementation for User Story 5

- [X] T044 [US5] Configure flagd OTLP exporter to otel-collector in flagd-chart.ts
- [X] T045 [US5] Configure Flipt audit logging in flipt-chart.ts
- [ ] T046 [P] [US5] Create Grafana dashboard for flag evaluation metrics
- [ ] T047 [US5] Add ServiceMonitor for flagd metrics endpoint in flagd-chart.ts
- [ ] T048 [US5] Verify audit events appear in Flipt UI after flag changes
- [ ] T049 [US5] Verify flag evaluation traces appear in Jaeger/tracing backend

**Checkpoint**: Metrics visible in Grafana, audit trail visible in Flipt UI

---

## Phase 8: User Story 6 - Multi-Environment Flag Management (Priority: P3)

**Goal**: Enable environment-specific flag configurations across clusters

**Independent Test**: Set different flag values per environment, verify correct values in each

### Implementation for User Story 6

- [ ] T050 [US6] Configure Flipt namespace per environment mapping in flipt-chart.ts
- [ ] T051 [US6] Document environment promotion workflow in quickstart.md
- [ ] T052 [P] [US6] Create hub cluster flagd deployment configuration
- [ ] T053 [P] [US6] Create spoke cluster flagd deployment configuration (Tailscale connectivity)
- [ ] T054 [US6] Test flag evaluation returns environment-specific values
- [ ] T055 [US6] Document cross-cluster flag sync architecture in quickstart.md

**Checkpoint**: Different environments have independent flag configurations

---

## Phase 9: Tailscale Service Exposure

**Purpose**: Remote access to flagd and Flipt via Tailscale

- [X] T056 [P] Create flipt-tailscale-serve-chart.ts in cdk8s/charts/platform/ (using TailscaleServeChart)
- [ ] T057 [P] Create flagd-tailscale-serve-chart.ts in cdk8s/charts/platform/ (optional)
- [X] T058 Add Tailscale chart entries to cdk8s/config/applications.ts with syncWave -60
- [ ] T059 Verify Flipt UI accessible at flipt-{cluster}.ts.net

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T060 [P] Update specs/115-feature-flags/quickstart.md with complete deployment steps
- [ ] T061 [P] Add troubleshooting section to quickstart.md
- [ ] T062 Run full synthesis and validate all manifests: `npm run synth`
- [ ] T063 Verify ArgoCD sync completes successfully
- [ ] T064 Run performance validation: 1000 evaluations/second (SC-003)
- [ ] T065 Security review: verify no secrets in generated manifests
- [ ] T066 Document flag naming conventions and best practices

---

## Phase 11: User Story 7 - CAIPE/Backstage Feature Flag Integration (Priority: P1)

**Goal**: Enable dynamic control of CAIPE agents and Backstage features via feature flags

**Independent Test**: Toggle CAIPE agent flags and verify behavior changes; toggle Backstage flags and verify UI changes

### Phase 11a: Flag Definitions (Infrastructure)

- [X] T067 [US7] Add CAIPE agent flags to flagd ConfigMap (caipe-agents-enabled, caipe-agent-argocd, caipe-agent-github, caipe-agent-backstage)
- [X] T068 [US7] Add CAIPE feature flags to flagd ConfigMap (caipe-deep-orchestration, caipe-artifact-streaming)
- [X] T069 [US7] Add observability flags to flagd ConfigMap (langfuse-tracing-enabled, otel-trace-sampling-rate, verbose-agent-logging)
- [X] T070 [US7] Add rate limit flags to flagd ConfigMap (caipe-rate-limit, llm-token-limit, agent-timeout-seconds)
- [X] T071 [US7] Add Backstage flags to flagd ConfigMap (backstage-agentforge-enabled, backstage-agentforge-suggestions, backstage-external-api-access)
- [X] T072 [US7] Add targeting segments to flagd ConfigMap (caipe-testers group, premium tier)

**Checkpoint**: All CAIPE/Backstage flags defined and evaluable via flagd ✓

### Phase 11b: Test Scripts & Validation

- [X] T073 [US7] Create test script to verify CAIPE flags evaluate correctly: scripts/feature-flags/test-caipe-flags.sh
- [X] T074 [US7] Create test script to verify Backstage flags evaluate correctly (included in test-caipe-flags.sh)
- [X] T075 [US7] Verify flag changes for CAIPE propagate within 30 seconds (flagd file watcher confirmed)
- [X] T076 [US7] Document flag toggle procedures for emergency agent disable: scripts/feature-flags/EMERGENCY-PROCEDURES.md

**Checkpoint**: All CAIPE/Backstage flags tested and documented ✓

### Phase 11c: SDK Integration Documentation

- [ ] T077 [P] [US7] Document Python SDK integration for CAIPE supervisor in quickstart.md
- [ ] T078 [P] [US7] Add Python code example for agent routing with flags
- [ ] T079 [P] [US7] Document TypeScript SDK integration for Backstage backend in quickstart.md
- [ ] T080 [P] [US7] Add TypeScript code example for AgentForge feature toggle

**Checkpoint**: SDK integration fully documented for both CAIPE and Backstage

### Phase 11d: Future Code Integration (Separate PR)

These tasks require changes to CAIPE and Backstage codebases:

- [ ] T081 [US7] [FUTURE] Add openfeature-sdk-python to CAIPE supervisor requirements.txt
- [ ] T082 [US7] [FUTURE] Implement flag provider initialization in CAIPE supervisor startup
- [ ] T083 [US7] [FUTURE] Add flag checks in CAIPE supervisor agent routing logic
- [ ] T084 [US7] [FUTURE] Add @openfeature/server-sdk to Backstage package.json
- [ ] T085 [US7] [FUTURE] Implement flag provider in Backstage backend
- [ ] T086 [US7] [FUTURE] Add AgentForge visibility toggle based on flag

**Checkpoint**: CAIPE and Backstage consume feature flags at runtime

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational phase - core infrastructure
- **User Story 2 (Phase 4)**: Depends on US1 (flagd/Flipt deployed) - flag management
- **User Story 3 (Phase 5)**: Depends on US1 (flagd deployed) - runtime evaluation
- **User Story 4 (Phase 6)**: Depends on US2 (Git repo configured) - GitOps workflow
- **User Story 5 (Phase 7)**: Depends on US1 (flagd deployed) - observability
- **User Story 6 (Phase 8)**: Depends on US1-US2 complete - multi-environment
- **Tailscale (Phase 9)**: Depends on US1 (services exist) - external access
- **Polish (Phase 10)**: Depends on desired user stories complete
- **User Story 7 (Phase 11)**: Depends on US1+US3 complete - CAIPE/Backstage integration

### User Story Dependencies

- **User Story 1 (P1)**: Foundation → Deploy flagd + Flipt (MVP baseline)
- **User Story 2 (P1)**: US1 → Configure Git repo and UI access
- **User Story 3 (P1)**: US1 → SDK integration and evaluation
- **User Story 4 (P2)**: US2 → GitOps workflow
- **User Story 5 (P2)**: US1 → Observability integration
- **User Story 6 (P3)**: US1+US2 → Multi-environment
- **User Story 7 (P1)**: US1+US3 → CAIPE/Backstage feature flag integration

### Within Each User Story

- Charts before services
- Configuration before deployment
- Deployment before validation
- Validation before checkpoint

### Parallel Opportunities

Within Phase 3 (US1):
- T010 (flagd chart) and T011 (flipt chart) can run in parallel
- T020 (flagd config) and T021 (flipt config) can run in parallel

Within Phase 4 (US2):
- T024, T025, T026 (environment configs) can run in parallel

Within Phase 5 (US3):
- T031, T032, T033 (SDK docs) can run in parallel

Within Phase 7 (US5):
- T046 (Grafana dashboard) and other observability tasks

Within Phase 8 (US6):
- T052 (hub config) and T053 (spoke config) can run in parallel

---

## Parallel Example: User Story 1 (Phase 3)

```bash
# Launch chart implementations in parallel:
Task: "Create flagd Deployment spec in cdk8s/charts/infra/flagd-chart.ts"
Task: "Create Flipt Deployment spec in cdk8s/charts/infra/flipt-chart.ts"

# After services added, launch config updates in parallel:
Task: "Add flagd entry to cdk8s/config/applications.ts with syncWave -75"
Task: "Add flipt entry to cdk8s/config/applications.ts with syncWave -75"
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only)

1. Complete Phase 1: Setup (namespace)
2. Complete Phase 2: Foundational (secrets, Keycloak)
3. Complete Phase 3: User Story 1 (deploy flagd + Flipt)
4. **VALIDATE**: Pods running, Flipt UI accessible
5. Complete Phase 4: User Story 2 (flag management via UI)
6. Complete Phase 5: User Story 3 (SDK integration)
7. **STOP and VALIDATE**: Full MVP - flags can be created and evaluated
8. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational → Base infrastructure ready
2. Add User Story 1 → Validate → Infrastructure deployed (MVP foundation)
3. Add User Story 2 → Validate → Flag management working
4. Add User Story 3 → Validate → SDK integration working (Full MVP!)
5. Add User Story 4 → Validate → GitOps workflow
6. Add User Story 5 → Validate → Observability
7. Add User Story 6 → Validate → Multi-environment

### Critical Path

```
Setup → Foundational → US1 → US2 → US3 (MVP Complete)
                         ↘ US5 (Observability - can parallel with US2/US3)
                    US2 → US4 (GitOps - after Git repo setup)
              US1+US2 → US6 (Multi-env - after base complete)
```

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Each user story should be independently testable at its checkpoint
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Flag configurations stored in separate `feature-flags` Git repository (FR-009)
- Production namespace is protected and requires platform-team role (FR-015)
