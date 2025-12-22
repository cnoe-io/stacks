# Tasks: Tailscale Architecture Optimization

**Input**: Design documents from `/specs/103-tailscale-services/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: No automated tests for this infrastructure feature. Validation is via manual commands documented in quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **CDK8s charts**: `cdk8s/charts/` (infra, platform, secrets)
- **Config**: `cdk8s/config/applications.ts`
- **Libraries**: `cdk8s/lib/`
- **Documentation**: `CLAUDE.md`, `specs/103-tailscale-services/`

---

## Phase 1: Setup (Verify Prerequisites)

**Purpose**: Verify prerequisites before making changes

- [X] T001 Verify Tailscale Admin Console access is available
- [X] T002 Verify Azure Key Vault has required secrets (TAILSCALE-AUTH-KEY, TAILSCALE-OAUTH-CLIENT-ID, TAILSCALE-OAUTH-CLIENT-SECRET)
- [X] T003 [P] Verify M1 Mac has Tailscale CLI installed (`tailscale version`)
- [X] T004 [P] Verify cluster is running and accessible (`kubectl get nodes`)
- [X] T005 [P] Run TypeScript type check (`cd cdk8s && npx tsc --noEmit`)

---

## Phase 2: Foundational (Tailscale ACL Configuration)

**Purpose**: Configure Tailscale ACL grants that MUST be complete before code changes

**⚠️ CRITICAL**: User Story 1 (kubectl OAuth) requires ACL grants to be configured first

- [X] T006 Add tagOwner entry for `tag:k8s-operator` in Tailscale Admin Console → Access Controls
- [X] T007 Add ACL grant for API Server Proxy impersonation with `tailscale.com/cap/kubernetes` capability
- [X] T008 Add ACL rule allowing `vpittamp@github` to access `tag:k8s-operator:443`
- [X] T009 Verify ACL changes saved and effective in Tailscale Admin Console

**Checkpoint**: ACL configuration ready - User Story 1 implementation can begin

---

## Phase 3: User Story 1 - kubectl Access via OAuth Identity (Priority: P0) 🎯 MVP

**Goal**: Enable kubectl access from M1 Mac using tailnet identity instead of static tokens

**Independent Test**: Run `kubectl get nodes` from M1 Mac, verify `kubectl auth whoami` shows tailnet identity

### Implementation for User Story 1

- [X] T010 [US1] Update Helm values in `cdk8s/charts/infra/tailscale-operator-chart.ts` to set `apiServerProxyConfig.mode: "true"` (auth mode)
- [X] T011 [US1] Add ClusterRoleBinding for tailnet identity `vpittamp@github` → `cluster-admin` in `cdk8s/charts/infra/tailscale-operator-chart.ts`
- [X] T012 [US1] Run TypeScript type check (`cd cdk8s && npx tsc --noEmit`)
- [X] T013 [US1] Synthesize CDK8s packages (`cd cdk8s && npx ts-node main-v2.ts`)
- [X] T014 [US1] Deploy changes via ArgoCD (`source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`)
- [X] T015 [US1] Wait for Tailscale Operator pod to restart and become ready
- [X] T016 [US1] Run `sudo tailscale configure kubeconfig kind-operator` to generate kubeconfig
- [X] T017 [US1] Verify `kubectl get nodes` succeeds via Tailscale OAuth
- [X] T018 [US1] Verify `kubectl auth whoami` shows tailnet identity (`vpittamp@github`)

**Checkpoint**: kubectl OAuth access working - SC-001, SC-002, SC-003 validated

---

## Phase 4: User Story 2 - Remove Stale Devices (Priority: P1)

**Goal**: Remove offline Tailscale devices blocking hostname reuse

**Independent Test**: Run `tailscale status` and verify no offline devices for cluster services

### Implementation for User Story 2

- [X] T019 [US2] Run `tailscale status` to list all devices and identify offline ones (none found)
- [X] T020 [US2] In Tailscale Admin Console → Machines, delete offline device: argocd (N/A - not present)
- [X] T021 [P] [US2] In Tailscale Admin Console → Machines, delete offline device: gitea (N/A - not present)
- [X] T022 [P] [US2] In Tailscale Admin Console → Machines, delete offline device: kagent (N/A - not present)
- [X] T023 [P] [US2] In Tailscale Admin Console → Machines, delete offline device: langfuse (N/A - not present)
- [X] T024 [P] [US2] In Tailscale Admin Console → Machines, delete offline device: kargo (N/A - not present)
- [X] T025 [P] [US2] In Tailscale Admin Console → Machines, delete offline device: headlamp (N/A - not present)
- [X] T026 [P] [US2] In Tailscale Admin Console → Machines, delete offline device: keycloak (N/A - not present)
- [X] T027 [US2] Verify cleanup: No offline service devices found

**Checkpoint**: Stale devices removed - SC-005 validated

---

## Phase 5: User Story 3 - Access ArgoCD via Stable URL (Priority: P1)

**Goal**: ArgoCD accessible at `https://argocd-<cluster>.<tailnet>.ts.net`

