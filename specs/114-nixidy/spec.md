# Feature Specification: Nixidy Migration - Complete cdk8s to Nixidy Transition

**Feature Branch**: `114-nixidy`
**Created**: 2025-12-31
**Status**: Draft
**Input**: User description: "completely replace our usage of cdk8s charts to produce manifests with a nixidy approach using https://github.com/arnarg/nixidy. The nixidy based approach should result in the equivalent manifests, and we should test this to know when our work is done. Don't worry about backwards compatibility. Use a full transition to nixidy. Make sure we create a way to inject environment variables into the manifests using nixidy best practices, and replicate the current cdk8s environment variables into our new nixidy configuration."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generate Kubernetes Manifests via Nixidy (Priority: P1)

A platform engineer wants to generate Kubernetes manifests for the cluster using the new nixidy-based configuration instead of cdk8s. They run a Nix build command that produces YAML manifests identical in structure and content to what cdk8s currently generates.

**Why this priority**: This is the core functionality - without manifest generation, nothing else matters. The entire platform depends on manifests being correctly generated for ArgoCD to deploy.

**Independent Test**: Can be fully tested by running `nixidy build .#<environment>` and verifying output YAML files exist in the expected directory structure with valid Kubernetes resource definitions.

**Acceptance Scenarios**:

1. **Given** the nixidy configuration is defined for the `kind` environment, **When** a user runs the nixidy build command, **Then** YAML manifests are generated in the output directory matching the cdk8s `dist/<app>/manifests/` structure.

2. **Given** the nixidy configuration is defined for the `talos` environment, **When** a user runs the nixidy build command, **Then** YAML manifests are generated with Talos-specific settings (TLS, Azure Workload Identity, GitHub source URLs).

3. **Given** a user generates manifests with nixidy, **When** comparing output to existing cdk8s-generated manifests, **Then** the Kubernetes resources (Deployments, Services, ConfigMaps, Secrets, Ingresses, etc.) are functionally equivalent.

---

### User Story 2 - Environment Variable Injection (Priority: P1)

A platform engineer needs to inject environment-specific configuration values (cluster type, Azure credentials, ingress hosts, etc.) into the manifests at build time, following nixidy best practices for variable handling.

**Why this priority**: Environment variables drive critical cluster-specific configuration. The current system uses ~30 environment variables that must be replicated for the migration to be successful.

**Independent Test**: Can be fully tested by setting environment variables (e.g., `CLUSTER_TYPE=talos`, `AZURE_CLIENT_ID=xxx`) and verifying the generated manifests contain the injected values in the correct resource fields.

**Acceptance Scenarios**:

