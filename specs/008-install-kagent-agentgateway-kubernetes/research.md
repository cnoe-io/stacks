# Research: kagent and kgateway with Agentgateway Deployment

**Date**: November 17, 2025
**Feature**: 008-install-kagent-agentgateway-kubernetes

## Executive Summary

This research consolidates findings on deploying kgateway v2.2.0 (with agentgateway) and kagent v0.7.4 to Kubernetes using official Helm charts. Key discovery: ArgoCD Application resources should reference Helm charts directly (not CDK8s include()), simplifying the deployment pattern.

---

## Decision 1: Helm Chart Integration Pattern

**Decision**: Use ArgoCD Application resources with Helm source type (not CDK8s include())

**Rationale**:
- ArgoCD has native Helm chart support with OCI registry authentication
- Helm values can be inline in Application spec
- Avoids complexity of CDK8s `include()` pattern for Helm charts
- Better GitOps story - ArgoCD manages the Helm lifecycle

**Alternatives Considered**:
- **CDK8s `include()` pattern**: Rejected because it requires Helm CLI during synthesis and adds complexity
- **Raw manifest generation**: Rejected because we'd lose Helm's dependency management and values templating

**Implementation**:
```typescript
// CDK8s chart generates ArgoCD Application with Helm source
new Application(this, 'kgateway', {
  source: {
    repoUrl: 'cr.kgateway.dev/kgateway-dev/charts/kgateway',
    targetRevision: 'v2.2.0',
    chart: 'kgateway',
    helm: {
      values: `
agentGateway:
  enabled: true
gateway:
  aiExtension:
    enabled: true
      `
    }
  }
});
```

---

## Decision 2: kgateway Helm Values for Agentgateway

**Decision**: Minimal values configuration with OpenTelemetry via GatewayParameters CRD

**Rationale**:
- kgateway uses GatewayParameters CRD for runtime configuration (not Helm values)
- OpenTelemetry tracing configured post-deployment via CRD
- Simplifies initial Helm deployment

**Helm Values** (minimal for agentgateway):
```yaml
agentGateway:
  enabled: true
gateway:
  aiExtension:
    enabled: true
```

**OpenTelemetry Configuration** (via GatewayParameters CRD):
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
metadata:
  name: kgateway-params
  namespace: kgateway-system
spec:
  kube:
    aiExtension:
      tracing:
        enabled: true
        endpoint: "http://opentelemetry-collector.telemetry.svc.cluster.local:4317"
        sampler:
          type: "traceidratio"
          arg: "1.0"
        protocol: "grpc"
        transportSecurity: "plaintext"
```

**Installation Commands**:
```bash
# Gateway API CRDs (prerequisite)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# kgateway CRDs
helm upgrade -i --create-namespace --namespace kgateway-system \
  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --version v2.2.0

# kgateway with agentgateway
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --set agentGateway.enabled=true \
  --set gateway.aiExtension.enabled=true \
  --version v2.2.0
```

---

## Decision 3: kagent v0.7.4 Helm Values

**Decision**: Use secret references for LLM providers (compatible with External Secrets Operator)

**Rationale**:
- kagent v0.7.4 supports `apiKeySecretRef` pattern
- External Secrets Operator creates secrets from Azure Key Vault
- No API keys hardcoded in values or charts
- KMCP included by default (no extra config needed)

**Helm Values** (production-ready):
```yaml
# kagent v0.7.4 values
namespace: kagent

controller:
  replicas: 1
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
  logLevel: info

ui:
  enabled: true
  replicas: 1
  service:
    type: ClusterIP
    port: 8080
  ingress:
    enabled: true
    className: "nginx"
    hosts:
      - kagent.cnoe.localtest.me

providers:
  default: openAI
  openAI:
    enabled: true
    model: "gpt-4"
    apiKeySecretRef: kagent-llm-providers
    apiKeySecretKey: OPENAI_API_KEY
  anthropic:
    enabled: true
    model: "claude-3-5-sonnet-20241022"
    apiKeySecretRef: kagent-llm-providers
    apiKeySecretKey: ANTHROPIC_API_KEY
  gemini:
    enabled: true
    model: "gemini-2.0-flash-exp"
    apiKeySecretRef: kagent-llm-providers
    apiKeySecretKey: GEMINI_API_KEY

kmcp:
  enabled: true  # Default since v0.7
  controller:
    replicas: 1
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "1000m"
        memory: "1Gi"

database:
  type: sqlite  # Use PostgreSQL for production HA
  sqlite:
    path: "/data/kagent.db"
  persistence:
    enabled: true
    size: "1Gi"