**Independent Test**: Access ArgoCD via stable URL from Tailscale-connected device

### Prerequisites: ACL Auto-Approver

- [X] T028 [US3] Add ACL auto-approver for `svc:argocd` with `tag:k8s-services` in Tailscale Admin Console

### Implementation for User Story 3

- [X] T029 [US3] Update ArgoCD service name from `argocd2` to `argocd` in `cdk8s/config/applications.ts`
- [X] T030 [US3] Run TypeScript type check (`cd cdk8s && npx tsc --noEmit`)
- [X] T031 [US3] Synthesize CDK8s packages (`cd cdk8s && npx ts-node main-v2.ts`)
- [X] T032 [US3] Deploy changes (`cluster-update`)
- [X] T033 [US3] Wait for ArgoCD Tailscale serve pod to restart
- [X] T034 [US3] Verify ArgoCD accessible at `https://argocd-<cluster>.<tailnet>.ts.net` ✅

**Checkpoint**: ArgoCD stable URL working - SC-007 validated

---

## Phase 6: User Story 4 - All Platform Services Stable URLs (Priority: P2)

**Goal**: All 7 platform services accessible via stable URLs

**Independent Test**: Access each service via `https://<service>-<cluster>.<tailnet>.ts.net`

### Prerequisites: ACL Auto-Approvers

- [X] T035 [P] [US4] Add ACL auto-approver for `svc:langfuse` with `tag:k8s-services`
- [X] T036 [P] [US4] Add ACL auto-approver for `svc:gitea` with `tag:k8s-services`
- [X] T037 [P] [US4] Add ACL auto-approver for `svc:kagent` with `tag:k8s-services`
- [X] T038 [P] [US4] Add ACL auto-approver for `svc:kargo` with `tag:k8s-services`
- [X] T039 [P] [US4] Add ACL auto-approver for `svc:headlamp` with `tag:k8s-services`
- [X] T040 [P] [US4] Add ACL auto-approver for `svc:keycloak` with `tag:k8s-services`

### Implementation for User Story 4

- [X] T041 [P] [US4] Update Langfuse service name from `langfuse2` to `langfuse` in `cdk8s/config/applications.ts`
- [X] T042 [P] [US4] Update Gitea service name from `gitea2` to `gitea` in `cdk8s/config/applications.ts`
- [X] T043 [P] [US4] Update kagent service name from `kagent2` to `kagent` in `cdk8s/config/applications.ts`
- [X] T044 [P] [US4] Update Kargo service name from `kargo2` to `kargo` in `cdk8s/config/applications.ts`
- [X] T045 [P] [US4] Update Headlamp service name from `headlamp2` to `headlamp` in `cdk8s/config/applications.ts`
- [X] T046 [P] [US4] Update Keycloak service name from `keycloak2` to `keycloak` in `cdk8s/config/applications.ts`
- [X] T047 [US4] Update Langfuse `nextAuthUrl` to use new service URL in `cdk8s/config/applications.ts`
- [X] T048 [US4] Run TypeScript type check (`cd cdk8s && npx tsc --noEmit`)
- [X] T049 [US4] Synthesize CDK8s packages (`cd cdk8s && npx ts-node main-v2.ts`)
- [X] T050 [US4] Deploy changes (`cluster-update`)
- [X] T051 [US4] Verify all services accessible via stable URLs ✅ All 7 services HTTP/2 200

**Checkpoint**: All 7 services with stable URLs - SC-008 validated

---

## Phase 7: User Story 5 - Charts Use Helpers (Priority: P2)

**Goal**: All Tailscale serve charts use `TailscaleServeHelpers` from shared library

**Independent Test**: Verify all serve charts import from `cdk8s/lib/tailscale-serve-helpers.ts`

### Implementation for User Story 5

