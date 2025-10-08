# Feature Specification: Tailscale Remote Kubernetes Cluster Access

**Feature Branch**: `001-review-the-tailscale`
**Created**: 2025-10-07
**Status**: Draft
**Input**: User description: "review the tailscale kubernetes functionality by reviewing: https://tailscale.com/kb/1236/kubernetes-operator;  then specify kuberenetes functionality that will allow me to connect to my kuberenetes cluster remotely via the tailscale network that i have setup.  tailscale cli is available so use it as needed to add items/config directly to my tailscale account and to get information that we embed into our cdk8s charts."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remote Cluster Access via Tailscale (Priority: P1)

As a platform administrator, I want to securely access my Kubernetes cluster's API server from any location using my Tailscale network, so that I can manage the cluster remotely without exposing it to the public internet.

**Why this priority**: This is the foundational capability that enables all remote cluster management. Without secure API access, administrators cannot perform any cluster operations remotely.

**Independent Test**: Can be fully tested by connecting to the cluster via `kubectl` from a remote machine on the Tailscale network and successfully executing cluster commands (e.g., `kubectl get nodes`), delivering immediate remote management capability.

**Acceptance Scenarios**:

1. **Given** the Tailscale operator is deployed and configured, **When** an administrator runs `tailscale configure kubeconfig` from a remote machine, **Then** their local kubectl configuration is updated with the Tailscale proxy endpoint
2. **Given** kubectl is configured with the Tailscale endpoint, **When** the administrator runs `kubectl get nodes` from their remote machine, **Then** the cluster responds with the current node list
3. **Given** the administrator is connected via Tailscale, **When** they execute any kubectl command, **Then** the request is authenticated using their Tailscale identity and subject to Kubernetes RBAC policies
4. **Given** the cluster API server is accessible via Tailscale, **When** the administrator disconnects from the Tailscale network, **Then** API access is immediately unavailable

---

### User Story 2 - Identity-Based Access Control (Priority: P2)

As a platform administrator, I want cluster access permissions mapped to Tailscale user groups and identities, so that team members automatically receive appropriate Kubernetes permissions based on their organizational role without manual RBAC configuration.

**Why this priority**: While basic connectivity is critical (P1), identity-based access control is essential for team environments and security compliance. This prevents the need for separate credential management.

**Independent Test**: Can be tested independently by assigning different Tailscale users to specific groups (e.g., `group:admins`, `group:developers`), configuring corresponding Kubernetes role mappings, and verifying each user receives only their designated permissions when connecting via Tailscale.

**Acceptance Scenarios**:

1. **Given** a Tailscale user belongs to `group:admins`, **When** they connect to the cluster via Tailscale, **Then** they are impersonated as a member of Kubernetes `system:masters` group
2. **Given** a Tailscale user belongs to `group:developers`, **When** they attempt to access namespace resources, **Then** their permissions are limited to developer-specific namespaces as defined in Kubernetes RBAC
3. **Given** a user is not a member of any authorized Tailscale group, **When** they attempt to access the cluster, **Then** their requests are denied by Kubernetes RBAC
4. **Given** a user's Tailscale group membership changes, **When** they make subsequent API requests, **Then** their permissions reflect the updated group membership without manual intervention

---

### User Story 3 - High Availability API Proxy (Priority: P3)

As a platform administrator, I want multiple replicas of the Tailscale API proxy running, so that cluster access remains available even if individual proxy instances fail.

**Why this priority**: High availability is important for production resilience but not critical for initial remote access capability. Single-instance proxy is sufficient for development and testing environments.

**Independent Test**: Can be tested by deploying multiple proxy replicas, connecting to the cluster, terminating one proxy instance, and verifying that kubectl commands continue to succeed through remaining replicas.

**Acceptance Scenarios**:

1. **Given** multiple Tailscale proxy replicas are deployed, **When** an administrator connects via Tailscale, **Then** their traffic is load-balanced across available proxy instances
2. **Given** a proxy instance fails, **When** the administrator executes kubectl commands, **Then** requests are automatically routed to healthy proxy instances
3. **Given** all proxy instances are healthy, **When** traffic patterns change, **Then** load is distributed evenly across replicas

