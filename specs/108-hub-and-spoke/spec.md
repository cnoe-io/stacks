# Feature Specification: Hub-and-Spoke ArgoCD with Dedicated Talos Hub Cluster

**Feature Branch**: `108-hub-and-spoke`
**Created**: 2025-12-17
**Status**: Draft
**Input**: User description: "Create a hub-and-spoke ArgoCD architecture with a dedicated minimal Talos hub cluster to manage multiple spoke clusters (hetzner, thinkpad, ryzen, talos) from a single ArgoCD instance using GitOps principles and rendered manifests pattern with CDK8s charts."

## Overview

This feature provisions a dedicated minimal Talos Linux cluster on Hetzner Cloud to serve as the ArgoCD hub for managing multiple spoke clusters across different hosts. The hub cluster runs only management workloads (ArgoCD, Kargo, External Secrets Operator) while application workloads run on spoke clusters.

### Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        TAILSCALE MESH NETWORK                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────────┐    ┌───────────────────┐    ┌───────────────────┐
│  TALOS HUB        │    │    THINKPAD       │    │      RYZEN        │
│  (Management)     │    │    (Dev/Test)     │    │    (Dev/Test)     │
│  • ArgoCD         │───▶│    (Spoke)        │    │     (Spoke)       │
│  • Kargo          │    │                   │    │                   │
│  • ESO            │    └───────────────────┘    └───────────────────┘
│  • Tailscale Op   │
└───────────────────┘    ┌───────────────────┐    ┌───────────────────┐
                         │    HETZNER        │    │      TALOS        │
                    ────▶│  (Production)     │    │   (Production)    │
                         │    (Spoke)        │    │     (Spoke)       │
                         └───────────────────┘    └───────────────────┘
