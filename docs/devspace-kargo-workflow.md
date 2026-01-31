# DevSpace + Kargo Development Workflow

This guide explains how DevSpace, Kargo, and ArgoCD work together for active-development applications.

## Architecture: Single Branch Model

Active-development apps use a **Single Branch Model** for simplified GitOps:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ArgoCD Applications (per active-dev app)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ ai-chatbot           │ DEPLOYER │ Syncs from Gitea main branch             │
│ vibe-coding-platform │ DEPLOYER │ Kargo updates image tag on main          │
│ workflow-web         │ DEPLOYER │ Config changes sync in ~3-10s            │
│ ...                  │ DEPLOYER │ Image changes sync in ~60s               │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Characteristics:**
- **Single app per application**: No separate `*-local-dev` apps
- **Kargo updates main branch**: Uses `kustomize-set-image` to update image tags directly
- **Fast config changes**: ~3-10s via idpbuilder → Gitea (main) → ArgoCD
- **Image changes via Kargo**: ~60s via Warehouse → Stage → main branch push → ArgoCD

## Overview

| Tool | Responsibility | Latency | Use When |
|------|----------------|---------|----------|
| **DevSpace** | Local hot-reload development | ~2-3s | Iterating on code/UI |
| **devenv up** | Config sync to cluster | ~3-10s | ConfigMap/manifest changes |
| **Kargo** | Image promotion pipeline | ~60s | Testing production images |
| **ArgoCD** | GitOps state enforcement | auto | Enforces desired state |

## Development Phases

```
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 1: DEVSPACE LOCAL DEV (Fastest iteration, ~2-3s)             │
├─────────────────────────────────────────────────────────────────────┤
│ Use when: Iterating on code, UI, business logic                    │
│ Command: devspace dev                                               │
│ Flow: Save file → sync → hot-reload (no rebuild)                   │
│ Config: INHERITS from cluster, overrides via devspace.yaml env     │
│ ArgoCD: ignoreDifferences allows DevSpace to modify pods           │
└─────────────────────────────────────────────────────────────────────┘
           │
           │ Ready to test config changes?
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 2: CONFIG CHANGES (Fast path, ~3-10s)                        │
├─────────────────────────────────────────────────────────────────────┤
│ Use when: ConfigMap changes, env var updates, manifest changes     │
│ Command: (edit packages/...) → devenv up auto-syncs               │
│ Flow: Edit → kustomize build → idpbuilder → Gitea (main)          │
│       → ArgoCD syncs automatically (~3-10s total)                 │
│ Note: Config changes bypass Kargo - direct ArgoCD sync!           │
└─────────────────────────────────────────────────────────────────────┘
           │
           │ Ready to test production image?
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 3: BUILD & PUSH IMAGE (Test with production image, ~60s)     │
├─────────────────────────────────────────────────────────────────────┤
│ Use when: Testing Dockerfile changes, production build             │
│ Command: docker build && docker push gitea.../app:test-<hash>      │
│ Flow: Push → Kargo Warehouse → Stage → kustomize-set-image        │
│       → push main → ArgoCD syncs                                   │
│ Result: Pod restarts with new production image                     │
└─────────────────────────────────────────────────────────────────────┘
           │
           │ DevSpace back to code iteration
           ▼
           └─────────────────────────────────────────────────────────┐
                                                                     │
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 4: RELEASE (When feature complete)                            │
├─────────────────────────────────────────────────────────────────────┤
│ Use when: Feature ready for outer-loop promotion                   │
│ Command: devspace reset && devspace purge                          │
│ Flow: Commit → PR → Merge → GitHub Actions → GHCR → Kargo outer   │
│ Result: Verified artifact promoted through dev → staging → prod   │
└─────────────────────────────────────────────────────────────────────┘
```

## Decision Tree

```
Need to make a change?
│
├── Code/UI changes?
│   └── Use DevSpace: `devspace dev` → edit → hot-reload (~2-3s)
│
├── ConfigMap/env var changes?
│   └── Edit packages/... → devenv up → ArgoCD syncs (~3-10s)  ← FAST PATH!
│
├── Dockerfile/build changes?
│   └── Build & push: `docker build && docker push` → Kargo → ArgoCD (~60s)
│
└── Ready for production?
    └── Reset DevSpace, commit, PR, merge → outer-loop pipeline
```

