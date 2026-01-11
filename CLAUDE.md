# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

GitOps infrastructure repository using **Kustomize** to define Kubernetes manifests, deployed via idpBuilder and managed by ArgoCD. Stack includes Backstage, Keycloak, External Secrets Operator, Kargo pipelines, and multi-environment support.

**CNOE** (Cloud Native Operational Excellence): Open-source-first, Kubernetes-powered platform framework. See `docs/cnoe-overview.md`.

**idpBuilder**: Spins up complete IDP locally (Docker only). Creates kind cluster, installs ArgoCD + Gitea + ingress-nginx. Uses `cnoe://` URL syntax for local packages.

## Common Commands

### Package Development
```bash
cd packages
make build-kind           # Build KIND local dev environment
make build-kind-ryzen     # Build KIND for Ryzen host
make build-kind-thinkpad  # Build KIND for Thinkpad host
make build-talos          # Build Talos production environment
make build-hub            # Build Hub multi-cluster environment
make build-all            # Build all environments
make validate-kind        # Validate KIND build output
make clean                # Remove generated files
```

### IdpBuilder Deployment
```bash
cd packages
make deploy-kind                                   # Build and deploy KIND
idpbuilder create --package dist/kind/             # Deploy KIND build
idpbuilder create --package dist/kind/<app>        # Deploy specific app
idpbuilder create --use-path-routing --package ... # Path-based routing
idpbuilder get secrets -p gitea                    # Get secrets
idpbuilder delete --name localdev                  # Delete cluster
```

### Talos Linux Cluster Bootstrap
```bash
cd scripts
cp .env.template .env  # Set AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID
./bootstrap-cluster.sh --setup-azure  # Fresh setup with Azure resources
./bootstrap-cluster.sh                # Existing Azure infrastructure
./bootstrap-cluster.sh --force        # Force re-bootstrap
```

**Bootstrap phases**: Azure Infrastructure → Validate Prerequisites → Install ArgoCD → Sync JWKS → Apply GitOps

**Key scripts**: `bootstrap-cluster.sh` (orchestrator), `00-bootstrap-azure-infra.sh`, `01-install-argocd.sh`, `02-sync-jwks.sh`, `03-apply-base-apps.sh`

**Azure Workload Identity**: ServiceAccount with azure.workload.identity labels → JWT validated against JWKS in Azure Storage → Azure AD App issues token → Key Vault access. See `docs/AZURE_WORKLOAD_IDENTITY.md`.

### ArgoCD CLI
```bash
source ~/stacks/deployment/scripts/cluster-menu.sh  # Sets ARGOCD_AUTH_TOKEN
argocd app list --insecure                          # Always use --insecure for local dev
argocd app sync argocd/my-app --prune --insecure
argocd-status                                       # Helper function
```

### Kargo Pipelines
```bash
kubectl get warehouses,stages,freights -n kargo-pipelines
kargo promote --project kargo-pipelines --stage backstage-staging --freight <name>
```

**Architecture**: Inner Loop (Gitea → local-dev, auto, <60s) | Outer Loop (GHCR → dev → staging → prod)

See `specs/105-setup-kargo-pipelines/quickstart.md`.

### Gitea System Webhooks

System webhooks automatically notify ArgoCD and Kargo on **every push** to any Gitea repository, enabling instant syncs without polling delays.

```bash
# Verify system webhooks are configured
kubectl run -i --rm curl --image=curlimages/curl:8.5.0 -n gitea -- \
  curl -s -u giteaAdmin:developer \
  "http://my-gitea-http.gitea.svc.cluster.local:3000/api/v1/admin/hooks"
```

**Webhooks created automatically via PostSync hooks:**

| Service | Webhook URL | App |
|---------|-------------|-----|
| ArgoCD | `http://argocd-server.argocd.svc.cluster.local/api/webhook` | `argocd-webhook-setup` |
| Kargo | `http://kargo-external-webhooks-server.kargo.svc.cluster.local:80/webhooks/gitea/<hash>` | `kargo-webhook-sync` |

**How it works:**
1. `ingress-nginx-cert` (sync-wave: -99) copies TLS cert for external access
2. ExternalSecrets fetch Gitea admin credentials from Azure Key Vault
3. PostSync Jobs create system webhooks using Gitea admin API
4. Any push to Gitea triggers instant sync in ArgoCD/Kargo (vs 3-5 min polling)

See `docs/gitea-webhooks.md` for detailed architecture.

### kagent/kmcp (AI Agent Platform)
```bash
kubectl get pods -n kagent
kubectl get agents,modelconfigs,mcpservers -n kagent
# Dashboard: https://kagent.cnoe.localtest.me:8443
```

**Note**: kagent-controller v0.6.3 has upstream bugs causing CrashLoopBackOff. Dashboard works independently.

### Tailscale (Remote Access & Services)

**Operator** (kubectl access):
```bash
./deployment/scripts/tailscale/generate-kubeconfig.sh
kubectl --kubeconfig=~/remote-kubeconfig.yaml get nodes
```

**Service URLs** (cluster-scoped pattern: `https://<service>-<cluster>.<tailnet>.ts.net`):
| Service | Purpose |
|---------|---------|
| argocd-\<cluster\> | GitOps Dashboard |
| langfuse-\<cluster\> | LLM Observability |
| gitea-\<cluster\> | Git Server |
| kagent-\<cluster\> | AI Agent Dashboard |
| kargo-\<cluster\> | Progressive Delivery |
| headlamp-\<cluster\> | Kubernetes Dashboard |
| keycloak-\<cluster\> | Identity Provider |

See `docs/tailscale-cluster-access.md` and `specs/103-tailscale-services/quickstart.md`.

### Hub-and-Spoke Architecture (Feature 108)

