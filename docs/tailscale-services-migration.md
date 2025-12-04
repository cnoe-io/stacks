# Tailscale Services Migration Guide

This guide documents the migration from hostname-based Tailscale exposure to stable Tailscale Services URLs.

## Overview

**Before**: Services exposed via device hostnames that changed on cluster recreation
- ArgoCD: `https://argocd-ui-serve-3.tail286401.ts.net` (suffix increments)
- Langfuse: `https://langfuse-2.tail286401.ts.net` (suffix increments)

**After**: Services exposed via stable Tailscale Services URLs
- ArgoCD: `https://svc-argocd.tail286401.ts.net` (stable)
- Langfuse: `https://svc-langfuse.tail286401.ts.net` (stable)

## Prerequisites

1. Tailscale v1.86.0+ (current: v1.90.9)
2. Tailscale Admin Console access
3. Azure Key Vault access (for auth key secret)

## Migration Steps

### 1. Configure Tailscale Admin Console

#### 1.1 Update ACL Policy

Add to your existing ACL policy:

```json
{
  "tagOwners": {
    // ... existing tags ...
    "tag:k8s-services": ["vpittamp@github"]
  },
  "autoApprovers": {
    "routes": {
      // ... existing routes ...
    },
    "services": {
      "svc:argocd": ["tag:k8s-services"],
      "svc:langfuse": ["tag:k8s-services"]
    }
  },
  "acls": [
    // ... existing rules ...
    {
      "action": "accept",
      "src": ["vpittamp@github"],
      "dst": ["tag:k8s-services:*"]
    },
    {
      "action": "accept",
      "src": ["tag:k8s-services"],
      "dst": ["tag:k8s:*", "tag:k8s-operator:*", "vpittamp@github:*"]
    }
  ]
}
```

#### 1.2 Define Services

In Tailscale Admin Console → Services:

1. Create service `argocd` with endpoint `tcp:443`
2. Create service `langfuse` with endpoint `tcp:443`

#### 1.3 Generate Tagged Auth Key

In Settings → Keys → Generate auth key:
- [x] Reusable
- [x] Ephemeral
- Tags: `tag:k8s-services`

### 2. Update Azure Key Vault

Update the `tailscale-auth-key` secret with the new tagged auth key.

### 3. Trigger Secret Sync

```bash
# Delete secret to trigger External Secrets sync
kubectl delete secret tailscale-auth-key -n tailscale

# Verify sync
kubectl get secret tailscale-auth-key -n tailscale
```

### 4. Deploy Changes

```bash
# Synthesize charts
cd cdk8s && npx ts-node main-v2.ts

# Sync via ArgoCD
argocd-sync argocd/argocd-tailscale-serve
argocd-sync argocd/langfuse-tailscale-serve
```

### 5. Verify

```bash
# Check pods
kubectl get pods -n tailscale -l app.kubernetes.io/part-of=argocd
kubectl get pods -n tailscale -l app.kubernetes.io/part-of=langfuse

# Check logs for service registration
kubectl logs -n tailscale -l app.kubernetes.io/name=argocd-tailscale-serve --tail=10
```

In Tailscale Admin Console → Services:
- `svc:argocd` should show as "Active"
- `svc:langfuse` should show as "Active"

## Service URLs

| Service | Stable URL | Legacy URL (deprecated) |
|---------|-----------|------------------------|
| ArgoCD | `https://svc-argocd.<tailnet>.ts.net` | `https://argocd-ui-serve.<tailnet>.ts.net` |
| Langfuse | `https://svc-langfuse.<tailnet>.ts.net` | `https://langfuse.<tailnet>.ts.net` |

Replace `<tailnet>` with your tailnet domain (e.g., `tail286401`).

## Rollback

To revert to hostname-based access, update `applications.ts`:

```typescript
// For ArgoCD
{
  chart: {
    type: 'ArgoCdTailscaleServeChart',
    props: {
      legacyHostnameMode: true,
      legacyHostname: 'argocd-ui-serve',
      // ... other props
    }
  }
}

// For Langfuse
{
  chart: {
    type: 'LangfuseTailscaleServeChart',
    props: {
      legacyHostnameMode: true,
      legacyHostname: 'langfuse',
      // ... other props
    }
  }
}
```

Then synthesize and deploy.

## Known Limitations

- **TCP-only**: Tailscale Services currently only support TCP transport (our HTTPS services work via TCP:443)
- **No hairpinning**: Service host devices cannot access their own services
- **Beta feature**: Subject to change, but stable for production use

## Troubleshooting

### Service Not Appearing

1. Check auth key has `tag:k8s-services` tag
2. Verify ACL auto-approver rules
3. Check pod logs for registration errors

### Certificate Errors

Tailscale automatically provisions TLS certificates for services. If you see certificate errors:
1. Wait 30 seconds for certificate provisioning
2. Verify service is "Active" in Admin Console

### Langfuse Auth Failures

Langfuse requires `nextAuthUrl` to match the access URL exactly. Verify:
```typescript
nextAuthUrl: 'https://svc-langfuse.<tailnet>.ts.net'
```

## References

- [Tailscale Services Documentation](https://tailscale.com/kb/1552/tailscale-services)
- [Tailscale Serve Command](https://tailscale.com/kb/1242/tailscale-serve)
- [Feature Spec](../specs/101-improve-tailscale/spec.md)
- [Quickstart Guide](../specs/101-improve-tailscale/quickstart.md)
