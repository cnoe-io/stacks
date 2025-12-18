# Implementation Plan: Kargo Progressive Delivery Pipelines Framework

**Branch**: `105-setup-kargo-pipelines` | **Date**: 2025-12-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/105-setup-kargo-pipelines/spec.md`

## Summary

Create a CDK8s-based framework for Kargo progressive delivery pipelines supporting a parallel pipeline architecture: an **Inner Loop** (Gitea → local-dev) for rapid sub-minute developer iteration, and an **Outer Loop** (GitHub → dev → staging → production) for CI-verified production deployments. Backstage serves as the first pipeline implementation. Webhooks from both Gitea (in-cluster) and GitHub (external) provide instant image detection.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s)
**Primary Dependencies**: cdk8s, cdk8s-cli, constructs, @kubernetes/client-node
**Storage**: N/A (Kubernetes CRDs, External Secrets for credentials)
**Testing**: Manual validation via ArgoCD sync, `kubectl` verification, Kargo UI
**Target Platform**: Kubernetes (KIND for local dev, Talos for staging)
**Project Type**: Infrastructure-as-Code (CDK8s charts)
**Performance Goals**: Inner loop: 60s end-to-end (image push → running pod); Outer loop: 30s Freight creation, 2min auto-promotion
**Constraints**: KIND cluster ephemeral (inner loop state lost on rebuild); external webhook TLS required for GitHub
**Scale/Scope**: Initial: 1 application (Backstage); Framework: 10+ applications

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**No constitution file found** - proceeding without gate validation. The design follows established CDK8s patterns in this repository.

## Project Structure

### Documentation (this feature)

```
specs/105-setup-kargo-pipelines/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (Kargo CRD manifests)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   └── pipelines/                           # Pipeline chart modules
│       ├── kargo-pipelines-project-chart.ts # Existing: Project, ProjectConfig, RBAC
│       ├── kargo-backstage-pipeline-chart.ts # NEW: Backstage inner+outer loop
│       └── kargo-pipeline-factory.ts        # NEW: Reusable pipeline generator
├── config/
│   └── applications.ts                      # Add pipeline app configs
├── imports/
│   └── kargo.akuity.io.ts                   # Existing: Kargo CRD types
└── lib/
    └── kargo-helpers.ts                     # NEW: Pipeline construction utilities
```

**Structure Decision**: Extends existing `cdk8s/charts/pipelines/` structure. New charts follow established patterns in `kargo-pipelines-project-chart.ts`. The factory pattern enables framework extensibility for additional applications.

## Complexity Tracking

*No constitution violations to justify.*

---

## Phase 0: Research

### Research Tasks

1. **Kargo Warehouse Configuration for OCI Registries**
   - How to configure Warehouses for Gitea OCI registry (in-cluster)
   - How to configure Warehouses for GHCR (external)
   - Image subscription patterns and tag filters

2. **Kargo Stage and Promotion Configuration**
   - Stage-to-Stage relationships and promotion flows
   - Auto-promotion policies
   - Manual promotion approval workflows

3. **Kargo Webhook Configuration**
   - ProjectConfig webhookReceivers for GitHub-compatible webhooks
   - Webhook secret management
   - External vs in-cluster webhook endpoints

4. **ArgoCD Integration Patterns**
   - `argocd-update` promotion step configuration
   - `kargo.akuity.io/authorized-stage` annotation requirements
   - Multi-cluster ArgoCD Application management

5. **Existing Codebase Patterns**
   - Current kargo-pipelines-project-chart.ts implementation
   - ESO patterns for credential management
   - ArgoCD Application chart patterns

### Output

See [research.md](./research.md) for consolidated findings.

---

## Phase 1: Design

### Data Model

See [data-model.md](./data-model.md) for entity definitions.

### Contracts

See [contracts/](./contracts/) for Kargo CRD specifications:
- `warehouse-gitea-oci.yaml` - Inner loop warehouse
- `warehouse-github-ghcr.yaml` - Outer loop warehouse
- `stage-local-dev.yaml` - Inner loop stage
- `stage-dev.yaml` - Outer loop first stage
- `stage-staging.yaml` - Outer loop second stage
- `stage-production.yaml` - Outer loop placeholder

### Quickstart

See [quickstart.md](./quickstart.md) for deployment and validation steps.
