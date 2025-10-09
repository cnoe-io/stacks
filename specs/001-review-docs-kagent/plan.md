# Implementation Plan: Kubernetes-Native AI Agent Platform (kagent & kmcp)

**Branch**: `001-review-docs-kagent` | **Date**: 2025-10-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-review-docs-kagent/spec.md`

**Note**: This plan implements kagent (Kubernetes agent runtime) and kmcp (Kubernetes MCP server manager) using CDK8s TypeScript to deploy AI agents and custom tool servers to local kind cluster following GitOps patterns.

## Summary

This feature deploys a Kubernetes-native AI agent platform that enables platform engineers to create autonomous agents capable of interacting with Kubernetes resources, executing multi-step tasks, and using extensible tool servers for custom functionality. The implementation uses CDK8s TypeScript to generate Kubernetes manifests for:

1. **kagent CRDs and Controllers** - Custom resource definitions for Agent and ModelConfig resources, with a Go-based controller managing their lifecycle
2. **kagent Engine** - Python application running agent conversation loops using the AI Developer Kit (ADK) framework
3. **kmcp CRDs and Controllers** - Custom resource definitions for MCPServer resources with lifecycle management
4. **Example Agents** - Pre-configured agents demonstrating Kubernetes tool usage, web fetching, and multi-agent workflows
5. **Example MCP Servers** - Custom tool servers (Python FastMCP) for capabilities like web content fetching and domain-specific operations

The platform integrates with the existing Stacks GitOps architecture via ArgoCD, uses External Secrets Operator for LLM API keys, and follows all constitutional requirements for type-safe infrastructure as code, security by default, and package-based deployment.

**Technical Approach**: Leverage official kagent/kmcp Helm charts as source of truth for resource specifications, translate to CDK8s TypeScript charts, deploy via cnoe:// URL syntax for local development, and configure example agents/tools using upstream project examples.

## Technical Context

**Language/Version**: TypeScript 4.9+ (for CDK8s), Python 3.11+ (for MCP servers), Go 1.21+ (kagent/kmcp controllers - pre-built images)
**Primary Dependencies**: cdk8s, cdk8s-plus-32, @kubernetes/client-node (imports), fastmcp (Python MCP servers), kagent/kmcp Helm charts (reference)
**Storage**: N/A (agent conversation state is ephemeral or managed by kagent controller; no persistent database required for MVP)
**Testing**: TypeScript compilation (npm run compile), manifest validation (kubectl dry-run), ArgoCD sync verification
**Target Platform**: Kubernetes 1.27+ (local kind cluster for development, EKS/AKS for production)
**Project Type**: Infrastructure/Platform (CDK8s charts generating Kubernetes manifests)
**Performance Goals**: <5min platform deployment, <10min agent creation, <60sec multi-step task completion, 5+ concurrent conversations
**Constraints**: LLM API rate limits (provider-dependent), cluster resources (controller pods ~500MB RAM, agent engine pods ~1GB RAM per concurrent conversation)
**Scale/Scope**: Initial deployment supports 5-10 concurrent agents, 10-15 custom MCP servers, single-tenant (one namespace), local development focus (production multi-tenancy is future enhancement)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Type-Safe Infrastructure as Code ✅ **PASS**

- **Requirement**: All Kubernetes manifests defined using CDK8s with TypeScript
- **Compliance**: All kagent/kmcp resources (CRDs, Deployments, Services, Agents, MCPServers) will be defined as CDK8s TypeScript charts in `cdk8s/charts/infra/kagent-chart.ts` and `cdk8s/charts/apps/example-agents-chart.ts`
- **Implementation**: Use `imports/k8s` for exact YAML control of CRDs and Deployments; reference official Helm chart values as specifications but implement in TypeScript

### II. GitOps-First Deployment ✅ **PASS**

- **Requirement**: Deployed via ArgoCD using GitOps patterns with cnoe:// URL syntax
- **Compliance**:
  - ArgoCD Application manifest: `cdk8s/dist/kagent.yaml` (controller/CRDs), `cdk8s/dist/kagent-agents.yaml` (example agents)
  - Source URL: `cnoe://kagent/manifests` for local development
  - Sync waves: CRDs (-110), Namespaces (-100), ServiceAccounts (-90), Secrets (-70), Deployments (0), Agents/MCPServers (50)
