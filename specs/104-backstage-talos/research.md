# Research: Backstage CDK8s Chart Migration

**Date**: 2025-12-09
**Feature**: 104-backstage-talos

## Research Questions

1. What existing chart patterns should BackstageChart follow?
2. How do ExternalSecret helpers work in this codebase?
3. What sync-wave conventions are established?
4. How do ClusterSecretStore dependencies work for ArgoCD integration?
5. What is the correct approach for multi-ClusterSecretStore ExternalSecrets?

---

## 1. Existing Chart Patterns

### Decision: Follow HeadlampChart pattern for workloads

**Rationale**: HeadlampChart (`cdk8s/charts/platform/headlamp-chart.ts`) is the most similar existing chart:
- Creates Namespace, ServiceAccount, ClusterRoleBinding, Deployment, Service, Ingress
- Uses environment variables for configuration (`process.env.INGRESS_HOST`)
- Follows established naming conventions

**Reference Pattern** (from HeadlampChart):
```typescript
export interface HeadlampChartProps extends ChartProps {
  enablePluginManager?: boolean;
  plugins?: Array<{ name: string; source: string; version: string; }>;
}

export class HeadlampChart extends Chart {
  constructor(scope: Construct, id: string, props: HeadlampChartProps = {}) {
    super(scope, id, props);
    const namespace = 'headlamp';
    const appName = 'headlamp';
    // ... create resources
  }
}
```

**Alternatives Considered**:
- KagentChart: More complex with CRD dependencies
- PostgresChart: Too simple, only StatefulSet
- HeadlampChart: ✅ Best match for scope and complexity

---

## 2. ExternalSecret Helper Patterns

### Decision: Use eso-helpers.ts for dockerconfigjson, raw ESO API for complex secrets

**Rationale**: The codebase has helper functions for common patterns, but Backstage needs both:
- `createDockerConfigJsonExternalSecret`: Perfect for ghcr.io pull secret
- Raw ESO API: Required for backstage-oidc (uses Password generators and multi-source data)

**Helper Available** (from `lib/eso-helpers.ts`):
```typescript
// For Docker registry secrets
createDockerConfigJsonExternalSecret(scope, id, {
  name: 'ghcr-dockercfg',
  namespace: 'backstage',
  registry: 'ghcr.io',
  usernameTemplate: 'pittampalliorg',
  passwordKey: 'GITHUB-PAT',
});

// For environment variable secrets (limited - doesn't support generators)
createEnvExternalSecret(scope, id, {
  name: 'secret-name',
  namespace: 'backstage',
  mappings: [...],
});
```

**Raw ESO API Needed For** (backstage-oidc ExternalSecret):
- Password generators (`generators.external-secrets.io/v1alpha1 Password`)
- `dataFrom` with generatorRef for rewriting
- Multi-ClusterSecretStore references (keycloak + generators)

**Alternatives Considered**:
- Extend eso-helpers: Would add complexity for a single use case
- Use raw ESO API everywhere: Would duplicate common patterns
- Mixed approach: ✅ Best balance of reuse and flexibility

---

## 3. Sync-Wave Conventions

### Decision: Follow established sync-wave ordering

**Rationale**: Existing applications.ts establishes clear patterns:

| Sync-Wave | Purpose | Examples |
|-----------|---------|----------|
| -200 to -150 | CRDs, Critical Infrastructure | dapr-crds, local-path-provisioner |
| -100 to -85 | Operators, Core Secrets | external-secrets-operator, bootstrap-secrets |
| -80 to -50 | Infrastructure Components | dagger-infra, tailscale-secrets |
| -10 to 0 | Application Secrets | ExternalSecrets for apps |
| 10 to 30 | Databases, Stateful | PostgreSQL, application deployments |
| 40+ | Applications, Services | headlamp, kargo-pipelines |

**Backstage Sync-Waves**:
- `backstage-secrets` Application: `-10` (secrets before workloads)
- `ghcr-dockercfg-external`: `-10` (image pull before deployment)
- `postgresql` StatefulSet: `10` (database before application)
- `backstage` Deployment: `20` (application after database)

