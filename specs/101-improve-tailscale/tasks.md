# Tasks: Tailscale Services Migration

**Input**: Design documents from `/specs/101-improve-tailscale/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Manual verification via curl and kubectl (no automated tests for infrastructure changes)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## User Story Mapping

| Story | Title | Priority | Files |
|-------|-------|----------|-------|
| US1 | Access ArgoCD Dashboard Remotely | P1 | `argocd-tailscale-serve-chart.ts` |
| US2 | Access Langfuse Dashboard | P2 | `langfuse-tailscale-serve-chart.ts` |
| US3 | Remote kubectl Access | P2 | (out of scope - uses existing operator) |
| US4 | Consistent Hostnames Across Recreations | P1 | (cross-cutting - validated by US1/US2) |

**Note**: US3 (kubectl access) is out of scope per spec - existing Tailscale operator APISERVER_PROXY provides this. US4 is validated by testing US1 and US2 after cluster recreation.

---

## Phase 1: Setup (Tailscale Admin Console)

**Purpose**: One-time Tailscale Admin Console configuration (manual, outside cluster)

- [x] T001 Update ACL policy: Add `tag:k8s-services` to `tagOwners` in Tailscale Admin Console
- [x] T002 Update ACL policy: Add `services` block to `autoApprovers` with `svc:argocd-<cluster>`, `svc:langfuse-<cluster>` in Tailscale Admin Console
- [x] T003 Update ACL policy: Add ACL rules for `tag:k8s-services` traffic in Tailscale Admin Console
- [x] T004 Define service `argocd-<cluster>` with endpoint `tcp:443` in Tailscale Admin Console → Services
- [x] T005 Define service `langfuse-<cluster>` with endpoint `tcp:443` in Tailscale Admin Console → Services
- [x] T006 Generate tagged auth key (reusable, ephemeral, tag:k8s-services) in Tailscale Admin Console → Settings → Keys

**Checkpoint**: Tailscale Admin Console fully configured - save auth key for Phase 2

---

## Phase 2: Foundational (Secrets & Shared Code)

**Purpose**: Core infrastructure that MUST be complete before ANY chart updates

**⚠️ CRITICAL**: No chart changes can work until this phase is complete

- [x] T007 Update Azure Key Vault secret `tailscale-auth-key` with new tagged auth key
- [x] T008 Trigger External Secrets sync by deleting secret: `kubectl delete secret tailscale-auth-key -n tailscale`
- [x] T009 Verify secret synced: `kubectl get secret tailscale-auth-key -n tailscale`
- [x] T010 [P] Create shared helper library in cdk8s/lib/tailscale-serve-helpers.ts
- [x] T011 [P] Copy contract interface from specs/101-improve-tailscale/contracts/tailscale-serve-chart-props.ts to cdk8s/lib/tailscale-serve-chart-props.ts

**Checkpoint**: Foundation ready - chart updates can now begin

---

## Phase 3: User Story 1 - Access ArgoCD Dashboard Remotely (Priority: P1) 🎯 MVP

**Goal**: Platform engineers can access ArgoCD at stable URL `https://argocd-<cluster>.<tailnet>.ts.net` that survives cluster recreation

**Independent Test**: From Tailscale-connected device, `curl -sI https://argocd-<cluster>.<tailnet>.ts.net` returns HTTP 200/302

### Implementation for User Story 1

