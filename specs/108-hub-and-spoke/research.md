# Research: Hub-and-Spoke ArgoCD Architecture

**Feature**: 108-hub-and-spoke
**Date**: 2025-12-17

## Research Topics

1. ArgoCD Cluster Secret Format & Multi-Cluster Patterns
2. Talos Single-Node Cluster Configuration
3. Kargo Cross-Cluster Promotion Patterns
4. Tailscale Service Mesh Connectivity
5. CDK8s targetCluster Implementation Pattern

---

## 1. ArgoCD Cluster Secret Format

### Decision
Use ArgoCD cluster secrets with label `argocd.argoproj.io/secret-type: cluster` to register spoke clusters.

### Rationale
ArgoCD's built-in cluster registration mechanism uses Kubernetes Secrets with a specific format. This is the standard, well-documented approach that integrates seamlessly with ArgoCD's reconciliation loop.

### Format Specification

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-<spoke-name>
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    cluster-host: <spoke-name>
    cluster-type: development|production
type: Opaque
stringData:
  name: <spoke-name>
  server: https://k8s-api-<spoke-name>.<tailnet>.ts.net
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64-encoded-CA>"
      },
      "bearerToken": "<service-account-token>"
    }
```

### Key Fields

| Field | Purpose | Source |
|-------|---------|--------|
| `name` | Human-readable cluster name | Static configuration |
| `server` | Kubernetes API URL | Tailscale service URL |
| `config.tlsClientConfig.caData` | CA certificate for TLS | Exported from spoke cluster |
| `config.bearerToken` | ServiceAccount token | Generated on spoke cluster |

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| ArgoCD CLI `argocd cluster add` | Imperative, not GitOps-friendly |
| Cluster Generator with Git | Adds complexity; cluster secrets are simpler |
| In-cluster destination only | Doesn't support hub-and-spoke model |

---

## 2. Talos Single-Node Cluster Configuration

### Decision
Deploy a single-node Talos cluster with `allowSchedulingOnControlPlanes: true` for the hub.

### Rationale
A single-node hub minimizes cost (~€12/mo for CX32) while providing sufficient capacity for management workloads. Talos supports running workloads on control plane nodes, making this viable for non-HA scenarios.

### Configuration Pattern

```yaml
# patches/controlplane/hub.yaml
machine:
  type: controlplane
  install:
    disk: /dev/sda
    wipe: true
  network:
    hostname: hub-cp-1
  kubelet:
    nodeIP:
      validSubnets:
        - 10.1.1.0/24

cluster:
  clusterName: hub-cluster
  allowSchedulingOnControlPlanes: true
  controlPlane:
    endpoint: https://10.1.1.1:6443
  network:
    cni:
      name: none  # Cilium deployed separately
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
  proxy:
    disabled: true  # Cilium kube-proxy replacement
```

### Resource Requirements

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| ArgoCD Server (2) | 200m | 256Mi | 1000m | 1Gi |
| ArgoCD Controller | 100m | 512Mi | 1000m | 2Gi |
| ArgoCD Repo Server (2) | 200m | 256Mi | 1000m | 1Gi |
| Kargo Controller | 100m | 256Mi | 500m | 512Mi |
| ESO Controller | 100m | 128Mi | 500m | 256Mi |
| Tailscale Operator | 100m | 128Mi | 500m | 256Mi |
| **Total** | **~1000m** | **~1.8Gi** | **~5500m** | **~6Gi** |

**Recommendation**: CX32 (4 vCPU, 8GB RAM) provides comfortable headroom.

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| 3-node HA hub | ~€45/mo exceeds cost constraint; single-node sufficient for management-only |
| KIND cluster as hub | Not suitable for production; no persistence |
| Managed K8s (AKS/EKS) | Higher cost (~€70/mo); adds external dependency |

---

## 3. Kargo Cross-Cluster Promotion

### Decision
Kargo on hub cluster orchestrates promotions via ArgoCD Applications that target spoke clusters.

### Rationale
Kargo's promotion model works through ArgoCD - it updates Application sources and triggers syncs. Since ArgoCD on the hub already manages spoke clusters, Kargo promotions naturally work across cluster boundaries.

### Cross-Cluster Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           HUB CLUSTER                                    │
│                                                                          │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐            │
│  │   Warehouse  │────▶│    Stage     │────▶│    Stage     │            │
│  │ backstage-   │     │ backstage-   │     │ backstage-   │            │
│  │    ghcr      │     │    dev       │     │   staging    │            │
│  └──────────────┘     └──────┬───────┘     └──────┬───────┘            │
│                              │                     │                    │
│                              │ Updates             │ Updates            │
│                              ▼                     ▼                    │
│                       ┌──────────────┐     ┌──────────────┐            │
│                       │   ArgoCD     │     │   ArgoCD     │            │
│                       │ Application  │     │ Application  │            │
│                       │ backstage-   │     │ backstage-   │            │
│                       │    dev       │     │   staging    │            │
│                       └──────┬───────┘     └──────┬───────┘            │
│                              │                     │                    │
└──────────────────────────────┼─────────────────────┼────────────────────┘
                               │ Syncs to            │ Syncs to
                               ▼                     ▼
                        ┌──────────────┐     ┌──────────────┐
                        │   THINKPAD   │     │    TALOS     │
                        │   (Spoke)    │     │   (Spoke)    │
                        │              │     │              │
                        │ backstage    │     │ backstage    │
                        │   pods       │     │   pods       │
                        └──────────────┘     └──────────────┘
```

