# Data Model: Hub-and-Spoke ArgoCD Architecture

**Feature**: 108-hub-and-spoke
**Date**: 2025-12-17

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              HUB CLUSTER                                 │
│                                                                          │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │
│  │ ClusterSecret│     │ Application  │     │    Stage     │            │
│  │              │────▶│              │────▶│   (Kargo)    │            │
│  │ name         │     │ destination  │     │ argocdConfig │            │
│  │ server       │     │ source       │     │              │            │
│  │ credentials  │     │ syncPolicy   │     │              │            │
│  └──────────────┘     └──────────────┘     └──────────────┘            │
│         │                    │                    │                     │
│         │                    │                    │                     │
│         │     references     │    updates         │                     │
│         └────────────────────┼────────────────────┘                     │
│                              │                                          │
│  ┌──────────────┐            │                                          │
│  │ExternalSecret│            │                                          │
│  │              │────────────┘                                          │
│  │ target       │                                                       │
│  │ secretStore  │                                                       │
│  └──────────────┘                                                       │
└─────────────────────────────────────────────────────────────────────────┘
         │
         │ manages
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           SPOKE CLUSTERS                                 │
│                                                                          │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │
│  │ ServiceAcct  │     │  Namespace   │     │  Workloads   │            │
│  │ argocd-      │────▶│              │────▶│              │            │
│  │ remote-mgr   │     │ backstage    │     │ Deployments  │            │
│  └──────────────┘     │ langfuse     │     │ Services     │            │
│                       │ etc.         │     │ ConfigMaps   │            │
│                       └──────────────┘     └──────────────┘            │
└─────────────────────────────────────────────────────────────────────────┘
```

## Core Entities

### 1. HubCluster

The dedicated management cluster running ArgoCD, Kargo, and supporting services.

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| name | string | Cluster identifier | `hub-cluster` |
| server | string | Kubernetes API URL | Tailscale service URL |
| nodeCount | integer | Number of nodes | 1 (single-node) |
| nodeType | string | Hetzner instance type | CX22 or CX32 |
| talosVersion | string | Talos Linux version | 1.11.5 |
| kubernetesVersion | string | K8s version | 1.32.0 |
| podCIDR | string | Pod network range | 10.244.0.0/16 |
| serviceCIDR | string | Service network range | 10.96.0.0/12 |
| privateIP | string | Node private IP | 10.1.1.1 |

**State Transitions**:
- `Provisioning` → `Bootstrapping` → `Running` → `Degraded` → `Running`
- `Running` → `Upgrading` → `Running`
- Any → `Failed` (on unrecoverable error)

### 2. SpokeCluster

A Kubernetes cluster managed by the hub ArgoCD.

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| name | string | Cluster identifier | Unique across all spokes |
| displayName | string | Human-readable name | Optional |
| server | string | Kubernetes API URL | Tailscale service URL |
| environment | enum | Cluster purpose | `development` \| `staging` \| `production` |
| hostMachine | string | Physical host | `hetzner` \| `thinkpad` \| `ryzen` \| `talos` |
| status | enum | Connection status | `Connected` \| `Disconnected` \| `Unknown` |
| lastSyncTime | timestamp | Last successful sync | ISO 8601 |

**Identity**: Uniquely identified by `name` field.

**State Transitions**:
- `Unknown` → `Connected` (on successful health check)
- `Connected` → `Disconnected` (on connection failure)
- `Disconnected` → `Connected` (on reconnection)

### 3. ClusterSecret

ArgoCD cluster secret for spoke registration.

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| name | string | Secret name | `cluster-<spokeName>` |
| namespace | string | Secret namespace | `argocd` |
| clusterName | string | Spoke cluster name | Must match SpokeCluster.name |
| server | string | K8s API URL | Valid HTTPS URL |
| caData | string | CA certificate | Base64-encoded PEM |
| bearerToken | string | ServiceAccount token | Valid K8s token |
| labels | map | Metadata labels | Must include `argocd.argoproj.io/secret-type: cluster` |

**Relationships**:
- References exactly one `SpokeCluster`
- Managed by one `ExternalSecret`

### 4. ExternalSecret

ESO resource that syncs spoke credentials from Azure Key Vault.

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| name | string | ExternalSecret name | `argocd-cluster-<spokeName>` |
| namespace | string | ESO namespace | `argocd` |
| secretStoreRef | object | ClusterSecretStore reference | `azure-keyvault-store` |
| target | string | Target Secret name | Same as ClusterSecret.name |
| refreshInterval | duration | Sync interval | `1h` default |
| dataKeys | array | Remote key mappings | bearerToken, caData |

**Relationships**:
- Creates/updates exactly one `ClusterSecret`
- References `ClusterSecretStore` (cluster-scoped)

### 5. ApplicationConfig

CDK8s configuration for applications with cluster targeting.

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| name | string | Application name | Unique per cluster |
| namespace | string | Target namespace | Valid K8s namespace |
| disabled | boolean | Skip synthesis | Default: false |
| clusterType | enum | Cluster type filter | `kind` \| `talos` \| `both` |
| targetCluster | string | Destination cluster | `hub` or spoke name |
| chart | object | Chart configuration | Type + props |
| argocd | object | ArgoCD configuration | Sync wave, labels, etc. |

**Relationships**:
- Generates one `ArgoCD Application`
- References zero or one `SpokeCluster` via targetCluster

### 6. ArgoCD Application

Generated Application resource targeting a cluster.

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| name | string | Application name | From ApplicationConfig.name |
| namespace | string | ArgoCD namespace | `argocd` |
| project | string | ArgoCD project | `default` |
| destination.name | string | Target cluster name | From targetCluster or derived |
| destination.namespace | string | Deployment namespace | From ApplicationConfig.namespace |
| source.repoURL | string | Git repository | GitHub or cnoe:// |
| source.path | string | Manifests path | `<app>/manifests` |
| syncPolicy | object | Auto-sync config | prune, selfHeal |

**Relationships**:
- Targets exactly one cluster (hub or spoke)
- Managed by optional `Kargo Stage`

### 7. Kargo Stage

Kargo promotion stage for cross-cluster deployment.

| Attribute | Type | Description | Constraints |
|-----------|------|-------------|-------------|
| name | string | Stage name | `<app>-<environment>` |
| namespace | string | Kargo namespace | `kargo-pipelines` |
| warehouseName | string | Source warehouse | References Warehouse |
| upstreamStages | array | Predecessor stages | Stage names |
| requiredSoakTime | duration | Wait before promotion | `24h`, `48h`, etc. |
| argocdConfig.appName | string | Target Application | ArgoCD Application name |

**Relationships**:
- References one `ArgoCD Application`
- May reference upstream `Kargo Stage`s

## Validation Rules

### ClusterSecret

1. `labels` MUST contain `argocd.argoproj.io/secret-type: cluster`
2. `server` MUST be valid HTTPS URL
3. `bearerToken` MUST be non-empty
4. `caData` MUST be valid Base64-encoded certificate

### ApplicationConfig

1. `name` MUST be unique within `applications.ts`
2. `targetCluster` if specified MUST match registered `SpokeCluster.name` or be `hub`
3. `clusterType` MUST be compatible with current `CLUSTER_TYPE` environment
4. `chart.type` MUST be registered in `IdpBuilderChartFactory`

### SpokeCluster

1. `name` MUST be unique across all registered clusters
2. `server` MUST be reachable from hub cluster via Tailscale
3. ServiceAccount on spoke MUST have cluster-admin role

## Data Flow

### Spoke Registration Flow

```
1. Operator runs bootstrap-spoke.sh on spoke cluster
   ↓
