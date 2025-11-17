# Tasks: Install kagent and kgateway with Agentgateway in Kubernetes

**Input**: Design documents from `/specs/008-install-kagent-agentgateway-kubernetes/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: No explicit test generation requested. Validation performed via ArgoCD sync status and kubectl health checks.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **CDK8s source**: `cdk8s/` directory
- **Charts**: `cdk8s/charts/infra/`, `cdk8s/charts/secrets/`, `cdk8s/charts/apps/`
- **Config**: `cdk8s/config/applications.ts`
- **Libraries**: `cdk8s/lib/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Remove deprecated kagent resources and prepare CDK8s environment

- [x] T001 Remove deprecated custom kagent charts from cdk8s/charts/infra/
- [x] T002 Remove deprecated kagent entries from cdk8s/config/applications.ts
- [x] T003 [P] Verify CDK8s dependencies in cdk8s/package.json (cdk8s, constructs versions)
- [x] T004 [P] Import kagent CRD types via npm run import in cdk8s/imports/kagent.dev.ts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core ArgoCD Application wrapper infrastructure that MUST be complete before user story charts

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Create ArgoCD Application helper for Helm charts in cdk8s/lib/helm-argocd-helpers.ts
- [x] T006 Update IdpBuilderChartFactory registration in cdk8s/main-v2.ts for new chart types
- [x] T007 [P] Verify ArgoCD sync wave constants are defined in cdk8s/lib/argocd-sync-builders.ts

**Checkpoint**: Foundation ready - user story chart implementation can now begin

---

## Phase 3: User Story 1 - Deploy kgateway with Agentgateway (Priority: P1) MVP

**Goal**: Deploy kgateway v2.2.0 with agentgateway enabled for MCP server gateway functionality

**Independent Test**: Verify kgateway control plane and gateway proxy pods are Running; Gateway resource can be created with agentgateway configuration

### Implementation for User Story 1

- [x] T008 [P] [US1] Create Gateway API CRDs chart in cdk8s/charts/infra/gateway-api-crds-chart.ts
- [x] T009 [P] [US1] Create kgateway CRDs chart in cdk8s/charts/infra/kgateway-crds-chart.ts
- [x] T010 [US1] Create kgateway main chart with agentGateway.enabled=true in cdk8s/charts/infra/kgateway-chart.ts
- [x] T011 [US1] Add gateway-api-crds entry to cdk8s/config/applications.ts with syncWave -130
- [x] T012 [US1] Add kgateway-crds entry to cdk8s/config/applications.ts with syncWave -125
- [x] T013 [US1] Add kgateway entry to cdk8s/config/applications.ts with syncWave -120
- [x] T014 [US1] Register Gateway API CRDs chart in cdk8s/main-v2.ts
- [x] T015 [US1] Register kgateway CRDs chart in cdk8s/main-v2.ts
- [x] T016 [US1] Register kgateway main chart in cdk8s/main-v2.ts
- [x] T017 [US1] Synthesize and validate gateway-api-crds package via npx ts-node main-v2.ts
- [x] T018 [US1] Synthesize and validate kgateway packages via npx ts-node main-v2.ts
- [ ] T019 [US1] Deploy Gateway API CRDs via idpbuilder create --package cdk8s/dist/gateway-api-crds
- [ ] T020 [US1] Deploy kgateway CRDs via idpbuilder create --package cdk8s/dist/kgateway-crds
- [ ] T021 [US1] Deploy kgateway via idpbuilder create --package cdk8s/dist/kgateway
- [ ] T022 [US1] Verify kgateway pods Running via kubectl get pods -n kgateway-system
- [ ] T023 [US1] Verify Gateway CRDs installed via kubectl get crds | grep gateway.networking.k8s.io

**Checkpoint**: kgateway with agentgateway is deployed and functional

---

## Phase 4: User Story 2 - Deploy kagent AI Agent Framework (Priority: P2)

**Goal**: Deploy kagent v0.7.4 with controller, UI, and kmcp components

**Independent Test**: Verify kagent controller and UI pods are Running; kagent CRDs are installed

### Implementation for User Story 2

- [x] T024 [P] [US2] Create kagent CRDs chart in cdk8s/charts/infra/kagent-crds-chart.ts
- [x] T025 [US2] Create kagent main chart with kmcp.enabled=true in cdk8s/charts/infra/kagent-chart.ts
- [x] T026 [US2] Add kagent-crds entry to cdk8s/config/applications.ts with syncWave -115
- [x] T027 [US2] Add kagent entry to cdk8s/config/applications.ts with syncWave -110
- [x] T028 [US2] Register kagent CRDs chart in cdk8s/main-v2.ts
- [x] T029 [US2] Register kagent main chart in cdk8s/main-v2.ts
- [x] T030 [US2] Synthesize and validate kagent packages via npx ts-node main-v2.ts
- [ ] T031 [US2] Deploy kagent CRDs via idpbuilder create --package cdk8s/dist/kagent-crds
- [ ] T032 [US2] Deploy kagent via idpbuilder create --package cdk8s/dist/kagent
- [ ] T033 [US2] Verify kagent controller pod Running via kubectl get pods -n kagent
- [ ] T034 [US2] Verify kagent UI pod Running via kubectl get pods -n kagent
- [ ] T035 [US2] Verify kagent CRDs installed via kubectl get crds | grep kagent.dev
- [ ] T036 [US2] Access kagent dashboard via https://kagent.cnoe.localtest.me:8443

