# Research: Tailscale Kubernetes Operator Deployment

**Feature**: Tailscale Remote Kubernetes Cluster Access
**Phase**: 0 (Research & Architecture Decisions)
**Date**: 2025-10-07

## Overview

This document captures research findings and architectural decisions for deploying the Tailscale Kubernetes Operator to enable secure remote cluster access via Tailscale network.

## Key Research Areas

### 1. Tailscale Operator Deployment Method

**Decision**: Use TypeScript CDK8s to generate native Kubernetes manifests instead of Helm chart consumption

**Rationale**:
- Constitution Principle I (Type Safety First) requires TypeScript with CDK8s
- CDK8s provides compile-time validation and type safety
- Native manifest generation enables fine-grained control over resource specifications
- Integrates seamlessly with existing chart factory pattern
- Allows customization of operator deployment without Helm value overrides

**Alternatives Considered**:
1. ❌ **Direct Helm chart deployment via ArgoCD**: Would bypass TypeScript type safety and CDK8s workflow
2. ❌ **Helm template rendering in CDK8s**: Adds complexity and reduces type safety benefits
3. ✅ **Native Kubernetes resources in TypeScript**: Aligns with constitution, provides maximum flexibility

**Implementation Approach**:
- Define operator Deployment, Service Account, RBAC, and CRDs as typed Kubernetes resources
- Use `imports/k8s.ts` for core resources (Deployment, ServiceAccount, ClusterRole, ClusterRoleBinding)
- Import Tailscale CRDs via `cdk8s import` from operator manifest or API specification
- Configure OAuth credentials via External Secrets Operator pattern

### 2. OAuth Credential Management

**Decision**: Store OAuth client secret in Azure Key Vault, sync via External Secrets Operator; store client ID in existing `.env-files/wi.env` (dev environment only)

**Rationale**:
- Constitution Principle VI mandates External Secrets Operator for sensitive data
- OAuth client secret is sensitive and must not be in Git
- OAuth client ID is non-secret metadata and can be version-controlled
- Existing `eso-helpers.ts` library provides reusable pattern for secret synchronization
- Azure Key Vault provides audit trail and access control for credential rotation

**Implementation Pattern**:
```typescript
// Use existing ESO helper
import { createEnvExternalSecret } from '../lib/eso-helpers';

const oauthSecret = createEnvExternalSecret(this, 'tailscale-oauth', {
  namespace: 'tailscale',
  secretStoreName: 'cluster-secret-store',
  data: {
    clientId: 'TAILSCALE_OAUTH_CLIENT_ID',
    clientSecret: 'TAILSCALE_OAUTH_CLIENT_SECRET'
  }
});
```

**Alternatives Considered**:
1. ❌ **Kubernetes Secret with base64 encoding**: Violates constitution, no audit trail
2. ❌ **Sealed Secrets**: Less mature ecosystem compared to ESO + Azure Key Vault
3. ✅ **External Secrets + Azure Key Vault**: Aligns with existing pattern, provides enterprise-grade secret management

### 3. Tailscale Policy Configuration

**Decision**: Use Tailscale CLI (`tailscale` command) to programmatically configure tailnet policy ACLs and tags

**Rationale**:
- Tailscale CLI provides declarative policy management via JSON files
- Enables automation of tag creation and grant configuration
- Can be integrated into deployment scripts or one-time setup tasks
- Provides idempotent operations (safe to re-run)

**Required Policy Configuration**:
```json
{
  "tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"]
  },
  "grants": [
    {
      "src": ["group:admins"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["system:masters"]
          }
        }]
      }
    },
    {
      "src": ["group:developers"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["developers"]
          }
        }]
      }
    }
  ]
}
```

**CLI Commands**:
```bash
# Create OAuth client
tailscale --auth-key="${TAILSCALE_AUTH_KEY}" oauth create \
  --name "k8s-operator-${CLUSTER_NAME}" \
  --device-write --auth-keys

# Update ACL policy (requires file with policy JSON)
tailscale acl set policy.json
```

**Alternatives Considered**:
1. ❌ **Manual web UI configuration**: Not automatable, error-prone, no version control
2. ❌ **Terraform Tailscale provider**: Adds infrastructure dependency, increases complexity
3. ✅ **Tailscale CLI**: Simple, scriptable, idempotent, aligns with existing workflow

### 4. API Server Proxy Configuration

**Decision**: Deploy in-cluster proxy by default (operator mode), offer optional ProxyGroup for HA as P3 feature