- [X] T052 [US5] Verify `cdk8s/charts/platform/tailscale-serve-chart.ts` imports from `tailscale-serve-helpers.ts`
- [X] T053 [US5] Verify all serve chart entries in `cdk8s/config/applications.ts` use `TailscaleServeChart` type
- [X] T054 [US5] Run `grep -r "TailscaleServeHelpers" cdk8s/charts/` to confirm usage

**Checkpoint**: Helper library compliance verified - SC-011 validated

---

## Phase 8: User Story 6 - Auth Keys via External Secrets (Priority: P2)

**Goal**: Auth keys sourced from Azure Key Vault via ESO

**Independent Test**: Verify ExternalSecret resources sync auth keys from Azure Key Vault

### Implementation for User Story 6

- [X] T055 [US6] Verify `TAILSCALE-AUTH-KEY` exists in Azure Key Vault with `tag:k8s-services` tag ✅ Updated
- [X] T056 [US6] Verify ExternalSecret resource in `cdk8s/charts/secrets/tailscale-secrets-chart.ts` syncs auth key
- [X] T057 [US6] Run `kubectl get externalsecret -n tailscale` to verify sync status ✅ secret synced
- [X] T058 [US6] Run `kubectl get secret tailscale-auth-key -n tailscale -o yaml` to verify secret exists

**Checkpoint**: Auth keys from ESO verified - SC-012 validated

---

## Phase 9: User Story 7 - Deprecate kubectl-proxy Chart (Priority: P3)

**Goal**: Remove redundant custom kubectl-proxy chart after Operator API Proxy validated

**Independent Test**: Verify kubectl works via Operator API Proxy, then remove custom chart

**Prerequisites**: US1 validated for 48+ hours

### Implementation for User Story 7

- [X] T059 [US7] Final verification: kubectl works via Operator API Proxy ✅ vpittamp@github
- [ ] T060 [US7] Remove `k8s-api-tailscale-serve` entry from `cdk8s/config/applications.ts` (OPTIONAL - P3)
- [ ] T061 [US7] Delete chart file: `rm cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts` (OPTIONAL - P3)
- [ ] T062 [US7] Remove chart registration from `cdk8s/main-v2.ts` (if present) (OPTIONAL - P3)
- [ ] T063 [US7] Run TypeScript type check (`cd cdk8s && npx tsc --noEmit`) (OPTIONAL - P3)
- [ ] T064 [US7] Synthesize CDK8s packages (`cd cdk8s && npx ts-node main-v2.ts`) (OPTIONAL - P3)
- [ ] T065 [US7] Deploy changes (`cluster-update`) (OPTIONAL - P3)
- [ ] T066 [US7] Clean up Kubernetes resources (OPTIONAL - P3)
- [ ] T067 [US7] Clean up ClusterRoleBinding (OPTIONAL - P3)
- [ ] T068 [US7] Verify no custom kubectl-proxy remains (OPTIONAL - P3)

**Checkpoint**: Custom kubectl-proxy removed - SC-014 validated

---

## Phase 10: User Story 8 - Remove Legacy Code (Priority: P3)

**Goal**: Remove all legacy hostname mode code from charts

**Independent Test**: Verify no `legacyHostnameMode` flags or hostname-based configurations remain

### Implementation for User Story 8

- [X] T069 [US8] Search for legacy patterns: `grep -r "legacyHostnameMode\|hostname-based" cdk8s/` ✅ None found
- [X] T070 [US8] Remove any legacy hostname mode flags found in charts ✅ N/A
- [X] T071 [US8] Verify all serve charts use `--service` flag pattern only ✅
- [X] T072 [US8] Run TypeScript type check (`cd cdk8s && npx tsc --noEmit`) ✅
- [X] T073 [US8] Synthesize CDK8s packages (`cd cdk8s && npx ts-node main-v2.ts`) ✅

**Checkpoint**: Legacy code removed - SC-013 validated

---

## Phase 11: Polish & Documentation

**Purpose**: Update documentation with final architecture

- [X] T074 [P] Update CLAUDE.md Tailscale Operator section with auth mode configuration ✅
- [X] T075 [P] Update CLAUDE.md with `tailscale configure kubeconfig` instructions ✅
- [X] T076 Update CLAUDE.md Tailscale Services section with all 7 service URLs ✅
- [X] T077 Remove CLAUDE.md references to old `2` suffixed service names ✅
- [X] T078 Update quickstart.md with test results and final URLs ✅
- [X] T079 Run full quickstart.md validation checklist ✅ All SC passed
- [ ] T080 Commit all changes with Constitution compliance notes (user action)