- [x] T012 [US1] Update ArgoCdTailscaleServeChart interface to accept TailscaleServeChartProps in cdk8s/charts/platform/argocd-tailscale-serve-chart.ts
- [x] T013 [US1] Update ArgoCdTailscaleServeChart constructor to use props.serviceName for service registration in cdk8s/charts/platform/argocd-tailscale-serve-chart.ts
- [x] T014 [US1] Update `tailscale serve` command to use `--service=svc:${serviceName} --https=${exposedPort}` syntax in cdk8s/charts/platform/argocd-tailscale-serve-chart.ts
- [x] T015 [US1] Remove hardcoded `TS_HOSTNAME` env var (no longer needed with Services) in cdk8s/charts/platform/argocd-tailscale-serve-chart.ts
- [x] T016 [US1] Add backward compatibility: support legacyHostnameMode prop in cdk8s/charts/platform/argocd-tailscale-serve-chart.ts
- [x] T017 [US1] Update argocd-tailscale-serve config in cdk8s/config/applications.ts with serviceName='argocd', backendHost, backendPort, backendInsecure props
- [x] T018 [US1] Synthesize charts: `cd cdk8s && npx ts-node main-v2.ts`
- [x] T019 [US1] Deploy via ArgoCD sync or `argocd-sync argocd/argocd-tailscale-serve`
- [x] T020 [US1] Verify pod running: `kubectl get pods -n tailscale -l app.kubernetes.io/name=argocd-tailscale-serve`
- [x] T021 [US1] Verify pod logs show service registration: `kubectl logs -n tailscale -l app.kubernetes.io/name=argocd-tailscale-serve --tail=20`
- [x] T022 [US1] Verify service active in Tailscale Admin Console → Services → argocd-<cluster>
- [x] T023 [US1] Test access from Tailscale device: `curl -sI https://argocd-<cluster>.<tailnet>.ts.net`

**Checkpoint**: ArgoCD accessible at stable service URL - US1 complete and independently testable

---

## Phase 4: User Story 2 - Access Langfuse Dashboard (Priority: P2)

**Goal**: ML engineers can access Langfuse at stable URL `https://langfuse-<cluster>.<tailnet>.ts.net` with working authentication

**Independent Test**: From Tailscale-connected device, navigate to `https://langfuse-<cluster>.<tailnet>.ts.net` and successfully authenticate

### Implementation for User Story 2

- [x] T024 [P] [US2] Update LangfuseTailscaleServeChart interface to accept TailscaleServeChartProps in cdk8s/charts/platform/langfuse-tailscale-serve-chart.ts
- [x] T025 [US2] Update LangfuseTailscaleServeChart constructor to use props.serviceName in cdk8s/charts/platform/langfuse-tailscale-serve-chart.ts
- [x] T026 [US2] Update `tailscale serve` command to use `--service=svc:${serviceName} --https=${exposedPort}` syntax in cdk8s/charts/platform/langfuse-tailscale-serve-chart.ts
- [x] T027 [US2] Remove hardcoded `TS_HOSTNAME` env var in cdk8s/charts/platform/langfuse-tailscale-serve-chart.ts
- [x] T028 [US2] Add backward compatibility: support legacyHostnameMode prop in cdk8s/charts/platform/langfuse-tailscale-serve-chart.ts
- [x] T029 [US2] Update langfuse-tailscale-serve config in cdk8s/config/applications.ts with serviceName='langfuse', backendHost, backendPort props
- [x] T030 [US2] Update Langfuse chart nextAuthUrl to use new service URL in cdk8s/config/applications.ts (langfuse config)
- [x] T031 [US2] Synthesize charts: `cd cdk8s && npx ts-node main-v2.ts`
- [x] T032 [US2] Deploy via ArgoCD sync or `argocd-sync argocd/langfuse-tailscale-serve`
- [x] T033 [US2] Verify pod running: `kubectl get pods -n tailscale -l app.kubernetes.io/name=langfuse-tailscale-serve`
- [x] T034 [US2] Verify service active in Tailscale Admin Console → Services → langfuse-<cluster>
- [x] T035 [US2] Test access and authentication: navigate to `https://langfuse-<cluster>.<tailnet>.ts.net` and login

**Checkpoint**: Langfuse accessible at stable service URL with working auth - US2 complete

---

## Phase 5: User Story 4 - Consistent Hostnames Across Recreations (Priority: P1)

**Goal**: Validate that service URLs remain stable after cluster recreation

**Independent Test**: Recreate cluster and verify same URLs work without changes

**Note**: This is a validation phase - no code changes, only testing

### Validation for User Story 4

