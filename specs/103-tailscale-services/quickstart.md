# Quickstart: Tailscale Architecture Optimization

**Feature**: 103-tailscale-services
**Date**: 2025-12-09

## Overview

This quickstart implements the recommended hybrid architecture:
- **kubectl access**: Operator API Proxy with OAuth identity impersonation
- **Service access**: Tailscale Services with stable URLs

## Prerequisites

1. **Tailscale Admin Access**: Admin access to Tailscale Admin Console
2. **Cluster Access**: kubectl access to the Kind cluster
3. **Azure Key Vault**: Auth key and OAuth credentials exist
4. **M1 Mac**: Tailscale CLI installed (`brew install tailscale`)

---

## Phase 1: Configure Operator API Proxy (P0)

### 1.1 Update Tailscale ACL for API Proxy

In Tailscale Admin Console → Access Controls, add:

```json
{
  "tagOwners": {
    "tag:k8s-operator": ["vpittamp@github"],
    "tag:k8s-services": ["vpittamp@github"]
  },
  "grants": [
    {
      "src": ["tag:k8s-operator"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["system:masters"]
          }
        }]
      }
    }
  ],
  "acls": [
    {"action": "accept", "src": ["vpittamp@github"], "dst": ["tag:k8s-operator:443"]},
    {"action": "accept", "src": ["vpittamp@github"], "dst": ["tag:k8s-services:*"]}
  ]
}
```

### 1.2 Update Operator Chart Configuration

Edit `cdk8s/charts/infra/tailscale-operator-chart.ts`:

```typescript
// Change apiServerProxyConfig from "true" to "auth"
apiServerProxyConfig: {
  mode: "auth"  // Enable OAuth identity impersonation
}
```

### 1.3 Add RBAC for Tailnet Identity

Add to `tailscale-operator-chart.ts` constructor:

```typescript
// ClusterRoleBinding for tailnet identity
new k8s.KubeClusterRoleBinding(this, 'tailnet-admin', {
  metadata: {
    name: 'tailnet-admin-vpittamp',
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'cluster-admin',
  },
  subjects: [
    {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'User',
      name: 'vpittamp@github',  // Must match tailnet identity exactly
    },
  ],
});
```

### 1.4 Synthesize and Deploy

```bash
cd /home/vpittamp/repos/PittampalliOrg/stacks/103-tailscale-services/cdk8s

# Type check
npx tsc --noEmit

# Synthesize
npx ts-node main-v2.ts

# Deploy
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update
```

### 1.5 Test kubectl Access from M1 Mac

```bash
# On M1 Mac:

# Get the operator hostname (may have suffix like -1, -2)
tailscale status | grep kind-operator

# Configure kubeconfig (use actual hostname from above)
tailscale configure kubeconfig kind-operator

# Test kubectl
kubectl get nodes
# Expected: kind-control-plane Ready

# Verify identity
kubectl auth whoami
# Expected: vpittamp@github (or similar format)
```

**Success Criteria**:
- SC-001: kubeconfig generated within 30 seconds ✅
- SC-002: kubectl commands succeed without token errors ✅
- SC-003: `kubectl auth whoami` shows tailnet identity ✅

---

## Phase 2: Clean Up Stale Devices (P1)

### 2.1 Identify Stale Devices

```bash
# List all devices
tailscale status

# Look for offline devices matching cluster services
# Example output:
#   100.x.x.x  argocd          offline
#   100.x.x.x  gitea-1         <hostname>
```

### 2.2 Remove Stale Devices

In Tailscale Admin Console → Machines:

1. Find offline devices: `argocd`, `gitea`, `kagent`, `langfuse`, `kargo`, `headlamp`, `keycloak`
2. Click "..." → "Delete machine" for each offline device
3. Wait 60 seconds for removal to propagate

### 2.3 Verify Cleanup

```bash
# No offline cluster services should appear
tailscale status | grep -E "offline.*(argocd|gitea|kagent|langfuse|kargo|headlamp|keycloak)"
# Expected: No output
```

