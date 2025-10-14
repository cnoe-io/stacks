# Implementation Plan: Remote Kubernetes Cluster Access via Tailscale

**Branch**: `005-remote-kubernetes-cluster` | **Date**: 2025-10-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-remote-kubernetes-cluster/spec.md`

**User Testing Directive**: Test directly by SSH'ing to the Mac machine (via Tailscale) using tmux pane %30 for interactive validation during implementation.

## Summary

Implement secure remote Kubernetes cluster access for platform engineers and developers using Tailscale's API server proxy and ingress-nginx. Primary capabilities: (1) kubectl access from any Tailscale-connected device, (2) port-forward for pod debugging, (3) web UI access to cluster services (ArgoCD, Gitea, Backstage). Technical approach: Simplify existing Tailscale operator configuration by removing ProxyGroup conflicts, document TLS certificate handling for both auto-provisioned Tailscale HTTPS and cluster CA distribution, and validate end-to-end connectivity from Mac machine over Tailscale network.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s), Bash (cluster management scripts), YAML (synthesized manifests)
**Primary Dependencies**:
- cdk8s ^2.68.90 (Kubernetes manifest synthesis)
- Tailscale Kubernetes Operator v1.88.3 (API server proxy)
- External Secrets Operator (OAuth credential sync from Azure Key Vault)
- ingress-nginx (web UI exposure)
- CoreDNS (in-cluster DNS resolution)

**Storage**:
- Azure Key Vault: Tailscale OAuth credentials (TAILSCALE-OAUTH-CLIENT-ID, TAILSCALE-OAUTH-CLIENT-SECRET)
- Kubernetes Secrets: Cluster CA certificates, kubeconfig files
- Gitea in-cluster: ArgoCD Application manifests via cnoe:// URLs

**Testing**:
- Interactive validation: kubectl commands from Mac via Tailscale (tmux pane %30)
- Port-forward validation: Access pod services from remote machine
- Web browser testing: Load ArgoCD/Gitea UIs from Tailscale-connected device
- TLS validation: Verify certificate handling (Tailscale HTTPS and cluster CA)
- DNS resolution testing: Internal (CoreDNS) and external (Tailscale MagicDNS)

**Target Platform**:
- Local: kind Kubernetes v1.33.1 on Hetzner NixOS host
- Remote clients: macOS (kubectl), any OS with web browser and Tailscale
- Network: Tailscale mesh network (tail286401.ts.net)

**Project Type**: Infrastructure/Platform (CDK8s charts, deployment scripts, documentation)

**Performance Goals**:
- kubectl response time: <2 seconds for simple operations (get, describe)
- Port-forward stability: 1+ hour sessions without disconnection
- Web UI load time: <3 seconds for ArgoCD/Gitea pages
- DNS resolution: <100ms for hostname lookups

**Constraints**:
- Single-replica operator acceptable for dev (not production HA)
- TLS certificate limitations: Tailscale HTTPS requires org-level enablement
- Cluster CA signed certificates only valid for specific IPs (127.0.0.1, 10.96.0.1, 172.18.0.2)
- Tailscale API endpoint must be 443 (cannot use custom ports for HTTPS auto-provisioning)

**Scale/Scope**:
- Users: 5+ concurrent platform engineers/developers
- Clusters: Single kind cluster (localdev) initially, pattern extensible to multiple clusters
- Services: 3 web UIs (ArgoCD, Gitea, Backstage) + Kubernetes API proxy
- Documentation: Setup guide for new team members (<10 minute configuration time target)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Type-Safe Infrastructure as Code ✅ PASS
- **Requirement**: All Kubernetes manifests via CDK8s with TypeScript
- **Status**: PASS - Existing `TailscaleOperatorChart` in `cdk8s/charts/infra/tailscale-operator-chart.ts` uses CDK8s
- **Action**: Enhance existing chart, not create new YAML templates

### Principle II: GitOps-First Deployment ✅ PASS
- **Requirement**: Deploy via ArgoCD, use cluster-menu.sh wrappers
- **Status**: PASS - Tailscale operator already deployed via ArgoCD, will use `cluster-update` for changes
- **Action**: Synthesize to `cdk8s/dist/tailscale/manifests/`, deploy via `cnoe://` URL pattern