- **Implementation**: Each chart synthesizes to `cdk8s/dist/<app>/manifests/` with kustomization.yaml; ArgoCD syncs from Gitea repo created by idpbuilder

### III. Multi-Environment Isolation ⚠️ **CONDITIONAL PASS**

- **Requirement**: Dev/staging use VClusters, production uses dedicated clusters
- **Compliance**: Initial implementation deploys to `kagent` namespace in local kind cluster (single-tenant)
- **Justification**: kagent/kmcp are platform infrastructure components (not per-environment apps); they manage agents across environments but run in shared platform namespace
- **Future**: When deploying production, kagent will run in dedicated platform cluster and manage agents in target VClusters via kubeconfig

### IV. Declarative Configuration ✅ **PASS**

- **Requirement**: All config declared in code via config/applications.ts
- **Compliance**:
  - Application config: Add `kagent`, `kmcp`, `kagent-agents` to `cdk8s/config/applications.ts`
  - Chart registration: Register `KagentChart`, `KmcpChart`, `KagentExampleAgentsChart` in `IdpBuilderChartFactory`
  - Secrets: LLM API keys managed via External Secrets Operator (`ExternalSecret` CRD syncing from Azure Key Vault)
- **Implementation**: No manual kubectl commands; all resources synthesized from TypeScript

### V. CNOE Technology Alignment ⚠️ **PARTIAL - JUSTIFIED DEVIATION**

- **Requirement**: Use CNOE-endorsed technologies
- **Compliance**: kagent/kmcp are not CNOE-endorsed tools (emerging technology, not yet adopted by CNOE cohort)
- **Justification**:
  - **Why Needed**: Enables Kubernetes-native AI agent workflows that integrate with existing platform (ArgoCD, Backstage, etc.)
  - **Simpler Alternative Rejected**: Running agents outside cluster (e.g., GitHub Actions with kubectl) - rejected because it doesn't provide agent-as-a-service capability or leverage Kubernetes orchestration
  - **Alignment**: kagent/kmcp follow CNCF patterns (CRDs, controllers, declarative APIs) and integrate with CNOE stack (ArgoCD for deployment, ESO for secrets, Keycloak for future auth)
- **Complexity Tracking**: See table below

### VI. Package-Based Architecture ✅ **PASS**

- **Requirement**: Self-contained packages with manifests, kustomization.yaml, ArgoCD Application
- **Compliance**:
  - Packages: `cdk8s/dist/kagent/manifests/` (CRDs + controllers), `cdk8s/dist/kmcp/manifests/` (MCP CRDs + controller), `cdk8s/dist/kagent-agents/manifests/` (example agents/tools)
  - Each includes `kustomization.yaml` generated by `KustomizationGenerator`
  - ArgoCD Applications: `cdk8s/dist/kagent.yaml`, `cdk8s/dist/kmcp.yaml`, `cdk8s/dist/kagent-agents.yaml`
- **Implementation**: Charts in `cdk8s/charts/infra/` (infrastructure) and `cdk8s/charts/apps/` (example agents)

### VII. Security by Default ✅ **PASS**

- **Requirement**: ESO for secrets, SecurityContext, resource limits, NetworkPolicies
- **Compliance**:
  - **Secrets**: LLM provider API keys via External Secrets Operator (`ExternalSecret` → Azure Key Vault)
  - **SecurityContext**: All pods define `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true` where feasible
  - **Resource Limits**: Controller pods (500MB RAM limit/250MB request), agent engine pods (1GB RAM limit/512MB request), MCP servers (512MB RAM limit/256MB request)
  - **NetworkPolicies**: Optional for initial local dev; required for production deployment
- **Implementation**: SecurityContext and resources defined in CDK8s chart; ExternalSecret chart for LLM API keys

## Project Structure

### Documentation (this feature)

