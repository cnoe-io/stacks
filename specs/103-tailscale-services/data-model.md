# Data Model: Tailscale Architecture Optimization

**Feature**: 103-tailscale-services
**Date**: 2025-12-09

## Forward-Only Migration (Constitution Principle IX)

This migration implements the recommended hybrid architecture. Legacy patterns are replaced completely.

### Files to MODIFY

| File | Changes |
|------|---------|
| `cdk8s/charts/infra/tailscale-operator-chart.ts` | Set `apiServerProxyConfig.mode: "auth"`, add RBAC for tailnet identity |
| `cdk8s/config/applications.ts` | Update service names (`argocd2` → `argocd`), remove `k8s-api-tailscale-serve` after validation |

### Files to DELETE (After Validation)

| File | Current Purpose | Replacement |
|------|-----------------|-------------|
| `cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts` | Custom kubectl-proxy via Tailscale Services | Operator API Proxy (built-in) |

### Files to KEEP (No Changes)

| File | Purpose |
|------|---------|
| `cdk8s/charts/platform/tailscale-serve-chart.ts` | Generic chart for service exposure |
| `cdk8s/lib/tailscale-serve-helpers.ts` | Shared helpers for serve charts |
| `cdk8s/charts/secrets/tailscale-secrets-chart.ts` | Auth key ESO |
| `cdk8s/charts/secrets/tailscale-operator-secrets-chart.ts` | OAuth credentials ESO |
| `cdk8s/charts/infra/tailscale-crds-chart.ts` | CRDs |
| `cdk8s/charts/infra/tailscale-subnet-router-chart.ts` | Subnet router |

---

## Key Entities

### Entity: ApiServerProxyConfig

**Purpose**: Configuration for Tailscale Operator API Server Proxy

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `mode` | string | Yes | `"true"` | Proxy mode: `"true"`, `"auth"`, or `"noauth"` |

**Mode Values**:
- `"true"`: Legacy mode (equivalent to `"noauth"`)
- `"noauth"`: Proxy without identity impersonation
- `"auth"`: Proxy with OAuth identity impersonation (RECOMMENDED)

**Helm Values Integration**:
```typescript
// tailscale-operator-chart.ts
apiServerProxyConfig: {
  mode: "auth"  // Enable OAuth identity impersonation
}
```

---

### Entity: TailnetIdentityRBAC

**Purpose**: Kubernetes RBAC mapping tailnet identity to cluster roles

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `identity` | string | Yes | Tailscale identity (e.g., `vpittamp@github`) |
| `clusterRole` | string | Yes | Kubernetes ClusterRole to bind (e.g., `cluster-admin`) |
| `bindingName` | string | Yes | ClusterRoleBinding name |

**Kubernetes Resource**:
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
  name: "vpittamp@github"
