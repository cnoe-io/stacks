# Research: kagent & kmcp Implementation

**Feature**: Kubernetes-Native AI Agent Platform
**Date**: 2025-10-08
**Research Phase**: Technology Decisions and Helm Chart Analysis

## Overview

This document captures research findings for implementing kagent (Kubernetes agent runtime) and kmcp (Kubernetes MCP server manager) using CDK8s TypeScript. Research focused on understanding official Helm chart structures, CRD schemas, deployment patterns, and integration approaches with existing Stacks platform.

## Key Decisions

### Decision 1: Use Helm Charts as Specification Reference (Not Direct Deployment)

**Chosen Approach**: Analyze official kagent/kmcp Helm charts to extract resource specifications, then implement equivalent resources using CDK8s TypeScript.

**Rationale**:
- Official Helm charts are authoritative source for resource specifications, RBAC requirements, and deployment patterns
- Extracting specifications from Helm ensures compatibility with upstream project best practices
- Implementing in CDK8s satisfies constitutional requirement for Type-Safe Infrastructure as Code
- Avoids "reinventing the wheel" by manually writing all YAML without reference

**Alternatives Considered**:
1. **Direct Helm Deployment** - Use `helm install` commands
   - **Rejected**: Violates Type-Safe IaC constitution principle; no TypeScript type checking or IDE support
2. **Manual YAML Writing** - Write all manifests from scratch without Helm reference
   - **Rejected**: High risk of missing required resources (RBAC, ServiceAccounts, ConfigMaps), deviating from upstream best practices

**Implementation**: Use `helm template` to render Helm charts locally, analyze output YAML, extract resource specifications (image versions, environment variables, RBAC rules), translate to CDK8s TypeScript charts.

---

### Decision 2: Deploy kagent and kmcp as Separate Packages

**Chosen Approach**: Three separate ArgoCD Applications:
1. `kagent` - kagent CRDs, controller, engine, dashboard
2. `kmcp` - kmcp CRDs, controller
3. `kagent-agents` - Example agents and MCP servers

**Rationale**:
- **Independent Lifecycle**: kagent and kmcp have separate release cycles; packaging separately enables independent upgrades
- **Dependency Ordering**: kagent CRDs must be deployed before Agent resources; kmcp CRDs before MCPServer resources
- **Optional Components**: Users may want kagent without kmcp, or vice versa (though typically both are needed)
- **Follows Package-Based Architecture**: Each package is self-contained with manifests, kustomization.yaml, ArgoCD Application

**Alternatives Considered**:
1. **Single Monolithic Package** - All resources in one `kagent-platform` package
   - **Rejected**: Creates tight coupling; cannot upgrade kagent without redeploying kmcp
2. **Per-Agent Packages** - Each example agent as separate package
   - **Rejected**: Too granular; excessive ArgoCD Applications for simple examples

**Implementation**: Sync wave ordering ensures CRDs deploy first (`-110`), controllers next (`0`), example resources last (`50`).

---

### Decision 3: LLM Provider API Key Management via External Secrets Operator

**Chosen Approach**: Use existing External Secrets Operator (ESO) to sync LLM provider API keys from Azure Key Vault into Kubernetes secrets.

**Rationale**:
- **Constitutional Requirement**: Security by Default principle mandates ESO for sensitive data
- **Existing Infrastructure**: ESO already deployed in Stacks platform; reuse existing pattern
- **Secret Rotation**: Azure Key Vault provides secret rotation capabilities; ESO automatically syncs updates
- **Multi-Provider Support**: Single ExternalSecret can fetch keys for OpenAI, Anthropic, Gemini, etc. from different Azure Key Vault secrets

**Alternatives Considered**:
1. **Kubernetes Secrets (Manual)** - Create secrets via `kubectl create secret`
   - **Rejected**: Violates Security by Default and Declarative Configuration principles; no secret rotation or audit trail
2. **Sealed Secrets** - Encrypt secrets in Git using Sealed Secrets controller
   - **Rejected**: Less secure than centralized secret store; rotation requires re-encryption and Git commits

**Implementation**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kagent-llm-api-keys
  namespace: kagent
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault-store  # Existing ClusterSecretStore
    kind: ClusterSecretStore
  target:
    name: kagent-llm-providers
    template:
      type: Opaque
      data:
        OPENAI_API_KEY: "{{ .openai_api_key }}"
        ANTHROPIC_API_KEY: "{{ .anthropic_api_key }}"
        GEMINI_API_KEY: "{{ .gemini_api_key }}"
  data:
    - secretKey: openai_api_key
      remoteRef:
        key: llm-providers/openai
        property: api_key
    - secretKey: anthropic_api_key
      remoteRef:
        key: llm-providers/anthropic
        property: api_key
    - secretKey: gemini_api_key
      remoteRef:
        key: llm-providers/gemini
        property: api_key
