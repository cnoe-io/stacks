# Tasks: GitOps Bootstrap for Talos Linux Cluster

**Input**: Design documents from `/specs/102-bootstrap-talos-argocd/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in the feature specification. Manual verification via kubectl and ArgoCD UI is the testing approach.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is an Infrastructure-as-Code project with:
- `scripts/`: Bootstrap shell scripts
- `cdk8s/`: TypeScript CDK8s charts and configuration
- `cdk8s/charts/`: Chart implementations by domain
- `cdk8s/config/`: Application configuration

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and directory structure

- [X] T001 Create scripts directory structure: `scripts/`, `scripts/lib/` per plan.md
- [X] T002 [P] Create common.sh with shared functions in `scripts/lib/common.sh`
- [X] T003 [P] Create azure.sh with Azure CLI helpers in `scripts/lib/azure.sh`
- [X] T004 [P] Create talos.sh with talosctl helpers in `scripts/lib/talos.sh`
- [X] T005 Create CDK8s Talos entry point in `cdk8s/main-talos.ts`
- [X] T006 [P] Create talos-applications.ts config in `cdk8s/config/talos-applications.ts`
- [X] T007 [P] Create argocd-values.yaml Helm values in `cdk8s/values/argocd-values.yaml`

**Checkpoint**: Directory structure and base files created

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T008 Implement bootstrap-cluster.sh main orchestrator in `scripts/bootstrap-cluster.sh`
- [X] T009 Add prerequisite validation to bootstrap-cluster.sh (check talosctl, kubectl, helm, az CLI)
- [X] T010 [P] Create environment variable template in `scripts/.env.template`
- [X] T011 Implement ArgoCD Helm chart wrapper in `cdk8s/charts/platform/argocd-helm-chart.ts`
- [X] T012 [P] Register ArgoCDHelmChart in chart factory in `cdk8s/main-talos.ts`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - ArgoCD GitOps Deployment (Priority: P1) 🎯 MVP

**Goal**: Deploy ArgoCD on Talos cluster so that operators can declaratively manage all cluster applications from Git

**Independent Test**: Access ArgoCD UI, create an Application resource from Git, verify it syncs successfully

### Implementation for User Story 1

- [X] T013 [US1] Implement 01-install-argocd.sh with Helm install logic in `scripts/01-install-argocd.sh`
- [X] T014 [US1] Add idempotency check to 01-install-argocd.sh (skip if ArgoCD exists)
- [X] T015 [US1] Add ArgoCD health wait loop to 01-install-argocd.sh (wait for pods ready)
- [X] T016 [P] [US1] Implement ArgoCD root application chart in `cdk8s/charts/platform/argocd-root-application-chart.ts`
- [X] T017 [P] [US1] Register ArgoCDRootApplicationChart in chart factory in `cdk8s/main-talos.ts`
- [X] T018 [US1] Implement 03-apply-base-apps.sh with kubectl apply logic in `scripts/03-apply-base-apps.sh`
- [X] T019 [US1] Add ArgoCD Application sync status check to 03-apply-base-apps.sh
- [X] T020 [US1] Add external-secrets-operator to talos-applications.ts in `cdk8s/config/talos-applications.ts`
- [X] T021 [US1] Add tailscale-operator to talos-applications.ts in `cdk8s/config/talos-applications.ts`
- [X] T022 [US1] Update bootstrap-cluster.sh to call 01-install-argocd.sh and 03-apply-base-apps.sh

**Checkpoint**: ArgoCD deployed and managing applications - User Story 1 independently testable

---

## Phase 4: User Story 2 - Tailscale Operator with OAuth Integration (Priority: P2)

**Goal**: Securely access Kubernetes API and cluster services from any device on tailnet without exposing public endpoints

**Independent Test**: Access Kubernetes API via Tailscale hostname (k8s-api.<tailnet>.ts.net) from a remote tailnet device

### Implementation for User Story 2

- [X] T023 [P] [US2] Implement TailscaleOperatorChart using Helm construct in `cdk8s/charts/infra/tailscale-operator-chart.ts`
- [X] T024 [P] [US2] Register TailscaleOperatorChart in chart factory in `cdk8s/main-talos.ts`
- [X] T025 [P] [US2] Implement TailscaleSecretsChart for OAuth credentials in `cdk8s/charts/secrets/tailscale-secrets-chart.ts`
- [X] T026 [P] [US2] Register TailscaleSecretsChart in chart factory in `cdk8s/main-talos.ts`
- [X] T027 [US2] Implement K8sApiTailscaleServeChart for kubectl access in `cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts`
- [X] T028 [US2] Register K8sApiTailscaleServeChart in chart factory in `cdk8s/main-talos.ts`
- [X] T029 [US2] Implement ArgoCDTailscaleServeChart for UI access in `cdk8s/charts/platform/argocd-tailscale-serve-chart.ts`
- [X] T030 [US2] Register ArgoCDTailscaleServeChart in chart factory in `cdk8s/main-talos.ts`
- [X] T031 [US2] Add tailscale-secrets to talos-applications.ts with sync wave -85 in `cdk8s/config/talos-applications.ts`
- [X] T032 [US2] Add k8s-api-tailscale-serve to talos-applications.ts with sync wave -60 in `cdk8s/config/talos-applications.ts`
- [X] T033 [US2] Add argocd-tailscale-serve to talos-applications.ts with sync wave -60 in `cdk8s/config/talos-applications.ts`

**Checkpoint**: Tailscale access working - User Story 2 independently testable

---

## Phase 5: User Story 3 - External Secrets with Azure Workload Identity (Priority: P3)

**Goal**: Applications can securely access secrets from Azure Key Vault without storing credentials in the cluster

**Independent Test**: Create ClusterSecretStore pointing to Azure Key Vault and ExternalSecret that pulls a secret value

### Implementation for User Story 3

- [X] T034 [US3] Implement 02-sync-jwks.sh for OIDC federation in `scripts/02-sync-jwks.sh`
- [X] T035 [US3] Add JWKS extraction from cluster to 02-sync-jwks.sh (kubectl get --raw)
- [X] T036 [US3] Add openid-configuration generation to 02-sync-jwks.sh
- [X] T037 [US3] Add Azure Storage upload logic to 02-sync-jwks.sh
- [X] T038 [US3] Add idempotency check to 02-sync-jwks.sh (verify JWKS endpoint accessible)
- [X] T039 [P] [US3] Implement EsoHelmChart using Helm construct in `cdk8s/charts/secrets/eso-helm-chart.ts`
- [X] T040 [P] [US3] Register EsoHelmChart in chart factory in `cdk8s/main-talos.ts`
- [X] T041 [P] [US3] Implement WorkloadIdentityPatchChart for ServiceAccount annotations in `cdk8s/charts/secrets/workload-identity-patch-chart.ts`
- [X] T042 [P] [US3] Register WorkloadIdentityPatchChart in chart factory in `cdk8s/main-talos.ts`
- [X] T043 [US3] Implement ClusterSecretStoreChart for Azure Key Vault in `cdk8s/charts/secrets/cluster-secret-store-chart.ts`
- [X] T044 [US3] Register ClusterSecretStoreChart in chart factory in `cdk8s/main-talos.ts`
- [X] T045 [US3] Add workload-identity-patch to talos-applications.ts with sync wave -94 in `cdk8s/config/talos-applications.ts`
- [X] T046 [US3] Add cluster-secret-store to talos-applications.ts with sync wave -92 in `cdk8s/config/talos-applications.ts`
- [X] T047 [US3] Update bootstrap-cluster.sh to call 02-sync-jwks.sh before 03-apply-base-apps.sh

**Checkpoint**: External Secrets fetching from Azure Key Vault - User Story 3 independently testable

---

## Phase 6: User Story 4 - CDK8s-Based Manifest Generation (Priority: P4)

**Goal**: Generate Kubernetes manifests using CDK8s with TypeScript for type-safety and programmatic logic

**Independent Test**: Run `npm run synth` and verify valid YAML manifests are generated in output directory

### Implementation for User Story 4

- [ ] T048 [P] [US4] Add Talos-specific npm script to package.json in `cdk8s/package.json`
- [ ] T049 [US4] Implement synthesis logic in main-talos.ts using IdpBuilderChartFactory pattern in `cdk8s/main-talos.ts`
- [ ] T050 [US4] Add FILE_PER_RESOURCE output mode to main-talos.ts synthesis in `cdk8s/main-talos.ts`
- [ ] T051 [US4] Implement kustomization.yaml generation per application in `cdk8s/main-talos.ts`
- [ ] T052 [P] [US4] Copy/adapt SYNC_WAVES constants from contracts to cdk8s lib in `cdk8s/lib/sync-waves.ts`
- [ ] T053 [US4] Verify all charts registered in factory and synthesis produces valid YAML in `cdk8s/main-talos.ts`

**Checkpoint**: CDK8s synthesis working for Talos - User Story 4 independently testable

---

## Phase 7: User Story 5 - Automated Bootstrap Scripting (Priority: P5)

**Goal**: Single bootstrap script that orchestrates entire cluster configuration from bare Talos to operational GitOps

**Independent Test**: Run bootstrap script against fresh Talos cluster and verify all components deployed and healthy

### Implementation for User Story 5

- [ ] T054 [US5] Add phase tracking to bootstrap-cluster.sh for idempotent re-runs in `scripts/bootstrap-cluster.sh`
- [ ] T055 [US5] Add error handling and retry logic to bootstrap-cluster.sh in `scripts/bootstrap-cluster.sh`
- [ ] T056 [US5] Add completion output with access URLs to bootstrap-cluster.sh in `scripts/bootstrap-cluster.sh`
- [ ] T057 [US5] Add CNI readiness check before ArgoCD install in bootstrap-cluster.sh in `scripts/bootstrap-cluster.sh`
- [ ] T058 [US5] Create kubeconfig generation helper in `scripts/lib/talos.sh`
- [ ] T059 [US5] Create Azure credential validation helper in `scripts/lib/azure.sh`
- [ ] T060 [P] [US5] Create remote kubeconfig generation script in `scripts/generate-remote-kubeconfig.sh`
- [ ] T061 [US5] Add --force flag to 02-sync-jwks.sh for cluster rebuild scenarios in `scripts/02-sync-jwks.sh`

**Checkpoint**: Full bootstrap automation complete - User Story 5 independently testable

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T062 [P] Update CLAUDE.md with new Talos bootstrap commands in `CLAUDE.md`
- [ ] T063 [P] Create README.md for scripts directory in `scripts/README.md`
- [ ] T064 Validate quickstart.md steps against actual bootstrap process in `specs/102-bootstrap-talos-argocd/quickstart.md`
- [ ] T065 Add shellcheck validation to all scripts in `scripts/`
- [ ] T066 Add TypeScript strict mode validation to CDK8s charts in `cdk8s/tsconfig.json`
- [ ] T067 Run full bootstrap on fresh Talos cluster and document any issues in `specs/102-bootstrap-talos-argocd/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - ArgoCD is required first
- **User Story 2 (Phase 4)**: Depends on US1 (ArgoCD manages Tailscale apps)
- **User Story 3 (Phase 5)**: Depends on US1 (ArgoCD manages ESO apps) - can parallel with US2
- **User Story 4 (Phase 6)**: Can start after Foundational (Phase 2) - mostly independent
- **User Story 5 (Phase 7)**: Depends on US1, US2, US3 being implemented
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

