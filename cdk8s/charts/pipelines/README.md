# Kargo Pipeline Charts

This directory contains CDK8s charts for creating Kargo progressive delivery pipelines.

## Overview

Kargo pipelines enable GitOps-based image promotion through environments:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Kargo Pipeline Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  INNER LOOP (Rapid Iteration)                                               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────────┐ │
│  │   Gitea     │───▶│ Warehouse   │───▶│ local-dev Stage (auto-promote) │ │
│  │   Registry  │    │ backstage-  │    │ → ArgoCD App: backstage-local- │ │
│  │  dev-*      │    │ gitea       │    │   dev                          │ │
│  └─────────────┘    └─────────────┘    └─────────────────────────────────┘ │
│                                                                              │
│  OUTER LOOP (CI-Verified)                                                    │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────┐    ┌─────────┐    ┌───┐│
│  │   GHCR      │───▶│ Warehouse   │───▶│ dev     │───▶│ staging │───▶│prod│
│  │   Registry  │    │ backstage-  │    │ (auto)  │    │ (manual)│    │(m) ││
│  │  v1.2.3     │    │ ghcr        │    └─────────┘    └─────────┘    └───┘│
│  └─────────────┘    └─────────────┘                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Charts

### kargo-pipelines-project-chart.ts

Creates the Kargo Project and ProjectConfig resources:
- Namespace with `kargo.akuity.io/project: 'true'` label
- Project resource
- ProjectConfig with promotion policies and webhook receivers
- RBAC for ArgoCD operations
- Webhook secrets for Gitea and GitHub

### kargo-backstage-pipeline-chart.ts

Creates the complete Backstage pipeline:
- **Inner Loop**: Gitea Warehouse + local-dev Stage
- **Outer Loop**: GHCR Warehouse + dev/staging/prod Stages

### kargo-pipeline-factory.ts

Reusable factory for creating pipelines for any application:

```typescript
import { KargoPipelineFactory } from './kargo-pipeline-factory';

// Create a pipeline for a new application
KargoPipelineFactory.create(this, 'my-app-pipeline', {
  appName: 'my-app',
  enableInnerLoop: true,
  enableOuterLoop: true,
  giteaRegistry: 'gitea.cnoe.localtest.me:8443/giteaadmin',
  ghcrRegistry: 'ghcr.io/myorg',
});
```

Or use the Chart wrapper in applications.ts:

```typescript
{
  name: 'kargo-my-app-pipeline',
  namespace: 'kargo-pipelines',
  chart: {
    type: 'KargoPipelineFactoryChart',
    props: {
      appName: 'my-app',
      enableInnerLoop: true,
      enableOuterLoop: true,
    }
  }
}
```

## Adding a New Application Pipeline

### Option 1: Using the Factory (Recommended)

1. Add to `config/applications.ts`:

```typescript
{
  name: 'kargo-frontend-pipeline',
  namespace: 'kargo-pipelines',
  chart: {
    type: 'KargoPipelineFactoryChart',
    props: {
      appName: 'frontend',
      enableInnerLoop: true,
      enableOuterLoop: true,
      // Optional: customize registries
      giteaRegistry: 'gitea.cnoe.localtest.me:8443/giteaadmin',
      ghcrRegistry: 'ghcr.io/pittampalliorg',
    }
  },
  argocd: {
    syncWave: '77',
    // ... sync policy
  }
}
```

2. Add ArgoCD Application targets with Kargo authorization:

```typescript
{
  name: 'frontend-local-dev',
  namespace: 'frontend-local-dev',
  chart: { type: 'FrontendChart', props: { namespace: 'frontend-local-dev' } },
  argocd: {
    annotations: {
      'kargo.akuity.io/authorized-stage': 'kargo-pipelines:frontend-local-dev'
    }
  }
},
{
  name: 'frontend-dev',
  namespace: 'frontend-dev',
  chart: { type: 'FrontendChart', props: { namespace: 'frontend-dev' } },
  argocd: {
    annotations: {
      'kargo.akuity.io/authorized-stage': 'kargo-pipelines:frontend-dev'
    }
  }
}
```

3. Synthesize: `npm run synth`

### Option 2: Custom Chart

Create a dedicated chart following the pattern in `kargo-backstage-pipeline-chart.ts`.

## Configuration Reference

### PipelineConfig

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `appName` | string | required | Application name |
| `namespace` | string | `'kargo-pipelines'` | Kargo namespace |
| `enableInnerLoop` | boolean | `true` | Enable Gitea → local-dev |
| `enableOuterLoop` | boolean | `true` | Enable GHCR → dev → staging → prod |
| `giteaRegistry` | string | `'gitea.cnoe.localtest.me:8443/giteaadmin'` | Gitea registry URL |
| `ghcrRegistry` | string | `'ghcr.io/pittampalliorg'` | GHCR registry URL |
| `innerLoopTagPattern` | string | `'^dev-[a-f0-9]{7}$'` | Regex for inner loop tags |
| `semverConstraint` | string | `'>=1.0.0'` | SemVer constraint for outer loop |
| `stages` | StageDefinition[] | default stages | Custom stage definitions |

### StageDefinition

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | required | Stage name suffix |
| `isInnerLoop` | boolean | `false` | Inner or outer loop |
| `directFromWarehouse` | boolean | `true` | Get freight directly from warehouse |
| `upstreamStage` | string | - | Upstream stage name |
| `requiredSoakTime` | string | - | Soak time (e.g., '24h') |
| `autoPromote` | boolean | `false` | Auto-promote to this stage |
| `isPlaceholder` | boolean | `false` | Mark as placeholder |

## Image Tagging Conventions

| Loop | Registry | Tag Pattern | Selection Strategy |
|------|----------|-------------|-------------------|
| Inner | Gitea | `dev-<7-char-hex>` | Lexical (newest) |
| Outer | GHCR | `v1.2.3` (SemVer) | SemVer (highest) |

## Webhook Setup

See `specs/105-setup-kargo-pipelines/quickstart.md` for webhook configuration instructions.

## Files

| File | Purpose |
|------|---------|
| `kargo-pipelines-project-chart.ts` | Project, ProjectConfig, RBAC |
| `kargo-backstage-pipeline-chart.ts` | Backstage-specific pipeline |
| `kargo-pipeline-factory.ts` | Reusable factory for any app |
| `kargo-pipelines-credentials-chart.ts` | Registry credentials |
| `kargo-helm-chart.ts` | Kargo Helm deployment |
| `kargo-ca-certificates-chart.ts` | CA certificates for Gitea |
| `kargo-secrets-chart.ts` | Kargo secrets |
| `kargo-gitea-webhook-setup-chart.ts` | Gitea webhook automation |
