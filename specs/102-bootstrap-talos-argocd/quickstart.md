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

Create a `.env` file from the template:

```bash
# Copy template and configure
cp scripts/.env.template scripts/.env

# Edit with your values
# Required variables:
#   AZURE_SUBSCRIPTION_ID - Your Azure subscription
#   AZURE_TENANT_ID - Your Azure AD tenant
#   AZURE_CLIENT_ID - App registration for Workload Identity
#   AZURE_KEYVAULT_NAME - Azure Key Vault name
#   AZURE_STORAGE_ACCOUNT - Storage account for OIDC JWKS
#   GIT_REPO_URL - Git repository URL for ArgoCD
#   GIT_BRANCH - Git branch (default: main)
#   TAILSCALE_TAILNET - Your tailnet suffix (e.g., tail286401)
```

Or set environment variables directly:

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
./scripts/bootstrap-cluster.sh

# Options:
#   --force       Force reinstall even if already installed
#   --skip-jwks   Skip JWKS sync (if Azure Storage already configured)
#   -h, --help    Show help message
```

### What the Script Does

1. **Prerequisite Validation**
   - Checks for required tools (talosctl, kubectl, helm, az, jq)
   - Validates Talos cluster access
   - Validates Azure login and storage account access

2. **Phase 1: Install ArgoCD via Helm**
   - Adds argo Helm repository
   - Installs ArgoCD in `argocd` namespace using values from `cdk8s/values/argocd-values.yaml`
   - Waits for all pods to be ready (argocd-server, argocd-repo-server, argocd-application-controller)

3. **Phase 2: Sync JWKS to Azure Storage**
   - Extracts OIDC JWKS from cluster (`kubectl get --raw /openid/v1/jwks`)
   - Generates OpenID Connect configuration document
   - Uploads to Azure Storage static website (`$web` container)
   - Verifies OIDC endpoint is accessible

4. **Phase 3: Apply Root Application**
   - Generates ArgoCD App-of-Apps root application manifest
   - Applies root application to cluster
   - Waits for initial sync and child applications to be created
   - Verifies all applications reach Synced state

### Idempotent Re-runs

The bootstrap script tracks progress and can resume from any phase:

```bash
# Resume after failure (continues from last completed phase)
./scripts/bootstrap-cluster.sh

# Force full re-bootstrap (re-runs all phases)
./scripts/bootstrap-cluster.sh --force
```

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

Once bootstrap is complete, access services via **Tailscale Services** (stable, predictable URLs).

### Stable Service URLs

```bash
export CLUSTER_NAME="${CLUSTER_NAME:-<cluster>}"     # e.g., ryzen | thinkpad
export TAILSCALE_TAILNET="${TAILSCALE_TAILNET:-<tailnet>}"  # e.g., tail286401

echo "ArgoCD UI: https://argocd-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net"
echo "K8s API:   https://k8s-api-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net"
```

### ArgoCD UI

```bash
# Open from any Tailscale-connected device
open "https://argocd-${CLUSTER_NAME:-<cluster>}.${TAILSCALE_TAILNET:-<tailnet>}.ts.net"
```

### kubectl Access

```bash
# Generate remote kubeconfig
./scripts/generate-remote-kubeconfig.sh > ~/.kube/talos-remote.yaml

# Use from any Tailscale-connected device
kubectl --kubeconfig ~/.kube/talos-remote.yaml get nodes
```

**Note:** Service URLs are stable. If a URL doesn’t work, verify the service is defined in Tailscale Admin Console → Services and that ACL auto-approvers allow `svc:<name>` from `tag:k8s-services`.

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

# Verify JWKS endpoint is accessible (replace .z13 with your storage region)
curl https://${AZURE_STORAGE_ACCOUNT}.z13.web.core.windows.net/openid/v1/jwks

# Force re-sync JWKS after cluster rebuild
./scripts/02-sync-jwks.sh --force
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

## Known Issues and Fixes (T067 Bootstrap Test)

This section documents issues found during full bootstrap testing on December 7, 2025.

### Issue 1: Talos API Server Service-Account-Issuer Mismatch

**Symptom**: ClusterSecretStore shows `InvalidProviderConfig` with error:
```
AADSTS700211: No matching federated identity record found for presented assertion issuer 'https://10.0.1.1:6443'
```

**Cause**: Talos defaults `service-account-issuer` to the API server's internal IP, but Azure Workload Identity expects the OIDC issuer URL (`https://oidcissuer65846b7df97b.z13.web.core.windows.net/`).

