# Feature Specification: GitOps Bootstrap for Talos Linux Cluster

**Feature Branch**: `102-bootstrap-talos-argocd`
**Created**: 2025-12-06
**Status**: Draft
**Input**: User description: "Setup Talos Linux cluster using declarative GitOps approach with ArgoCD, automated scripting, Azure workload identity for secrets via External Secrets Operator, and Tailscale for secure cluster access via OAuth."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - ArgoCD GitOps Deployment (Priority: P1)

As a cluster operator, I want ArgoCD deployed on my Talos cluster so that I can declaratively manage all cluster applications from Git, enabling reproducible deployments and configuration drift detection.

**Why this priority**: ArgoCD is the foundation for all other GitOps-managed components. Without ArgoCD, no declarative application management is possible. This delivers immediate value by establishing the GitOps control plane.

**Independent Test**: Can be validated by accessing ArgoCD UI, creating an Application resource from Git, and verifying it syncs successfully to the cluster.

**Acceptance Scenarios**:

1. **Given** a running 5-node Talos cluster with Cilium CNI (from feature 100), **When** the operator runs the bootstrap script, **Then** ArgoCD is installed in the `argocd` namespace with all components healthy within 5 minutes.

2. **Given** ArgoCD is installed, **When** the operator accesses the ArgoCD UI, **Then** they can authenticate and view application status.

3. **Given** ArgoCD is running, **When** an Application resource pointing to a Git repository is created, **Then** ArgoCD syncs the manifests to the cluster automatically.

4. **Given** ArgoCD is managing applications, **When** a manifest is changed in Git, **Then** ArgoCD detects the drift and either syncs automatically (if auto-sync enabled) or shows OutOfSync status.

---

### User Story 2 - Tailscale Operator with OAuth Integration (Priority: P2)

As a cluster operator, I want Tailscale Operator installed and configured with OAuth so that I can securely access the Kubernetes API and cluster services from any device on my tailnet without exposing public endpoints.

**Why this priority**: Secure access to the cluster is essential for ongoing operations. Tailscale provides zero-trust networking without requiring public IP exposure or VPN complexity.

**Independent Test**: Can be validated by accessing the Kubernetes API via Tailscale hostname (k8s-api.<tailnet>.ts.net) from a remote machine on the tailnet.

**Acceptance Scenarios**:

1. **Given** ArgoCD is running, **When** the Tailscale Operator Application is synced, **Then** the operator pod is running in the `tailscale` namespace with OAuth authentication configured.

2. **Given** Tailscale Operator is running with OAuth, **When** a `Connector` or `ProxyGroup` resource is created, **Then** it authenticates automatically using the OAuth client credentials.

3. **Given** Tailscale is configured, **When** the operator accesses `k8s-api.<tailnet>.ts.net` from a tailnet-connected device, **Then** kubectl commands succeed without public internet exposure.

4. **Given** Tailscale ingress is configured for ArgoCD, **When** the operator accesses `argocd.<tailnet>.ts.net`, **Then** the ArgoCD UI is accessible securely via Tailscale.

---

### User Story 3 - External Secrets with Azure Workload Identity (Priority: P3)

As a cluster operator, I want External Secrets Operator configured with Azure Workload Identity so that applications can securely access secrets from Azure Key Vault without storing credentials in the cluster.

**Why this priority**: Secure secret management is critical for production workloads. Azure Workload Identity eliminates the need for static credentials while integrating with existing Azure infrastructure.

**Independent Test**: Can be validated by creating a ClusterSecretStore pointing to Azure Key Vault and an ExternalSecret that successfully pulls a secret value.

**Acceptance Scenarios**:

1. **Given** ArgoCD is running, **When** the External Secrets Operator Application is synced, **Then** the operator pod is running with Azure Workload Identity annotations on its ServiceAccount.

2. **Given** ESO is installed with Workload Identity, **When** a ClusterSecretStore referencing Azure Key Vault is created, **Then** the store reports Ready status with successful Azure authentication.

3. **Given** a ClusterSecretStore is Ready, **When** an ExternalSecret referencing a Key Vault secret is created, **Then** a Kubernetes Secret is created with the correct value within 60 seconds.

4. **Given** a secret is updated in Azure Key Vault, **When** the ExternalSecret refresh interval elapses, **Then** the Kubernetes Secret is automatically updated with the new value.

---

### User Story 4 - CDK8s-Based Manifest Generation (Priority: P4)

As a cluster operator, I want to generate Kubernetes manifests using CDK8s with TypeScript so that I can leverage type-safety, IDE support, and programmatic logic for infrastructure-as-code.

**Why this priority**: CDK8s provides a familiar programming model for developers, reduces YAML boilerplate, and enables complex configuration logic. This aligns with the existing stacks/main architecture.

