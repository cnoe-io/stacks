# Data Model: Tailscale Kubernetes Operator Configuration

**Feature**: Tailscale Remote Kubernetes Cluster Access
**Phase**: 1 (Design & Contracts)
**Date**: 2025-10-07

## Overview

This document defines the configuration entities, data structures, and relationships for the Tailscale Kubernetes Operator deployment. Since this is infrastructure-as-code, the "data model" represents TypeScript interfaces for chart configuration and Kubernetes resource specifications.

## Configuration Entities

### 1. TailscaleOperatorChartProps

**Purpose**: TypeScript interface for parameterized chart configuration

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `environmentName` | `'dev' \| 'staging' \| 'production'` | Yes | - | Target environment determining HA and resource allocation |
| `clusterName` | `string` | Yes | - | Cluster identifier used in operator naming |
| `oauthSecretName` | `string` | Yes | `'tailscale-oauth'` | Name of Kubernetes Secret containing OAuth credentials |
| `namespace` | `string` | No | `'tailscale'` | Kubernetes namespace for operator deployment |
| `enableHA` | `boolean` | No | `false` | Enable high-availability ProxyGroup (requires Tailscale Services alpha) |
| `proxyReplicas` | `number` | No | `2` | Number of proxy replicas when HA enabled |
| `operatorImage` | `string` | No | `'tailscale/operator:latest'` | Container image for operator deployment |
| `impersonationGrants` | `ImpersonationGrant[]` | No | `[]` | Tailscale group to Kubernetes group mappings |

**TypeScript Definition**:
```typescript
export interface TailscaleOperatorChartProps extends ChartProps {
  environmentName: 'dev' | 'staging' | 'production';
  clusterName: string;
  oauthSecretName?: string;
  namespace?: string;
  enableHA?: boolean;
  proxyReplicas?: number;
  operatorImage?: string;
  impersonationGrants?: ImpersonationGrant[];
}
```

**Validation Rules**:
- `clusterName` must be valid DNS label (lowercase alphanumeric + hyphens)
- `proxyReplicas` must be between 1 and 10
- If `enableHA` is true, `environmentName` should be `staging` or `production`
- `impersonationGrants` array must contain at least one entry for auth mode

### 2. ImpersonationGrant

**Purpose**: Maps Tailscale user groups to Kubernetes groups for identity-based access control

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `tailscaleGroup` | `string` | Yes | - | Tailscale group name (e.g., `group:admins`) |
| `kubernetesGroups` | `string[]` | Yes | - | Kubernetes groups for impersonation (e.g., `['system:masters']`) |
| `description` | `string` | No | - | Human-readable description of grant purpose |

**TypeScript Definition**:
```typescript
export interface ImpersonationGrant {
  tailscaleGroup: string;
  kubernetesGroups: string[];
  description?: string;
}
```

**Validation Rules**:
- `tailscaleGroup` must start with `group:`, `tag:`, or `user:`
- `kubernetesGroups` array must contain at least one entry
- Common Kubernetes groups: `system:masters`, `system:authenticated`, custom RBAC groups

**Example Configuration**:
```typescript
const grants: ImpersonationGrant[] = [
  {
    tailscaleGroup: 'group:admins',
    kubernetesGroups: ['system:masters'],
    description: 'Full cluster admin access for Tailscale admin group'
  },
  {
    tailscaleGroup: 'group:developers',
    kubernetesGroups: ['developers'],
    description: 'Developer namespace access via Kubernetes RBAC'
  },
  {
    tailscaleGroup: 'group:read-only',
    kubernetesGroups: ['view'],
    description: 'Read-only cluster access'
  }
];
```

### 3. OAuthCredentials

**Purpose**: Tailscale OAuth client credentials for operator authentication

**Fields**:

