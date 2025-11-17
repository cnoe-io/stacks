# Feature Specification: Install kagent and kgateway with Agentgateway in Kubernetes

**Feature Branch**: `008-install-kagent-agentgateway-kubernetes`
**Created**: November 17, 2025
**Status**: Draft
**Input**: User description: "add kagent and agentgateway to my kubernetes configuration. use our cdk8s charts approach that synthesizes to yaml. review official documentation; don't worry about backwards compatibility; if there are kagent/agent gateway related resources that exist in our configuration, replace them completely; use argocd plugin via 1password to test if the deployed resources are working"

## Product Overview

This feature deploys two complementary products:

1. **kgateway v2.2.0** with **agentgateway enabled** - Kubernetes Gateway API implementation with AI-native gateway capabilities for MCP server traffic management, A2A protocol support, LLM routing, and security policies
2. **kagent v0.7.4** - Cloud-native AI agent framework for building and running AI agents in Kubernetes with built-in MCP server support (kmcp included by default since v0.7)

These work together to provide a complete AI agent infrastructure: kgateway/agentgateway handles the network layer (routing, security, observability for MCP/A2A traffic), while kagent provides the agent execution framework.

## Clarifications

### Session 2025-11-17

- Q: Should MCP server traffic from kagent agents flow through agentgateway, or should agentgateway only handle external MCP traffic? → A: All kagent agent-to-MCP traffic routes through agentgateway (internal + external unified control)
- Q: How should agents authenticate when accessing MCP servers through agentgateway? → A: API keys via External Secrets Operator with Azure Workload Identity (Key Vault stores Anthropic, OpenAI, Gemini API keys)
- Q: What observability approach should agentgateway use for MCP traffic monitoring? → A: OpenTelemetry integration (distributed tracing, metrics, spans for MCP calls)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy kgateway with Agentgateway for MCP Gateway (Priority: P1)

Platform engineer deploys kgateway with agentgateway enabled to provide MCP server gateway functionality, including traffic routing, authentication, rate limiting, and observability for AI agent communications.

**Why this priority**: Foundation for all MCP server traffic management. Without the gateway layer, MCP servers cannot be securely exposed, monitored, or managed at scale. Enables centralized control over agent-to-tool communications.

**Independent Test**: Can be fully tested by deploying kgateway Helm chart with agentgateway enabled and verifying the gateway proxy is running and can route traffic. Delivers value by providing enterprise-grade traffic management for AI workloads.

**Acceptance Scenarios**:

1. **Given** a Kubernetes cluster with Gateway API CRDs installed, **When** platform engineer deploys kgateway with `agentGateway.enabled=true` and `gateway.aiExtension.enabled=true`, **Then** kgateway control plane and gateway proxy pods are Running in kgateway-system namespace
2. **Given** kgateway is deployed, **When** platform engineer creates a Gateway resource with agentgateway configuration, **Then** the gateway accepts MCP and A2A protocol traffic
3. **Given** agentgateway is running, **When** platform engineer configures an MCP server backend, **Then** the gateway routes MCP protocol requests to the backend with proper authentication and telemetry

---

### User Story 2 - Deploy kagent AI Agent Framework (Priority: P2)

Platform engineer deploys kagent v0.7.4 to enable creation and management of AI agents in Kubernetes with built-in MCP server support through kmcp.

**Why this priority**: Core agent execution framework. Without kagent, no AI agents can be defined, executed, or managed. Provides the runtime for AI workloads that agentgateway protects.

**Independent Test**: Can be tested by deploying kagent Helm chart and verifying controller, UI, and engine components are operational. Delivers value by enabling Kubernetes-native AI agent deployment and management.

**Acceptance Scenarios**:

1. **Given** a Kubernetes cluster, **When** platform engineer deploys kagent v0.7.4 via Helm chart from `oci://ghcr.io/kagent-dev/kagent/helm/kagent`, **Then** kagent controller and UI pods are Running in kagent namespace
2. **Given** kagent is deployed, **When** platform engineer accesses the kagent dashboard, **Then** UI loads and displays agent management interface
3. **Given** kagent CRDs are installed, **When** platform engineer runs `kubectl get crds | grep kagent.dev`, **Then** Agent, ModelConfig, ToolServer CRDs are present