**Checkpoint**: kagent framework is deployed with controller, UI, and kmcp operational

---

## Phase 5: User Story 3 - Configure LLM Provider Integration (Priority: P3)

**Goal**: Sync LLM API keys from Azure Key Vault via External Secrets Operator

**Independent Test**: Verify ExternalSecret syncs and ModelConfig resources can be created with Ready status

### Implementation for User Story 3

- [x] T037 [US3] Create kagent-secrets chart with ExternalSecret in cdk8s/charts/secrets/kagent-secrets-chart.ts
- [x] T038 [US3] Add kagent-secrets entry to cdk8s/config/applications.ts with syncWave -70
- [x] T039 [US3] Register kagent-secrets chart in cdk8s/main-v2.ts
- [x] T040 [US3] Synthesize and validate kagent-secrets package via npx ts-node main-v2.ts
- [ ] T041 [US3] Deploy kagent-secrets via idpbuilder create --package cdk8s/dist/kagent-secrets
- [ ] T042 [US3] Verify ExternalSecret synced via kubectl get externalsecret -n kagent kagent-llm-providers
- [ ] T043 [US3] Verify secret created via kubectl get secret -n kagent kagent-llm-providers
- [ ] T044 [US3] Verify secret keys exist via kubectl get secret -n kagent kagent-llm-providers -o jsonpath='{.data}' | jq -r 'keys'
- [ ] T045 [US3] Create default OpenAI ModelConfig resource in kagent namespace
- [ ] T046 [US3] Verify ModelConfig status Ready via kubectl get modelconfig -n kagent

**Checkpoint**: LLM credentials are synced and ModelConfig resources can be created successfully

---

## Phase 6: User Story 4 - Create AI Agents with MCP Tool Access (Priority: P4)

**Goal**: Create AI agents that use MCP servers with traffic flowing through agentgateway

**Independent Test**: Verify Agent resources can be created with Ready status and MCP servers are deployed via kmcp

### Implementation for User Story 4

- [ ] T047 [US4] Create kagent-agents chart with example agents in cdk8s/charts/apps/kagent-example-agents-chart.ts
- [ ] T048 [US4] Add example MCPServer resource definition in kagent-example-agents-chart.ts
- [ ] T049 [US4] Add example Agent resource with tool references in kagent-example-agents-chart.ts
- [ ] T050 [US4] Add kagent-agents entry to cdk8s/config/applications.ts with syncWave 50
- [ ] T051 [US4] Register kagent-agents chart in cdk8s/main-v2.ts
- [ ] T052 [US4] Synthesize and validate kagent-agents package via npx ts-node main-v2.ts
- [ ] T053 [US4] Deploy kagent-agents via idpbuilder create --package cdk8s/dist/kagent-agents
- [ ] T054 [US4] Verify MCPServer pod deployed via kubectl get pods -n kagent
- [ ] T055 [US4] Verify Agent status Ready via kubectl get agent -n kagent
- [ ] T056 [US4] Create HTTPRoute for MCP server backend routing through agentgateway
- [ ] T057 [US4] Test agent response via kagent dashboard query

**Checkpoint**: AI agents are operational with MCP tool access through agentgateway

---

## Phase 7: User Story 5 - Verify Deployment via ArgoCD (Priority: P5)

**Goal**: Validate complete deployment health using ArgoCD CLI authenticated via 1Password

**Independent Test**: All ArgoCD applications show Synced and Healthy status

### Implementation for User Story 5

- [ ] T058 [US5] Authenticate ArgoCD CLI via 1Password using eval $(op signin)
- [ ] T059 [US5] Export ARGOCD_AUTH_TOKEN from 1Password vault
- [ ] T060 [US5] List all applications via argocd app list --insecure
- [ ] T061 [US5] Verify gateway-api-crds Synced/Healthy via argocd app get argocd/gateway-api-crds --insecure
- [ ] T062 [US5] Verify kgateway-crds Synced/Healthy via argocd app get argocd/kgateway-crds --insecure
- [ ] T063 [US5] Verify kgateway Synced/Healthy via argocd app get argocd/kgateway --insecure
- [ ] T064 [US5] Verify kagent-crds Synced/Healthy via argocd app get argocd/kagent-crds --insecure
- [ ] T065 [US5] Verify kagent Synced/Healthy via argocd app get argocd/kagent --insecure
- [ ] T066 [US5] Verify kagent-secrets Synced/Healthy via argocd app get argocd/kagent-secrets --insecure
- [ ] T067 [US5] Verify kagent-agents Synced/Healthy via argocd app get argocd/kagent-agents --insecure
- [ ] T068 [US5] Verify no out-of-sync applications via argocd-list-outofsync helper
- [ ] T069 [US5] Document deployment verification results in quickstart.md