| Field | Type | Required | Storage | Description |
|-------|------|----------|---------|-------------|
| `clientId` | `string` | Yes | `.env-files/wi.env` (non-secret) | OAuth client identifier |
| `clientSecret` | `string` | Yes | Azure Key Vault → External Secret | OAuth client secret (sensitive) |
| `scopes` | `string[]` | Yes | Documentation | Required scopes: `['devices:write', 'auth_keys:write']` |
| `tags` | `string[]` | Yes | Tailnet policy | Required tags: `['tag:k8s-operator']` |

**Kubernetes Secret Structure** (created by External Secrets Operator):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tailscale-oauth
  namespace: tailscale
type: Opaque
stringData:
  clientId: "<OAuth client ID>"
  clientSecret: "<OAuth client secret>"
```

**External Secret Reference**:
```typescript
const oauthSecret = createEnvExternalSecret(this, 'tailscale-oauth', {
  namespace: props.namespace,
  secretStoreName: 'cluster-secret-store',
  data: {
    clientId: 'TAILSCALE_OAUTH_CLIENT_ID',
    clientSecret: 'TAILSCALE_OAUTH_CLIENT_SECRET'
  }
});
```

**Validation Rules**:
- `clientId` format: `k8s-<identifier>` (Tailscale convention)
- `clientSecret` must be >= 32 characters
- Scopes and tags validated by Tailscale API on operator startup

### 4. ProxyGroupSpec

**Purpose**: Kubernetes custom resource specification for high-availability API server proxy

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `type` | `'kube-apiserver'` | Yes | - | Proxy type (fixed for API server access) |
| `replicas` | `number` | Yes | `2` | Number of proxy instances |
| `tags` | `string[]` | Yes | `['tag:k8s']` | Tailscale tags for proxy authorization |
| `kubeApiServer.mode` | `'auth' \| 'noauth'` | Yes | `'auth'` | Authentication mode (always auth for identity-based access) |

**Kubernetes CRD Representation**:
```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyGroup
metadata:
  name: <clusterName>-api-server
  namespace: tailscale
spec:
  type: kube-apiserver
  replicas: 2
  tags:
    - tag:k8s
  kubeApiServer:
    mode: auth
```

**TypeScript CRD Import** (after `cdk8s import`):
```typescript
import { ProxyGroup } from '../imports/tailscale.com';

new ProxyGroup(this, 'api-server-proxy', {
  metadata: {
    name: `${props.clusterName}-api-server`,
    namespace: props.namespace,
    annotations: {
      'argocd.argoproj.io/sync-wave': '0'
    }
  },
  spec: {
    type: 'kube-apiserver',
    replicas: props.proxyReplicas,
    tags: ['tag:k8s'],
    kubeApiServer: {
      mode: 'auth'
    }
  }
});
```

**State Transitions**:
1. ProxyGroup created → Operator watches CRD
2. Operator provisions proxy pods → Pods register with Tailscale
3. Tailscale assigns DNS name → `<clusterName>-api-server.<tailnet>.ts.net`
4. Proxy pods ready → Load balanced API server access available
5. Pod failure → Operator replaces pod, Tailscale updates routing

**Validation Rules**:
- `replicas` must be odd number (2, 3, 5) for split-brain prevention
- `type` must be exactly `kube-apiserver` (case-sensitive)
- `tags` must include `tag:k8s` (authorized by tailnet policy)

### 5. TailnetPolicyConfiguration

**Purpose**: Tailscale network policy configuration for operator authorization

**JSON Structure**:
```json
{
  "tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"]
  },
  "grants": [
    {
      "src": ["<tailscale-group>"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["<kubernetes-group>"]
          }
        }]
      }
    }
  ]
}
```

**Fields**:

| Field | Purpose | Example |
|-------|---------|---------|
| `tagOwners` | Define tag ownership hierarchy | Operator owns `tag:k8s-operator`, proxies tagged `tag:k8s` |
| `grants[].src` | Source Tailscale identity | `group:admins`, `tag:ci-cd`, `user:alice@example.com` |
| `grants[].dst` | Destination resource tag | `tag:k8s-operator` (the API server proxy) |
| `grants[].app.tailscale.com/cap/kubernetes` | Kubernetes-specific capability | Impersonation configuration |
| `grants[].app...impersonate.groups` | Target Kubernetes groups | `system:masters`, `developers`, custom RBAC groups |

**Application via Tailscale CLI**:
```bash
# Save policy to file
cat > tailnet-policy.json <<EOF
{
  "tagOwners": {...},
  "grants": [...]
}
EOF