```
specs/001-review-docs-kagent/
├── plan.md              # This file (/speckit.plan command output)
├── spec.md              # Feature specification (completed)
├── research.md          # Phase 0 output (technology decisions and Helm chart analysis)
├── data-model.md        # Phase 1 output (Agent, MCPServer, ModelConfig CRD schemas)
├── quickstart.md        # Phase 1 output (deployment and usage guide)
├── contracts/           # Phase 1 output (agent API examples, MCP tool protocol)
│   ├── agent-crd-schema.yaml
│   ├── mcpserver-crd-schema.yaml
│   ├── mcp-tool-protocol.md
│   └── example-agent-definitions.yaml
└── checklists/
    └── requirements.md  # Specification quality checklist (completed)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   ├── infra/
│   │   ├── kagent-chart.ts           # kagent CRDs, controller, engine
│   │   ├── kmcp-chart.ts             # kmcp CRDs, controller
│   │   └── kagent-secrets-chart.ts   # ExternalSecrets for LLM API keys
│   └── apps/
│       ├── kagent-example-agents-chart.ts  # Example agents (K8s, web fetch, A2A)
│       └── kagent-example-mcps-chart.ts    # Example MCP servers (fetch, custom)
├── lib/
│   ├── kagent-helpers.ts             # Reusable functions for Agent/MCPServer resource generation
│   └── mcp-tool-builders.ts          # Builders for common MCP server patterns
├── imports/
│   ├── kagent.dev.ts                 # kagent CRD types (generated via cdk8s import)
│   └── kmcp.dev.ts                   # kmcp CRD types (generated via cdk8s import)
├── config/
│   └── applications.ts               # Add kagent, kmcp, kagent-agents app configs
└── dist/                             # Synthesized output
    ├── kagent/
    │   └── manifests/
    │       ├── kagent-crds.yaml
    │       ├── kagent-namespace.yaml
    │       ├── kagent-serviceaccount.yaml
    │       ├── kagent-rbac.yaml
    │       ├── kagent-controller-deployment.yaml
    │       ├── kagent-engine-deployment.yaml
    │       ├── kagent-service.yaml
    │       ├── kagent-external-secret.yaml
    │       └── kustomization.yaml
    ├── kmcp/
    │   └── manifests/
    │       ├── kmcp-crds.yaml
    │       ├── kmcp-controller-deployment.yaml
    │       └── kustomization.yaml
    ├── kagent-agents/
    │   └── manifests/
    │       ├── k8s-agent.yaml         # Agent for Kubernetes resource queries
    │       ├── fetch-agent.yaml       # Agent with web fetch MCP tool
    │       ├── a2a-agent.yaml         # Agent with A2A protocol enabled
    │       ├── mcp-fetch-server.yaml  # MCPServer for web content fetching
    │       └── kustomization.yaml
    ├── kagent.yaml                    # ArgoCD Application for kagent platform
    ├── kmcp.yaml                      # ArgoCD Application for kmcp platform
    └── kagent-agents.yaml             # ArgoCD Application for example agents
```

**Structure Decision**: Infrastructure pattern with CDK8s charts in `cdk8s/charts/infra/` for platform components (kagent/kmcp controllers) and `cdk8s/charts/apps/` for example agents/tools. This follows existing Stacks architecture where platform services are in `infra/` and application workloads are in `apps/`. No frontend/backend split required - this is pure infrastructure deployment.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Non-CNOE Technology (kagent/kmcp) | Enables Kubernetes-native AI agent workflows, declarative agent management via CRDs, integration with existing K8s tooling (ArgoCD, Backstage, monitoring) | **Alternative 1**: Run agents as standalone Python scripts outside cluster - Rejected because it doesn't provide multi-tenancy, lifecycle management, or Kubernetes API integration. **Alternative 2**: Use Argo Workflows with LangChain - Rejected because workflows are imperative task execution, not autonomous conversational agents with tool use. **Alternative 3**: Wait for CNOE to endorse an agent framework - Rejected because kagent/kmcp follow CNCF patterns and integrate cleanly with existing CNOE stack; early adoption enables feedback to community. |
| Helm Chart Reference (not using Helm directly) | Official kagent/kmcp projects distribute via Helm charts; using charts as specification reference ensures compatibility with upstream | **Alternative**: Manually write all YAML manifests - Rejected because it creates maintenance burden (tracking upstream changes, missing best practices from official charts). **Mitigation**: Use Helm charts as reference only (analyze values, translate to CDK8s), not deploying Helm charts directly (violates Type-Safe IaC principle). |

**Post-Design Re-Check**: Constitution violations remain justified after Phase 1 design. kagent/kmcp provide unique value for Kubernetes-native agent workflows, and implementation follows all other constitutional principles (Type-Safe IaC, GitOps, Security by Default, Package-Based Architecture).