**Key Insight:** Config changes are now FAST (~3-10s) because they go directly through
ArgoCD, bypassing the Kargo pipeline. Only image updates go through Kargo.

## Configuration Architecture

### ConfigMap Tiers

| Tier | ConfigMap | Purpose | DevSpace Behavior |
|------|-----------|---------|-------------------|
| **1. App Config** | `<app>-config` | Core app settings (PORT, NODE_ENV) | Inherits |
| **2. OTEL Config** | `<app>-otel-config` | Observability settings | Inherits |
| **3. Dapr Config** | `<app>-dapr-config` | Dapr integration settings | Inherits |
| **4. Secrets** | `<app>-secrets` | API keys, credentials | Inherits |

### DevSpace Overrides

DevSpace only overrides these values (defined in `devspace.yaml`):

```yaml
env:
  NODE_ENV: development
  OTEL_SERVICE_NAME: <app>-devspace
  NODE_TLS_REJECT_UNAUTHORIZED: "0"
```

All other configuration is inherited from the deployed ConfigMaps.

### ArgoCD ignoreDifferences

Active-development apps ignore these fields for drift detection:

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
      - /spec/template/spec/containers/0/image      # DevSpace replaces
      - /spec/template/spec/containers/0/resources  # DevSpace overrides
      - /spec/replicas                              # Manual scaling
```

This allows DevSpace to modify pods without ArgoCD reverting the changes.

### Kargo Authorization

Each app has a `kargo.akuity.io/authorized-stage` annotation that allows
Kargo to update the ArgoCD Application:

```yaml
metadata:
  annotations:
    kargo.akuity.io/authorized-stage: kargo-pipelines:<app>-local-dev
```

## Key Points

| Aspect | How It Works |
|--------|--------------|
| **Config source of truth** | `packages/components/active-development/manifests/<app>/` |
| **Config sync flow** | devenv up → idpbuilder → Gitea (main) → ArgoCD syncs |
| **Config sync latency** | ~3-10 seconds (direct ArgoCD sync) |
| **Image sync flow** | Docker push → Kargo Warehouse → Stage → kustomize-set-image → main → ArgoCD |
| **Image sync latency** | ~60 seconds (goes through Kargo pipeline) |
| **DevSpace interaction** | Inherits ConfigMaps from cluster, only overrides NODE_ENV/OTEL_SERVICE_NAME |
| **ArgoCD apps** | Single app per namespace with automated sync + selfHeal |
| **Kargo role** | Image promotion only - updates image tag on main branch |

## Commands Reference

### DevSpace Commands

```bash
# Start local development
devspace dev

# Reset to production state
devspace reset

# Purge DevSpace resources
devspace purge

# View sync status
devspace logs

# List all variables (verify Kargo integration)
devspace list vars
```

## Shared DevSpace Configuration

All apps use shared templates from `stacks/main/devspace-templates/`:

```yaml
# Example devspace.yaml
imports:
  - path: ../../stacks/main/devspace-templates/base.yaml
  - path: ../../stacks/main/devspace-templates/snippets/nextjs.yaml

vars:
  APP_NAME: ai-chatbot
  LOCAL_PORT: "3000"
```

### Shared Devcontainers

Instead of per-app images, use centralized containers from `stacks/main/devcontainers/`:

| Image | Use Case |
|-------|----------|
| `nodejs-22-devspace` | Next.js/Node.js apps |
| `python-312-devspace` | Python/FastAPI apps |
| `nodejs-python-devspace` | Agent apps (Node.js + Python) |

```yaml
# In devspace.yaml
dev:
  app:
    devImage: ${GITEA_HOST}/${GITEA_USER}/nodejs-22-devspace:latest
