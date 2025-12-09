# Implementation Plan: Tailscale Architecture Optimization

**Branch**: `103-tailscale-services` | **Date**: 2025-12-09 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification with recommended hybrid architecture

**Note**: This plan implements the recommended hybrid architecture:
- **kubectl access**: Operator API Proxy with OAuth identity impersonation
- **Service access**: Tailscale Services with stable URLs

## Summary

Optimize Tailscale architecture by:
1. Switching kubectl access to Operator API Proxy "auth" mode for OAuth identity
2. Maintaining Tailscale Services for stable web service URLs
3. Removing redundant custom kubectl-proxy chart after validation

## Technical Context

**Language/Version**: TypeScript 5.x with CDK8s
**Primary Dependencies**: CDK8s, Helm (Tailscale Operator), External Secrets Operator
**Storage**: PersistentVolumeClaims for Tailscale state (1Gi each)
**Testing**: kubectl validation, service URL tests, ArgoCD sync verification
**Target Platform**: Kind Kubernetes cluster (Linux amd64)
**Project Type**: CDK8s GitOps Infrastructure
**Performance Goals**: <2s kubectl response, <60s service startup
**Constraints**: Let's Encrypt rate limits (5 certs/domain/7 days)
**Scale/Scope**: Single developer cluster, 7 platform services

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Requirement | Status | Implementation |
|-----------|-------------|--------|----------------|
| I. CDK8s Typed Composition | Charts use typed imports | ✅ PASS | All charts use `imports/k8s` |
| II. IdpBuilder Package Architecture | cnoe:// URLs, kustomization.yaml | ✅ PASS | All packages follow convention |
| III. Modular Chart Composition | Use helper libraries | ✅ PASS | Use `tailscale-serve-helpers.ts` |
| IV. ArgoCD Sync Wave Discipline | Explicit sync waves | ✅ PASS | -120 CRDs → -75 Operator → -70 Secrets → -60 Services |
| V. Tailscale Services Standards | svc-<name> pattern, tag:k8s-services | ✅ PASS | All services follow pattern |
| VI. External Secrets Management | Azure Key Vault via ESO | ✅ PASS | Auth keys from Key Vault |
| VII. Test-Before-Apply | Synthesis, tsc, diff | ✅ PASS | Standard workflow |
| VIII. GitOps Observability | ArgoCD UI, health checks | ✅ PASS | All apps visible in ArgoCD |
| IX. Forward-Only Development | Remove legacy patterns | ✅ PASS | Remove kubectl-proxy chart after validation |
| X. Documentation as Code | CLAUDE.md updates | ✅ PASS | Update with new access methods |

## Project Structure

### Documentation (this feature)

```
specs/103-tailscale-services/
├── spec.md              # Feature specification
├── plan.md              # This file (implementation plan)
├── research.md          # Architecture research (updated)
├── data-model.md        # Entity definitions (updated)
├── quickstart.md        # Step-by-step validation (updated)
├── checklists/          # Quality checklists
└── contracts/           # API contracts (N/A - infrastructure)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   ├── infra/
│   │   ├── tailscale-operator-chart.ts   # Update: auth mode config
│   │   ├── tailscale-crds-chart.ts       # Keep unchanged
│   │   └── tailscale-subnet-router-chart.ts  # Keep unchanged
│   ├── platform/
│   │   ├── tailscale-serve-chart.ts      # Keep: stable service URLs
│   │   └── k8s-api-tailscale-serve-chart.ts  # DELETE after validation
│   └── secrets/
│       ├── tailscale-operator-secrets-chart.ts  # Keep unchanged
│       └── tailscale-secrets-chart.ts    # Keep unchanged
├── lib/
│   └── tailscale-serve-helpers.ts        # Keep unchanged
└── config/
    └── applications.ts                    # Update: operator config, remove kubectl-proxy
```

**Structure Decision**: CDK8s GitOps infrastructure pattern. No new directories needed.

## Complexity Tracking

*No complexity violations. Hybrid architecture is the simplest solution that meets all requirements.*

## Implementation Phases

### Phase 1: Enable Operator API Proxy Auth Mode (P0)

**Objective**: Configure Tailscale Operator to expose Kubernetes API with OAuth identity impersonation.

**Changes Required**:

1. **Update `tailscale-operator-chart.ts`**:
   - Set `apiServerProxyConfig.mode` to `"auth"` (currently `"true"`)
   - Add RBAC configuration for tailnet identity impersonation

2. **Create RBAC for Tailnet Identity**:
   - ClusterRoleBinding: `vpittamp@github` → `cluster-admin`
   - This maps the Tailscale identity to Kubernetes RBAC

3. **Update Tailscale ACL** (manual):
   - Add grants for `tag:k8s-operator` to impersonate users
   - Example: `{ "src": ["tag:k8s-operator"], "dst": ["*:*"], "accept": true }`

4. **Test kubectl Access**:
   ```bash
   # On M1 Mac
   tailscale configure kubeconfig kind-operator
   kubectl get nodes
   kubectl auth whoami  # Should show vpittamp@github
   ```

**Success Criteria**: SC-001 through SC-004