```
          ┌─────────────────────────────────────┐
          │     Phase 2: Foundational           │
          └─────────────┬───────────────────────┘
                        │
          ┌─────────────▼───────────────────────┐
          │    Phase 3: US1 - ArgoCD (P1)       │
          └─────────────┬───────────────────────┘
                        │
          ┌─────────────┼───────────────────────┐
          │             │                       │
  ┌───────▼──────┐    ┌─▼────────────┐  ┌───────▼────────┐
  │ Phase 4: US2 │    │ Phase 5: US3 │  │ Phase 6: US4   │
  │ Tailscale    │    │ ESO+Workload │  │ CDK8s Synth    │
  │ (P2)         │    │ Identity (P3)│  │ (P4)           │
  └───────┬──────┘    └──────┬───────┘  └───────┬────────┘
          │                  │                  │
          └──────────────────┼──────────────────┘
                             │
          ┌──────────────────▼──────────────────┐
          │    Phase 7: US5 - Full Automation    │
          └─────────────────────────────────────┘
```

### Within Each User Story

- Charts before factory registration
- Factory registration before config addition
- Scripts implement phases in order
- Synthesis validates all charts work together

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel (T002-T004, T006-T007)
- US2 chart implementations (T023-T026) can run in parallel
- US3 chart implementations (T039-T042) can run in parallel
- US2 and US3 can run in parallel after US1 is complete
- US4 can run in parallel with US2 and US3

