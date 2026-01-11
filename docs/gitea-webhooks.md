# Gitea System Webhooks

This document describes the declarative system webhook configuration for ArgoCD and Kargo, enabling instant GitOps syncs on every push to Gitea.

## Overview

Instead of relying on polling (3-5 minute delays), we use **Gitea system webhooks** that fire on every push to ANY repository. This triggers immediate syncs in both ArgoCD and Kargo.

```
┌─────────────────────────────────────────────────────────────┐
│         Gitea System Webhooks (fire for ALL repos)          │
└─────────────────────────────────────────────────────────────┘
           │ push event                    │ push event
           ▼                               ▼
┌─────────────────────────┐    ┌─────────────────────────────┐
│ ArgoCD Server           │    │ Kargo Webhooks Server       │
│ /api/webhook            │    │ /webhooks/gitea/<hash>      │
│ → Refreshes all apps    │    │ → Refreshes all Warehouses  │
└─────────────────────────┘    └─────────────────────────────┘
```

## Components

### 1. ArgoCD Webhook Setup

**App**: `argocd-webhook-setup`
**Namespace**: `argocd`
**Sync Wave**: `80`

Creates a Gitea system webhook pointing to ArgoCD's webhook endpoint.

| Resource | Purpose |
|----------|---------|
| `ExternalSecret` | Fetches Gitea admin credentials (username/password) |
| `ConfigMap` | Shell script to create system webhook via admin API |
| `Job` (PostSync) | Executes webhook creation, idempotent |

**Webhook URL**: `http://argocd-server.argocd.svc.cluster.local/api/webhook`

### 2. Kargo Webhook Sync

**App**: `kargo-webhook-sync`
**Namespace**: `kargo`
**Sync Wave**: `80`

Creates a Gitea system webhook pointing to Kargo's ClusterConfig webhook receiver.

| Resource | Purpose |
|----------|---------|
| `ExternalSecret` | Fetches Gitea admin credentials |
| `Secret` | Kargo webhook secret for payload validation |
| `ConfigMap` | Shell script to create system webhook |
| `Job` (PostSync) | Executes webhook creation, idempotent |

**Webhook URL**: `http://kargo-external-webhooks-server.kargo.svc.cluster.local:80/webhooks/gitea/<hash>`

The hash is derived from Kargo's ClusterConfig and ensures only authorized requests trigger Warehouse refreshes.

### 3. Ingress TLS Certificate

**App**: `ingress-nginx-cert`
**Namespace**: `ingress-nginx`
**Sync Wave**: `-99` (runs first)

Copies the idpbuilder-generated TLS certificate to `persistent-tls-cert`, which nginx uses as the default SSL certificate. This enables external HTTPS access to Gitea for ArgoCD repo-server.

| Resource | Purpose |
|----------|---------|
| `ServiceAccount` | RBAC identity for the Job |
| `Role` | Permission to read/create secrets |
| `RoleBinding` | Binds role to service account |
| `Job` (PreSync) | Copies `idpbuilder-cert` to `persistent-tls-cert` |

## Architecture

### Sync Order

```
Sync Wave -99: ingress-nginx-cert (PreSync: copy TLS cert)
Sync Wave -10: ExternalSecrets (fetch credentials)
Sync Wave  80: argocd-webhook-setup, kargo-webhook-sync
                └── PostSync: Jobs create system webhooks
```

### Why System Webhooks?

| Approach | Scope | Maintenance | Sync Delay |
|----------|-------|-------------|------------|
| Per-repo webhooks | Single repo | High (CronJob needed) | Instant |
| **System webhooks** | ALL repos | None | Instant |
| Polling | ALL repos | None | 3-5 minutes |

System webhooks provide the best of both worlds: instant sync with zero maintenance.

### Credentials Flow

```
Azure Key Vault
    │ gitea-credential (username, password, token)
    ▼
ClusterSecretStore (gitea)
    │
    ▼
ExternalSecret (per namespace)
    │
    ▼
Kubernetes Secret
    │
    ▼
Job (mounts as files, uses basic auth)
```

## Verification

### Check System Webhooks

