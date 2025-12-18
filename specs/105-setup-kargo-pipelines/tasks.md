# Tasks: Kargo Progressive Delivery Pipelines Framework

**Input**: Design documents from `/specs/105-setup-kargo-pipelines/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in spec - manual validation via quickstart.md validation steps.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **CDK8s charts**: `cdk8s/charts/pipelines/`
- **CDK8s config**: `cdk8s/config/applications.ts`
- **CDK8s lib**: `cdk8s/lib/`
- **Imports**: `cdk8s/imports/kargo.akuity.io.ts`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and verification of existing components

- [X] T001 Verify existing Kargo CRD imports are up-to-date in cdk8s/imports/kargo.akuity.io.ts
- [X] T002 Verify existing kargo-pipelines-project-chart.ts structure in cdk8s/charts/pipelines/kargo-pipelines-project-chart.ts
- [X] T003 [P] Create kargo-helpers.ts utility file in cdk8s/lib/kargo-helpers.ts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Update kargo-pipelines-project-chart.ts to add inner loop promotion policy in cdk8s/charts/pipelines/kargo-pipelines-project-chart.ts
- [X] T005 Add webhook receiver configurations for Gitea in ProjectConfig in cdk8s/charts/pipelines/kargo-pipelines-project-chart.ts
- [X] T006 Add webhook receiver configurations for GitHub in ProjectConfig in cdk8s/charts/pipelines/kargo-pipelines-project-chart.ts
- [X] T007 [P] Create ExternalSecret for kargo-gitea-webhook-secret in cdk8s/charts/secrets/ (if not existing)
- [X] T008 [P] Create ExternalSecret for kargo-github-webhook-secret in cdk8s/charts/secrets/ (if not existing)
- [X] T009 Create base kargo-backstage-pipeline-chart.ts skeleton in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Inner Loop: Rapid Local Development with Gitea (Priority: P1) 🎯 MVP

**Goal**: Developer pushes image to Gitea → auto-promoted to local-dev stage → running in KIND within 60 seconds

**Independent Test**: Push image to Gitea registry, verify Freight creation and auto-promotion to local-dev stage using quickstart.md validation steps (Test Inner Loop section)

### Implementation for User Story 1

- [X] T010 [US1] Implement Gitea Warehouse (backstage-gitea) in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T011 [US1] Implement local-dev Stage with direct warehouse source in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T012 [US1] Implement promotion template with argocd-update step for local-dev in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T013 [US1] Add backstage-local-dev ArgoCD Application with kargo authorization annotation in cdk8s/charts/apps/ (or update existing)
- [X] T014 [US1] Register kargo-backstage-pipeline chart in applications.ts config in cdk8s/config/applications.ts
- [X] T015 [US1] Synthesize and validate manifest output for inner loop in cdk8s/dist/kargo-backstage-pipeline/

**Checkpoint**: Inner loop fully functional - can push to Gitea and see deployment in local-dev

---

## Phase 4: User Story 2 - Outer Loop: CI-Built Image Flows to Development (Priority: P1)

**Goal**: GitHub Actions pushes image to GHCR → auto-promoted to dev stage → running in KIND

**Independent Test**: Push semver-tagged image to GHCR, verify Freight creation and auto-promotion to dev stage

### Implementation for User Story 2

- [X] T016 [US2] Implement GHCR Warehouse (backstage-ghcr) in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T017 [US2] Implement dev Stage with direct warehouse source in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T018 [US2] Implement promotion template with argocd-update step for dev in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T019 [US2] Add backstage-dev ArgoCD Application with kargo authorization annotation in cdk8s/charts/apps/ (or update existing)
- [X] T020 [US2] Synthesize and validate manifest output for outer loop dev stage in cdk8s/dist/kargo-backstage-pipeline/

**Checkpoint**: Outer loop dev stage functional - can push to GHCR and see deployment in backstage-dev namespace

---

## Phase 5: User Story 3 - Manual Promotion to Staging (Talos) (Priority: P2)

**Goal**: Manual promotion from dev stage to staging stage deploys to Talos cluster

**Independent Test**: Manually promote Freight from dev to staging via Kargo CLI/UI, verify Talos deployment updates

### Implementation for User Story 3

- [X] T021 [US3] Implement staging Stage with upstream stage source (backstage-dev) in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T022 [US3] Implement promotion template targeting Talos cluster ArgoCD Application in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T023 [US3] Add backstage-staging ArgoCD Application with kargo authorization annotation in cdk8s/charts/apps/ (or update existing)
- [X] T024 [US3] Configure staging cluster URL variable in promotion template in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts

**Checkpoint**: Staging promotion functional - can promote from dev to staging via manual action

---

## Phase 6: User Story 4 - Webhook-Driven Instant Detection (Priority: P2)

**Goal**: Webhooks notify Kargo immediately when images are pushed, eliminating polling latency

**Independent Test**: Measure time from image push to Freight creation - should be under 30 seconds

### Implementation for User Story 4

- [X] T025 [US4] Configure Gitea webhook URL discovery documentation in specs/105-setup-kargo-pipelines/quickstart.md
- [X] T026 [US4] Document Gitea webhook configuration steps (Gitea admin UI) in specs/105-setup-kargo-pipelines/quickstart.md
- [X] T027 [US4] Configure GitHub webhook URL discovery documentation in specs/105-setup-kargo-pipelines/quickstart.md
- [X] T028 [US4] Document GitHub webhook configuration steps (repo settings) in specs/105-setup-kargo-pipelines/quickstart.md
- [X] T029 [US4] Add Tailscale/Ingress configuration for external webhook endpoint in documentation

**Checkpoint**: Webhooks documented and configurable - Freight creation is instant rather than polled

---

## Phase 7: User Story 5 - Pipeline Visualization and Status Monitoring (Priority: P3)

**Goal**: Both pipelines visible in Kargo UI with stage relationships and Freight history

**Independent Test**: Access Kargo UI and verify both inner and outer loop pipelines are displayed correctly

### Implementation for User Story 5

- [X] T030 [US5] Add appropriate labels for Kargo UI grouping in all Warehouse resources
- [X] T031 [US5] Add appropriate labels for Kargo UI grouping in all Stage resources
- [X] T032 [US5] Document Kargo UI access and verification steps in quickstart.md

**Checkpoint**: Both pipelines visible and distinguishable in Kargo UI

---

## Phase 8: User Story 6 - Graduating from Inner Loop to Outer Loop (Priority: P3)

**Goal**: Developer workflow from inner loop testing to outer loop production path is documented

**Independent Test**: Follow documented workflow: inner loop testing → PR creation → CI build → outer loop promotion

### Implementation for User Story 6

- [X] T033 [US6] Document developer workflow for transitioning inner loop to outer loop in docs/ or specs/
- [X] T034 [US6] Document image tagging strategy differences (dev-commit vs semver) in quickstart.md

**Checkpoint**: Developer workflow fully documented

---

## Phase 9: User Story 7 - Reusable Pipeline Framework (Priority: P4)

**Goal**: CDK8s factory pattern enables adding new applications with minimal configuration

**Independent Test**: Add a second application pipeline using the factory and verify both loops function

### Implementation for User Story 7

- [X] T035 [US7] Create kargo-pipeline-factory.ts with PipelineConfig interface in cdk8s/charts/pipelines/kargo-pipeline-factory.ts
- [X] T036 [US7] Extract common patterns from kargo-backstage-pipeline-chart.ts into factory in cdk8s/charts/pipelines/kargo-pipeline-factory.ts
- [ ] T037 [US7] Refactor kargo-backstage-pipeline-chart.ts to use factory in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T038 [US7] Add helper functions for Warehouse creation in cdk8s/lib/kargo-helpers.ts
- [X] T039 [US7] Add helper functions for Stage creation in cdk8s/lib/kargo-helpers.ts
- [X] T040 [US7] Document framework usage for adding new applications in cdk8s/charts/pipelines/README.md

**Checkpoint**: Framework ready for additional applications

---

## Phase 10: Production Stage Placeholder (Priority: P4)

**Goal**: Production stage placeholder exists for future expansion

**Independent Test**: Verify production stage resource exists but is marked as placeholder

### Implementation for Production Placeholder

- [X] T041 Implement production Stage placeholder with requiredSoakTime from staging in cdk8s/charts/pipelines/kargo-backstage-pipeline-chart.ts
- [X] T042 Add placeholder annotation to production stage for Kargo UI indication

**Checkpoint**: Production stage placeholder exists

---

## Phase 11: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T043 [P] Update CLAUDE.md with Kargo pipeline commands and patterns
- [X] T044 Run npm run synth and verify all manifests generate correctly
- [ ] T045 Deploy via idpbuilder create --package cdk8s/dist/kargo-backstage-pipeline and verify ArgoCD sync
- [ ] T046 [P] Run quickstart.md validation steps for inner loop
- [ ] T047 [P] Run quickstart.md validation steps for outer loop
- [X] T048 Document troubleshooting steps based on validation results in quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-9)**: All depend on Foundational phase completion
  - US1 & US2 are both P1 - implement sequentially (US1 first for MVP)
  - US3 depends on US2 (staging needs dev stage)
  - US4 can proceed in parallel once US1/US2 exist
  - US5 can proceed in parallel once US1/US2 exist
  - US6 depends on US1 & US2 completion
  - US7 depends on US1/US2/US3 completion (need patterns to extract)
- **Production Placeholder (Phase 10)**: Depends on US3 completion
- **Polish (Phase 11)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - MVP target
- **User Story 2 (P1)**: Can start after Foundational - completes outer loop entry point
- **User Story 3 (P2)**: Depends on US2 (dev stage must exist for staging source)
- **User Story 4 (P2)**: Can start after US1/US2 - enhances existing functionality
- **User Story 5 (P3)**: Can start after US1/US2 - visualization only
- **User Story 6 (P3)**: Depends on US1 & US2 - documents workflow
- **User Story 7 (P4)**: Depends on US1/US2/US3 - extracts patterns

### Within Each User Story

- Warehouses before Stages (Stages reference Warehouses)
- Stages before ArgoCD Applications (authorization annotation references stage)
- Core implementation before documentation
- Synthesis/validation at end of each story

### Parallel Opportunities

- T007 & T008 (webhook secrets) can run in parallel
- T030, T031, T032 (labeling) can run in parallel
- T046 & T047 (validation) can run in parallel
- Once Foundational phase completes, US4 and US5 can proceed in parallel with US2/US3

---

## Parallel Example: Foundational Phase

```bash
# Launch webhook secret tasks together:
Task: "Create ExternalSecret for kargo-gitea-webhook-secret in cdk8s/charts/secrets/"
Task: "Create ExternalSecret for kargo-github-webhook-secret in cdk8s/charts/secrets/"
```

## Parallel Example: Polish Phase

```bash
# Launch validation tasks together:
Task: "Run quickstart.md validation steps for inner loop"
Task: "Run quickstart.md validation steps for outer loop"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Inner Loop)
4. **STOP and VALIDATE**: Test inner loop with Gitea push
5. Deploy/demo if ready - developer can iterate on Backstage rapidly

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (Inner Loop) → Test → Deploy (MVP!)
3. Add User Story 2 (Outer Loop Dev) → Test → Deploy
4. Add User Story 3 (Staging) → Test → Deploy
5. Add User Story 4 (Webhooks) → Test → Deploy (improves latency)
6. Add remaining stories incrementally

### Suggested MVP Scope

**MVP**: Phase 1 + Phase 2 + Phase 3 (User Story 1 - Inner Loop)

This delivers:
- Gitea Warehouse watching for dev images
- Local-dev Stage with auto-promotion
- ArgoCD Application authorization
- 60-second push-to-deployment cycle

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Use `npm run synth` after each significant change to validate output
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
