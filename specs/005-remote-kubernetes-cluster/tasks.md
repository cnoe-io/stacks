# Tasks: Remote Kubernetes Cluster Access via Tailscale

**Input**: Design documents from `/home/vpittamp/stacks/specs/005-remote-kubernetes-cluster/`
**Prerequisites**: plan.md (complete), spec.md (complete), research-coredns.md (complete), research-tls-only.md (complete)

**Tests**: Testing is performed interactively via tmux pane %31 on Mac machine connected to Tailscale network. No automated test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **CDK8s charts**: `cdk8s/charts/infra/`
- **Config files**: `cdk8s/config/`
- **Helper scripts**: `deployment/scripts/tailscale/`
- **Documentation**: `docs/`, `specs/005-remote-kubernetes-cluster/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, script directories, and documentation structure

- [X] T001 Create helper script directory structure: `mkdir -p deployment/scripts/tailscale`
- [X] T002 [P] Create documentation placeholder: `touch docs/tailscale-cluster-access.md`
- [X] T003 [P] Create quickstart documentation: `specs/005-remote-kubernetes-cluster/quickstart.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core TailscaleOperatorChart modifications that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [US1] Remove ProxyGroup conflict from TailscaleOperatorChart in `cdk8s/charts/infra/tailscale-operator-chart.ts` (lines 329-348) - change condition from `props.enableHA || ['staging', 'production'].includes(props.environmentName)` to `props.enableHA && props.environmentName === 'production'` to prevent ProxyGroup creation in dev environment
- [X] T005 [US1] Add SecurityContext to operator deployment in `cdk8s/charts/infra/tailscale-operator-chart.ts` - add `securityContext` with `runAsNonRoot: true`, `readOnlyRootFilesystem: false`, `allowPrivilegeEscalation: false` to container spec (after line 266)
- [X] T006 [US1] Add resource limits to operator deployment in `cdk8s/charts/infra/tailscale-operator-chart.ts` - add `resources` with `limits: { cpu: '500m', memory: '256Mi' }`, `requests: { cpu: '100m', memory: '128Mi' }` to container spec
- [X] T007 [US1] Verify `APISERVER_PROXY=true` remains enabled in operator deployment env vars in `cdk8s/charts/infra/tailscale-operator-chart.ts` (line 290) - no changes needed, validation only
- [X] T008 [US1] Verify `OPERATOR_HOSTNAME` uses `clusterName-operator` pattern in `cdk8s/charts/infra/tailscale-operator-chart.ts` (line 274) - no changes needed, validation only
- [X] T009 [US1] Verify operator image version is `tailscale/k8s-operator:v1.88.3` in `cdk8s/charts/infra/tailscale-operator-chart.ts` (line 96) - no changes needed, validation only

**Checkpoint**: Foundation ready - Tailscale operator chart is properly configured for API server proxy mode

---

## Phase 3: User Story 1 - Remote kubectl Access from Any Device (Priority: P1) 🎯 MVP

**Goal**: Enable platform engineers to securely access Kubernetes cluster using kubectl from any Tailscale-connected device with <2 second response times

**Independent Test**: From Mac (tmux pane %31), run `kubectl --kubeconfig=remote-kubeconfig.yaml get nodes` and receive successful output showing cluster nodes without TLS errors

### Implementation for User Story 1

