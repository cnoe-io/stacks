# Kustomize Packages for idpbuilder

This directory contains kustomize-based ArgoCD application definitions compatible with idpbuilder.

Based on the [cnoe-io/stacks reference implementation](https://github.com/cnoe-io/stacks/tree/main/ref-implementation).

## Quick Start

### Full Cluster Management (Recommended)

Use the cluster-menu.sh script for complete cluster lifecycle management with Azure integration:

```bash
# Source the cluster management script
source deployment/scripts/cluster-menu.sh

# Create a new cluster
cluster-deploy   # or: cld

# Update cluster after manifest changes
cluster-update   # or: clu

# Delete and recreate cluster
cluster-recreate # or: clr

# Show cluster status
cluster-status   # or: clst
```

The cluster-menu.sh script handles:
- Azure authentication and Workload Identity
- Building kustomize packages
- KIND config with OIDC issuer
- Persistent TLS from Azure Key Vault
- JWKS sync to Azure Storage
- ArgoCD CA trust configuration
- Tailscale token generation
- Manual app sync for non-autosync apps

### Simple Deploy (idpbuilder only)

For quick testing without Azure integration:

```bash
cd packages
make deploy-kind
```

Note: Without Azure integration, External Secrets won't work

## Directory Structure

### Source Structure

```
packages/
├── base/                    # Shared apps (all environments)
│   ├── apps/               # ArgoCD Application YAMLs
│   └── manifests/          # K8s manifests for non-Helm apps
├── components/             # Environment-specific app groups
│   ├── kind-only/          # KIND local development apps
│   ├── talos-only/         # Talos production apps
│   ├── tailscale-serve/    # Tailscale proxy apps
│   └── observability/      # Monitoring stack
├── overlays/               # Environment configurations
│   ├── kind/               # Generic KIND cluster
│   ├── kind-ryzen/         # KIND on Ryzen host
│   ├── kind-thinkpad/      # KIND on Thinkpad host
│   ├── talos/              # Production Talos cluster
│   └── hub/                # Hub multi-cluster management
├── scripts/
│   └── build.sh            # Build script (generates dist/)
└── dist/                   # Generated output (gitignored)
```

### Generated Output Structure (idpbuilder-compatible)

```
dist/<env>/
├── backstage.yaml              # ArgoCD Application (Helm-based)
├── backstage-namespace.yaml    # ArgoCD Application (manifest-based)
├── backstage-namespace/        # Manifests for cnoe:// URL
│   └── Namespace-backstage.yaml
├── argo-workflows.yaml
├── argo-workflows/
│   ├── ClusterRole-*.yaml
│   ├── Deployment-*.yaml
│   └── ...
└── ...
```

When idpbuilder processes `cnoe://backstage-namespace`:
1. Creates Gitea repo `backstage-namespace`
2. Pushes contents of `backstage-namespace/` directory
3. ArgoCD syncs from `path: "."` (repo root)

## Azure Workload Identity

For External Secrets to access Azure Key Vault, the cluster needs:

1. **OIDC Issuer**: KIND cluster configured with custom service account keys
2. **JWKS Sync**: Cluster's JWKS uploaded to Azure Storage
3. **App Registration**: Azure AD app trusting the OIDC issuer

The bootstrap script handles JWKS sync automatically. OIDC issuer is configured via `kind-config.yaml.template`.

### Prerequisites

```bash
# Azure CLI authenticated
az login

# Environment variables (in .env-files/kind.env)
AZURE_SUBSCRIPTION_ID=<subscription-id>
AZURE_TENANT_ID=<tenant-id>
AZURE_KEYVAULT_NAME=<keyvault-name>
AZURE_STORAGE_ACCOUNT=<storage-account>
```

## Build Commands

```bash
# Build only (no deploy)
make build-kind           # Generic KIND
make build-kind-ryzen     # Per-host KIND
make build-kind-thinkpad
make build-talos          # Production
make build-hub            # Multi-cluster hub

# Build all environments
make build-all
```

## Adding a New Application

### Helm-based application

Create an ArgoCD Application in the appropriate location:

```yaml
# base/apps/my-app.yaml
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
    repoURL: 'https://charts.example.com/'
    targetRevision: 1.0.0
    chart: my-app
    helm:
      releaseName: my-app
      valuesObject:
        # Inline values
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Manifest-based application

1. Create manifest directory: `base/manifests/my-app/`
2. Add K8s resources to the directory
3. Create ArgoCD Application using `cnoe://` URL:

```yaml
# base/apps/my-app.yaml
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
    server: 'https://kubernetes.default.svc'
    namespace: my-app
  syncPolicy:
    automated: {}
```

### Environment-specific application

Place the application in the appropriate component:
- `components/kind-only/` - Local development only
- `components/talos-only/` - Production only
- `components/tailscale-serve/` - All environments (Tailscale proxy)
- `components/observability/` - All environments (monitoring)

## Sync Wave Order

Applications are deployed in order based on sync wave annotations:

| Wave | Category | Examples |
|------|----------|----------|
| -100 | CRDs & Operators | cert-manager, external-secrets |
| -80 | Namespaces & RBAC | *-namespace apps |
| -60 | Secret stores | ClusterSecretStore, ExternalSecret |
| -40 | Databases & Caches | PostgreSQL, Redis |
| -20 | Infrastructure | Keycloak, Gitea |
| 0 | Applications | Default |
| 20 | Config jobs | Token sync, webhooks |
| 40 | Main apps | Backstage, Argo Workflows |
| 60 | Ingress | Tailscale serve, Ingress |

## Validation

```bash
# Validate KIND output
make validate-kind

# Dry run against cluster
kubectl apply --dry-run=client -f dist/kind/
```

## Troubleshooting

### External Secrets not syncing

Check JWKS sync:
```bash
# Verify JWKS in Azure Storage
curl -s https://<storage-account>.z13.web.core.windows.net/openid/v1/jwks | jq

# Re-sync JWKS
../ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh
```

### ArgoCD can't reach Gitea

Check CA trust:
```bash
kubectl get configmap argocd-tls-certs-cm -n argocd -o yaml
kubectl rollout restart deployment argocd-repo-server -n argocd
```

### Apps stuck in OutOfSync

```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Force sync
argocd app sync <app-name> --insecure
```