**Checkpoint**: Documentation updated - SC-015 validated

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS User Story 1
- **User Story 1 (Phase 3)**: Depends on Foundational - P0 priority, MVP
- **User Story 2 (Phase 4)**: Depends on Setup only - can run parallel to US1
- **User Story 3 (Phase 5)**: Depends on Setup + US2 cleanup - P1 priority
- **User Story 4 (Phase 6)**: Depends on US3 pattern validation - P2 priority
- **User Story 5 (Phase 7)**: Can verify in parallel with any phase - P2 priority
- **User Story 6 (Phase 8)**: Can verify in parallel with any phase - P2 priority
- **User Story 7 (Phase 9)**: Depends on US1 validated 48+ hours - P3 priority
- **User Story 8 (Phase 10)**: Can run after US7 - P3 priority
- **Polish (Phase 11)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P0)**: Foundational ACL setup required first
- **US2 (P1)**: Independent - can start after Setup
- **US3 (P1)**: Depends on US2 (stale devices must be removed first)
- **US4 (P2)**: Depends on US3 pattern (extend ArgoCD pattern to all services)
- **US5 (P2)**: Independent verification task
- **US6 (P2)**: Independent verification task
- **US7 (P3)**: Depends on US1 being validated for 48+ hours
- **US8 (P3)**: Depends on US7 (remove kubectl-proxy first, then other legacy code)

### Parallel Opportunities

- Phase 2 tasks T006-T008 can run in parallel (different ACL sections)
- Phase 4 device deletions T020-T026 can all run in parallel
- Phase 6 ACL auto-approvers T035-T040 can all run in parallel
- Phase 6 service name updates T041-T046 can all run in parallel
- Phase 11 documentation updates T074-T075 can run in parallel

---

## Parallel Example: Phase 6 Service Updates

```bash
# Launch all ACL auto-approvers in parallel:
Task: "Add ACL auto-approver for svc:langfuse"
Task: "Add ACL auto-approver for svc:gitea"
Task: "Add ACL auto-approver for svc:kagent"
Task: "Add ACL auto-approver for svc:kargo"
Task: "Add ACL auto-approver for svc:headlamp"
Task: "Add ACL auto-approver for svc:keycloak"

# Launch all service name updates in parallel:
Task: "Update Langfuse service name in applications.ts"
Task: "Update Gitea service name in applications.ts"
Task: "Update kagent service name in applications.ts"
Task: "Update Kargo service name in applications.ts"
Task: "Update Headlamp service name in applications.ts"
Task: "Update Keycloak service name in applications.ts"
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only)

1. Complete Phase 1: Setup verification
2. Complete Phase 2: Foundational ACL configuration
3. Complete Phase 3: User Story 1 (kubectl OAuth)
4. **STOP and VALIDATE**: Test kubectl from M1 Mac
5. Complete Phase 4: User Story 2 (stale device cleanup)
6. Complete Phase 5: User Story 3 (ArgoCD stable URL)
7. **DEPLOY MVP**: kubectl + ArgoCD working with stable access

### Incremental Delivery

1. Setup + Foundational → ACL ready
2. Add US1 → Test independently → kubectl OAuth working (MVP!)
3. Add US2 + US3 → Test independently → ArgoCD stable URL
4. Add US4 → Test independently → All services stable URLs
5. Add US5-US6 → Verify compliance
6. Add US7-US8 → Cleanup legacy code
7. Each story adds value without breaking previous stories

### Recommended Execution Order

For a single developer:
1. **Day 1**: Phases 1-3 (Setup, Foundational, US1) - kubectl working
2. **Day 2**: Phases 4-5 (US2, US3) - ArgoCD stable URL
3. **Day 3**: Phase 6 (US4) - All services stable URLs
4. **Wait 48h**: Let US1 run for validation period
5. **Day 5**: Phases 7-10 (US5-US8) - Verification and cleanup
6. **Day 5**: Phase 11 (Polish) - Documentation

---

## Notes

- [P] tasks = different files/resources, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Manual Tailscale Admin Console tasks must be done in the browser
- Commit after each phase or logical group
- Stop at any checkpoint to validate story independently
- US7 has a 48-hour waiting period (validation gate)
- ACL changes take effect immediately but may need 60s propagation
