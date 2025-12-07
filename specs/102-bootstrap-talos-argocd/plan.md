# Implementation Plan: GitOps Bootstrap for Talos Linux Cluster

**Branch**: `102-bootstrap-talos-argocd` | **Date**: 2025-12-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/102-bootstrap-talos-argocd/spec.md`

## Summary

Bootstrap a Talos Linux cluster with ArgoCD-based GitOps, External Secrets Operator with Azure Workload Identity, and Tailscale for secure remote access. The implementation uses CDK8s for TypeScript-based manifest generation, matching patterns from stacks/main. Bootstrap scripts orchestrate Helm deployments and JWKS synchronization to Azure Storage.

## Technical Context

**Language/Version**: TypeScript (CDK8s charts), Bash (bootstrap scripts)
**Primary Dependencies**:
- CDK8s with cdk8s-plus-32 (Kubernetes manifest generation)
- Helm v3 (ArgoCD, ESO, Tailscale operator installation)
- talosctl, kubectl, az CLI (cluster/cloud operations)
- External Secrets Operator v0.9+ (secret synchronization)
- Tailscale Operator v1.86+ (Services feature for stable URLs)

**Storage**: Azure Key Vault (secrets), Azure Storage (OIDC JWKS hosting)
**Testing**: Manual verification (kubectl, argocd CLI), CDK8s synthesis validation
**Target Platform**: Kubernetes (Talos Linux on Hetzner Cloud)
**Project Type**: Infrastructure-as-Code (CDK8s charts + bootstrap scripts)
**Performance Goals**:
- Full bootstrap: <15 minutes
- ArgoCD sync: 10+ applications without degradation
- Secret fetch: <60 seconds after ExternalSecret creation
**Constraints**:
- No public API exposure (Tailscale only)
- Azure Workload Identity (no static credentials)
- Idempotent bootstrap (safe to re-run)
**Scale/Scope**: 5-node cluster (3 CP + 2 worker), ~10 managed applications

## Constitution Check

*No constitution file found - proceeding with standard engineering best practices*

| Gate | Status | Notes |
|------|--------|-------|
| Single responsibility | PASS | Each chart handles one component |
| Infrastructure as Code | PASS | All manifests via CDK8s |
| Secret management | PASS | Azure Key Vault via Workload Identity |
| Idempotency | PASS | Bootstrap script re-runnable |
| Documentation | PASS | Quickstart and research docs provided |

## Project Structure

### Documentation (this feature)

```
specs/102-bootstrap-talos-argocd/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: ArgoCD bootstrap, Workload Identity, Tailscale patterns
├── data-model.md        # Phase 1: Entity definitions (ArgoCD Apps, ClusterSecretStore, etc.)
├── quickstart.md        # Phase 1: Bootstrap guide
├── contracts/           # Phase 1: CDK8s chart interfaces
│   ├── argocd-chart-props.ts
│   ├── eso-chart-props.ts
│   └── tailscale-chart-props.ts
├── checklists/
│   └── requirements.md  # Specification quality checklist
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```
# Bootstrap scripts
scripts/
├── bootstrap-cluster.sh          # Main entry point
├── 01-install-argocd.sh          # Helm install ArgoCD
├── 02-sync-jwks.sh               # Upload OIDC keys to Azure Storage
├── 03-apply-base-apps.sh         # Apply CDK8s-generated manifests
└── lib/
    ├── common.sh                 # Shared functions
    ├── azure.sh                  # Azure CLI helpers
    └── talos.sh                  # talosctl helpers

# CDK8s charts (leverage existing stacks/main patterns)
cdk8s/
├── main-talos.ts                 # Entry point for Talos bootstrap
├── config/
│   └── talos-applications.ts     # Application configuration for Talos cluster
├── charts/
│   ├── platform/
│   │   ├── argocd-helm-chart.ts              # Helm release for ArgoCD
│   │   ├── argocd-tailscale-serve-chart.ts   # Existing (reuse from stacks/main)
│   │   └── argocd-applications-chart.ts      # App-of-apps pattern
│   ├── infra/
│   │   ├── tailscale-operator-chart.ts       # Existing (reuse from stacks/main)
│   │   └── tailscale-apiserver-proxy-chart.ts # K8s API via Tailscale
│   └── secrets/
│       ├── eso-helm-chart.ts                 # Helm release for ESO
│       ├── cluster-secret-store-chart.ts     # Azure Key Vault ClusterSecretStore
│       └── workload-identity-patch-chart.ts  # ServiceAccount annotations
└── lib/
    ├── eso-helpers.ts            # Existing (reuse from stacks/main)
    └── tailscale-serve-helpers.ts # Existing (reuse from stacks/main)
```

**Structure Decision**: Extend existing CDK8s project in stacks/main with Talos-specific entry point (`main-talos.ts`) and configuration. Bootstrap scripts in dedicated `scripts/` directory. Reuse existing helper libraries and chart patterns.

## Key Implementation Patterns

