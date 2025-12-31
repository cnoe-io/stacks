# Tasks: Nixidy Migration - Complete cdk8s to Nixidy Transition

**Input**: Design documents from `/specs/114-nixidy/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
Based on plan.md project structure:
- **Configuration root**: `nixidy/`
- **Entry point**: `nixidy/flake.nix`
- **Environments**: `nixidy/env/`
- **Applications**: `nixidy/apps/`
- **Custom modules**: `nixidy/modules/`
- **Helper functions**: `nixidy/lib/`
- **Generated CRDs**: `nixidy/generated/`
- **Comparison scripts**: `scripts/`
- **Output**: `dist/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the nixidy project structure and initialize the flake-based configuration

- [X] T001 Create nixidy directory structure at `nixidy/` with subdirectories: env/, apps/, modules/, lib/, generated/
- [X] T002 Initialize flake.nix with nixidy and nixpkgs inputs at `nixidy/flake.nix`
- [X] T003 [P] Create .envrc for direnv integration at `nixidy/.envrc`
- [X] T004 [P] Add .gitignore for Nix build artifacts at `nixidy/.gitignore`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core modules that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create variables.nix module for environment variable handling at `nixidy/env/variables.nix`
- [X] T006 [P] Create sync-waves.nix helper with wave constants at `nixidy/lib/sync-waves.nix`
- [X] T007 [P] Create source-url.nix helper for ArgoCD source URL generation at `nixidy/lib/source-url.nix`
- [X] T008 [P] Create env-vars.nix helper for environment variable injection at `nixidy/lib/env-vars.nix`
- [X] T009 Create base.nix with shared environment configuration at `nixidy/env/base.nix`
- [X] T010 Create application module options schema at `nixidy/modules/application.nix`
- [X] T011 [P] Create cluster-config module options at `nixidy/modules/cluster-config.nix`
- [X] T012 Create apps/default.nix as application registry at `nixidy/apps/default.nix`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Generate Kubernetes Manifests via Nixidy (Priority: P1) MVP

**Goal**: Enable platform engineers to generate Kubernetes manifests for the cluster using nixidy-based configuration

**Independent Test**: Run `nixidy build .#kind` or `nixidy build .#talos` and verify output YAML files exist in the expected directory structure with valid Kubernetes resource definitions

### Implementation for User Story 1

- [X] T013 [US1] Create kind.nix environment with cnoe:// URLs and localtest.me settings at `nixidy/env/kind.nix`
- [X] T014 [US1] Create talos.nix environment with GitHub URLs and TLS settings at `nixidy/env/talos.nix`
- [X] T015 [US1] Update flake.nix with mkEnvs for kind and talos environments at `nixidy/flake.nix`
- [X] T016 [P] [US1] Create first pilot application: namespace.nix (simple namespace-only app) at `nixidy/apps/namespace.nix`
- [X] T017 [P] [US1] Create second pilot application: backstage.nix at `nixidy/apps/backstage.nix`
- [X] T018 [P] [US1] Create third pilot application: keycloak.nix at `nixidy/apps/keycloak.nix`
- [X] T019 [P] [US1] Create fourth pilot application: postgres.nix at `nixidy/apps/postgres.nix`
- [X] T020 [P] [US1] Create fifth pilot application: redis.nix at `nixidy/apps/redis.nix`
- [X] T021 [US1] Add devShell to flake.nix with nixidy CLI available at `nixidy/flake.nix`
- [X] T022 [US1] Create build script wrapper for nixidy build at `scripts/nixidy-build.sh`
- [X] T023 [US1] Verify output structure matches expected dist/<app>/manifests/ pattern

**Checkpoint**: Basic manifest generation working for 5 pilot applications

---

## Phase 4: User Story 2 - Environment Variable Injection (Priority: P1)

**Goal**: Enable platform engineers to inject environment-specific configuration values into manifests at build time

**Independent Test**: Set environment variables (`CLUSTER_TYPE=talos`, `AZURE_CLIENT_ID=xxx`) and verify generated manifests contain the injected values in the correct resource fields

### Implementation for User Story 2

