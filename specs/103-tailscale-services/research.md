# Research: Tailscale Architecture Optimization

**Feature**: 103-tailscale-services
**Date**: 2025-12-09
**Status**: Complete

## Architecture Analysis

### Current State

The cluster has multiple Tailscale integration points that evolved organically:

| Component | Purpose | Status |
|-----------|---------|--------|
| Tailscale Operator | Helm-deployed, API Server Proxy enabled | Active but underutilized |
| Custom kubectl-proxy | `k8s-api-tailscale-serve-chart.ts` with Services | Active |
| Tailscale Serve Charts | Individual services via `--service` flag | Active with suffixed names |
| Subnet Router | Direct pod/service IP access | Active |

**Issues Identified**:
1. **Overlapping kubectl access**: Both Operator API Proxy and custom kubectl-proxy exist
2. **Service naming workarounds**: Using `argocd2`, `langfuse2` due to Let's Encrypt limits
3. **Token-based only**: No OAuth identity for kubectl; static tokens expire/leak

### Recommended Architecture (Hybrid)

Based on Tailscale documentation research (December 2025):

**kubectl access**: Use Operator API Proxy in "auth" mode
- OAuth identity impersonation (`vpittamp@github`)
- No token management required
- RBAC via tailnet identity

**Service access**: Keep Tailscale Services pattern
- Stable URLs via `--service=svc:<name>` flag
- `svc-<name>.<tailnet>.ts.net` format
- Persistent storage for certificates

---

## Research Questions

### RQ-1: What is the optimal kubectl access pattern?

**Decision**: Use Tailscale Operator API Server Proxy in "auth" mode

**Rationale**:
- **Auth Mode**: Operator impersonates tailnet identity in Kubernetes RBAC
- **Identity-based**: Uses `vpittamp@github` instead of ServiceAccount tokens
- **No token expiration**: OAuth tokens managed automatically by Tailscale
- **No custom pods**: Operator handles everything

**Alternatives Considered**:
1. **Custom kubectl-proxy chart**: Current approach, works but requires token management
2. **noauth mode**: Proxy-only without impersonation, less secure
3. **Direct port-forward**: Requires cluster host access, not remote-friendly

**Configuration**:
```typescript
// tailscale-operator-chart.ts Helm values
apiServerProxyConfig: {
  mode: "auth"  // Not "true" or "noauth"
}
```

**Source**: [Tailscale API Server Proxy docs](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)

---

### RQ-2: How does Operator API Proxy auth mode work?

**Decision**: Document impersonation flow for implementation

**Rationale**:
Auth mode uses Kubernetes impersonation headers to map tailnet identity to RBAC.

**Flow**:
1. User connects to Tailscale with identity `vpittamp@github`
2. User runs `tailscale configure kubeconfig <operator-hostname>`
3. kubeconfig points to `https://<operator-hostname>:443`
4. kubectl command sent to Operator pod
5. Operator extracts tailnet identity from connection
6. Operator impersonates user in Kubernetes API request
7. Kubernetes RBAC evaluates against impersonated identity
8. Response returned to user