---

## Parallel Example: User Story 2

```bash
# Launch all Tailscale charts together (marked [P]):
Task: "Implement TailscaleOperatorChart in cdk8s/charts/infra/tailscale-operator-chart.ts"
Task: "Register TailscaleOperatorChart in chart factory"
Task: "Implement TailscaleSecretsChart in cdk8s/charts/secrets/tailscale-secrets-chart.ts"
Task: "Register TailscaleSecretsChart in chart factory"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T007)
2. Complete Phase 2: Foundational (T008-T012)
3. Complete Phase 3: User Story 1 (T013-T022)
4. **STOP and VALIDATE**: Verify ArgoCD UI accessible, can sync applications
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → ArgoCD working! (MVP!)
3. Add User Story 2 → Test Tailscale access → Remote kubectl working!
4. Add User Story 3 → Test ExternalSecrets → Azure secrets syncing!
5. Add User Story 4 → Verify CDK8s synthesis → Type-safe manifests!
6. Add User Story 5 → Full automation → One-command bootstrap!

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once US1 is done:
   - Developer A: User Story 2 (Tailscale)
   - Developer B: User Story 3 (External Secrets)
   - Developer C: User Story 4 (CDK8s synthesis)
3. All contribute to User Story 5 (automation integrates everything)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- This is IaC - "testing" is manual verification via kubectl/argocd CLI
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