---

### User Story 3 - Configure LLM Provider Integration (Priority: P3)

Platform engineer configures LLM provider API keys via External Secrets Operator for both kagent agents and kgateway AI extension features.

**Why this priority**: Enables actual AI functionality. Without LLM credentials, neither kagent agents nor agentgateway's AI features (prompt guards, model failover) can function.

**Independent Test**: Can be tested by verifying ExternalSecret syncs credentials and ModelConfig resources report Ready status. Delivers value by enabling secure, GitOps-managed credential distribution for AI workloads.

**Acceptance Scenarios**:

1. **Given** Azure Key Vault contains LLM API keys, **When** ExternalSecret for LLM providers is deployed, **Then** secret is created with OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY
2. **Given** credentials are synced, **When** platform engineer creates a ModelConfig resource in kagent, **Then** ModelConfig status shows Ready
3. **Given** agentgateway is configured, **When** platform engineer creates an LLM backend with API key reference, **Then** agentgateway can proxy requests to LLM providers with authentication

---

### User Story 4 - Create AI Agents with MCP Tool Access (Priority: P4)

Platform engineer creates AI agents that use MCP servers deployed via kmcp, with traffic flowing through agentgateway for security and observability.

**Why this priority**: End-to-end validation of complete architecture. Demonstrates kagent agents using tools via MCP servers, with agentgateway providing traffic management.

**Independent Test**: Can be tested by creating a Kubernetes-focused agent and verifying it can query cluster resources through MCP tools. Delivers value by providing intelligent automation with enterprise traffic controls.

**Acceptance Scenarios**:

1. **Given** kagent and agentgateway are deployed, **When** platform engineer creates a ToolServer resource for Kubernetes tools, **Then** kmcp deploys the MCP server pod and service
2. **Given** MCP server is running, **When** platform engineer creates an Agent referencing the tools, **Then** agent status shows Ready and tools are available
3. **Given** agentgateway routing is configured, **When** agent makes tool calls, **Then** traffic flows through agentgateway with proper telemetry and access controls

---

### User Story 5 - Verify Deployment via ArgoCD with 1Password Authentication (Priority: P5)

Platform engineer validates complete deployment health and GitOps compliance using ArgoCD CLI authenticated via 1Password.

**Why this priority**: Operational validation and deployment confidence. Ensures all components are healthy and managed through GitOps workflow.

**Independent Test**: Can be tested by running ArgoCD CLI commands to verify sync status and health of all deployed applications. Delivers value by confirming reliable, auditable deployments.

**Acceptance Scenarios**:

1. **Given** kgateway and kagent applications are deployed via ArgoCD, **When** platform engineer runs `argocd app list --insecure`, **Then** all applications show Synced and Healthy status
2. **Given** ArgoCD shows healthy status, **When** platform engineer views application details, **Then** all child resources (pods, services, CRDs) show green health indicators
3. **Given** 1Password is configured, **When** platform engineer authenticates ArgoCD CLI, **Then** authentication succeeds and operations complete successfully

---

### Edge Cases

- What happens when Gateway API CRDs are not installed?
  - kgateway Helm chart fails to install with clear error message about missing Gateway API prerequisites
- How does system handle when agentgateway and kagent have version incompatibilities?
  - Document tested version combinations in deployment; controller logs show compatibility warnings
- What happens when MCP server deployed via kmcp fails health checks?
  - kagent controller reports unhealthy status on ToolServer resource; agent cannot use unavailable tools; agentgateway stops routing to unhealthy backend
- How does system handle rate limiting when agents exceed MCP server call quotas?
  - Agentgateway enforces rate limits; returns 429 responses; agent receives error and can retry with backoff