```bash
# From inside the cluster
kubectl run -i --rm curl --image=curlimages/curl:8.5.0 -n gitea -- \
  curl -s -u giteaAdmin:developer \
  "http://my-gitea-http.gitea.svc.cluster.local:3000/api/v1/admin/hooks" | jq .

# Expected output shows 2 webhooks:
# - ArgoCD webhook (id: 1 or 2)
# - Kargo webhook (id: 1 or 2)
```

### Check App Status

```bash
argocd app get argocd/argocd-webhook-setup --insecure
argocd app get argocd/kargo-webhook-sync --insecure
argocd app get argocd/ingress-nginx-cert --insecure
```

All should show `Synced` and `Healthy`.

### Check Job Logs

```bash
# ArgoCD webhook setup
kubectl logs job/argocd-webhook-setup -n argocd

# Kargo webhook sync
kubectl logs job/kargo-webhook-sync-init -n kargo

# Expected output:
# [+] Created system webhook (id: X)
# OR
# ArgoCD/Kargo system webhook already exists. Skipping.
```

### Test Webhook Delivery

```bash
# Make a change to any Gitea repo
# Then immediately check ArgoCD refresh
argocd app list --insecure | grep -E "Synced|OutOfSync"

# Check Kargo Warehouse refresh
kubectl get warehouses -n kargo-pipelines -o jsonpath='{.items[*].status.lastFreight.discoveredAt}'
```

## Troubleshooting

### Webhook Not Created

1. Check ExternalSecret status:
   ```bash
   kubectl get externalsecret -n argocd gitea-argocd-webhook-creds -o yaml
   kubectl get externalsecret -n kargo kargo-gitea-credentials -o yaml
   ```

2. Check Job logs:
   ```bash
   kubectl logs job/argocd-webhook-setup -n argocd --tail=50
   kubectl logs job/kargo-webhook-sync-init -n kargo --tail=50
   ```

3. Verify Gitea admin credentials work:
   ```bash
   kubectl get secret gitea-argocd-webhook-creds -n argocd -o jsonpath='{.data.username}' | base64 -d
   ```

### TLS Certificate Issues

If ArgoCD repo-server can't connect to Gitea:

1. Check if `persistent-tls-cert` exists:
   ```bash
   kubectl get secret persistent-tls-cert -n ingress-nginx
   ```

2. Verify nginx is on control-plane:
   ```bash
   kubectl get pods -n ingress-nginx -o wide | grep controller
   # Should show: thinkpad-control-plane (or your control-plane node)
   ```

3. Restart ArgoCD repo-server:
   ```bash
   kubectl rollout restart deployment argocd-repo-server -n argocd
   ```

### Webhook Delivery Failures

Check Gitea webhook delivery history:

```bash
kubectl run -i --rm curl --image=curlimages/curl:8.5.0 -n gitea -- \
  curl -s -u giteaAdmin:developer \
  "http://my-gitea-http.gitea.svc.cluster.local:3000/api/v1/admin/hooks/1" | jq .
```

## Files Reference

### ArgoCD Webhook Setup

```
packages/base/manifests/argocd-webhook-setup/
├── ConfigMap-argocd-webhook-setup-script.yaml  # Webhook creation script
├── ExternalSecret-gitea-argocd-webhook-creds.yaml  # Credentials
└── Job-argocd-webhook-setup.yaml  # PostSync hook
```

### Kargo Webhook Sync

```
packages/base/manifests/kargo-webhook-sync/
├── ConfigMap-kargo-webhook-sync-script.yaml  # Webhook creation script
├── ExternalSecret-kargo-gitea-credentials.yaml  # Gitea credentials
├── Secret-kargo-gitea-cluster-webhook-secret.yaml  # Kargo webhook secret
└── Job-kargo-webhook-sync-init.yaml  # PostSync hook
```

### Ingress TLS Certificate

```
packages/base/manifests/ingress-nginx-cert/
├── Job-copy-tls-cert.yaml  # PreSync hook
├── Role-copy-cert.yaml
├── RoleBinding-copy-cert.yaml
└── ServiceAccount-copy-cert-sa.yaml
```

## Related Documentation

- [Kargo Gitea Webhook Receiver](https://main.docs.kargo.io/user-guide/reference-docs/webhook-receivers/gitea/)
- [ArgoCD Webhook Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/)
- [Gitea System Webhooks API](https://docs.gitea.com/api/1.20/#tag/admin/operation/adminCreateHook)