### Principle III: Multi-Environment Isolation ✅ PASS
- **Requirement**: VClusters for dev/staging, dedicated clusters for production
- **Status**: PASS - Tailscale operator deploys to single namespace (`tailscale`), access control via RBAC
- **Action**: No multi-environment concerns for infrastructure component

### Principle IV: Declarative Configuration ✅ PASS
- **Requirement**: All config in code, use config/applications.ts
- **Status**: PASS - Chart configuration via TailscaleOperatorChartProps interface
- **Action**: Verify `config/applications.ts` includes tailscale application entry

### Principle V: CNOE Technology Alignment ⚠️ REVIEW
- **Requirement**: CNOE-endorsed tools (Tailscale listed under "Remote Access")
- **Status**: PASS - Tailscale explicitly listed in constitution under Platform Capabilities
- **Action**: Document alignment with CNOE patterns for secure cluster access

### Principle VI: Package-Based Architecture ✅ PASS
- **Requirement**: Self-contained packages with manifests, kustomization.yaml, ArgoCD Application
- **Status**: PASS - Will synthesize to `cdk8s/dist/tailscale/` with kustomization and Application manifest
- **Action**: Ensure KustomizationGenerator creates proper kustomization.yaml

### Principle VII: Security by Default ✅ PASS
- **Requirement**: External Secrets, SecurityContext, resource limits, NetworkPolicies
- **Status**: PASS - OAuth credentials via External Secrets (Azure Key Vault), RBAC for impersonation
- **Action**: Add SecurityContext to operator deployment, document least-privilege RBAC patterns

### Principle VIII: AI-Augmented Platform Engineering ⚠️ REVIEW
- **Requirement**: AI agents for observability/troubleshooting with human oversight
- **Status**: NOT APPLICABLE - This feature is infrastructure provisioning, not AI automation
- **Action**: None required (manual kubectl testing from Mac sufficient)

**Constitution Gate Result**: ✅ PASS - No violations. All principles satisfied.

## Project Structure

### Documentation (this feature)

```
specs/005-remote-kubernetes-cluster/
├── spec.md                          # Feature specification (COMPLETE)
├── checklists/
│   └── requirements.md              # Spec quality validation (COMPLETE)
├── plan.md                          # This file (IN PROGRESS - Phase 0)
├── research.md                      # Technology decisions, TLS strategies (PHASE 0 - PENDING)
├── data-model.md                    # Key entities, relationships (PHASE 1 - PENDING)
├── quickstart.md                    # End-to-end setup guide (PHASE 1 - PENDING)
└── contracts/                       # API contracts (PHASE 1 - PENDING)
    ├── tailscale-operator-config.yaml  # Operator configuration schema
    ├── kubeconfig-template.yaml        # Remote kubeconfig template
    └── rbac-mappings.yaml              # Tailscale identity → K8s RBAC schema
```

### Source Code (repository root)

```
cdk8s/
├── charts/infra/
│   └── tailscale-operator-chart.ts      # EXISTING - Enhance with ProxyGroup removal, cert docs
├── config/
│   └── applications.ts                  # UPDATE - Verify tailscale application entry
├── lib/
│   ├── idpbuilder-chart-factory.ts      # VERIFY - TailscaleOperatorChart registration
│   └── argocd-sync-builders.ts          # USE - Sync wave helpers for operator deployment
└── dist/
    └── tailscale/
        ├── manifests/                   # GENERATED - Namespace, Deployment, RBAC, ExternalSecret
        │   ├── namespace.yaml
        │   ├── serviceaccount.yaml
        │   ├── clusterrole.yaml
        │   ├── clusterrolebinding.yaml
        │   ├── externalsecret.yaml
        │   ├── deployment.yaml
        │   └── kustomization.yaml       # AUTO-GENERATED by KustomizationGenerator
        └── tailscale.yaml               # ArgoCD Application with cnoe://tailscale/manifests

deployment/scripts/
├── cluster-menu.sh                      # USE - cluster-update function for deployment
└── tailscale/                           # NEW DIRECTORY - Tailscale-specific utilities
    ├── generate-kubeconfig.sh           # Generate remote kubeconfig from cluster credentials
    ├── test-kubectl-access.sh           # Validate kubectl commands from remote machine
    └── verify-dns-resolution.sh         # Test CoreDNS and Tailscale MagicDNS

docs/
└── tailscale-cluster-access.md          # NEW - Comprehensive guide for remote access setup
```