```

---

### Decision 4: kagent CRD Import Strategy

**Chosen Approach**: Use `cdk8s import` to generate TypeScript types for kagent and kmcp CRDs from their published schemas.

**Rationale**:
- **Type Safety**: Generated TypeScript types provide compile-time validation for Agent, MCPServer, ModelConfig resources
- **IDE Support**: Autocomplete for CRD fields (e.g., `agent.spec.declarative.systemMessage`)
- **Schema Enforcement**: cdk8s validates resource structure against CRD schema before synthesis
- **Upstream Compatibility**: Importing from published CRDs ensures compatibility with kagent/kmcp versions

**Alternatives Considered**:
1. **Manual Type Definitions** - Hand-write TypeScript interfaces for CRDs
   - **Rejected**: High maintenance burden; types drift from upstream CRD schemas; no schema validation
2. **Untyped Objects** - Use `any` or `Record<string, unknown>` for CRD specs
   - **Rejected**: Loses type safety benefits; defeats purpose of TypeScript/CDK8s

**Implementation**:
```bash
# In cdk8s/ directory
npm run import -- \
  https://raw.githubusercontent.com/kagent-dev/kagent/main/deploy/crds/kagent.dev_agents.yaml \
  https://raw.githubusercontent.com/kagent-dev/kagent/main/deploy/crds/kagent.dev_modelconfigs.yaml \
  https://raw.githubusercontent.com/kagent-dev/kmcp/main/deploy/crds/kmcp.dev_mcpservers.yaml

# Generates:
# cdk8s/imports/kagent.dev.ts
# cdk8s/imports/kmcp.dev.ts
```

---

### Decision 5: Example Agent Selection

**Chosen Approach**: Implement 3 example agents demonstrating core capabilities:
1. **k8s-agent** - Query Kubernetes resources using built-in k8s tools
2. **fetch-agent** - Fetch web content using custom MCP server
3. **a2a-agent** - Expose capabilities via Agent-to-Agent protocol for external integrations

**Rationale**:
- **Progressive Complexity**: k8s-agent is simplest (built-in tools only), fetch-agent adds custom MCP server, a2a-agent adds protocol exposure
- **User Story Coverage**: Maps directly to spec user stories (US2: agents, US3: custom tools, US4: interoperability)
- **Practical Utility**: k8s-agent useful for cluster operations, fetch-agent demonstrates extensibility, a2a-agent enables Slack/Discord integrations
- **Upstream Examples**: All three patterns have examples in official kagent documentation

**Alternatives Considered**:
1. **Single "Hello World" Agent** - Minimal example with no tools
   - **Rejected**: Not useful for demonstrating agent capabilities; users can't see value
2. **10+ Example Agents** - Comprehensive agent library
   - **Rejected**: Overkill for initial deployment; creates maintenance burden

**Agent Definitions** (see `contracts/example-agent-definitions.yaml` for full specs):
- **k8s-agent**: Uses `kagent-tool-server` (built-in) with `k8s_get_resources`, `k8s_get_available_api_resources` tools
- **fetch-agent**: Uses custom `mcp-website-fetcher` MCPServer with `fetch` tool
- **a2a-agent**: Exposes skills via A2A protocol (`get-resources-skill`), configurable endpoint

---

### Decision 6: MCP Server Implementation Language and Framework

**Chosen Approach**: Use Python 3.11+ with FastMCP framework for custom MCP servers.

**Rationale**:
- **Official Recommendation**: kagent/kmcp documentation examples use FastMCP (Python framework for Model Context Protocol servers)
- **Ecosystem**: FastMCP is actively maintained, has rich tool ecosystem, integrates with popular AI frameworks (LangChain, LlamaIndex)
- **Simplicity**: Python is accessible for platform engineers; FastMCP provides high-level abstractions for tool definition
- **UVX Deployment**: kmcp supports `uvx` command for running FastMCP servers (handles dependency installation automatically)

**Alternatives Considered**:
1. **TypeScript MCP Servers** - Use Node.js/TypeScript MCP SDK
   - **Rejected**: Less mature than FastMCP; fewer examples in kagent/kmcp docs; TypeScript already used for CDK8s (want language diversity for learning)
2. **Go MCP Servers** - Use Go MCP library
   - **Rejected**: Steeper learning curve; less ecosystem support; overkill for simple tool servers

**Implementation Example** (FastMCP server for web fetching):
```python
# my-mcp-server/main.py
from fastmcp import FastMCP

mcp = FastMCP("website-fetcher")

@mcp.tool()
def fetch(url: str) -> str:
    """Fetch content from a website URL."""
    import requests
    response = requests.get(url)
    return response.text

if __name__ == "__main__":
    mcp.run()
