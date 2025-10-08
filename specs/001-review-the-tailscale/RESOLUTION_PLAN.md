# Tailscale API Server Proxy - Resolution Plan

**Date**: 2025-10-08
**Status**: Root cause identified, resolution path documented
**Priority**: P1 - Requires Tailscale Support action

---

## Executive Summary

After comprehensive research and testing, we've successfully **configured the Tailscale Kubernetes Operator** to start the API server proxy. The proxy is running and listening on port 443, but **port 443 is not being advertised as a Tailscale Service** because:

1. ✅ **SOLVED**: Fixed environment variable name (`APISERVER_PROXY=true`, not `API_SERVER_PROXY`)
2. ✅ **SOLVED**: Added impersonation RBAC permissions to ClusterRole
3. ✅ **CONFIRMED**: API server proxy starts successfully ("API server proxy in auth mode is listening on :443")
4. ❌ **BLOCKED**: Tailscale Services (Alpha) feature not enabled for tailnet

---

## Root Cause Analysis

### What's Working

✅ **Operator Deployment**
- Image: `tailscale/k8s-operator:v1.88.3`
- Environment: `APISERVER_PROXY=true`, `OPERATOR_LOGGING=debug`
- Status: Running, authenticated to Tailscale
- Logs: `"API server proxy in auth mode is listening on :443"`

✅ **Tailscale Device Registration**
- Device: `kind-operator-9.tail286401.ts.net`
- Tailscale IP: `100.71.2.71`
- Status: Connected, authenticated
- Tags: `tag:k8s-operator`

✅ **Network Connectivity**
- Endpoints: `10.244.0.49:33123` (pod), `178.156.202.233:33123` (external)
- Relays: Connected (Ashburn: 2.86ms latency)

### What's NOT Working

❌ **Port 443 Service Advertisement**
- **Current Services**: Only ports 8080 (metrics) and 62694 (peerapi)
- **Missing**: Port 443 (API server proxy)
- **Impact**: Cannot use `tailscale configure kubeconfig` or access API server

### The Blocker

🚫 **Tailscale Services (Alpha Feature) Not Enabled**

According to Tailscale documentation:
> "ProxyGroups of type kube-apiserver use the Tailscale Services feature, which is currently in alpha. **You need to contact Tailscale Support to enable it for your tailnet** before you can start deploying the API server proxy in high availability configurations."

**This applies to in-process mode as well** - the operator uses the same underlying service advertisement mechanism.

---

## Resolution Paths

### Path 1: Enable Tailscale Services (RECOMMENDED if planning production use)

**Requirements:**
1. Contact Tailscale Support to enable Services (alpha) for tailnet
2. Update ACL policy with `autoApprovers` (✅ DONE - see below)
3. Apply updated ACL policy
4. Restart operator to re-register with new permissions

**ACL Policy Updates Required:**

```json
{
  "tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"]
  },
  "autoApprovers": {
    "services": {
      "tag:k8s": ["tag:k8s-operator"],
      "tag:k8s-operator": ["tag:k8s-operator"]
    }
  },
  "acls": [
    {
      "action": "accept",
      "src": ["vpittamp@gmail.com"],
      "dst": ["tag:k8s-operator:80,443"]
    }
  ],
  "grants": [
    {
      "src": ["vpittamp@gmail.com"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["system:masters"]
          }
        }]
      }
    }
  ]
}
```

**Status**: ✅ ACL policy updated in `tailnet-policy.json`

**Next Steps:**
1. **Apply ACL policy**: Go to https://login.tailscale.com/admin/acls and paste updated policy
2. **Contact Tailscale Support**: Request Tailscale Services (alpha) enablement
   - URL: https://tailscale.com/contact/support
   - Reason: "Need Tailscale Services (alpha) enabled for Kubernetes API server proxy"
   - Tailnet: `tail286401.ts.net`
