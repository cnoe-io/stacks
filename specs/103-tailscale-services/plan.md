# Implementation Plan: Tailscale Stale Device Cleanup and Services Migration

**Branch**: `103-tailscale-services` | **Date**: 2025-12-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/103-tailscale-services/spec.md`

## Summary

Migrate platform services (ArgoCD, Langfuse, Gitea, kagent, Kargo, Headlamp, Keycloak) from Tailscale Ingress pattern to Tailscale Services pattern for stable URLs that survive cluster recreation. This eliminates hostname suffix drift (`argocd-1`, `argocd-2`) and Let's Encrypt rate limit issues caused by new certificates being requested on each pod restart.

**Technical Approach** (Forward-Only, No Backward Compatibility per Constitution Principle IX):
1. **Phase 1 (Tailscale Admin)**: Clean up stale devices, configure ACL auto-approvers for all 7 services
2. **Phase 2 (CDK8s)**: Create unified `TailscaleServeChart` using `--service` flag pattern from `k8s-api-tailscale-serve-chart.ts`
3. **Phase 3 (Complete Replacement)**: DELETE `tailscale-ingress-chart.ts` entirely, replace all ingress entries in `applications.ts` with serve chart entries

**Files to DELETE (Legacy)**:
- `cdk8s/charts/platform/tailscale-ingress-chart.ts` - Legacy hostname-based ingress pattern
- All `tailscale-ingresses` entries in `applications.ts`

**Files to CREATE (Optimal)**:
- `cdk8s/lib/tailscale-serve-helpers.ts` - Shared helper using `--service` flag pattern
- Individual serve chart entries in `applications.ts` for each of the 7 services

## Technical Context

**Language/Version**: TypeScript (CDK8s charts)
**Primary Dependencies**: CDK8s, cdk8s-plus-32, Tailscale Operator v1.82.0+, External Secrets Operator
**Storage**: Azure Key Vault (secrets), Kubernetes ConfigMaps (configuration)
**Testing**: `npx tsc --noEmit` (type checking), `kubectl diff` (manifest validation)
**Target Platform**: Kubernetes (Kind + IdpBuilder local dev)
**Project Type**: Infrastructure-as-Code (CDK8s charts)
**Performance Goals**: Services accessible within 60s of pod startup, <3 min recovery after cluster recreation
**Constraints**: Must use existing `tailscale-serve-helpers.ts`, tag-based auth keys via ESO
**Scale/Scope**: 7 platform services (ArgoCD, Langfuse, Gitea, kagent, Kargo, Headlamp, Keycloak)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check (Phase 0)

| Principle | Requirement | Status | Notes |
|-----------|-------------|--------|-------|
| I. CDK8s Typed Composition | Charts use typed imports from `cdk8s/imports/` | ✅ PASS | Charts will use `imports/k8s.ts` for resources |
| III. Modular Chart Composition | Use helpers from `cdk8s/lib/tailscale-serve-helpers.ts` | ✅ PASS | Existing helpers will be extended |
| IV. ArgoCD Sync Wave Discipline | Explicit sync waves for deployment ordering | ✅ PASS | Sync wave -60 for serve charts (after secrets -70) |
| V. Tailscale Services Standards | `<name>-<cluster>` naming, `tag:k8s-services`, ACL auto-approvers for `svc:<name>` | ✅ PASS | Primary focus of this feature |
| VI. External Secrets Management | Auth keys from Azure Key Vault via ESO | ✅ PASS | Using existing `tailscale-secrets-chart.ts` |
| IX. Forward-Only Development | Remove legacy hostname mode, no dual support | ✅ PASS | Will remove `tailscale-ingress-chart.ts` after migration |
| X. Documentation as Code | Update CLAUDE.md with service URLs | ✅ PASS | Will update Tailscale Services section |

**Gate Status**: PASS - All constitution principles can be satisfied

### Post-Design Check (Phase 1)

| Principle | Verification | Status | Artifact |
|-----------|--------------|--------|----------|
| I. CDK8s Typed Composition | Contract interface uses cdk8s types | ✅ VERIFIED | `contracts/tailscale-serve-chart-props.ts` |
| III. Modular Chart Composition | Helper function defined, service configs centralized | ✅ VERIFIED | `contracts/tailscale-serve-chart-props.ts:PLATFORM_SERVICES` |
| IV. ArgoCD Sync Wave Discipline | Sync wave -60 documented in plan | ✅ VERIFIED | `plan.md:Technical Context` |
| V. Tailscale Services Standards | `svc:<name>` pattern, ACL rules documented | ✅ VERIFIED | `research.md:RQ-2, RQ-3` |
| VI. External Secrets Management | Using existing ESO infrastructure | ✅ VERIFIED | `research.md:RQ-4` |
| IX. Forward-Only Development | Legacy removal steps documented | ✅ VERIFIED | `quickstart.md:Phase 5` |
| X. Documentation as Code | CLAUDE.md update included in quickstart | ✅ VERIFIED | `quickstart.md:Validation Checklist` |

**Post-Design Gate Status**: PASS - All principles verified in design artifacts

## Project Structure

### Documentation (this feature)

```
specs/103-tailscale-services/
├── plan.md              # This file
├── research.md          # Phase 0: Tailscale Services research
├── data-model.md        # Phase 1: Entity definitions
├── quickstart.md        # Phase 1: Validation steps
├── contracts/           # Phase 1: Chart props interfaces
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (CDK8s Charts)

