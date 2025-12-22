# Quickstart: Tailscale Services Migration

**Feature**: 101-improve-tailscale
**Date**: 2025-12-04

This guide walks through deploying Tailscale Services for stable remote access to Kubernetes cluster services.

## Prerequisites

- [ ] Tailscale Admin Console access (admin role)
- [ ] Azure Key Vault access (to update secrets)
- [ ] Local kubectl access to the cluster
- [ ] Tailscale CLI on a connected device (for testing)

## Step 1: Configure Tailscale Admin Console (One-Time)

### 1.1 Update ACL Policy

Navigate to **Access Controls** in Tailscale Admin Console.

**Current ACL** (for reference):
```json
{
    "tagOwners": {
        "tag:k8s-operator": ["vpittamp@github"],
        "tag:k8s":          ["tag:k8s-operator", "vpittamp@github"],
    },
    "autoApprovers": {
        "routes": {
            "10.244.0.0/16": ["tag:k8s", "vpittamp@github"],
            "10.96.0.0/16":  ["tag:k8s", "vpittamp@github"],
        },
    },
    // ... acls, grants, ssh sections ...
}
```

**Updated ACL** (add the highlighted sections):
```json
{
    "tagOwners": {
        "tag:k8s-operator": ["vpittamp@github"],
        "tag:k8s":          ["tag:k8s-operator", "vpittamp@github"],
        // ▼▼▼ NEW: Add this line ▼▼▼
        "tag:k8s-services": ["vpittamp@github"],
    },
    "autoApprovers": {
        "routes": {
            "10.244.0.0/16": ["tag:k8s", "vpittamp@github"],
            "10.96.0.0/16":  ["tag:k8s", "vpittamp@github"],
        },
        // ▼▼▼ NEW: Add this block ▼▼▼
        "services": {
            "svc:argocd-ryzen":       ["tag:k8s-services"],
            "svc:argocd-thinkpad":    ["tag:k8s-services"],
            "svc:langfuse-ryzen":     ["tag:k8s-services"],
            "svc:langfuse-thinkpad":  ["tag:k8s-services"],
            "svc:k8s-api-ryzen":      ["tag:k8s-services"],
            "svc:k8s-api-thinkpad":   ["tag:k8s-services"],
        },
    },
    "acls": [
        // ... existing acl rules ...

        // ▼▼▼ NEW: Add these rules at the end ▼▼▼
        {
            "action": "accept",
            "src":    ["vpittamp@github"],
            "dst":    ["tag:k8s-services:*"],
        },
        {
            "action": "accept",
            "src":    ["tag:k8s-services"],
            "dst":    ["tag:k8s:*", "tag:k8s-operator:*", "vpittamp@github:*"],
        },
    ],
    // ... grants, ssh sections unchanged ...
}
```

### 1.2 Define Services

Navigate to **Services** (beta) in the left sidebar and create:

**Service 1: ArgoCD**
- Name: `argocd-ryzen` and `argocd-thinkpad`
- Description: ArgoCD GitOps Dashboard
- Endpoint: `tcp:443`

**Service 2: Langfuse**
- Name: `langfuse-ryzen` and `langfuse-thinkpad`
- Description: Langfuse LLM Observability
- Endpoint: `tcp:443`

**Service 3 (Optional): K8s API**
- Name: `k8s-api-ryzen` and `k8s-api-thinkpad`
- Description: Kubernetes API Server Proxy
- Endpoint: `tcp:443`

### 1.3 Generate Tagged Auth Key

Navigate to **Settings → Keys → Generate auth key**:

- [x] Reusable
- [x] Ephemeral
- Tags: `tag:k8s-services`

**Save the key** - you'll need it for Step 2.

> **Note**: The auto-approvers configured in Step 1.1 will automatically approve service advertisements from devices using this tagged auth key.

## Step 2: Update Azure Key Vault

Update the `tailscale-auth-key` secret with the new tagged auth key:

```bash
# Using Azure CLI
az keyvault secret set \
  --vault-name <your-vault-name> \
  --name tailscale-auth-key \
  --value "<your-new-tagged-auth-key>"
```

Or update via Azure Portal:
1. Navigate to Key Vault → Secrets
2. Select `tailscale-auth-key`
3. Create new version with the new key value

## Step 3: Deploy Updated Charts

### 3.1 Synthesize CDK8s Charts

```bash
cd cdk8s
npx ts-node main-v2.ts
```

### 3.2 Deploy via ArgoCD

The changes will be picked up by ArgoCD automatically. To force sync:

