# Implementation Plan: Install kagent and kgateway with Agentgateway in Kubernetes

**Branch**: `008-install-kagent-agentgateway-kubernetes` | **Date**: November 17, 2025 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-install-kagent-agentgateway-kubernetes/spec.md`

## Summary

Deploy kgateway v2.2.0 with agentgateway enabled (MCP server gateway functionality) and kagent v0.7.4 (AI agent framework) to Kubernetes using CDK8s TypeScript charts that wrap official Helm charts. All MCP traffic routes through agentgateway for unified security, observability (OpenTelemetry), and rate limiting. LLM credentials managed via External Secrets Operator with Azure Workload Identity.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s charts)
**Primary Dependencies**: CDK8s 2.x, cdk8s-plus-32, Helm (for chart inclusion)
**Storage**: N/A (infrastructure deployment, no application data storage)
**Testing**: TypeScript compilation validation, ArgoCD sync verification, kubectl health checks
**Target Platform**: Kubernetes 1.26+ (Kind cluster for local dev)
**Project Type**: Infrastructure-as-Code (GitOps CDK8s charts)
**Performance Goals**:
- kgateway/kagent pods Running within 5 minutes
- MCP traffic routing <10ms added latency
- ArgoCD Synced/Healthy within 15 minutes
**Constraints**:
- Official Helm charts must be used (OCI registries: ghcr.io, cr.kgateway.dev)
- Gateway API CRDs v1.4.0 prerequisite
- Azure Workload Identity for secrets
- OpenTelemetry for observability
**Scale/Scope**:
- Single Kind cluster deployment
- 6-8 ArgoCD Applications (Gateway API CRDs, kgateway CRDs, kgateway, kagent CRDs, kagent, secrets, example agents)
- Minimum 8GB RAM, 4 CPU

## Constitution Check

*GATE: No constitution file found. Proceeding with best practices.*

**Core Principles Applied**:
- Use official upstream Helm charts (not custom manifests)
- GitOps workflow via ArgoCD with automated sync
- Security via External Secrets Operator and Azure Workload Identity
- Observability via OpenTelemetry integration
- Type safety via CDK8s TypeScript (not raw YAML)

## Project Structure

### Documentation (this feature)

```
specs/008-install-kagent-agentgateway-kubernetes/
├── spec.md              # Feature specification (completed)
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (CRD schemas)
├── quickstart.md        # Phase 1 output (deployment guide)
├── contracts/           # Phase 1 output (Helm values schemas)
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   └── infra/
│       ├── gateway-api-crds-chart.ts      # NEW: Gateway API CRDs
│       ├── kgateway-crds-chart.ts         # NEW: kgateway CRDs (Helm wrapper)
│       ├── kgateway-chart.ts              # NEW: kgateway with agentgateway (Helm wrapper)
│       ├── kagent-crds-chart.ts           # REPLACE: kagent CRDs (Helm wrapper)
│       └── kagent-chart.ts                # REPLACE: kagent platform (Helm wrapper)
├── charts/
│   └── secrets/
│       └── kagent-secrets-chart.ts        # UPDATE: LLM provider secrets (ESO)
├── charts/
│   └── apps/
│       └── kagent-example-agents-chart.ts # REPLACE: Example agents
├── lib/
│   ├── helm-chart-wrapper.ts              # NEW: Helper for Helm chart inclusion
│   └── kagent-helpers.ts                  # UPDATE: Updated helper functions
├── config/
│   └── applications.ts                    # UPDATE: Application registry
├── imports/
│   └── kagent.dev.ts                      # UPDATE: CRD type definitions
└── main-v2.ts                             # UPDATE: Chart registration
```

**Structure Decision**: Infrastructure-as-Code pattern using CDK8s charts that synthesize to YAML. Each chart wraps an official Helm chart from OCI registry using `include()` or generates ArgoCD Application resources that reference Helm charts directly.

## Complexity Tracking

*No constitution violations to justify.*

| Aspect | Approach | Rationale |
|--------|----------|-----------|
| Helm Chart Integration | ArgoCD Application with Helm source | Simpler than CDK8s include(), leverages ArgoCD's native Helm support |
| CRD Installation | Separate sync waves per component | Ensures dependency ordering (Gateway API → kgateway → kagent) |
| Secret Management | External Secrets Operator | Already established pattern in cluster, no new tools |
| Observability | OpenTelemetry (agentgateway native) | Built-in to agentgateway, no additional configuration needed |
