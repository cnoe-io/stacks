# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

GitOps infrastructure repository using **nixidy** (Nix-based) to define Kubernetes manifests, deployed via IdpBuilder and managed by ArgoCD. Stack includes Backstage, Keycloak, External Secrets Operator, Kargo pipelines, and multi-environment support.

**CNOE** (Cloud Native Operational Excellence): Open-source-first, Kubernetes-powered platform framework. See `docs/cnoe-overview.md`.

**nixidy**: Nix-based GitOps framework for generating Kubernetes YAML. Uses NixOS module system for type-safe configuration. Environments → Applications → Resources → YAML manifests.

**idpBuilder**: Spins up complete IDP locally (Docker only). Creates kind cluster, installs ArgoCD + Gitea + ingress-nginx. Uses `cnoe://` URL syntax for local packages.

## Common Commands

### Nixidy Development
```bash
cd nixidy
nix develop                        # Enter dev shell with nixidy CLI
nixidy build .#kind                # Build manifests for KIND cluster
nixidy build .#talos               # Build manifests for Talos cluster
nixidy build .#hub                 # Build manifests for Hub cluster
ls result/                         # View generated applications
ls result/<app>/                   # View manifests for specific app
```

### Legacy CDK8s (Archived)
```bash
# CDK8s has been replaced by nixidy. See cdk8s/ for historical reference.
# Use nixidy for all new manifest generation.
```

### IdpBuilder Deployment
```bash
idpbuilder create --package nixidy-dist/             # Deploy all from nixidy
idpbuilder create --package nixidy-dist/<app>        # Deploy specific
idpbuilder create --use-path-routing --package ...   # Path-based routing
idpbuilder get secrets -p gitea                      # Get secrets
idpbuilder delete --name localdev                    # Delete cluster
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

### Code Organization

- **Entry point**: `cdk8s/main-v2.ts` - loads config, creates charts, synthesizes to `cdk8s/dist/<app>/manifests/`
- **Config**: `cdk8s/config/applications.ts` - declarative ApplicationConfig[]
- **Charts**: `cdk8s/charts/{apps,platform,pipelines,secrets,infra}/`
- **Libraries**: `cdk8s/lib/` - factory, sync builders, ESO helpers, Kargo RBAC
- **Imports**: `cdk8s/imports/` - k8s.ts, argoproj.io.ts, external-secrets.io.ts, kargo.akuity.io.ts

### CDK8s Pattern

TypeScript over YAML templating for type safety, IDE support, reusability.

**Resource APIs**:
- `imports/k8s` (low-level): Exact YAML control, CRDs, precise specs
- `cdk8s-plus-32` (high-level): Standard resources with ergonomics

This repo primarily uses `imports/k8s` for consistency.

### IdpBuilder Packages & cnoe:// URLs

1. `cnoe://<package>/manifests` in ArgoCD Application source
2. IdpBuilder creates Gitea repo, pushes manifests
3. Rewrites URL to Gitea, ArgoCD syncs

### Secrets Management

ESO with Azure Key Vault via Workload Identity:
- ClusterSecretStore → Key Vault
- ExternalSecret per namespace
- Patterns: env secrets, dockerconfigjson, TLS

## Adding New Applications

```typescript
// 1. Create chart: cdk8s/charts/apps/my-app-chart.ts
export class MyAppChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);
    // Define resources...
  }
}

// 2. Add to config/applications.ts
{
  name: 'my-app',
  namespace: 'my-app',
  chart: { type: 'MyAppChart', props: {} },
  argocd: { syncWave: '100', syncPolicy: { automated: { prune: true, selfHeal: true } } }
}
```

```bash
# 3. Synthesize and deploy
cd cdk8s && npm run synth
idpbuilder create --package dist/my-app
```

## Best Practices

1. **Sync Waves**: `-110` namespaces → `-90` RBAC → `-70` secrets → `0` deployments → `100+` ingresses
2. **Resource Naming**: `<app>-<env>-<resource>` pattern
3. **Security**: External Secrets for sensitive data, SecurityContext, resource limits
4. **Type Safety**: Interfaces for chart props, validate configurations

## Troubleshooting

```bash
# TypeScript errors
rm -rf cdk8s/node_modules/.cache && cd cdk8s && npm run compile

# Synthesis failures
cd cdk8s && rm -rf dist/ && npm run synth

# Import issues
cd cdk8s && npm run import
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
| Packaging | cdk8s | TypeScript manifests |
| Deployment | Kargo | Progressive delivery |

## Documentation

See `docs/` for detailed guides:
- `cnoe-overview.md`, `cdk8s-typescript-docs.md`, `cdk8s-architecture-and-packaging.md`
- `development-workflow.md`, `gitops-architecture-overview.md`
- `secrets-management.md`, `AZURE_WORKLOAD_IDENTITY.md`, `tailscale-cluster-access.md`

## Reference Implementation

```bash
idpbuilder create --use-path-routing \
  --kind-config ref-implementation/kind-config.yaml \
  --package https://github.com/cnoe-io/stacks//ref-implementation
```

**URLs** (domain-based): `https://{argocd,argo-workflows,gitea,keycloak}.cnoe.localtest.me:8443`
**Credentials**: `idpbuilder get secrets` (user1/user2 for Backstage, cnoe-admin for Keycloak)