**Independent Test**: Can be validated by running `npm run synth` and verifying that valid YAML manifests are generated in the output directory.

**Acceptance Scenarios**:

1. **Given** a CDK8s project with chart definitions, **When** the operator runs synthesis, **Then** valid Kubernetes YAML manifests are generated for all defined resources.

2. **Given** CDK8s charts for ArgoCD applications, **When** manifests are synthesized, **Then** each application has its manifests in a separate directory with a kustomization.yaml.

3. **Given** environment variables are set, **When** synthesis runs, **Then** the manifests correctly interpolate environment-specific values.

---

### User Story 5 - Automated Bootstrap Scripting (Priority: P5)

As a cluster operator, I want a single bootstrap script that orchestrates the entire cluster configuration so that I can go from bare Talos cluster to fully operational GitOps environment with one command.

**Why this priority**: Automation reduces human error, ensures reproducibility, and documents the setup process. A single entry point simplifies onboarding and disaster recovery.

**Independent Test**: Can be validated by running the bootstrap script against a fresh Talos cluster and verifying all components are deployed and healthy.

**Acceptance Scenarios**:

1. **Given** a running Talos cluster with kubeconfig available, **When** the operator runs the bootstrap script, **Then** ArgoCD, External Secrets, and Tailscale are deployed in correct dependency order.

2. **Given** Azure credentials are configured locally, **When** the bootstrap script runs, **Then** JWKS is synced to Azure Storage for workload identity federation.

3. **Given** all components are deployed, **When** the script completes, **Then** it outputs access URLs and instructions for the operator.

4. **Given** a component fails during bootstrap, **When** the operator re-runs the script, **Then** it is idempotent and recovers gracefully.

---

### Edge Cases

- **JWKS Mismatch After Cluster Rebuild**: If the cluster is rebuilt, the JWKS keys change. The bootstrap script must re-sync JWKS to Azure Storage before ExternalSecrets can authenticate.

- **Tailscale OAuth Token Expiration**: OAuth tokens have limited lifetime. The operator must handle token rotation gracefully without service disruption.

- **ArgoCD Application Out-of-Sync Loop**: If manifests have non-deterministic generation (e.g., timestamps), ArgoCD may show perpetual drift. Manifests must be deterministic.

- **External Secrets Sync Failure**: If Azure Key Vault is unreachable or credentials are invalid, ExternalSecrets should report clear error status. Applications depending on secrets must handle initial unavailability.

- **Cilium CNI Not Ready**: If Cilium is not fully operational, pods cannot schedule. Bootstrap must wait for CNI readiness before deploying applications.

### Observability

- **Monitoring Approach**: Kubernetes-native observability via pod status, events, and logs (kubectl). Full monitoring stack (Prometheus/Grafana) is out of scope for this feature.
- **Health Verification**: Operators verify component health using `kubectl get pods`, `kubectl describe`, and `kubectl logs` commands.
- **ArgoCD Dashboard**: ArgoCD UI provides application sync status and health indicators for managed resources.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy ArgoCD using Helm chart via bootstrap script or ArgoCD ApplicationSet with manual sync policy and auto-prune enabled.
- **FR-002**: System MUST deploy Tailscale Operator with OAuth authentication for automatic device registration.
- **FR-003**: System MUST deploy External Secrets Operator with Azure Workload Identity federation.
- **FR-004**: System MUST create a ClusterSecretStore pointing to Azure Key Vault with workload identity auth.
- **FR-005**: System MUST expose Kubernetes API via Tailscale Services (k8s-api.<tailnet>.ts.net).
- **FR-006**: System MUST expose ArgoCD UI via Tailscale Ingress (argocd.<tailnet>.ts.net).
- **FR-007**: System MUST sync JWKS from cluster to Azure Storage for workload identity federation.
- **FR-008**: Bootstrap script MUST be idempotent - running multiple times produces the same result.
- **FR-009**: System MUST use CDK8s with TypeScript for manifest generation matching stacks/main patterns.
- **FR-010**: System MUST store remote access tokens in Azure Key Vault for persistence across cluster rebuilds.

### Key Entities

- **ArgoCD Application**: A custom resource that points to a Git repository path and namespace, defining what manifests ArgoCD should sync to the cluster.

- **ClusterSecretStore**: An ESO resource that defines how to connect to Azure Key Vault, including tenant ID and managed identity configuration.

- **ExternalSecret**: An ESO resource that references a ClusterSecretStore and Key Vault secret, producing a Kubernetes Secret.

- **Tailscale Connector**: A resource that creates a Tailscale node for exposing Kubernetes services to the tailnet.