# Apply policy to tailnet
tailscale acl set tailnet-policy.json
```

**Validation Rules**:
- Policy JSON must conform to Tailscale ACL schema
- `tagOwners` must define all tags referenced in grants
- Grant sources must exist in tailnet (groups, tags, users)
- Impersonation groups should align with Kubernetes RBAC

## Entity Relationships

```
TailscaleOperatorChartProps (TypeScript)
  │
  ├─> OAuthCredentials (Azure Key Vault → External Secret)
  │     └─> Used by: Operator Deployment (env vars)
  │
  ├─> ImpersonationGrant[] (Tailnet Policy)
  │     └─> Referenced by: ProxyGroup auth mode
  │
  ├─> ProxyGroupSpec (Kubernetes CRD)
  │     └─> Created by: Operator (if enableHA=true)
  │
  └─> TailnetPolicyConfiguration (Tailscale API)
        ├─> Tag definitions for operator and proxies
        └─> Grants mapping groups to Kubernetes permissions
```

**Flow**:
1. Chart props define desired state (environment, HA, grants)
2. OAuth credentials provisioned via External Secrets
3. Operator deployed with credentials and RBAC
4. Tailnet policy configured with tags and grants (manual/scripted)
5. ProxyGroup created (if HA enabled) → Operator provisions proxies
6. Users connect via `tailscale configure kubeconfig` → kubectl works

## Configuration Validation Checklist

Before deploying the operator, validate:

- [ ] OAuth credentials created in Tailscale admin console
- [ ] OAuth client ID and secret stored in Azure Key Vault
- [ ] External Secret configured to sync credentials to `tailscale` namespace
- [ ] Tailnet policy includes `tag:k8s-operator` and `tag:k8s` definitions
- [ ] Impersonation grants configured for all required user groups
- [ ] HTTPS enabled for tailnet (verified via `tailscale status`)
- [ ] Chart props specify correct `environmentName` and `clusterName`
- [ ] RBAC permissions exist in Kubernetes for impersonated groups

## Example Complete Configuration

```typescript
// In cdk8s/config/applications.ts
{
  name: 'tailscale-operator',
  namespace: 'tailscale',
  chart: {
    type: 'TailscaleOperatorChart',
    props: {
      environmentName: 'production',
      clusterName: 'prod-us-east-1',
      oauthSecretName: 'tailscale-oauth',
      namespace: 'tailscale',
      enableHA: true,
      proxyReplicas: 3,
      operatorImage: 'tailscale/operator:v1.54.0',
      impersonationGrants: [
        {
          tailscaleGroup: 'group:platform-admins',
          kubernetesGroups: ['system:masters'],
          description: 'Full cluster admin access'
        },
        {
          tailscaleGroup: 'group:sre',
          kubernetesGroups: ['cluster-admin'],
          description: 'SRE team cluster-admin role'
        },
        {
          tailscaleGroup: 'group:developers',
          kubernetesGroups: ['developers'],
          description: 'Developer namespace access'
        }
      ]
    }
  },
  argocd: {
    syncWave: '-90',
    labels: {
      'app.kubernetes.io/name': 'tailscale-operator',
      'app.kubernetes.io/component': 'network-proxy'
    },
    syncPolicy: {
      automated: { prune: true, selfHeal: true }
    }
  }
}
```

This configuration creates:
- Tailscale operator in `tailscale` namespace
- HA API server proxy with 3 replicas (production)
- Identity-based access for 3 Tailscale groups
- GitOps deployment via ArgoCD with sync wave `-90`