- [ ] T036 [US4] Record current service URLs: `argocd-<cluster>.<tailnet>.ts.net`, `langfuse-<cluster>.<tailnet>.ts.net`
- [ ] T037 [US4] Delete cluster: `idpbuilder delete --name localdev`
- [ ] T038 [US4] Recreate cluster: `idpbuilder create --package cdk8s/dist/`
- [ ] T039 [US4] Wait for pods: `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-tailscale-serve -n tailscale --timeout=300s`
- [ ] T040 [US4] Verify ArgoCD URL unchanged: `curl -sI https://argocd-<cluster>.<tailnet>.ts.net` returns HTTP 200/302
- [ ] T041 [US4] Verify Langfuse URL unchanged: `curl -sI https://langfuse-<cluster>.<tailnet>.ts.net` returns HTTP 200/302
- [ ] T042 [US4] Verify no `-1`, `-2` suffixes in Tailscale Admin Console → Machines

**Checkpoint**: Hostname stability validated across cluster recreation - US4 complete

---

## Phase 6: Polish & Documentation

**Purpose**: Documentation and cleanup

- [x] T043 [P] Create migration guide in docs/tailscale-services-migration.md
- [x] T044 [P] Update CLAUDE.md Tailscale section with new service URLs and usage instructions
- [ ] T045 Update quickstart.md with actual tested service URLs in specs/101-improve-tailscale/quickstart.md
- [ ] T046 Remove deprecated code paths if legacyHostnameMode not needed
- [ ] T047 Commit all changes with descriptive message

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)          ──────────────────────────────────────┐
   │                                                            │
   ▼                                                            │
Phase 2 (Foundational)   ──────────────────────────────────────┼──► BLOCKS all chart work
   │                                                            │
   ├────────────────────┬───────────────────────────────────────┘
   │                    │
   ▼                    ▼
Phase 3 (US1/ArgoCD)   Phase 4 (US2/Langfuse)   ◄── Can run in parallel
   │                    │
   └────────┬───────────┘
            │
            ▼
Phase 5 (US4/Validation)  ◄── Requires US1 and US2 complete
            │
            ▼
Phase 6 (Polish)
```

### User Story Dependencies

- **US1 (ArgoCD)**: Depends on Phase 1 + Phase 2 completion
- **US2 (Langfuse)**: Depends on Phase 1 + Phase 2 completion, can run in parallel with US1
- **US3 (kubectl)**: Out of scope - existing operator functionality
- **US4 (Hostname Stability)**: Depends on US1 and US2 being deployed and working

### Parallel Opportunities

**Phase 2** (after Phase 1):
```bash
# Launch in parallel:
Task T010: "Create shared helper library in cdk8s/lib/tailscale-serve-helpers.ts"
Task T011: "Copy contract interface to cdk8s/lib/tailscale-serve-chart-props.ts"
```

**Phase 3 + Phase 4** (after Phase 2):
```bash
# Can run in parallel if multiple developers:
# Developer A: US1 (T012-T023)
# Developer B: US2 (T024-T035)
```

**Phase 6** (documentation):
```bash
# Launch in parallel:
Task T043: "Create migration guide in docs/tailscale-services-migration.md"
Task T044: "Update CLAUDE.md Tailscale section"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Tailscale Admin Console setup
2. Complete Phase 2: Secrets + shared code
3. Complete Phase 3: ArgoCD service migration (US1)
4. **STOP and VALIDATE**: Test ArgoCD via stable service URL
5. Deploy/demo if ready - ArgoCD alone provides immediate value

### Full Implementation

1. Complete Setup + Foundational (Phases 1-2)
2. Complete US1 (ArgoCD) → Test → **MVP Complete!**
3. Complete US2 (Langfuse) → Test
4. Complete US4 (Validation) → Cluster recreation test
5. Complete Polish (Documentation)

### Time Estimates

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| Phase 1 (Setup) | T001-T006 | 15-20 minutes |
| Phase 2 (Foundational) | T007-T011 | 10-15 minutes |
| Phase 3 (US1) | T012-T023 | 30-45 minutes |
| Phase 4 (US2) | T024-T035 | 20-30 minutes |
| Phase 5 (US4) | T036-T042 | 15-20 minutes (cluster recreation time) |
| Phase 6 (Polish) | T043-T047 | 15-20 minutes |
| **Total** | 47 tasks | ~2-2.5 hours |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Manual Tailscale Admin Console tasks (Phase 1) cannot be automated
- External Secrets sync may take up to 1h (or force with `kubectl delete secret`)
- Service URLs format: `https://<name>.<tailnet>.ts.net`
- Test from Tailscale-connected device only
- Commit after each phase or logical group
