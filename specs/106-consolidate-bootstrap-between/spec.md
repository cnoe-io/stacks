# Feature Specification: Consolidate Bootstrap Between KIND and Talos Clusters

**Feature Branch**: `106-consolidate-bootstrap-between`
**Created**: 2025-12-07
**Updated**: 2025-12-07
**Status**: Draft
**Constitution**: v1.3.0 (aligns with Principles I, II, IV, VII, IX)
**Input**: User description: "Consolidate scripting/configuration between KIND and Talos cluster setup. Fully replace legacy implementations. No backward compatibility required."

## User Scenarios & Testing

### User Story 1 - Unified CDK8s Synthesis (Priority: P1)

As a platform operator, I want a single CDK8s entry point (`main.ts`) that works for both KIND and Talos clusters, so that I can maintain one codebase instead of two separate synthesis files.

**Why this priority**: This is the core consolidation - eliminating duplicate code between `main-v2.ts` and `main-talos.ts`.

**Independent Test**: Running `npm run synth` with `CLUSTER_TYPE=kind` produces KIND-appropriate manifests with `cnoe://` URLs, and with `CLUSTER_TYPE=talos` produces Talos-appropriate manifests with GitHub URLs.

**Acceptance Scenarios**:

1. **Given** `CLUSTER_TYPE=kind` is set, **When** I run `npm run synth`, **Then** ArgoCD Application sources use `cnoe://<app>/manifests` URLs and output goes to `cdk8s/dist/<app>/`.

2. **Given** `CLUSTER_TYPE=talos` is set, **When** I run `npm run synth`, **Then** ArgoCD Application sources use GitHub repository URLs with paths like `cdk8s/dist/<app>/manifests` and output goes to `cdk8s/dist/<app>/`.

3. **Given** `CLUSTER_TYPE` is not set, **When** I run `npm run synth`, **Then** synthesis defaults to `kind` behavior with a warning message.

---

### User Story 2 - Unified Application Configuration (Priority: P1)

As a platform operator, I want a single `applications.ts` configuration file with cluster-type filtering, so that I can see all applications in one place and understand which apply to which cluster.

**Why this priority**: Eliminates confusion about which apps exist for which cluster and reduces file duplication.

**Independent Test**: The merged `applications.ts` contains all apps from both `applications.ts` and `talos-applications.ts` with a `clusterType` field that filters correctly during synthesis.

**Acceptance Scenarios**:

1. **Given** an application config with `clusterType: 'kind'`, **When** synthesizing with `CLUSTER_TYPE=talos`, **Then** that application is excluded from output.

2. **Given** an application config with `clusterType: 'both'`, **When** synthesizing with either cluster type, **Then** that application is included with cluster-appropriate source URLs.

3. **Given** an application config with `clusterType: 'talos'`, **When** synthesizing with `CLUSTER_TYPE=kind`, **Then** that application is excluded from output.

---

### User Story 3 - Environment-Driven Configuration (Priority: P1)

As a platform operator, I want cluster-specific configuration loaded automatically from `.env-files/{cluster_type}.env`, so that I can switch between clusters by changing one environment variable.

**Why this priority**: Environment-driven configuration is the mechanism that makes unified synthesis work.

**Independent Test**: Setting `CLUSTER_TYPE=kind` loads `.env-files/kind.env` and setting `CLUSTER_TYPE=talos` loads `.env-files/talos.env`.

**Acceptance Scenarios**:

1. **Given** `.env-files/kind.env` contains `CLUSTER_TYPE=kind` and KIND-specific Azure variables, **When** I source the environment, **Then** all required variables for KIND synthesis are available.

2. **Given** `.env-files/talos.env` contains `CLUSTER_TYPE=talos` and Talos-specific Azure variables, **When** I source the environment, **Then** all required variables for Talos synthesis are available.

3. **Given** a required Azure variable is missing, **When** I run synthesis, **Then** I receive a clear error message listing the missing variable.

---

### User Story 4 - Legacy Script Replacement (Priority: P2)

As a platform operator, I want the legacy KIND scripts (`wi-kind.sh`, `wi-kind-lib.sh`) marked as deprecated and eventually removed, so that there's one clear way to bootstrap each cluster type.

**Why this priority**: Reduces confusion and maintenance burden by having clear, modern workflows.

**Independent Test**: Legacy scripts display deprecation warnings when sourced, and `cluster-menu.sh` is the documented approach for KIND.

**Acceptance Scenarios**:

1. **Given** I source `scripts/wi-kind-lib.sh`, **When** the file loads, **Then** a deprecation warning is displayed directing me to use `cluster-menu.sh`.

2. **Given** I want to bootstrap a KIND cluster, **When** I follow CLAUDE.md documentation, **Then** I'm directed to use `source deployment/scripts/cluster-menu.sh && cluster-deploy`.

---

### User Story 5 - Cluster-Specific Deployment Orchestration (Priority: P2)

As a platform operator, I want clear separation between cluster orchestrators (cluster-menu.sh for KIND, bootstrap-cluster.sh for Talos), so that each cluster type has an appropriate deployment strategy.

**Why this priority**: KIND uses idpbuilder (package-based), Talos uses Helm/kubectl (direct apply) - these are legitimately different approaches.

**Independent Test**: KIND deployment via `cluster-menu.sh` uses idpbuilder, Talos deployment via `bootstrap-cluster.sh` uses Helm.

**Acceptance Scenarios**:

1. **Given** a KIND cluster is running, **When** I run `cluster-deploy`, **Then** synthesis runs followed by `idpbuilder create --package cdk8s/dist/`.

2. **Given** a Talos cluster is running, **When** I run `./scripts/bootstrap-cluster.sh`, **Then** synthesis runs followed by Helm ArgoCD installation and kubectl apply.

---

### Edge Cases

- What happens when `CLUSTER_TYPE` is set to an unsupported value?
  - Synthesis fails with error: "Unsupported CLUSTER_TYPE: {value}. Supported: kind, talos"

- What happens when running synthesis without required Azure variables?
  - Synthesis fails early with list of missing variables before any manifests are generated.

- What happens when application config has invalid `clusterType` field?
  - TypeScript compilation fails (type-safe enum prevents invalid values).

## Requirements

### Functional Requirements

- **FR-001**: Single `cdk8s/main.ts` MUST replace both `main-v2.ts` and `main-talos.ts`.
- **FR-002**: `main.ts` MUST read `CLUSTER_TYPE` environment variable to determine synthesis behavior.
- **FR-003**: For `CLUSTER_TYPE=kind`, ArgoCD Application sources MUST use `cnoe://<app>/manifests` format.
- **FR-004**: For `CLUSTER_TYPE=talos`, ArgoCD Application sources MUST use GitHub repository URLs with manifest paths.
- **FR-005**: Single `cdk8s/config/applications.ts` MUST replace both `applications.ts` and `talos-applications.ts`.
- **FR-006**: Application config MUST support `clusterType: 'kind' | 'talos' | 'both'` field.
- **FR-007**: Synthesis MUST filter applications based on `clusterType` field and current `CLUSTER_TYPE`.
- **FR-008**: Environment files MUST follow `.env-files/{cluster_type}.env` naming convention.
- **FR-009**: Legacy scripts `wi-kind.sh` and `wi-kind-lib.sh` MUST display deprecation warnings when sourced.
- **FR-010**: `cdk8s/lib/source-url.ts` MUST provide centralized logic for ArgoCD source URL generation.

### What Gets Consolidated

| Component | Before | After |
|-----------|--------|-------|
| CDK8s entry point | `main-v2.ts`, `main-talos.ts` | `main.ts` |
| App configuration | `applications.ts`, `talos-applications.ts` | `applications.ts` with `clusterType` field |
| Environment files | `wi.env`, `talos.env` | `kind.env`, `talos.env` |
| Source URL logic | Inline in each main file | `cdk8s/lib/source-url.ts` |

### What Remains Distinct

| Component | KIND | Talos | Reason |
|-----------|------|-------|--------|
| Orchestrator | `cluster-menu.sh` | `bootstrap-cluster.sh` | Different deployment strategies |
| Deployment method | idpbuilder | Helm + kubectl | Architectural difference |
| ArgoCD source URLs | `cnoe://` (rewritten to Gitea) | GitHub URLs | Different Git sources |

### Key Entities

- **ClusterType**: Enum `'kind' | 'talos'` determining synthesis and deployment behavior
- **ApplicationConfig**: Configuration object with `name`, `namespace`, `chart`, `clusterType`, and ArgoCD settings
- **SourceUrl**: Generated ArgoCD Application source URL based on cluster type

## Success Criteria

### Measurable Outcomes

- **SC-001**: A single `npm run synth` command produces correct manifests for both cluster types based on `CLUSTER_TYPE` environment variable.
- **SC-002**: Line count reduction: Combined `main.ts` is smaller than sum of `main-v2.ts` + `main-talos.ts`.
- **SC-003**: All existing applications for both cluster types continue to synthesize correctly (no regressions).
- **SC-004**: KIND deployment via `cluster-menu.sh` completes successfully with unified synthesis.
- **SC-005**: Talos deployment via `bootstrap-cluster.sh` completes successfully with unified synthesis.
- **SC-006**: TypeScript compilation passes with merged application config (type safety maintained).

## Assumptions

- Operators have Node.js 18+ installed for CDK8s synthesis
- `CLUSTER_TYPE` environment variable will be set before synthesis (via direnv or manual export)
- Both cluster types support Kubernetes API version 1.29+
- GitHub repository URL format is consistent (`https://github.com/<org>/<repo>.git`)
- KIND uses idpbuilder exclusively; no manual kubectl apply needed
- Talos bootstrap continues to use existing 4-phase approach

## Constitution Alignment

This feature directly implements **Principle IX: Unified Cluster Bootstrap** from the constitution v1.3.0:

| Constitution Requirement | Spec Coverage |
|-------------------------|---------------|
| Single Synthesis Entry Point (`main.ts`) | FR-001, US1 |
| `CLUSTER_TYPE` environment variable | FR-002, US3 |
| Cluster-type-driven ArgoCD sources | FR-003, FR-004, US1 |
| Unified `applications.ts` with `clusterType` field | FR-005, FR-006, FR-007, US2 |
| Environment files naming convention | FR-008, US3 |
| Legacy script deprecation | FR-009, US4 |
| Centralized source URL utility | FR-010, US1 |

**Additional Principles Enforced:**
- **Principle I (Type-Safe IaC)**: Single `main.ts` per enforcement rule
- **Principle II (GitOps-First)**: Cluster-type-driven source URLs
- **Principle IV (Declarative Config)**: Unified `applications.ts`
- **Principle VII (Security)**: ESO patterns for both cluster types