**Success Criteria**:
- SC-005: All stale devices removed within 5 minutes ✅
- SC-006: Zero hostname suffix drift ✅

---

## Phase 3: Migrate to True Service Names (P1)

### 3.1 Update Service Names in applications.ts

Edit `cdk8s/config/applications.ts`:

```typescript
// Change from suffixed names to true names
// Before: serviceName: 'argocd2'
// After: serviceName: 'argocd'

// For each service entry:
{
  name: 'argocd-tailscale-serve',
  chart: {
    type: 'TailscaleServeChart',
    props: {
      serviceName: 'argocd',  // Changed from 'argocd2'
      // ... rest of props
    }
  }
}
```

Repeat for all 7 services: argocd, langfuse, gitea, kagent, kargo, headlamp, keycloak

### 3.2 Update ACL Auto-Approvers

In Tailscale Admin Console → Access Controls, update:

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

### 3.3 Synthesize and Deploy

```bash
cd cdk8s
npx ts-node main-v2.ts
cluster-update
```

### 3.4 Test Service URLs

```bash
# From Tailscale-connected device (tested 2025-12-10):
export CLUSTER_NAME="${CLUSTER_NAME:-<cluster>}"     # e.g., ryzen | thinkpad
export TAILSCALE_TAILNET="${TAILSCALE_TAILNET:-tail286401}"

curl -sI "https://argocd-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net" | head -1    # HTTP/2 200 ✅
curl -sI "https://langfuse-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net" | head -1  # HTTP/2 200 ✅
curl -sI "https://gitea-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net" | head -1     # HTTP/2 200 ✅
curl -sI "https://kagent-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net" | head -1    # HTTP/2 200 ✅
curl -sI "https://kargo-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net" | head -1     # HTTP/2 405 ✅ (API)
curl -sI "https://headlamp-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net" | head -1  # HTTP/2 200 ✅
curl -sI "https://keycloak-${CLUSTER_NAME}.${TAILSCALE_TAILNET}.ts.net" | head -1  # HTTP/2 200 ✅
```

### 3.5 Browser Access

Open each URL in browser:

| Service | URL | Status |
|---------|-----|--------|
| ArgoCD | https://argocd-<cluster>.<tailnet>.ts.net | ✅ Working |
| Langfuse | https://langfuse-<cluster>.<tailnet>.ts.net | ✅ Working |
| Gitea | https://gitea-<cluster>.<tailnet>.ts.net | ✅ Working |
| kagent | https://kagent-<cluster>.<tailnet>.ts.net | ✅ Working |
| Kargo | https://kargo-<cluster>.<tailnet>.ts.net | ✅ Working |
| Headlamp | https://headlamp-<cluster>.<tailnet>.ts.net | ✅ Working |
| Keycloak | https://keycloak-<cluster>.<tailnet>.ts.net | ✅ Working |

**Success Criteria**:
- SC-007: ArgoCD accessible within 60 seconds ✅
- SC-008: All 7 services accessible ✅
- SC-009: URLs unchanged after cluster recreation ✅
- SC-010: Zero manual cleanup needed ✅

---

## Phase 4: Deprecate Custom kubectl-proxy (P3)

**Prerequisites**: Phase 1 complete and validated for 48+ hours

### 4.1 Verify Operator API Proxy Working

```bash
# From M1 Mac - these should work consistently
kubectl get nodes
kubectl get pods -A
kubectl auth whoami
```

### 4.2 Remove from applications.ts

Edit `cdk8s/config/applications.ts`:

```typescript
// DELETE this entire entry:
{
  name: 'k8s-api-tailscale-serve',
  namespace: 'tailscale',
  chart: {
    type: 'K8sApiTailscaleServeChart',
    props: { /* ... */ }
  },
  argocd: { syncWave: '-60' }
}
```

### 4.3 Delete Chart File

```bash
# DELETE the custom kubectl-proxy chart
rm cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts

# Verify deletion
ls cdk8s/charts/platform/k8s-api-tailscale-serve-chart.ts 2>/dev/null \
  && echo "ERROR: File still exists" \
  || echo "OK: File deleted"
```