- [X] T010 [US1] Create kubeconfig generation script in `deployment/scripts/tailscale/generate-kubeconfig.sh` - extract client certificates from cluster, write kubeconfig with Tailscale HTTPS endpoint (`https://kind-operator.tail286401.ts.net:443`), include usage instructions
- [X] T011 [US1] Make kubeconfig script executable: `chmod +x deployment/scripts/tailscale/generate-kubeconfig.sh`
- [X] T012 [US1] Document Tailscale HTTPS prerequisites in `docs/tailscale-cluster-access.md` - verify MagicDNS enabled, verify HTTPS certificates enabled in Tailscale admin console, note initial connection delay (30-60 seconds)
- [X] T013 [US1] Document kubeconfig setup procedure in `docs/tailscale-cluster-access.md` - run generate-kubeconfig.sh, copy to Mac, configure kubectl context, include troubleshooting for certificate provisioning timeout
- [X] T014 [US1] Add certificate architecture diagram to `docs/tailscale-cluster-access.md` - show kubectl → Tailscale proxy TLS (Let's Encrypt) → API server TLS (cluster CA) flow
- [X] T015 [US1] Document `--insecure-skip-tls-verify` as temporary troubleshooting workaround in `docs/tailscale-cluster-access.md` - include security warnings, time limits (10 minutes max), proper solutions (Tailscale HTTPS or cluster CA distribution)
- [ ] T016 [US1] Synthesize Tailscale operator package: `cd cdk8s && npx ts-node main-v2.ts` (generates `dist/tailscale/manifests/`)
- [ ] T017 [US1] Deploy Tailscale operator via cluster-menu.sh: `source deployment/scripts/cluster-menu.sh && cluster-update` (deploys all packages including tailscale)
- [ ] T018 [US1] Verify operator pod running: `kubectl get pods -n tailscale -l app=tailscale-operator` (should show Running status)
- [ ] T019 [US1] Check operator logs for API proxy startup: `kubectl logs -n tailscale deployment/tailscale-operator --tail=50` (should show "API server proxy listening on :443")
- [ ] T020 [US1] Generate kubeconfig on Mac: run `./deployment/scripts/tailscale/generate-kubeconfig.sh` on cluster host, copy output to `~/remote-kubeconfig.yaml` on Mac
- [ ] T021 [US1] Test kubectl connectivity from Mac (tmux pane %31): `kubectl --kubeconfig=~/remote-kubeconfig.yaml get nodes --request-timeout=60s` (first connection may take 30 seconds for certificate provisioning)
- [ ] T022 [US1] Verify subsequent kubectl commands respond quickly: `kubectl --kubeconfig=~/remote-kubeconfig.yaml get pods -A` (should complete in <2 seconds)
- [ ] T023 [US1] Test authentication and RBAC: `kubectl --kubeconfig=~/remote-kubeconfig.yaml auth whoami` (should show Tailscale identity and cluster-admin privileges)
- [ ] T024 [US1] Document acceptance criteria validation in `specs/005-remote-kubernetes-cluster/quickstart.md` - record response times, TLS validation status, multi-device testing results

**Checkpoint**: At this point, User Story 1 should be fully functional - kubectl access works from Mac with valid certificates

---

## Phase 4: User Story 2 - Direct Pod Access via Port Forwarding (Priority: P2)

**Goal**: Enable developers to access individual pod services from local machine via kubectl port-forward with <500ms added latency

**Independent Test**: From Mac, run `kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n argocd svc/argocd-server 8080:443`, then access `http://localhost:8080` in browser and see ArgoCD login page

### Implementation for User Story 2

- [ ] T025 [US2] Document port-forward usage patterns in `docs/tailscale-cluster-access.md` - basic syntax (`kubectl port-forward pod/name local:remote`), service forwarding, multiple simultaneous forwards, background processes
- [ ] T026 [US2] Create port-forward testing script in `deployment/scripts/tailscale/test-port-forward.sh` - test ArgoCD (8080:443), Gitea (8081:3000), MinIO (8082:9000), include curl validation commands
- [ ] T027 [US2] Make port-forward test script executable: `chmod +x deployment/scripts/tailscale/test-port-forward.sh`
- [ ] T028 [US2] Test port-forward to ArgoCD from Mac: `kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n argocd svc/argocd-server 8080:443` (run in background)
- [ ] T029 [US2] Verify ArgoCD accessible at localhost: Open `http://localhost:8080` in browser on Mac (should load ArgoCD login page within 5 seconds)
- [ ] T030 [US2] Test port-forward to Gitea from Mac: `kubectl --kubeconfig=~/remote-kubeconfig.yaml port-forward -n gitea svc/gitea-http 8081:3000`
- [ ] T031 [US2] Verify Gitea accessible at localhost: Open `http://localhost:8081` in browser on Mac
- [ ] T032 [US2] Test multiple simultaneous port-forwards: Run ArgoCD and Gitea forwards in parallel, verify both remain stable for 10 minutes
- [ ] T033 [US2] Measure port-forward latency: Use curl with timing (`time curl http://localhost:8080`) and compare to direct cluster access latency (should add <500ms)
- [ ] T034 [US2] Test long-running port-forward session: Keep ArgoCD forward active for 1+ hour, verify no disconnections or reconnection requirements
- [ ] T035 [US2] Document port-forward troubleshooting in `docs/tailscale-cluster-access.md` - connection resets, firewall issues, port conflicts, Tailscale connectivity drops
- [ ] T036 [US2] Add port-forward examples to `specs/005-remote-kubernetes-cluster/quickstart.md` - common services (ArgoCD, Gitea, Postgres, Redis), debugging workflows

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - kubectl access and port-forwarding are fully functional

---

## Phase 5: User Story 3 - Web UI Access to Cluster Services (Priority: P3)

**Goal**: Enable team members to access cluster dashboards and UIs from any browser on Tailscale network with <3 second load times

**Independent Test**: From Mac browser, navigate to `https://argocd.cnoe.localtest.me:8443` and see ArgoCD login page load successfully with valid TLS certificate

### Implementation for User Story 3

- [ ] T037 [US3] Document DNS resolution requirements in `docs/tailscale-cluster-access.md` - explain that `*.cnoe.localtest.me` resolves to 127.0.0.1 externally but requires ingress-nginx access from Tailscale network
- [ ] T038 [US3] Document ingress access pattern in `docs/tailscale-cluster-access.md` - services must have ingress rules, ingress-nginx must be accessible via Tailscale (already exposed via kind host network), browsers access via domain-based routing (https://service.cnoe.localtest.me:8443)
- [ ] T039 [US3] Verify ingress-nginx accessibility from Mac: `curl -k https://argocd.cnoe.localtest.me:8443` from Mac terminal (should receive 200 OK or redirect)
- [ ] T040 [US3] Test ArgoCD web UI access from Mac browser: Navigate to `https://argocd.cnoe.localtest.me:8443` (should load login page within 3 seconds)
- [ ] T041 [US3] Test Gitea web UI access from Mac browser: Navigate to `https://gitea.cnoe.localtest.me:8443`
- [ ] T042 [US3] Test Backstage web UI access from Mac browser: Navigate to `https://cnoe.localtest.me:8443` (if Backstage deployed)
- [ ] T043 [US3] Verify TLS certificate handling: Check browser certificate warnings for `*.cnoe.localtest.me` (expected: self-signed cluster CA warnings, document trust store addition if needed)
- [ ] T044 [US3] Test multi-service access: Open ArgoCD, Gitea, and Backstage in separate tabs, verify all load within 3 seconds and remain responsive
- [ ] T045 [US3] Test authentication persistence: Log into ArgoCD, refresh page, navigate between pages, verify session remains active
- [ ] T046 [US3] Document web UI access procedure in `docs/tailscale-cluster-access.md` - list all available services with URLs, note certificate warnings, include login credentials retrieval (`idpbuilder get secrets`)
- [ ] T047 [US3] Create DNS verification script in `deployment/scripts/tailscale/verify-dns-resolution.sh` - test external resolution (from Mac: `dig argocd.cnoe.localtest.me`), test internal resolution (from pod: `nslookup kubernetes.default.svc`), include troubleshooting steps
- [ ] T048 [US3] Make DNS verification script executable: `chmod +x deployment/scripts/tailscale/verify-dns-resolution.sh`
- [ ] T049 [US3] Add web UI troubleshooting section to `docs/tailscale-cluster-access.md` - DNS resolution failures, certificate errors, 502 Bad Gateway (service not running), Tailscale connectivity issues

**Checkpoint**: All user stories should now be independently functional - kubectl, port-forward, and web UI access all work from Mac

---

## Phase 6: Cluster CA Distribution Fallback (Optional Enhancement)

**Purpose**: Document alternative certificate strategy for environments without Tailscale HTTPS

- [ ] T050 [P] Create cluster CA export script in `deployment/scripts/tailscale/export-cluster-ca.sh` - extract CA from kind cluster (`docker exec localdev-control-plane cat /etc/kubernetes/pki/ca.crt`), include OS-specific trust store installation instructions (macOS, Linux, kubectl-only)
- [ ] T051 [P] Make CA export script executable: `chmod +x deployment/scripts/tailscale/export-cluster-ca.sh`
- [ ] T052 [P] Document cluster CA distribution workflow in `docs/tailscale-cluster-access.md` - when to use (no Tailscale HTTPS, CI/CD pipelines, air-gapped), export procedure, trust store installation (macOS: `security add-trusted-cert`, Linux: `update-ca-certificates`, kubectl: `--certificate-authority` flag)
- [ ] T053 [P] Add kubeconfig example with cluster CA in `docs/tailscale-cluster-access.md` - show `certificate-authority` field pointing to exported CA file, note file path management requirements
- [ ] T054 [P] Document CI/CD integration pattern in `docs/tailscale-cluster-access.md` - GitHub Actions example mounting CA from secret, GitLab CI example, note air-gap compatibility

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T055 [P] Create comprehensive quickstart guide in `specs/005-remote-kubernetes-cluster/quickstart.md` - prerequisites (Tailscale account, kubectl installed), configuration steps, validation procedures, all three user story test scenarios
- [ ] T056 [P] Add troubleshooting matrix to `docs/tailscale-cluster-access.md` - common error messages (x509 certificate validation, TLS handshake timeout, EOF, unauthorized, ProxyGroup conflicts), causes, resolutions
- [ ] T057 [P] Document certificate lifecycle in `docs/tailscale-cluster-access.md` - Let's Encrypt 90-day validity, automatic renewal, monitoring for renewal failures, certificate expiration warnings
- [ ] T058 [P] Add performance benchmarking section to `specs/005-remote-kubernetes-cluster/quickstart.md` - kubectl response times (<2s), port-forward latency (<500ms), web UI load times (<3s), record actual measurements
- [ ] T059 [P] Document multi-cluster patterns in `docs/tailscale-cluster-access.md` - unique operator hostnames per cluster (cluster1-operator, cluster2-operator), kubectl context switching, avoiding DNS conflicts
- [ ] T060 [P] Add security best practices to `docs/tailscale-cluster-access.md` - least-privilege RBAC (avoid system:masters for all users), Tailscale ACL policies, audit logging recommendations, network policies for operator pod
- [ ] T061 [P] Create RBAC impersonation examples in `docs/tailscale-cluster-access.md` - mapping Tailscale groups to Kubernetes groups (`group:admins` → `system:masters`), least-privilege mappings (`group:developers` → custom ClusterRole), impersonationGrants configuration in TailscaleOperatorChart
- [ ] T062 [P] Document production readiness considerations in `docs/tailscale-cluster-access.md` - HA operator deployment (multi-replica), monitoring (operator pod health, certificate expiration), backup access methods (SSH port forwarding), disaster recovery (certificate regeneration)
- [ ] T063 Update CLAUDE.md with Tailscale operator patterns in `CLAUDE.md` - add kubectl access via Tailscale section under Common Commands, document generate-kubeconfig.sh usage, add troubleshooting tips
- [ ] T064 Validate all three user stories end-to-end from Mac (tmux pane %31): kubectl access (US1), port-forward (US2), web UI access (US3) - ensure all acceptance criteria met
- [ ] T065 Run quickstart.md validation from clean Mac environment (no prior kubeconfig) to verify documentation completeness

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phases 3-5)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if multiple team members)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Cluster CA Distribution (Phase 6)**: Optional - can proceed in parallel with user stories or after completion
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories - establishes kubectl access foundation
- **User Story 2 (P2)**: Depends on User Story 1 completion (requires working kubectl access) - port-forward builds on kubectl connectivity
- **User Story 3 (P3)**: Independent of User Story 2, only depends on User Story 1 (requires Tailscale network access) - can start in parallel with US2 after US1 complete