```

**MCPServer CRD** (deployed via CDK8s):
```typescript
new KubeMCPServer(this, 'mcp-website-fetcher', {
  metadata: { name: 'mcp-website-fetcher', namespace: 'kagent' },
  spec: {
    deployment: {
      cmd: 'uvx',
      args: ['mcp-server-fetch'],  // Published FastMCP package
      port: 3000,
    },
    transportType: 'stdio',
    stdioTransport: {},
  },
});
```

---

### Decision 7: kagent Dashboard Deployment Strategy

**Chosen Approach**: Include kagent dashboard deployment in `kagent` package, expose via Ingress with path `/kagent-dashboard`.

**Rationale**:
- **User Story Requirement**: FR-013 requires management interface for viewing agents and their status
- **Existing Pattern**: Stacks platform already exposes multiple UIs via ingress-nginx (ArgoCD, Backstage, Gitea)
- **Path-Based Routing**: Consistent with Stacks use of path-based routing for local development (`--use-path-routing` flag)
- **Optional for Production**: Can be disabled in production environments where CLI is preferred

**Alternatives Considered**:
1. **Port-Forward Only** - No ingress, users run `kubectl port-forward svc/kagent-dashboard`
   - **Rejected**: Inconsistent with other platform UIs; requires manual kubectl commands (less user-friendly)
2. **Separate Subdomain** - Expose at `kagent.cnoe.localtest.me`
   - **Rejected**: Adds complexity for local dev (CoreDNS rewrite rules); path-based routing is simpler

**Implementation**:
```typescript
new KubeIngress(this, 'kagent-dashboard-ingress', {
  metadata: {
    name: 'kagent-dashboard',
    namespace: 'kagent',
    annotations: {
      'nginx.ingress.kubernetes.io/rewrite-target': '/$2',
    },
  },
  spec: {
    ingressClassName: 'nginx',
    rules: [{
      host: 'cnoe.localtest.me',
      http: {
        paths: [{
          path: '/kagent-dashboard(/|$)(.*)',
          pathType: 'Prefix',
          backend: {
            service: {
              name: 'kagent-dashboard',
              port: { number: 8082 },
            },
          },
        }],
      },
    }],
  },
});
```

---

## Helm Chart Analysis Summary

### kagent Helm Chart Components

**Chart**: `oci://ghcr.io/kagent-dev/kagent/helm/kagent` (version: latest as of 2025-10-08)

**Resources Deployed**:
1. **CRDs** (deployed via separate `kagent-crds` chart):
   - `agents.kagent.dev/v1alpha2`
   - `modelconfigs.kagent.dev/v1alpha1`
   - `remotemcpservers.kagent.dev/v1alpha1`

2. **Namespace**: `kagent` (default, configurable)

3. **ServiceAccount**: `kagent-controller` (with RBAC for managing Agent/ModelConfig resources)

4. **RBAC**:
   - ClusterRole: `kagent-controller-role` (permissions: create/update/delete/get/list/watch Agents, ModelConfigs, Pods, Services, Deployments)
   - ClusterRoleBinding: `kagent-controller-rolebinding`

5. **Deployments**:
   - `kagent-controller`: Go-based controller managing Agent/ModelConfig lifecycle
     - Image: `ghcr.io/kagent-dev/kagent/controller:latest`
     - Resources: 500MB RAM limit, 250MB request; 500m CPU limit, 100m request
   - `kagent-app`: Python application running agent conversation loops (ADK-based)
     - Image: `ghcr.io/kagent-dev/kagent/app:latest`
     - Resources: 1GB RAM limit, 512MB request; 1000m CPU limit, 500m request
   - `kagent-dashboard`: Web UI for agent management (optional)
     - Image: `ghcr.io/kagent-dev/kagent/dashboard:latest`
     - Port: 8082

6. **Services**:
   - `kagent-controller`: ClusterIP on port 8083 (A2A protocol endpoint)
   - `kagent-dashboard`: ClusterIP on port 8082

7. **ConfigMap**: `kagent-config` (controller configuration, logging settings)

8. **Secret**: `kagent-llm-providers` (LLM provider API keys - **will replace with ExternalSecret**)

**Key Helm Values**:
```yaml
providers:
  default: openAI  # or anthropic, gemini, azureOpenAI, ollama
  openAI:
    apiKey: ""  # Required if default=openAI
  anthropic:
    apiKey: ""
  gemini:
    apiKey: ""

resources:
  controller:
    limits: { memory: 500Mi, cpu: 500m }
    requests: { memory: 250Mi, cpu: 100m }
  app:
    limits: { memory: 1Gi, cpu: 1000m }
    requests: { memory: 512Mi, cpu: 500m }

dashboard:
  enabled: true
```

---

### kmcp Helm Chart Components

**Chart**: `oci://ghcr.io/kagent-dev/kmcp/helm/kmcp` (version: latest as of 2025-10-08)