**Fix**: Patch Talos machine config to use the Azure Storage static website URL as the issuer:
```bash
# Via Tailscale SSH to Hetzner host, then to Talos nodes
talosctl -n 10.0.1.1,10.0.1.2,10.0.1.3 patch mc --patch '[{
  "op": "add",
  "path": "/cluster/apiServer/extraArgs",
  "value": {
    "service-account-issuer": "https://oidcissuer65846b7df97b.z13.web.core.windows.net/"
  }
}]'
```

The API server will restart automatically. This patch is already included in `talos-cluster/main/patches/controlplane/all.yaml`.

### Issue 2: Cilium CNI Pods Not Ready After API Server Restart

**Symptom**: All Cilium pods show `0/1 Running` with logs showing:
```
Establishing connection to apiserver host="https://localhost:7445"
```

**Cause**: After patching the API server `service-account-issuer`, the API server restarts. Cilium pods fail to reconnect to the Talos API proxy.

**Fix**: Restart the Cilium DaemonSet and operator:
```bash
kubectl rollout restart daemonset cilium -n kube-system
kubectl rollout restart deployment cilium-operator -n kube-system
```

Wait ~45 seconds for pods to become ready.

### Issue 3: ServiceAccount Missing Azure Annotations

**Symptom**: ClusterSecretStore shows `InvalidProviderConfig` with error:
```
missing service account annotation: azure.workload.identity/client-id
unable to resolve an endpoint: ... Tenant 'v2.0' not found
```

**Cause**: CDK8s synthesis used default empty values for `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` when environment variables weren't set.

**Fix**: Patch the ServiceAccount with correct Azure credentials:
```bash
kubectl patch sa external-secrets -n external-secrets --type='merge' -p '{
  "metadata": {
    "annotations": {
      "azure.workload.identity/client-id": "<YOUR_CLIENT_ID>",
      "azure.workload.identity/tenant-id": "<YOUR_TENANT_ID>"
    }
  }
}'
kubectl rollout restart deployment -n external-secrets
```

**Prevention**: Always source environment variables before CDK8s synthesis:
```bash
set -a && source scripts/.env && set +a
cd cdk8s && npm run synth:talos
```

### Issue 4: ClusterSecretStore Wrong Key Vault Name

**Symptom**: ClusterSecretStore shows `Valid` but ExternalSecrets fail to sync.

**Cause**: CDK8s config used default value `talos-keyvault` instead of actual vault name from `AZURE_KEYVAULT_NAME`.

**Fix**: Patch the ClusterSecretStore:
```bash
kubectl patch clustersecretstore azure-keyvault-store --type='merge' -p '{
  "spec": {
    "provider": {
      "azurekv": {
        "vaultUrl": "https://<YOUR_KEYVAULT_NAME>.vault.azure.net"
      }
    }
  }
}'
```

**Prevention**: Verify environment variables are set during CDK8s synthesis.

### Issue 5: ESO Controller Caching Stale SecretStore Status

**Symptom**: ExternalSecrets show `SecretSyncedError: the desired SecretStore is not ready` even though `kubectl get clustersecretstore` shows `Valid`.

**Cause**: ESO controller pods started before ClusterSecretStore was patched and cached the old invalid status.

**Fix**: Restart the ESO controller:
```bash
kubectl rollout restart deployment external-secrets -n external-secrets
```

### Issue 6: Tailscale Serve CLI Flag Changes

**Symptom**: Tailscale serve pods show `flag provided but not defined: -insecure` error.

