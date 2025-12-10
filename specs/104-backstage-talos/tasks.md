# Tasks: Backstage CDK8s Chart Migration

**Input**: Design documents from `/specs/104-backstage-talos/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests not explicitly requested. Validation is manual via `npm run synth` and `diff` comparisons per quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md, this project extends the existing cdk8s structure:
- **Charts**: `cdk8s/charts/apps/`, `cdk8s/charts/secrets/`
- **Config**: `cdk8s/config/applications.ts`
- **Libraries**: `cdk8s/lib/`, `cdk8s/imports/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Review existing patterns and prepare for chart implementation

- [X] T001 Review HeadlampChart implementation pattern in cdk8s/charts/platform/headlamp-chart.ts
- [X] T002 Review HeadlampKeycloakSecretsChart ESO pattern in cdk8s/charts/secrets/headlamp-keycloak-secrets-chart.ts
- [X] T003 [P] Review eso-helpers.ts helper functions in cdk8s/lib/eso-helpers.ts
- [X] T004 [P] Review existing applications.ts structure in cdk8s/config/applications.ts
- [X] T005 Review ref-implementation/backstage/manifests/install.yaml source manifests

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Ensure all CDK8s dependencies and patterns are understood before implementation

**⚠️ CRITICAL**: Chart implementation cannot begin until reference patterns are understood

- [X] T006 Verify imports/k8s.ts has all required Kubernetes types (Namespace, ServiceAccount, ClusterRole, etc.)
- [X] T007 Verify imports/external-secrets.io.ts has ExternalSecret, ClusterSecretStore types
- [X] T008 Verify auto-register-charts.ts pattern in cdk8s/lib/auto-register-charts.ts

**Checkpoint**: Foundation ready - chart implementation can now begin

---

## Phase 3: User Story 1 - Platform Engineer Synthesizes Backstage Manifests (Priority: P1) 🎯 MVP

**Goal**: Create BackstageChart and BackstageSecretsChart that synthesize YAML manifests equivalent to ref-implementation

**Independent Test**: Run `npm run synth` and verify:
- `dist/backstage/manifests/` contains 11 resources
- `dist/backstage-secrets/manifests/` contains 10 resources
- Compare against `ref-implementation/backstage/manifests/` using diff

### Implementation for User Story 1

#### BackstageSecretsChart (10 resources) - sync-wave: -10

- [X] T009 [P] [US1] Create BackstageSecretsChart class skeleton in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T010 [P] [US1] Create Password generator 'backstage' (36 chars) in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T011 [P] [US1] Create Password generator 'backstage-session' (64 chars) in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T012 [US1] Create ExternalSecret 'backstage-oidc' with dataFrom generators in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T013 [US1] Create ExternalSecret 'gitea-credentials' from gitea ClusterSecretStore in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T014 [US1] Create ExternalSecret 'ghcr-dockercfg-external' with sync-wave -10 in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T015 [US1] Create ServiceAccount 'eso-store' in argocd namespace in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T016 [US1] Create Role 'eso-store' with secrets read permissions in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T017 [US1] Create RoleBinding 'eso-store' linking ServiceAccount to Role in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T018 [US1] Create ClusterSecretStore 'argocd' with Kubernetes provider in cdk8s/charts/secrets/backstage-secrets-chart.ts
- [X] T019 [US1] Create ExternalSecret 'argocd-credentials' from argocd ClusterSecretStore in cdk8s/charts/secrets/backstage-secrets-chart.ts

#### BackstageChart (11 resources) - sync-wave: 20

- [X] T020 [P] [US1] Create BackstageChart class skeleton with props interface in cdk8s/charts/apps/backstage-chart.ts
- [X] T021 [US1] Create Namespace 'backstage' with managed-by label in cdk8s/charts/apps/backstage-chart.ts
- [X] T022 [US1] Create ServiceAccount 'backstage' in backstage namespace in cdk8s/charts/apps/backstage-chart.ts
- [X] T023 [P] [US1] Create ClusterRole 'backstage-argo-worfklows' (keep typo) in cdk8s/charts/apps/backstage-chart.ts
- [X] T024 [P] [US1] Create ClusterRole 'read-all' with wildcard permissions in cdk8s/charts/apps/backstage-chart.ts
- [X] T025 [US1] Create ClusterRoleBinding 'backstage-argo-worfklows' in cdk8s/charts/apps/backstage-chart.ts
- [X] T026 [US1] Create ClusterRoleBinding 'backstage-read-all' in cdk8s/charts/apps/backstage-chart.ts
- [X] T027 [P] [US1] Create Service 'backstage' (port 7007) in cdk8s/charts/apps/backstage-chart.ts
- [X] T028 [P] [US1] Create Service 'postgresql' (headless, port 5432) in cdk8s/charts/apps/backstage-chart.ts
- [X] T029 [US1] Create StatefulSet 'postgresql' with sync-wave 10, PVC 500Mi in cdk8s/charts/apps/backstage-chart.ts
- [X] T030 [US1] Create Deployment 'backstage' with sync-wave 20, envFrom references in cdk8s/charts/apps/backstage-chart.ts
- [X] T031 [US1] Create Ingress 'backstage' with hosts localhost and cnoe.localtest.me in cdk8s/charts/apps/backstage-chart.ts

#### Configuration Registration

- [X] T032 [US1] Add 'backstage-secrets' ApplicationConfig entry with sync-wave -10 in cdk8s/config/applications.ts
- [X] T033 [US1] Add 'backstage' ApplicationConfig entry with sync-wave 20 in cdk8s/config/applications.ts