```
cdk8s/
├── charts/
│   ├── platform/
│   │   ├── k8s-api-tailscale-serve-chart.ts     # KEEP: Reference implementation
│   │   ├── tailscale-serve-chart.ts             # NEW: Generic serve chart for all services
│   │   └── tailscale-ingress-chart.ts           # DELETE: Legacy ingress (no backward compat)
│   └── secrets/
│       └── tailscale-secrets-chart.ts           # KEEP: Auth key ESO
├── lib/
│   └── tailscale-serve-helpers.ts               # NEW: Extract pattern from k8s-api chart
├── config/
│   └── applications.ts                          # REPLACE: Remove tailscale-ingresses, add 7 serve entries
└── imports/
    └── k8s.ts                                   # KEEP: Typed K8s resources
```

**Structure Decision**: Single generic `TailscaleServeChart` that accepts service configuration as props. Pattern extracted from working `k8s-api-tailscale-serve-chart.ts`. No separate chart files per service - configuration in `applications.ts` only.

**Key Insight**: The `k8s-api-tailscale-serve-chart.ts` already implements the optimal pattern with `--service` flag and socat forwarding. We extract this pattern into a reusable helper and generic chart.

## Complexity Tracking

*No constitution violations - all principles satisfied.*

| Consideration | Decision | Rationale |
|---------------|----------|-----------|
| 7 separate serve charts vs 1 generic chart | 1 generic chart | Configuration via props in `applications.ts`; Constitution Principle III (DRY) |
| Remove legacy ingress vs keep both | **DELETE entirely** | Constitution Principle IX (Forward-Only Development) - no backward compatibility |
| Create new helpers vs copy k8s-api pattern | Extract from k8s-api | Pattern already proven in `k8s-api-tailscale-serve-chart.ts`; reuse via helper |

## Files to DELETE (Complete Removal)

Per Constitution Principle IX (Forward-Only Development), the following files will be **completely deleted**, not deprecated:

| File | Reason for Deletion |
|------|---------------------|
| `cdk8s/charts/platform/tailscale-ingress-chart.ts` | Legacy hostname-based ingress pattern; replaced by Services |
| `tailscale-ingresses` entry in `applications.ts` | References deleted chart |

## Files to CREATE (Optimal Implementation)

| File | Purpose |
|------|---------|
| `cdk8s/lib/tailscale-serve-helpers.ts` | Extract serve script generation from k8s-api chart |
| `cdk8s/charts/platform/tailscale-serve-chart.ts` | Generic serve chart using helpers |

## applications.ts Changes

**REMOVE**:
```typescript
// DELETE THIS ENTIRE ENTRY
{
  name: 'tailscale-ingresses',
  namespace: 'tailscale',
  chart: { type: 'TailscaleIngressChart' },
  // ...
}
```

**ADD** (7 entries, one per service):
```typescript
// Example: ArgoCD
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