Multi-cluster GitOps: Hub cluster (Hetzner) manages spoke clusters (thinkpad, ryzen, talos) via Tailscale.

```bash
# Hub provisioning (in talos-cluster repo)
./scripts/provision-hub.sh && ./scripts/gen-hub-config.sh && ./scripts/bootstrap-hub.sh $IP

# Spoke registration
source scripts/lib/spoke-helpers.sh
./scripts/bootstrap-spoke.sh thinkpad
```

**targetCluster values**: `'hub'`, `'hetzner'`, `'thinkpad'`, `'ryzen'`, `'talos'`

See `specs/108-hub-and-spoke/` and `docs/hub-recovery-runbook.md`.

## Architecture

### Package Structure

```
packages/
├── Makefile                    # Build commands
├── scripts/build.sh            # idpbuilder-compatible build script
├── base/                       # Shared infrastructure (all environments)
│   ├── kustomization.yaml      # Lists ~51 shared apps
│   ├── apps/                   # ArgoCD Application YAMLs
│   └── manifests/              # Raw K8s manifests (non-Helm)
├── components/                 # Environment-specific app groups
│   ├── kind-only/              # KIND-specific apps (~31)
│   ├── talos-only/             # Talos production apps
│   ├── tailscale-serve/        # Tailscale proxy apps (~20)
│   └── observability/          # LGTM monitoring stack (~18)
├── overlays/                   # Environment configurations
│   ├── kind/                   # KIND local dev (base + kind-only + tailscale + observability)
│   ├── kind-ryzen/             # Per-host KIND variant
│   ├── kind-thinkpad/          # Per-host KIND variant
│   ├── talos/                  # Talos production
│   └── hub/                    # Hub multi-cluster
└── dist/                       # Generated output (gitignored)
    └── <env>/                  # idpbuilder-compatible structure
        ├── <app>.yaml          # ArgoCD Application
        └── <app>/manifests/    # K8s manifests for cnoe://
```

### Application Types

**Helm-based** (ArgoCD manages Helm):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-95"
spec:
  source:
    repoURL: https://charts.jetstack.io
    targetRevision: v1.14.4
    chart: cert-manager
    helm:
      valuesObject:
        installCRDs: true
```

**Manifest-based** (local manifests via cnoe://):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backstage-secrets
  namespace: argocd
spec:
  source:
    repoURL: cnoe://backstage-secrets
    targetRevision: HEAD
    path: "."
```

### Kustomize Components

Environment-specific apps are organized into Kustomize components:

| Component | Apps | Purpose |
|-----------|------|---------|
| base | ~51 | Shared infrastructure (cert-manager, external-secrets, keycloak, backstage, etc.) |
| kind-only | ~31 | KIND-specific (CAIPE, idpbuilder-gitea, azure-workload-identity, etc.) |
| tailscale-serve | ~20 | Tailscale proxies (*-tailscale-serve apps) |
| observability | ~18 | LGTM stack (grafana, loki, tempo, langfuse, etc.) |
| talos-only | - | Talos production (placeholder) |

### IdpBuilder & cnoe:// URLs

1. `cnoe://<package>/manifests` in ArgoCD Application source
2. IdpBuilder creates Gitea repo, pushes manifests
3. Rewrites URL to Gitea, ArgoCD syncs

### Secrets Management

ESO with Azure Key Vault via Workload Identity:
- ClusterSecretStore → Key Vault
- ExternalSecret per namespace
- Patterns: env secrets, dockerconfigjson, TLS

## Adding New Applications

### Helm-based App
```yaml
# packages/base/apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://charts.example.com
    targetRevision: 1.0.0
    chart: my-app
    helm:
      valuesObject:
        key: value
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Manifest-based App
```yaml
# packages/base/apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: cnoe://my-app
    targetRevision: HEAD
    path: "."
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated: {}
```

```yaml
# packages/base/manifests/my-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
# ...
```

```bash
# Update kustomization.yaml and deploy
echo "  - apps/my-app.yaml" >> packages/base/kustomization.yaml
cd packages && make build-kind
idpbuilder create --package dist/kind/my-app
```

## Best Practices

1. **Sync Waves**: `-100` CRDs → `-80` namespaces → `-60` secrets → `0` apps → `60` ingresses
2. **Resource Naming**: `<app>-<component>` pattern
3. **Security**: External Secrets for sensitive data, SecurityContext, resource limits
4. **Components**: Use Kustomize components for environment-specific apps

## Troubleshooting

```bash
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

## CNOE Technology Stack

| Category | Tool | Implementation |
|----------|------|----------------|
| Code Repository | Git | Gitea (local), GitHub |
| Artifact Registry | OCI | Gitea registry, GHCR |
| Secrets | External Secrets | Azure Key Vault |
| CD | ArgoCD | GitOps |
| Identity | Keycloak | SSO |
| Portal | Backstage | Catalog, templates |
| Packaging | Kustomize | YAML manifests |
| Deployment | Kargo | Progressive delivery |

## Documentation

See `docs/` for detailed guides:
- `cnoe-overview.md`, `gitops-architecture-overview.md`
- `development-workflow.md`, `secrets-management.md`
- `AZURE_WORKLOAD_IDENTITY.md`, `tailscale-cluster-access.md`
- `gitea-webhooks.md` - System webhooks for instant ArgoCD/Kargo syncs

## Reference Implementation

```bash
idpbuilder create --use-path-routing \
  --kind-config ref-implementation/kind-config.yaml \
  --package https://github.com/cnoe-io/stacks//ref-implementation
```

**URLs** (domain-based): `https://{argocd,argo-workflows,gitea,keycloak}.cnoe.localtest.me:8443`
**Credentials**: `idpbuilder get secrets` (user1/user2 for Backstage, cnoe-admin for Keycloak)
