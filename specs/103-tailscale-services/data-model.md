# Data Model: Tailscale Stale Device Cleanup and Services Migration

**Feature**: 103-tailscale-services
**Date**: 2025-12-06

## Forward-Only Migration (Constitution Principle IX)

This migration completely replaces the legacy Tailscale Ingress pattern. There is no backward compatibility.

### Files to DELETE

| File | Current Purpose | Replacement |
|------|-----------------|-------------|
| `cdk8s/charts/platform/tailscale-ingress-chart.ts` | Legacy hostname-based ingress via Tailscale Operator | `tailscale-serve-chart.ts` |
| `tailscale-ingresses` in `applications.ts` | Deploys 7 services via Ingress | 7 individual serve chart entries |

### Files to CREATE

| File | Purpose |
|------|---------|
| `cdk8s/lib/tailscale-serve-helpers.ts` | Extracted serve script from `k8s-api-tailscale-serve-chart.ts` |
| `cdk8s/charts/platform/tailscale-serve-chart.ts` | Generic chart using helpers |

### Files to KEEP (No Changes)

| File | Purpose |
|------|---------|
| `cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts` | Reference implementation (already uses optimal pattern) |
| `cdk8s/charts/secrets/tailscale-secrets-chart.ts` | Auth key ESO |
| `cdk8s/charts/infra/tailscale-operator-chart.ts` | Operator deployment |
| `cdk8s/charts/infra/tailscale-crds-chart.ts` | CRDs |

---

## Key Entities

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
| `url` | string | Public URL (e.g., "https://argocd-<cluster>.tail286401.ts.net") |
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

Format: `https://<serviceName>.<tailnet>.ts.net`

| Service | URL |
|---------|-----|
| ArgoCD | `https://argocd-<cluster>.tail286401.ts.net` |
| Langfuse | `https://langfuse-<cluster>.tail286401.ts.net` |
| Gitea | `https://gitea-<cluster>.tail286401.ts.net` |
| kagent | `https://kagent-<cluster>.tail286401.ts.net` |
| Kargo | `https://kargo-<cluster>.tail286401.ts.net` |
| Headlamp | `https://headlamp-<cluster>.tail286401.ts.net` |
| Keycloak | `https://keycloak-<cluster>.tail286401.ts.net` |

### Legacy Hostname URLs (deprecated)

Format: `https://<device-hostname>.<tailnet>.ts.net` (often ends up with `-1`, `-2`, … suffix drift)

| Service | Legacy URL | Status |
|---------|------------|--------|
| ArgoCD | `https://argocd-1.tail286401.ts.net` | Blocked by rate limit |
| Gitea | `https://gitea-1.tail286401.ts.net` | Active (suffixed) |
| kagent | `https://kagent-1.tail286401.ts.net` | Active (suffixed) |

---

## Kubernetes Resources Created

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
| `TAILSCALE-AUTH-KEY` | Auth key with `tag:k8s-services` |

### Tailscale Admin Console

| Configuration | Manual Setup Required |
|---------------|----------------------|
| Service definitions | Yes (once per service) |
| ACL auto-approvers | Yes (once per service) |
| Tag creation | Yes (`tag:k8s-services`) |
