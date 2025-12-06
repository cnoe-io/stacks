# Data Model: GitOps Bootstrap for Talos Linux Cluster

**Branch**: `102-bootstrap-talos-argocd` | **Date**: 2025-12-06

This document defines the key entities, their relationships, and validation rules for the GitOps bootstrap feature.

## Entity Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Bootstrap Orchestration                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐                                                   │
│  │ Bootstrap State │                                                   │
│  │  (Script-level) │                                                   │
│  └────────┬────────┘                                                   │
│           │                                                             │
│           ▼                                                             │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │                    Kubernetes Resources                         │   │
│  ├────────────────────────────────────────────────────────────────┤   │
│  │                                                                 │   │
│  │  ┌───────────────┐    ┌────────────────────┐                   │   │
│  │  │ ArgoCD        │───▶│ Application        │                   │   │
│  │  │ Helm Release  │    │ (App-of-Apps Root) │                   │   │
│  │  └───────────────┘    └─────────┬──────────┘                   │   │
│  │                                 │                               │   │
│  │                    ┌────────────┼────────────┐                 │   │
│  │                    │            │            │                 │   │
│  │                    ▼            ▼            ▼                 │   │
│  │             ┌──────────┐ ┌──────────┐ ┌──────────────┐        │   │
│  │             │ ESO App  │ │ Tailscale│ │ Workload     │        │   │
│  │             │          │ │ App      │ │ Apps         │        │   │
│  │             └────┬─────┘ └────┬─────┘ └──────────────┘        │   │
│  │                  │            │                                │   │
│  │                  ▼            ▼                                │   │
│  │   ┌─────────────────┐  ┌──────────────────┐                   │   │
│  │   │ClusterSecretStore│  │ Tailscale        │                   │   │
│  │   │                 │  │ Operator         │                   │   │
│  │   └────────┬────────┘  └────────┬─────────┘                   │   │
│  │            │                    │                              │   │
│  │            ▼                    ▼                              │   │
│  │   ┌─────────────────┐  ┌──────────────────┐                   │   │
│  │   │ ExternalSecret  │  │ Tailscale        │                   │   │
│  │   │ (per secret)    │  │ Services         │                   │   │
│  │   └────────┬────────┘  └──────────────────┘                   │   │
│  │            │                                                   │   │
│  │            ▼                                                   │   │
│  │   ┌─────────────────┐                                          │   │
│  │   │ Kubernetes      │                                          │   │
│  │   │ Secret          │                                          │   │
│  │   └─────────────────┘                                          │   │
│  │                                                                 │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Bootstrap State (Script-Level)

Tracks the overall bootstrap progress and enables idempotent re-runs.

### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `phase` | enum | Current bootstrap phase | `helm-install`, `jwks-sync`, `gitops-takeover`, `complete` |
| `argocdInstalled` | boolean | Helm release exists | Check via `helm list -n argocd` |
| `jwksSynced` | boolean | JWKS uploaded to Azure | Check via HTTP GET on issuer URL |
| `rootAppApplied` | boolean | Root Application exists | Check via `kubectl get app argocd-bootstrap -n argocd` |
| `lastRunTime` | timestamp | Last successful run | ISO 8601 format |
| `errorMessage` | string | Last error if failed | Optional |

### State Transitions

```
INITIAL ──▶ helm-install ──▶ jwks-sync ──▶ gitops-takeover ──▶ complete
                 │               │                 │
                 ▼               ▼                 ▼
              (error)        (error)           (error)
```

### Idempotency Rules

- If `argocdInstalled=true`, skip Phase 1 (Helm install)
- If `jwksSynced=true`, skip Phase 2 (only re-sync on explicit flag or cluster rebuild)
- If `rootAppApplied=true`, Phase 3 becomes an update (kubectl apply is idempotent)

---

## 2. ArgoCD Application

Represents a GitOps-managed application in ArgoCD.

### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | Application name | `^[a-z0-9-]+$`, max 63 chars |
| `namespace` | string | Target namespace | Must exist or `CreateNamespace=true` |
| `project` | string | ArgoCD project | Default: `default` |
| `repoUrl` | string | Git repository URL | Valid HTTPS or SSH URL |
| `path` | string | Path in repository | Relative path to manifests |
| `targetRevision` | string | Git ref | Branch, tag, or commit SHA |
| `syncWave` | integer | Deployment order | -110 to 100, lower = earlier |
| `syncPolicy` | object | Automation settings | See below |

### Sync Policy Options

```typescript
interface SyncPolicy {
  automated?: {
    prune: boolean;    // Delete resources removed from Git
    selfHeal: boolean; // Auto-sync when cluster drifts
  };
  syncOptions?: string[]; // e.g., ['CreateNamespace=true']
}
```

### Relationships

- **Parent**: None (root app) or another Application (child)
- **Children**: 0..N child Applications (App-of-Apps pattern)
- **Owns**: Kubernetes resources defined in source path

---

## 3. ClusterSecretStore

Defines connection to Azure Key Vault for secret retrieval.

### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | Store name | `^[a-z0-9-]+$`, cluster-scoped |
| `vaultUrl` | string | Key Vault URL | `https://{name}.vault.azure.net` |
| `authType` | enum | Authentication method | `WorkloadIdentity` (required) |
| `serviceAccountRef.name` | string | ServiceAccount name | Must exist in referenced namespace |
| `serviceAccountRef.namespace` | string | ServiceAccount namespace | Must have WI annotations |

### Validation Rules

- `vaultUrl` must be reachable from cluster
- Referenced ServiceAccount must have:
  - `azure.workload.identity/client-id` annotation
  - `azure.workload.identity/tenant-id` annotation
  - `azure.workload.identity/use: "true"` label

