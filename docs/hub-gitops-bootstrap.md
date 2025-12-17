# Hub Cluster GitOps Bootstrap Guide

Bootstrap ArgoCD, External Secrets Operator, and Tailscale on the hub cluster with Azure Workload Identity.

**Prerequisites**: Complete [hub-cluster-setup.md](hub-cluster-setup.md) first.

## Overview

This guide installs the platform software stack on the hub cluster:

| Component | Purpose |
|-----------|---------|
| ArgoCD | GitOps deployment controller |
| External Secrets Operator | Sync secrets from Azure Key Vault |
| Tailscale Operator | Remote kubectl access |
| Tailscale Services | Stable URLs for platform UIs |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Hub Cluster (Hetzner)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   ArgoCD    │  │     ESO     │  │   Tailscale Operator    │  │
│  │  (GitOps)   │  │  (Secrets)  │  │   (Remote Access)       │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                     │                │
│         ▼                ▼                     ▼                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Azure Workload Identity (OIDC)                 ││
│  │  Issuer: https://oidcissuerhub<id>.z13.web.core.windows.net ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                   ┌──────────────────┐
                   │  Azure Key Vault  │
                   │  (Secrets Store)  │
                   └──────────────────┘
```

## Prerequisites

### Required Azure Resources

| Resource | Purpose |
|----------|---------|
| Azure AD App Registration | Workload Identity client |
| Azure Storage Account | OIDC JWKS hosting (static website) |
| Azure Key Vault | Secrets storage |
| Federated Credentials | Trust relationship with K8s SA |

### Required Secrets in Azure Key Vault

| Secret Name | Purpose |
|-------------|---------|
| `TAILSCALE-AUTH-KEY` | Tagged auth key for Tailscale pods |
| `TAILSCALE-OAUTH-CLIENT-ID` | OAuth client for Tailscale Operator |
| `TAILSCALE-OAUTH-CLIENT-SECRET` | OAuth secret for Tailscale Operator |

### Required Tailscale ACL Configuration

Add to your Tailscale ACL policy:

```json
{
  "tagOwners": {
    "tag:k8s-operator": ["autogroup:admin"],
    "tag:k8s-services": ["autogroup:admin"]
  },
  "autoApprovers": {
    "services": {
      "svc:argocd-hub": ["tag:k8s-services"],
      "svc:k8s-api-hub": ["tag:k8s-services"]
    }
  }
}
```

### Environment Variables

Create `.env-files/talos.env`:

```bash
# Git Configuration
GIT_REPO_URL="https://github.com/PittampalliOrg/stacks.git"
GIT_BRANCH="108-hub-and-spoke"

# Tailscale
TAILSCALE_TAILNET="tail286401"

# Azure Workload Identity
SERVICE_ACCOUNT_ISSUER="https://oidcissuerhub<id>.z13.web.core.windows.net/"
AZURE_KEYVAULT_NAME="keyvault-<suffix>"
AZURE_TENANT_ID="<tenant-id>"
AZURE_CLIENT_ID="<app-registration-client-id>"
```

## Step 1: Configure OIDC Issuer

The Talos cluster must use an external OIDC issuer for Azure Workload Identity.

### 1.1 Update Talos Machine Config

Edit `talos-cluster/main/patches/controlplane/hub.yaml`:

```yaml
cluster:
  clusterName: hub-cluster
  allowSchedulingOnControlPlanes: true
  apiServer:
    extraArgs:
      service-account-issuer: https://oidcissuerhub<id>.z13.web.core.windows.net/
      service-account-jwks-uri: https://oidcissuerhub<id>.z13.web.core.windows.net/openid/v1/jwks
```

### 1.2 Apply Configuration

```bash
# Get hub IP
HUB_IP=$(hcloud server describe hub-cp-1 -o format='{{.PublicNet.IPv4.IP}}')

# Apply patch (no reboot required)
talosctl --talosconfig ~/.talos/hub-config --nodes $HUB_IP \
  patch mc --mode no-reboot --patch-file main/patches/controlplane/hub.yaml

# Restart affected pods to get new tokens
kubectl --kubeconfig ~/.kube/hub-config delete pods -n kube-system -l k8s-app=cilium
```

### 1.3 Sync JWKS to Azure Storage

```bash
# Extract JWKS from cluster
kubectl --kubeconfig ~/.kube/hub-config get --raw /openid/v1/jwks > /tmp/jwks.json

