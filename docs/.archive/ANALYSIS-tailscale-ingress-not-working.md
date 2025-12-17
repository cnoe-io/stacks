# Analysis: Tailscale Ingress Links Not Working from M1 Browser

## Summary

Commit `5acf474` added ingress aliases for kagent and agentgateway, but the links don't work because the **Tailscale Kubernetes Operator is disabled**, causing LoadBalancer services to remain in `<pending>` state without external IPs.

## Commit Analysis: 5acf47475e17

**Commit Message**: "Post-synthesis state"
**Date**: Tue Nov 18 15:34:57 2025
**File Changed**: `cdk8s/charts/platform/tailnet-ingress-alias-chart.ts`

**Changes Made**:
```typescript
// Added two new ingress aliases:
{
  namespace: 'kagent',
  name: 'kagent-tailnet-alias',
  host: 'kagent.tail286401.ts.net',
  paths: [{ path: '/', service: 'kagent-ui', port: 8080, pathType: 'Prefix' }],
},
{
  namespace: 'kgateway-system',
  name: 'agentgateway-tailnet-alias',
  host: 'agentgateway.tail286401.ts.net',
  paths: [{ path: '/', service: 'kgateway', port: 9977, pathType: 'Prefix' }],
}
```

**Note**: Current file has `kagent-grafana-mcp:8000` but commit shows `kagent-ui:8080` (discrepancy).

## Root Cause Analysis

### Architecture Overview

The cluster has **two approaches** for Tailscale ingress:

1. **Tailscale Operator + LoadBalancer** (NOT WORKING)
   - Uses Tailscale Kubernetes Operator
   - Creates LoadBalancer services with `loadBalancerClass: tailscale`
   - Operator provisions Tailscale devices for each LoadBalancer
   - Nginx ingress → LoadBalancer → Service → Pod

2. **Tailscale Serve** (WORKING)
   - Standalone pod running `tailscale serve`
   - Direct exposure without ingress/LoadBalancer
   - Example: `argocd-tailscale-serve`
   - URL: `https://argocd-ui-serve-37.tail286401.ts.net/`

### Current State

| Component | Status | Details |
|-----------|--------|---------|
| **Tailscale Operator** | ❌ DISABLED | Commented out in `cdk8s/config/applications.ts:756` |
| **LoadBalancer Services** | ⏳ PENDING | No external IPs assigned (requires operator) |
| **Ingress Resources** | ✅ CREATED | Rules exist but can't route (no backend) |
| **Old Tailscale Devices** | 🔴 OFFLINE | kagent, gitea, agentgateway (last seen 2d ago) |
| **argocd-tailscale-serve** | ✅ WORKING | Direct Tailscale serve approach |

### Evidence

```bash
# LoadBalancer services stuck in pending:
$ kubectl get svc -A | grep LoadBalancer
ts-kagent-ingress        LoadBalancer   10.96.130.242   <pending>   443:31036/TCP
ts-gitea-ingress         LoadBalancer   10.96.149.76    <pending>   443:32563/TCP
ts-agentgateway-ingress  LoadBalancer   10.96.52.178    <pending>   443:32541/TCP

# No Tailscale operator running:
$ kubectl get pods -n tailscale
NAME                                      READY   STATUS
argocd-tailscale-serve-7664fdf969-kdm9b   1/1     Running
tailscale-api-proxy-644cf48b6d-grhdj      2/2     Running
tailscale-subnet-router                   1/1     Running

# Old devices offline:
$ tailscale status | grep -E "kagent|gitea|agentgateway"
100.92.255.45    kagent           offline, last seen 2d ago
100.127.178.42   gitea            offline, last seen 2d ago
100.109.218.4    agentgateway     offline, last seen 2d ago

# Ingress works but has no backend:
$ curl -k http://kagent.tail286401.ts.net/
curl: (28) Connection timed out

# But ArgoCD Tailscale serve works:
$ curl -k https://argocd-ui-serve-37.tail286401.ts.net/
<!doctype html><html lang="en"><head><meta charset="UTF-8"><title>Argo CD</title>
```