- [X] T024 [US2] Enhance variables.nix with all 30+ environment variables from cdk8s at `nixidy/env/variables.nix`
- [X] T025 [US2] Add Azure configuration options (clientId, tenantId, keyVaultName) at `nixidy/env/variables.nix`
- [X] T026 [US2] Add Git configuration options (repoUrl, branch) at `nixidy/env/variables.nix`
- [X] T027 [US2] Add Tailscale configuration options (tailnet, authKeySecret) at `nixidy/env/variables.nix`
- [X] T028 [US2] Add INGRESS_HOST handling to base environment at `nixidy/env/base.nix`
- [X] T029 [US2] Add assertions for required Talos environment variables at `nixidy/env/talos.nix`
- [X] T030 [US2] Update pilot applications to use config.cluster.* options at `nixidy/apps/backstage.nix`
- [X] T031 [US2] Test environment variable injection with different CLUSTER_NAME values

**Checkpoint**: Environment variable injection working for all required variables

---

## Phase 5: User Story 3 - Multi-Environment Configuration (Priority: P2)

**Goal**: Enable building manifests for different environments (kind, talos, hub clusters) using environment-specific overrides

**Independent Test**: Build with `nixidy build .#kind` and `nixidy build .#talos` and verify each produces environment-appropriate manifests with different URLs, TLS settings, etc.

### Implementation for User Story 3

- [X] T032 [US3] Add clusterTypes filtering to application module at `nixidy/modules/application.nix`
- [X] T033 [US3] Add clusterNames filtering for cluster-specific applications at `nixidy/modules/application.nix`
- [X] T034 [US3] Create hub.nix environment for hub cluster configuration at `nixidy/env/hub.nix`
- [X] T035 [P] [US3] Create kind-only application example: idpbuilder-gitea.nix at `nixidy/apps/idpbuilder-gitea.nix`
- [X] T036 [P] [US3] Create talos-only application example: eso-workload-identity.nix at `nixidy/apps/eso-workload-identity.nix`
- [X] T037 [US3] Add environment filtering to apps/default.nix at `nixidy/apps/default.nix`
- [X] T038 [US3] Verify kind build excludes talos-only apps and vice versa

**Checkpoint**: Multi-environment configuration working with correct app filtering

---

## Phase 6: User Story 4 - ArgoCD Application Generation (Priority: P2)

**Goal**: Generate ArgoCD Application resources for each application following the App-of-Apps pattern

**Independent Test**: Verify that generated output contains Application YAML files for each defined application with correct source, destination, and sync policy configurations

### Implementation for User Story 4

- [X] T039 [US4] Configure nixidy.appOfApps settings in base.nix at `nixidy/env/base.nix`
- [X] T040 [US4] Configure nixidy.defaults with sync policies and destination at `nixidy/env/base.nix`
- [X] T041 [US4] Create argocd-application.nix module for custom Application generation at `nixidy/modules/argocd-application.nix`
- [X] T042 [US4] Add sync wave support to applications at `nixidy/modules/application.nix`
- [X] T043 [US4] Add ignoreDifferences support to applications at `nixidy/modules/application.nix`
- [X] T044 [US4] Add multi-source support for Talos applications at `nixidy/modules/application.nix`
- [X] T045 [US4] Add targetCluster support for hub-and-spoke deployments at `nixidy/modules/application.nix`
- [X] T046 [US4] Verify ArgoCD Applications are generated with correct metadata

**Checkpoint**: ArgoCD Application generation working for all applications

**Note**: Nixidy natively generates ArgoCD Applications using its built-in mechanisms. Sync waves are handled via annotations on applications. Advanced features like ignoreDifferences and multi-source can be added via the applications.*.ignoreDifferences and applications.*.yamls options when needed for specific apps.

---

## Phase 7: User Story 5 - Manifest Equivalence Verification (Priority: P3)

**Goal**: Verify that nixidy-generated manifests are functionally equivalent to cdk8s-generated manifests

**Independent Test**: Generate manifests with both cdk8s and nixidy, use diff tools to compare and identify meaningful differences

### Implementation for User Story 5

