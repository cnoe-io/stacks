# Quickstart: Consolidated Bootstrap for KIND and Talos Clusters

**Feature**: 106-consolidate-bootstrap-between
**Date**: 2025-12-07

## Overview

This guide shows how to use the unified bootstrap command for both KIND and Talos clusters. After consolidation, you'll use the same scripts regardless of cluster type.

---

## Prerequisites

### Required Tools

```bash
# Verify required tools are installed
kubectl version --client
az version
direnv version
node --version    # 18+ required
npm --version

# For KIND clusters
kind version

# For Talos clusters
talosctl version
```

### Azure Authentication

```bash
# Login to Azure (required for both cluster types)
az login

# Verify login
az account show
```

---

## Quick Start (TL;DR)

```bash
# 1. Navigate to project directory
cd /path/to/stacks

# 2. Allow direnv (auto-detects cluster type)
direnv allow

# 3. Run bootstrap
./scripts/bootstrap-cluster.sh --setup-azure

# That's it! Works for both KIND and Talos.
```

---

## Detailed Steps

### Step 1: Configure Environment File

Choose the appropriate environment file based on your cluster type:

**For KIND clusters** - Edit `.env-files/kind.env`:
```bash
# Verify KIND cluster is running
kind get clusters

# Edit environment file
vim .env-files/kind.env
```

**For Talos clusters** - Edit `.env-files/talos.env`:
```bash
# Verify Talos cluster is accessible
talosctl config info

# Edit environment file
vim .env-files/talos.env
```

### Step 2: Verify direnv Detection

```bash
# Navigate to project root
cd /path/to/stacks

# Allow direnv
direnv allow

# Verify cluster type detection
echo $CLUSTER_TYPE
# Output: "kind" or "talos"

echo $AZURE_CLIENT_ID
# Output: Your Azure AD app client ID
```

### Step 3: Run Bootstrap

**Full bootstrap with Azure setup** (first time or Azure infrastructure changes):
```bash
./scripts/bootstrap-cluster.sh --setup-azure
```

**Bootstrap without Azure setup** (subsequent runs):
```bash
./scripts/bootstrap-cluster.sh
```

**With options**:
```bash
# Skip JWKS sync (Talos only)
./scripts/bootstrap-cluster.sh --skip-jwks

# Force reinstall
./scripts/bootstrap-cluster.sh --force
```

---

## Verification Checklist

### Cluster Detection

```bash
# ✓ Cluster type correctly detected
echo $CLUSTER_TYPE
# Expected: "kind" or "talos"

# ✓ Environment file loaded
echo $AZURE_CLIENT_ID
# Expected: UUID (not empty)
```

### Azure Infrastructure

```bash
# ✓ Azure AD app exists (only one, no duplicates)
az ad app list --display-name "gitops-${CLUSTER_TYPE}-*" \
  --query "[].displayName" -o table

# ✓ Federated credentials created
az ad app federated-credential list --id "$(az ad app list \
  --display-name "gitops-${CLUSTER_TYPE}-${CLUSTER_NAME}" \
  --query "[0].id" -o tsv)" --query "[].name" -o table
```

### ArgoCD Deployment

```bash
# ✓ ArgoCD pods running
kubectl get pods -n argocd

# ✓ ArgoCD accessible
kubectl get ingress -n argocd
```

### External Secrets

```bash
# ✓ External Secrets controller running
kubectl get pods -n external-secrets

# ✓ ClusterSecretStore ready
kubectl get clustersecretstore azure-keyvault-store
```

---

## Switching Between Clusters

The unified bootstrap makes switching clusters simple:

```bash
# 1. Switch kubectl context
# For KIND:
kubectl config use-context kind-gitops

# For Talos:
kubectl config use-context admin@talos-cluster

# 2. Re-enter directory to reload environment
cd .. && cd stacks
# Or: direnv reload

# 3. Verify switch
echo $CLUSTER_TYPE
# Should match your new cluster type
```

---

## Common Operations

### Synthesize CDK8s Manifests Only

```bash
# For either cluster type
cd cdk8s
npm run synth
```

### Update Cluster Configuration

```bash
# Using cluster menu (after sourcing)
source deployment/scripts/cluster-menu-talos.sh  # For Talos
# or
source deployment/scripts/cluster-menu.sh        # For KIND

# Then use shortcuts:
tclu   # talos-cluster-update (synth + commit + push + sync)
# or
cluster-update  # KIND equivalent
```

### View Cluster Status

```bash
# Unified status command
./scripts/bootstrap-cluster.sh --status

# Or cluster-specific:
tclst  # Talos status
# or cluster-status for KIND
```

---

## Troubleshooting

### Cluster Type Not Detected

```bash
# Check kubectl context
kubectl config current-context

# If empty or wrong, set it:
kubectl config use-context kind-gitops
# or
kubectl config use-context admin@talos-cluster

# Force reload direnv
direnv reload
```

### Azure Authentication Failed

```bash
# Check Azure login status
az account show

# If expired or not logged in:
az login

# Verify subscription
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
```

### Environment Variables Missing

```bash
# Check which file is loaded
echo $CLUSTER_TYPE

# Verify file exists
ls -la .env-files/${CLUSTER_TYPE}.env

# Re-allow direnv
direnv allow
```

### Bootstrap Phase Failed

```bash
# Check which phase failed
cat scripts/.bootstrap-phase

# Resume from current phase
./scripts/bootstrap-cluster.sh

# Or start fresh
rm scripts/.bootstrap-phase
./scripts/bootstrap-cluster.sh --setup-azure
```

### CDK8s Synthesis Errors

```bash
# Check TypeScript compilation
cd cdk8s
npx tsc --noEmit

# Reinstall dependencies if needed
rm -rf node_modules
npm install

# Regenerate CRD imports
npm run import
```

---

## Environment File Reference

### Required Variables (Both Clusters)

| Variable | Description | Example |
|----------|-------------|---------|
| `CLUSTER_TYPE` | Cluster type identifier | `kind` or `talos` |
| `CLUSTER_NAME` | Cluster name | `gitops`, `talos-cluster` |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription | UUID |
| `AZURE_TENANT_ID` | Azure AD tenant | UUID |
| `AZURE_CLIENT_ID` | Azure AD app client ID | UUID |
| `AZURE_KEYVAULT_NAME` | Key Vault name | `keyvault-xxx` |
| `AZURE_STORAGE_ACCOUNT` | OIDC storage account | `oidcissuerxxx` |
| `SERVICE_ACCOUNT_ISSUER` | OIDC issuer URL (with /) | `https://xxx.z13.web.core.windows.net/` |

### Cluster-Specific Variables

| Variable | KIND | Talos |
|----------|------|-------|
| `GIT_REPO_URL` | `cnoe://` (idpBuilder) | GitHub URL |
| `INGRESS_HOST` | `cnoe.localtest.me` | `talos.cnoe.localtest.me` |
| `TLS_ISSUER` | (empty for self-signed) | `letsencrypt-prod` |

---

## Next Steps

After successful bootstrap:

1. **Access ArgoCD**:
   - KIND: `https://argocd.cnoe.localtest.me:8443`
   - Talos: `https://svc-argocd.<tailnet>.ts.net`

2. **View applications**: Check ArgoCD UI for synced applications

3. **Add new applications**: Modify `cdk8s/config/applications.ts` and run synthesis

4. **Update manifests**: Use cluster menu commands (`tclu` or `cluster-update`)