- What happens when LLM provider API keys are rotated in Azure Key Vault?
  - External Secrets automatically refreshes credentials at configured interval; ModelConfig remains operational without restart

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST install Kubernetes Gateway API CRDs v1.4.0 as prerequisite for kgateway
- **FR-002**: System MUST deploy kgateway CRDs via Helm chart from `oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds` version v2.2.0
- **FR-003**: System MUST deploy kgateway control plane with agentgateway enabled (`agentGateway.enabled=true`) and AI extension enabled (`gateway.aiExtension.enabled=true`)
- **FR-004**: System MUST create kgateway-system namespace for kgateway components
- **FR-005**: System MUST deploy kagent CRDs via Helm chart from `oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds` version v0.7.4
- **FR-006**: System MUST deploy kagent controller and UI via Helm chart from `oci://ghcr.io/kagent-dev/kagent/helm/kagent` version v0.7.4
- **FR-007**: System MUST enable kmcp (Kubernetes MCP) which is included by default in kagent v0.7.4
- **FR-008**: System MUST create kagent namespace for kagent components
- **FR-009**: System MUST sync LLM provider API keys (OpenAI, Anthropic, Gemini) from Azure Key Vault via External Secrets Operator using Azure Workload Identity for secure authentication
- **FR-010**: System MUST route ALL kagent agent-to-MCP server traffic through agentgateway for unified security, observability, and rate limiting (both internal cluster traffic and external access)
- **FR-011**: System MUST configure agentgateway with OpenTelemetry integration for distributed tracing, metrics, and spans for all MCP protocol calls
- **FR-012**: System MUST replace all existing kagent-related resources completely (no backwards compatibility required)
- **FR-013**: System MUST generate CDK8s charts that wrap official Helm charts using `include()` pattern
- **FR-014**: System MUST generate ArgoCD Application manifests with cnoe:// URL syntax for IdpBuilder compatibility
- **FR-015**: System MUST implement proper sync wave ordering: Gateway API CRDs (-130) → kgateway CRDs (-125) → kgateway (-120) → kagent CRDs (-115) → kagent (-110) → Secrets (-70) → Example Agents (50)
- **FR-016**: System MUST enable ArgoCD automated sync with prune and self-heal policies for all applications

### Key Entities

- **Gateway** (Kubernetes Gateway API): Gateway resource defining listeners and routes for kgateway
- **HTTPRoute**: Routing rules for HTTP/MCP traffic through agentgateway
- **Agent** (kagent.dev): AI agent definition with system message, tools, and model configuration
- **ModelConfig** (kagent.dev): LLM provider configuration (API endpoint, model name, credentials)
- **ToolServer** (kagent.dev): MCP tool server deployment specification managed by kmcp
- **ExternalSecret**: Azure Key Vault secret synchronization for LLM credentials
- **ArgoCD Application**: GitOps deployment unit with sync policies for each component

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: kgateway control plane and gateway proxy pods reach Running state within 5 minutes of deployment
- **SC-002**: kagent controller and UI pods reach Running state within 5 minutes of deployment
- **SC-003**: Agentgateway successfully routes MCP protocol traffic with less than 10ms added latency
- **SC-004**: External Secrets sync LLM credentials from Azure Key Vault with 1-hour refresh interval
- **SC-005**: AI agents respond to queries within 30 seconds of receiving request
- **SC-006**: ArgoCD reports all applications (kgateway, kagent, secrets) as Synced and Healthy within 15 minutes
- **SC-007**: Platform engineer can create first agent with MCP tool access within 20 minutes of full deployment
- **SC-008**: All CDK8s charts synthesize to valid Kubernetes YAML without TypeScript errors
- **SC-009**: ArgoCD CLI authenticated via 1Password successfully verifies deployment status
- **SC-010**: Complete replacement of existing kagent resources verified by removal of all deprecated custom charts

## Assumptions

- Kubernetes cluster version 1.26 or later (required for Gateway API v1.4.0)
- Helm v3.10+ available for OCI registry support
- Azure Key Vault contains LLM API keys (OPENAI-API-KEY, ANTHROPIC-API-KEY, GEMINI-API-KEY)
- External Secrets Operator and ClusterSecretStore for Azure Key Vault are already configured
- ArgoCD is installed and accessible at https://argocd.cnoe.localtest.me:8443
- IdpBuilder is available for deploying CDK8s synthesized packages
- Ingress-nginx controller is configured for external access
- 1Password CLI and ArgoCD plugin are installed for authentication
- Network policies allow egress to LLM provider APIs and OCI registries (ghcr.io, cr.kgateway.dev)
- Domain-based routing is enabled (*.cnoe.localtest.me resolves correctly)
- Cluster has sufficient resources: minimum 8GB RAM, 4 CPU for complete stack