### Pattern 1: Helm-First ArgoCD Bootstrap

ArgoCD is installed via Helm (not self-managed initially) to break the chicken-and-egg problem:

```bash
# scripts/01-install-argocd.sh
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values values/argocd-values.yaml \
  --wait
```

After ArgoCD is running, it can manage its own configuration via App-of-Apps.

### Pattern 2: Azure Workload Identity JWKS Sync

OIDC issuer configuration for Azure AD trust:

```bash
# scripts/02-sync-jwks.sh
# Extract JWKS from cluster
kubectl get --raw /openid/v1/jwks > jwks.json

# Upload to Azure Storage static website
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name '$web' \
  --name .well-known/openid-configuration \
  --file openid-config.json

az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name '$web' \
  --name openid/v1/jwks \
  --file jwks.json
```

### Pattern 3: Tailscale Services for Stable URLs

Use Tailscale Services (not device hostnames) for stable access:

```typescript
// cdk8s/charts/platform/argocd-tailscale-serve-chart.ts
{
  serviceName: 'argocd',           // → svc-argocd.<tailnet>.ts.net
  backendHost: 'argocd-server.argocd.svc.cluster.local',
  backendPort: 443,
  backendInsecure: true
}
```

### Pattern 4: CDK8s App-of-Apps

Bootstrap applications via App-of-Apps pattern:

```typescript
// cdk8s/config/talos-applications.ts
export const talosApplications: ApplicationConfig[] = [
  {
    name: 'external-secrets-operator',
    namespace: 'external-secrets',
    chart: { type: 'EsoHelmChart' },
    argocd: { syncWave: '-100' }  // Deploy early
  },
  {
    name: 'cluster-secret-store',
    namespace: 'external-secrets',
    chart: { type: 'ClusterSecretStoreChart' },
    argocd: { syncWave: '-90' }
  },
  {
    name: 'tailscale-operator',
    namespace: 'tailscale',
    chart: { type: 'TailscaleOperatorChart' },
    argocd: { syncWave: '-80' }
  },
  // ... more applications
];
```

## Infrastructure Changes

### New Files

| File | Purpose |
|------|---------|
| `scripts/bootstrap-cluster.sh` | Main bootstrap entry point |
| `scripts/01-install-argocd.sh` | Helm install ArgoCD |
| `scripts/02-sync-jwks.sh` | Azure OIDC configuration |
| `scripts/03-apply-base-apps.sh` | Apply ArgoCD Applications |
| `cdk8s/main-talos.ts` | CDK8s entry point for Talos |
| `cdk8s/config/talos-applications.ts` | Application definitions |
| `cdk8s/charts/platform/argocd-helm-chart.ts` | ArgoCD Helm release |
| `cdk8s/charts/secrets/eso-helm-chart.ts` | ESO Helm release |
| `cdk8s/charts/secrets/cluster-secret-store-chart.ts` | Azure Key Vault store |

### Reused Files (from stacks/main)

| File | Purpose |
|------|---------|
| `cdk8s/lib/eso-helpers.ts` | ExternalSecret builders |
| `cdk8s/lib/tailscale-serve-helpers.ts` | Tailscale serve helpers |
| `cdk8s/charts/infra/tailscale-operator-chart.ts` | Tailscale operator |
| `cdk8s/charts/platform/argocd-tailscale-serve-chart.ts` | ArgoCD via Tailscale |

## Complexity Tracking

*No constitution violations to justify*

| Decision | Rationale |
|----------|-----------|
| Helm-first ArgoCD | Breaks chicken-and-egg; ArgoCD can self-manage after bootstrap |
| Separate entry point (main-talos.ts) | Talos-specific config without affecting Kind cluster setup |
| Reuse stacks/main charts | Consistent patterns, proven implementations |

## Dependencies

| Dependency | Required For | Status |
|------------|--------------|--------|
| Talos cluster (feature 100) | Target cluster | Prerequisite |
| Azure Key Vault | Secret storage | User responsibility |
| Azure Storage account | OIDC issuer hosting | User responsibility |
| Tailscale tailnet + OAuth | Secure access | User responsibility |

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| JWKS mismatch after cluster rebuild | Medium | High | Bootstrap script re-syncs JWKS automatically |
| ArgoCD sync conflicts | Low | Medium | Manual sync policy, operator approval |
| Tailscale OAuth expiry | Low | Medium | OAuth client with appropriate scopes |
| ESO workload identity failure | Medium | High | Clear error reporting, troubleshooting guide |

## Next Steps

1. **Phase 0** (research.md): ArgoCD bootstrap patterns, Azure Workload Identity setup, Tailscale Services configuration
2. **Phase 1** (design): data-model.md, contracts/, quickstart.md
3. **Phase 2** (tasks.md): Via `/speckit.tasks` command

## References

- [ArgoCD Helm Chart](https://github.com/argoproj/argo-helm)
- [External Secrets Operator](https://external-secrets.io/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [Tailscale Services](https://tailscale.com/kb/1552/tailscale-services)
