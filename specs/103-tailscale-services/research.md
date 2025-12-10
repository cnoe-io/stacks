# Research: Tailscale Stale Device Cleanup and Services Migration

**Feature**: 103-tailscale-services
**Date**: 2025-12-06
**Status**: Complete

## Research Questions

### RQ-1: How do Tailscale Services differ from Hostname Mode?

**Decision**: Use Tailscale Services (`--service` flag) instead of hostname mode

**Rationale**:
- **Hostname Mode** (legacy): Each pod registers as `<hostname>.<tailnet>.ts.net`. If the hostname is "claimed" by an offline device, new pods get suffixed names (`argocd-1`, `argocd-2`), triggering new Let's Encrypt certificate requests.
- **Services Mode** (new): Pods register to a stable service (`svc:<name>`) via `tailscale up --service=svc:<name>`. Multiple pods can serve the same service. URLs remain stable regardless of pod identity.

**Alternatives Considered**:
1. **ProxyClass with hostname cleanup**: Rejected - still vulnerable to race conditions
2. **Headless service with DNS**: Rejected - doesn't solve Let's Encrypt rate limits
3. **Ingress Controller mode**: Rejected - doesn't provide stable URLs across cluster recreation

**Source**: Tailscale Services documentation (v1.86.0+), existing `k8s-api-tailscale-serve-chart.ts` implementation

---

### RQ-2: What is the correct `--service` flag syntax?

**Decision**: Use `--service=svc:<service-name>` format

**Rationale**:
- The `svc:` prefix is required to indicate service mode
- Service name follows the pattern `svc:<name>` where `<name>` matches ACL auto-approver rules
- Example: `tailscale up --service=svc:argocd` registers to `svc:argocd` service

**Implementation**:
```bash
# In tailscale container entrypoint
tailscale up --authkey="$TS_AUTHKEY" --service=svc:argocd
tailscale serve https / http://argocd-server.argocd.svc.cluster.local:443
```

**Source**: `cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts` lines 85-95

---

### RQ-3: How should ACL auto-approvers be configured?

**Decision**: Configure per-service auto-approvers in Tailscale Admin Console

**Rationale**:
- ACL auto-approvers automatically approve service registrations from tagged devices
- Tag `tag:k8s-services` on auth key enables auto-approval
- Each service needs explicit auto-approver rule

**Configuration** (Tailscale Admin Console → Access Controls):
```json
{
  "autoApprovers": {
    "routes": {},
    "services": {
      "svc:argocd": ["tag:k8s-services"],
      "svc:langfuse": ["tag:k8s-services"],
      "svc:gitea": ["tag:k8s-services"],
      "svc:kagent": ["tag:k8s-services"],
      "svc:kargo": ["tag:k8s-services"],
      "svc:headlamp": ["tag:k8s-services"],
      "svc:keycloak": ["tag:k8s-services"]
    }
  }
}
```

**Source**: Tailscale ACL documentation, spec.md FR-006

---

### RQ-4: What auth key configuration is required?

**Decision**: Use existing tagged ephemeral auth key from Azure Key Vault

**Rationale**:
- Auth key already exists in Azure Key Vault as `TAILSCALE-AUTH-KEY`
- Key has `tag:k8s-services` tag for auto-approval
- Key is ephemeral (devices removed on disconnect)
- Synced to Kubernetes via `tailscale-secrets-chart.ts`

**Current Flow**:
1. Azure Key Vault stores `TAILSCALE-AUTH-KEY`
2. `tailscale-secrets-chart.ts` creates ExternalSecret
3. ESO syncs to `tailscale-auth-key` secret in `tailscale` namespace
4. Serve charts mount secret as `TS_AUTHKEY` environment variable

**No Changes Needed**: Existing infrastructure supports this feature

**Source**: `cdk8s/charts/secrets/tailscale-secrets-chart.ts`

---

### RQ-5: What is the current state of stale devices?

**Decision**: Manual cleanup required before migration

**Current State** (from spec background):
- ArgoCD: Rate limited until ~2025-12-07 00:15 UTC
- Gitea: Working via `gitea-1.tail286401.ts.net`
- kagent: Working via `kagent-1.tail286401.ts.net`
- Multiple stale devices visible as "offline" in `tailscale status`

**Cleanup Process**:
```bash
# List devices
tailscale status

# Remove stale device (requires admin access)
tailscale devices remove <device-id>

# Or via Tailscale Admin Console → Machines → Delete
```

**Source**: spec.md Background section

---

### RQ-6: What backend configurations are needed per service?

**Decision**: Document per-service backend configuration

| Service | Backend Host | Port | TLS | Notes |
|---------|-------------|------|-----|-------|
| ArgoCD | `argocd-server.argocd.svc.cluster.local` | 443 | Insecure (self-signed) | Uses `+insecure` in serve config |
| Langfuse | `langfuse.langfuse.svc.cluster.local` | 3000 | None | HTTP backend |
| Gitea | `gitea-http.gitea.svc.cluster.local` | 3000 | None | HTTP backend |
| kagent | `kagent-dashboard.kagent.svc.cluster.local` | 8082 | None | HTTP backend |
| Kargo | `kargo-controller.kargo.svc.cluster.local` | 443 | Insecure | Uses `+insecure` |
| Headlamp | `headlamp.headlamp.svc.cluster.local` | 4466 | None | HTTP backend |
| Keycloak | `keycloak.keycloak.svc.cluster.local` | 8080 | None | HTTP backend |

**Source**: Existing `tailscale-ingress-chart.ts`, service definitions

---

### RQ-7: Should we use existing helpers or create new ones?

**Decision**: Extend existing `tailscale-serve-helpers.ts`

**Rationale**:
- `cdk8s/lib/tailscale-serve-helpers.ts` already exists
- Contains `TailscaleServeChartProps` interface
- Contains `resolveProps()` function for defaults
- Add new `createServiceModeDeployment()` helper function

**New Helper Function Signature**:
```typescript
export function createServiceModeDeployment(
  scope: Construct,
  id: string,
  props: TailscaleServeChartProps
): k8s.KubeDeployment;
```

**Source**: Constitution Principle III (Modular Chart Composition)

---

### RQ-8: What is the sync wave ordering for serve charts?

**Decision**: Use sync wave -60 for serve charts

**Rationale**:
- Secrets (sync wave -70) must exist before serve pods
- Serve charts depend on auth key secret
- Current `k8s-api-tailscale-serve` uses sync wave -60
- Consistent ordering across all serve charts

**Sync Wave Order**:
1. `-120`: CRDs
2. `-85`: Operator secrets
3. `-75`: Operator
4. `-70`: Auth key secret (ESO)
5. `-60`: Serve charts (ArgoCD, Langfuse, etc.)
6. `-50`: Subnet router

**Source**: `cdk8s/config/applications.ts`, Constitution Principle IV

---

## Summary

All research questions resolved. Key decisions:

1. **Services Mode**: Use `--service=svc:<name>` for stable URLs
2. **ACL Auto-Approvers**: Configure in Tailscale Admin Console per service
3. **Auth Key**: Reuse existing Azure Key Vault + ESO infrastructure
4. **Helpers**: Extend `tailscale-serve-helpers.ts` with service mode function
5. **Sync Waves**: All serve charts at sync wave -60
6. **Legacy Removal**: Delete `tailscale-ingress-chart.ts` after migration (Constitution Principle IX)

**No NEEDS CLARIFICATION items remain.**