### Stage Configuration for Cross-Cluster

```typescript
createStage(this, 'backstage-staging-stage', {
  name: 'backstage-staging',
  namespace: 'kargo-pipelines',
  warehouseName: 'backstage-ghcr',
  directFromWarehouse: false,
  upstreamStages: ['backstage-dev'],
  requiredSoakTime: '24h',
  argocdConfig: {
    appName: 'backstage-staging',      // ArgoCD Application name
    namespace: 'argocd',                // ArgoCD namespace on HUB
    repoUrl: 'https://github.com/PittampalliOrg/stacks.git',
    imageRef: 'ghcr.io/pittampalliorg/backstage-cnoe',
  }
});
```

The ArgoCD Application `backstage-staging` has `destination.name: talos` which routes to the Talos spoke cluster.

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Kargo per spoke cluster | Management overhead; inconsistent promotion across clusters |
| Manual promotion scripts | Not GitOps; error-prone; no audit trail |
| ArgoCD Image Updater | Less flexible than Kargo; no soak times or approval gates |

---

## 4. Tailscale Service Mesh Connectivity

### Decision
Use Tailscale k8s-api service URLs for spoke cluster access from hub ArgoCD.

### Rationale
Tailscale provides secure, authenticated mesh networking without VPNs or firewall rules. The existing Tailscale operator pattern (Feature 103) exposes Kubernetes APIs as stable service URLs.

### Connectivity Matrix

| Source | Destination | URL Pattern | Auth Method |
|--------|-------------|-------------|-------------|
| Hub ArgoCD | Hetzner API | `https://k8s-api-hetzner.tail286401.ts.net` | Bearer token |
| Hub ArgoCD | Thinkpad API | `https://k8s-api-thinkpad.tail286401.ts.net` | Bearer token |
| Hub ArgoCD | Ryzen API | `https://k8s-api-ryzen.tail286401.ts.net` | Bearer token |
| Hub ArgoCD | Talos API | `https://k8s-api-talos.tail286401.ts.net` | Bearer token |
| Operator | Hub ArgoCD | `https://argocd-hub.tail286401.ts.net` | SSO/Password |