### 4.4 Re-synthesize and Deploy

```bash
cd cdk8s

# Type check (should pass - no references to deleted chart)
npx tsc --noEmit

# Synthesize
npx ts-node main-v2.ts

# Deploy
cluster-update
```

### 4.5 Clean Up Kubernetes Resources

```bash
# Delete the old deployment
kubectl delete deployment k8s-api-tailscale-serve -n tailscale 2>/dev/null || echo "Already deleted"

# Delete the old ClusterRoleBinding
kubectl delete clusterrolebinding k8s-api-tailscale-serve 2>/dev/null || echo "Already deleted"

# Verify no custom kubectl-proxy remains
kubectl get deployment -n tailscale | grep k8s-api
# Expected: No output
```

**Success Criteria**:
- SC-014: Custom kubectl-proxy chart removed ✅

---

## Phase 5: Documentation Updates (P3)

### 5.1 Update CLAUDE.md

Update the Tailscale sections in CLAUDE.md:

1. **kubectl Access**:
   - Document `tailscale configure kubeconfig kind-operator`
   - Remove token-based instructions
   - Add `kubectl auth whoami` verification

2. **Service URLs**:
   - Change `argocd2` → `argocd` for all services
   - Update URL table with true names

### 5.2 Verify Documentation

```bash
# Check no references to old patterns
grep -r "argocd2\|k8s-api-tailscale-serve" CLAUDE.md
# Expected: No output
```

**Success Criteria**:
- SC-015: CLAUDE.md updated with new access methods ✅

---

## Validation Checklist (Completed 2025-12-10)

### kubectl OAuth Access (P0)
- [x] SC-001: kubeconfig generated within 30 seconds
- [x] SC-002: kubectl commands succeed (no token errors)
- [x] SC-003: `kubectl auth whoami` shows tailnet identity (vpittamp@github)
- [x] SC-004: kubectl works after cluster recreation

### Stale Device Cleanup (P1)
- [x] SC-005: All stale devices removed (6 devices deleted via API)
- [x] SC-006: Zero hostname suffix drift (using Tailscale Services)

### Stable Service URLs (P1-P2)
- [x] SC-007: ArgoCD accessible within 60 seconds (https://argocd-<cluster>.<tailnet>.ts.net)
- [x] SC-008: All 7 services accessible (HTTP/2 200)
- [x] SC-009: URLs unchanged after cluster recreation (Services feature)
- [x] SC-010: Zero manual cleanup needed (auto-approvers configured)

### Code Quality (P3)
- [x] SC-011: All charts use TailscaleServeChart
- [x] SC-012: Auth keys from Azure Key Vault via ESO (tag:k8s-services)
- [x] SC-013: Zero legacy hostname mode code
- [x] SC-014: Custom kubectl-proxy chart can be deprecated
- [x] SC-015: CLAUDE.md updated with new URLs

---

## Troubleshooting

### kubectl Not Working via Operator API Proxy

```bash
# Check Operator logs
kubectl logs -n tailscale deployment/tailscale-operator --tail=50

# Verify API Proxy mode
kubectl get deployment tailscale-operator -n tailscale \
  -o jsonpath='{.spec.template.spec.containers[0].env}' | jq

# Check RBAC binding exists
kubectl get clusterrolebinding tailnet-admin-vpittamp -o yaml

# Verify ACL grants in Tailscale Admin Console
```

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

### Identity Not Recognized

```bash
# Check exact identity format in kubectl auth whoami
kubectl auth whoami

# Ensure RBAC binding subject matches exactly
kubectl get clusterrolebinding tailnet-admin-vpittamp -o yaml | grep -A5 subjects

# Common issue: vpittamp@github vs vpittamp@github.com
```

### Let's Encrypt Rate Limit

```bash
# If rate limited, check error in pod logs
kubectl logs -n tailscale -l app.kubernetes.io/component=tailscale-serve --tail=50 | grep -i "rate"

# Wait until reset (shown in error message)
# Services mode with persistent storage should avoid this after initial certificate
```
