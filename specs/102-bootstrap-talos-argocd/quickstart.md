# Quickstart: GitOps Bootstrap for Talos Linux Cluster

**Branch**: `102-bootstrap-talos-argocd` | **Date**: 2025-12-06

This guide walks through bootstrapping a Talos Linux cluster with ArgoCD, External Secrets Operator, and Tailscale for secure remote access.

## Prerequisites

### Required Tools

- `talosctl` - Talos cluster management
- `kubectl` - Kubernetes CLI
- `helm` v3 - Helm package manager
- `az` CLI - Azure CLI (logged in)
- `jq` - JSON processor

### Verify Tools

```bash
# Check all tools are available
for tool in talosctl kubectl helm az jq; do
  command -v $tool >/dev/null 2>&1 || echo "Missing: $tool"
done
```

### Required Infrastructure

- **Talos Cluster**: Running 5-node cluster from feature 100 (3 CP + 2 workers)
- **Azure Key Vault**: With the following secrets:
  - `TAILSCALE-OAUTH-CLIENT-ID` - Tailscale OAuth client ID
  - `TAILSCALE-OAUTH-CLIENT-SECRET` - Tailscale OAuth client secret
  - `TAILSCALE-AUTH-KEY` - Tagged, reusable, ephemeral auth key
- **Azure Storage Account**: Configured for static website hosting (for OIDC JWKS)
- **Azure AD App Registration**: With federated credential for workload identity
- **Tailscale ACLs**: Tag owners and auto-approvers configured (see below)

### Tailscale ACL Configuration

Add to your Tailscale ACL configuration:

```json
{
  "tagOwners": {
    "tag:k8s-operator": ["autogroup:admin"],
    "tag:k8s-services": ["autogroup:admin"]
  },
  "autoApprovers": {
    "services": {
      "svc:argocd": ["tag:k8s-services"],
      "svc:k8s-api": ["tag:k8s-services"]
    }
  }
}
```

---

## Step 1: Verify Cluster Access

```bash
# Export kubeconfig from Talos
export KUBECONFIG=~/.kube/talos-cluster.yaml
talosctl kubeconfig --force

# Verify cluster access
kubectl get nodes
# Expected: 3 control-plane + 2 worker nodes in Ready state

# Verify CNI is ready
kubectl get pods -n kube-system -l k8s-app=cilium
# Expected: All pods Running
```

---

## Step 2: Set Environment Variables

```bash
# Azure configuration
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"  # For workload identity
export AZURE_KEYVAULT_NAME="your-keyvault-name"
export AZURE_STORAGE_ACCOUNT="your-storage-account"

# Git repository (for ArgoCD)
export GIT_REPO_URL="https://github.com/your-org/stacks.git"
export GIT_BRANCH="main"

# Tailscale
export TAILSCALE_TAILNET="tail286401"  # Your tailnet suffix
```

---

## Step 3: Run Bootstrap Script

```bash
# From repository root
cd stacks/main

# Run the bootstrap
./scripts/bootstrap-cluster.sh
```

### What the Script Does

1. **Phase 1: Install ArgoCD via Helm**
   - Adds argo Helm repository
   - Installs ArgoCD in `argocd` namespace
   - Waits for all pods to be ready

2. **Phase 2: Sync JWKS to Azure Storage**
   - Extracts OIDC keys from cluster
   - Creates openid-configuration document
   - Uploads to Azure Storage static website

3. **Phase 3: Apply Root Application**
   - Applies ArgoCD App-of-Apps root application
   - Triggers cascading deployment of all platform services

---

## Step 4: Verify Deployment

### ArgoCD Access

```bash
# Port-forward for initial access
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

# Open UI at https://localhost:8080
# Login: admin / <password from above>
```

### Check Application Status

```bash
# List all ArgoCD applications
kubectl get applications -n argocd

# Expected applications:
# - argocd-bootstrap (root)
# - external-secrets-operator
# - workload-identity-patch
# - cluster-secret-store
# - tailscale-secrets
# - tailscale-operator
# - k8s-api-tailscale-serve
# - argocd-tailscale-serve
```

### Verify External Secrets