**Checkpoint**: All applications verified healthy and compliant with GitOps workflow

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final documentation, cleanup, and optimization

- [ ] T070 [P] Update CLAUDE.md with kagent/kgateway deployment instructions
- [ ] T071 [P] Add OpenTelemetry GatewayParameters CRD example to documentation
- [ ] T072 Document MCP traffic routing architecture in specs/008-install-kagent-agentgateway-kubernetes/
- [ ] T073 Validate all synthesized YAML via kubectl diff -f cdk8s/dist/
- [ ] T074 Run quickstart.md verification checklist
- [ ] T075 Remove any temporary test resources via kubectl delete
- [ ] T076 Commit all changes with descriptive messages

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 (kgateway) and US2 (kagent) can start in parallel after Foundation
  - US3 (secrets) can start after US2 is deployed (needs kagent namespace)
  - US4 (agents) depends on US2 and US3 completion
  - US5 (verification) depends on all prior user stories
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Gateway infrastructure - no dependencies on other stories
- **User Story 2 (P2)**: Agent framework - can run in parallel with US1
- **User Story 3 (P3)**: LLM credentials - depends on US2 (kagent namespace exists)
- **User Story 4 (P4)**: Agent creation - depends on US2 and US3 (agents need models)
- **User Story 5 (P5)**: Verification - depends on US1-US4 (all must be deployed)

### Within Each User Story

- Chart creation before configuration updates
- Configuration before chart registration
- Registration before synthesis
- Synthesis before deployment
- Deployment before verification
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel
- US1 and US2 can start in parallel after Foundation
- T008 and T009 can run in parallel (different chart files)
- T024 can run in parallel with US1 implementation
- All verification tasks in US5 can run in parallel (independent ArgoCD app checks)

---

## Parallel Example: User Story 1 (kgateway)

```bash
# Launch chart creation tasks in parallel:
Task: "Create Gateway API CRDs chart in cdk8s/charts/infra/gateway-api-crds-chart.ts"
Task: "Create kgateway CRDs chart in cdk8s/charts/infra/kgateway-crds-chart.ts"

# After parallel chart creation, sequential registration:
Task: "Register Gateway API CRDs chart in cdk8s/main-v2.ts"
Task: "Register kgateway CRDs chart in cdk8s/main-v2.ts"
Task: "Register kgateway main chart in cdk8s/main-v2.ts"
```

---

## Parallel Example: User Story 5 (Verification)

```bash
# Launch all ArgoCD app verification in parallel:
Task: "Verify gateway-api-crds Synced/Healthy"
Task: "Verify kgateway-crds Synced/Healthy"
Task: "Verify kgateway Synced/Healthy"
Task: "Verify kagent-crds Synced/Healthy"
Task: "Verify kagent Synced/Healthy"
Task: "Verify kagent-secrets Synced/Healthy"
Task: "Verify kagent-agents Synced/Healthy"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (remove deprecated charts)
2. Complete Phase 2: Foundational (helper infrastructure)
3. Complete Phase 3: User Story 1 (kgateway with agentgateway)
4. **STOP and VALIDATE**: Verify kgateway pods Running, Gateway resource programmable
5. Deploy/demo if ready - agentgateway now available for MCP traffic

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (kgateway) → Verify pods Running → Deploy (Gateway infrastructure!)
3. Add User Story 2 (kagent) → Verify controller/UI → Deploy (Agent framework!)
4. Add User Story 3 (secrets) → Verify secret synced → Deploy (LLM credentials!)
5. Add User Story 4 (agents) → Verify agent Ready → Deploy (Working agents!)
6. Add User Story 5 (verification) → ArgoCD healthy → Deploy (Production-ready!)
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (kgateway infrastructure)
   - Developer B: User Story 2 (kagent framework)
3. After US2 completes:
   - Developer C: User Story 3 (secrets)
4. After US3 completes:
   - Developer A: User Story 4 (agents)
5. After all complete:
   - Team: User Story 5 (verification)
6. Stories integrate independently with ArgoCD orchestration

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- ArgoCD sync waves ensure proper deployment ordering (-130 to 50)
- Helm charts referenced via OCI URLs (ghcr.io, cr.kgateway.dev)
- External Secrets Operator must be pre-configured with Azure Key Vault ClusterSecretStore
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- All kubectl commands assume --insecure flag for local development (self-signed certs)

---

## Total Task Summary

- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 3 tasks
- **Phase 3 (US1 - kgateway)**: 16 tasks
- **Phase 4 (US2 - kagent)**: 13 tasks
- **Phase 5 (US3 - Secrets)**: 10 tasks
- **Phase 6 (US4 - Agents)**: 11 tasks
- **Phase 7 (US5 - Verification)**: 12 tasks
- **Phase 8 (Polish)**: 7 tasks

**Total**: 76 tasks across 8 phases

**MVP Scope**: Phases 1-3 (Setup + Foundational + US1) = 23 tasks
**Core Functionality**: Phases 1-6 (through US4) = 57 tasks
**Complete Feature**: All 76 tasks
