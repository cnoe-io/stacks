# Feature Specification: Tailscale Architecture Optimization

**Feature Branch**: `103-tailscale-services`
**Created**: 2025-12-06
**Updated**: 2025-12-09
**Status**: Draft
**Input**: User description: "Review the implementation of Tailscale in our Kind Kubernetes cluster. Research whether our Tailscale architecture is the best option. Want stable kubectl access from M1 Mac (perhaps using OAuth) and stable URLs for individual services accessible from any Tailscale device."

## Background

The cluster has multiple Tailscale integration points that have evolved organically:

1. **Tailscale Operator** - Helm-deployed with API Server Proxy mode enabled
2. **Custom Tailscale Serve Charts** - Manual deployments for each service
3. **K8s API Serve Chart** - Custom kubectl-proxy using Tailscale Services
4. **Tailscale Subnet Router** - For direct pod/service IP access

**Current Issues**:
- **Overlapping API access patterns**: Both Operator API Proxy and custom kubectl-proxy exist
- **Service naming workarounds**: Using suffixed names (`argocd2`, `langfuse2`) due to Let's Encrypt rate limits
- **Token-based auth**: No OAuth identity for kubectl access; uses static tokens
- **Multiple stale devices**: Visible in `tailscale status` as "offline"

**Architecture Analysis** (2025-12-09):

| Pattern | Operator-Native | Tailscale Services (Current) |
|---------|-----------------|------------------------------|
| kubectl OAuth | ✅ Built-in impersonation | ❌ Token-based only |
| Stable URLs | ⚠️ Depends on config | ✅ Yes |
| No custom pods | ✅ Yes | ❌ Requires custom deployments |
| HA support | ✅ ProxyGroup | ⚠️ Single replica |
| RBAC via identity | ✅ Tailnet identity | ❌ ServiceAccount tokens |

**Target State**:
- kubectl access via Operator API Proxy with OAuth identity impersonation
- Services exposed via stable Tailscale Services (`svc-argocd`, `svc-langfuse`, etc.)
- No hostname drift on pod/cluster recreation
- M1 Mac connects using tailnet identity, no token management

## User Scenarios & Testing *(mandatory)*

### User Story 1 - kubectl Access via OAuth Identity (Priority: P0)

A platform engineer needs to run kubectl commands from their M1 Mac against the Kind cluster without managing static tokens. Their Tailscale identity (`vpittamp@github`) should be used for RBAC, eliminating token expiration issues.

**Why this priority**: This is the primary user requirement - stable, secure kubectl access from remote machines using OAuth identity rather than static tokens that can expire or leak.

**Independent Test**: Can be fully tested by running `kubectl get nodes` from an M1 Mac connected to Tailscale, verifying the request is authenticated using the user's tailnet identity.

**Acceptance Scenarios**:

1. **Given** the Tailscale Operator is configured with API Server Proxy in auth mode, **When** a user runs `tailscale configure kubeconfig` on their M1 Mac, **Then** a valid kubeconfig is generated pointing to the cluster.

2. **Given** a kubeconfig is generated via Tailscale, **When** the user runs `kubectl get nodes`, **Then** the command succeeds and the user is impersonated in RBAC as their tailnet identity.

3. **Given** the user is connected to Tailscale, **When** kubectl commands are executed, **Then** no manual token refresh is required.

4. **Given** the cluster is recreated, **When** the user reconnects, **Then** kubectl access works with the same kubeconfig (no regeneration needed).

---

### User Story 2 - Remove Stale Devices to Reclaim Hostnames (Priority: P1)

A platform administrator needs to remove stale/offline Tailscale devices that are blocking hostname reuse. After cluster recreation, old devices remain in the Tailscale network as "offline", causing new pods to get suffixed hostnames (`argocd-1` instead of `argocd`).

**Why this priority**: This is a prerequisite for stable hostnames. Without removing stale devices, new deployments continue to get suffixed names, and rate limits persist.

**Independent Test**: Can be fully tested by running `tailscale status` before and after cleanup, verifying offline devices are removed.

**Acceptance Scenarios**:

1. **Given** stale devices exist in the Tailscale network (visible as "offline" in `tailscale status`), **When** the administrator runs the cleanup process, **Then** all offline devices for the cluster services are removed from the network.

2. **Given** stale devices have been removed, **When** a new pod registers with the original hostname (e.g., `argocd`), **Then** it successfully claims that hostname without a suffix.

3. **Given** a device is actively in use (not offline), **When** the cleanup process runs, **Then** active devices are not removed.

---

### User Story 3 - Access ArgoCD via Stable Tailscale Service URL (Priority: P1)