```

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Dedicated Hub Cluster Provisioning (Priority: P1)

As a platform operator, I want to provision a dedicated minimal Talos Linux cluster on Hetzner Cloud that serves exclusively as the ArgoCD hub, so that management plane components are isolated from application workloads and can be independently managed.

**Why this priority**: The hub cluster is the foundational infrastructure for the entire multi-cluster architecture. Without it, no spoke clusters can be managed centrally. A dedicated hub ensures management plane stability regardless of spoke cluster activity.

**Independent Test**: Can be validated by running `talosctl health` on the hub cluster showing healthy status, `kubectl get nodes` showing 1 Ready node, and ArgoCD UI accessible via Tailscale.

**Acceptance Scenarios**:

1. **Given** Hetzner Cloud credentials and the talos-cluster repository, **When** the operator runs the hub provisioning workflow, **Then** a single-node Talos cluster is created with private networking and firewall rules within 15 minutes.

2. **Given** the hub cluster is bootstrapped, **When** the operator checks cluster resources, **Then** the node has at least 2 vCPU, 4GB RAM, suitable for running ArgoCD, Kargo, ESO, and Tailscale operator.

3. **Given** the hub cluster is running, **When** the GitOps bootstrap is applied, **Then** ArgoCD, Kargo, External Secrets Operator, and Tailscale operator are deployed and healthy within 10 minutes.

4. **Given** the hub cluster is operational, **When** accessing ArgoCD via Tailscale URL, **Then** the ArgoCD UI loads and shows the hub cluster as healthy with no application workloads.

---

### User Story 2 - Spoke Cluster Registration (Priority: P2)

As a platform operator, I want to register existing clusters (hetzner, thinkpad, ryzen, talos) as spoke clusters in the hub ArgoCD, so that I can deploy and manage applications across all clusters from a single control plane.

**Why this priority**: After the hub is running, registering spokes enables the core value proposition: centralized multi-cluster management. This can be tested independently per spoke.

**Independent Test**: Can be validated by registering one spoke cluster and verifying it appears in ArgoCD cluster list with healthy connection status.

**Acceptance Scenarios**:

1. **Given** the hub cluster is running with ArgoCD, **When** the operator runs the spoke registration for any cluster, **Then** a cluster secret is created in ArgoCD namespace with correct credentials.

2. **Given** a spoke cluster is registered, **When** viewing ArgoCD cluster list, **Then** the spoke cluster shows as connected and healthy.

3. **Given** spoke credentials are stored in Azure Key Vault, **When** External Secrets syncs the credentials, **Then** the ArgoCD cluster secret is automatically created and kept up to date.

4. **Given** Tailscale is operational on both hub and spoke, **When** ArgoCD connects to the spoke, **Then** communication happens securely over Tailscale mesh using the k8s-api service URL.

---

### User Story 3 - Cross-Cluster Application Deployment (Priority: P3)

As a platform operator, I want to deploy applications to specific spoke clusters from the hub ArgoCD, so that I can manage workloads across my entire fleet with GitOps principles.

**Why this priority**: This delivers the primary user value of the hub-and-spoke model. After hub and spokes are connected, operators can deploy applications to any cluster.

**Independent Test**: Can be validated by deploying a simple test application to a specific spoke cluster and verifying it runs on that cluster.

**Acceptance Scenarios**:

1. **Given** a spoke cluster is registered in ArgoCD, **When** an Application targeting that spoke is created, **Then** the application syncs and resources are created on the spoke cluster.

2. **Given** the `targetCluster` field is set in ApplicationConfig, **When** CDK8s synthesizes the application, **Then** the ArgoCD Application destination points to the named spoke cluster.

3. **Given** an ApplicationSet with cluster generator exists, **When** a new spoke cluster is registered, **Then** applications are automatically created for the new cluster based on the generator template.

4. **Given** applications are deployed to multiple spokes, **When** viewing ArgoCD dashboard, **Then** all applications across all clusters are visible with their sync and health status.

---

### User Story 4 - Cross-Cluster Kargo Promotion (Priority: P4)

As a platform operator, I want Kargo pipelines on the hub to promote application versions across spoke clusters, so that I have automated progressive delivery from development to production environments.

**Why this priority**: Extends the hub-and-spoke value with progressive delivery. Requires US1-US3 to be complete.

**Independent Test**: Can be validated by pushing a new image version and observing automatic promotion from dev spoke to staging spoke.

**Acceptance Scenarios**:

1. **Given** Kargo is running on the hub cluster, **When** a new image version is detected by a Warehouse, **Then** a Freight is created and available for promotion.

2. **Given** a Stage targets a spoke cluster via ArgoCD, **When** a Promotion is approved, **Then** Kargo updates the spoke's application via the hub ArgoCD.

3. **Given** the outer loop pipeline has stages for dev, staging, and prod spokes, **When** an image passes all quality gates, **Then** it is promoted sequentially across cluster boundaries.

---

### User Story 5 - Hub Cluster Recovery (Priority: P5)

As a platform operator, I want clear procedures for hub cluster recovery, so that I can restore multi-cluster management capability after a hub failure.

**Why this priority**: Operational resilience is important but secondary to core functionality.

**Independent Test**: Can be validated by simulating hub failure (delete and recreate) and verifying spoke clusters continue running, then restore management.

**Acceptance Scenarios**:

1. **Given** the hub cluster becomes unavailable, **When** checking spoke clusters, **Then** all spoke workloads continue running uninterrupted (they do not depend on hub for runtime).

2. **Given** the hub is down, **When** the operator reprovisions the hub using GitOps, **Then** ArgoCD reconnects to all spokes and resumes management within 30 minutes.

3. **Given** hub state is stored in Git (Applications, Secrets references), **When** a new hub is bootstrapped, **Then** all application definitions and cluster registrations are restored.

---

### Edge Cases

- **Spoke Cluster Unreachable**: If a spoke becomes temporarily unreachable (network issue, maintenance), ArgoCD should report the cluster as unhealthy but not affect other spokes or hub functionality.

- **Hub Cluster Failure**: If the hub fails, spoke clusters continue running existing workloads. No new deployments or updates are possible until hub is restored.

- **Credential Rotation**: When Tailscale auth keys or cluster ServiceAccount tokens expire, External Secrets should automatically rotate them without manual intervention.

- **Network Partition**: If Tailscale mesh is partitioned, ArgoCD marks affected spokes as unknown. Reunion should automatically restore connectivity.

- **Cluster Name Collision**: If two clusters are registered with the same name, the second registration should fail with a clear error message.

## Requirements *(mandatory)*

### Functional Requirements

#### Hub Cluster Infrastructure

- **FR-001**: Hub cluster MUST be a single-node Talos Linux cluster on Hetzner Cloud.
- **FR-002**: Hub cluster MUST have minimum 2 vCPU, 4GB RAM (Hetzner CX22 or larger).
- **FR-003**: Hub cluster MUST run only management workloads: ArgoCD, Kargo, ESO, Tailscale operator.
- **FR-004**: Hub cluster MUST use the same Talos provisioning patterns as existing clusters (talos-cluster repo).
- **FR-005**: Hub cluster MUST be accessible only via Tailscale (no public Kubernetes API exposure after bootstrap).

#### Spoke Cluster Registration

- **FR-006**: System MUST support registering clusters as spokes using ArgoCD cluster secrets.
- **FR-007**: Spoke credentials MUST be stored in Azure Key Vault and synced via External Secrets.
- **FR-008**: Each spoke MUST have a dedicated ServiceAccount with cluster-admin role for ArgoCD management.
- **FR-009**: Spoke clusters MUST be accessible via Tailscale k8s-api service URLs.
- **FR-010**: System MUST support registering at least 4 spoke clusters: hetzner, thinkpad, ryzen, talos.

#### CDK8s Integration

- **FR-011**: ApplicationConfig type MUST support `targetCluster` field for specifying deployment destination.
- **FR-012**: CDK8s MUST generate ArgoCD Applications with correct `destination.name` for spoke targeting.
- **FR-013**: ArgoCD cluster secrets MUST be generated via CDK8s charts with ExternalSecret references.
- **FR-014**: System MUST use rendered manifests pattern (synthesized YAML committed to Git).

#### GitOps Workflow

- **FR-015**: All cluster registrations MUST be declarative and version-controlled in Git.
- **FR-016**: Hub bootstrap MUST follow App-of-Apps pattern for self-managing ArgoCD.
- **FR-017**: Spoke credentials MUST NOT be stored in Git directly (only ExternalSecret references).

### Infrastructure Requirements

- **Hub Cluster Specifications**:
  - Node: 1× CX22 (2 vCPU, 4GB RAM, 40GB SSD) @ ~€4.75/mo
  - Alternative: 1× CX32 (4 vCPU, 8GB RAM, 80GB SSD) @ ~€12/mo (recommended)
  - Location: Hetzner Ashburn (us-east) or Falkenstein (eu-central)
  - Private Network: hub-cluster-net (10.1.0.0/16)
  - Node IP: 10.1.1.1

- **Network Requirements**:
  - Tailscale mesh connectivity between hub and all spokes
  - Hub API accessible at: `https://k8s-api-hub.{tailnet}.ts.net`
  - ArgoCD accessible at: `https://argocd-hub.{tailnet}.ts.net`
  - Pod CIDR: 10.244.0.0/16 (non-overlapping with spokes)
  - Service CIDR: 10.96.0.0/12

