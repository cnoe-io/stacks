# Feature Specification: Tailscale Stale Device Cleanup and Services Migration

**Feature Branch**: `103-tailscale-services`
**Created**: 2025-12-06
**Status**: Draft
**Input**: User description: "Clean up stale Tailscale devices and migrate to Tailscale Services for stable hostnames"

## Background

The cluster is currently experiencing Let's Encrypt rate limits (5 certificates per hostname per 7 days) due to hostname suffix drift. When pods restart, Tailscale assigns suffixed hostnames (e.g., `argocd-1`, `gitea-1`) because the original hostname is "claimed" by an offline device. Each new hostname triggers a new certificate request, quickly exhausting rate limits.

**Current State**:
- ArgoCD: Blocked by Let's Encrypt rate limit until ~2025-12-07 00:15 UTC
- Gitea: Working via `gitea-1.tail286401.ts.net` (not original `gitea`)
- kagent: Working via `kagent-1.tail286401.ts.net` (not original `kagent`)
- Multiple stale devices visible in `tailscale status` as "offline"

**Target State**:
- Stale devices removed from Tailscale network
- Services exposed via stable Tailscale Services (`argocd-<cluster>`, `langfuse-<cluster>`, etc.)
- No hostname drift on pod/cluster recreation

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove Stale Devices to Reclaim Hostnames (Priority: P1)

A platform administrator needs to remove stale/offline Tailscale devices that are blocking hostname reuse. After cluster recreation, old devices remain in the Tailscale network as "offline", causing new pods to get suffixed hostnames (`argocd-1` instead of `argocd`).

**Why this priority**: This is a prerequisite for stable hostnames. Without removing stale devices, new deployments continue to get suffixed names, and rate limits persist.

**Independent Test**: Can be fully tested by running `tailscale status` before and after cleanup, verifying offline devices are removed.

**Acceptance Scenarios**:

1. **Given** stale devices exist in the Tailscale network (visible as "offline" in `tailscale status`), **When** the administrator runs the cleanup process, **Then** all offline devices for the cluster services are removed from the network.

2. **Given** stale devices have been removed, **When** a new pod registers with the original hostname (e.g., `argocd`), **Then** it successfully claims that hostname without a suffix.

3. **Given** a device is actively in use (not offline), **When** the cleanup process runs, **Then** active devices are not removed.

---

### User Story 2 - Access ArgoCD via Stable Tailscale Service URL (Priority: P1)

A platform engineer working remotely needs to access ArgoCD at a consistent URL that survives cluster recreations. The URL should not change regardless of pod restarts, cluster deletions, or infrastructure updates.

**Why this priority**: ArgoCD is the primary GitOps control plane. Stable URLs eliminate the need to discover new hostnames after each cluster recreation.

**Independent Test**: Can be fully tested by accessing ArgoCD via `https://argocd-<cluster>.<tailnet>.ts.net` from a Tailscale-connected device.

**Acceptance Scenarios**:

1. **Given** ArgoCD is deployed with Tailscale Services, **When** a user navigates to `https://argocd-<cluster>.<tailnet>.ts.net`, **Then** the ArgoCD login page loads within 10 seconds.

2. **Given** the cluster is deleted and recreated, **When** the user accesses the same ArgoCD URL, **Then** the URL continues to work without modification.

3. **Given** ArgoCD pod restarts, **When** the user accesses the service URL, **Then** access is restored within 60 seconds of pod becoming ready.

---

### User Story 3 - Access All Platform Services via Stable URLs (Priority: P2)

Platform engineers need stable URLs for all exposed services (Gitea, Langfuse, kagent, Kargo, Headlamp, Keycloak) that follow a consistent naming pattern.

**Why this priority**: After ArgoCD, other services benefit from the same stability. A consistent pattern (`<name>-<cluster>`) makes URLs predictable.

**Independent Test**: Can be tested by accessing each service via its stable URL from a Tailscale-connected device.

**Acceptance Scenarios**:

1. **Given** all platform services are configured with Tailscale Services, **When** a user accesses any service via `https://<service>-<cluster>.<tailnet>.ts.net`, **Then** the service responds appropriately.

2. **Given** multiple services are exposed, **When** viewing Tailscale Admin Console Services page, **Then** all services appear as "Active".

---

### User Story 4 - Charts Use Tailscale Serve Helpers (Priority: P2)

Platform developers updating Tailscale serve charts need to use standardized helper functions from the shared library rather than implementing patterns directly.

**Why this priority**: Ensures consistency across all service charts and simplifies future updates. Constitution Principle III (Modular Chart Composition) requires using helper libraries.

**Independent Test**: Can be tested by verifying charts import from `cdk8s/lib/tailscale-serve-helpers.ts` and follow the established pattern.

**Acceptance Scenarios**:

1. **Given** a developer updates a Tailscale serve chart, **When** they implement the service configuration, **Then** they use `TailscaleServeHelpers` from the shared library.

2. **Given** a new service needs Tailscale exposure, **When** a chart is created, **Then** it follows the same pattern as existing charts using the helper functions.

---

### User Story 5 - Auth Keys Managed via External Secrets (Priority: P2)