A platform engineer working remotely needs to access ArgoCD at a consistent URL that survives cluster recreations. The URL should not change regardless of pod restarts, cluster deletions, or infrastructure updates.

**Why this priority**: ArgoCD is the primary GitOps control plane. Stable URLs eliminate the need to discover new hostnames after each cluster recreation.

**Independent Test**: Can be fully tested by accessing ArgoCD via `https://svc-argocd.<tailnet>.ts.net` from a Tailscale-connected device.

**Acceptance Scenarios**:

1. **Given** ArgoCD is deployed with Tailscale Services, **When** a user navigates to `https://svc-argocd.<tailnet>.ts.net`, **Then** the ArgoCD login page loads within 10 seconds.

2. **Given** the cluster is deleted and recreated, **When** the user accesses the same ArgoCD URL, **Then** the URL continues to work without modification.

3. **Given** ArgoCD pod restarts, **When** the user accesses the service URL, **Then** access is restored within 60 seconds of pod becoming ready.

---

### User Story 4 - Access All Platform Services via Stable URLs (Priority: P2)

Platform engineers need stable URLs for all exposed services (Gitea, Langfuse, kagent, Kargo, Headlamp, Keycloak) that follow a consistent naming pattern.

**Why this priority**: After ArgoCD, other services benefit from the same stability. A consistent pattern (`svc-<name>`) makes URLs predictable.

**Independent Test**: Can be tested by accessing each service via its stable URL from a Tailscale-connected device.

**Acceptance Scenarios**:

1. **Given** all platform services are configured with Tailscale Services, **When** a user accesses any service via `https://svc-<service>.<tailnet>.ts.net`, **Then** the service responds appropriately.

2. **Given** multiple services are exposed, **When** viewing Tailscale Admin Console Services page, **Then** all services appear as "Active".

---

### User Story 5 - Charts Use Tailscale Serve Helpers (Priority: P2)

Platform developers updating Tailscale serve charts need to use standardized helper functions from the shared library rather than implementing patterns directly.

**Why this priority**: Ensures consistency across all service charts and simplifies future updates. Constitution Principle III (Modular Chart Composition) requires using helper libraries.

**Independent Test**: Can be tested by verifying charts import from `cdk8s/lib/tailscale-serve-helpers.ts` and follow the established pattern.

**Acceptance Scenarios**:

1. **Given** a developer updates a Tailscale serve chart, **When** they implement the service configuration, **Then** they use `TailscaleServeHelpers` from the shared library.

2. **Given** a new service needs Tailscale exposure, **When** a chart is created, **Then** it follows the same pattern as existing charts using the helper functions.

---

### User Story 6 - Auth Keys Managed via External Secrets (Priority: P2)

The tagged auth key required for Tailscale Services must be stored in Azure Key Vault and synced via External Secrets Operator, not hardcoded or committed to Git.

**Why this priority**: Constitution Principle VI (External Secrets Management) requires all sensitive configuration to be managed via ESO with Azure Key Vault. Auth keys are sensitive credentials.

**Independent Test**: Can be tested by verifying the auth key is sourced from an ExternalSecret resource.

**Acceptance Scenarios**:

1. **Given** a Tailscale serve pod needs an auth key, **When** the pod starts, **Then** it retrieves the key from a Kubernetes Secret synced via ESO from Azure Key Vault.

2. **Given** the auth key is rotated in Azure Key Vault, **When** the ESO refresh interval elapses, **Then** pods automatically use the new key without manual intervention.

---

### User Story 7 - Deprecate Custom kubectl-proxy Chart (Priority: P3)

Once kubectl access via Operator API Proxy (User Story 1) is validated, the custom `k8s-api-tailscale-serve-chart.ts` should be removed to avoid overlapping patterns.

**Why this priority**: Constitution Principle IX (Forward-Only Development) prohibits maintaining backward compatibility with legacy patterns. Once Operator API Proxy is working, the custom chart is redundant.

**Independent Test**: Can be tested by verifying kubectl works via Operator API Proxy, then removing `k8s-api-tailscale-serve` from applications.ts.

**Acceptance Scenarios**:

1. **Given** Operator API Proxy is functioning, **When** reviewing the codebase, **Then** `k8s-api-tailscale-serve-chart.ts` is removed or marked as deprecated.

2. **Given** the migration is complete, **When** users access kubectl, **Then** only the Operator API Proxy is used.

---

### User Story 8 - Remove Legacy Hostname Mode Code (Priority: P3)

Charts must be updated to remove legacy hostname mode support entirely, not maintain dual support for both modes.

**Why this priority**: Constitution Principle IX (Forward-Only Development) prohibits maintaining backward compatibility with legacy patterns. The migration must be complete, not gradual.

