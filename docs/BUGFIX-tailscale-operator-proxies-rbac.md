# Bugfix: Tailscale Operator Missing Proxies ServiceAccount and RBAC

## Issue

Tailscale Operator was enabled but LoadBalancer services remained in `<pending>` state because:

1. **Missing ServiceAccount**: Operator created StatefulSets with `serviceAccountName: proxies` but did not auto-create this ServiceAccount
2. **Missing RBAC**: Proxy pods need `get/update/patch/create` permissions on Secrets to manage their Tailscale state

## Root Cause

The Tailscale Kubernetes Operator (v1.88.3) creates StatefulSets for LoadBalancer services but does not automatically provision the required `proxies` ServiceAccount and RBAC. This is unexpected behavior - the operator should create these resources automatically when reconciling LoadBalancer services.

## Error Messages

```
Warning  FailedCreate  create Pod ts-ts-kagent-ingress-x84ww-0 in StatefulSet
  ts-ts-kagent-ingress-x84ww failed error: pods "ts-ts-kagent-ingress-x84ww-0"
  is forbidden: error looking up service account tailscale/proxies:
  serviceaccount "proxies" not found
```

After manually creating ServiceAccount:

```
boot: error setting up for running on Kubernetes: some Kubernetes permissions
  are missing, please check your RBAC configuration:
  missing get permission on secret "ts-ts-kagent-ingress-x84ww-0"
  missing update permission on secret "ts-ts-kagent-ingress-x84ww-0"
```

## Solution

Added ServiceAccount and RBAC resources to `TailscaleOperatorChart`:

### 1. Proxies ServiceAccount

```typescript
// T011b: Create ServiceAccount for proxy pods
new k8s.KubeServiceAccount(this, 'proxies-sa', {
  metadata: {
    name: 'proxies',
    namespace: namespace,
    annotations: {
      'argocd.argoproj.io/sync-wave': '-90',
    },
  },
});
```

### 2. Proxies Role

```typescript
// T014b: Create Role for proxy pods
new k8s.KubeRole(this, 'proxies-role', {
  metadata: {
    name: 'proxies',
    namespace: namespace,
    annotations: {
      'argocd.argoproj.io/sync-wave': '-90',
    },
  },
  rules: [
    {
      apiGroups: [''],
      resources: ['secrets'],
      verbs: ['get', 'update', 'patch', 'create'],
    },
  ],
});
```

### 3. Proxies RoleBinding

```typescript
// T014c: Create RoleBinding for proxy pods
new k8s.KubeRoleBinding(this, 'proxies-rolebinding', {
  metadata: {
    name: 'proxies',
    namespace: namespace,
    annotations: {
      'argocd.argoproj.io/sync-wave': '-90',
    },
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Role',
    name: 'proxies',
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: 'proxies',
      namespace: namespace,
    },
  ],
});
```

## Verification

After applying the fix:

```bash
$ kubectl get pods -n tailscale | grep "ts-ts-"
ts-ts-agentgateway-ingress-7qg7k-0        1/1     Running   0          31s
ts-ts-argocd-ingress-4fhql-0              1/1     Running   0          31s
ts-ts-cnoe-ingress-9rrct-0                1/1     Running   0          31s
ts-ts-gitea-ingress-t7kf9-0               1/1     Running   0          31s
ts-ts-headlamp-ingress-5rqr9-0            1/1     Running   0          30s
ts-ts-kagent-ingress-x84ww-0              1/1     Running   0          113s
ts-ts-kargo-ingress-6lg99-0               1/1     Running   0          30s
ts-ts-kargo-webhooks-ingress-mrlch-0      1/1     Running   0          30s
ts-ts-keycloak-ingress-8mj5m-0            1/1     Running   0          30s

$ kubectl get svc -n ingress-nginx | grep LoadBalancer
ts-agentgateway-ingress    LoadBalancer   10.96.52.178    100.65.162.16,agentgateway-1.tail286401.ts.net      443:32541/TCP
ts-argocd-ingress          LoadBalancer   10.96.180.17    100.80.153.70,argocd-1.tail286401.ts.net            443:30091/TCP
ts-cnoe-ingress            LoadBalancer   10.96.12.216    100.84.82.126,cnoe-1.tail286401.ts.net              443:31916/TCP
ts-gitea-ingress           LoadBalancer   10.96.149.76    100.90.10.41,gitea-1.tail286401.ts.net              443:32563/TCP
ts-headlamp-ingress        LoadBalancer   10.96.116.236   100.90.34.55,headlamp-1.tail286401.ts.net           443:31088/TCP
ts-kagent-ingress          LoadBalancer   10.96.130.242   100.102.148.64,kagent-1.tail286401.ts.net           443:31036/TCP
ts-kargo-ingress           LoadBalancer   10.96.200.221   100.84.138.36,kargo-1.tail286401.ts.net             443:32631/TCP
ts-kargo-webhooks-ingress  LoadBalancer   10.96.196.101   100.104.117.69,kargo-webhooks-1.tail286401.ts.net   443:30352/TCP
ts-keycloak-ingress        LoadBalancer   10.96.158.4     100.72.87.25,keycloak-1.tail286401.ts.net           443:32306/TCP
```

All LoadBalancer services now have:
- ✅ External IPs assigned
- ✅ Tailscale hostnames (with `-1` suffix appended automatically)
- ✅ Proxy pods running successfully

## Files Changed

1. `cdk8s/charts/infra/tailscale-operator-chart.ts`: Added proxies ServiceAccount, Role, and RoleBinding
2. `cdk8s/config/applications.ts`: Uncommented tailscale-operator configuration, set `enableHA: false`

## Testing

Access services via Tailscale network from any Tailscale-connected device:

```bash
# Test from M1 browser or any Tailscale device
open https://kagent-1.tail286401.ts.net
open https://argocd-1.tail286401.ts.net
open https://gitea-1.tail286401.ts.net
```

## Notes

- **Hostname Suffix**: Tailscale automatically appends `-1`, `-2`, etc. to prevent conflicts with existing devices
- **Old Devices**: Previous devices (without suffix) are offline and can be deleted from Tailscale admin console
- **ProxyGroup**: Disabled in dev environments (`enableHA: false`) to avoid conflicts with `APISERVER_PROXY=true` in-process proxy mode
- **Sync Wave**: All RBAC resources use sync wave `-90` to ensure they're created before the operator deployment (wave `-70`)