### Status Fields

| Field | Type | Description |
|-------|------|-------------|
| `status.conditions.type` | string | `Ready` or `NotReady` |
| `status.conditions.status` | string | `True` or `False` |
| `status.conditions.reason` | string | Error code if not ready |
| `status.conditions.message` | string | Human-readable message |

---

## 4. ExternalSecret

Maps Azure Key Vault secrets to Kubernetes Secrets.

### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | ExternalSecret name | `^[a-z0-9-]+$` |
| `namespace` | string | Target namespace | Must exist |
| `secretStoreRef.name` | string | ClusterSecretStore name | Must exist and be Ready |
| `secretStoreRef.kind` | enum | Store type | `ClusterSecretStore` |
| `refreshInterval` | duration | Sync frequency | e.g., `1h`, `24h` |
| `target.name` | string | Output Secret name | Defaults to ExternalSecret name |
| `target.creationPolicy` | enum | Creation behavior | `Owner`, `Merge`, `None` |
| `data` | array | Secret mappings | See below |

### Data Mapping

```typescript
interface DataMapping {
  secretKey: string;      // Key in Kubernetes Secret
  remoteRef: {
    key: string;          // Key Vault secret name
    property?: string;    // JSON property (if secret is JSON)
  };
}
```

### Status Fields

| Field | Type | Description |
|-------|------|-------------|
| `status.refreshTime` | timestamp | Last successful sync |
| `status.syncedResourceVersion` | string | Current Secret resourceVersion |
| `status.conditions.type` | string | `Ready`, `Deleted` |
| `status.conditions.status` | string | `True`, `False` |

---

## 5. Tailscale Operator

Manages Tailscale network resources in Kubernetes.

### Deployment Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `namespace` | string | Operator namespace | Default: `tailscale` |
| `hostname` | string | Tailscale device name | `^[a-z0-9-]+$` |
| `apiServerProxy` | boolean | Enable API proxy mode | Required for kubectl access |
| `tags` | array | Device tags | e.g., `['tag:k8s-operator']` |

### Authentication

- **OAuth Client**: For operator itself (from Azure Key Vault)
- **Auth Key**: For service pods (tagged, reusable, ephemeral)

---

## 6. Tailscale Service

Exposes a Kubernetes service via Tailscale.

### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `serviceName` | string | Tailscale service name | `^[a-z0-9-]+$` |
| `backendHost` | string | K8s service DNS | `{svc}.{ns}.svc.cluster.local` |
| `backendPort` | integer | Target port | 1-65535 |
| `backendInsecure` | boolean | Skip TLS verify | For self-signed certs |

### Generated URLs

| Service | Pattern | Example |
|---------|---------|---------|
| ArgoCD | `svc-argocd.<tailnet>.ts.net` | `svc-argocd.tail286401.ts.net` |
| K8s API | `svc-k8s-api.<tailnet>.ts.net` | `svc-k8s-api.tail286401.ts.net` |

---

## 7. CDK8s Application Config

Configuration object driving chart generation.

### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `name` | string | Application name | `^[a-z0-9-]+$` |
| `namespace` | string | Target namespace | Optional, chart default |
| `chart.type` | string | Chart class name | Must be registered in factory |
| `chart.props` | object | Chart-specific props | Type-safe per chart |
| `argocd.syncWave` | string | Deployment order | `-110` to `100` |
| `argocd.labels` | object | Application labels | Key-value pairs |
| `argocd.syncPolicy` | object | Automation settings | Optional |

### Example

```typescript
{
  name: 'external-secrets-operator',
  namespace: 'external-secrets',
  chart: {
    type: 'EsoHelmChart',
    props: {
      version: '0.9.13',
      enableWebhook: true
    }
  },
  argocd: {
    syncWave: '-100',
    syncPolicy: {
      automated: { prune: true, selfHeal: true }
    }
  }
}
```

---

## Relationships Summary

```
Bootstrap State
    │
    ├── triggers ──▶ ArgoCD Helm Release
    │                     │
    │                     └── manages ──▶ ArgoCD (running)
    │
    ├── uploads ──▶ JWKS to Azure Storage
    │                     │
    │                     └── trusted by ──▶ Azure AD
    │
    └── applies ──▶ Root Application
                          │
                          └── creates ──▶ Child Applications
                                              │
                          ┌───────────────────┼───────────────────┐
                          ▼                   ▼                   ▼
                    ESO Application     Tailscale App       Workload Apps
                          │                   │
                          ▼                   ▼
                ClusterSecretStore     Tailscale Operator
                          │                   │
                          ▼                   ▼
                  ExternalSecret      Tailscale Services
                          │                   │
                          ▼                   ▼
                  Kubernetes Secret   Stable Service URLs
                          │
                          └── consumed by ──▶ Applications
```

---

## Validation Checklist

### Pre-Bootstrap Requirements

- [ ] Talos cluster running with kubeconfig available
- [ ] Cilium CNI ready (all pods in Running state)
- [ ] Azure Key Vault exists with required secrets
- [ ] Azure Storage account configured for static website
- [ ] Azure AD federated credential configured
- [ ] Tailscale OAuth client created with required scopes
- [ ] Tagged auth key generated for services

### Post-Bootstrap Validation

- [ ] ArgoCD accessible via Tailscale (`svc-argocd.<tailnet>.ts.net`)
- [ ] ClusterSecretStore reports Ready status
- [ ] ExternalSecret syncs within 60 seconds
- [ ] Kubernetes API accessible via Tailscale (`svc-k8s-api.<tailnet>.ts.net`)
- [ ] All ArgoCD Applications show Synced/Healthy status
