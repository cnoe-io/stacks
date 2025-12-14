# Research: Kargo Progressive Delivery Pipelines Framework

**Branch**: `105-setup-kargo-pipelines` | **Date**: 2025-12-11

## Overview

This document consolidates research findings for implementing the parallel pipeline architecture with Inner Loop (Gitea) and Outer Loop (GitHub) pipelines.

---

## 1. Warehouse Configuration for OCI Registries

### Decision: Use `spec.subscriptions.image` for OCI registry monitoring

**Rationale**: Warehouses support image subscriptions with flexible tag selection strategies. The `image` subscription type is specifically designed for OCI registries.

**Alternatives Considered**:
- Git-based subscriptions (rejected: images are artifacts, not Git commits)
- Helm chart subscriptions (rejected: we're tracking container images, not Helm charts)

### Key Configuration Pattern

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: <warehouse-name>
  namespace: kargo-pipelines
spec:
  freightCreationPolicy: Automatic
  interval: 5m0s
  subscriptions:
    - image:
        repoURL: <registry>/<org>/<image>  # NO tag
        imageSelectionStrategy: SemVer     # or Lexical, Digest, NewestBuild
        constraint: ">=0.1.0"              # SemVer constraint
        allowTags: "^v?\\d+\\.\\d+\\.\\d+$"  # Regex whitelist
        ignoreTags: [latest, develop]      # Exact match blacklist
        discoveryLimit: 20
        insecureSkipTLSVerify: false       # true for Gitea self-signed
```

### Gitea OCI Registry Configuration

```yaml
# Inner Loop Warehouse
subscriptions:
  - image:
      repoURL: gitea.cnoe.localtest.me:8443/giteaadmin/backstage
      imageSelectionStrategy: Lexical      # Dev builds use timestamps/commits
      allowTags: "^dev-[a-f0-9]{7}$"       # dev-abc1234 format
      insecureSkipTLSVerify: true          # Self-signed cert
      discoveryLimit: 10
```

**Gotchas for Gitea**:
- Include port in URL (`:8443`)
- Set `insecureSkipTLSVerify: true` for self-signed certificates
- Use `Lexical` strategy for commit-based tags

### GHCR Configuration

```yaml
# Outer Loop Warehouse
subscriptions:
  - image:
      repoURL: ghcr.io/pittampalliorg/backstage
      imageSelectionStrategy: SemVer
      constraint: ">=1.0.0"
      allowTags: "^v\\d+\\.\\d+\\.\\d+$"   # v1.2.3 format only
      ignoreTags: [latest, main, develop]
      discoveryLimit: 20
```

**GHCR Notes**:
- Public images need no authentication
- Standard HTTPS works without TLS skip
- Webhooks must be configured via GitHub repository settings (not GHCR directly)

---

## 2. Stage and Promotion Configuration

### Decision: Use `requestedFreight.sources` for stage relationships

**Rationale**: Kargo's `requestedFreight` model supports both direct warehouse subscriptions and upstream stage relationships, enabling flexible pipeline topologies.

### Stage Spec Structure

```typescript
interface StageSpec {
  requestedFreight: [{
    origin: { kind: 'Warehouse', name: string },
    sources: {
      direct?: boolean,           // Direct from warehouse
      stages?: string[],          // From upstream stages
      availabilityStrategy?: 'All' | 'OneOf',
      requiredSoakTime?: string   // e.g., '24h'
    }
  }],
  promotionTemplate: {
    spec: {
      steps: [{
        uses: string,    // 'argocd-update', 'git-update', etc.
        config: any,     // Step-specific config
        as?: string,     // Step alias
        if?: string,     // Conditional execution
        retry?: { errorThreshold?: number, timeout?: string }
      }],
      vars?: [{ name: string, value: string }]
    }
  }
}
```

### Auto-Promotion Configuration

Auto-promotion is configured at the **ProjectConfig** level, not per-Stage:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: ProjectConfig
spec:
  promotionPolicies:
    - stageSelector:
        name: 'glob:*-local-dev'    # Inner loop stages
      autoPromotionEnabled: true
    - stageSelector:
        name: 'glob:*-dev'          # Outer loop dev stages
      autoPromotionEnabled: true
    - stageSelector:
        name: 'glob:*-staging'      # Staging stages
      autoPromotionEnabled: false   # Manual
    - stageSelector:
        name: 'glob:*-prod'         # Production stages
      autoPromotionEnabled: false   # Manual
```

---

## 3. ArgoCD Integration

### Decision: Use `argocd-update` promotion step with direct image path updates

**Rationale**: The `argocd-update` step directly modifies ArgoCD Application parameters, which is simpler than Git-based updates for image-only changes.

### argocd-update Step Configuration

```yaml
promotionTemplate:
  spec:
    steps:
      - uses: argocd-update
        config:
          apps:
            - name: backstage-local-dev     # ArgoCD Application name
              namespace: argocd
              sources:
                - repoURL: cnoe://backstage/manifests  # or Git URL
                  desiredCommitFromStep: ""            # Skip for image-only
                  images:
                    - image: gitea.cnoe.localtest.me:8443/giteaadmin/backstage
                      # Kargo automatically substitutes the correct tag from Freight
```

### ArgoCD Application Authorization

ArgoCD Applications must authorize Kargo to update them:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backstage-local-dev
  annotations:
    kargo.akuity.io/authorized-stage: kargo-pipelines:backstage-local-dev
```

**Format**: `<project-namespace>:<stage-name>`

### Critical Path Syntax Note

When using `yaml-update` or similar steps, paths use **sjson dot notation**, not JSONPath:
- **CORRECT**: `spec.template.spec.containers.0.image`
- **WRONG**: `spec.template.spec.containers[0].image`

---

## 4. Webhook Configuration

### Decision: Use ProjectConfig webhookReceivers with GitHub-compatible format for Gitea

**Rationale**: Gitea implements GitHub's webhook payload format, so the `github` webhook receiver type works for both.

### Webhook Receiver Configuration

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: ProjectConfig
spec:
  webhookReceivers:
    # Gitea (in-cluster, GitHub-compatible)
    - name: gitea-backstage
      github:
        secretRef:
          name: kargo-gitea-webhook-secret
    # GitHub (external)
    - name: github-backstage
      github:
        secretRef:
          name: kargo-github-webhook-secret
```

### Webhook Secret Format

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kargo-gitea-webhook-secret
  namespace: kargo-pipelines
stringData:
  secret: <32-character-random-string>  # Key MUST be 'secret'
```

### Webhook Endpoint Discovery

The webhook URL is dynamically generated and available in ProjectConfig status:

```bash
kubectl get projectconfigs kargo-pipelines \
  -n kargo-pipelines \
  -o jsonpath='{.status.webhookReceivers}'
```

### Gitea vs GitHub Webhook Differences

| Aspect | Gitea (Inner Loop) | GitHub (Outer Loop) |
|--------|-------------------|---------------------|
| Network | In-cluster | External |
| TLS Required | No (self-signed OK) | Yes (valid cert) |
| Endpoint | In-cluster service | Public URL (Tailscale/Ingress) |
| Events | Package push | Packages events |

---

## 5. Existing Codebase Patterns

### kargo-pipelines-project-chart.ts Analysis

**Location**: `cdk8s/charts/pipelines/kargo-pipelines-project-chart.ts`

**Key Patterns Found**:

1. **Namespace with Kargo label**:
```typescript
new k8s.KubeNamespace(this, 'pipelines-namespace', {
  metadata: {
    name: 'kargo-pipelines',
    labels: { 'kargo.akuity.io/project': 'true' }
  }
});
```

2. **Project resource** (no spec field):
```typescript
new Project(this, 'pipelines-project', {
  metadata: { name: 'kargo-pipelines' }
});
```

3. **ProjectConfig with promotion policies and webhooks**:
```typescript
new ProjectConfig(this, 'pipelines-project-config', {
  spec: {
    promotionPolicies: [
      { stageSelector: { name: 'glob:*-dev' }, autoPromotionEnabled: true },
      { stageSelector: { name: 'glob:*-prod' }, autoPromotionEnabled: false }
    ],
    webhookReceivers: [{
      name: 'gitea-backstage',
      github: { secretRef: { name: 'kargo-gitea-webhook-secret' } }
    }]
  }
});
```

4. **RBAC for ArgoCD operations**:
```typescript
new k8s.KubeClusterRole(this, 'kargo-argocd-updater-role', {
  rules: [
    { apiGroups: ['argoproj.io'], resources: ['applications'], verbs: ['get', 'list', 'patch', 'update'] }
  ]
});
```

### External Secrets Pattern

Credentials should be managed via External Secrets from Azure Key Vault, following the existing pattern in the codebase.

---

## 6. Dual ArgoCD Application Strategy

### Decision: Separate ArgoCD Applications for inner vs outer loop in KIND

**Rationale**: Prevents conflicts when both loops deploy different image versions to KIND simultaneously.

### Application Naming Convention

| Stage | ArgoCD Application | Namespace |
|-------|-------------------|-----------|
| local-dev | `backstage-local-dev` | `backstage-local-dev` |
| dev | `backstage-dev` | `backstage-dev` |
| staging | `backstage-staging` | `backstage` |
| production | `backstage-prod` | `backstage` |

### KIND Cluster Configuration

Two separate namespaces in KIND:
- `backstage-local-dev`: Receives inner loop images (Gitea)
- `backstage-dev`: Receives outer loop images (GHCR)

This ensures inner and outer loop can coexist with different image versions.

---

## 7. Image Tagging Strategy

### Decision: Different tagging strategies per loop

**Inner Loop (Gitea)**:
- Pattern: `dev-<short-commit-hash>` (e.g., `dev-abc1234`)
- Selection Strategy: `Lexical` (newest tag lexicographically)
- Rationale: Fast iteration, no semantic meaning

**Outer Loop (GitHub)**:
- Pattern: `v<major>.<minor>.<patch>` (e.g., `v1.2.3`)
- Selection Strategy: `SemVer` with constraint
- Rationale: Meaningful versions, release tracking

---

## 8. Framework Design Decisions

### Chart Structure

```
cdk8s/charts/pipelines/
├── kargo-pipelines-project-chart.ts   # Existing: shared project resources
├── kargo-backstage-pipeline-chart.ts  # NEW: Backstage-specific pipelines
└── kargo-pipeline-factory.ts          # NEW: Reusable pipeline generator
```

### Pipeline Factory Interface

```typescript
interface PipelineConfig {
  appName: string;                      // e.g., 'backstage'
  giteaRegistry: string;               // e.g., 'gitea.cnoe.localtest.me:8443'
  ghcrRegistry: string;                // e.g., 'ghcr.io/pittampalliorg'
  innerLoop: {
    enabled: boolean;
    tagPattern: string;                // e.g., '^dev-[a-f0-9]{7}$'
    argocdApp: string;                 // e.g., 'backstage-local-dev'
  };
  outerLoop: {
    enabled: boolean;
    tagPattern: string;                // e.g., '^v\\d+\\.\\d+\\.\\d+$'
    stages: {
      dev: { argocdApp: string };
      staging: { argocdApp: string; clusterUrl: string };
      production?: { argocdApp: string; clusterUrl: string };
    };
  };
}
```

---

## Sources

- [Kargo Warehouse Documentation](https://docs.kargo.io/user-guide/how-to-guides/working-with-warehouses/)
- [Kargo Webhook Receivers Reference](https://docs.kargo.io/user-guide/reference-docs/webhook-receivers/)
- [Kargo Managing Credentials](https://docs.kargo.io/user-guide/security/managing-credentials/)
- [GitHub Issue #4783: HTTP-only OCI Registry](https://github.com/akuity/kargo/issues/4783)
- Existing codebase: `cdk8s/charts/pipelines/kargo-pipelines-project-chart.ts`
- Existing codebase: `cdk8s/imports/kargo.akuity.io.ts`