**Rationale**:
- In-cluster proxy sufficient for MVP (P1) and identity-based access (P2)
- ProxyGroup requires alpha Tailscale Services feature (must contact support to enable)
- Simpler architecture reduces operational complexity for initial deployment
- HA configuration can be added later without breaking changes

**Default Configuration (P1/P2)**:
- Operator automatically creates API server proxy on startup
- Single replica in-cluster proxy
- Auth mode enabled for identity-based access control

**Optional HA Configuration (P3)**:
```typescript
// Only create ProxyGroup if environment is staging/production
if (['staging', 'production'].includes(props.environmentName)) {
  new ProxyGroup(this, 'api-server-proxy', {
    metadata: {
      name: `${props.clusterName}-api-server`,
      namespace: 'tailscale'
    },
    spec: {
      type: 'kube-apiserver',
      replicas: props.replicas || 2,
      tags: ['tag:k8s'],
      kubeApiServer: {
        mode: 'auth'
      }
    }
  });
}
```

**Alternatives Considered**:
1. ❌ **ProxyGroup only**: Requires alpha feature, blocks MVP
2. ❌ **Multiple separate proxy deployments**: Complex, manual load balancing
3. ✅ **In-cluster default + optional ProxyGroup**: Supports both simple and HA use cases

### 5. HTTPS/TLS Configuration

**Decision**: Assume HTTPS is already enabled for tailnet, add validation check in quickstart guide

**Rationale**:
- HTTPS for tailnet is a prerequisite, not something the operator configures
- Most production Tailscale deployments have HTTPS enabled
- Quickstart guide can document verification step
- Error messages from operator will indicate if HTTPS is missing

**Validation Check**:
```bash
# Verify HTTPS is enabled
tailscale status --json | jq -r '.MagicDNSSuffix' | grep -q 'https' && echo "HTTPS enabled" || echo "ERROR: Enable HTTPS for tailnet"
```

**Alternatives Considered**:
1. ❌ **Programmatically enable HTTPS**: Not supported via Tailscale CLI
2. ❌ **Document manual web UI steps**: Error-prone, not automatable
3. ✅ **Prerequisite validation check**: Simple, clear, provides actionable error

### 6. CRD Import Strategy

**Decision**: Import Tailscale CRDs using `cdk8s import` from published operator manifests

**Rationale**:
- Matches existing pattern for External Secrets and Kargo CRDs
- Provides TypeScript type definitions for ProxyGroup and Connector resources
- Enables IDE autocomplete and compile-time validation
- Operator publishes CRDs in GitHub repository

**Import Command**:
```bash
# From cdk8s/ directory
cdk8s import https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_proxygroups.yaml
cdk8s import https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_connectors.yaml
cdk8s import https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_dnsconfigs.yaml
```

**Output**: `cdk8s/imports/tailscale.com.ts`

**Alternatives Considered**:
1. ❌ **Manual TypeScript interfaces**: Error-prone, out of sync with CRD schema
2. ❌ **Generic ApiObject usage**: No type safety, defeats purpose of TypeScript
3. ✅ **cdk8s import from CRD manifests**: Standard practice, provides full type safety

### 7. Sync Wave Configuration

**Decision**: Use the following sync wave ordering to ensure correct deployment sequence

| Resource | Sync Wave | Rationale |
|----------|-----------|-----------|
| Namespace (tailscale) | `-100` | Must exist before all other resources |
| CRDs (ProxyGroup, Connector, DNSConfig) | `-100` | Required before custom resources can be created |
| Operator Deployment | `-90` | Core operator must be running |
| ServiceAccount, RBAC | `-90` | Operator permissions needed at startup |
| External Secret (OAuth credentials) | `-80` | Credentials must be available before proxy creation |
| ProxyGroup (if HA enabled) | `0` | Requires operator to be healthy |

**Rationale**:
- Follows constitution's recommended sync wave ranges
- Prevents race conditions during deployment
- Enables parallel deployment of independent resources at same wave
- Operator can start immediately once RBAC and credentials are available

## Technology Stack Summary

| Component | Technology | Version/Source |
|-----------|-----------|----------------|
| Infrastructure Definition | TypeScript + CDK8s | TypeScript 5.x, cdk8s latest |
| Kubernetes Resources | imports/k8s.ts | Standard Kubernetes API types |
| Tailscale CRDs | imports/tailscale.com.ts | Imported from operator CRD manifests |
| Secret Management | External Secrets Operator | Existing installation, Azure Key Vault backend |
| GitOps Deployment | ArgoCD | Existing installation |
| Tailscale Operator | Kubernetes Deployment | Official Tailscale operator (latest stable) |
| Policy Management | Tailscale CLI | System tailscale command |