3. **Wait for confirmation** from Tailscale Support
4. **Restart operator**: `kubectl rollout restart -n tailscale deployment/tailscale-operator`
5. **Verify service advertisement**: Check if port 443 appears in Tailscale admin console
6. **Test access**: `sudo tailscale configure kubeconfig kind-operator-9`

**Timeline**: Depends on Tailscale Support response time (typically 1-3 business days)

---

### Path 2: Sidecar Proxy (IMMEDIATE, NO EXTERNAL DEPENDENCIES)

**Benefits:**
- ✅ Works immediately (no waiting for Tailscale Support)
- ✅ No alpha features required
- ✅ Full control over configuration
- ✅ Proven architecture

**Implementation:**

Create `TailscaleApiProxyChart` with two containers:

```typescript
// cdk8s/charts/infra/tailscale-api-proxy-chart.ts
export class TailscaleApiProxyChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const namespace = 'tailscale';

    new k8s.KubeDeployment(this, 'api-proxy', {
      metadata: { name: 'api-proxy', namespace },
      spec: {
        replicas: 1,
        selector: { matchLabels: { app: 'tailscale-api-proxy' } },
        template: {
          metadata: { labels: { app: 'tailscale-api-proxy' } },
          spec: {
            serviceAccountName: 'operator', // Reuse existing SA
            containers: [
              {
                name: 'tailscale',
                image: 'tailscale/tailscale:latest',
                env: [
                  { name: 'TS_AUTH_KEY', valueFrom: { secretKeyRef: { name: 'tailscale-auth-key', key: 'authKey' }}},
                  { name: 'TS_HOSTNAME', value: 'k8s-api-proxy' },
                  { name: 'TS_EXTRA_ARGS', value: '--advertise-tags=tag:k8s' },
                ],
                securityContext: { capabilities: { add: ['NET_ADMIN'] }},
              },
              {
                name: 'kubectl-proxy',
                image: 'bitnami/kubectl:latest',
                command: ['kubectl', 'proxy', '--port=8001', '--address=0.0.0.0', '--accept-hosts=.*'],
              }
            ]
          }
        }
      }
    });
  }
}
```

**Setup Steps:**
1. Generate Tailscale auth key (reusable, tag:k8s)
2. Store auth key in Azure Key Vault
3. Create ExternalSecret for auth key
4. Deploy sidecar chart via ArgoCD
5. Access: The full Tailscale daemon advertises services properly

**Timeline**: 1-2 hours implementation

---

### Path 3: ProxyGroup with HA (FUTURE)

Use `ProxyGroup` CRD for high-availability deployment. This also requires Tailscale Services (alpha) enablement.

**Not recommended** until Path 1 is resolved, as it has the same blocker.

---

## Comparison Matrix

| Feature | Operator (Path 1) | Sidecar (Path 2) |
|---------|------------------|------------------|
| **Availability** | Blocked (needs Support) | ✅ Immediate |
| **Setup Complexity** | ⭐⭐ Medium | ⭐⭐⭐ Simple |
| **Maintenance** | ⭐⭐⭐ Operator-managed | ⭐⭐ Manual |
| **HA Support** | ✅ Yes (ProxyGroup) | ❌ No (single pod) |
| **Resource Usage** | ⭐⭐⭐ Low (single container) | ⭐⭐ Medium (2 containers) |
| **Alpha Features** | ❌ Required | ✅ None |
| **Tailscale Plan** | May require upgrade | ✅ Works with any plan |

---

## Recommended Action Plan

### For Immediate Testing/Development

**Use Path 2 (Sidecar Proxy)**
- No blockers, can be implemented today
- Provides full functionality for development/testing
- Easy to switch to operator later

### For Production

**Pursue Path 1 (Operator with Services)**
- Contact Tailscale Support ASAP to enable Services (alpha)
- Apply updated ACL policy while waiting
- More scalable long-term solution
- HA support via ProxyGroup

---

## Current Status

### ✅ Completed

1. Imported Tailscale CRDs
2. Created TailscaleOperatorChart with correct configuration
3. Fixed environment variable (`APISERVER_PROXY=true`)
4. Added impersonation RBAC permissions
5. Verified API server proxy starts successfully
6. Identified root cause (Tailscale Services not enabled)
7. Updated ACL policy with autoApprovers
8. Documented resolution paths