```bash
# Check ClusterSecretStore
kubectl get clustersecretstore azure-keyvault-store
# Expected: Ready=True

# Check ExternalSecrets
kubectl get externalsecrets -A
# Expected: All with status SecretSynced

# Verify a synced secret
kubectl get secret tailscale-auth-key -n tailscale -o yaml
# Should have 'authKey' data key
```

### Verify Tailscale Services

```bash
# Check operator
kubectl get pods -n tailscale -l app.kubernetes.io/name=tailscale-operator
# Expected: Running

# Check serve pods
kubectl get pods -n tailscale
# Expected: k8s-api-tailscale-serve, argocd-tailscale-serve pods

# Check Tailscale device registration
kubectl logs -n tailscale deploy/tailscale-operator | grep -i "registered"
```

---

## Step 5: Access via Tailscale

Once bootstrap is complete, access services via Tailscale:

### ArgoCD UI

```bash
# From any Tailscale-connected device
open https://svc-argocd.${TAILSCALE_TAILNET}.ts.net
```

### kubectl Access

```bash
# Generate remote kubeconfig
./scripts/generate-remote-kubeconfig.sh > ~/.kube/talos-remote.yaml

# Use from any Tailscale-connected device
kubectl --kubeconfig ~/.kube/talos-remote.yaml get nodes
```

---

## Troubleshooting

### ArgoCD Not Installing

```bash
# Check Helm release
helm list -n argocd

# Check pod status
kubectl get pods -n argocd

# Check events
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

### JWKS Sync Failing

```bash
# Verify Azure login
az account show

# Check storage account access
az storage blob list \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --container-name '$web' \
  --auth-mode login

# Verify JWKS endpoint is accessible
curl https://${AZURE_STORAGE_ACCOUNT}.z13.web.core.windows.net/openid/v1/jwks
```

### ClusterSecretStore Not Ready

```bash
# Check status
kubectl describe clustersecretstore azure-keyvault-store

# Common issues:
# - "Principal not found": Federated credential subject mismatch
# - "JWKS key not found": Need to re-sync JWKS
# - "Unauthorized": Check ServiceAccount annotations

# Verify ServiceAccount annotations
kubectl get sa external-secrets -n external-secrets -o yaml | grep azure
```

### Tailscale Services Not Registering

```bash
# Check serve pod logs
kubectl logs -n tailscale deploy/argocd-tailscale-serve

# Common issues:
# - "ACL denied": Check tag:k8s-services ACL configuration
# - "Auth key invalid": Regenerate auth key with correct tags
# - "Cannot connect": Check Tailscale operator is healthy

# Verify ACL approval
# In Tailscale Admin Console > Machines, check for pending approvals
```

---

## Re-running Bootstrap

The bootstrap script is idempotent. Safe to re-run:

```bash
# Re-run after failure or cluster changes
./scripts/bootstrap-cluster.sh

# Force JWKS re-sync (after cluster rebuild)
./scripts/02-sync-jwks.sh --force
```

---

## Success Criteria Validation

| Criterion | Command | Expected |
|-----------|---------|----------|
| Bootstrap time | `time ./scripts/bootstrap-cluster.sh` | < 15 minutes |
| ArgoCD apps synced | `kubectl get app -n argocd` | All Synced/Healthy |
| Secret fetch time | Create ExternalSecret, measure | < 60 seconds |
| Tailscale access | `curl svc-argocd.<tailnet>.ts.net` | HTTP 200 |
| Idempotency | Re-run bootstrap | No errors |

---

## Next Steps

1. **Add Application Workloads**: Define additional ArgoCD Applications in `config/talos-applications.ts`
2. **Configure Additional Secrets**: Add ExternalSecrets for application credentials
3. **Enable Monitoring**: Deploy Prometheus/Grafana stack (separate feature)
4. **Backup Configuration**: Set up etcd backup to Hetzner Object Storage (separate feature)

---

## Reference Commands

```bash
# ArgoCD CLI setup
argocd login svc-argocd.${TAILSCALE_TAILNET}.ts.net --insecure --grpc-web

# Sync all applications
argocd app sync argocd-bootstrap --prune

# List all managed resources
argocd app resources argocd-bootstrap

# Force secret refresh
kubectl annotate externalsecret -n tailscale tailscale-auth-key \
  force-sync=$(date +%s) --overwrite
```