**Independent Test**: Can be tested by verifying no charts contain `legacyHostnameMode` flags or hostname-based configurations.

**Acceptance Scenarios**:

1. **Given** charts are migrated to Tailscale Services, **When** reviewing the codebase, **Then** no legacy hostname mode code remains.

2. **Given** the migration is complete, **When** deploying any Tailscale serve chart, **Then** only the `--service` flag pattern is used.

---

### Edge Cases

- What happens if Tailscale Admin Console is unavailable during cleanup? (Cleanup operation should fail gracefully with retry guidance)
- What happens if a device is incorrectly identified as stale? (Only remove devices marked "offline" AND matching cluster service patterns)
- What happens if rate limits are still in effect after cleanup? (Wait for rate limit reset before requesting new certificates)
- What happens if two clusters try to register the same service? (ACL auto-approvers with different tags prevent conflicts)
- What happens if the ESO sync fails for the auth key? (Pod startup fails with clear error; ESO retry logic applies)

## Requirements *(mandatory)*

### Functional Requirements

**kubectl OAuth Access (P0):**

- **FR-001**: System MUST configure Tailscale Operator API Server Proxy in "auth" mode for OAuth identity impersonation.

- **FR-002**: System MUST create Kubernetes RBAC ClusterRoleBinding granting `cluster-admin` to tailnet identity `vpittamp@github`.

- **FR-003**: System MUST enable `tailscale configure kubeconfig` command to generate valid kubeconfig files on remote machines.

- **FR-004**: System MUST ensure kubectl commands from Tailscale-connected devices use the user's tailnet identity for RBAC (no static tokens required).

**Stale Device Cleanup (P1):**

- **FR-005**: System MUST provide a mechanism to identify stale/offline Tailscale devices associated with cluster services.

- **FR-006**: System MUST provide a mechanism to remove stale devices from the Tailscale network via API or CLI.

**Stable Service URLs (P1-P2):**

- **FR-007**: System MUST configure services (ArgoCD, Langfuse, Gitea, kagent, Kargo, Headlamp, Keycloak) to register as Tailscale Services following the `svc-<service-name>` naming pattern per Constitution Principle V.

- **FR-008**: System MUST use tag-based auth keys with `tag:k8s-services` tag for service registration auto-approval per Constitution Principle V.

- **FR-009**: System MUST update all Tailscale serve charts to use helper functions from `cdk8s/lib/tailscale-serve-helpers.ts` per Constitution Principle III.

- **FR-010**: System MUST configure Tailscale ACL auto-approvers for each service (`svc:argocd`, `svc:langfuse`, etc.) per Constitution Principle V.

- **FR-011**: System MUST use ephemeral auth keys so terminated pods are automatically removed from the network.

- **FR-012**: System MUST store Tailscale auth keys in Azure Key Vault and sync via External Secrets Operator per Constitution Principle VI.

**Code Cleanup (P3):**

- **FR-013**: System MUST remove custom `k8s-api-tailscale-serve-chart.ts` after Operator API Proxy is validated per Constitution Principle IX (Forward-Only Development).

- **FR-014**: System MUST remove all legacy hostname mode code from charts per Constitution Principle IX (Forward-Only Development).

- **FR-015**: System MUST update CLAUDE.md with new service URLs per Constitution Principle X (Documentation as Code).

- **FR-016**: System MUST configure appropriate ArgoCD sync waves for Tailscale serve deployments per Constitution Principle IV.

### Key Entities

- **API Server Proxy**: Tailscale Operator feature that exposes Kubernetes API via Tailscale with OAuth identity impersonation. Operates in "auth" mode (user impersonation) or "noauth" mode (proxy-only).

- **Tailnet Identity**: A user's identity in Tailscale (e.g., `vpittamp@github`), used for RBAC impersonation when connecting via API Server Proxy.

- **Stale Device**: A Tailscale device that is offline and associated with a previous deployment (identified by hostname pattern matching cluster services).

- **Tailscale Service**: A stable service endpoint (`svc-<name>`) that decouples service identity from device identity, per Constitution Principle V.

- **Tagged Auth Key**: A reusable, ephemeral auth key with ACL tags enabling automatic service approval, stored in Azure Key Vault.

- **ACL Auto-Approver**: A Tailscale ACL rule that automatically approves service registrations from tagged devices.

- **Tailscale Serve Helper**: A shared library (`cdk8s/lib/tailscale-serve-helpers.ts`) providing standardized chart patterns per Constitution Principle III.

## Success Criteria *(mandatory)*

### Measurable Outcomes

**kubectl OAuth Access (P0):**

- **SC-001**: User can run `tailscale configure kubeconfig` on M1 Mac and get valid kubeconfig within 30 seconds.

