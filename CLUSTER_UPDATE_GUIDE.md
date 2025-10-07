# Cluster Update Guide

## New Cluster Management Functions

### Overview
Added idempotent cluster update functionality to the cluster management tools. The `idpbuilder create` command is idempotent and uses eventual consistency, allowing safe repeated execution.

### Available Commands

#### `cluster-update` / `clu`
Updates the cluster with the latest CDK8s charts without recreating it.

```bash
# Basic usage
cluster-update

# Short alias
clu
```

**What it does:**
1. Sources environment files (`wi.env`)
2. Synthesizes CDK8s manifests (`npm run synth`)
3. Runs idpbuilder create with existing cluster (idempotent)
4. Shows ArgoCD application sync status

#### Interactive Menu
The cluster menu (`clm`) now includes an "Update Cluster (idempotent)" option:

```bash
clm
```

Menu options:
- **Synthesize Only** - Just run CDK8s synthesis
- **Update Cluster (idempotent)** - Synthesize and update existing cluster
- **Synthesize & Deploy** - Full deployment (with spinner or logs)
- **Recreate Cluster** - Delete and recreate from scratch
- **Show Status** - Display cluster and ArgoCD status

### Command Reference

| Command | Alias | Description |
|---------|-------|-------------|
| `cluster-synth` | `cls` | Synthesize CDK8s manifests only |
| `cluster-deploy` | `cld` | Create/deploy cluster from scratch |
| `cluster-update` | `clu` | Update existing cluster (idempotent) |
| `cluster-recreate` | `clr` | Delete and recreate cluster |
| `cluster-status` | `clst` | Show cluster and ArgoCD status |
| `cluster-menu` | `clm` | Interactive management menu |

### Implementation Details

The update function uses:
```bash
# Primary path: deploy-linux-ssh.sh (with kind-config-linux-ssh.yaml)
./deploy-linux-ssh.sh \
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

### Notes

- The functions are loaded automatically in new shell sessions
- Environment variables are sourced from `~/stacks/.env-files/wi.env`
- The cluster name is `localdev` (IDPBuilder default)
- Kind config includes SSH port mappings for development
- Override the kubectl helper image (if needed) by exporting `KUBECTL_IMAGE`
  before running `clu`/`clm`; defaults to `registry.k8s.io/kubectl:v1.31.4`.
- If you previously deployed the legacy CoreDNS rewrite package, run
  `~/stacks/scripts/remove-core-dns-package.sh` once before the next
  `cluster-update` or `cluster-recreate` run. This removes the old
  custom package so IDPBuilder can manage CoreDNS natively.

### Activation

After NixOS rebuild, start a new shell session to use the functions:
```bash
# The functions are automatically loaded
# You'll see: 🎯 Cluster functions loaded: cluster-synth, cluster-deploy, cluster-update, cluster-recreate, cluster-status, cluster-menu
```

## Recent Changes

### AgentGateway Integration
Added comprehensive AgentGateway/kgateway support via CDK8s:

1. **kgateway-agentgateway-chart.ts**
   - AgentGateway Backend with A2A and MCP support
   - Authentication with External Secrets
   - Gateway resources and TLS configuration

2. **kgateway-ai-services-chart.ts**
   - OpenAI and Anthropic Backend resources
   - HTTPRoute for AI service routing
   - 1Password integration for API keys

These charts are now included in the CDK8s synthesis and will be deployed/updated with the cluster commands.
