# Quickstart: Tailscale Stale Device Cleanup and Services Migration

**Feature**: 103-tailscale-services
**Date**: 2025-12-06

## Forward-Only Migration (No Backward Compatibility)

Per Constitution Principle IX, this migration **completely replaces** the legacy Tailscale Ingress pattern. The `tailscale-ingress-chart.ts` file will be **deleted**, not deprecated.

**Before**: 7 services via `TailscaleIngressChart` (hostname-based, suffix drift)
**After**: 7 services via `TailscaleServeChart` (Services-based, stable URLs)

---

## Prerequisites

1. **Tailscale Admin Access**: Admin access to Tailscale Admin Console
2. **Cluster Access**: kubectl access to the Kind cluster
3. **Azure Key Vault**: Auth key `TAILSCALE-AUTH-KEY` with `tag:k8s-services` tag exists
4. **Tailscale CLI**: `tailscale` CLI available on cluster host

## Phase 1: Stale Device Cleanup

### 1.1 List Current Devices

```bash
# List all devices in tailnet
tailscale status

# Expected: Offline devices for argocd, gitea, kagent, etc.
```

### 1.2 Remove Stale Devices

```bash
# Via Tailscale Admin Console (recommended):
# 1. Go to https://login.tailscale.com/admin/machines
# 2. Find offline devices matching: argocd, gitea, kagent, langfuse, kargo, headlamp, keycloak
# 3. Click "..." → "Delete machine"

# Or via CLI (requires admin token):
# tailscale devices remove <device-id>
```

### 1.3 Verify Cleanup

```bash
# Verify no offline devices for cluster services
tailscale status | grep -E "(argocd|gitea|kagent|langfuse|kargo|headlamp|keycloak)"
# Expected: No output (all stale devices removed)
```

## Phase 2: Configure ACL Auto-Approvers

### 2.1 Access ACL Editor

1. Go to https://login.tailscale.com/admin/acls
2. Click "Edit ACL file"

### 2.2 Add Auto-Approvers

Add the following to the ACL file:

```json
{
  "autoApprovers": {
    "services": {
      "svc:argocd": ["tag:k8s-services"],
      "svc:langfuse": ["tag:k8s-services"],
      "svc:gitea": ["tag:k8s-services"],
      "svc:kagent": ["tag:k8s-services"],
      "svc:kargo": ["tag:k8s-services"],
      "svc:headlamp": ["tag:k8s-services"],
      "svc:keycloak": ["tag:k8s-services"]
    }
  }
}
```

### 2.3 Verify ACL

```bash
# After saving ACL, verify services section exists
# Go to Admin Console → Access Controls → View effective policy
```

## Phase 3: Deploy Serve Charts

### 3.1 Synthesize Charts

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/103-tailscale-services/cdk8s

# Synthesize all packages
npx ts-node main-v2.ts

# Verify new serve chart packages exist
ls -la dist/ | grep tailscale-serve
# Expected: argocd-tailscale-serve, langfuse-tailscale-serve, etc.
```

### 3.2 Type Check

```bash
# Verify TypeScript compiles
npm run compile
# Or: npx tsc --noEmit

# Expected: No errors
```

### 3.3 Deploy via IdpBuilder

```bash
# Deploy all packages
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update

# Or deploy specific serve chart
idpbuilder create --package cdk8s/dist/argocd-tailscale-serve
```

### 3.4 Verify ArgoCD Sync

```bash
# Check sync status
argocd app list --insecure | grep tailscale-serve
# Expected: All apps Synced/Healthy

# Check specific app
argocd app get argocd/argocd-tailscale-serve --insecure
```

## Phase 4: Validate Services

### 4.1 Check Pod Status

```bash
# Check all serve pods
kubectl get pods -n tailscale -l app.kubernetes.io/component=tailscale-serve
# Expected: Running state for all serve pods
```

### 4.2 Check Tailscale Registration

```bash
# Check service registration in tailscale status
tailscale status

# Expected: Services registered as svc:argocd, svc:langfuse, etc.
```

### 4.3 Test Service URLs

```bash
# From a Tailscale-connected device:

# Test ArgoCD
curl -sI https://svc-argocd.tail286401.ts.net | head -5
# Expected: HTTP/2 200

# Test Langfuse
curl -sI https://svc-langfuse.tail286401.ts.net | head -5
# Expected: HTTP/2 200

# Test all services
for svc in argocd langfuse gitea kagent kargo headlamp keycloak; do
  echo "Testing svc-${svc}..."
  curl -sI "https://svc-${svc}.tail286401.ts.net" | head -1