- **SC-002**: kubectl commands execute successfully using tailnet identity (no token errors, no expiration).

- **SC-003**: `kubectl auth whoami` shows impersonated identity matching tailnet user (`vpittamp@github`).

- **SC-004**: kubectl access survives cluster recreation without regenerating kubeconfig (only needs cluster to be running).

**Stale Device Cleanup (P1):**

- **SC-005**: All stale devices (matching cluster service patterns and marked offline) are removed within 5 minutes of running cleanup.

- **SC-006**: Zero hostname suffix drift observed across 3 consecutive cluster recreations.

**Stable Service URLs (P1-P2):**

- **SC-007**: ArgoCD is accessible via stable URL (`https://svc-argocd.<tailnet>.ts.net`) within 60 seconds of pod startup.

- **SC-008**: All 7 platform services (ArgoCD, Langfuse, Gitea, kagent, Kargo, Headlamp, Keycloak) are accessible via their stable service URLs.

- **SC-009**: After cluster recreation, service URLs remain unchanged and services become accessible within 3 minutes.

- **SC-010**: Zero manual Tailscale device cleanup required after cluster recreation when using Tailscale Services.

**Code Quality (P3):**

- **SC-011**: All Tailscale serve charts use `TailscaleServeHelpers` from the shared library (Constitution Principle III compliance).

- **SC-012**: Auth keys are sourced exclusively from Azure Key Vault via ESO (Constitution Principle VI compliance).

- **SC-013**: Zero legacy hostname mode code remains in the codebase (Constitution Principle IX compliance).

- **SC-014**: Custom kubectl-proxy chart removed after Operator API Proxy validated (Constitution Principle IX compliance).

- **SC-015**: CLAUDE.md Tailscale Services section is updated with all service URLs (Constitution Principle X compliance).

## Assumptions

- Tailscale Operator v1.82+ supports API Server Proxy in "auth" mode.
- `tailscale configure kubeconfig` command is available on M1 Mac (Tailscale CLI installed).
- Kubernetes RBAC impersonation is supported (standard in K8s 1.23+).
- Tailscale CLI or API access is available for device cleanup operations.
- User has admin access to Tailscale Admin Console for ACL and service configuration.
- The current Let's Encrypt rate limit will reset naturally (no workaround needed for existing limit).
- Tailscale Services feature (v1.86.0+) is production-ready despite beta label.
- Azure Key Vault is available and configured for storing the new tagged auth key.
- Ephemeral auth keys automatically remove devices on disconnect.
- Existing `cdk8s/lib/tailscale-serve-helpers.ts` provides the required helper functions.
- ExternalSecret resources for Tailscale secrets follow existing ESO patterns in the repository.

## Out of Scope

- Automatic provisioning of Tailscale Admin Console configuration (requires manual setup).
- Migration of existing bookmarks/scripts to new URLs (user responsibility).
- Monitoring/alerting for Tailscale service health.
- ProxyClass configuration for Let's Encrypt staging (not needed with Services).
- High-availability ProxyGroup configuration for kubectl access (single operator replica sufficient for dev).
- Creating new helper functions (use existing `tailscale-serve-helpers.ts`).
- Multi-user RBAC configuration (single admin user `vpittamp@github` sufficient for dev).

## Constitution Alignment Summary

This specification aligns with the following Constitution v2.0.0 principles:

| Principle | Alignment |
|-----------|-----------|
| I. CDK8s Typed Composition | Charts use typed imports from `cdk8s/imports/` |
| III. Modular Chart Composition | Use helpers from `cdk8s/lib/tailscale-serve-helpers.ts` |
| IV. ArgoCD Sync Wave Discipline | Configure appropriate sync waves for Tailscale deployments |
| V. Tailscale Services Standards | `svc-<name>` pattern, `tag:k8s-services`, ACL auto-approvers, Operator API Proxy for kubectl |
| VI. External Secrets Management | Auth keys and OAuth credentials stored in Azure Key Vault, synced via ESO |
| IX. Forward-Only Development | Remove legacy hostname mode, remove custom kubectl-proxy after validation |
| X. Documentation as Code | Update CLAUDE.md with service URLs and kubectl access instructions |

## Research Sources

- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator) - Core operator documentation
- [API Server Proxy](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy) - OAuth identity impersonation for kubectl
- [Cluster Ingress](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress) - Service exposure methods
- [Tailscale Services](https://tailscale.com/kb/1552/tailscale-services) - Stable URLs with `--service` flag
- [Multi-Cluster Ingress](https://tailscale.com/kb/1541/kubernetes-operator-multi-cluster-ingress) - HA and regional routing