```

**Validation Rules**:
- `identity` must match tailnet identity format exactly (case-sensitive)
- `clusterRole` must exist in cluster

---

### Entity: TailscaleServeChartProps

**Purpose**: Configuration interface for Tailscale serve deployments using Services mode

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `serviceName` | string | Yes | - | Service name for Tailscale Services (e.g., "argocd") |
| `backendHost` | string | Yes | - | Kubernetes service URL (e.g., "argocd-server.argocd.svc.cluster.local") |
| `backendPort` | number | Yes | - | Backend service port (e.g., 443, 3000) |
| `authKeySecretName` | string | No | "tailscale-auth-key" | Secret containing Tailscale auth key |
| `authKeySecretKey` | string | No | "authKey" | Key name in secret |
| `namespace` | string | No | "tailscale" | Deployment namespace |
| `exposedPort` | number | No | 443 | HTTPS port exposed via Tailscale |
| `backendInsecure` | boolean | No | false | Whether backend uses self-signed certificates |

**Validation Rules**:
- `serviceName` must be lowercase alphanumeric with hyphens only
- `backendHost` must be valid Kubernetes DNS name
- `backendPort` must be between 1-65535
- `exposedPort` must be between 1-65535

**Relationships**:
- References `Secret` resource for auth key
- Creates `Deployment` resource for Tailscale container
- Creates `Service` resource for health checks (optional)

---

### Entity: TailscaleService

**Purpose**: Tailscale service registration in the Tailscale network

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Service identifier (e.g., "svc:argocd") |
| `url` | string | Public URL (e.g., "https://svc-argocd.tail286401.ts.net") |
| `tag` | string | ACL tag for auto-approval (e.g., "tag:k8s-services") |
| `status` | enum | "active", "pending", "error" |

**State Transitions**:
```
pending → active (on successful registration)
pending → error (on ACL rejection or auth failure)
active → pending (on pod restart)
```

---

### Entity: ACLAutoApprover

**Purpose**: Tailscale ACL rule for automatic service approval

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `service` | string | Service pattern (e.g., "svc:argocd") |
| `approvers` | string[] | Tags allowed to register (e.g., ["tag:k8s-services"]) |

**Configuration Location**: Tailscale Admin Console → Access Controls

---

### Entity: ACLGrant (New for API Proxy)

**Purpose**: Tailscale ACL grant for API Server Proxy impersonation

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `src` | string[] | Source tags/users (e.g., ["tag:k8s-operator"]) |
| `dst` | string[] | Destination tags/users (e.g., ["tag:k8s-operator"]) |
| `app` | object | Application-specific capabilities |

**Configuration**:
```json
{
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
  ]
}
```

---

### Entity: StaleDevice

**Purpose**: Represents an offline Tailscale device blocking hostname reuse

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Tailscale device ID |
| `hostname` | string | Device hostname (e.g., "argocd") |
| `status` | string | Always "offline" for stale devices |
| `lastSeen` | datetime | Last online timestamp |

**Identification Criteria**:
- Status is "offline"
- Hostname matches cluster service pattern (`argocd`, `langfuse`, `gitea`, etc.)

---

## Service Configuration Matrix

| Service | serviceName | backendHost | backendPort | backendInsecure |
|---------|-------------|-------------|-------------|-----------------|
| ArgoCD | argocd | argocd-server.argocd.svc.cluster.local | 443 | true |
| Langfuse | langfuse | langfuse.langfuse.svc.cluster.local | 3000 | false |
| Gitea | gitea | gitea-http.gitea.svc.cluster.local | 3000 | false |
| kagent | kagent | kagent-dashboard.kagent.svc.cluster.local | 8082 | false |
| Kargo | kargo | kargo-controller.kargo.svc.cluster.local | 443 | true |
| Headlamp | headlamp | headlamp.headlamp.svc.cluster.local | 4466 | false |
| Keycloak | keycloak | keycloak.keycloak.svc.cluster.local | 8080 | false |

---

## URL Patterns

### Service Mode URLs

Format: `https://svc-<serviceName>.<tailnet>.ts.net`

| Service | URL |
|---------|-----|
| ArgoCD | `https://svc-argocd.tail286401.ts.net` |
| Langfuse | `https://svc-langfuse.tail286401.ts.net` |
| Gitea | `https://svc-gitea.tail286401.ts.net` |
| kagent | `https://svc-kagent.tail286401.ts.net` |
| Kargo | `https://svc-kargo.tail286401.ts.net` |
| Headlamp | `https://svc-headlamp.tail286401.ts.net` |
| Keycloak | `https://svc-keycloak.tail286401.ts.net` |

### Operator API Proxy URL

Format: `https://<operator-hostname>.<tailnet>.ts.net`

Example: `https://kind-operator.tail286401.ts.net`

---

## Kubernetes Resources Created

### By Tailscale Operator Chart

1. **ClusterRoleBinding** (`tailnet-admin-vpittamp`)
   - Binds tailnet identity `vpittamp@github` to `cluster-admin`
   - Required for API Proxy auth mode

### Per Serve Chart

1. **Deployment** (`tailscale-serve-<serviceName>`)
   - Container: Tailscale sidecar with `--service` flag
   - Mount: Auth key secret
   - Command: `tailscale up && tailscale serve`

2. **Service** (optional, for health checks)
   - ClusterIP service for readiness probes

3. **ArgoCD Application** (`<serviceName>-tailscale-serve`)
   - Sync wave: -60
   - Source: `cnoe://<serviceName>-tailscale-serve/manifests`

---

## External Dependencies

### Azure Key Vault

| Secret Name | Usage |
|-------------|-------|
| `TAILSCALE-AUTH-KEY` | Auth key with `tag:k8s-services` for serve charts |
| `TAILSCALE-OAUTH-CLIENT-ID` | OAuth client ID for Operator |
| `TAILSCALE-OAUTH-CLIENT-SECRET` | OAuth client secret for Operator |

### Tailscale Admin Console

| Configuration | Manual Setup Required |
|---------------|----------------------|
| Service definitions | Yes (once per service) |
| ACL auto-approvers | Yes (once per service) |
| ACL grants for API Proxy | Yes (once for Operator) |
| Tag creation | Yes (`tag:k8s-services`, `tag:k8s-operator`) |