2. ServiceAccount created: argocd-remote-manager
   ↓
3. Token and CA exported to Azure Key Vault
   ↓
4. ExternalSecret syncs credentials to hub cluster
   ↓
5. ClusterSecret created in argocd namespace
   ↓
6. ArgoCD discovers new cluster
   ↓
7. Spoke appears in ArgoCD cluster list as "Connected"
```

### Application Deployment Flow

```
1. Developer adds ApplicationConfig with targetCluster: <spoke>
   ↓
2. CDK8s synthesizes ArgoCD Application with destination.name: <spoke>
   ↓
3. Manifests committed to Git
   ↓
4. ArgoCD on hub syncs Application
   ↓
5. ArgoCD deploys resources to spoke cluster via ClusterSecret credentials
   ↓
6. Workloads running on spoke cluster
```

### Kargo Promotion Flow

```
1. New image detected by Warehouse
   ↓
2. Freight created
   ↓
3. Stage (dev) auto-promotes → ArgoCD Application updated
   ↓
4. ArgoCD syncs to dev spoke cluster
   ↓
5. Soak time elapses (24h)
   ↓
6. Stage (staging) manual approval → ArgoCD Application updated
   ↓
7. ArgoCD syncs to staging spoke cluster
```

## Storage Locations

| Data | Storage | Encryption |
|------|---------|------------|
| Cluster secrets (runtime) | Hub etcd | Kubernetes encryption at rest |
| Cluster credentials | Azure Key Vault | AES-256 |
| Application configs | Git (applications.ts) | None (no secrets) |
| Rendered manifests | Git (dist/) | None (no secrets) |
| Hub machine secrets | talos-cluster/secrets/ | git-crypt |