- **CDK8s Chart**: A TypeScript class that generates Kubernetes manifests programmatically.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Full bootstrap from bare Talos cluster to operational GitOps environment completes within 15 minutes.

- **SC-002**: ArgoCD can sync 10+ applications from Git without degradation or sync conflicts.

- **SC-003**: External Secrets successfully fetches secrets from Azure Key Vault within 60 seconds of ExternalSecret creation.

- **SC-004**: Tailscale-exposed endpoints (argocd, k8s-api) are accessible from tailnet devices within 5 minutes of deployment.

- **SC-005**: System recovers from single control plane node failure without losing GitOps functionality.

- **SC-006**: Bootstrap script can be re-run after partial failure and complete successfully (idempotency).

- **SC-007**: CDK8s synthesis completes in under 30 seconds for all charts.

## Out of Scope

The following items are explicitly out of scope for this feature:

- **Monitoring Stack**: Prometheus, Grafana, Loki deployment will be a separate feature
- **etcd Backup Configuration**: Backup to Hetzner Object Storage is out of scope
- **Certificate Management**: cert-manager and Let's Encrypt integration is out of scope
- **Additional Workloads**: Application-specific deployments beyond core infrastructure
- **Multi-Cluster Federation**: ArgoCD multi-cluster management is out of scope
- **Ingress Controller**: Gateway API or other ingress beyond Tailscale is out of scope

## Technical Context

### Repository Structure

This feature is implemented in the **stacks repository** (centralized approach):
- All CDK8s charts, manifests, and ArgoCD configurations live in `stacks/main`
- Talos machine-level configs remain in `talos-cluster` repo (node configs, patches, secrets)
- ArgoCD syncs from stacks/main, providing single source of truth for Kubernetes resources
- Bootstrap script in stacks/main orchestrates Talos cluster GitOps setup

### Relationship to Talos Cluster (Feature 100 in talos-cluster repo)

This feature builds directly on `100-setup-talos` (in talos-cluster repo) which provides:
- 5-node Talos cluster (3 CP + 2 workers) on Hetzner Cloud
- Cilium CNI with kube-proxy replacement
- Private networking (10.0.0.0/16)
- KubePrism for local API access (localhost:7445)

### Comparison: IDPBuilder vs Talos Direct Bootstrap

**IDPBuilder** (used in stacks/main for Kind clusters):
- Creates Kind cluster + GitOps stack in one command
- Manages ArgoCD, Gitea, and custom packages
- Designed for local development with Kind
- Cannot be used for Talos (different cluster provisioning)

**Talos Direct Bootstrap** (this feature):
- Talos cluster already exists from feature 100
- Helm/kubectl-based bootstrap for ArgoCD
- Simpler, more direct approach for production clusters
- Can reuse CDK8s patterns from stacks/main for manifest generation

### CDK8s Integration Approach

Leverage patterns from `stacks/main/cdk8s/`:
- Chart structure: `charts/{platform,infra,secrets}/`
- Application configuration: `config/applications.ts`
- Helper libraries: `lib/eso-helpers.ts`, `lib/idpbuilder-chart-factory.ts`
- ArgoCD Application generation: `charts/platform/argo-applications-chart-v2.ts`

Generate manifests locally with CDK8s in stacks/main repository, commit to Git, ArgoCD syncs from stacks/main.

### Azure Workload Identity Flow

1. Cluster generates OIDC JWT tokens signed by cluster CA
2. JWKS (public keys) uploaded to Azure Storage static website
3. Azure AD configured to trust OIDC issuer URL
4. External Secrets ServiceAccount gets workload identity annotation
5. ESO pod presents JWT to Azure, gets Key Vault access token
6. Secrets fetched from Key Vault without static credentials

## Assumptions

- Talos cluster from feature 100 is running and accessible
- Azure subscription has Key Vault with required secrets
- Azure Storage account configured for OIDC issuer hosting
- Tailscale tailnet exists with OAuth client configured
- Operator has local machine with talosctl, kubectl, helm, and az CLI
- Git repository is accessible for ArgoCD to sync from
- Tailnet ACLs allow access to k8s-api and argocd services

## Clarifications

### Session 2025-12-06

- Q: Which Git repository should ArgoCD sync from? → A: stacks/main repository (existing GitOps repo with CDK8s infrastructure)
- Q: What ArgoCD sync policy should be used? → A: Manual sync with auto-prune (operator approves changes, deleted resources cleaned up)
- Q: How should operators monitor bootstrap components? → A: Kubernetes-native only (pod status, events, logs via kubectl)
- Q: Where should speckit implementation live? → A: Centralized in stacks repository (Option A) - CDK8s charts, manifests, bootstrap scripts all in stacks/main; Talos machine configs remain in talos-cluster repo