## Integration Points

### 1. External Secrets Operator Integration
- **Pattern**: Use existing `createEnvExternalSecret()` helper from `eso-helpers.ts`
- **Secret Store**: Existing `cluster-secret-store` ClusterSecretStore
- **Azure Key Vault Keys**:
  - `TAILSCALE_OAUTH_CLIENT_ID`
  - `TAILSCALE_OAUTH_CLIENT_SECRET`

### 2. ArgoCD Integration
- **Package Location**: `cdk8s/dist/tailscale-operator/`
- **Application Manifest**: `tailscale-operator.yaml` using `cnoe://` URL
- **Sync Policy**: Automated sync with prune and self-heal enabled
- **Health Check**: ArgoCD health assessments for Deployment and ProxyGroup

### 3. IdpBuilder Integration
- **Deployment**: `idpbuilder create --package cdk8s/dist/tailscale-operator`
- **Gitea Repository**: Created as `idpbuilder-localdev-tailscale-operator-manifests`
- **Local Testing**: Full GitOps workflow with Tailscale connectivity verification

### 4. Existing Chart Factory Integration
- **Registration**: Add `TailscaleOperatorChart` to `IdpBuilderChartFactory`
- **Configuration**: Entry in `config/applications.ts`:
  ```typescript
  {
    name: 'tailscale-operator',
    namespace: 'tailscale',
    chart: {
      type: 'TailscaleOperatorChart',
      props: {
        environmentName: 'dev', // or staging, production
        oauthSecretName: 'tailscale-oauth',
        enableHA: false // true for staging/production
      }
    },
    argocd: {
      syncWave: '-90',
      labels: { 'app.kubernetes.io/name': 'tailscale-operator' },
      syncPolicy: { automated: { prune: true, selfHeal: true } }
    }
  }
  ```

## Security Considerations

1. **OAuth Credential Rotation**:
   - OAuth secrets should be rotated periodically
   - Use Azure Key Vault access policies to control who can rotate secrets
   - Update External Secret to trigger operator pod restart on secret change

2. **RBAC Principle of Least Privilege**:
   - Operator requires ClusterRole for managing Tailscale resources
   - ServiceAccount scoped to tailscale namespace
   - Impersonation grants should be specific to user groups (no wildcard)

3. **Network Policies**:
   - Consider NetworkPolicy to restrict operator pod communication
   - Allow egress to Tailscale coordination servers
   - Allow egress to Kubernetes API server

4. **Audit Logging**:
   - Kubernetes audit logs capture API server access via Tailscale proxy
   - Tailscale logs show device authentication events
   - ArgoCD GitOps logs show deployment changes

## Performance Considerations

1. **API Proxy Latency**:
   - In-cluster proxy adds minimal latency (<10ms overhead)
   - Tailscale network adds latency based on geographic distance
   - ProxyGroup HA adds load balancing overhead (negligible)

2. **Operator Resource Requirements**:
   - Operator: 100m CPU, 128Mi memory (typical)
   - Proxy pod: 100m CPU, 128Mi memory per replica
   - ProxyGroup (HA): 2-5 replicas = 200m-500m CPU, 256Mi-640Mi memory

3. **Scaling Considerations**:
   - Single operator instance per cluster (no need for operator HA)
   - Proxy replicas scale based on API server request volume
   - ProxyGroup automatic load balancing across replicas

## Open Questions & Future Research

1. **Proxy Health Monitoring**: How to configure Kubernetes liveness/readiness probes for ProxyGroup pods?
2. **Certificate Management**: How does Tailscale handle TLS cert rotation for HTTPS-enabled tailnets?
3. **Multi-Cluster Support**: Pattern for managing multiple clusters with same Tailscale account?
4. **Metrics & Observability**: Does operator expose Prometheus metrics for monitoring?

*These questions can be addressed during implementation based on operator documentation and testing.*

## References

- [Tailscale Kubernetes Operator Overview](https://tailscale.com/kb/1236/kubernetes-operator)
- [API Server Proxy Configuration](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)
- [Tailscale CLI Documentation](https://tailscale.com/kb/1080/cli)
- [CDK8s Documentation](https://cdk8s.io/)
- Project Constitution v1.2.0: `/home/vpittamp/stacks/.specify/memory/constitution.md`
