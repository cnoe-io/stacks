# Feature Specification: Remote Kubernetes Cluster Access via Tailscale

**Feature Branch**: `005-remote-kubernetes-cluster`
**Created**: 2025-10-13
**Status**: Draft
**Input**: User description: "either enhance the spec to allow for the functionality where i can accesss the cluster from another machine (kubectl access), or create another feature to do this.  in addition, review and consider simplifying our tailscale operator setup.  ideally i would like to access from any tailscale connected device and be able to connect to any pod.  consider whether we should use ingress.  review cnoe documentation to determine how ingress/certificates apply to our setup;"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remote kubectl Access from Any Device (Priority: P1)

As a platform engineer working from multiple locations (home, office, mobile), I need to securely access my Kubernetes cluster using kubectl from any device connected to my Tailscale network, so that I can manage cluster resources without requiring VPN configuration or SSH tunneling.

**Why this priority**: This is the foundational capability that enables all remote cluster management workflows. Without reliable kubectl access, platform engineers cannot perform basic operational tasks remotely.

**Independent Test**: Can be fully tested by running `kubectl get nodes` from a Tailscale-connected Mac/laptop that is not the cluster host, and receiving successful output showing cluster nodes. Delivers immediate value for remote cluster management.

**Acceptance Scenarios**:

1. **Given** a platform engineer on a Tailscale-connected Mac with kubectl installed, **When** they configure kubectl to use the Tailscale endpoint and run `kubectl get nodes`, **Then** they receive the list of cluster nodes without TLS errors or connection timeouts
2. **Given** a platform engineer has authenticated to the cluster once, **When** they switch to a different Tailscale-connected device and use the same configuration, **Then** they can access the cluster without re-authentication or additional configuration
3. **Given** a platform engineer is working offline from the Tailscale network, **When** they attempt to run kubectl commands, **Then** they receive clear error messages indicating network unavailability rather than authentication failures
4. **Given** the kubectl connection is established, **When** the platform engineer runs multiple consecutive commands (get, describe, logs), **Then** all commands complete successfully with response times under 2 seconds each

---

### User Story 2 - Direct Pod Access via Port Forwarding (Priority: P2)

As a developer debugging application issues, I need to access individual pod services (databases, APIs, dashboards) running in the cluster from my local machine via kubectl port-forward, so that I can inspect application state and troubleshoot problems without deploying additional infrastructure.

**Why this priority**: After basic kubectl access, port-forwarding is the most common troubleshooting workflow. Developers need this to inspect databases, access internal dashboards, and debug microservices.

**Independent Test**: Can be tested by running `kubectl port-forward -n namespace pod/name 8080:8080` from a remote machine, then accessing `http://localhost:8080` in a browser and seeing the pod's service response. Delivers value for debugging and development workflows.

**Acceptance Scenarios**:

1. **Given** a pod running a web service in the cluster, **When** a developer runs `kubectl port-forward` from their remote machine, **Then** they can access the service at localhost on the forwarded port within 5 seconds
2. **Given** an active port-forward session, **When** the developer makes repeated requests to the forwarded port, **Then** all requests complete successfully with minimal latency (under 500ms added latency beyond direct cluster access)
3. **Given** multiple pods need simultaneous access, **When** the developer opens multiple port-forward sessions to different pods, **Then** all sessions remain stable and responsive
4. **Given** a port-forward session has been running for extended periods (hours), **When** the developer uses the connection, **Then** the session remains active without requiring manual reconnection

---

### User Story 3 - Web UI Access to Cluster Services (Priority: P3)

As a team member needing access to cluster dashboards and UIs (ArgoCD, Gitea, Backstage), I need to access these web interfaces from any browser on my Tailscale network, so that I can manage deployments, review code, and monitor applications without SSH tunneling or complex network configuration.

**Why this priority**: While important for team collaboration, web UI access is less critical than kubectl access since many operations can be performed via command-line. However, it significantly improves user experience for non-terminal workflows.

**Independent Test**: Can be tested by navigating to `https://argocd.cnoe.localtest.me:8443` in a browser from a Tailscale-connected device and seeing the ArgoCD login page load successfully. Delivers value for team members who prefer GUI-based cluster management.

**Acceptance Scenarios**:

1. **Given** a team member on a Tailscale-connected device with a web browser, **When** they navigate to cluster service URLs (ArgoCD, Gitea), **Then** the web interfaces load within 3 seconds with valid TLS certificates
2. **Given** multiple services are exposed via ingress, **When** a user accesses any service URL, **Then** they are routed to the correct service without host header conflicts or routing errors
3. **Given** a service requires authentication, **When** a user logs in successfully, **Then** their session remains active across page refreshes and navigation
4. **Given** DNS resolution is configured for Tailscale, **When** a user types a service hostname in their browser, **Then** the hostname resolves to the correct Tailscale IP automatically

---

### Edge Cases

- **What happens when Tailscale connection drops during an active kubectl command?** The command should fail gracefully with a clear timeout error, and subsequent commands should automatically reconnect when network is restored.
- **How does the system handle certificate expiration for Tailscale TLS endpoints?** Certificates should auto-renew before expiration, and users should receive warnings if renewal fails.
- **What occurs when multiple users access the cluster simultaneously through Tailscale?** Each user's requests are handled independently with their own authentication context; no connection sharing or interference occurs.
- **How are DNS conflicts resolved when multiple clusters use the same ingress domain pattern?** Each cluster's Tailscale hostname is unique (e.g., `cluster1-operator.tail.ts.net`, `cluster2-operator.tail.ts.net`), preventing conflicts.
- **What happens when a user's Tailscale authentication expires?** The user receives authentication errors and must re-authenticate with Tailscale before cluster access resumes.
- **How does the system handle TLS certificate validation for self-signed certificates?** Users can either add cluster CA to their trust store or use `--insecure-skip-tls-verify` flag for testing environments; production should use valid certificates.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST expose Kubernetes API server over Tailscale network with unique, stable hostname
- **FR-002**: System MUST authenticate kubectl requests using Tailscale user identity mapped to Kubernetes RBAC
- **FR-003**: Users MUST be able to run kubectl commands (get, describe, logs, exec, port-forward) from any Tailscale-connected device
- **FR-004**: System MUST provide TLS-encrypted connections between remote clients and cluster API server
- **FR-005**: System MUST support kubectl port-forward command for accessing individual pod services
- **FR-006**: System MUST expose web-based cluster services (ArgoCD, Gitea, Backstage) via ingress accessible from Tailscale network
- **FR-007**: System MUST resolve cluster service hostnames (*.cnoe.localtest.me) correctly both inside and outside the cluster
- **FR-008**: System MUST maintain connection stability for long-running kubectl operations (port-forward, logs -f, exec)
- **FR-009**: System MUST provide clear error messages when Tailscale connectivity is unavailable
- **FR-010**: System MUST persist Tailscale operator configuration declaratively in cdk8s charts for reproducibility
- **FR-011**: System MUST support multiple concurrent users accessing the cluster through Tailscale
- **FR-012**: System MUST map Tailscale user identity to appropriate Kubernetes user groups (e.g., `vpittamp@github` → `cluster-admin`)
- **FR-013**: System MUST avoid ProxyGroup resource when using in-process proxy mode to prevent configuration conflicts
- **FR-014**: System MUST configure CoreDNS to properly resolve cluster service hostnames from within pods
- **FR-015**: System MUST document certificate management strategy for Tailscale TLS endpoints

### Key Entities

