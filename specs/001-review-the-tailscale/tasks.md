# Tasks: Tailscale Remote Kubernetes Cluster Access

## ⚠️ IMPLEMENTATION STATUS UPDATE (2025-10-08)

**Current Status:** Operator infrastructure deployed successfully, but API proxy feature **not available** in current operator releases.

**Completed:**
- ✅ T001-T026: Operator deployed and running (v1.88.3)
- ✅ OAuth authentication configured
- ✅ External Secrets integration working
- ✅ ArgoCD synced and healthy
- ✅ Tailscale ACL policy updated

**Blocked:**
- ❌ T027-T064: API server proxy functionality not working
- **Root Cause:** Operators authenticate to Tailscale but don't expose functional network peers
- **Evidence:** Devices visible in admin console but unreachable via network (`tailscale ping` fails)
- **Versions Tested:** Both `:unstable` (v1.89.218) and `v1.88.3` show identical limitation

**Recommended Next Steps:**
1. **Sidecar Proxy Approach (RECOMMENDED):** Deploy dedicated Tailscale + kubectl proxy pod - see `FINAL_SUMMARY.md` and `IMPLEMENTATION_NOTES.md`
2. **Wait for Operator Maturity:** Monitor Tailscale releases for API proxy fixes
3. **Enable Tailscale Services:** Check if account supports beta "Services" feature

**Documentation:**
- Comprehensive analysis: `specs/001-review-the-tailscale/IMPLEMENTATION_NOTES.md`
- Executive summary: `specs/001-review-the-tailscale/FINAL_SUMMARY.md`
- Quick reference: `specs/001-review-the-tailscale/README.md`

---

**Input**: Design documents from `/home/vpittamp/stacks/specs/001-review-the-tailscale/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/tailscale-cli.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Testing Criteria**: Each user story includes validation checkpoints using ArgoCD CLI, Kubernetes resource health checks, and functional connectivity tests to ensure deployment success.

## Testing Strategy

Each user story has a **Validation Checkpoint** with progressive testing criteria:

### Minimal Testing (MVP - User Story 1)
1. ✅ **ArgoCD Health**: `argocd app get argocd/tailscale-operator --insecure` shows Healthy + Synced
2. ✅ **Operator Running**: `kubectl get pods -n tailscale` shows Running pods
3. ✅ **Remote Connectivity**: `kubectl --context=tailscale-${CLUSTER_NAME} get nodes` succeeds

### Progressive Validation (User Stories 2-3)
- **US2**: Add identity verification (`kubectl auth whoami`)
- **US3**: Add ProxyGroup health check and failover test

### Production Readiness (Final Checkpoint)
- **Clean Slate**: Full `cluster-recreate` + redeploy test
- **Security**: OAuth secrets from Key Vault, no secrets in git
- **Documentation**: Quickstart validation + troubleshooting complete

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
- **CDK8s Charts**: `cdk8s/charts/infra/`
- **CDK8s Config**: `cdk8s/config/`
- **CDK8s Libraries**: `cdk8s/lib/`
- **CDK8s Imports**: `cdk8s/imports/`
- **Environment Config**: `.env-files/`
- **Documentation**: `specs/001-review-the-tailscale/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize Tailscale operator chart structure and import CRDs

