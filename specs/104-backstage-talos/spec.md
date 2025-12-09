# Feature Specification: Backstage CDK8s Chart Migration

**Feature Branch**: `104-backstage-talos`
**Created**: 2025-12-09
**Status**: Draft
**Input**: User description: "review the backstage implementation and dependencies within my kubernetes configuration. currently we use idpbuilder custom package. review https://cnoe.io/docs/idpbuilder/usage#custom-packages to understand how it works with my kind cluster. then, transform the custom package into a cdk8s typescript equivalent chart. the cdk8s chart and the custom package should result in the equivalent output of yaml manifests. test that our cdk8s charts work by confirming that they synthesize to the same yaml manifests"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform Engineer Synthesizes Backstage Manifests (Priority: P1)

A platform engineer wants to generate Backstage Kubernetes manifests using the CDK8s TypeScript chart instead of relying on raw YAML files in the ref-implementation directory. They run `npm run synth` from the cdk8s directory and receive a complete set of manifests in `cdk8s/dist/backstage/manifests/` that can be deployed via idpBuilder or ArgoCD.

**Why this priority**: This is the core feature - without CDK8s synthesis producing valid manifests, nothing else works. The manifests must be equivalent to the existing ref-implementation YAML to ensure zero regression.

**Independent Test**: Can be fully tested by running `npm run synth` and comparing output manifests against `ref-implementation/backstage/manifests/` using `diff` or `kubectl diff`.

**Acceptance Scenarios**:

1. **Given** a clean cdk8s directory with Backstage chart registered, **When** the engineer runs `npm run synth`, **Then** the `dist/backstage/manifests/` directory contains all required Kubernetes resources (Namespace, ServiceAccount, ClusterRoles, Services, Deployment, StatefulSet, ExternalSecrets, Ingress)

2. **Given** synthesized Backstage manifests, **When** compared to `ref-implementation/backstage/manifests/install.yaml`, **Then** the resources are semantically equivalent (same resource types, namespaces, labels, and configurations)

3. **Given** the Backstage chart in `config/applications.ts`, **When** the chart is enabled (uncommented), **Then** idpBuilder can deploy it using `cnoe://backstage/manifests` URL pattern

---

### User Story 2 - Platform Engineer Synthesizes Backstage Templates Manifests (Priority: P2)

A platform engineer wants to manage Backstage templates through CDK8s alongside the main Backstage deployment. The templates application needs a separate ArgoCD Application that points to the templates entities directory.

**Why this priority**: Templates are essential for Backstage self-service functionality but can be deployed after the main Backstage application is working.

**Independent Test**: Can be tested by verifying the ArgoCD Application manifest for backstage-templates is generated correctly and points to the correct source path.

**Acceptance Scenarios**:

1. **Given** Backstage templates chart configuration, **When** synthesized, **Then** an ArgoCD Application manifest is generated that references `cnoe://backstage-templates/entities`

2. **Given** the backstage-templates ArgoCD Application, **When** deployed via idpBuilder, **Then** templates from `ref-implementation/backstage-templates/entities/` are synchronized to the cluster

---

### User Story 3 - Platform Engineer Deploys to Talos Cluster (Priority: P3)