1. **Given** `CLUSTER_TYPE` is set to `kind`, **When** manifests are generated, **Then** KIND-specific configurations are applied (cnoe:// URLs, localtest.me hostnames, no TLS).

2. **Given** `CLUSTER_TYPE` is set to `talos`, **When** manifests are generated, **Then** Talos-specific configurations are applied (GitHub URLs, production domains, TLS with Let's Encrypt, Azure Workload Identity).

3. **Given** Azure environment variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_KEYVAULT_NAME`) are set, **When** manifests are generated for Talos, **Then** the Workload Identity and ClusterSecretStore resources contain these values.

4. **Given** `INGRESS_HOST` is set to a custom domain, **When** manifests are generated, **Then** all ingress resources use the specified host.

---

### User Story 3 - Multi-Environment Configuration (Priority: P2)

A platform engineer wants to build manifests for different environments (kind, talos, hub clusters) using the same nixidy configuration with environment-specific overrides.

**Why this priority**: The current system supports multiple cluster types with different configurations. This capability must be preserved for the migration to be complete.

**Independent Test**: Can be fully tested by building with `nixidy build .#kind` and `nixidy build .#talos` and verifying each produces environment-appropriate manifests.

**Acceptance Scenarios**:

1. **Given** a unified nixidy configuration, **When** building for the `kind` environment, **Then** only applications with `clusterType: kind` or `clusterType: both` are included.

2. **Given** a unified nixidy configuration, **When** building for the `talos` environment, **Then** only applications with `clusterType: talos` or `clusterType: both` are included.

3. **Given** an application has cluster-name filtering (e.g., `clusterNames: ["thinkpad"]`), **When** building for a matching cluster, **Then** the application is included; when building for a non-matching cluster, it is excluded.

---

### User Story 4 - ArgoCD Application Generation (Priority: P2)

A platform engineer expects nixidy to generate ArgoCD Application resources for each application, following the App-of-Apps pattern, so ArgoCD can deploy and manage all applications.

**Why this priority**: ArgoCD Applications are the deployment mechanism. Without proper Application resources, manifests cannot be deployed via GitOps.

**Independent Test**: Can be fully tested by verifying that `apps/` directory contains Application YAML files for each defined application with correct source, destination, and sync policy configurations.

**Acceptance Scenarios**:

1. **Given** applications are defined in nixidy configuration, **When** manifests are generated, **Then** ArgoCD Application resources are created for each application with correct metadata (name, namespace, labels).

2. **Given** an application has sync wave annotations, **When** the ArgoCD Application is generated, **Then** the sync wave is set correctly in the Application metadata.

3. **Given** an application targets a specific cluster (hub, spoke), **When** the ArgoCD Application is generated, **Then** the destination server/name is set correctly.

---

### User Story 5 - Manifest Equivalence Verification (Priority: P3)

A platform engineer wants to verify that nixidy-generated manifests are functionally equivalent to cdk8s-generated manifests to ensure a safe migration.

**Why this priority**: This is critical for validating the migration but can be tested after core functionality works.

**Independent Test**: Can be fully tested by generating manifests with both cdk8s and nixidy, then using diff tools to compare and identify meaningful differences.

**Acceptance Scenarios**:

1. **Given** both cdk8s and nixidy generate manifests for the same application, **When** comparing the outputs, **Then** the Kubernetes resource structure (kinds, names, namespaces) matches.

2. **Given** both systems generate a Deployment resource, **When** comparing the specs, **Then** containers, ports, volumes, and environment variables match.

3. **Given** differences exist between cdk8s and nixidy outputs, **When** reviewing those differences, **Then** they are limited to ordering, formatting, or intentional improvements (not semantic changes).

---

### Edge Cases

- What happens when required environment variables are missing (e.g., `AZURE_CLIENT_ID` for Talos)?
  - Build should fail with a clear error message listing missing variables
- How does the system handle invalid or malformed environment variable values?
  - Build should validate inputs and fail with descriptive errors
- What happens when building for an unknown cluster type?
  - Build should fail with an error listing valid cluster types
- How are secrets handled in the nixidy configuration?
  - Secrets should reference External Secrets or Kubernetes Secrets, never contain actual secret values

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST generate Kubernetes YAML manifests from nixidy configuration that are deployable by ArgoCD
- **FR-002**: System MUST support environment variable injection at build time for cluster-specific configuration
- **FR-003**: System MUST replicate all current cdk8s environment variable usage, including:
  - `CLUSTER_TYPE` (kind/talos)
  - `CLUSTER_NAME` / `CLUSTER_HOST`
  - `INGRESS_HOST`
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_KEYVAULT_NAME`
  - `GIT_REPO_URL`, `GIT_BRANCH`
  - All other environment variables currently read in cdk8s charts
- **FR-004**: System MUST filter applications by cluster type (kind, talos, both) during manifest generation
- **FR-005**: System MUST generate ArgoCD Application resources following the App-of-Apps pattern
- **FR-006**: System MUST generate kustomization.yaml files for each application's manifest directory
- **FR-007**: System MUST support the current application configuration structure (name, namespace, chart type, ArgoCD config, dependencies)
- **FR-008**: System MUST output manifests in the structure expected by idpBuilder and ArgoCD: `dist/<app>/manifests/` with `<app>.yaml` Application at package root
- **FR-009**: System MUST support sync wave annotations for deployment ordering
- **FR-010**: System MUST support ArgoCD sync policies (automated prune, self-heal, retry, ignoreDifferences)
- **FR-011**: System MUST support multi-source ArgoCD Applications for Talos clusters (GitHub repository sources)
- **FR-012**: System MUST provide a mechanism to validate manifest equivalence between cdk8s and nixidy outputs

### Key Entities

- **Application**: A deployable unit with name, namespace, Kubernetes resources, and ArgoCD configuration
- **Environment**: A target cluster configuration (kind for local development, talos for production)
- **Manifest**: Generated YAML files containing Kubernetes resource definitions
- **Configuration**: Nix modules defining applications, resources, and environment-specific overrides

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 80+ applications currently defined in `cdk8s/config/applications.ts` can be represented in nixidy configuration
- **SC-002**: Generated manifests for both kind and talos environments deploy successfully to their respective clusters without modification
- **SC-003**: Environment variable injection works for all 30+ currently-used environment variables
- **SC-004**: Manifest generation completes in under 60 seconds for all applications (comparable to current cdk8s synthesis time)
- **SC-005**: Generated ArgoCD Applications successfully sync and reach Healthy status for all applications
- **SC-006**: Platform engineers can understand and modify the nixidy configuration without specialized Nix expertise (using provided documentation and examples)
- **SC-007**: Zero regression in deployed application functionality when switching from cdk8s to nixidy-generated manifests

## Assumptions

1. The nixidy framework (https://github.com/arnarg/nixidy) is stable and suitable for production use
2. Nix is already available in the development environment (NixOS-based system as indicated by repository structure)
3. The existing ArgoCD and idpBuilder deployment mechanisms remain unchanged
4. Complete replacement of cdk8s is acceptable (no hybrid approach needed)
5. Existing TypeScript chart logic can be faithfully translated to Nix module definitions
6. The nixidy module system supports all required Kubernetes resource types (Deployments, Services, Ingresses, StatefulSets, CRDs, etc.)
