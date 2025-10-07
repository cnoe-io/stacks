# Cluster Update Guide

## Cluster Management Functions

The cluster management functions are now maintained in the `stacks` repository for version control and portability.

### Quick Start

Source the cluster management functions in your shell:

```bash
# One-time setup: Add to ~/.bashrc
echo 'source ~/stacks/deployment/scripts/.bashrc-cluster' >> ~/.bashrc

# Or source manually in current session
source ~/stacks/deployment/scripts/cluster-menu.sh
```

### Available Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `cluster-synth` | `cls` | Synthesize CDK8s manifests only |
| `cluster-deploy` | `cld` | Create/deploy cluster from scratch |
| `cluster-update` | `clu` | Update existing cluster (idempotent) |
| `cluster-update-gum` | `clug` | Interactive update with gum UI |
| `cluster-recreate` | `clr` | Delete and recreate cluster |
| `cluster-status` | `clst` | Show cluster and ArgoCD status |
| `cluster-menu` | `clm` | Interactive management menu (requires gum) |

### Interactive Menu

The cluster menu (`clm`) provides an interactive UI for common operations:

```bash
./deployment/scripts/cluster-menu.sh
# or
clm
```

Menu options:
- **Synthesize Only** - Just run CDK8s synthesis
- **Update Cluster (idempotent)** - Synthesize and update existing cluster
- **Synthesize & Deploy** - Full deployment (with logs)
- **Synthesize & Deploy (with spinner)** - Full deployment (quiet with spinner)
- **Recreate Cluster** - Delete and recreate from scratch
- **Show Status** - Display cluster and ArgoCD status

### Implementation Details

The update function uses:
```bash
# Primary path: deploy-linux-ssh.sh (dynamically generates kind-config)
./deployment/scripts/deploy-linux-ssh.sh \
  --package "$STACKS_DIR/cdk8s/dist/" \
  --package "$STACKS_DIR/ref-implementation/"
```

This command is **idempotent** - it can be run multiple times safely:
- Creates resources that don't exist
- Updates resources that have changed
- Leaves unchanged resources alone
- ArgoCD handles the actual reconciliation

### Usage Workflow

1. **Make changes to CDK8s charts**
   ```bash
   cd ~/stacks/cdk8s
   # Edit charts...
   ```

2. **Update the cluster**
   ```bash
   clu
   # or use the menu
   clm
   ```

3. **Check status**
   ```bash
   clst
   ```

### Advanced Usage

**Update with manifest diff viewing:**
```bash
clu  # Will prompt to view diff
```

**Update in watch mode (keeps terminal open):**
```bash
cluw  # or: cluster-update --no-exit
```

**Interactive update with gum:**
```bash
clug  # or: cluster-update-gum
```

### Environment Variables

The functions automatically:
- Source environment variables from `~/stacks/.env-files/wi.env`
- Set `STACKS_DIR` (defaults to `$HOME/stacks`)
- Configure SSL certificates from `~/stacks/certs/ca-bundle-with-idpbuilder.crt`
- Clear WSL Docker variables if native Docker socket exists

Override the kubectl helper image (if needed):
```bash
export KUBECTL_IMAGE=registry.k8s.io/kubectl:v1.31.4
```

### Azure Authentication

Functions automatically check Azure authentication when needed:
- **With gum installed**: Interactive prompts with colored output
- **Without gum**: Fallback to basic prompts

To manually authenticate:
```bash
az login
```

### Optional: gum Installation

For the best interactive experience, install gum:
```bash
nix-env -iA nixpkgs.gum
```

Features with gum:
- Colored, styled output
- Interactive confirmations
- Spinners for long-running operations
- Better visual feedback

### Migration from NixOS Configuration

If you previously had cluster management in `/etc/nixos`, you can now remove it and use this version-controlled approach instead. Benefits:
- ✅ Version controlled in Git
- ✅ Portable across systems
- ✅ No NixOS rebuild needed for updates
- ✅ Can be modified without sudo
- ✅ Easier to review changes in pull requests

### Notes

- The cluster name is `localdev` (idpbuilder default)
- Kind config includes SSH port mappings for development
- Functions handle Docker socket detection automatically
- ArgoCD UI available at: https://argocd.cnoe.localtest.me:8443
- Manifest changes are tracked with git in `cdk8s/dist/.git`

### Troubleshooting

**Functions not available:**
```bash
# Re-source the functions
source ~/stacks/deployment/scripts/cluster-menu.sh
```

**Azure authentication errors:**
```bash
# Refresh Azure login
az login
```

**Cluster not found:**
```bash
# Create new cluster
cld
```

**gum not found:**
```bash
# Install gum for interactive features
nix-env -iA nixpkgs.gum

# Or use non-interactive versions
clu  # instead of clug
```
