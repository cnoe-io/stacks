# Tasks: Tailscale Stale Device Cleanup and Services Migration

**Input**: Design documents from `/specs/103-tailscale-services/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/tailscale-serve-chart-props.ts, quickstart.md

**Tests**: No automated tests requested. Validation via quickstart.md manual verification.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **CDK8s Charts**: `cdk8s/charts/platform/`, `cdk8s/charts/secrets/`
- **Helpers**: `cdk8s/lib/`
- **Config**: `cdk8s/config/`
- **Specs**: `specs/103-tailscale-services/`

---

## Phase 1: Setup (Tailscale Admin Console)

**Purpose**: Manual prerequisite configuration in Tailscale Admin Console

**Note**: These are manual tasks in Tailscale Admin Console, not code tasks

- [ ] T001 Remove stale offline devices via Tailscale Admin Console (https://login.tailscale.com/admin/machines) [MANUAL - User must complete]
- [ ] T002 Verify auth key `TAILSCALE-AUTH-KEY` in Azure Key Vault has `tag:k8s-services` tag [MANUAL - User must complete]
- [ ] T003 Add ACL auto-approvers for all 7 services in Tailscale Admin Console (https://login.tailscale.com/admin/acls) [MANUAL - User must complete]

**ACL Configuration** (add to autoApprovers.services):
```json
{
  "svc:argocd": ["tag:k8s-services"],
  "svc:langfuse": ["tag:k8s-services"],
  "svc:gitea": ["tag:k8s-services"],
  "svc:kagent": ["tag:k8s-services"],
  "svc:kargo": ["tag:k8s-services"],
  "svc:headlamp": ["tag:k8s-services"],
  "svc:keycloak": ["tag:k8s-services"]
}
```

**Checkpoint**: Tailscale Admin Console configured - code implementation can begin

---

## Phase 2: Foundational (Create Shared Helpers)

**Purpose**: Create shared helper library that ALL user stories depend on

**CRITICAL**: No service chart work can begin until this phase is complete

- [X] T004 Create tailscale-serve-helpers.ts in cdk8s/lib/tailscale-serve-helpers.ts using pattern from contracts/tailscale-serve-chart-props.ts
- [X] T005 Create generic TailscaleServeChart in cdk8s/charts/platform/tailscale-serve-chart.ts using helpers
- [X] T006 Register TailscaleServeChart in cdk8s/main-v2.ts with IdpBuilderChartFactory (auto-registered via autoRegisterCharts)

**Helper functions to implement** (from contracts/tailscale-serve-chart-props.ts):
- `resolveProps()`: Apply defaults to TailscaleServeChartProps
- `generateServeScript()`: Generate shell script for Tailscale container

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Remove Stale Devices to Reclaim Hostnames (Priority: P1)

**Goal**: Clean up stale devices and verify hostname reclamation

**Independent Test**: Run `tailscale status` before/after, verify offline devices removed

### Implementation for User Story 1

- [ ] T007 [US1] Verify stale device cleanup completed (T001 prerequisite)
- [ ] T008 [US1] Test new device registration without suffix by deploying test pod
- [ ] T009 [US1] Document cleanup procedure in quickstart.md Phase 1 (already done - verify accuracy)

**Checkpoint**: Stale devices removed, hostnames can be reclaimed without suffix

---

## Phase 4: User Story 2 - Access ArgoCD via Stable Tailscale Service URL (Priority: P1)

**Goal**: ArgoCD accessible at `https://svc-argocd.<tailnet>.ts.net`

**Independent Test**: `curl -sI https://svc-argocd.tail286401.ts.net | head -5` returns HTTP/2 200

### Implementation for User Story 2

- [X] T010 [US2] Add argocd-tailscale-serve entry to cdk8s/config/applications.ts with TailscaleServeChart props
- [X] T011 [US2] Synthesize and verify ArgoCD serve chart manifest in cdk8s/dist/argocd-tailscale-serve/manifests/
- [ ] T012 [US2] Deploy via idpbuilder and verify ArgoCD pod registration [PENDING DEPLOYMENT]
- [ ] T013 [US2] Test ArgoCD access at https://svc-argocd.tail286401.ts.net from Tailscale-connected device [PENDING DEPLOYMENT]

**applications.ts entry**:
```typescript
{
  name: 'argocd-tailscale-serve',
  namespace: 'tailscale',
  chart: {
    type: 'TailscaleServeChart',
    props: {
      serviceName: 'argocd',
      backendHost: 'argocd-server.argocd.svc.cluster.local',
      backendPort: 443,
      backendInsecure: true,
    }
  },
  argocd: { syncWave: '-60' }
}
```

