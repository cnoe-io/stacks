# Deployment Scripts and Configuration

This directory contains all cluster deployment and management scripts, separating deployment logic from application manifests.

## Directory Structure

```
deployment/
├── scripts/
│   ├── cluster-menu.sh           # Main cluster management functions
│   ├── deploy-linux-ssh.sh       # idpbuilder deployment with Azure integration
│   └── .bashrc-cluster           # Shell initialization snippet
└── config/
    └── (dynamically generated)   # Config files created by scripts at runtime
```

## Quick Start

### 1. Source Cluster Functions

Add to your `~/.bashrc`:

```bash
source ~/stacks/deployment/scripts/.bashrc-cluster
```

Or source manually:

```bash
source ~/stacks/deployment/scripts/cluster-menu.sh
```

### 2. Available Commands

| Command              | Alias  | Description                          |
| -------------------- | ------ | ------------------------------------ |
| `cluster-synth`      | `cls`  | Synthesize CDK8s manifests           |
| `cluster-deploy`     | `cld`  | Create/deploy cluster                |
| `cluster-update`     | `clu`  | Update existing cluster (idempotent) |
| `cluster-update-gum` | `clug` | Interactive update with gum UI       |
| `cluster-recreate`   | `clr`  | Delete and recreate cluster          |
| `cluster-status`     | `clst` | Show cluster status                  |
| `cluster-menu`       | `clm`  | Interactive menu                     |

### 3. Deploy Cluster

```bash
# Simple deployment
cld

# Or run the script directly
./deployment/scripts/deploy-linux-ssh.sh \
  --package cdk8s/dist/ \
  --package ref-implementation/
```

## Scripts

### cluster-menu.sh

Main cluster management functions with:

- All cluster operations (synth, deploy, update, recreate, status)
- Interactive menu with gum support
- Azure authentication checks (optional for local dev)
- Manifest diff tracking
- Aliases for quick access

**Functions:**

- `cluster-synth` - Synthesize CDK8s manifests
- `cluster-deploy` - Full deployment workflow
- `cluster-update` - Idempotent cluster update
- `cluster-update-gum` - Interactive update with gum
- `cluster-recreate` - Delete and recreate from scratch
- `cluster-status` - Show cluster and ArgoCD status
- `cluster-menu` - Interactive menu (requires gum)

**Local Development (Skip Azure Auth):**

For local Kind clusters without Azure integration:

```bash
# Option 1: Export for current session
export SKIP_AZURE_AUTH=true
./deployment/scripts/cluster-menu.sh

# Option 2: Inline for single command
SKIP_AZURE_AUTH=true cld

# Option 3: Add to your shell profile for persistent skip
echo 'export SKIP_AZURE_AUTH=true' >> ~/.bashrc
```

This skips Azure authentication checks, useful when:

- Developing locally with Kind clusters
- Not using Azure External Secrets integration
- Testing without cloud credentials

### deploy-linux-ssh.sh

Specialized deployment script that:

- Generates service account keys for Azure Workload Identity
- Creates Kind cluster configuration dynamically
- Mounts keys directly into Kind cluster
- Syncs JWKS to Azure for External Secrets
- Configures SSH port mappings for dev containers
- Integrates with idpbuilder for package deployment

**Key Features:**

- Azure Workload Identity integration
- Direct key mounting (no post-creation copying)
- SSH NodePort support (ports 30022-30027)
- Certificate management
- Azure authentication checks

**Usage:**

```bash
./deployment/scripts/deploy-linux-ssh.sh \
  --package cdk8s/dist/ \
  --package ref-implementation/
```

### .bashrc-cluster

Shell initialization snippet that:

- Sources cluster-menu.sh
- Shows confirmation message
- Sets up aliases

## Configuration

### Dynamically Generated

The `deploy-linux-ssh.sh` script generates configuration files at runtime:

**kind-config.yaml** (created in deployment/config/)

- Generated with current `KEYS_DIR` path and `SERVICE_ACCOUNT_ISSUER` from wi.env
- Minimal configuration that adds only Azure Workload Identity to idpbuilder defaults
- Mounts service account keys for custom OIDC issuer

### Environment Variables

The scripts use these environment variables:

- `STACKS_DIR` - Base directory (defaults to `$HOME/stacks`)
- `SERVICE_ACCOUNT_ISSUER` - Azure OIDC issuer URL
- `AZURE_STORAGE_ACCOUNT` - Azure storage account name
- `RESOURCE_GROUP` - Azure resource group
- `SSL_CERT_FILE` - Custom CA bundle path

Load from `.env-files/wi.env`:

```bash
source ~/stacks/.env-files/wi.env
```

## Integration

### With ref-implementation/

Deployment scripts package and deploy manifests from:

- `cdk8s/dist/` - Synthesized CDK8s manifests
- `ref-implementation/` - ArgoCD applications and configs

### With Azure Workload Identity

Scripts integrate with Azure via:

- `ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh`
- `ref-implementation/azure-workload-identity/keys/` - Service account keys
- Dynamic JWKS syncing after cluster creation

## Workflow

### Development Workflow

1. **Make changes** to CDK8s charts
2. **Synthesize**: `cls`
3. **Update cluster**: `clu`
4. **Check status**: `clst`

### Full Deployment

1. **Ensure Azure login**: `az login`
2. **Deploy**: `cld`
3. **Monitor**: Check ArgoCD UI at https://argocd.cnoe.localtest.me:8443

### Recreate Cluster

```bash
clr  # Delete and recreate fresh
```

## Dependencies

**Required:**

- `idpbuilder` - CNOE tool for local Kubernetes
- `kubectl` - Kubernetes CLI
- `kind` - Kubernetes in Docker
- `npm` - For CDK8s synthesis
- `az` - Azure CLI (for Workload Identity)

**Optional:**

- `gum` - Better interactive UI
- `bat` - Syntax-highlighted diff viewing

## Troubleshooting

**Functions not available:**

```bash
source ~/stacks/deployment/scripts/cluster-menu.sh
```

**Azure auth errors:**

```bash
az login
```

**Config file not found:**
The config file is generated dynamically by `deploy-linux-ssh.sh`. If using idpbuilder directly, the script will generate it on the fly.

## Migration from Previous Structure

Files moved from various locations to `deployment/`:

**From root:**

- `cluster-menu.sh` → `deployment/scripts/cluster-menu.sh`
- `.bashrc-cluster` → `deployment/scripts/.bashrc-cluster`

**From ref-implementation:**

- `deploy-linux-ssh.sh` → `deployment/scripts/deploy-linux-ssh.sh`
- `kind-config-linux-ssh.yaml` → Removed (now generated dynamically)

## Benefits

✅ **Clear Separation**: Deployment logic separated from manifests
✅ **Modular**: Scripts organized by function
✅ **Version Controlled**: All deployment logic in Git
✅ **Portable**: Self-contained deployment directory
✅ **No Duplication**: Single kind-config generated dynamically

## See Also

- `CLUSTER_UPDATE_GUIDE.md` - Detailed usage guide
- `docs/NIXOS_CLUSTER_MANAGEMENT_MIGRATION.md` - Migration from NixOS config
- `ref-implementation/azure-workload-identity/` - Azure integration files