**Structure Decision**: Infrastructure enhancement pattern - modify existing TailscaleOperatorChart, add helper scripts to deployment/scripts/tailscale/, create user-facing documentation in docs/. No new application code or frontend/backend split required. All source in cdk8s/charts/infra/ per constitution's chart organization requirements.

## Complexity Tracking

*No constitutional violations - this section left empty as per template instructions.*

## Phase 0: Research & Decisions

**Status**: PENDING - Tasks to dispatch

### Research Tasks

1. **Tailscale Operator Configuration Simplification**
   - **Question**: How to eliminate ProxyGroup conflicts with in-process proxy mode?
   - **Research**: Review Tailscale operator documentation for APISERVER_PROXY=true + ProxyGroup interaction
   - **Deliverable**: Decision on ProxyGroup removal, document in research.md

2. **TLS Certificate Management Strategy**
   - **Question**: When to use Tailscale HTTPS auto-provisioning vs. cluster CA distribution?
   - **Research**: Compare certificate workflows, document tradeoffs
   - **Deliverable**: Decision matrix with use cases, document in research.md

3. **RBAC Impersonation Patterns**
   - **Question**: Best practices for mapping Tailscale identities (vpittamp@github) to Kubernetes groups?
   - **Research**: Review Tailscale impersonation docs, Kubernetes RBAC best practices
   - **Deliverable**: Recommended RBAC patterns, document in research.md

4. **CoreDNS Configuration for Tailscale**
   - **Question**: What CoreDNS rewrite rules are needed for Tailscale endpoints?
   - **Research**: Review idpBuilder CoreDNS setup, Tailscale MagicDNS interaction
   - **Deliverable**: CoreDNS configuration requirements, document in research.md

5. **Testing Strategy for Remote Access**
   - **Question**: How to validate kubectl, port-forward, and web UI access from Mac?
   - **Research**: Define test scenarios, acceptance criteria per user story
   - **Deliverable**: Test plan with specific commands, document in research.md

**Output**: research.md consolidating all decisions with rationale and alternatives considered

## Phase 1: Design & Contracts

**Status**: BLOCKED - Waiting for Phase 0 research completion

### Tasks (to execute after research.md complete)

1. **Generate data-model.md**
   - Extract entities from spec.md Key Entities section
   - Define relationships: TailscaleOperatorDeployment → KubernetesAPIProxy → RBACMappings
   - Document state transitions: OAuth secret sync → operator startup → API proxy ready

2. **Generate API contracts** (contracts/ directory)
   - `tailscale-operator-config.yaml`: Environment variables, OAuth secret refs, impersonation grants
   - `kubeconfig-template.yaml`: Template for remote kubectl configuration with Tailscale endpoint
   - `rbac-mappings.yaml`: ClusterRoleBinding examples for Tailscale identity mapping

3. **Generate quickstart.md**
   - End-to-end setup guide: Prerequisites → Configuration → Deployment → Validation
   - Troubleshooting section: Common errors (TLS, DNS, RBAC), resolution steps
   - Testing commands: kubectl from Mac, port-forward examples, web UI access

4. **Update agent context**
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
   - Add: Tailscale operator patterns, TLS certificate handling, RBAC impersonation
   - Preserve existing entries between markers

**Output**: data-model.md, contracts/*, quickstart.md, updated .claude-code-context.md

## Phase 2: Task Generation

**Status**: NOT STARTED - Use `/speckit.tasks` command after Phase 1 completion

This phase is outside the scope of `/speckit.plan`. After data-model.md and quickstart.md are complete, run `/speckit.tasks` to generate dependency-ordered implementation tasks in tasks.md.