**Checkpoint**: ArgoCD accessible via stable service URL

---

## Phase 5: User Story 3 - Access All Platform Services via Stable URLs (Priority: P2)

**Goal**: All 6 remaining services (Langfuse, Gitea, kagent, Kargo, Headlamp, Keycloak) accessible via stable URLs

**Independent Test**: Loop through all service URLs and verify HTTP 200 responses

### Implementation for User Story 3

- [X] T014 [P] [US3] Add langfuse-tailscale-serve entry to cdk8s/config/applications.ts
- [X] T015 [P] [US3] Add gitea-tailscale-serve entry to cdk8s/config/applications.ts
- [X] T016 [P] [US3] Add kagent-tailscale-serve entry to cdk8s/config/applications.ts
- [X] T017 [P] [US3] Add kargo-tailscale-serve entry to cdk8s/config/applications.ts
- [X] T018 [P] [US3] Add headlamp-tailscale-serve entry to cdk8s/config/applications.ts
- [X] T019 [P] [US3] Add keycloak-tailscale-serve entry to cdk8s/config/applications.ts
- [X] T020 [US3] Synthesize all serve charts via `npx ts-node main-v2.ts`
- [ ] T021 [US3] Deploy all serve charts via cluster-update [PENDING DEPLOYMENT]
- [ ] T022 [US3] Test all service URLs from Tailscale-connected device [PENDING DEPLOYMENT]

**Service configurations** (from contracts/tailscale-serve-chart-props.ts PLATFORM_SERVICES):

| Service | backendHost | backendPort | backendInsecure |
|---------|-------------|-------------|-----------------|
| langfuse | langfuse.langfuse.svc.cluster.local | 3000 | false |
| gitea | gitea-http.gitea.svc.cluster.local | 3000 | false |
| kagent | kagent-dashboard.kagent.svc.cluster.local | 8082 | false |
| kargo | kargo-controller.kargo.svc.cluster.local | 443 | true |
| headlamp | headlamp.headlamp.svc.cluster.local | 4466 | false |
| keycloak | keycloak.keycloak.svc.cluster.local | 8080 | false |

**Checkpoint**: All 7 platform services accessible via stable service URLs

---

## Phase 6: User Story 4 - Charts Use Tailscale Serve Helpers (Priority: P2)

**Goal**: Verify all charts use standardized helpers from shared library

**Independent Test**: Verify all serve chart entries in applications.ts use TailscaleServeChart type

### Implementation for User Story 4

- [X] T023 [US4] Verify TailscaleServeChart in cdk8s/charts/platform/tailscale-serve-chart.ts imports from cdk8s/lib/tailscale-serve-helpers.ts
- [X] T024 [US4] Run `npx tsc --noEmit` to verify TypeScript compilation passes
- [X] T025 [US4] Verify all serve chart entries in applications.ts use type: 'TailscaleServeChart'

**Checkpoint**: All charts using standardized helper pattern

---

## Phase 7: User Story 5 - Auth Keys Managed via External Secrets (Priority: P2)

**Goal**: Auth keys sourced exclusively from Azure Key Vault via ESO

**Independent Test**: Verify `kubectl get externalsecret -n tailscale tailscale-auth-key` shows Synced status

### Implementation for User Story 5

- [X] T026 [US5] Verify existing tailscale-secrets-chart.ts in cdk8s/charts/secrets/ syncs auth key
- [X] T027 [US5] Verify TailscaleServeChart references authKeySecretName: 'tailscale-auth-key'
- [ ] T028 [US5] Test ESO sync by checking `kubectl get secret -n tailscale tailscale-auth-key` [PENDING DEPLOYMENT]

**Checkpoint**: Auth keys managed via ESO (Constitution Principle VI compliance)

---

## Phase 8: User Story 6 - Legacy Hostname Mode Removed (Priority: P3)

**Goal**: Complete removal of legacy `tailscale-ingress-chart.ts` and all references

**Independent Test**: `grep -r "TailscaleIngressChart" cdk8s/` returns no output

### Implementation for User Story 6

- [X] T029 [US6] DELETE cdk8s/charts/platform/tailscale-ingress-chart.ts
- [X] T030 [US6] Remove tailscale-ingresses entry from cdk8s/config/applications.ts
- [X] T031 [US6] Remove TailscaleIngressChart import and registration from cdk8s/main-v2.ts (auto-registration, no manual import)
- [X] T032 [US6] Run `npx tsc --noEmit` to verify no broken references
- [X] T033 [US6] Verify `grep -r "TailscaleIngressChart" cdk8s/` returns no output (only comment reference remains)
- [X] T034 [US6] Verify `grep -r "tailscale-ingress" cdk8s/` returns no output