### Phase 2: Clean Up Stale Devices (P1)

**Objective**: Remove offline devices blocking hostname reuse.

**Changes Required**:

1. **Manual Cleanup**:
   - Tailscale Admin Console → Machines → Delete offline devices
   - Target devices: argocd, gitea, kagent, langfuse, kargo, headlamp, keycloak (offline)

2. **Verify Cleanup**:
   ```bash
   tailscale status | grep -E "offline.*(argocd|gitea|kagent)"
   # Expected: No output
   ```

**Success Criteria**: SC-005, SC-006

### Phase 3: Migrate to True Service Names (P1)

**Objective**: Switch from suffixed names (`argocd2`) to true names (`argocd`).

**Current State**: Services use `argocd2`, `langfuse2`, etc. to bypass Let's Encrypt rate limits.

**Changes Required**:

1. **Update `applications.ts`**:
   - Change `serviceName: 'argocd2'` → `serviceName: 'argocd'`
   - Repeat for all 7 services

2. **Update ACL Auto-Approvers** (manual):
   - Replace `svc:argocd2` → `svc:argocd` in Tailscale Admin Console

3. **Update Langfuse Configuration**:
   - Change `nextAuthUrl` to match new service URL

4. **Synthesize and Deploy**:
   ```bash
   cd cdk8s && npx ts-node main-v2.ts
   cluster-update
   ```

**Success Criteria**: SC-007 through SC-010

### Phase 4: Deprecate Custom kubectl-proxy (P3)

**Objective**: Remove redundant `k8s-api-tailscale-serve-chart.ts` after Operator API Proxy is validated.

**Prerequisites**: Phase 1 complete and validated for 48+ hours

**Changes Required**:

1. **Remove from `applications.ts`**:
   - Delete `k8s-api-tailscale-serve` entry

2. **Delete Chart File**:
   ```bash
   rm cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts
   ```

3. **Clean Up Kubernetes Resources**:
   ```bash
   kubectl delete deployment k8s-api-tailscale-serve -n tailscale
   kubectl delete clusterrolebinding k8s-api-tailscale-serve
   ```

4. **Update Documentation**:
   - Remove references to custom kubectl-proxy from CLAUDE.md
   - Document Operator API Proxy usage

**Success Criteria**: SC-014

### Phase 5: Documentation Updates (P3)

**Objective**: Update CLAUDE.md with final architecture.

**Changes Required**:

1. **Update Tailscale Operator Section**:
   - Document auth mode configuration
   - Add `tailscale configure kubeconfig` instructions

2. **Update Service URLs Section**:
   - Change from `argocd2` → `argocd` (all services)
   - Add stable URL reference table

3. **Remove Legacy Documentation**:
   - Remove references to custom kubectl-proxy
   - Remove token-based access instructions

**Success Criteria**: SC-015

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Operator API Proxy doesn't work as expected | Keep custom kubectl-proxy until validation complete |
| Let's Encrypt rate limits during migration | Use persistent storage, migrate during off-hours |
| ACL misconfiguration blocks access | Test ACL changes in Admin Console before deployment |
| Identity impersonation not recognized | Verify RBAC binding syntax matches Tailscale identity format |

## Rollback Plan

If Operator API Proxy fails:
1. Re-enable custom kubectl-proxy in `applications.ts`
2. Use token-based authentication (existing pattern)
3. Document issue for future resolution

## Dependencies

### External (Manual Configuration)

1. **Tailscale Admin Console**:
   - ACL grants for API Proxy impersonation
   - Auto-approvers for services (if not already configured)

2. **Azure Key Vault**:
   - `TAILSCALE-AUTH-KEY` with `tag:k8s-services`
   - `TAILSCALE-OAUTH-CLIENT-ID` and `TAILSCALE-OAUTH-CLIENT-SECRET`

### Internal (Automated)

1. **External Secrets Operator**: Syncs secrets from Azure Key Vault
2. **ArgoCD**: Deploys synthesized packages
3. **IdpBuilder**: Manages cnoe:// URL routing

## Validation Commands

```bash
# Phase 1: kubectl OAuth access
tailscale configure kubeconfig kind-operator
kubectl --kubeconfig=~/.kube/tailscale-cluster.yaml get nodes
kubectl --kubeconfig=~/.kube/tailscale-cluster.yaml auth whoami

# Phase 2: Stale device cleanup
tailscale status | grep -c offline

# Phase 3: Service URLs
for svc in argocd langfuse gitea kagent kargo headlamp keycloak; do
  curl -sI "https://svc-${svc}.tail286401.ts.net" | head -1
done

# Phase 4: Cleanup verification
kubectl get deployment -n tailscale | grep k8s-api
# Expected: No output
```

## Timeline-Free Task Sequence

1. Configure Operator API Proxy auth mode
2. Create RBAC for tailnet identity
3. Update Tailscale ACL grants
4. Test kubectl via Operator API Proxy
5. Clean up stale Tailscale devices
6. Migrate service names from suffixed to true names
7. Validate all service URLs
8. Remove custom kubectl-proxy chart
9. Update CLAUDE.md documentation
