# Feature Specification: Tailscale Services Migration for Kubernetes Remote Access

**Feature Branch**: `101-improve-tailscale`
**Created**: 2025-12-04
**Status**: Draft
**Input**: User description: "Improve Tailscale services to access the Kubernetes cluster remotely using the new Tailscale Services feature for stable service URLs"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Access ArgoCD Dashboard Remotely (Priority: P1)

A platform engineer working from home needs to access the ArgoCD dashboard to monitor and manage GitOps deployments. Currently, when the cluster is recreated, the Tailscale hostname changes (e.g., `argocd-ui-serve-3.tail286401.ts.net`), requiring the user to discover the new URL. With stable Tailscale Services, the user always accesses `svc:argocd` which resolves to a consistent endpoint regardless of cluster recreation.

**Why this priority**: ArgoCD is the primary GitOps control plane used daily for deployment management. Stable URLs reduce friction and eliminate bookmark/script updates after cluster recreation.

**Independent Test**: Can be fully tested by accessing the ArgoCD UI via the stable service URL from a Tailscale-connected device. Delivers immediate value for remote GitOps management.

**Acceptance Scenarios**:

1. **Given** a platform engineer connected to the Tailscale network, **When** they navigate to the ArgoCD service URL (e.g., `https://svc:argocd.ts.net` or registered service name), **Then** they see the ArgoCD dashboard login page within 5 seconds.

2. **Given** the Kubernetes cluster has been recreated with a fresh ArgoCD pod, **When** the user accesses the same ArgoCD service URL as before recreation, **Then** the URL resolves to the new ArgoCD instance without requiring URL changes.

3. **Given** a user accesses ArgoCD via the stable service URL, **When** viewing the browser certificate information, **Then** the certificate is valid and issued for the service endpoint.

---

### User Story 2 - Access Langfuse Dashboard for LLM Observability (Priority: P2)

A data scientist or ML engineer needs to access the Langfuse dashboard to monitor LLM traces and observability data. The stable service URL ensures they can always reach the Langfuse UI without discovering dynamic hostname suffixes.

**Why this priority**: Langfuse is important for LLM observability but used less frequently than ArgoCD. The NextAuth URL configuration in Langfuse makes stable URLs especially valuable for avoiding authentication issues.

**Independent Test**: Can be fully tested by logging into Langfuse via the stable service URL and verifying trace data is accessible.

**Acceptance Scenarios**:

1. **Given** an ML engineer connected to the Tailscale network, **When** they navigate to the Langfuse service URL, **Then** they see the Langfuse login page and can authenticate successfully.

2. **Given** Langfuse is configured with a NextAuth URL, **When** the user authenticates, **Then** authentication succeeds because the NextAuth URL matches the stable service endpoint.

---

### User Story 3 - Remote kubectl Access via Tailscale Services (Priority: P2)

A platform engineer needs to run kubectl commands against the cluster from a remote machine. The stable service URL for the Kubernetes API proxy ensures kubeconfig files don't need updates after cluster recreation.

**Why this priority**: kubectl access is essential for operations but the existing Tailscale operator APISERVER_PROXY already provides this. Services integration provides additional URL stability.

**Independent Test**: Can be fully tested by running `kubectl get nodes` from a remote machine using a kubeconfig pointing to the stable service endpoint.

**Acceptance Scenarios**:

1. **Given** a platform engineer with a kubeconfig using the stable k8s-api service URL, **When** they run `kubectl get nodes`, **Then** the command returns cluster node information within 5 seconds.

2. **Given** the cluster has been recreated, **When** the engineer runs kubectl with the same kubeconfig, **Then** the command succeeds without kubeconfig modifications.

---

### User Story 4 - Consistent Tailscale Hostnames Across Cluster Recreations (Priority: P1)

When the Kind cluster is recreated (during development or updates), Tailscale-exposed services maintain their canonical hostnames without `-1`, `-2`, etc. suffixes. This eliminates the need for manual device cleanup or discovering new URLs.