### Within Each User Story

- **User Story 1**: Script creation → documentation → synthesis → deployment → operator verification → kubeconfig generation → testing
- **User Story 2**: Documentation → script creation → testing (depends on US1 kubectl access)
- **User Story 3**: Documentation → testing (depends on US1 Tailscale connectivity, ingress-nginx already deployed)

### Parallel Opportunities

- **Setup (Phase 1)**: All tasks marked [P] can run in parallel (T002, T003)
- **Foundational (Phase 2)**: T004-T006 modify same file (sequential), T007-T009 are validation tasks (can run after T004-T006)
- **User Story 1**: T010-T011 (scripts), T012-T015 (documentation) can run in parallel, then T016-T024 (deployment/testing) must be sequential
- **User Story 2**: T025-T027 can run in parallel, T028-T036 must be sequential (testing depends on previous tests)
- **User Story 3**: T037-T038 (documentation), T047-T048 (scripts) can run in parallel, T039-T046 (testing) must be sequential
- **Cluster CA Distribution (Phase 6)**: All tasks marked [P] can run in parallel with user stories
- **Polish (Phase 7)**: All tasks marked [P] can run in parallel

---

## Parallel Example: User Story 1 Documentation & Scripts

```bash
# Launch all independent tasks for User Story 1 together:
Task: "Create kubeconfig generation script in deployment/scripts/tailscale/generate-kubeconfig.sh"
Task: "Make kubeconfig script executable"
Task: "Document Tailscale HTTPS prerequisites in docs/tailscale-cluster-access.md"
Task: "Document kubeconfig setup procedure in docs/tailscale-cluster-access.md"
Task: "Add certificate architecture diagram to docs/tailscale-cluster-access.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003) - ~5 minutes
2. Complete Phase 2: Foundational (T004-T009) - ~20 minutes
3. Complete Phase 3: User Story 1 (T010-T024) - ~30 minutes
4. **STOP and VALIDATE**: Test kubectl access from Mac (tmux pane %31)
5. Deploy/demo if ready - basic remote cluster access working

**Total MVP Time**: ~1 hour
**Value Delivered**: Platform engineers can manage cluster from any location

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (~25 minutes)
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!) (~30 minutes)
3. Add User Story 2 → Test independently → Deploy/Demo (~20 minutes)
4. Add User Story 3 → Test independently → Deploy/Demo (~15 minutes)
5. Each story adds value without breaking previous stories

**Total Feature Time**: ~1.5 hours for all three user stories
**Additional Time for Polish**: ~30 minutes for documentation and hardening

### Parallel Team Strategy

Not applicable - this is an infrastructure feature with sequential dependencies. Single implementer recommended due to:
- TailscaleOperatorChart modifications affect same file
- Testing requires access to specific Mac machine (tmux pane %31)
- Deployment steps must be executed sequentially

---

## Notes

- **[P] tasks** = different files, no dependencies (can parallelize)
- **[Story] label** maps task to specific user story for traceability (US1, US2, US3)
- Each user story should be independently completable and testable
- Testing performed interactively from Mac via tmux pane %31 (no automated tests)
- Stop at any checkpoint to validate story independently
- User Story 2 depends on User Story 1 completion (port-forward requires working kubectl)
- User Story 3 can start in parallel with User Story 2 after User Story 1 complete
- Certificate provisioning delay (30-60 seconds) on first connection is expected behavior
- `--insecure-skip-tls-verify` is temporary troubleshooting tool only (not for production use)
- All kubectl commands use `--kubeconfig=~/remote-kubeconfig.yaml` to avoid modifying default kubeconfig
- Phase 6 (Cluster CA Distribution) is optional fallback for environments without Tailscale HTTPS