## Why It Doesn't Work

### Step-by-Step Breakdown

1. **Commit added ingress rules** ✅
   - `kagent.tail286401.ts.net` → nginx-ingress → kagent-ui:8080

2. **LoadBalancer services created** ✅
   - `ts-kagent-ingress` with `loadBalancerClass: tailscale`

3. **Tailscale operator should provision** ❌
   - Operator watches LoadBalancer services
   - Creates Tailscale device with hostname
   - Assigns external IP to service
   - **BUT: Operator is not running!**

4. **Service stays in pending** ❌
   - No external IP assigned
   - `kagent.tail286401.ts.net` doesn't resolve

5. **Browser request fails** ❌
   - DNS resolves to old offline device (100.92.255.45)
   - Device is offline (last seen 2d ago)
   - Connection timeout

## What's Working vs Not Working

| Service | Approach | Status | URL | Why |
|---------|----------|--------|-----|-----|
| **ArgoCD** | Tailscale Serve | ✅ WORKS | `https://argocd-ui-serve-37.tail286401.ts.net` | Direct serve, no operator needed |
| **Kagent** | Operator + LB | ❌ BROKEN | `https://kagent.tail286401.ts.net` | Operator disabled, LB pending |
| **Gitea** | Operator + LB | ❌ BROKEN | `https://gitea.tail286401.ts.net` | Operator disabled, LB pending |
| **Agentgateway** | Operator + LB | ❌ BROKEN | `https://agentgateway.tail286401.ts.net` | Operator disabled, LB pending |

## Solution Options

### Option 1: Enable Tailscale Operator (Recommended for Production)

**Pros:**
- Automatic LoadBalancer provisioning
- Centralized management
- Scales to many services
- Standard Kubernetes patterns

**Cons:**
- Requires ProxyGroup CRD fix
- More complex architecture
- Higher resource usage

**Implementation:**
1. Uncomment Tailscale operator in `cdk8s/config/applications.ts:756`
2. Fix ProxyGroup CRD import issue
3. Deploy operator
4. LoadBalancer services will auto-provision
5. All ingress URLs will work

### Option 2: Use Tailscale Serve for Each Service (Current Working Pattern)

**Pros:**
- Simple, works immediately
- No operator dependency
- Each service independent
- Proven working (ArgoCD example)

**Cons:**
- One pod per service (more pods)
- Manual chart creation per service
- Doesn't leverage Kubernetes LoadBalancer abstraction

**Implementation:**
1. Create charts similar to `ArgoCdTailscaleServeChart`
2. Deploy for kagent, gitea, agentgateway
3. Each gets unique Tailscale device + serve URL

### Option 3: Subnet Router + Port Forwarding (Alternative)

**Pros:**
- One Tailscale device for all services
- Minimal pods

**Cons:**
- All services share one hostname
- Port-based routing (less clean URLs)
- Subnet routing required

## Recommended Action

**For immediate fix**: Use **Option 2** (Tailscale Serve) because:
1. ✅ Proven working (ArgoCD already uses it)
2. ✅ No operator dependency
3. ✅ Quick to implement
4. ✅ Cluster recreation safe (dynamic hostname detection)

**For long-term**: Migrate to **Option 1** (Operator) when:
1. ProxyGroup CRD import is fixed
2. Production deployment needs scale
3. Want centralized LoadBalancer management

## Does Commit 5acf474 Have the Fix?

**Answer: NO ❌**

The commit added the ingress rules but **did not fix the underlying issue**:
- ❌ Didn't enable Tailscale operator
- ❌ Didn't create Tailscale serve pods
- ❌ Didn't update LoadBalancer service status
- ✅ Only added ingress rules (necessary but not sufficient)

**What the commit did**:
- Added configuration for what SHOULD work IF operator was running
- Like building a road (ingress) without building the bridge (LoadBalancer) it needs

**What's needed to make it work**:
1. Enable Tailscale operator, OR
2. Create Tailscale serve pods for each service

## Next Steps

See implementation plan in `docs/PLAN-tailscale-serve-rollout.md`
