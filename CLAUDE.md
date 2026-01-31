# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

GitOps infrastructure repository using **Kustomize** to define Kubernetes manifests, deployed via [idpBuilder](https://cnoe.io/docs/idpbuilder) and managed by ArgoCD. Stack includes Backstage, Keycloak, External Secrets Operator, Kargo pipelines, and multi-environment support.

**Quick Start:**
```bash
source ~/stacks/deployment/scripts/cluster-menu.sh
cld  # cluster-deploy: full cluster creation
```

**CNOE** (Cloud Native Operational Excellence): Open-source-first, Kubernetes-powered platform framework. See `docs/cnoe-overview.md`.

**idpBuilder**: Spins up complete IDP locally (Docker only). Creates kind cluster, installs ArgoCD + Gitea + ingress-nginx. Uses `cnoe://` URL syntax for local packages. [Documentation](https://cnoe.io/docs/idpbuilder) | [GitHub](https://github.com/cnoe-io/idpbuilder)

## Cluster Lifecycle Commands

**CRITICAL:** Never use `idpbuilder` commands directly - they require the exact same flags as when the cluster was created. Always use cluster-menu.sh commands which embed the correct flags.

```bash
source ~/stacks/deployment/scripts/cluster-menu.sh
```

| Command | Alias | Purpose |
|---------|-------|---------|
| `cluster-deploy` | `cld` | Full cluster creation (Azure auth → kustomize build → idpbuilder → post-setup) |
| `cluster-recreate` | `clr` | Delete + recreate with Tailscale cleanup and health monitoring |
| `cluster-update` | `clu` | Idempotent manifest updates (fastest path for existing clusters) |
| `cluster-build` | `clb` | Kustomize package synthesis only (no apply) |
| `cluster-status` | `clst` | Show cluster and ArgoCD status |
| `cluster-menu` | `clm` | Interactive management menu (requires gum) |

### cluster-deploy Workflow
1. Azure authentication (Key Vault access)
2. Hostname detection (thinkpad, ryzen, hetzner)
3. Kustomize build → `packages/dist/<env>/`
4. idpbuilder create with correct flags
5. Parallel: image preload, CA inject, Tailscale setup
6. ArgoCD token initialization
7. Sync apps without auto-sync

### cluster-recreate Workflow
1. Tailscale operator cleanup (kubeconfig regeneration)
2. idpbuilder delete
3. cluster-deploy
4. Health wait with timing summary

## Development Workflow with devenv

**Typical workflow - automatic sync on file changes:**
```bash
devenv up               # Start watch + rebuild + apply (unified, always-on)
# Edit files in packages/base/, components/, overlays/
# Changes auto-sync within 2-3 seconds (watchexec + idpbuilder)
```

The `devenv up` process monitors `packages/` directories and automatically:
1. Rebuilds kustomize via `make build-kustomize-kind-$CLUSTER_NAME`
2. Applies via `idpbuilder create` with correct flags

**Before running `cluster-update` manually:** Check if `devenv up` is already running - if so, changes are automatically synced.

**Alternative commands:**
| Command | Purpose |
|---------|---------|
| `devenv up` | Watch + rebuild + apply (unified) |
| `watch-kustomize` | Watch + rebuild only (no apply) |
| `kustomize-build` | One-shot build |
| `apply-manifests` | One-shot apply |

## Package Development

```bash
cd packages
make build-kind           # Build KIND local dev environment
make build-kind-ryzen     # Build KIND for Ryzen host
make build-kind-thinkpad  # Build KIND for Thinkpad host
make build-talos          # Build Talos production environment
make build-all            # Build all environments
make validate-kind        # Validate KIND build output
make clean                # Remove generated files
```

### Package Structure

```
packages/
├── Makefile                    # Build commands
├── scripts/build-kustomize.sh  # Native kustomize + yq YAML splitting
├── base/                       # Shared infrastructure (~51 apps)
│   ├── kustomization.yaml
│   ├── apps/                   # ArgoCD Application YAMLs
│   └── manifests/              # Raw K8s manifests (non-Helm)
├── components/                 # Environment-specific app groups
│   ├── kind-only/              # KIND-specific apps (~43)
│   ├── talos-only/             # Talos production apps
│   ├── tailscale-serve/        # Tailscale proxy apps (~20)
│   ├── observability/          # LGTM monitoring stack (~18)
│   └── active-development/     # Apps with auto-sync disabled (7)
├── overlays/                   # Environment configurations
│   ├── kind/                   # KIND local dev
│   ├── kind-ryzen/             # Per-host KIND variant
│   ├── kind-thinkpad/          # Per-host KIND variant
│   ├── talos/                  # Talos production
│   └── hub/                    # Hub multi-cluster
└── dist/                       # Generated output (gitignored)
    └── <env>/                  # idpbuilder-compatible structure
        ├── <app>.yaml          # ArgoCD Application
        └── <app>/manifests/    # K8s manifests for cnoe://
```

### Kustomize Components

| Component | Apps | Purpose |
|-----------|------|---------|
| base | ~51 | Shared infrastructure (cert-manager, external-secrets, keycloak, backstage) |
| kind-only | ~43 | KIND-specific (CAIPE, idpbuilder-gitea, azure-workload-identity) |
| tailscale-serve | ~20 | Tailscale proxies (*-tailscale-serve apps) |
| observability | ~18 | LGTM stack (grafana, loki, tempo, langfuse) |
| active-development | 7 | Apps with Kargo inner-loop pipelines (local Gitea registry images) |

## Architecture

### Application Types

**Helm-based**: ArgoCD manages Helm chart with `source.repoURL` pointing to chart repository, `helm.valuesObject` for configuration.

**Manifest-based**: Local manifests via `cnoe://<package>` URL. idpBuilder creates Gitea repo, pushes manifests, rewrites URL for ArgoCD.

**Kargo-managed (Inner Loop)**: Apps with local development pipelines. Key requirements:
- Deployment image must reference **local Gitea registry**: `gitea.cnoe.localtest.me:8443/giteaadmin/<app>:latest`
- ArgoCD app should NOT use `ServerSideApply=true` (causes comparison errors)
- `ignoreDifferences` should include `resources` and `replicas` but NOT `image` (Kargo manages images)

See `docs/gitops-architecture-overview.md` for detailed patterns.

### Secrets Management

External Secrets Operator with Azure Key Vault via Workload Identity:
- ClusterSecretStore → Key Vault
- ExternalSecret per namespace
- Patterns: env secrets, dockerconfigjson, TLS

See `docs/AZURE_WORKLOAD_IDENTITY.md` for configuration.

## Key Scripts Reference

| Script | Purpose |
|--------|---------|
| `cluster-menu.sh` | Orchestration - lifecycle commands (cld, clu, clr, clst) |
| `argocd-auth.sh` | Token management with 1Password/Azure Key Vault |
| `preload-images.sh` | Image caching (parallel with idpbuilder) |
| `push-devcontainers.sh` | Build/push shared devcontainers (parallel with idpbuilder) |
| `cluster-health-check.sh` | Timing, benchmarks, health summary |
| `devenv-watch-handler.sh` | Automatic rebuild handler for devenv up |
| `tailscale/tailscale-kubeconfig.sh` | Remote kubectl access via Tailscale |

## ArgoCD CLI

```bash
source ~/stacks/deployment/scripts/cluster-menu.sh  # Sets ARGOCD_AUTH_TOKEN
argocd app list --insecure                          # Always use --insecure for local dev
argocd app sync argocd/my-app --prune --insecure
argocd-status                                       # Helper function
```

## Best Practices

1. **Sync Waves**: `-100` CRDs → `-80` namespaces → `-60` secrets → `0` apps → `60` ingresses
2. **Resource Naming**: `<app>-<component>` pattern
3. **Security**: External Secrets for sensitive data, SecurityContext, resource limits
4. **Components**: Use Kustomize components for environment-specific apps

## Adding New Applications

### Standard Applications
1. Create ArgoCD Application YAML in `packages/base/apps/` or appropriate component
2. For manifest-based apps, add manifests to `packages/base/manifests/<app>/`
3. Add to `kustomization.yaml` in the appropriate layer
4. Build and deploy:
```bash
make build-kind && clu  # Or let devenv up auto-apply
```

### Kargo Inner-Loop Applications
For apps with local development pipelines (built images pushed to local Gitea registry):

1. **Deployment**: Set image to `gitea.cnoe.localtest.me:8443/giteaadmin/<app>:latest`
2. **ArgoCD App**: Add to `packages/components/active-development/apps/`:
   ```yaml
   ignoreDifferences:
     - group: apps
       kind: Deployment
       jsonPointers:
         - /spec/template/spec/containers/0/resources
         - /spec/replicas
   syncPolicy:
     automated:
       selfHeal: true
       prune: true
     syncOptions:
       - CreateNamespace=true
       - RespectIgnoreDifferences=true
   ```
3. **Kargo Pipeline**: Add entry to `packages/base/manifests/kargo-inner-loop/images.yaml`
4. Build: `make build-kind` (generates Warehouse + Stage from template)

## Troubleshooting

```bash
# Cluster health summary
$STACKS_DIR/deployment/scripts/cluster-health-check.sh summary

# Validate kustomize build
kubectl kustomize packages/overlays/kind | head -100

# Check build output
make build-kind
ls packages/dist/kind/

# idpBuilder logs
idpbuilder get logs

# ArgoCD sync issues
argocd app sync argocd/<app> --prune --insecure
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

## DevSpace Development

### Shared Configuration

DevSpace configurations are standardized via shared templates in `devspace-templates/`:

```yaml
# Example app devspace.yaml
imports:
  - path: ../../stacks/main/devspace-templates/base.yaml
  - path: ../../stacks/main/devspace-templates/snippets/nextjs.yaml  # or fastapi.yaml

vars:
  APP_NAME: my-app
  LOCAL_PORT: "3000"
  CONTAINER_PORT: "3000"
```

### Shared Devcontainers

Centralized devcontainer images in `devcontainers/`:

| Image | Base | Use Case |
|-------|------|----------|
| `nodejs-22-devspace` | node:22-bookworm | Next.js/Node.js apps |
| `python-312-devspace` | python:3.12-bookworm | Python/FastAPI apps |
| `nodejs-python-devspace` | node:22 + python3.12 | Agent apps needing both |

Build and push:
```bash
# Manual push (after cluster is running)
push-devcontainers all     # All images (alias from cluster-menu.sh)
push-devcontainers hybrid  # Node.js + Python only

# Or use the script directly
cd devcontainers
bash build-push.sh all
```

**Note:** Devcontainers are automatically pushed during `cluster-deploy` and `cluster-recreate` in parallel with image preloading. Set `SKIP_DEVCONTAINER_PUSH=true` to disable.

### Port Allocation

| App | Local Port | SSH Port | Container Port |
|-----|------------|----------|----------------|
| ai-chatbot | 3000 | 2222 | 3000 |
| workflow-builder | 3002 | 2223 | 3000 |
| planner-agent | 8080 | 2224 | 8080 |

### Kargo Integration

DevSpace queries the cluster to show which Kargo-promoted image is being replaced:
```bash
$ devspace dev
=== DevSpace Development Container ===
Replacing production image: gitea.cnoe.localtest.me:8443/giteaadmin/ai-chatbot:v1.2.3
Using shared devcontainer: nodejs-22-devspace
```

See `docs/devspace-kargo-workflow.md` for complete workflow documentation.

## Advanced Topics

### Talos Linux Bootstrap
```bash
cd scripts && ./bootstrap-cluster.sh --setup-azure
```
See `specs/102-bootstrap-talos-argocd/quickstart.md`.

### Hub-and-Spoke Architecture
Multi-cluster GitOps: Hub cluster manages spoke clusters via Tailscale.
- **targetCluster values**: `'hub'`, `'hetzner'`, `'thinkpad'`, `'ryzen'`, `'talos'`
- See `specs/108-hub-and-spoke/quickstart.md` and `docs/hub-recovery-runbook.md`

### Kargo Pipelines

```bash
kubectl get warehouses,stages,freights -n kargo-pipelines
```

**Single-Branch Model (Inner Loop):**
All inner-loop apps use a **single-branch model** where Kargo updates the image tag in `kustomization.yaml` on the `main` branch. idpBuilder manages the source manifests, and Kargo modifies only the image tag.

**Key patterns:**
- Deployments reference local Gitea registry: `gitea.cnoe.localtest.me:8443/giteaadmin/<app>:latest`
- Kargo `kustomize-set-image` updates the tag, ArgoCD syncs the change
- ArgoCD apps have `ignoreDifferences` for `resources` and `replicas` (NOT image) to allow DevSpace compatibility while Kargo manages images

**Kargo Expression Syntax (v1.8+):**
```yaml
# Correct syntax for accessing freight in promotion templates
Freight: ${{ ctx.targetFreight.name }}  # NOT ctx.freight.alias
```

**Pipeline Types:**
| Loop | Source | Stages | Auto-promote |
|------|--------|--------|--------------|
| Inner | Gitea registry | local-dev | Yes |
| Outer | GHCR | dev → staging → prod | Manual |

See `specs/105-setup-kargo-pipelines/quickstart.md`.

### Tailscale Remote Access
Service URLs pattern: `https://<service>-<cluster>.<tailnet>.ts.net`
See `specs/103-tailscale-services/quickstart.md` and `docs/tailscale-naming.md`.

### Gitea System Webhooks
Automatic ArgoCD/Kargo notifications on push, enabling instant syncs.
See `docs/gitea-webhooks.md`.

### kagent/kmcp (AI Agent Platform)
```bash
kubectl get pods -n kagent
kubectl get agents,modelconfigs,mcpservers -n kagent
```

## External References

**idpBuilder:**
- Documentation: https://cnoe.io/docs/idpbuilder
- GitHub: https://github.com/cnoe-io/idpbuilder

**Related Docs:**
- `docs/cnoe-overview.md` - CNOE framework
- `docs/gitops-architecture-overview.md` - GitOps patterns
- `docs/devspace-kargo-workflow.md` - DevSpace + Kargo development workflow
- `devspace-templates/README.md` - Shared DevSpace configuration templates
- `devcontainers/README.md` - Shared devcontainer images
- `docs/development-workflow.md` - Development patterns (legacy CDK8s)
- `docs/AZURE_WORKLOAD_IDENTITY.md` - Azure identity configuration
- `docs/gitea-webhooks.md` - System webhooks architecture
- `docs/tailscale-naming.md` - Tailscale service naming

## CNOE Technology Stack

| Category | Tool |
|----------|------|
| Code Repository | Gitea (local), GitHub |
| Artifact Registry | Gitea registry, GHCR |
| Secrets | External Secrets + Azure Key Vault |
| CD | ArgoCD |
| Identity | Keycloak |
| Portal | Backstage |
| Packaging | Kustomize |
| Deployment | Kargo |