**RBAC Requirements**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tailnet-admin-vpittamp
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: "vpittamp@github"  # Must match tailnet identity exactly
```

**Source**: Tailscale API Server Proxy documentation, Kubernetes impersonation docs

---

### RQ-3: What ACL configuration is needed for API Proxy?

**Decision**: Configure grants for Operator to access API and impersonate users

**Rationale**:
The Operator needs ACL grants to:
1. Connect to Tailscale network
2. Access Kubernetes API via proxy
3. Impersonate users (in auth mode)

**Required ACL**:
```json
{
  "tagOwners": {
    "tag:k8s-operator": ["vpittamp@github"]
  },
  "grants": [
    {
      "src": ["tag:k8s-operator"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["system:masters"]
          }
        }]
      }
    }
  ],
  "acls": [
    {"action": "accept", "src": ["vpittamp@github"], "dst": ["tag:k8s-operator:443"]}
  ]
}
```

**Source**: [Tailscale Kubernetes Operator grants](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)

---

### RQ-4: How do Tailscale Services differ from Hostname Mode?

**Decision**: Use Tailscale Services (`--service` flag) for stable URLs

**Rationale**:
- **Hostname Mode** (legacy): Each pod registers as `<hostname>.<tailnet>.ts.net`. If hostname "claimed" by offline device, pods get suffixed names (`argocd-1`, `argocd-2`), triggering new Let's Encrypt requests.
- **Services Mode** (current): Pods register to stable service (`svc:<name>`) via `--service=svc:<name>`. Multiple pods can serve same service. URLs remain stable regardless of pod identity.

**Alternatives Considered**:
1. **ProxyClass with hostname cleanup**: Rejected - still vulnerable to race conditions
2. **Headless service with DNS**: Rejected - doesn't solve Let's Encrypt rate limits
3. **Ingress Controller mode**: Rejected - doesn't provide stable URLs across cluster recreation

**Source**: [Tailscale Services docs](https://tailscale.com/kb/1552/tailscale-services)

---

### RQ-5: What is the correct `--service` flag syntax?

**Decision**: Use `--service=svc:<service-name>` format

**Rationale**:
- The `svc:` prefix is required to indicate service mode
- Service name follows the pattern `svc:<name>` where `<name>` matches ACL auto-approver rules
- Example: `tailscale up --service=svc:argocd` registers to `svc:argocd` service

**Implementation**:
```bash
# In tailscale container entrypoint
tailscale up --authkey="$TS_AUTHKEY"
tailscale serve --service=svc:argocd https / http://argocd-server.argocd.svc.cluster.local:443
```

**Source**: `cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts`, Tailscale serve docs

---

### RQ-6: How should ACL auto-approvers be configured?

**Decision**: Configure per-service auto-approvers in Tailscale Admin Console

**Rationale**:
- ACL auto-approvers automatically approve service registrations from tagged devices
- Tag `tag:k8s-services` on auth key enables auto-approval
- Each service needs explicit auto-approver rule

**Configuration** (Tailscale Admin Console → Access Controls):
```json
{
  "autoApprovers": {
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

**Source**: Tailscale ACL documentation, spec.md FR-010

---

### RQ-7: What auth key configuration is required?

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

### RQ-8: What backend configurations are needed per service?

**Decision**: Document per-service backend configuration

| Service | Backend Host | Port | TLS | Notes |
|---------|-------------|------|-----|-------|
| ArgoCD | `argocd-server.argocd.svc.cluster.local` | 443 | Insecure (self-signed) | Uses `+insecure` |
| Langfuse | `langfuse.langfuse.svc.cluster.local` | 3000 | None | HTTP backend |
| Gitea | `gitea-http.gitea.svc.cluster.local` | 3000 | None | HTTP backend |
| kagent | `kagent-dashboard.kagent.svc.cluster.local` | 8082 | None | HTTP backend |
| Kargo | `kargo-controller.kargo.svc.cluster.local` | 443 | Insecure | Uses `+insecure` |
| Headlamp | `headlamp.headlamp.svc.cluster.local` | 4466 | None | HTTP backend |
| Keycloak | `keycloak.keycloak.svc.cluster.local` | 8080 | None | HTTP backend |

**Source**: Existing `tailscale-serve-chart.ts`, service definitions

---

### RQ-9: What is the sync wave ordering?

**Decision**: Use sync wave -60 for serve charts, -75 for operator

**Rationale**:
- CRDs must exist before operator
- Operator must exist before API proxy is available
- Secrets must exist before serve pods
- Serve charts depend on auth key secret

**Sync Wave Order**:
1. `-120`: CRDs
2. `-85`: Operator secrets (OAuth credentials)
3. `-75`: Operator (with API Proxy enabled)
4. `-70`: Auth key secret (ESO for services)
5. `-60`: Serve charts (ArgoCD, Langfuse, etc.)
6. `-50`: Subnet router

**Source**: `cdk8s/config/applications.ts`, Constitution Principle IV

---

### RQ-10: Should we remove the custom kubectl-proxy after migration?

**Decision**: Yes, remove after Operator API Proxy is validated

**Rationale**:
- Constitution Principle IX (Forward-Only Development) requires removing legacy patterns
- Once Operator API Proxy works, custom chart is redundant
- Keep custom chart until validation complete (48+ hours of testing)

**Deprecation Steps**:
1. Configure and validate Operator API Proxy auth mode
2. Test kubectl from M1 Mac using `tailscale configure kubeconfig`
3. Validate for 48+ hours
4. Remove `k8s-api-tailscale-serve` from applications.ts
5. Delete `k8s-api-tailscale-serve-chart.ts`

**Source**: Constitution Principle IX, spec.md FR-013

---

## Summary

All research questions resolved. Key decisions:

1. **kubectl Access**: Use Operator API Proxy in "auth" mode for OAuth identity
2. **Service Access**: Keep Tailscale Services (`--service` flag) for stable URLs
3. **RBAC**: ClusterRoleBinding maps `vpittamp@github` to `cluster-admin`
4. **ACL Grants**: Configure impersonation grants for Operator
5. **Auto-Approvers**: Configure per-service rules for `tag:k8s-services`
6. **Auth Keys**: Reuse existing Azure Key Vault + ESO infrastructure
7. **Sync Waves**: -75 for Operator, -60 for serve charts
8. **Legacy Removal**: Delete custom kubectl-proxy after Operator validation

**No NEEDS CLARIFICATION items remain.**

## Sources

- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [API Server Proxy](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)
- [Tailscale Services](https://tailscale.com/kb/1552/tailscale-services)
- [Cluster Ingress](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress)
- [Tailscale serve command](https://tailscale.com/kb/1242/tailscale-serve)
