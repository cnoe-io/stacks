# Kustomize Packages

This directory contains Kustomize-based ArgoCD application definitions.

Based on the [cnoe-io/stacks reference implementation](https://github.com/cnoe-io/stacks/tree/main/ref-implementation).

## Quick Start

### Full Cluster Management (Recommended)

Use the cluster-menu.sh script for complete cluster lifecycle management:

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

## Directory Structure

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
└── overlays/               # Environment configurations
    ├── kind/               # Generic KIND cluster
    ├── kind-ryzen/         # KIND on Ryzen host
    ├── kind-thinkpad/      # KIND on Thinkpad host
    ├── talos/              # Production Talos cluster
    └── hub/                # Hub multi-cluster management
```

## Application Structure

Applications are managed natively by ArgoCD which runs Kustomize on the repository. 
When adding a new app:

1. Add your manifests to `packages/base/manifests/<app>` (or in a component).
2. Create an ArgoCD `Application` in `packages/base/apps/<app>.yaml` that points to the manifest directory.
3. Include the `Application` manifest in `packages/base/kustomization.yaml`.