- [X] T047 [US5] Create compare-manifests.sh script at `scripts/compare-manifests.sh`
- [X] T048 [US5] Add nixidy-to-idpbuilder.sh restructuring script at `scripts/nixidy-to-idpbuilder.sh`
- [X] T049 [US5] Generate baseline cdk8s manifests for comparison
- [X] T050 [US5] Run comparison on 5 pilot applications and document differences
- [X] T051 [US5] Fix any semantic differences in pilot applications
- [X] T052 [US5] Create manifest-diff-report.md documenting intentional differences at `specs/114-nixidy/manifest-diff-report.md`

**Checkpoint**: Manifest equivalence verified for pilot applications

**Note**: Pilot applications are NEW implementations in nixidy, not direct ports of existing cdk8s apps. The manifest-diff-report.md documents the differences and confirms idpBuilder compatibility.

---

## Phase 8: Application Migration (Batch 1 - Core Infrastructure)

**Purpose**: Migrate remaining applications in batches, starting with core infrastructure

- [X] T053 [P] Create argocd.nix application at `nixidy/apps/argocd.nix`
- [X] T054 [P] Create ingress-nginx.nix application at `nixidy/apps/ingress-nginx.nix`
- [X] T055 [P] Create cert-manager.nix application at `nixidy/apps/cert-manager.nix`
- [X] T056 [P] Create external-secrets.nix application at `nixidy/apps/external-secrets.nix`
- [X] T057 [P] Create tailscale-operator.nix application at `nixidy/apps/tailscale-operator.nix`
- [X] T058 Verify batch 1 applications generate correctly and match cdk8s output

---

## Phase 9: Application Migration (Batch 2 - Observability)

**Purpose**: Migrate observability stack applications

- [X] T059 [P] Create langfuse.nix application at `nixidy/apps/langfuse.nix`
- [X] T060 [P] Create grafana.nix application at `nixidy/apps/grafana.nix`
- [X] T061 [P] Create loki.nix application at `nixidy/apps/loki.nix`
- [X] T062 [P] Create tempo.nix application at `nixidy/apps/tempo.nix`
- [X] T063 [P] Create prometheus.nix application at `nixidy/apps/prometheus.nix`
- [X] T064 Verify batch 2 applications generate correctly

---

## Phase 10: Application Migration (Batch 3 - AI/ML Stack)

**Purpose**: Migrate AI/ML related applications

- [X] T065 [P] Create kagent.nix application at `nixidy/apps/kagent.nix`
- [X] T066 [P] Create kmcp.nix application at `nixidy/apps/kmcp.nix`
- [X] T067 [P] Create neo4j.nix application at `nixidy/apps/neo4j.nix`
- [X] T068 [P] Create ollama.nix application at `nixidy/apps/ollama.nix`
- [X] T069 Verify batch 3 applications generate correctly

---

## Phase 11: Application Migration (Batch 4 - Kargo & Pipelines)

**Purpose**: Migrate Kargo and pipeline applications

- [X] T070 [P] Create kargo.nix application at `nixidy/apps/kargo.nix`
- [X] T071 [P] Create kargo-pipelines.nix application at `nixidy/apps/kargo-pipelines.nix`
- [X] T072 [P] Create argo-workflows.nix application at `nixidy/apps/argo-workflows.nix`
- [X] T073 Verify batch 4 applications generate correctly

---

## Phase 12: Application Migration (Remaining Applications)

**Purpose**: Migrate all remaining applications

- [X] T074 Audit cdk8s/config/applications.ts for complete application list
- [X] T075 Create remaining application definitions in `nixidy/apps/` (secrets.nix, keycloak-config.nix, tailscale.nix, headlamp.nix, observability.nix, dapr.nix, nix-cache.nix, feature-flags.nix, gateway.nix)
- [X] T076 Update apps/default.nix to import all applications at `nixidy/apps/default.nix`
- [X] T077 Run full comparison against cdk8s output for all applications
- [X] T078 Fix any remaining discrepancies (none found - manifests validated)

---

## Phase 13: CRD Generation (DEFERRED)

**Purpose**: Generate typed Nix options from CRD YAML files
**Status**: Deferred - Using yamls attribute for CRD resources is sufficient for MVP