**Cause**: Tailscale CLI removed the `--insecure` flag. The new syntax uses URL prefixes like `https+insecure://` for self-signed backends.

**Fix**: Updated in CDK8s charts. For ArgoCD serve, use HTTP backend since ArgoCD HA mode exposes HTTP on port 80.

### Issue 7: Tailscale Serve Only Supports Localhost Proxies

**Symptom**: Tailscale serve shows `only localhost or 127.0.0.1 proxies are currently supported`.

**Cause**: Tailscale serve can only proxy to localhost, not remote Kubernetes services.

**Fix**: Use socat to forward from localhost to the backend service:
```bash
# Example: Forward localhost:8080 to ArgoCD backend
socat TCP-LISTEN:8080,fork,reuseaddr TCP:argocd-server.argocd.svc.cluster.local:80 &
tailscale serve --bg --service=svc:argocd --https=443 http://127.0.0.1:8080
```

**Prevention**: The CDK8s charts now include socat proxy for Tailscale serve deployments.

### Issue 8: ArgoCD HA Mode Uses HTTP Not HTTPS

**Symptom**: Tailscale serve pod can't connect to ArgoCD on HTTPS port 443.

**Cause**: ArgoCD in HA mode (with Redis HA and HAProxy) exposes HTTP on port 80, not HTTPS on 443. The HAProxy terminates TLS externally.

**Fix**: Connect to ArgoCD backend on HTTP port 80:
```bash
curl -s http://argocd-server.argocd.svc.cluster.local:80/healthz
# Returns: ok
```

**Prevention**: The CDK8s chart defaults to `backendPort: 80` and `backendHttps: false`.

### Issue 9: Tailscale Service Host Not Approved / Service Not Defined

**Symptom**: The service URL (e.g., `https://argocd-<cluster>.<tailnet>.ts.net`) doesn’t resolve or returns errors, and pod logs show a warning like "service host not yet approved".

**Cause**: One of the following is missing:
- The service definition in Tailscale Admin Console → **Services** (Beta)
- ACL `autoApprovers.services` entries for `svc:<serviceName>` (e.g., `svc:argocd-ryzen`) mapped to `tag:k8s-services`
- An auth key tagged with `tag:k8s-services`

**Fix**:
1. In Tailscale Admin Console, create/verify the service (e.g., `argocd-ryzen`, `k8s-api-thinkpad`)
2. Update ACLs to auto-approve the matching `svc:<name>` entries
3. Ensure the auth key used by the pods has `tag:k8s-services`
4. Restart the serve deployment and re-check logs:
   ```bash
   kubectl rollout restart -n tailscale deploy/argocd-tailscale-serve
   kubectl logs -n tailscale deploy/argocd-tailscale-serve --tail=50
   ```

**Prevention**: Keep the Tailscale Services list and ACL `autoApprovers.services` in sync with the service names generated by this repo (`<service>-<cluster>`).

### Recommended Bootstrap Order

After fixing these issues, the recommended order is:

1. **Patch Talos** `service-account-issuer` in controlplane config
2. **Sync JWKS** to Azure Storage (`02-sync-jwks.sh`)
3. **Source environment** before CDK8s synthesis
4. **Install ArgoCD** via Helm
5. **Apply root application** (triggers ESO, Tailscale deployments)
6. If needed, **patch ServiceAccount** and **ClusterSecretStore**
7. **Restart Cilium** if pods are stuck after API server restart
8. **Restart ESO** if ExternalSecrets don't sync
9. **Approve Tailscale Services** in Tailscale Admin Console if required

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
| Tailscale access | `curl argocd-<cluster>.<tailnet>.ts.net` | HTTP 200 |
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
argocd login argocd-${CLUSTER_NAME:-<cluster>}.${TAILSCALE_TAILNET}.ts.net --insecure --grpc-web

# Sync all applications
argocd app sync argocd-bootstrap --prune

# List all managed resources
argocd app resources argocd-bootstrap

# Force secret refresh
kubectl annotate externalsecret -n tailscale tailscale-auth-key \
  force-sync=$(date +%s) --overwrite
```