#### Validation

- [X] T034 [US1] Run npm run synth and verify backstage-secrets produces 10 resources
- [X] T035 [US1] Run npm run synth and verify backstage produces 11 resources
- [X] T036 [US1] Compare synthesized manifests to ref-implementation using diff per quickstart.md

**Checkpoint**: User Story 1 complete - BackstageChart and BackstageSecretsChart synthesize equivalent manifests ✅

---

## Phase 4: User Story 2 - Platform Engineer Synthesizes Backstage Templates Manifests (Priority: P2)

**Goal**: Create ArgoCD Application configuration for backstage-templates that references the templates entities directory

**Independent Test**: Run `npm run synth` and verify `dist/backstage-templates.yaml` references `cnoe://backstage-templates/entities`

### Implementation for User Story 2

- [X] T037 [US2] Add 'backstage-templates' ApplicationConfig entry in cdk8s/config/applications.ts
- [X] T038 [US2] Configure backstage-templates to use source path 'entities' instead of 'manifests'
- [X] T039 [US2] Run npm run synth and verify backstage-templates.yaml is generated
- [X] T040 [US2] Verify backstage-templates.yaml references cnoe://backstage-templates/entities

**Checkpoint**: User Story 2 complete - backstage-templates ArgoCD Application configured ✅

---

## Phase 5: User Story 3 - Platform Engineer Deploys to Talos Cluster (Priority: P3)

**Goal**: Ensure charts support both KIND (cnoe:// URLs) and Talos (GitHub URLs) cluster types

**Independent Test**: Run `npm run synth:talos` and verify ArgoCD Application uses GitHub repository URL

### Implementation for User Story 3

- [X] T041 [US3] Add clusterType: 'both' to backstage-secrets ApplicationConfig in cdk8s/config/applications.ts
- [X] T042 [US3] Add clusterType: 'both' to backstage ApplicationConfig in cdk8s/config/applications.ts
- [X] T043 [US3] Add clusterType: 'both' to backstage-templates ApplicationConfig in cdk8s/config/applications.ts
- [X] T044 [US3] Run npm run synth:talos and verify ArgoCD Applications use GitHub URLs
- [X] T045 [US3] Verify Talos synthesis uses correct GIT_REPO_URL environment variable

**Checkpoint**: User Story 3 complete - Charts support both KIND and Talos clusters ✅

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup

- [X] T046 [P] Run full synthesis with npm run synth and verify no errors
- [X] T047 [P] Run TypeScript compile check with npx tsc --noEmit (Note: pre-existing kubevirt/cdi import errors unrelated to Backstage)
- [X] T048 Run quickstart.md validation steps for resource counts (11 + 10 = 21 resources, types match ref-implementation)
- [ ] T049 Deploy to KIND cluster with idpbuilder create --package cdk8s/dist/backstage-secrets --package cdk8s/dist/backstage
- [ ] T050 Verify ArgoCD applications reach Healthy status
- [ ] T051 Verify ExternalSecrets reach SecretSynced status
- [ ] T052 Verify Backstage UI accessible at https://cnoe.localtest.me:8443

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1 (P1) must complete before US2 and US3 can be validated
  - US2 and US3 can be worked on in parallel after US1 core charts exist
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - Creates both charts
- **User Story 2 (P2)**: Depends on US1 config patterns - Adds templates config
- **User Story 3 (P3)**: Depends on US1 configs existing - Adds clusterType field

### Within Each User Story

- BackstageSecretsChart before BackstageChart (secrets must exist for deployment)
- Chart class skeleton before resource implementations
- All resources before config registration
- Config registration before validation

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel (T003, T004)
- Password generators (T010, T011) can run in parallel
- ClusterRoles (T023, T024) can run in parallel
- Services (T027, T028) can run in parallel
- Polish validation tasks (T046, T047) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch Password generators together:
Task: "Create Password generator 'backstage' in cdk8s/charts/secrets/backstage-secrets-chart.ts"
Task: "Create Password generator 'backstage-session' in cdk8s/charts/secrets/backstage-secrets-chart.ts"

# Launch ClusterRoles together:
Task: "Create ClusterRole 'backstage-argo-worfklows' in cdk8s/charts/apps/backstage-chart.ts"
Task: "Create ClusterRole 'read-all' in cdk8s/charts/apps/backstage-chart.ts"

# Launch Services together:
Task: "Create Service 'backstage' in cdk8s/charts/apps/backstage-chart.ts"
Task: "Create Service 'postgresql' in cdk8s/charts/apps/backstage-chart.ts"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (understand existing patterns)
2. Complete Phase 2: Foundational (verify dependencies)
3. Complete Phase 3: User Story 1 (both charts + config)
4. **STOP and VALIDATE**: Run `npm run synth` and compare with ref-implementation
5. Deploy with idpbuilder if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test with synth + diff → Deploy/Demo (MVP!)
3. Add User Story 2 → Verify templates config
4. Add User Story 3 → Verify Talos synthesis
5. Polish phase → Full validation

---

## Notes

- [P] tasks = different files or resources with no dependencies
- [Story] label maps task to specific user story for traceability
- BackstageSecretsChart resources have sync-wave -10 for early deployment
- BackstageChart resources have sync-wave 10 (PostgreSQL) and 20 (Backstage)
- Maintain typo "worfklows" in ClusterRole name for ref-implementation compatibility
- Verify tests by comparing synthesized YAML against contracts/backstage-resources.yaml