- **Tailscale Operator Deployment**: Kubernetes deployment running Tailscale operator with API server proxy enabled, OAuth credentials, unique hostname per cluster
- **Kubernetes API Proxy**: Exposed endpoint (e.g., `kind-operator.tail286401.ts.net:443`) routing kubectl traffic to cluster API server with authentication
- **Ingress Configuration**: Rules mapping service hostnames to backend services, exposed via ingress-nginx on Tailscale network
- **RBAC Mappings**: ClusterRoleBindings associating Tailscale user identities with Kubernetes roles/groups
- **TLS Certificates**: Certificates for Tailscale endpoints, either auto-provisioned via Tailscale HTTPS or cluster CA certificates
- **DNS Configuration**: CoreDNS rewrite rules for in-cluster resolution and Tailscale MagicDNS for external resolution

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Platform engineers can execute kubectl commands from remote devices and receive responses within 2 seconds for simple operations (get, describe)
- **SC-002**: Port-forward sessions remain stable for at least 1 hour of continuous use without disconnection
- **SC-003**: Web UI services (ArgoCD, Gitea) load within 3 seconds when accessed from Tailscale-connected browsers
- **SC-004**: 100% of kubectl command types (get, describe, logs, exec, port-forward, apply) function correctly over Tailscale connection
- **SC-005**: Zero authentication errors occur after initial configuration when user's Tailscale session is valid
- **SC-006**: Cluster remains accessible to multiple concurrent users (at least 5) without performance degradation
- **SC-007**: Configuration changes are captured in version-controlled cdk8s charts and can be redeployed to new clusters within 5 minutes
- **SC-008**: DNS resolution for cluster services succeeds 100% of the time from both inside and outside cluster
- **SC-009**: TLS certificate warnings are eliminated for all Tailscale endpoints when HTTPS is properly enabled
- **SC-010**: Documentation enables new team members to configure remote kubectl access in under 10 minutes

## Assumptions *(optional)*

- Tailscale HTTPS is enabled for the organization's tailnet (required for automatic TLS certificate provisioning)
- Users have valid Tailscale accounts and are authenticated to the organization's tailnet
- Cluster is running kind or another Kubernetes distribution with accessible API server endpoint
- OAuth credentials for Tailscale operator are available in Azure Key Vault and synced via External Secrets Operator
- idpBuilder core packages (ArgoCD, Gitea, ingress-nginx) are already deployed and functional
- Users have kubectl installed on their remote devices
- Cluster CA certificate is available for distribution to users if using self-signed certificates

## Out of Scope *(optional)*

- Multi-cluster kubectl context switching automation (users manually manage kubeconfig contexts)
- Tailscale subnet routing for broader network access beyond Kubernetes API and ingress
- Custom DNS domain configuration (using default `.ts.net` Tailscale domains)
- High-availability configuration for API proxy (single-replica operator deployment acceptable for dev environments)
- Tailscale ACL policy configuration (assumed to be managed separately in Tailscale admin console)
- VPN or SSH-based alternative access methods
- Windows client configuration (documentation focuses on macOS/Linux)

## Dependencies *(optional)*

- Tailscale operator Helm chart or manifest templates
- External Secrets Operator for OAuth credential management
- Azure Key Vault containing `TAILSCALE-OAUTH-CLIENT-ID` and `TAILSCALE-OAUTH-CLIENT-SECRET`
- ingress-nginx controller for web service exposure
- CoreDNS configuration for in-cluster DNS resolution
- kubectl client version compatible with cluster version (v1.27+)
- Tailscale HTTPS feature enabled for organization

## Risks and Considerations *(optional)*

### Security Considerations
- Tailscale user identity mapping to Kubernetes RBAC must be carefully configured to avoid privilege escalation
- OAuth credentials in Azure Key Vault must be protected with appropriate access policies
- TLS certificates must be validated to prevent man-in-the-middle attacks
- Audit logging should track which Tailscale users access cluster resources

### Operational Considerations
- Single-replica operator deployment creates single point of failure (acceptable for dev, should be addressed for production)
- Tailscale connectivity depends on external Tailscale infrastructure availability
- Certificate renewal must be monitored to prevent expiration-related outages
- DNS configuration changes require CoreDNS pod restarts

### Simplification Opportunities
- Current setup mixes in-process proxy (`APISERVER_PROXY=true`) with ProxyGroup resources causing conflicts
- Multiple authentication failure scenarios create confusion (Tailscale auth, Kubernetes RBAC, TLS verification)
- Documentation for certificate management is scattered across troubleshooting guides
- Alternative approaches (tailscale serve, SSH port forwarding) should be documented for comparison

## Related Work *(optional)*

- Feature 003 (Attic/MinIO Nix Cache): Similar pattern of exposing in-cluster services to external clients
- CNOE reference implementation ingress patterns: Domain-based vs path-based routing considerations
- Existing Tailscale operator chart at `cdk8s/charts/infra/tailscale-operator-chart.ts`
- ArgoCD automation scripts with ARGOCD_AUTH_TOKEN pattern (similar authentication model)