The tagged auth key required for Tailscale Services must be stored in Azure Key Vault and synced via External Secrets Operator, not hardcoded or committed to Git.

**Why this priority**: Constitution Principle VI (External Secrets Management) requires all sensitive configuration to be managed via ESO with Azure Key Vault. Auth keys are sensitive credentials.

**Independent Test**: Can be tested by verifying the auth key is sourced from an ExternalSecret resource.

**Acceptance Scenarios**:

1. **Given** a Tailscale serve pod needs an auth key, **When** the pod starts, **Then** it retrieves the key from a Kubernetes Secret synced via ESO from Azure Key Vault.

2. **Given** the auth key is rotated in Azure Key Vault, **When** the ESO refresh interval elapses, **Then** pods automatically use the new key without manual intervention.

---

### User Story 6 - Legacy Hostname Mode Removed (Priority: P3)

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

- **FR-001**: System MUST provide a mechanism to identify stale/offline Tailscale devices associated with cluster services.

- **FR-002**: System MUST provide a mechanism to remove stale devices from the Tailscale network via API or CLI.

- **FR-003**: System MUST configure services (ArgoCD, Langfuse, Gitea, kagent, Kargo, Headlamp, Keycloak) to register as Tailscale Services following the `<service>-<cluster>` naming pattern per Constitution Principle V.

- **FR-004**: System MUST use tag-based auth keys with `tag:k8s-services` tag for service registration auto-approval per Constitution Principle V.

- **FR-005**: System MUST update all Tailscale serve charts to use helper functions from `cdk8s/lib/tailscale-serve-helpers.ts` per Constitution Principle III.

- **FR-006**: System MUST configure Tailscale ACL auto-approvers for each service (`svc:argocd`, `svc:langfuse`, etc.) per Constitution Principle V.

- **FR-007**: System MUST use ephemeral auth keys so terminated pods are automatically removed from the network.

- **FR-008**: System MUST store Tailscale auth keys in Azure Key Vault and sync via External Secrets Operator per Constitution Principle VI.

- **FR-009**: System MUST remove all legacy hostname mode code from charts per Constitution Principle IX (Forward-Only Development).

- **FR-010**: System MUST update CLAUDE.md with new service URLs per Constitution Principle X (Documentation as Code).

- **FR-011**: System MUST configure appropriate ArgoCD sync waves for Tailscale serve deployments per Constitution Principle IV.

### Key Entities

- **Stale Device**: A Tailscale device that is offline and associated with a previous deployment (identified by hostname pattern matching cluster services).

- **Tailscale Service**: A stable service endpoint (`<name>-<cluster>`) that decouples service identity from device identity, per Constitution Principle V.

- **Tagged Auth Key**: A reusable, ephemeral auth key with ACL tags enabling automatic service approval, stored in Azure Key Vault.

- **ACL Auto-Approver**: A Tailscale ACL rule that automatically approves service registrations from tagged devices.

- **Tailscale Serve Helper**: A shared library (`cdk8s/lib/tailscale-serve-helpers.ts`) providing standardized chart patterns per Constitution Principle III.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All stale devices (matching cluster service patterns and marked offline) are removed within 5 minutes of running cleanup.

- **SC-002**: ArgoCD is accessible via stable URL (`https://argocd-<cluster>.<tailnet>.ts.net`) within 60 seconds of pod startup.

- **SC-003**: All 7 platform services (ArgoCD, Langfuse, Gitea, kagent, Kargo, Headlamp, Keycloak) are accessible via their stable service URLs.

- **SC-004**: After cluster recreation, service URLs remain unchanged and services become accessible within 3 minutes.

- **SC-005**: Zero manual Tailscale device cleanup required after cluster recreation when using Tailscale Services.

- **SC-006**: Zero hostname suffix drift observed across 3 consecutive cluster recreations.

- **SC-007**: All Tailscale serve charts use `TailscaleServeHelpers` from the shared library (Constitution Principle III compliance).

- **SC-008**: Auth keys are sourced exclusively from Azure Key Vault via ESO (Constitution Principle VI compliance).

- **SC-009**: Zero legacy hostname mode code remains in the codebase (Constitution Principle IX compliance).

- **SC-010**: CLAUDE.md Tailscale Services section is updated with all service URLs (Constitution Principle X compliance).

## Assumptions

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
- High-availability ProxyGroup configuration.
- Creating new helper functions (use existing `tailscale-serve-helpers.ts`).

## Constitution Alignment Summary

This specification aligns with the following Constitution v2.0.0 principles:

| Principle | Alignment |
|-----------|-----------|
| I. CDK8s Typed Composition | Charts use typed imports from `cdk8s/imports/` |
| III. Modular Chart Composition | Use helpers from `cdk8s/lib/tailscale-serve-helpers.ts` |
| IV. ArgoCD Sync Wave Discipline | Configure appropriate sync waves for Tailscale deployments |
| V. Tailscale Services Standards | `<name>-<cluster>` naming, `tag:k8s-services`, ACL auto-approvers for `svc:<name>` |
| VI. External Secrets Management | Auth keys stored in Azure Key Vault, synced via ESO |
| IX. Forward-Only Development | Remove legacy hostname mode, no dual support |
| X. Documentation as Code | Update CLAUDE.md with service URLs |
