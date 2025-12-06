# Research: GitOps Bootstrap for Talos Linux Cluster

**Branch**: `102-bootstrap-talos-argocd` | **Date**: 2025-12-06
**Purpose**: Resolve technical unknowns for ArgoCD bootstrap, Azure Workload Identity, and Tailscale integration

## Table of Contents

1. [ArgoCD Bootstrap Patterns](#1-argocd-bootstrap-patterns)
2. [Azure Workload Identity for External Secrets](#2-azure-workload-identity-for-external-secrets)
3. [Tailscale Services and Operator](#3-tailscale-services-and-operator)
4. [CDK8s Integration Approach](#4-cdk8s-integration-approach)

---

## 1. ArgoCD Bootstrap Patterns

### Decision: Helm-First Bootstrap with App-of-Apps Self-Management

**Selected Approach**: Use Helm for initial ArgoCD installation, then transition to GitOps self-management via App-of-Apps pattern.

**Rationale**:
- Breaks the "chicken and egg" problem (ArgoCD cannot install itself if it doesn't exist)
- Industry standard approach used by Codefresh, EKS, and other production deployments
- After ArgoCD is running, its configuration can be managed via self-referential Application in Git
- Bootstrap script remains idempotent (Helm detects existing release)

**Alternatives Considered**:

| Alternative | Pros | Cons | Verdict |
|-------------|------|------|---------|
| Pure Manifest-Based | Direct kubectl, no Helm dependency | Difficult to manage upgrades; no versioning | REJECTED |
| ArgoCD Autopilot | Opinionated structure, simplified CLI | Less flexible, conflicts with stacks/main patterns | DEFERRED |
| ApplicationSet Bootstrap | More scalable than App-of-Apps | Newer API, less mature for bootstrap | OPTIONAL: Evolve later |

### Implementation Pattern: Two-Phase Bootstrap

**Phase 1: Helm Bootstrap (Manual, Once)**

```bash
# scripts/01-install-argocd.sh
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values argocd-values.yaml \
  --wait --timeout 5m
```

**Phase 2: GitOps Takeover (Automated)**

```bash
# scripts/03-apply-base-apps.sh
kubectl apply -f dist/argocd-bootstrap/manifests/application_argocd-root.yaml
# Creates: Parent Application managing all platform services
```

### App-of-Apps Hierarchy

Use exactly 3 levels to avoid complexity:

1. **Level 1 (Root)**: Single parent Application (`argocd-bootstrap`)
2. **Level 2 (Platform)**: Platform components (ArgoCD self-config, ESO, Tailscale)
3. **Level 3 (Workloads)**: User applications

### Sync Wave Ordering

```typescript
const syncWaves = {
  '-110': ['cilium-cni'],               // Foundation: networking (optional, often pre-installed)
  '-100': ['external-secrets-operator'],// Secrets must be ready first
  '-94':  ['workload-identity-patch'],  // ESO ServiceAccount annotations
  '-92':  ['cluster-secret-store'],     // Azure Key Vault access
  '-85':  ['tailscale-secrets'],        // Auth keys for Tailscale
  '-80':  ['tailscale-operator'],       // Remote access
  '-60':  ['k8s-api-tailscale-serve'],  // API server proxy
  '0':    ['argocd-self-managed'],      // Platform bootstrap
  '10':   ['user-applications']         // Workloads
};
```

### Talos-Specific Considerations

| Concern | Impact | Mitigation |
|---------|--------|------------|
| No SSH Access | Can't manually debug on nodes | Use `talosctl debug`, logs via kubectl |
| Read-Only Root FS | Can't install system packages | All functionality via containers |
| Immutable Machine State | Changes require restart | Embrace declarative, re-create VMs |

**Bootstrap Sequencing**:

```bash
# Step 1: Machine bootstrap (talos-cluster repo) - prerequisite
talosctl bootstrap --endpoints=<control-plane-ip>

# Step 2: Wait for CNI readiness
kubectl wait --for=condition=Ready pod -l k8s-app=cilium -n kube-system --timeout=5m

# Step 3: Kubernetes bootstrap (this feature)
./scripts/bootstrap-cluster.sh
```

---

## 2. Azure Workload Identity for External Secrets

### Decision: OIDC Workload Identity Federation (No Static Credentials)

**Selected Approach**: Use Azure Workload Identity with OIDC federation for authenticating External Secrets Operator to Azure Key Vault.

**Rationale**:
- Eliminates static service principal credentials stored in cluster
- Short-lived OIDC tokens (1 hour expiration) reduce blast radius if compromised
- Leverages Azure AD federation model with audit trails and conditional access
- Supported by External Secrets Operator v0.9+ via `authType: WorkloadIdentity`
- Recommended by both Azure and ESO documentation

**Alternatives Considered**:

| Alternative | Pros | Cons | Verdict |
|-------------|------|------|---------|
| ServiceAccount Key | Simple setup | Static credentials, poor rotation | REJECTED |
| Shared Key | Familiar pattern | Uses storage account keys, poor security | REJECTED |
| Pod Identity | Previous Azure standard | Deprecated, complex webhook | REJECTED |

### OIDC Federation Architecture

```
Kubernetes Cluster (OIDC Provider)
├── /.well-known/openid-configuration
└── /openid/v1/jwks
         │
         │ (JWKS synced to)
         ▼
Azure Storage Account (Static Website)
├── https://{storage-account}.z13.web.core.windows.net/
├── /.well-known/openid-configuration
└── /openid/v1/jwks
         │
         │ (Azure AD trusts)
         ▼
Azure AD (Validates tokens)
└── Federated credential references issuer URL
```

### JWKS Sync Script

```bash
# scripts/02-sync-jwks.sh

# Extract JWKS from Kubernetes
kubectl get --raw /openid/v1/jwks | jq > jwks.json

# Create openid-configuration
cat > openid-config.json <<EOF
{
  "issuer": "https://${STORAGE_ACCOUNT}.z13.web.core.windows.net/",
  "jwks_uri": "https://${STORAGE_ACCOUNT}.z13.web.core.windows.net/openid/v1/jwks",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
EOF

# Upload to Azure Storage static website
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name '$web' \
  --name .well-known/openid-configuration \
  --file openid-config.json \
  --auth-mode login \
  --overwrite

az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name '$web' \
  --name openid/v1/jwks \
  --file jwks.json \
  --auth-mode login \
  --overwrite
```

**Critical Note**: When cluster is rebuilt, new OIDC keys are generated. JWKS must be re-synced before workload identity can authenticate.

### ClusterSecretStore Configuration

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault-store
spec:
  provider:
    azurekv:
      vaultUrl: "https://{AZURE_KEYVAULT_NAME}.vault.azure.net"
      authType: WorkloadIdentity
      serviceAccountRef:
        name: external-secrets
        namespace: external-secrets
```

### ServiceAccount Annotations

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: external-secrets
  annotations:
    azure.workload.identity/client-id: "{client-id}"
    azure.workload.identity/tenant-id: "{tenant-id}"
  labels:
    azure.workload.identity/use: "true"
```

The Azure Workload Identity webhook automatically injects:
- Environment variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE`
- Projected volume: `/var/run/secrets/azure/tokens/azure-identity-token`

### Runtime Authentication Flow

```
1. ExternalSecret requests secret from ClusterSecretStore
2. ESO operator pod reads OIDC JWT from federated token file
3. ESO calls Azure AD token endpoint with JWT
4. Azure AD validates JWT against JWKS in Azure Storage
5. Azure AD checks federated credential (subject matches ServiceAccount)
6. Azure AD returns short-lived access token
7. ESO uses token to fetch secret from Azure Key Vault
8. ESO creates/updates Kubernetes Secret
```

### Edge Cases

| Edge Case | Detection | Mitigation |
|-----------|-----------|------------|
| JWKS rotation after cluster rebuild | "token signing key not found in JWKS" | Re-run sync-jwks.sh |
| Token expiration during operations | Auto-refreshed | ESO handles automatically |
| ServiceAccount annotation drift | ArgoCD sync | Use ServerSideApply option |
| Federated credential mismatch | "Principal not found" | Subject must match exactly |

---

## 3. Tailscale Services and Operator

### Decision: Tailscale Services for Stable URLs

**Selected Approach**: Use Tailscale Services (`--service=svc:<name>`) for stable, persistent service URLs that survive cluster recreation.

**Rationale**:
- Device hostnames change on cluster recreation (e.g., `argocd-ui-serve-1` → `argocd-ui-serve-2`)
- Services provide stable URLs (e.g., `svc-argocd.<tailnet>.ts.net`)
- ACL auto-approval enables automatic service registration with tagged auth keys
- No manual device cleanup needed after cluster recreation

**Alternatives Considered**:

| Alternative | Pros | Cons | Verdict |
|-------------|------|------|---------|
| Accept hostname suffixes | No migration effort | Poor UX, breaks scripts | REJECTED |
| Manual device cleanup | Canonical hostnames | Manual, error-prone | NOT RECOMMENDED |
| Preserve state secrets | Device identity preserved | Complex, not suitable for dev | DEFERRED |

### Service URL Scheme

| Service | URL | Purpose |
|---------|-----|---------|
| ArgoCD | `svc-argocd.<tailnet>.ts.net` | GitOps Dashboard |
| Langfuse | `svc-langfuse.<tailnet>.ts.net` | LLM Observability |
| K8s API | `svc-k8s-api.<tailnet>.ts.net` | kubectl access |

### APISERVER_PROXY Mode

**Selected Approach**: Enable APISERVER_PROXY mode in Tailscale Operator for in-process API proxy with automatic HTTPS.

**Architecture**:

```
kubectl (remote)
    ↓
Tailscale Network (encrypted)
    ↓
Tailscale Operator Pod (APISERVER_PROXY mode)
    ↓
In-process proxy → kubectl-proxy sidecar (port 8001)
    ↓
Kubernetes API Server (cluster IP)
```

**Benefits**:
- In-process proxy, no external ProxyGroup needed
- Automatic Let's Encrypt certificates
- Direct connection via Tailscale network
- Single point of access for all API traffic

### Authentication: OAuth vs Auth Keys

| Component | Credential Type | Rationale |
|-----------|-----------------|-----------|
| Tailscale Operator | OAuth | Granular permissions, revocation, audit logging |
| Service Pods | Tagged Auth Key | Ephemeral, reusable, enables ACL auto-approval |

**OAuth for Operator**:
```typescript
// From Azure Key Vault via ExternalSecret
data: [
  { secretKey: 'oauth_client_id', remoteRef: { key: 'TAILSCALE-OAUTH-CLIENT-ID' } },
  { secretKey: 'oauth_client_secret', remoteRef: { key: 'TAILSCALE-OAUTH-CLIENT-SECRET' } },
]
```

**Auth Key for Services**:
```typescript
// Reusable, ephemeral, tagged (tag:k8s-services)
remoteRef: { key: 'TAILSCALE-AUTH-KEY' }
```

### External Secrets Integration

**Sync Wave Strategy**:

| Component | Wave | Purpose |
|-----------|------|---------|
| ESO Workload Identity | `-94` | Configure ESO for Azure auth |
| Bootstrap Secrets | `-92` | Core infrastructure secrets |
| Tailscale Operator Secrets | `-85` | OAuth credentials for operator |
| Tailscale Secrets | `-70` | Auth keys for service pods |
| Tailscale Operator | `-75` | Operator deployment (needs OAuth) |
| K8s API Tailscale Serve | `-60` | Service pod (needs auth key) |

### ACL Configuration Requirements

```json
{
  "tagOwners": {
    "tag:k8s-services": ["autogroup:admin"]
  },
  "autoApprovers": {
    "services": {
      "svc:argocd": ["tag:k8s-services"],
      "svc:langfuse": ["tag:k8s-services"],
      "svc:k8s-api": ["tag:k8s-services"]
    }
  }
}
```

---

## 4. CDK8s Integration Approach

### Decision: Talos-Specific Entry Point with Shared Libraries

**Selected Approach**: Create `main-talos.ts` entry point with Talos-specific configuration, reusing existing chart libraries from stacks/main.

**Rationale**:
- Keeps Talos bootstrap separate from Kind cluster setup
- Reuses proven patterns from stacks/main (eso-helpers, tailscale-serve-helpers)
- Follows existing CDK8s architecture (Chart Factory pattern)
- Enables independent testing of Talos vs Kind configurations

### Synthesis Strategy

**Pre-Synthesized Manifests in Git + File-per-Resource**:

1. Run `cdk8s synthesis` locally (CI/CD or developer machine)
2. Export each resource as separate YAML file
3. Commit generated manifests to `/cdk8s/dist/<app>/manifests/`
4. ArgoCD syncs pre-synthesized manifests from Git

**Benefits**:
- Git is source of truth (GitOps principle)
- No runtime synthesis (no Node.js in cluster)
- Easier auditing (reviewers see exact manifests)
- File-per-resource enables granular ArgoCD sync

### Helm Integration via CDK8s

Use `cdk8s Helm` construct for core components:

```typescript
// cdk8s/charts/platform/argocd-helm-chart.ts
new Helm(this, 'argocd', {
  chart: 'argo-cd',
  repo: 'https://argoproj.github.io/argo-helm',
  version: '7.3.0',  // Pin to specific version
  namespace: 'argocd',
  releaseName: 'argocd',
  values: {
    replicaCount: 3,
    server: {
      autoscaling: { enabled: true, minReplicas: 2, maxReplicas: 5 }
    },
  }
});
```

**Components via Helm**:

| Component | Chart | Rationale |
|-----------|-------|-----------|
| ArgoCD | `argo/argo-cd` | Complex HA config, frequent upgrades |
| External Secrets | `external-secrets/external-secrets` | CRD-heavy, webhook management |
| Tailscale Operator | `tailscale/tailscale-operator` | CRD management, state handling |

### Configuration Structure

```typescript
// cdk8s/config/talos-applications.ts
export const talosApplications: ApplicationConfig[] = [
  {
    name: 'external-secrets-operator',
    namespace: 'external-secrets',
    chart: { type: 'EsoHelmChart' },
    argocd: { syncWave: '-100' }
  },
  {
    name: 'workload-identity-patch',
    namespace: 'external-secrets',
    chart: {
      type: 'ExternalSecretsWorkloadIdentityChart',
      props: { clientId: process.env.AZURE_CLIENT_ID }
    },
    argocd: { syncWave: '-94' }
  },
  // ... more applications
];
```

---

## Summary: Key Decisions

| Area | Decision | Key Benefit |
|------|----------|-------------|
| ArgoCD Bootstrap | Helm-first + App-of-Apps | Breaks chicken-egg, enables GitOps takeover |
| Secret Management | Azure Workload Identity | No static credentials, short-lived tokens |
| Remote Access | Tailscale Services | Stable URLs survive cluster recreation |
| Manifest Generation | Pre-synthesized CDK8s | GitOps compliant, no runtime deps |
| Configuration | Talos-specific entry point | Isolated from Kind cluster config |

## Next Steps

1. Create bootstrap scripts (`scripts/01-install-argocd.sh`, `02-sync-jwks.sh`, `03-apply-base-apps.sh`)
2. Implement CDK8s charts (`argocd-helm-chart.ts`, `eso-helm-chart.ts`, `cluster-secret-store-chart.ts`)
3. Configure Talos applications in `config/talos-applications.ts`
4. Test against fresh Talos cluster from feature 100
5. Document in quickstart.md

## References

- [ArgoCD Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [External Secrets Operator](https://external-secrets.io/)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [Tailscale Services](https://tailscale.com/kb/1552/tailscale-services)
- [CDK8s Documentation](https://cdk8s.io/)