done
```

### 4.4 Browser Access

Open each URL in browser from Tailscale-connected device:

| Service | URL | Expected |
|---------|-----|----------|
| ArgoCD | https://svc-argocd.tail286401.ts.net | ArgoCD login page |
| Langfuse | https://svc-langfuse.tail286401.ts.net | Langfuse dashboard |
| Gitea | https://svc-gitea.tail286401.ts.net | Gitea homepage |
| kagent | https://svc-kagent.tail286401.ts.net | kagent dashboard |
| Kargo | https://svc-kargo.tail286401.ts.net | Kargo UI |
| Headlamp | https://svc-headlamp.tail286401.ts.net | Headlamp K8s UI |
| Keycloak | https://svc-keycloak.tail286401.ts.net | Keycloak admin console |

## Phase 5: Delete Legacy Files (Forward-Only)

Per Constitution Principle IX, legacy files are **deleted**, not deprecated.

### 5.1 Delete Legacy Chart File

```bash
# DELETE the legacy ingress chart (no backup needed)
rm cdk8s/charts/platform/tailscale-ingress-chart.ts

# Verify deletion
ls cdk8s/charts/platform/tailscale-ingress-chart.ts 2>/dev/null && echo "ERROR: File still exists" || echo "OK: File deleted"
```

### 5.2 Remove Legacy Entry from applications.ts

Remove the entire `tailscale-ingresses` entry from `cdk8s/config/applications.ts`:

```typescript
// DELETE THIS ENTIRE BLOCK from applications.ts
{
  name: 'tailscale-ingresses',
  namespace: 'tailscale',
  chart: { type: 'TailscaleIngressChart' },
  argocd: { syncWave: '-30' }
}
```

### 5.3 Remove Registration from main-v2.ts

If `TailscaleIngressChart` is registered in `main-v2.ts`, remove the import and registration:

```typescript
// DELETE these lines from main-v2.ts
import { TailscaleIngressChart } from './charts/platform/tailscale-ingress-chart';
IdpBuilderChartFactory.register('TailscaleIngressChart', TailscaleIngressChart);
```

### 5.4 Re-synthesize and Deploy

```bash
cd cdk8s

# Type check (should pass with no TailscaleIngressChart references)
npx tsc --noEmit

# Re-synthesize
npx ts-node main-v2.ts

# Deploy changes
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update
```

### 5.5 Clean Up Kubernetes Resources

```bash
# Delete any remaining Tailscale Ingress resources
kubectl delete ingress -A -l app.kubernetes.io/component=tailscale-ingress

# Verify no legacy ingress remains
kubectl get ingress -A | grep tailscale
# Expected: No output (only serve pods remain)
```

### 5.6 Verify Only Optimal Implementation Remains

```bash
# List Tailscale-related files in charts/platform/
ls cdk8s/charts/platform/*tailscale*
# Expected:
#   cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts  (reference implementation)
#   cdk8s/charts/platform/tailscale-serve-chart.ts         (new generic chart)
#
# Should NOT show: tailscale-ingress-chart.ts

# Verify applications.ts has no TailscaleIngressChart references
grep -r "TailscaleIngressChart" cdk8s/
# Expected: No output
```

## Validation Checklist

### Functional Requirements
- [ ] All stale devices removed (SC-001)
- [ ] ArgoCD accessible via svc-argocd URL within 60s (SC-002)
- [ ] All 7 services accessible via stable URLs (SC-003)
- [ ] Service URLs unchanged after cluster recreation (SC-004)
- [ ] No manual device cleanup needed (SC-005)
- [ ] No hostname suffix drift observed (SC-006)

### Constitution Compliance (Forward-Only)
- [ ] All charts use TailscaleServeHelpers (SC-007)
- [ ] Auth keys from Azure Key Vault via ESO (SC-008)
- [ ] **No legacy code remains** - `tailscale-ingress-chart.ts` DELETED (SC-009)
- [ ] **No TailscaleIngressChart references** in codebase (SC-009)
- [ ] CLAUDE.md updated with service URLs (SC-010)

## Troubleshooting

### Service Not Registering

```bash
# Check pod logs
kubectl logs -n tailscale -l app.kubernetes.io/name=argocd-tailscale-serve --tail=50

# Check auth key secret
kubectl get secret -n tailscale tailscale-auth-key -o yaml

# Verify tag on auth key (in Tailscale Admin Console → Settings → Keys)
```

### ACL Rejection

```bash
# Check Tailscale Admin Console → Activity for ACL denials
# Ensure tag:k8s-services is on the auth key
# Ensure auto-approver rule exists for the service
```

### Let's Encrypt Rate Limit

```bash
# If rate limited, wait until reset (shown in error message)
# Services mode should avoid this after initial certificate
```

### Backend Connection Refused

```bash
# Verify backend service exists
kubectl get svc -n argocd argocd-server

# Test connectivity from serve pod
kubectl exec -n tailscale <serve-pod> -- curl -k https://argocd-server.argocd.svc.cluster.local:443
```