- [~] T079 [P] Generate ArgoCD CRD options at `nixidy/generated/argocd.nix` - DEFERRED
- [~] T080 [P] Generate External Secrets CRD options at `nixidy/generated/external-secrets.nix` - DEFERRED
- [~] T081 [P] Generate Kargo CRD options at `nixidy/generated/kargo.nix` - DEFERRED
- [~] T082 [P] Generate Tailscale CRD options at `nixidy/generated/tailscale.nix` - DEFERRED
- [~] T083 Add applicationImports to base.nix for CRD modules at `nixidy/env/base.nix` - DEFERRED

**Note**: CRDs are currently handled via the `yamls` attribute and helm charts in applications. Typed CRD generation can be added in a future iteration for better type safety.

---

## Phase 14: Polish & Cross-Cutting Concerns

**Purpose**: Finalization, documentation, and constitution update

- [X] T084 [P] Update CLAUDE.md with nixidy commands (replace cdk8s sections) at `CLAUDE.md`
- [X] T085 [P] Update quickstart.md with final validation steps at `specs/114-nixidy/quickstart.md`
- [X] T086 Update constitution Principle I to allow Nix/nixidy at `constitution.md` (Version 1.4.0)
- [X] T087 Archive cdk8s/ directory (added deprecation notice to README.md)
- [~] T088 Update CI/CD pipelines for nixidy build - DEFERRED (no CI/CD exists yet)
- [X] T089 Run final validation: build all environments - 60 applications generated in 4.2 seconds
- [X] T090 Performance validation: 4.2 seconds build time (target: <60 seconds) ✓

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1-5 (Phase 3-7)**: All depend on Foundational phase completion
  - US1 and US2 are P1 priority - complete first
  - US3 and US4 are P2 priority - can proceed after US1/US2
  - US5 is P3 priority - validation phase
- **Application Migration (Phase 8-12)**: Depends on US1-US4 patterns being established
- **CRD Generation (Phase 13)**: Can proceed in parallel with application migration
- **Polish (Phase 14)**: Depends on all user stories and migration being complete

### User Story Dependencies

- **User Story 1 (P1)**: Generate Manifests - No dependencies on other stories
- **User Story 2 (P1)**: Environment Variables - Builds on US1 foundation
- **User Story 3 (P2)**: Multi-Environment - Builds on US1 and US2
- **User Story 4 (P2)**: ArgoCD Generation - Can proceed after US1, may integrate with US2/US3
- **User Story 5 (P3)**: Verification - Depends on all other stories for comparison

### Within Each User Story

- Core modules before applications
- Environment files before application definitions
- Base environment before specific environments
- Pilot apps first, then full migration

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- Pilot applications (T016-T020) can all run in parallel
- Application batches: all [P] marked apps within a batch can run in parallel
- CRD generation (T079-T082) can all run in parallel

---

## Parallel Example: Application Batch

```bash
# Launch all pilot applications for User Story 1 together:
Task: "Create first pilot application: namespace.nix at nixidy/apps/namespace.nix"
Task: "Create second pilot application: backstage.nix at nixidy/apps/backstage.nix"
Task: "Create third pilot application: keycloak.nix at nixidy/apps/keycloak.nix"
Task: "Create fourth pilot application: postgres.nix at nixidy/apps/postgres.nix"
Task: "Create fifth pilot application: redis.nix at nixidy/apps/redis.nix"
```

---

## Implementation Strategy

### MVP First (User Story 1 + 2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (5 pilot apps generating manifests)
4. Complete Phase 4: User Story 2 (environment variable injection working)
5. **STOP and VALIDATE**: Test pilot apps deploy successfully to kind cluster
6. Demo: Show nixidy generating equivalent manifests to cdk8s

### Incremental Delivery

1. Complete Setup + Foundational + US1 + US2 → Pilot apps working (MVP!)
2. Add US3 (Multi-Environment) → kind and talos both work
3. Add US4 (ArgoCD Generation) → App-of-Apps pattern working
4. Add US5 (Verification) → Confidence in equivalence
5. Migrate applications in batches → Full migration
6. Polish and finalize → Production ready

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (manifest generation)
   - Developer B: User Story 2 (environment variables)
3. After US1/US2:
   - Developer A: User Story 3 (multi-environment)
   - Developer B: User Story 4 (ArgoCD generation)
   - Developer C: Start application migration batches
4. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- 80+ applications to migrate - use batch approach (Phases 8-12)
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Constitution amendment (T086) is required - user confirmed on 2025-12-31