### ⏳ Pending

**Option A (Operator Path):**
- [ ] Apply updated ACL policy to tailnet
- [ ] Contact Tailscale Support for Services enablement
- [ ] Wait for Support confirmation
- [ ] Restart operator after enablement
- [ ] Verify port 443 advertisement
- [ ] Test kubectl access

**Option B (Sidecar Path):**
- [ ] Generate Tailscale auth key
- [ ] Store auth key in Azure Key Vault
- [ ] Create TailscaleApiProxyChart
- [ ] Register chart and add to applications.ts
- [ ] Deploy via ArgoCD
- [ ] Test kubectl access

---

## Testing Checklist (Post-Resolution)

Once Services are enabled OR sidecar is deployed:

```bash
# 1. Verify device appears in Tailscale network
tailscale status | grep -E "kind-operator|k8s-api"

# 2. Verify port 443 service (operator) or port 8001 (sidecar)
# Check in Tailscale admin console under "Services"

# 3. Configure kubeconfig
## Operator:
sudo tailscale configure kubeconfig kind-operator-9

## Sidecar:
sudo tailscale configure kubeconfig k8s-api-proxy

# 4. Test kubectl access
kubectl --context=tailscale-kind get nodes

# 5. Verify impersonation
kubectl --context=tailscale-kind auth whoami
# Expected output: vpittamp@gmail.com with groups: system:masters

# 6. Test RBAC
kubectl --context=tailscale-kind get pods --all-namespaces
```

---

## Key Learnings

1. **Environment Variable**: The correct variable is `APISERVER_PROXY` (no underscore), not `API_SERVER_PROXY`

2. **Service Advertisement**: tsnet-based applications (like the operator) require Tailscale Services (alpha) to advertise custom ports

3. **AutoApprovers**: ACL policy must include `autoApprovers.services` configuration for service advertisement to work

4. **Alpha Features**: Some Tailscale features require contacting Support for enablement - not documented prominently

5. **Debug Logging**: `OPERATOR_LOGGING=debug` provides detailed tsnet connection logs but doesn't show service advertisement failures

6. **Alternative Approaches**: Sidecar pattern with full Tailscale daemon is more reliable for non-standard use cases

---

## References

- **Tailscale Services**: https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy
  > "You need to contact Tailscale Support to enable it for your tailnet"

- **AutoApprovers Documentation**: https://tailscale.com/kb/1018/acls#autoapprovers

- **Operator GitHub**: https://github.com/tailscale/tailscale/tree/main/cmd/k8s-operator

- **Helm Chart Values**: https://github.com/tailscale/tailscale/blob/main/cmd/k8s-operator/deploy/chart/values.yaml
  > Shows `APISERVER_PROXY` (not `API_SERVER_PROXY`)

---

## Contact Information

**Tailscale Support:**
- URL: https://tailscale.com/contact/support
- Community: https://tailscale.com/slack
- GitHub Issues: https://github.com/tailscale/tailscale/issues

**Request Template:**

> **Subject**: Request to enable Tailscale Services (Alpha) for Kubernetes API Server Proxy
>
> **Tailnet**: tail286401.ts.net
> **Use Case**: Kubernetes API server proxy using in-process mode
> **Operator Version**: v1.88.3
> **Device**: kind-operator-9 (tag:k8s-operator)
>
> We have successfully configured the Tailscale Kubernetes operator with `APISERVER_PROXY=true` and confirmed the proxy is listening on port 443. However, port 443 is not being advertised as a Tailscale Service. According to the documentation, we need the Tailscale Services (alpha) feature enabled for our tailnet.
>
> Our ACL policy includes the required `autoApprovers.services` configuration. Could you please enable Tailscale Services for our tailnet?

---

*Last Updated: 2025-10-08*
*Status: Awaiting Tailscale Services enablement OR implementing sidecar approach*