- [X] T001 Import Tailscale CRDs using `cdk8s import` to generate TypeScript interfaces in `cdk8s/imports/tailscale.com.ts`
- [X] T002 [P] Create base chart class `TailscaleOperatorChart` in `cdk8s/charts/infra/tailscale-operator-chart.ts` with constructor and ChartProps interface
- [X] T003 [P] Define `TailscaleOperatorChartProps` TypeScript interface in `cdk8s/charts/infra/tailscale-operator-chart.ts` extending ChartProps with properties from data-model.md (environmentName, clusterName, oauthSecretName, namespace, enableHA, proxyReplicas, operatorImage, impersonationGrants)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Tailscale configuration and credentials that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create Tailscale OAuth client using CLI command `tailscale oauth create --name "k8s-operator-${CLUSTER_NAME}" --device-write --auth-keys` and capture client ID and secret
- [X] T005 Store OAuth client ID in `.env-files/wi.env` as `TAILSCALE_OAUTH_CLIENT_ID` environment variable
- [ ] T006 Store OAuth client secret in Azure Key Vault `keyvault-thcmfmoo5oeow` with key name `TAILSCALE-OAUTH-CLIENT-SECRET` using `az keyvault secret set` (MANUAL: use Azure Portal)
- [X] T007 Create tailnet policy JSON file defining tagOwners (`tag:k8s-operator`, `tag:k8s`) and grants mapping Tailscale groups to Kubernetes groups per contracts/tailscale-cli.md
- [ ] T008 Apply tailnet policy using `tailscale acl set policy.json` to configure impersonation grants for group:admins and group:developers (MANUAL: use https://login.tailscale.com/admin/acls)
- [X] T009 Verify HTTPS enabled for tailnet using `tailscale status --json | jq -r '.MagicDNSSuffix'`

**Checkpoint**: Tailscale credentials and policy configured - operator deployment can now begin

---

## Phase 3: User Story 1 - Remote Cluster Access via Tailscale (Priority: P1) 🎯 MVP

**Goal**: Enable secure remote access to Kubernetes cluster API server from any location via Tailscale network

**Independent Test**: Connect to cluster via `kubectl` from remote machine on Tailscale network, run `kubectl get nodes` and verify successful response

### Implementation for User Story 1

- [X] T010 [P] [US1] Create Kubernetes Namespace resource for `tailscale` namespace in `TailscaleOperatorChart` using `KubeNamespace` from imports/k8s.ts with sync-wave `-100`
- [X] T011 [P] [US1] Create ServiceAccount `operator` in tailscale namespace in `TailscaleOperatorChart` using `KubeServiceAccount` from imports/k8s.ts with sync-wave `-90`
- [X] T012 [P] [US1] Create ExternalSecret resource in `TailscaleOperatorChart` using `createEnvExternalSecret` helper from lib/eso-helpers.ts to sync OAuth credentials from Azure Key Vault (TAILSCALE_OAUTH_CLIENT_ID, TAILSCALE_OAUTH_CLIENT_SECRET) to Secret `tailscale-oauth` with sync-wave `-80`
- [X] T013 [US1] Create ClusterRole `operator` in `TailscaleOperatorChart` using `KubeClusterRole` from imports/k8s.ts with permissions for managing ProxyGroups, Connectors, DNSConfigs, Secrets, and Services with sync-wave `-90`
- [X] T014 [US1] Create ClusterRoleBinding `operator` in `TailscaleOperatorChart` using `KubeClusterRoleBinding` from imports/k8s.ts binding ServiceAccount to ClusterRole with sync-wave `-90`
- [X] T015 [US1] Implement Deployment resource for Tailscale operator in `TailscaleOperatorChart` using `KubeDeployment` from imports/k8s.ts with container image from props.operatorImage (default: tailscale/operator:latest), environment variables referencing `tailscale-oauth` Secret, and sync-wave `-90`
- [X] T016 [US1] Add Deployment container environment variable `TS_KUBE_SECRET` referencing ExternalSecret `tailscale-oauth` for OAuth client credentials
- [X] T017 [US1] Add Deployment container environment variable `TS_AUTH_ONCE` set to `true` to enable one-time authentication mode
- [X] T018 [US1] Register `TailscaleOperatorChart` in `cdk8s/lib/idpbuilder-chart-factory.ts` using `IdpBuilderChartFactory.register()` method
- [X] T019 [US1] Add application configuration entry to `cdk8s/config/applications.ts` with name `tailscale-operator`, namespace `tailscale`, chart type `TailscaleOperatorChart`, and ArgoCD configuration (syncWave: `-90`, labels, automated syncPolicy)
- [X] T020 [US1] Set chart props in application configuration using values from wi.env: environmentName `dev`, clusterName from `CLUSTER_NAME` env var (kind), oauthSecretName `tailscale-oauth`, enableHA `false`, impersonationGrants array with basic admin grant
- [X] T021 [US1] Run `cluster-synth` from repository root to synthesize CDK8s manifests to `cdk8s/dist/tailscale-operator/manifests/` and verify output includes Namespace, ExternalSecret, Deployment, ServiceAccount, ClusterRole, ClusterRoleBinding, kustomization.yaml
- [X] T022 [US1] Run `cluster-update` from repository root to push synthesized manifests to Gitea and trigger ArgoCD sync for tailscale-operator application
- [X] T023 [US1] Verify ArgoCD application status using `argocd app get argocd/tailscale-operator --insecure` and confirm Synced and Healthy status
- [X] T024 [US1] Verify operator pod running using `kubectl get pods -n tailscale` and check for Running status
- [X] T025 [US1] Verify ExternalSecret sync using `kubectl get externalsecret -n tailscale` and `kubectl get secret tailscale-oauth -n tailscale` to confirm credentials synced
- [X] T026 [US1] Check operator logs using `kubectl logs -n tailscale deployment/tailscale-operator` and verify successful OAuth authentication and "Operator ready" message
- [ ] T027 [US1] From remote machine connected to Tailscale, run `tailscale configure kubeconfig ${CLUSTER_NAME}` to generate kubeconfig entry pointing to Tailscale proxy endpoint ⚠️ **BLOCKED**: API proxy not active - see `IMPLEMENTATION_NOTES.md`
- [ ] T028 [US1] From remote machine, test connectivity using `kubectl --context=tailscale-${CLUSTER_NAME} get nodes` and verify cluster responds with node list ⚠️ **BLOCKED**: API proxy not active - see `IMPLEMENTATION_NOTES.md`

**⚠️ IMPLEMENTATION STATUS**: T001-T026 complete (operator running), T027-T028 blocked pending API proxy feature investigation. See `specs/001-review-the-tailscale/IMPLEMENTATION_NOTES.md` for details.

### Validation Checkpoint: User Story 1

**Success Criteria** - All checks must pass:

1. **Synthesis Check**: `cluster-synth` completes without TypeScript errors
2. **Deployment Check**: `cluster-update` succeeds, ArgoCD sync completes
3. **ArgoCD Health**:
   ```bash
   argocd app get argocd/tailscale-operator --insecure
   # Expected: Health Status = Healthy, Sync Status = Synced
   ```
4. **Resource Health**:
   ```bash
   kubectl get pods -n tailscale
   # Expected: All pods STATUS = Running, READY = 1/1

   kubectl get externalsecret -n tailscale
   # Expected: STATUS = SecretSynced
   ```
5. **Operator Logs**:
   ```bash
   kubectl logs -n tailscale deployment/tailscale-operator --tail=50
   # Expected: Contains "Operator ready", no authentication errors
   ```
6. **Functional Test**:
   ```bash
   # From remote Tailscale-connected machine
   kubectl --context=tailscale-${CLUSTER_NAME} get nodes
   # Expected: Returns cluster node list without errors
   ```

**Checkpoint**: User Story 1 is fully functional - remote kubectl access via Tailscale is working

---

## Phase 4: User Story 2 - Identity-Based Access Control (Priority: P2)

**Goal**: Map cluster access permissions to Tailscale user groups, enabling automatic Kubernetes RBAC based on organizational roles

**Independent Test**: Assign different Tailscale users to specific groups (group:admins, group:developers), configure Kubernetes role mappings, verify each user receives only designated permissions when connecting via Tailscale

### Implementation for User Story 2

- [ ] T029 [US2] Add `ImpersonationGrant` TypeScript interface to `cdk8s/charts/infra/tailscale-operator-chart.ts` with fields: tailscaleGroup (string), kubernetesGroups (string[]), description (optional string)
- [ ] T030 [US2] Update tailnet policy JSON file to include multiple grants: one for group:admins → system:masters, one for group:developers → developers group
- [ ] T031 [US2] Apply updated tailnet policy using `tailscale acl set policy.json` to configure multiple impersonation grants
- [ ] T032 [US2] Update application configuration in `cdk8s/config/applications.ts` to include impersonationGrants array with entries for both admins and developers groups
- [ ] T033 [US2] Create Kubernetes ClusterRoleBinding in separate helper method in `TailscaleOperatorChart` to grant `view` ClusterRole to `developers` group for developer namespace access
- [ ] T034 [US2] Re-synthesize manifests using `cluster-synth` to pick up updated impersonation grant configuration
- [ ] T035 [US2] Deploy updated configuration using `cluster-update` and verify ArgoCD sync
- [ ] T036 [US2] From remote machine as user in group:admins, run `kubectl auth whoami --context=tailscale-${CLUSTER_NAME}` and verify impersonation shows system:masters group membership
- [ ] T037 [US2] From remote machine as user in group:developers, run `kubectl get pods -A --context=tailscale-${CLUSTER_NAME}` and verify request is forbidden (developers should not have cluster-wide access)
- [ ] T038 [US2] From remote machine as user in group:developers, run `kubectl get pods -n <dev-namespace> --context=tailscale-${CLUSTER_NAME}` and verify request succeeds with developer permissions
- [ ] T039 [US2] Add validation in quickstart.md for verifying group-based permissions using `kubectl auth can-i --list --context=tailscale-${CLUSTER_NAME}`

### Validation Checkpoint: User Story 2

**Success Criteria** - All checks must pass:

1. **ArgoCD Health** (from US1 still passing):
   ```bash
   argocd app get argocd/tailscale-operator --insecure
   # Expected: Health Status = Healthy, Sync Status = Synced
   ```

2. **Resource Health** (from US1 still passing):
   ```bash
   kubectl get pods -n tailscale
   # Expected: All pods STATUS = Running, READY = 1/1
   ```

3. **Identity Verification - Admin User**:
   ```bash
   # From remote machine as user in group:admins
   kubectl auth whoami --context=tailscale-${CLUSTER_NAME}
   # Expected: Shows impersonation with system:masters group
   ```

4. **Identity Verification - Developer User**:
   ```bash
   # From remote machine as user in group:developers
   kubectl get pods -A --context=tailscale-${CLUSTER_NAME}
   # Expected: Forbidden error (developers lack cluster-wide access)

   kubectl get pods -n <dev-namespace> --context=tailscale-${CLUSTER_NAME}
   # Expected: Success (developers have namespace access)
   ```

5. **Permission Audit**:
   ```bash
   kubectl auth can-i --list --context=tailscale-${CLUSTER_NAME}
   # Expected: Permissions match Tailscale group membership
   ```

**Checkpoint**: User Stories 1 AND 2 both work independently - identity-based access control is functional

---

## Phase 5: User Story 3 - High Availability API Proxy (Priority: P3)

**Goal**: Deploy multiple Tailscale API proxy replicas for resilient cluster access during proxy instance failures

**Independent Test**: Deploy multiple proxy replicas, connect to cluster, terminate one proxy instance, verify kubectl commands continue to succeed through remaining replicas

### Implementation for User Story 3

- [ ] T040 [US3] Add conditional ProxyGroup resource creation in `TailscaleOperatorChart` that only creates ProxyGroup when props.enableHA is true or environmentName is 'staging' or 'production'
- [ ] T041 [US3] Implement ProxyGroup resource using `ProxyGroup` from imports/tailscale.com.ts with spec: type `kube-apiserver`, replicas from props.proxyReplicas (default 2), tags `['tag:k8s']`, kubeApiServer.mode `auth`, sync-wave `0`
- [ ] T042 [US3] Set ProxyGroup metadata name to `${props.clusterName}-api-server` and namespace to props.namespace
- [ ] T043 [US3] Add ArgoCD sync-wave annotation `argocd.argoproj.io/sync-wave: "0"` to ProxyGroup metadata to ensure it deploys after operator is ready
- [ ] T044 [US3] Update application configuration in `cdk8s/config/applications.ts` to set enableHA to true and proxyReplicas to 3 for testing HA configuration
- [ ] T045 [US3] Re-synthesize manifests using `cluster-synth` and verify ProxyGroup.api-server.k8s.yaml is generated in dist/tailscale-operator/manifests/
- [ ] T046 [US3] Deploy HA configuration using `cluster-update` and verify ArgoCD sync includes ProxyGroup resource
- [ ] T047 [US3] Verify ProxyGroup created using `kubectl get proxygroup -n tailscale` and confirm resource exists with correct replica count
- [ ] T048 [US3] Verify multiple proxy pods running using `kubectl get pods -n tailscale -l app=api-server-proxy` and confirm 3 replicas in Running status
- [ ] T049 [US3] From remote machine, establish kubectl connection using `kubectl --context=tailscale-${CLUSTER_NAME} get nodes` to confirm load-balanced access
- [ ] T050 [US3] Simulate proxy failure using `kubectl delete pod <proxy-pod-name> -n tailscale` to terminate one proxy instance
- [ ] T051 [US3] Immediately run `kubectl --context=tailscale-${CLUSTER_NAME} get pods -A` and verify commands still succeed through remaining proxy replicas
- [ ] T052 [US3] Verify operator recreates terminated proxy pod using `kubectl get pods -n tailscale -l app=api-server-proxy -w` and confirm pod count returns to 3
- [ ] T053 [US3] Add ProxyGroup verification steps to quickstart.md including commands to check replica status and test failover

### Validation Checkpoint: User Story 3

**Success Criteria** - All checks must pass:

1. **ArgoCD Health** (from US1/US2 still passing):
   ```bash
   argocd app get argocd/tailscale-operator --insecure
   # Expected: Health Status = Healthy, Sync Status = Synced
   ```

2. **Resource Health - ProxyGroup**:
   ```bash
   kubectl get proxygroup -n tailscale
   # Expected: Resource exists with correct replica count

   kubectl get pods -n tailscale -l app=api-server-proxy
   # Expected: 3 pods, all STATUS = Running, READY = 1/1
   ```

3. **Load Balanced Access**:
   ```bash
   # From remote machine
   kubectl --context=tailscale-${CLUSTER_NAME} get nodes
   # Expected: Returns cluster node list (traffic distributed across replicas)
   ```

4. **Failover Test**:
   ```bash
   # Delete one proxy pod
   kubectl delete pod <proxy-pod-name> -n tailscale

   # Immediately test connectivity (while pod is down)
   kubectl --context=tailscale-${CLUSTER_NAME} get pods -A
   # Expected: Success - traffic routed to healthy replicas

   # Wait for pod recreation
   kubectl get pods -n tailscale -l app=api-server-proxy
   # Expected: 3 pods again, all Running
   ```

5. **Operator Health** (from US1 still passing):
   ```bash
   kubectl logs -n tailscale deployment/tailscale-operator --tail=50
   # Expected: No errors, shows ProxyGroup management logs
   ```

**Checkpoint**: All user stories independently functional - HA proxy provides resilient remote access

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and finalize implementation

- [ ] T054 [P] Update quickstart.md with complete deployment validation steps including ArgoCD status checks, pod health verification, and remote connectivity tests
- [ ] T055 [P] Add troubleshooting section to quickstart.md covering common errors: OAuth credentials not syncing, operator pod crash looping, remote kubectl connection failures, permission denied errors
- [ ] T056 [P] Document clean slate validation procedure in quickstart.md using `cluster-recreate` and re-running setup steps from scratch
- [ ] T057 [P] Add resource limit specifications to Deployment in `TailscaleOperatorChart` (100m CPU, 128Mi memory for operator)
- [ ] T058 [P] Add liveness and readiness probes to operator Deployment container for health monitoring
- [ ] T059 [P] Create helper function in `cdk8s/lib/` for reusable Tailscale impersonation grant generation
- [ ] T060 [P] Add code comments to `TailscaleOperatorChart` explaining sync-wave ordering rationale and resource dependencies
- [ ] T061 Verify TypeScript compilation using `cd cdk8s && npm run compile` and fix any type errors
- [ ] T062 Run full quickstart.md validation from "Clean Slate Validation" section on recreated cluster
- [ ] T063 Verify all ArgoCD sync waves execute in correct order using `argocd app get argocd/tailscale-operator --insecure` and check resource sync sequence
- [ ] T064 Update CLAUDE.md agent context with Tailscale operator implementation details and common troubleshooting patterns

### Final Validation Checkpoint: Complete Implementation

**Success Criteria** - Comprehensive validation across all user stories:

1. **Clean Slate Test**:
   ```bash
   # Recreate cluster from scratch (~5 minutes)
   cluster-recreate

   # Re-run all setup and deployment
   cluster-synth && cluster-update
   ```

2. **ArgoCD Health** (comprehensive):
   ```bash
   argocd app get argocd/tailscale-operator --insecure
   # Expected: Health Status = Healthy, Sync Status = Synced
   # Expected: All resources synced in correct sync-wave order
   ```

3. **Security Validation**:
   ```bash
   # Verify OAuth secret from Key Vault (not hardcoded)
   kubectl get secret tailscale-oauth -n tailscale -o jsonpath='{.metadata.annotations}'
   # Expected: Contains external-secrets.io annotations

   # Verify no secrets in git history
   git log --all -- '*.yaml' | grep -i 'client.*secret'
   # Expected: No secret values found
   ```

4. **All User Stories Working**:
   ```bash
   # US1: Remote access
   kubectl --context=tailscale-${CLUSTER_NAME} get nodes

   # US2: Identity verification
   kubectl auth whoami --context=tailscale-${CLUSTER_NAME}

   # US3: HA failover (if enabled)
   kubectl get proxygroup -n tailscale
   kubectl get pods -n tailscale -l app=api-server-proxy
   ```

5. **Documentation Complete**:
   - quickstart.md includes all validation steps
   - Troubleshooting section covers common errors
   - Clean slate validation documented

**Checkpoint**: Implementation complete and production-ready for dev environment

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1 (P1) can start after Foundational
  - User Story 2 (P2) can start after Foundational (or after US1 completion for sequential approach)
  - User Story 3 (P3) can start after Foundational (or after US1/US2 completion for sequential approach)
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Depends only on Phase 2 Foundational - No dependencies on other user stories
- **User Story 2 (P2)**: Depends only on Phase 2 Foundational - Builds on US1 configuration but should be independently testable
- **User Story 3 (P3)**: Depends only on Phase 2 Foundational - Extends US1 with HA but should be independently testable

### Within Each User Story

- Setup tasks (CRD imports, chart structure) before implementation
- Kubernetes resources in sync-wave order: Namespace (-100) → RBAC (-90) → Secrets (-80) → Deployment (-90) → ProxyGroup (0)
- Synthesis before deployment
- Deployment before verification
- Local verification before remote connectivity testing

### Parallel Opportunities

- **Phase 1**: T002 (chart class) and T003 (interface definition) can run in parallel
- **Phase 2**: T005 (env file), T006 (Key Vault), T007 (policy file) can run in parallel after T004 OAuth creation
- **Phase 3 (US1)**: T010 (Namespace), T011 (ServiceAccount), T012 (ExternalSecret) can run in parallel as they create independent resources
- **User Stories**: Once Phase 2 completes, US1, US2, US3 can be worked on in parallel by different team members (if using feature branches)
- **Phase 6**: All documentation tasks (T054, T055, T056) and code quality tasks (T057, T058, T059, T060) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all Kubernetes resource creation tasks together:
Task: "Create Kubernetes Namespace resource for tailscale namespace" (T010)
Task: "Create ServiceAccount operator in tailscale namespace" (T011)
Task: "Create ExternalSecret resource to sync OAuth credentials" (T012)

# After those complete, launch RBAC tasks in parallel:
Task: "Create ClusterRole operator" (T013)
Task: "Create ClusterRoleBinding operator" (T014)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T009) - CRITICAL: Tailscale OAuth and policy
3. Complete Phase 3: User Story 1 (T010-T028)
4. **STOP and VALIDATE**: Test remote kubectl access from Tailscale-connected machine
5. Demo remote cluster management capability

This delivers **immediate value**: Secure remote cluster access without public internet exposure.

### Incremental Delivery

1. Complete Setup + Foundational → Tailscale configured, credentials ready
2. Add User Story 1 → Test remote kubectl → Deploy/Demo (MVP!)
3. Add User Story 2 → Test group-based permissions → Deploy/Demo
4. Add User Story 3 → Test HA failover → Deploy/Demo
5. Polish phase → Production-ready implementation

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (critical path)
2. Once Foundational is done:
   - Developer A: User Story 1 (remote access)
   - Developer B: User Story 2 (identity-based access)
   - Developer C: User Story 3 (HA proxy)
3. Stories complete and integrate independently
4. Final integration testing with all stories enabled

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Use `cluster-recreate` for clean slate testing (~5 minutes)
- Use ArgoCD CLI with `--insecure` flag for local dev verification
- Tailscale CLI commands require tailnet admin permissions
- OAuth credentials are sensitive - always use Azure Key Vault via External Secrets
- Sync-wave ordering is critical: -100 (Namespace/CRDs) → -90 (RBAC/Operator) → -80 (Secrets) → 0 (ProxyGroup)