```

### Kargo Integration

DevSpace shows which Kargo-promoted image is being replaced:

```bash
$ devspace dev
=== DevSpace Development Container ===
Replacing production image: gitea.cnoe.localtest.me:8443/giteaadmin/ai-chatbot:v1.2.3
Using shared devcontainer: nodejs-22-devspace
```

This visibility helps developers understand the production state they're developing against.

### Kargo Commands

```bash
# Watch for new freight
kubectl get freights -n kargo-pipelines -w

# Check warehouse status
kubectl get warehouses -n kargo-pipelines

# Check stage status
kubectl get stages -n kargo-pipelines
```

### ArgoCD Commands

```bash
# Check app status
argocd app get argocd/<app> --insecure

# Force sync
argocd app sync argocd/<app> --prune --insecure

# View diff
argocd app diff argocd/<app> --insecure
```

### devenv Commands

```bash
# Start watch + rebuild + apply
devenv up

# One-shot build
kustomize-build

# One-shot apply
apply-manifests
```

## Typical Workflows

### New Feature Development

1. Start DevSpace: `devspace dev`
2. Iterate on code with hot-reload
3. Test config changes: edit ConfigMap → devenv up (~3-10s)
4. Test with production image: `docker build && docker push` (~60s)
5. Reset and commit: `devspace reset && git commit`

### Config-Only Changes

1. Edit ConfigMap in `packages/components/active-development/manifests/<app>/`
2. Run `devenv up` or let it auto-sync (pushes to Gitea main branch)
3. ArgoCD syncs automatically (~3-10s)
4. Verify: `kubectl get cm -n <app> -o yaml`

**Note:** Config changes go directly through ArgoCD - no Kargo involvement!

### Image Promotion Testing

1. Build and push: `docker build -t gitea.../app:test-abc && docker push`
2. Watch Kargo: `kubectl get freights -n kargo-pipelines -w`
3. Kargo Stage updates image tag on main branch
4. ArgoCD syncs the new image
5. Verify deployment: `kubectl get pods -n <app> -w`

## Troubleshooting

### DevSpace not syncing

```bash
# Check DevSpace status
devspace status

# Check sync logs
devspace logs --sync

# Restart DevSpace
devspace dev --force-rebuild
```

### Config changes not appearing

```bash
# Config changes go through ArgoCD directly, so check:

# 1. Was the manifest pushed to Gitea?
# Check devenv up is running
ps aux | grep watch

# 2. Did ArgoCD detect the change?
argocd app get argocd/<app> --insecure

# 3. Force a refresh
argocd app get argocd/<app> --refresh --insecure

# Or rebuild and push manually
kustomize-build && apply-manifests
```

### Kargo not detecting image

```bash
# Check warehouse subscription
kubectl describe warehouse <app>-warehouse -n kargo-pipelines

# Force warehouse refresh
kubectl annotate warehouse <app>-warehouse -n kargo-pipelines \
  refresh="$(date +%s)" --overwrite
```

### ArgoCD showing OutOfSync

```bash
# OutOfSync on image/resources is expected during DevSpace
# ignoreDifferences prevents selfHeal from reverting DevSpace changes

# To see what differs
argocd app diff argocd/<app> --insecure

# To force sync
argocd app sync argocd/<app> --insecure
```

## Active-Development Apps

| App | DevSpace | Dapr | OTEL | Notes |
|-----|----------|------|------|-------|
| ai-chatbot | ✅ | ✅ | ✅ | Full stack with sandbox |
| vibe-coding-platform | ✅ | ✅ | ✅ | Workflow orchestration |
| workflow-web | ✅ | ✅ | ✅ | Workflow visualization |
| workflow-builder | ✅ | ❌ | ✅ | No Dapr integration |
| activity-executor | ✅ | ✅ | ✅ | Dapr activities |
| flight-booking-app | ✅ | ✅ | ✅ | Demo app |
| planner-agent | ✅ | ✅ | ✅ | Multi-deployment |

## Related Documentation

- [CLAUDE.md](../CLAUDE.md) - Main development guide
- [Kargo Pipelines](../specs/105-setup-kargo-pipelines/quickstart.md)
- [Development Workflow](development-workflow.md)
- [GitOps Architecture](gitops-architecture-overview.md)