```

**Installation Command**:
```bash
helm install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  -n kagent --create-namespace --version v0.7.4

helm install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  -n kagent -f values.yaml --version v0.7.4
```

---

## Decision 4: External Secrets Configuration

**Decision**: Single ExternalSecret for all LLM providers using Azure Workload Identity

**Rationale**:
- Reuses existing ClusterSecretStore pattern
- Single secret with multiple keys simplifies management
- 1-hour refresh interval balances security and performance

**ExternalSecret Configuration**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kagent-llm-providers
  namespace: kagent
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault-store
    kind: ClusterSecretStore
  target:
    name: kagent-llm-providers
    creationPolicy: Owner
  data:
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: OPENAI-API-KEY
    - secretKey: ANTHROPIC_API_KEY
      remoteRef:
        key: ANTHROPIC-API-KEY
    - secretKey: GEMINI_API_KEY
      remoteRef:
        key: GEMINI-API-KEY
```

---

## Decision 5: ArgoCD Application Structure

**Decision**: Separate ArgoCD Applications per component with sync waves

**Rationale**:
- Clear dependency ordering via sync waves
- Independent health monitoring per component
- Granular rollback capability
- Matches existing IdpBuilder pattern

**Application Structure**:
| Application | Sync Wave | Source | Purpose |
|-------------|-----------|--------|---------|
| gateway-api-crds | -130 | URL (GitHub raw) | Gateway API CRDs |
| kgateway-crds | -125 | Helm (OCI) | kgateway CRDs |
| kgateway | -120 | Helm (OCI) | kgateway with agentgateway |
| kagent-crds | -115 | Helm (OCI) | kagent CRDs |
| kagent | -110 | Helm (OCI) | kagent platform |
| kagent-secrets | -70 | Manifests (cnoe://) | External Secrets |
| kagent-agents | 50 | Manifests (cnoe://) | Example agents |

---

## Decision 6: MCP Traffic Routing Architecture

**Decision**: kagent agents access MCP servers via agentgateway using Kubernetes Service DNS

**Rationale**:
- Unified observability and security
- Agentgateway provides rate limiting and authentication
- Standard Kubernetes networking

**Traffic Flow**:
```
Agent Pod → agentgateway Service (Gateway) → MCP Server Service → MCP Server Pod
```

**Configuration Required**:
1. Create Gateway resource for MCP traffic
2. Create HTTPRoute for each MCP server backend
3. Configure agentgateway backends for MCP servers
4. Update Agent resources to use gateway endpoint (not direct service)

---

## Decision 7: Ingress Strategy

**Decision**: Domain-based routing (existing pattern)

**Rationale**:
- Matches existing cluster configuration
- Separate TLS certificates per service
- Clear URL semantics

**URLs**:
- kgateway: `https://kgateway.cnoe.localtest.me:8443`
- kagent Dashboard: `https://kagent.cnoe.localtest.me:8443`
- ArgoCD: `https://argocd.cnoe.localtest.me:8443`

---

## Key Findings

### Breaking Changes in kagent v0.7.4
- API version changed to `kagent.dev/v1alpha2`
- Agent type field required (Declarative or BYO)
- ToolServer CRD removed (replaced by MCPServer via kmcp)
- KMCP now bundled by default

### kgateway v2.2.0 Features
- Native agentgateway integration
- Gateway API support (HTTPRoute, TCPRoute, TLSRoute)
- OpenTelemetry tracing via GatewayParameters CRD
- CEL-based RBAC for MCP/A2A protocols

### Integration Considerations
- Gateway API CRDs must be installed before kgateway
- kagent CRDs must be installed before kagent
- External Secrets must sync before kagent deployment (for LLM providers)
- OpenTelemetry collector should exist for tracing (or disable tracing initially)

---

## Open Questions (Deferred to Implementation)

1. **OpenTelemetry Collector**: Is there an existing OTel collector in the cluster, or should we deploy one?
   - **Default**: Disable tracing initially, document how to enable later

2. **PostgreSQL for kagent**: Should kagent use PostgreSQL instead of SQLite for HA?
   - **Default**: Use SQLite for simplicity, document PostgreSQL option

3. **Gateway resource configuration**: Exact listeners and routes for MCP traffic
   - **Default**: Create minimal Gateway resource, iterate based on testing

---

## References

- kgateway Helm Chart: `oci://cr.kgateway.dev/kgateway-dev/charts/kgateway`
- kagent Helm Chart: `oci://ghcr.io/kagent-dev/kagent/helm/kagent`
- Gateway API CRDs: https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.4.0
- kgateway Docs: https://kgateway.dev/docs/
- kagent Docs: https://kagent.dev/docs/