---

### Edge Cases

- What happens when the Tailscale network is unavailable but the cluster is reachable via other networks?
- How does the system handle OAuth credential expiration or revocation?
- What occurs when a user's Tailscale device is removed from the tailnet while they have an active kubectl session?
- How are concurrent requests from the same user across multiple devices handled?
- What happens when Kubernetes RBAC policies conflict with Tailscale group mappings?
- How does the proxy behave when the Kubernetes API server is temporarily unavailable?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy the Tailscale Kubernetes operator to the cluster using CDK8s-generated manifests
- **FR-002**: System MUST configure the operator with OAuth client credentials retrieved from Tailscale CLI
- **FR-003**: System MUST create necessary Tailscale tags (`tag:k8s-operator`, `tag:k8s`) in the tailnet policy via Tailscale CLI
- **FR-004**: System MUST enable API server proxy functionality to expose the Kubernetes control plane to the Tailscale network
- **FR-005**: System MUST support authentication mode where user identity from Tailscale is mapped to Kubernetes RBAC permissions
- **FR-006**: System MUST configure impersonation grants that map Tailscale user groups to Kubernetes groups
- **FR-007**: System MUST enable administrators to configure kubeconfig on remote machines using `tailscale configure kubeconfig`
- **FR-008**: System MUST authenticate all API requests using the requester's Tailscale identity
- **FR-009**: System MUST apply Kubernetes RBAC policies to impersonated requests based on Tailscale user groups
- **FR-010**: System MUST support optional ProxyGroup deployment for high-availability API proxy configurations
- **FR-011**: System MUST enable HTTPS for tailnet to secure API server communications
- **FR-012**: System MUST integrate with existing ArgoCD GitOps deployment workflow via synthesized CDK8s manifests
- **FR-013**: System MUST allow configuration of multiple impersonation grants for different user groups and permissions
- **FR-014**: System MUST persist Tailscale operator configuration across cluster restarts and updates

### Key Entities

- **OAuth Client**: Tailscale OAuth credentials with scopes required for Kubernetes operator functionality; includes client ID and client secret
- **Tailscale Tags**: Policy-based tags assigned to operator and proxy resources (`tag:k8s-operator`, `tag:k8s`); controls access and authorization within tailnet
- **Impersonation Grant**: Access control rule mapping Tailscale user groups or device tags to Kubernetes groups; enables identity-based RBAC enforcement
- **API Server Proxy**: Tailscale proxy service that exposes Kubernetes API server to tailnet; can be deployed as single instance or ProxyGroup for HA
- **Kubeconfig Entry**: kubectl configuration pointing to Tailscale proxy endpoint; generated via `tailscale configure kubeconfig` command

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Administrators can successfully connect to the cluster from any remote location with Tailscale access within 30 seconds of running configuration commands
- **SC-002**: All kubectl commands execute successfully via Tailscale proxy with response times comparable to direct cluster access (within 10% latency overhead)
- **SC-003**: 100% of API requests are authenticated using Tailscale identity with no manual credential management required
- **SC-004**: Users receive appropriate Kubernetes permissions based solely on their Tailscale group membership without additional RBAC configuration per user
- **SC-005**: Cluster API server remains accessible via Tailscale with zero public internet exposure
- **SC-006**: High availability configurations maintain cluster access through proxy instance failures with no observable downtime
- **SC-007**: Deployment and configuration process completes successfully on first attempt for administrators familiar with Tailscale CLI and kubectl

## Assumptions

- Tailscale CLI is installed and configured with administrative access to the target tailnet
- The Kubernetes cluster is running a supported version (1.23.0 or later)
- Administrators have the ability to create OAuth clients and modify tailnet policy files
- The cluster has internet connectivity to reach Tailscale coordination servers
- HTTPS is enabled or can be enabled for the tailnet
- Existing CDK8s synthesis and ArgoCD deployment workflows are functional and will incorporate the new Tailscale operator charts
- Administrators using remote access have kubectl installed on their local machines
- The cluster uses a standard CNI configuration compatible with the Tailscale operator