**Alternatives Considered**:
- All at sync-wave 0: Would cause race conditions
- Higher sync-waves (50+): Would delay Backstage unnecessarily
- Match ref-implementation exactly: ✅ Ensures behavioral equivalence

---

## 4. ClusterSecretStore Dependencies

### Decision: Create ArgoCD ClusterSecretStore in BackstageSecretsChart

**Rationale**: The ref-implementation creates an ArgoCD ClusterSecretStore using Kubernetes provider pattern:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: argocd
spec:
  provider:
    kubernetes:
      remoteNamespace: argocd
      server:
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          namespace: argocd
          key: ca.crt
      auth:
        serviceAccount:
          name: eso-store
          namespace: argocd
```

This pattern requires:
1. ServiceAccount (`eso-store`) in argocd namespace
2. Role with secrets read permission
3. RoleBinding linking ServiceAccount to Role
4. ClusterSecretStore using Kubernetes provider

**Why in BackstageSecretsChart**:
- Only Backstage needs argocd-credentials ExternalSecret
- Keeps ArgoCD secret store isolated from bootstrap-secrets
- Follows separation of concerns

**Alternatives Considered**:
- Add to bootstrap-secrets: Would bloat generic secrets chart
- Create separate argocd-secrets chart: Over-engineering for single use
- Include in BackstageSecretsChart: ✅ Keeps Backstage self-contained

---

## 5. Multi-Source ExternalSecrets

### Decision: backstage-oidc uses keycloak ClusterSecretStore + Password generators

**Rationale**: The backstage-oidc ExternalSecret has complex requirements:

**Data Sources**:
1. `keycloak` ClusterSecretStore → ARGOCD_SESSION_TOKEN, BACKSTAGE_CLIENT_SECRET
2. Password generator `backstage` → POSTGRES_PASSWORD
3. Password generator `backstage-session` → SESSION_SECRET

**Implementation Pattern**:
```typescript
// Password generators (ESO CRD)
new Password(this, 'backstage-password-generator', {
  metadata: { name: 'backstage', namespace: 'backstage' },
  spec: { length: 36, digits: 5, symbols: 5, symbolCharacters: '/-+', noUpper: false, allowRepeat: true }
});

// ExternalSecret with mixed sources
new ExternalSecret(this, 'backstage-oidc', {
  metadata: { name: 'backstage-oidc', namespace: 'backstage' },
  spec: {
    secretStoreRef: { name: 'keycloak', kind: 'ClusterSecretStore' },
    target: {
      name: 'backstage-env-vars',
      template: {
        engineVersion: 'v2',
        data: {
          BACKSTAGE_FRONTEND_URL: 'https://cnoe.localtest.me:8443/backstage',
          POSTGRES_PASSWORD: '{{.POSTGRES_PASSWORD}}',
          // ... other fields
        }
      }
    },
    data: [
      { secretKey: 'ARGOCD_SESSION_TOKEN', remoteRef: { key: 'keycloak-clients', property: 'ARGOCD_SESSION_TOKEN' }},
      // ...
    ],
    dataFrom: [
      { sourceRef: { generatorRef: { apiVersion: 'generators.external-secrets.io/v1alpha1', kind: 'Password', name: 'backstage' }},
        rewrite: [{ transform: { template: 'POSTGRES_PASSWORD' }}]},
      // ...
    ]
  }
});
```

**Alternatives Considered**:
- Separate ExternalSecrets per source: Would complicate secret management
- Static passwords: Security risk
- Combined approach: ✅ Matches ref-implementation pattern

---

## Summary: No NEEDS CLARIFICATION Items

All research questions resolved with clear decisions and rationales. Ready for Phase 1 design artifacts.

| Question | Resolution |
|----------|------------|
| Chart patterns | Follow HeadlampChart |
| ESO helpers | Use helpers where applicable, raw API for complex cases |
| Sync-waves | -10 for secrets, 10 for PostgreSQL, 20 for Backstage |
| ClusterSecretStore | Create in BackstageSecretsChart |
| Multi-source secrets | Use dataFrom with generators + data with remoteRef |
