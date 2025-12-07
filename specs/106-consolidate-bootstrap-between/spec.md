# Feature Specification: Consolidate Bootstrap Between KIND and Talos Clusters

**Feature Branch**: `106-consolidate-bootstrap-between`
**Created**: 2025-12-07
**Status**: Draft
**Input**: User description: "create a new feature that explores whether we can consolidate our scripting/configuration between our kind cluster setup and our talos cluster setup. this includes azure infrastructure setup, azure workload identity setup, cdk8s synthesis, applying manifests for cluster setup. we should consider parameterizing values by using our *.env files, using conditional logic in our cdk8s charts that correspond to the different environments, etc."

## User Scenarios & Testing

### User Story 1 - Unified Bootstrap Experience (Priority: P1)

As a platform operator, I want a single bootstrap command that works across both KIND and Talos clusters, so that I don't need to learn and maintain two different bootstrap workflows.

**Why this priority**: This is the core value proposition - reducing cognitive overhead and maintenance burden by having one consistent experience regardless of cluster type.

**Independent Test**: Running `./scripts/bootstrap-cluster.sh` on either a KIND or Talos cluster successfully completes the bootstrap process with cluster-appropriate behavior.

**Acceptance Scenarios**:

1. **Given** a KIND cluster is running and kubectl context is set, **When** I run `./scripts/bootstrap-cluster.sh --setup-azure`, **Then** the bootstrap detects KIND cluster type and executes KIND-appropriate steps (direnv environment loading, Azure AD app setup, CDK8s synthesis, ArgoCD installation via idpBuilder).

2. **Given** a Talos cluster is running and kubectl context is set, **When** I run `./scripts/bootstrap-cluster.sh --setup-azure`, **Then** the bootstrap detects Talos cluster type and executes Talos-appropriate steps (direnv environment loading, Azure AD app setup, CDK8s synthesis, ArgoCD installation via Helm, JWKS sync to Azure Storage).

3. **Given** an unsupported cluster type, **When** I run `./scripts/bootstrap-cluster.sh`, **Then** the script provides a clear error message listing supported cluster types.

---

### User Story 2 - Environment-Driven Configuration (Priority: P1)

As a platform operator, I want cluster-specific configuration to be loaded automatically from environment files, so that I can maintain cluster-specific values in one place without modifying scripts.

**Why this priority**: Environment-driven configuration is essential for making the unified bootstrap work - it's how the system knows what values to use for each cluster type.

**Independent Test**: Switching between KIND and Talos clusters and verifying that the correct environment file is loaded automatically and values like `AZURE_CLIENT_ID`, `SERVICE_ACCOUNT_ISSUER`, and `CLUSTER_TYPE` are correct.

**Acceptance Scenarios**:

1. **Given** `.env-files/kind.env` contains KIND-specific configuration, **When** I navigate to the project directory with a KIND cluster context, **Then** direnv automatically loads the KIND configuration and `CLUSTER_TYPE` equals "kind".

2. **Given** `.env-files/talos.env` contains Talos-specific configuration, **When** I navigate to the project directory with a Talos cluster context, **Then** direnv automatically loads the Talos configuration and `CLUSTER_TYPE` equals "talos".

3. **Given** required Azure variables are missing from the environment file, **When** I run the bootstrap, **Then** I receive clear validation errors listing which variables are missing.

---

### User Story 3 - CDK8s Synthesis Across Cluster Types (Priority: P2)

As a platform operator, I want CDK8s synthesis to work for both KIND and Talos clusters with appropriate output, so that I can generate ArgoCD-ready manifests for either cluster type from a single codebase.

**Why this priority**: CDK8s synthesis is the core mechanism for generating Kubernetes manifests, but both clusters can share much of the logic with cluster-specific variations.

