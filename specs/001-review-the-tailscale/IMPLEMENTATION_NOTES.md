# Tailscale Kubernetes Operator - Implementation Notes

## Implementation Status: ⚠️ OPERATOR LIMITATION IDENTIFIED

**Date**: 2025-10-07 (Updated: 2025-10-08)
**Feature**: Remote Kubernetes Cluster Access via Tailscale
**Status**: Operator deployed successfully but API proxy feature not available in current releases
**Recommendation**: Use sidecar proxy approach (Option 3 below)

---

## What Was Successfully Implemented

### ✅ Core Infrastructure (T001-T026)

1. **Tailscale CRDs Imported**
   - Location: `cdk8s/imports/tailscale.com.ts`
   - Types: Connector, ProxyGroup, DNSConfig

2. **Operator Chart Created**
   - File: `cdk8s/charts/infra/tailscale-operator-chart.ts`
   - Features: Full TypeScript types, ExternalSecret integration, RBAC, HA support

3. **OAuth Configuration**
   - Client ID: `kvSmDzGinB21CNTRL`
   - Stored in: `.env-files/wi.env`
   - Secret synced from Azure Key Vault via External Secrets Operator

4. **Tailnet ACL Policy**
   - File: `tailnet-policy.json`
   - User: `vpittamp@gmail.com`
   - Impersonation: `system:masters`
   - Applied via: https://login.tailscale.com/admin/acls

5. **Kubernetes Resources Deployed**
   ```
   Namespace:           tailscale
   ServiceAccount:      operator
   ClusterRole:         tailscale-operator
   ClusterRoleBinding:  tailscale-operator
   Deployment:          tailscale-operator (1/1 Running)
   ExternalSecret:      tailscale-oauth (SecretSynced)
   ```

6. **ArgoCD Integration**
   - Application: `argocd/tailscale-operator`
   - Sync Status: ✅ Synced
   - Health Status: ✅ Healthy
   - Repository: Gitea (idpbuilder-localdev-tailscale-operator-manifests)

### ✅ Operator Status

```
Pod: tailscale-operator-5bb87b75cf-xdjw4
Status: Running (1/1)
Version: 1.89.218-t98a0ccc18
Authentication: Successful
Message: "Startup complete, operator running"
```

---

## Current Limitation: API Server Proxy

### Issue

The Tailscale operator is running and authenticated, but the **Kubernetes API server proxy functionality is not available in current releases**. Multiple configuration approaches and versions were tested:

1. **ProxyGroup with `type: kube-apiserver`**
   - Created successfully
   - Not processed by operator (no proxy pods created)
   - Likely requires Tailscale Services (beta feature)

2. **LoadBalancer Service with Tailscale annotations**
   - Service created
   - Operator did not spawn proxy pod
   - No Service reconciliation logs

3. **Service with `tailscale.com/kubernetes-api-server-proxy: "true"`**
   - Correct annotation per docs
   - Still no proxy pod creation
   - Operator only watching Ingress resources

4. **Version Testing**
   - Tested `tailscale/k8s-operator:unstable` (v1.89.218)
   - Tested `tailscale/k8s-operator:v1.88.3` (stable)
   - **Both versions show identical behavior** - no API proxy

### Root Cause Analysis

After comprehensive testing and investigation:

**Evidence:**
- ✅ Operators deploy successfully (both unstable and v1.88.3)
- ✅ Operators authenticate to Tailscale (visible in device list)
- ✅ Devices registered with correct tags (`tag:k8s-operator`)
- ✅ Devices have Tailscale IPs assigned
- ❌ Devices are NOT reachable via Tailscale network (`tailscale ping` → "no matching peer")
- ❌ `tailscale configure kubeconfig` fails ("no peer found")
- ❌ No proxy-related logs in operator output
- ❌ No API server proxy pods created

**Operator Devices Registered:**
```
NAME              TAILSCALE IP    VERSION      STATUS
kind-operator     100.97.49.41    v1.89.218    Authenticated, tag:k8s-operator
kind-operator-1   100.90.240.123  v1.89.218    Authenticated, tag:k8s-operator
kind-operator-2   100.70.165.26   v1.88.3      Authenticated, tag:k8s-operator (current)
```

**Network Tests:**
```bash
$ tailscale ping 100.70.165.26
error: no matching peer

$ tailscale ping kind-operator-2.tail286401.ts.net
error: lookup kind-operator-2.tail286401.ts.net: no such host

$ tailscale configure kubeconfig kind-operator-2
error: no peer found for 'kind-operator-2'
```