**Why this priority**: Hostname stability is the core value proposition of Tailscale Services. Without it, users experience friction every cluster recreation.

**Independent Test**: Can be fully tested by recreating the cluster and verifying service hostnames remain unchanged.

**Acceptance Scenarios**:

1. **Given** a cluster with services registered to Tailscale Services, **When** the cluster is deleted and recreated, **Then** the service URLs remain unchanged.

2. **Given** services are using tag-based auth keys, **When** pods are recreated, **Then** they register to the same service name rather than creating new devices.

---

### Edge Cases

- What happens when a service pod crashes and restarts? (Service registration should persist)
- How does the system handle two clusters trying to register the same service name? (ACL auto-approvers should prevent conflicts via tags)
- What happens if the Tailscale admin console is unavailable during pod startup? (Graceful retry with exponential backoff)
- How are authentication failures handled? (Clear error logging, pod restart policy)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST register exposed services (ArgoCD, Langfuse, k8s-api) to stable Tailscale Service names instead of ephemeral device hostnames.

- **FR-002**: System MUST use tag-based auth keys (e.g., `tag:k8s-services`) to enable service auto-approval in Tailscale ACLs.

- **FR-003**: System MUST update the `tailscale serve` command to use the `--service` flag pattern (e.g., `tailscale serve --service=svc:argocd --https=443 127.0.0.1:8443`).

- **FR-004**: System MUST provide documentation for required Tailscale Admin Console configuration including service definitions and ACL auto-approvers.

- **FR-005**: System MUST maintain backward compatibility with existing cluster access methods during migration (both old and new access patterns should work during transition).

- **FR-006**: System MUST update the auth key secret to use a reusable, ephemeral, tagged auth key from Tailscale Admin Console.

- **FR-007**: System MUST update all Tailscale serve charts (ArgoCD, Langfuse) to use the new `--service` flag syntax.

- **FR-008**: System SHOULD provide a migration guide for transitioning from hostname-based to service-based access.

### Key Entities

- **Tailscale Service**: A stable service endpoint in Tailscale that maps to one or more backend pods (e.g., `svc:argocd → tcp:443`). Survives pod/cluster recreation.

- **Tagged Auth Key**: A Tailscale auth key with ACL tags (e.g., `tag:k8s-services`) that enables automatic service registration approval.

- **ACL Auto-Approver**: A Tailscale ACL rule that automatically approves service registrations from devices with specific tags.

- **Service Registration**: The process where a pod registers itself to a named Tailscale Service rather than creating a new device hostname.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can access ArgoCD at a stable URL that remains unchanged across 3 consecutive cluster recreations, verified by accessing the same URL each time.

- **SC-002**: Users can access Langfuse at a stable URL that remains unchanged across cluster recreations, with authentication working on each attempt.

- **SC-003**: Remote kubectl commands complete within 5 seconds using a kubeconfig that requires no modifications after cluster recreation.

- **SC-004**: Zero manual Tailscale device cleanup required after cluster recreation when using Tailscale Services.

- **SC-005**: Service URLs resolve within 30 seconds of pod startup (including first-time certificate provisioning).

- **SC-006**: All existing remote access functionality continues to work during and after migration.

## Assumptions

- Tailscale Services feature is available in the current Tailscale version (v1.90.9 ≥ v1.86.0 requirement confirmed).
- User has administrative access to the Tailscale Admin Console to define services and ACL policies.
- The beta status of Tailscale Services (TCP-only) is acceptable for the exposed services (HTTPS proxied services work via TCP:443).
- Tag-based auth keys can be generated and stored in Azure Key Vault.
- One-time Tailscale Admin Console configuration is acceptable as part of the setup process.

## Out of Scope

- Automatic provisioning of Tailscale Admin Console configuration (services, ACLs) - these require manual setup via the admin console.
- Migration of the Tailscale operator APISERVER_PROXY mode to Services (this continues to work independently).
- High-availability ProxyGroup configuration (existing HA setup continues unchanged).
- Monitoring/alerting for Tailscale service health (can be added in a future feature).