A platform engineer needs to deploy Backstage to a Talos Linux cluster where idpBuilder is not available. The CDK8s chart must support both KIND (with cnoe:// URLs) and Talos (with GitHub repository URLs) deployment targets.

**Why this priority**: Talos support extends the chart's utility but is not required for initial KIND-based validation.

**Independent Test**: Can be tested by running `npm run synth:talos` and verifying the ArgoCD Application source URLs point to GitHub instead of cnoe:// URLs.

**Acceptance Scenarios**:

1. **Given** CLUSTER_TYPE=talos environment, **When** synthesized, **Then** the ArgoCD Application repoURL uses GitHub repository format instead of cnoe://

2. **Given** Talos-specific configuration, **When** deployed, **Then** Backstage uses Tailscale service URLs instead of cnoe.localtest.me ingress

---

### Edge Cases

- What happens when External Secrets dependencies (Keycloak, Gitea, ArgoCD ClusterSecretStores) are not yet deployed?
  - Chart should include appropriate sync-wave annotations to ensure correct deployment ordering

- What happens when the ghcr.io image pull secret is not available?
  - Backstage pods will fail to pull images; chart must ensure external-secrets are deployed first (via sync-wave -10)

- How does the system handle PostgreSQL database initialization timing?
  - PostgreSQL StatefulSet has sync-wave 10, Backstage Deployment has sync-wave 20, ensuring database is ready first

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST generate a BackstageChart TypeScript class in `cdk8s/charts/apps/backstage-chart.ts` that produces Kubernetes manifests equivalent to `ref-implementation/backstage/manifests/install.yaml`

- **FR-002**: System MUST generate a BackstageSecretsChart TypeScript class in `cdk8s/charts/secrets/backstage-secrets-chart.ts` that produces ExternalSecret resources equivalent to those in `ref-implementation/backstage/manifests/install.yaml` and `argocd-secrets.yaml`

- **FR-003**: System MUST register both charts in the IdpBuilderChartFactory (main.ts) with correct type identifiers

- **FR-004**: System MUST include Backstage and backstage-secrets configurations in `cdk8s/config/applications.ts` with appropriate sync-wave ordering:
  - backstage-secrets: sync-wave -10 (ExternalSecrets before deployments)
  - backstage: sync-wave 20 (after secrets and PostgreSQL)

- **FR-005**: BackstageChart MUST create the following Kubernetes resources:
  - Namespace: backstage
  - ServiceAccount: backstage (namespace: backstage)
  - ClusterRole: backstage-argo-workflows (create Argo Workflows)
  - ClusterRole: read-all (get/list/watch all resources)
  - ClusterRoleBinding: backstage-argo-workflows
  - ClusterRoleBinding: backstage-read-all
  - Service: backstage (port 7007)
  - Service: postgresql (port 5432, headless)
  - Deployment: backstage (image: docker.io/vpittamp23/backstage:1.0.4)
  - StatefulSet: postgresql (image: postgres:15.3-alpine3.18)
  - Ingress: backstage (hosts: localhost, cnoe.localtest.me)

- **FR-006**: BackstageSecretsChart MUST create the following resources:
  - Password generator: backstage (36 chars for PostgreSQL)
  - Password generator: backstage-session (64 chars for session secret)
  - ExternalSecret: backstage-oidc (from keycloak ClusterSecretStore)
  - ExternalSecret: gitea-credentials (from gitea ClusterSecretStore)
  - ExternalSecret: ghcr-dockercfg-external (from azure-keyvault-store)
  - ExternalSecret: argocd-credentials (from argocd ClusterSecretStore)
  - ServiceAccount: eso-store (namespace: argocd)
  - Role: eso-store (namespace: argocd)
  - RoleBinding: eso-store (namespace: argocd)
  - ClusterSecretStore: argocd

- **FR-007**: Synthesized manifests MUST include ArgoCD sync-wave annotations matching the original:
  - ghcr-dockercfg-external: sync-wave -10
  - PostgreSQL StatefulSet: sync-wave 10
  - Backstage Deployment: sync-wave 20

- **FR-008**: System MUST support clusterType configuration ('kind' | 'talos' | 'both') to control which cluster types the application is synthesized for

- **FR-009**: Chart MUST use existing helper libraries:
  - `lib/eso-helpers.ts` for ExternalSecret patterns
  - `lib/argocd-sync-builders.ts` for sync-wave annotations
  - `imports/k8s.ts` for Kubernetes resource types
  - `imports/external-secrets.io.ts` for ESO CRDs

- **FR-010**: System MUST generate kustomization.yaml files in each package output directory for idpBuilder compatibility

### Key Entities

- **BackstageChart**: CDK8s Chart class that generates all Backstage Kubernetes workload resources (Namespace, ServiceAccount, RBAC, Deployment, StatefulSet, Services, Ingress)

- **BackstageSecretsChart**: CDK8s Chart class that generates all ExternalSecret and related security resources for Backstage

- **ApplicationConfig**: Configuration entry in `config/applications.ts` that defines chart type, namespace, sync-wave, labels, and sync policy

- **ExternalSecret**: ESO resource that syncs secrets from Keycloak, Gitea, ArgoCD, and Azure Key Vault ClusterSecretStores

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `npm run synth` produces Backstage manifests that can be deployed successfully via `idpbuilder create --package cdk8s/dist/backstage`

- **SC-002**: Synthesized manifests contain 100% of the resources defined in `ref-implementation/backstage/manifests/install.yaml` and `argocd-secrets.yaml`

- **SC-003**: Resource counts match: Backstage chart produces exactly 1 Namespace, 1 ServiceAccount, 2 ClusterRoles, 2 ClusterRoleBindings, 2 Services, 1 Deployment, 1 StatefulSet, 1 Ingress

- **SC-004**: BackstageSecretsChart produces exactly 2 Password generators, 4 ExternalSecrets, 1 ServiceAccount, 1 Role, 1 RoleBinding, 1 ClusterSecretStore

- **SC-005**: Backstage application deploys successfully and becomes Healthy in ArgoCD within 5 minutes of sync

- **SC-006**: All External Secrets reach "SecretSynced" status within 2 minutes of deployment

- **SC-007**: Backstage UI is accessible at https://cnoe.localtest.me:8443/backstage (KIND) or via Tailscale service URL (Talos) after successful deployment

## Assumptions

- Keycloak, Gitea, and ArgoCD ClusterSecretStores are already deployed and functional (these are dependencies managed by other charts)
- Azure Key Vault ClusterSecretStore is configured with GITHUB-PAT secret for ghcr.io image pulls
- The Backstage Docker image `docker.io/vpittamp23/backstage:1.0.4` is publicly accessible
- idpBuilder is installed and configured for KIND cluster deployments
- Existing CDK8s patterns from other charts (HeadlampChart, KagentChart, etc.) can be used as reference implementations