# Upload to Azure Storage static website
az storage blob upload \
  --account-name oidcissuerhub<id> \
  --container-name '$web' \
  --name openid/v1/jwks \
  --file /tmp/jwks.json \
  --content-type application/json

# Upload OIDC discovery document
cat > /tmp/openid-configuration.json << 'EOF'
{
  "issuer": "https://oidcissuerhub<id>.z13.web.core.windows.net/",
  "jwks_uri": "https://oidcissuerhub<id>.z13.web.core.windows.net/openid/v1/jwks",
  "response_types_supported": ["id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
EOF

az storage blob upload \
  --account-name oidcissuerhub<id> \
  --container-name '$web' \
  --name .well-known/openid-configuration \
  --file /tmp/openid-configuration.json \
  --content-type application/json
```

## Step 2: Install ArgoCD

### 2.1 Install via Helm

```bash
# Add ArgoCD repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create namespace
kubectl --kubeconfig ~/.kube/hub-config create namespace argocd

# Install ArgoCD
helm install argocd argo/argo-cd \
  --kubeconfig ~/.kube/hub-config \
  --namespace argocd \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true \
  --wait
```

### 2.2 Get Initial Admin Password

```bash
kubectl --kubeconfig ~/.kube/hub-config get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d
```

## Step 3: Install External Secrets Operator

### 3.1 Install via Helm

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --kubeconfig ~/.kube/hub-config \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --wait
```

### 3.2 Configure ServiceAccount for Workload Identity

```bash
kubectl --kubeconfig ~/.kube/hub-config patch serviceaccount external-secrets \
  -n external-secrets \
  --type=merge \
  -p '{
    "metadata": {
      "labels": {
        "azure.workload.identity/use": "true"
      },
      "annotations": {
        "azure.workload.identity/client-id": "<AZURE_CLIENT_ID>",
        "azure.workload.identity/tenant-id": "<AZURE_TENANT_ID>"
      }
    }
  }'
```

### 3.3 Create ClusterSecretStore

```bash
kubectl --kubeconfig ~/.kube/hub-config apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault-store
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: https://<AZURE_KEYVAULT_NAME>.vault.azure.net
      serviceAccountRef:
        name: external-secrets
        namespace: external-secrets
EOF
```

### 3.4 Verify ClusterSecretStore

```bash
kubectl --kubeconfig ~/.kube/hub-config get clustersecretstore azure-keyvault-store
# Status should show: Ready: True
```

## Step 4: Install Tailscale Operator

### 4.1 Create Tailscale Secrets

```bash
# Create namespace
kubectl --kubeconfig ~/.kube/hub-config create namespace tailscale

# Create ExternalSecret for OAuth credentials
kubectl --kubeconfig ~/.kube/hub-config apply -f - << 'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: operator-oauth
  namespace: tailscale
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: azure-keyvault-store
  target:
    name: operator-oauth
  data:
    - secretKey: client_id
      remoteRef:
        key: TAILSCALE-OAUTH-CLIENT-ID
    - secretKey: client_secret
      remoteRef:
        key: TAILSCALE-OAUTH-CLIENT-SECRET
EOF
```

### 4.2 Install Operator via Helm

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update

helm install tailscale-operator tailscale/tailscale-operator \
  --kubeconfig ~/.kube/hub-config \
  --namespace tailscale \
  --set oauth.clientId="$(kubectl --kubeconfig ~/.kube/hub-config get secret operator-oauth -n tailscale -o jsonpath='{.data.client_id}' | base64 -d)" \
  --set oauth.clientSecret="$(kubectl --kubeconfig ~/.kube/hub-config get secret operator-oauth -n tailscale -o jsonpath='{.data.client_secret}' | base64 -d)" \
  --set apiServerProxyConfig.mode=true \
  --wait
```

## Step 5: Deploy GitOps Applications

### 5.1 Synthesize CDK8s Manifests

```bash
cd ~/repos/PittampalliOrg/stacks/108-hub-and-spoke/cdk8s

# Source environment
source .env-files/talos.env

# Synthesize for Talos
npm run synth:talos
```

### 5.2 Apply Root Application

```bash
kubectl --kubeconfig ~/.kube/hub-config apply -f dist/talos/hub-cluster-secret-store.yaml
kubectl --kubeconfig ~/.kube/hub-config apply -f dist/talos/hub-eso-workload-identity.yaml
kubectl --kubeconfig ~/.kube/hub-config apply -f dist/talos/hub-tailscale-secrets.yaml
kubectl --kubeconfig ~/.kube/hub-config apply -f dist/talos/hub-tailscale-operator.yaml
kubectl --kubeconfig ~/.kube/hub-config apply -f dist/talos/hub-argocd-tailscale-serve.yaml
```

### 5.3 Verify Applications

```bash
kubectl --kubeconfig ~/.kube/hub-config get applications -n argocd
# All should show: Synced, Healthy
```

## Step 6: Verify Access

### 6.1 ArgoCD via Tailscale

```bash
# Test ArgoCD hub URL
curl -sk https://argocd-hub.tail286401.ts.net
# Should return ArgoCD HTML
```

### 6.2 kubectl via Tailscale

```bash
# Get remote kubeconfig
# The hub-operator provides kubectl access via Tailscale
kubectl --kubeconfig ~/.kube/hub-config get pods -n tailscale | grep hub-operator
```

## Troubleshooting

### OIDC Issuer Mismatch

**Symptom**: ClusterSecretStore shows `authentication failed`

**Cause**: Cluster using internal issuer instead of external Azure Storage URL

**Fix**:
```bash
# Check current issuer
kubectl --kubeconfig ~/.kube/hub-config get --raw /.well-known/openid-configuration | jq .issuer

# Should match: https://oidcissuerhub<id>.z13.web.core.windows.net/
# If not, re-apply Talos patch and restart pods
```

### Tailscale Service Not Working

**Symptom**: `svc:argocd-hub` shows "no Service hosts set up"

**Cause**: ACL auto-approver not triggered or pod missing tag

**Fix**:
```bash
# Check pod tags
tailscale status --json | jq '.Peer | to_entries[] | select(.value.HostName | contains("argocd-hub")) | .value.Tags'
# Should show: ["tag:k8s-services"]

# Restart pod to re-register
kubectl --kubeconfig ~/.kube/hub-config rollout restart deployment/argocd-hub-tailscale-serve -n tailscale
```

### TLS Proxy Error (502)

**Symptom**: ArgoCD returns HTTP 502 via Tailscale service

**Cause**: Chart bug - socat and tailscale serve port mismatch

**Fix**: Ensure using chart version with port 8080 fix:
```bash
# Verify deployment uses correct config
kubectl --kubeconfig ~/.kube/hub-config get deployment argocd-hub-tailscale-serve -n tailscale \
  -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -o "socat TCP-LISTEN:[0-9]*"
# Should show: socat TCP-LISTEN:8080 (NOT 443)
```

### ESO ServiceAccount Missing Annotations

**Symptom**: ClusterSecretStore can't authenticate to Azure

**Fix**:
```bash
# Verify annotations
kubectl --kubeconfig ~/.kube/hub-config get sa external-secrets -n external-secrets -o yaml | grep -A5 annotations

# Should show azure.workload.identity/client-id and tenant-id
```

## Service URLs

After successful setup, these URLs are available from any Tailscale-connected device:

| Service | URL |
|---------|-----|
| ArgoCD Hub | `https://argocd-hub.<tailnet>.ts.net` |
| Kubernetes API | Via `hub-operator` Tailscale device |

## Key Files Reference

| File | Purpose |
|------|---------|
| `cdk8s/.env-files/talos.env` | Environment configuration |
| `cdk8s/dist/talos/hub-*.yaml` | Generated ArgoCD Applications |
| `talos-cluster/main/patches/controlplane/hub.yaml` | Talos machine patch with OIDC config |
| `talos-cluster/secrets/hub-secrets.yaml` | Cluster secrets (encrypted) |

## Next Steps

After hub GitOps is running:

1. **Register Spoke Clusters**: Apply spoke-cluster-*.yaml and spoke-credentials-*.yaml
2. **Deploy Kargo**: Enable progressive delivery pipelines
3. **Configure Backstage**: Deploy developer portal

See [spoke-cluster-registration.md](spoke-cluster-registration.md) for spoke setup.