**Resources Deployed**:
1. **CRDs** (deployed via separate `kmcp-crds` chart):
   - `mcpservers.kmcp.dev/v1alpha1`

2. **Namespace**: `kmcp-system` (default, **will change to `kagent` for unified namespace**)

3. **ServiceAccount**: `kmcp-controller` (with RBAC for managing MCPServer resources)

4. **RBAC**:
   - ClusterRole: `kmcp-controller-role` (permissions: create/update/delete/get/list/watch MCPServers, Pods, Deployments, Services)
   - ClusterRoleBinding: `kmcp-controller-rolebinding`

5. **Deployment**:
   - `kmcp-controller`: Go-based controller managing MCPServer lifecycle
     - Image: `ghcr.io/kagent-dev/kmcp/controller:latest`
     - Resources: 500MB RAM limit, 250MB request; 500m CPU limit, 100m request

**Key Helm Values**:
```yaml
resources:
  controller:
    limits: { memory: 500Mi, cpu: 500m }
    requests: { memory: 250Mi, cpu: 100m }
```

---

## Integration Points with Existing Stacks Platform

### 1. ArgoCD GitOps Integration
- **Sync Waves**: kagent/kmcp CRDs at `-110`, controllers at `0`, examples at `50`
- **Source URL**: `cnoe://kagent/manifests` for local dev (idpbuilder rewrites to Gitea URL)
- **Sync Policy**: `automated: { prune: true, selfHeal: true }` for continuous reconciliation

### 2. External Secrets Operator
- **ClusterSecretStore**: Reuse existing `azure-keyvault-store` for LLM API keys
- **ExternalSecret**: `kagent-llm-providers` syncs keys from Azure Key Vault paths:
  - `llm-providers/openai` → `OPENAI_API_KEY`
  - `llm-providers/anthropic` → `ANTHROPIC_API_KEY`
  - `llm-providers/gemini` → `GEMINI_API_KEY`

### 3. Ingress-Nginx
- **Dashboard Ingress**: Path `/kagent-dashboard` → `kagent-dashboard:8082`
- **A2A Protocol Endpoint**: Path `/api/a2a` → `kagent-controller:8083` (for external agent integrations)

### 4. Backstage Integration (Future)
- **Software Catalog**: Register agents as Backstage components (catalog-info.yaml in Git repo)
- **Templates**: Create Backstage templates for generating Agent/MCPServer definitions
- **Plugin**: Develop Backstage plugin to visualize agent status and invoke agents via UI

### 5. Keycloak SSO (Future)
- **Dashboard Authentication**: Integrate kagent dashboard with Keycloak for SSO
- **A2A Protocol Auth**: Use Keycloak OAuth2 tokens for agent-to-agent communication

---

## Technology Stack Summary

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| **Infrastructure as Code** | CDK8s | 2.x | Generate Kubernetes manifests from TypeScript |
| **Agent Runtime** | kagent | latest | Kubernetes controller for Agent/ModelConfig CRDs |
| **MCP Server Manager** | kmcp | latest | Kubernetes controller for MCPServer CRDs |
| **Agent Engine** | Python + ADK | 3.11+ | Execute agent conversation loops and tool invocations |
| **MCP Servers** | Python + FastMCP | 3.11+ | Implement custom tools for agents |
| **LLM Providers** | OpenAI, Anthropic, Gemini, Azure OpenAI, Ollama | N/A | Provide AI model inference for agents |
| **Secret Management** | External Secrets Operator | Existing | Sync LLM API keys from Azure Key Vault |
| **GitOps** | ArgoCD | Existing | Deploy and sync all resources from Git |
| **Ingress** | ingress-nginx | Existing | Expose dashboard and A2A protocol endpoints |
| **Cluster** | kind | 0.20+ (local), EKS/AKS (prod) | Kubernetes runtime |

---

## Next Steps (Phase 1: Design)

1. **data-model.md**: Document CRD schemas for Agent, MCPServer, ModelConfig with field descriptions and examples
2. **contracts/**: Generate example YAML for agents, MCP servers, and MCP tool protocol documentation
3. **quickstart.md**: Step-by-step deployment and usage guide (prerequisites, installation, creating first agent, testing)
4. **Update CLAUDE.md**: Add kagent/kmcp commands, troubleshooting, and integration patterns

---

## References

- [kagent GitHub](https://github.com/kagent-dev/kagent)
- [kmcp GitHub](https://github.com/kagent-dev/kmcp)
- [kagent Documentation](https://kagent.dev/docs/kagent)
- [kmcp Documentation](https://kagent.dev/docs/kmcp)
- [FastMCP Framework](https://github.com/jlowin/fastmcp)
- [Model Context Protocol Specification](https://modelcontextprotocol.io)
- [AI Developer Kit (ADK)](https://github.com/anthropics/anthropic-sdk-python)