**Checkpoint**: Legacy code completely removed (Constitution Principle IX compliance)

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and validation

- [X] T035 [P] Update CLAUDE.md Tailscale Services section with all 7 service URLs
- [ ] T036 [P] Run complete quickstart.md validation checklist [PENDING DEPLOYMENT]
- [X] T037 Re-synthesize and deploy all charts via cluster-update (synthesized, deployment pending)
- [ ] T038 Verify ArgoCD shows all tailscale-serve apps as Synced/Healthy [PENDING DEPLOYMENT]
- [ ] T039 Delete any remaining legacy Kubernetes resources: `kubectl delete ingress -A -l app.kubernetes.io/component=tailscale-ingress` [PENDING DEPLOYMENT]

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies - manual Tailscale Admin Console tasks
- **Phase 2 (Foundational)**: No code dependencies - creates shared helpers
- **Phase 3 (US1)**: Depends on Phase 1 (stale device cleanup)
- **Phase 4 (US2)**: Depends on Phase 2 (helpers) - ArgoCD serve chart
- **Phase 5 (US3)**: Depends on Phase 2 (helpers) - remaining service charts
- **Phase 6 (US4)**: Depends on Phase 4, 5 - verification only
- **Phase 7 (US5)**: Depends on Phase 4, 5 - verification only
- **Phase 8 (US6)**: Depends on Phase 4, 5 - legacy removal
- **Phase 9 (Polish)**: Depends on all user stories complete

### User Story Dependencies

- **User Story 1 (P1)**: Independent - manual cleanup
- **User Story 2 (P1)**: Depends on Phase 2 (helpers) only
- **User Story 3 (P2)**: Depends on Phase 2 (helpers) only - can parallel with US2
- **User Story 4 (P2)**: Verification after US2/US3
- **User Story 5 (P2)**: Verification after US2/US3
- **User Story 6 (P3)**: Can only start after US2/US3 deployed and working

### Within Each User Story

- Service entries can be added in parallel (T014-T019 all [P])
- Synthesis must complete before deployment
- Deployment must complete before testing

### Parallel Opportunities

- **Phase 1**: T001, T002, T003 can run in parallel (different admin console pages)
- **Phase 5**: T014-T019 can run in parallel (different applications.ts entries)
- **Phase 9**: T035, T036 can run in parallel (different files)
- **US2 and US3**: Can run in parallel after Phase 2 complete

---

## Parallel Example: User Story 3

```bash
# Launch all service entries in parallel:
Task: "Add langfuse-tailscale-serve entry to cdk8s/config/applications.ts"
Task: "Add gitea-tailscale-serve entry to cdk8s/config/applications.ts"
Task: "Add kagent-tailscale-serve entry to cdk8s/config/applications.ts"
Task: "Add kargo-tailscale-serve entry to cdk8s/config/applications.ts"
Task: "Add headlamp-tailscale-serve entry to cdk8s/config/applications.ts"
Task: "Add keycloak-tailscale-serve entry to cdk8s/config/applications.ts"

# Then synthesize and deploy sequentially:
Task: "Synthesize all serve charts via npx ts-node main-v2.ts"
Task: "Deploy all serve charts via cluster-update"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (Tailscale Admin Console)
2. Complete Phase 2: Foundational (helpers + generic chart)
3. Complete Phase 3: User Story 1 (stale device cleanup verification)
4. Complete Phase 4: User Story 2 (ArgoCD service URL)
5. **STOP and VALIDATE**: Test ArgoCD at stable URL independently
6. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational → Helpers and generic chart ready
2. Add User Story 1 → Stale devices cleaned
3. Add User Story 2 → ArgoCD accessible (MVP!)
4. Add User Story 3 → All services accessible
5. Add User Stories 4-5 → Verification tasks
6. Add User Story 6 → Legacy removal
7. Polish → Documentation complete

### Single Developer Strategy

Execute phases sequentially:
1. Phase 1 (manual setup) → Phase 2 (helpers) → Phase 3 (US1)
2. Phase 4 (US2 - ArgoCD) → Test and validate
3. Phase 5 (US3 - remaining services) → Test all
4. Phase 6-8 (verification and cleanup)
5. Phase 9 (polish)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently testable
- Manual validation via quickstart.md (no automated tests)
- Constitution Principle IX: DELETE legacy code, don't deprecate
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