```bash
# Using ArgoCD CLI (with cluster-menu.sh sourced)
source deployment/scripts/cluster-menu.sh
argocd-sync argocd/argocd-tailscale-serve
argocd-sync argocd/langfuse-tailscale-serve
```

### 3.3 Trigger Secret Refresh

The ExternalSecret will sync within its refresh interval (1h default). To force immediate sync:

```bash
# Delete the secret to trigger immediate resync
kubectl delete secret tailscale-auth-key -n tailscale
# ExternalSecretOperator will recreate it from Key Vault
```

## Step 4: Verify Deployment

### 4.1 Check Pod Status

```bash
kubectl get pods -n tailscale -l app.kubernetes.io/part-of=argocd
kubectl get pods -n tailscale -l app.kubernetes.io/part-of=langfuse
```

Expected output:
```
NAME                                     READY   STATUS    RESTARTS   AGE
argocd-tailscale-serve-xxx               1/1     Running   0          1m
langfuse-tailscale-serve-xxx             1/1     Running   0          1m
```

### 4.2 Check Pod Logs

```bash
kubectl logs -n tailscale -l app.kubernetes.io/name=argocd-tailscale-serve --tail=20
```

Expected output includes:
```
tailscale serve running for ArgoCD service svc:argocd-<cluster>
```

### 4.3 Verify Service Registration

In Tailscale Admin Console → **Services**:
- `argocd-<cluster>` should show as "Active"
- `langfuse-<cluster>` should show as "Active"

### 4.4 Test Access

From a Tailscale-connected device:

```bash
# Test ArgoCD
curl -sI https://argocd-<cluster>.<your-tailnet>.ts.net | head -5

# Test Langfuse
curl -sI https://langfuse-<cluster>.<your-tailnet>.ts.net | head -5
```

Expected: HTTP 200 or redirect response.

## Step 5: Test Cluster Recreation (Optional)

To verify hostname stability:

```bash
# 1. Note current URLs
echo "ArgoCD: https://argocd-<cluster>.<tailnet>.ts.net"
echo "Langfuse: https://langfuse-<cluster>.<tailnet>.ts.net"

# 2. Recreate cluster
idpbuilder delete --name localdev
idpbuilder create --package cdk8s/dist/

# 3. Wait for services to come up (~2-3 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-tailscale-serve -n tailscale --timeout=180s

# 4. Test same URLs - should still work!
curl -sI https://argocd-<cluster>.<tailnet>.ts.net | head -5
```

## Troubleshooting

### Service Not Appearing in Admin Console

**Symptom**: Pod running but service not visible in Tailscale Services.

**Check**:
1. Auth key has correct tag: `tag:k8s-services`
2. Auto-approver rule exists for `svc:<name>`
3. Pod logs show service registration attempt

### Authentication Errors

**Symptom**: Pod fails with auth errors.

**Check**:
1. Secret `tailscale-auth-key` exists in namespace
2. Key is reusable and ephemeral
3. Key has not expired

```bash
kubectl get secret tailscale-auth-key -n tailscale -o jsonpath='{.data.authKey}' | base64 -d
```

### Service URL Not Resolving

**Symptom**: `curl` times out or DNS fails.

**Check**:
1. Tailscale client connected on test device
2. Service is "Active" in Admin Console
3. Confirm the service identity is advertised: `tailscale status | grep svc:argocd-<cluster>`

### Langfuse Auth Callback Fails

**Symptom**: Langfuse login redirects to wrong URL.

**Fix**: Update Langfuse chart's `nextAuthUrl` to match new service URL:
```typescript
nextAuthUrl: 'https://langfuse-<cluster>.<tailnet>.ts.net'
```

## Rollback

If issues occur, revert to hostname-based access:

1. Update charts to remove `--service` flag
2. Redeploy: `npx ts-node main-v2.ts && argocd-sync argocd/argocd-tailscale-serve`
3. Access via old URLs: `argocd-ui-serve.<tailnet>.ts.net`

## Service URLs Reference

After successful deployment:

| Service | URL | Notes |
|---------|-----|-------|
| ArgoCD | `https://argocd-<cluster>.<tailnet>.ts.net` | GitOps Dashboard |
| Langfuse | `https://langfuse-<cluster>.<tailnet>.ts.net` | LLM Observability |
| K8s API | `https://k8s-api-<cluster>.<tailnet>.ts.net` | kubectl access (if enabled) |

Replace `<tailnet>` with your tailnet domain (e.g., `tail286401`).