### Network Isolation

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      TAILSCALE MESH (100.x.x.x/8)                        │
│                                                                          │
│    Hub: 100.64.0.10                     Hetzner: 100.64.0.20            │
│    ┌──────────────┐                     ┌──────────────┐                │
│    │ ArgoCD       │◄────────────────────│ k8s-api      │                │
│    │ (outbound)   │     TLS + Bearer    │ (inbound)    │                │
│    └──────────────┘                     └──────────────┘                │
│                                                                          │
│    Thinkpad: 100.64.0.30               Ryzen: 100.64.0.40               │
│    ┌──────────────┐                     ┌──────────────┐                │
│    │ k8s-api      │                     │ k8s-api      │                │
│    │ (inbound)    │                     │ (inbound)    │                │
│    └──────────────┘                     └──────────────┘                │
└─────────────────────────────────────────────────────────────────────────┘
```

### Spoke Prerequisite

Each spoke must have:
1. Tailscale operator installed
2. `k8s-api-<name>` service exposed via Tailscale serve
3. ServiceAccount `argocd-remote-manager` with cluster-admin role
4. Long-lived token stored in Azure Key Vault

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Public K8s API endpoints | Security risk; requires firewall rules |
| VPN tunnels | Complex setup; management overhead |
| Direct IP connectivity | Dynamic IPs; NAT traversal issues |

---

## 5. CDK8s targetCluster Implementation

### Decision
Add `targetCluster` field to `ApplicationConfig` type and modify `ArgoApplicationsChartV2` to generate correct `destination.name`.

### Rationale
Extending the existing CDK8s pattern maintains consistency with the codebase while adding multi-cluster targeting capability.

### Type Extension

```typescript
// cdk8s/lib/idpbuilder-types.ts
export interface ApplicationConfig {
  name: string;
  namespace: string;
  disabled?: boolean;
  clusterType?: 'kind' | 'talos' | 'both';

  /**
   * Target cluster for deployment (hub-and-spoke model)
   * - 'hub': Deploy to hub cluster only (in-cluster)
   * - string: Deploy to specific spoke by name (e.g., 'hetzner', 'thinkpad')
   * - undefined: Use existing logic (vcluster for dev/staging, in-cluster otherwise)
   */
  targetCluster?: 'hub' | string;

  chart: ChartConfig;
  argocd?: ArgoCdConfig;
}
```

### Destination Logic

```typescript
// cdk8s/charts/platform/argo-applications-chart-v2.ts
private buildDestination(props: ArgoApplicationsChartV2Props): ApplicationSpecDestination {
  const targetCluster = props.argoCdConfig?.targetCluster;

  // Explicit targetCluster takes precedence
  if (targetCluster) {
    if (targetCluster === 'hub') {
      return {
        server: 'https://kubernetes.default.svc',
        namespace: props.applicationNamespace,
      };
    }
    // Spoke cluster by name
    return {
      name: targetCluster,
      namespace: props.applicationNamespace,
    };
  }

  // Fall back to existing vcluster logic
  const envLabel = props.argoCdConfig?.labels?.['app.kubernetes.io/environment'];
  if (envLabel === 'dev' || envLabel === 'staging') {
    return {
      name: `${envLabel}-vcluster`,
      namespace: props.applicationNamespace,
    };
  }

  // Default: in-cluster
  return {
    server: 'https://kubernetes.default.svc',
    namespace: props.applicationNamespace,
  };
}
```

### Example Usage in applications.ts

```typescript
// Hub-only management apps
{
  name: 'kargo',
  namespace: 'kargo',
  targetCluster: 'hub',
  chart: { type: 'KargoHelmChart' },
  argocd: { syncWave: '70' }
}

// Spoke-targeted app
{
  name: 'backstage-prod',
  namespace: 'backstage',
  targetCluster: 'talos',
  chart: { type: 'BackstageChart', props: { environment: 'production' } },
  argocd: { syncWave: '100' }
}

// Cluster registration (on hub)
{
  name: 'argocd-cluster-thinkpad',
  namespace: 'argocd',
  targetCluster: 'hub',
  chart: { type: 'ArgocdClusterSecretChart', props: { clusterName: 'thinkpad' } },
  argocd: { syncWave: '-80' }
}
```

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Separate ApplicationConfig per cluster | Violates Principle IV (unified config) |
| ApplicationSets only | Less explicit control; harder to understand per-app targeting |
| Environment variable switching | Not declarative; harder to audit |

---

## Summary

| Topic | Decision | Key Benefit |
|-------|----------|-------------|
| Cluster Secrets | ArgoCD cluster secrets with ESO | GitOps-native, auto-refresh credentials |
| Hub Cluster | Single-node Talos CX32 | Cost-effective (~€12/mo), sufficient for management |
| Cross-Cluster Kargo | Hub Kargo → spoke ArgoCD Applications | Unified promotion pipeline |
| Connectivity | Tailscale service URLs | Secure mesh, no public APIs |
| CDK8s Pattern | `targetCluster` field in ApplicationConfig | Explicit, type-safe cluster targeting |

All research items are resolved. Proceed to Phase 1 (Design).