- **Spoke Cluster URLs** (via Tailscale):
  - Hetzner: `https://k8s-api-hetzner.{tailnet}.ts.net`
  - Thinkpad: `https://k8s-api-thinkpad.{tailnet}.ts.net`
  - Ryzen: `https://k8s-api-ryzen.{tailnet}.ts.net`
  - Talos: `https://k8s-api-talos.{tailnet}.ts.net`

### Key Entities

- **Hub Cluster**: The dedicated Talos Linux single-node cluster running ArgoCD and Kargo for centralized management.

- **Spoke Cluster**: Any Kubernetes cluster registered in the hub ArgoCD for remote management (hetzner, thinkpad, ryzen, talos).

- **Cluster Secret**: An ArgoCD secret (labeled `argocd.argoproj.io/secret-type: cluster`) containing spoke cluster credentials (server URL, bearer token, CA certificate).

- **ApplicationConfig.targetCluster**: CDK8s configuration field specifying which cluster an application should be deployed to (`hub`, spoke name, or `all`).

- **Rendered Manifests**: Pre-synthesized Kubernetes YAML files committed to Git, consumed by ArgoCD for deployment.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Hub cluster is provisioned and running within 30 minutes from start of provisioning.

- **SC-002**: All 4 spoke clusters can be registered and show healthy status in ArgoCD within 15 minutes of hub being operational.

- **SC-003**: Applications can be deployed to any registered spoke cluster within 2 minutes of ArgoCD Application creation.

- **SC-004**: Hub cluster operational cost is under €15/month (CX32 recommended tier).

- **SC-005**: Spoke cluster failure does not affect hub cluster or other spoke clusters (verified by stopping one spoke and confirming others remain healthy).

- **SC-006**: Hub cluster can be fully reproduced from Git repositories within 45 minutes.

- **SC-007**: ArgoCD dashboard shows all applications across all clusters with accurate sync and health status.

- **SC-008**: Kargo can successfully promote images across spoke cluster boundaries (dev→staging→prod).

- **SC-009**: Platform operator can manage all clusters from a single ArgoCD UI accessed via Tailscale.

## Assumptions

- Tailscale is operational on all clusters with valid OAuth credentials.
- Azure Key Vault is accessible for storing spoke cluster credentials.
- The talos-cluster repository patterns are reusable for hub cluster provisioning.
- Existing spoke clusters (hetzner, thinkpad, ryzen, talos) have Tailscale operator installed with k8s-api service.
- Git repository (GitHub) is accessible for storing rendered manifests.
- Pod and service CIDRs across clusters are non-overlapping or isolated by Tailscale routing.

## Out of Scope

The following items are explicitly out of scope for this feature:

- **Spoke Cluster Provisioning**: Spoke clusters are assumed to already exist. This feature only registers them.
- **High Availability Hub**: Single-node hub is sufficient for this feature. HA hub is a future enhancement.
- **Cross-Cluster Service Mesh**: No service-to-service communication between clusters (only management plane).
- **Cluster Autoscaling**: Hub cluster size is static.
- **Multi-Tenancy**: All applications managed by single ArgoCD instance (no RBAC isolation between teams).
- **Disaster Recovery Automation**: Manual hub recovery is documented; automated failover is future work.

## Dependencies

- **Feature 100 (talos-cluster)**: Talos provisioning patterns and scripts.
- **Feature 102 (bootstrap-talos-argocd)**: ArgoCD bootstrap patterns for Talos.
- **Feature 103 (tailscale-services)**: Tailscale service URL patterns.
- **Feature 105 (kargo-pipelines)**: Kargo pipeline architecture.

## Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Hub single point of failure | High | Medium | Document recovery procedures; spoke workloads unaffected |
| Tailscale connectivity issues | Medium | Low | Multiple NAT traversal paths; DERP relay fallback |
| Credential expiration | Medium | Medium | External Secrets automatic refresh; monitoring alerts |
| Hub resource exhaustion | Medium | Low | Monitor memory/CPU; upgrade to CX32 if needed |
| Git repository unavailability | High | Low | GitHub has 99.9% SLA; local cache in ArgoCD |