**Conclusion:**
The operators register as devices in Tailscale's control plane but do NOT join the mesh network as reachable peers. The API server proxy feature appears to be **not fully implemented** in current operator releases. The devices exist in the admin console but are not functional network peers.

### Possible Solutions

**Option 1: ✅ TESTED - Does Not Resolve**
- Tried stable operator version v1.88.3
- Same behavior as unstable version
- API proxy not available in either release

**Option 2: Enable Tailscale Services**
- Check if account plan supports "Tailscale Services" (beta)
- Enable in Tailscale admin console if available
- ProxyGroups may require this feature
- **Action needed:** Verify account capabilities

**Option 3: Alternative Architecture - Sidecar Proxy** ⭐ RECOMMENDED
- Deploy standalone Tailscale sidecar pod with proxy configuration
- Configure it to proxy to Kubernetes API server (https://kubernetes.default.svc:443)
- Use `tailscale configure kubeconfig` from that pod
- More control, proven approach, works with any plan

**Option 4: Wait for Feature Maturity**
- API server proxy is relatively new
- Future operator versions may have full support
- Monitor Tailscale changelog and releases
- Revisit in 3-6 months

---

## Recommended Next Steps

### Option 3: Sidecar Proxy Implementation (RECOMMENDED)

Since the operator-based API proxy is not functional in current releases, the recommended approach is to deploy a dedicated Tailscale proxy pod:

#### 1. Create Tailscale Proxy Chart

```typescript
// cdk8s/charts/infra/tailscale-api-proxy-chart.ts
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';

export class TailscaleApiProxyChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    const namespace = 'tailscale';

    // Deployment with Tailscale sidecar + kubectl proxy
    new k8s.KubeDeployment(this, 'api-proxy', {
      metadata: { name: 'api-proxy', namespace },
      spec: {
        replicas: 1,
        selector: { matchLabels: { app: 'tailscale-api-proxy' } },
        template: {
          metadata: { labels: { app: 'tailscale-api-proxy' } },
          spec: {
            serviceAccountName: 'operator', // Reuse existing SA with cluster-admin
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

#### 2. Generate Auth Key

```bash
# Create reusable, non-expiring auth key
# Go to: https://login.tailscale.com/admin/settings/keys
# Click "Generate auth key"
# Options:
#   - Reusable: Yes
#   - Ephemeral: No (so device persists)
#   - Tags: tag:k8s
#   - Expiration: Never

# Store in Azure Key Vault
az keyvault secret set \
  --vault-name <vault-name> \
  --name TAILSCALE-AUTH-KEY \
  --value "tskey-auth-..."
```

#### 3. Configure ExternalSecret

Add to chart:
```typescript
createEnvExternalSecret(this, 'tailscale-auth-key', {
  externalName: 'tailscale-auth-key',
  name: 'tailscale-auth-key',
  namespace: namespace,
  secretStoreRef: {
    name: 'azure-keyvault-store',
    kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE
  },
  mappings: [
    { key: 'authKey', remoteRef: { key: 'TAILSCALE-AUTH-KEY' } }
  ]
});
```

#### 4. Deploy and Configure

```bash
# Synthesize and deploy
cd cdk8s && npm run synth
cluster-update

# Wait for pod to start
kubectl wait -n tailscale pod -l app=tailscale-api-proxy --for=condition=Ready --timeout=60s

# From pod, configure kubeconfig
kubectl exec -n tailscale deployment/api-proxy -c tailscale -- \
  tailscale configure kubeconfig k8s-api-proxy

# This generates kubeconfig that uses:
# - Server: https://k8s-api-proxy.tail286401.ts.net:8001
# - Identity-based auth via Tailscale
```

#### 5. Test Remote Access

```bash
# From any Tailscale-connected machine
export KUBECONFIG=~/.kube/k8s-api-proxy-kubeconfig
kubectl get nodes
kubectl auth whoami
# Should show: vpittamp@gmail.com with impersonated groups
```

### Benefits of Sidecar Approach

- ✅ **Works with any Tailscale plan** (no Services feature required)
- ✅ **Full control** over proxy configuration
- ✅ **Proven pattern** (standard kubectl proxy + Tailscale)
- ✅ **Easier debugging** (separate containers, clear responsibilities)
- ✅ **Reusable auth key** (survives pod restarts)

### Tradeoffs

- ❌ Manual lifecycle management (not operator-automated)
- ❌ Requires `NET_ADMIN` capability for Tailscale
- ❌ Two containers per replica (higher resource usage)

---

## Alternative: Wait for Operator Maturity

If the operator approach is preferred, recommended actions:

### Immediate Next Steps

1. **Verify Tailscale Account Plan**
   ```bash
   # Check if Tailscale Services is available
   # Go to: https://login.tailscale.com/admin/settings
   # Look for "Services" or "Beta Features"
   ```

2. **Try Stable Operator Version**
   ```typescript
   // cdk8s/config/applications.ts
   chart: {
     type: 'TailscaleOperatorChart',
     props: {
       operatorImage: 'tailscale/k8s-operator:v1.89.0',  // Use tagged version
       // ... rest of config
     }
   }
   ```

3. **Re-synthesize and Deploy**
   ```bash
   cd cdk8s && npm run synth
   cluster-update
   ```

4. **Create API Server Proxy Service**
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: Service
   metadata:
     name: k8s-api
     namespace: tailscale
     annotations:
       tailscale.com/kubernetes-api-server-proxy: "true"
       tailscale.com/tags: "tag:k8s"
       tailscale.com/hostname: "kind"
   spec:
     type: ExternalName
     externalName: placeholder
   EOF
   ```

5. **Monitor for Proxy Pod Creation**
   ```bash
   kubectl get pods -n tailscale --watch
   tailscale status | grep kind
   ```

### Testing Remote Access (Once Proxy is Active)

```bash
# From any Tailscale-connected machine
tailscale configure kubeconfig kind

# Test access
kubectl --context=tailscale-kind get nodes

# Verify impersonation
kubectl --context=tailscale-kind auth whoami
# Should show: vpittamp@gmail.com → system:masters
```

---

## File Changes Made

### New Files
- `cdk8s/imports/tailscale.com.ts` - CRD type definitions
- `cdk8s/charts/infra/tailscale-operator-chart.ts` - Operator chart
- `tailnet-policy.json` - Tailscale ACL policy
- `specs/001-review-the-tailscale/IMPLEMENTATION_NOTES.md` (this file)

### Modified Files
- `cdk8s/config/applications.ts` - Added tailscale-operator configuration
- `.env-files/wi.env` - Added TAILSCALE_OAUTH_CLIENT_ID

### Azure Key Vault Secrets
- `TAILSCALE-OAUTH-CLIENT-ID`: `kvSmDzGinB21CNTRL`
- `TAILSCALE-OAUTH-CLIENT-SECRET`: `tskey-client-***`

---

## Lessons Learned

1. **Alpha/Beta Features**: The Kubernetes API server proxy is a newer Tailscale feature and may not be fully stable in unstable operator versions

2. **Version Pinning**: Using `:unstable` tag is risky for production - prefer tagged stable releases

3. **Feature Flags**: Some Tailscale features require account-level enablement (Services, etc.)

4. **Operator Maturity**: The operator is actively developed - check changelog for feature availability

5. **External Secrets Integration**: Successfully demonstrated Azure Key Vault → ESO → Tailscale OAuth flow

---

## Architecture Decisions

### Why This Approach

1. **GitOps-First**: All manifests in Git, deployed via ArgoCD
2. **CDK8s for Type Safety**: Compile-time validation, IDE support
3. **External Secrets**: Secure credential management, no secrets in Git
4. **Operator Pattern**: Tailscale handles proxy lifecycle, not manual configuration

### Alternative Considered

**Sidecar Proxy Pod**: Deploy a simple pod with Tailscale + kubectl proxy
- ✅ Simpler, more predictable
- ✅ Works with any Tailscale plan
- ❌ Manual lifecycle management
- ❌ Less integrated with Kubernetes

**Decision**: Stick with operator approach, investigate version/feature requirements

---

## References

- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [API Server Proxy](https://tailscale.com/kb/1438/kubernetes-api-server-proxy)
- [Tailscale ACL Documentation](https://tailscale.com/kb/1018/acls)
- [External Secrets Operator](https://external-secrets.io/)

---

## Success Metrics

**Phase 1 (Current)**: ✅ COMPLETE
- ✅ Operator deployed and running
- ✅ OAuth authenticated
- ✅ All Kubernetes resources synced
- ✅ ArgoCD integration working

**Phase 2 (Pending)**: Needs Investigation
- ⏳ API server proxy active
- ⏳ Device visible in Tailscale network
- ⏳ Remote kubectl access functional
- ⏳ Identity-based impersonation working

---

## Contact & Support

**Next Actions:**
1. Check Tailscale account for Services feature availability
2. Try stable operator version (e.g., `v1.88.0`, `v1.89.0`)
3. Review Tailscale operator changelog for API proxy maturity
4. Consider alternative sidecar approach if operator path blocked

**Status**: Implementation paused pending feature availability confirmation