**Independent Test**: Running CDK8s synthesis produces correctly configured manifests that work with either KIND (idpBuilder with cnoe:// URLs) or Talos (direct Git repository URLs).

**Acceptance Scenarios**:

1. **Given** `ENVIRONMENT=dev` in `.env-files/kind.env`, **When** I run CDK8s synthesis, **Then** ArgoCD Application sources use `cnoe://` URLs appropriate for idpBuilder local development.

2. **Given** `ENVIRONMENT=dev` in `.env-files/talos.env`, **When** I run CDK8s synthesis for Talos, **Then** ArgoCD Application sources use GitHub repository URLs appropriate for GitOps.

3. **Given** `AZURE_CLIENT_ID` is set in the environment, **When** I run CDK8s synthesis, **Then** the workload identity ServiceAccount annotations include the correct client ID.

---

### User Story 4 - Shared Azure Infrastructure Setup (Priority: P2)

As a platform operator, I want Azure AD app and federated credential setup to work identically for both cluster types, so that I can use the same Azure infrastructure patterns regardless of where my cluster runs.

**Why this priority**: Azure infrastructure (AD apps, federated credentials, Key Vault access) is fundamentally the same regardless of cluster type - this is a clear consolidation opportunity.

**Independent Test**: Running `--setup-azure` flag creates/reuses Azure AD app and federated credentials correctly for both KIND and Talos clusters.

**Acceptance Scenarios**:

1. **Given** no existing Azure AD app exists, **When** I run bootstrap with `--setup-azure` on either cluster type, **Then** an Azure AD app is created with name pattern `gitops-{cluster_type}-{cluster_name}`.

2. **Given** an Azure AD app already exists, **When** I run bootstrap with `--setup-azure` again, **Then** the existing app is reused and no duplicate is created (idempotent operation).

3. **Given** federated credentials are configured in `WORKLOAD_IDENTITY_SERVICE_ACCOUNTS`, **When** I run `--setup-azure`, **Then** credentials are created for each namespace:serviceaccount pair with the correct OIDC issuer URL (including trailing slash).

---

### User Story 5 - Cluster-Specific Deployment Strategies (Priority: P3)

As a platform operator, I want the bootstrap to use the appropriate deployment strategy for each cluster type, so that manifests are applied correctly (idpBuilder for KIND, Helm/kubectl for Talos).

**Why this priority**: This is where architectural differences legitimately require different approaches - forcing consolidation here would add complexity rather than reduce it.

**Independent Test**: After bootstrap completes, ArgoCD is running and configured correctly using the cluster-appropriate deployment method.

**Acceptance Scenarios**:

1. **Given** a KIND cluster, **When** bootstrap completes the ArgoCD deployment phase, **Then** idpBuilder is used to deploy packages from `cdk8s/dist/`.

2. **Given** a Talos cluster, **When** bootstrap completes the ArgoCD deployment phase, **Then** Helm is used to install ArgoCD and kubectl applies the root ArgoCD Application.

3. **Given** either cluster type, **When** bootstrap completes, **Then** ArgoCD is accessible and configured to sync from the Git repository.

---

### Edge Cases

- What happens when cluster type detection fails (no kubectl context, no talosctl config)?
  - Bootstrap should fail with clear instructions on how to configure cluster access.

- What happens when Azure CLI is not authenticated?
  - Bootstrap should detect this early and prompt the user to run `az login`.

- What happens when environment file is missing required variables?
  - Bootstrap should validate required variables before proceeding and list all missing ones.

- What happens when running bootstrap from a git worktree instead of main repo?
  - Bootstrap should work correctly, detecting the repository root from the worktree.

- What happens when CDK8s node_modules are outdated or missing?
  - Bootstrap should detect this and run `npm install` automatically.

## Requirements

### Functional Requirements

- **FR-001**: Bootstrap script MUST detect cluster type (KIND or Talos) automatically based on kubectl context and available tools (talosctl, kind).
- **FR-002**: Bootstrap script MUST load cluster-specific environment from `.env-files/{cluster_type}.env` using direnv or manual sourcing.
- **FR-003**: Bootstrap script MUST validate required Azure variables (AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID, AZURE_CLIENT_ID) before proceeding.
- **FR-004**: Bootstrap script MUST support `--setup-azure` flag for Azure AD app and federated credential setup.
- **FR-005**: Azure AD app creation MUST be idempotent - existing apps are reused, not duplicated.
- **FR-006**: Federated credentials MUST be created with trailing slash on OIDC issuer URL to match Kubernetes OIDC configuration.
- **FR-007**: CDK8s synthesis MUST produce correct ArgoCD Application sources based on environment (`cnoe://` for KIND local dev, GitHub URLs for Talos).
- **FR-008**: Bootstrap MUST use cluster-appropriate deployment strategy (idpBuilder for KIND, Helm for Talos).
- **FR-009**: Shared libraries in `scripts/lib/` MUST be usable by both cluster-specific workflows.
- **FR-010**: Bootstrap MUST provide clear error messages when prerequisites are not met (missing tools, authentication, configuration).

### What Should Be Consolidated

Based on analysis of existing scripts, these areas have high overlap and should be unified:

- **Azure Infrastructure**: `scripts/lib/azure.sh` functions work identically for both clusters
- **Common Utilities**: `scripts/lib/common.sh` logging and helper functions
- **direnv Configuration**: Root `.envrc` with cluster detection and environment loading
- **CDK8s Synthesis Core**: Most chart logic is cluster-agnostic, only ArgoCD source URLs differ
- **Validation Logic**: Checking for required tools, Azure auth, environment variables

### What Should Remain Distinct

Based on architectural differences, these areas should have cluster-specific implementations:

- **Cluster Creation**: KIND uses `kind create cluster`, Talos uses different provisioning
- **ArgoCD Installation**: KIND uses idpBuilder, Talos uses Helm
- **OIDC/JWKS**: KIND may have different OIDC setup than Talos
- **Manifest Application**: KIND uses idpBuilder packages, Talos uses kubectl/Helm
- **Ingress Configuration**: KIND has idpBuilder ingress-nginx, Talos may use different ingress

### Key Entities

- **ClusterType**: Enumeration of supported cluster types (kind, talos) with associated configuration
- **EnvironmentFile**: Cluster-specific configuration containing Azure IDs, OIDC issuer, service accounts
- **AzureAdApp**: Azure AD application for workload identity with associated federated credentials
- **BootstrapPhase**: Named phases of the bootstrap process (validate, azure-setup, synth, deploy, verify)

## Success Criteria

### Measurable Outcomes

- **SC-001**: A single bootstrap command successfully configures both KIND and Talos clusters without requiring cluster-specific script modifications.
- **SC-002**: Operators can switch between KIND and Talos clusters by changing only the environment file, not the scripts or CDK8s code.
- **SC-003**: Code duplication between KIND and Talos scripts is reduced by consolidating shared libraries (target: 50%+ reduction in duplicate lines of code).
- **SC-004**: Bootstrap errors provide actionable messages that help operators resolve issues without consulting documentation (target: 95% of error cases have clear resolution steps).
- **SC-005**: Adding a new cluster type requires only creating a new environment file and implementing cluster-specific deployment hooks, not modifying shared logic.
- **SC-006**: Both cluster types can complete bootstrap in a single run without requiring manual intervention (excluding Azure AD consent if needed).

## Assumptions

- Operators have kubectl configured with appropriate context for their target cluster
- Azure CLI is installed and operators can authenticate with `az login`
- Node.js 18+ is available for CDK8s synthesis
- direnv is installed for automatic environment loading
- Git is available for repository operations
- Both KIND and Talos clusters support the same Kubernetes API version (1.29+)
