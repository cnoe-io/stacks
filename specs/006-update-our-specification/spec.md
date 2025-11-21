# Feature Specification: RustDesk Base Image Integration

**Feature Branch**: `006-update-our-specification`
**Created**: 2025-10-14
**Status**: Draft
**Input**: User description: "update our specification to incorporate the following challenges that may neccesitate changes to the spec: @docs/RUSTDESK_DEBUGGING_SUMMARY.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy VM with Working RustDesk Service (Priority: P1)

As a platform operator, I need VMs to boot with RustDesk service already running so that I can immediately access remote desktop without manual intervention or waiting for post-boot configuration.

**Why this priority**: This is the core requirement - VMs must have working RustDesk on first boot. Without this, the entire remote access feature is broken.

**Independent Test**: Can be fully tested by deploying a VM from the base image and verifying RustDesk service is active within 2 minutes of boot completion, delivering immediate remote desktop access capability.

**Acceptance Scenarios**:

1. **Given** a VM is deployed using the RustDesk-enabled base image, **When** the VM completes initial boot, **Then** RustDesk service is running and accessible within 2 minutes
2. **Given** a VM with RustDesk service running, **When** I connect via RustDesk client using the VM's connection details, **Then** I can establish remote desktop session without errors
3. **Given** a VM is recreated from the base image, **When** the VM boots, **Then** RustDesk service starts automatically without requiring cloud-init execution

---

### User Story 2 - Update RustDesk Configuration (Priority: P2)

As a platform operator, I need to update RustDesk configuration in the base image so that configuration changes propagate to all new VMs without requiring manual intervention on each VM.

**Why this priority**: Configuration updates are important but less critical than initial deployment. VMs can continue running with existing configuration while updates are prepared.

**Independent Test**: Can be fully tested by modifying RustDesk configuration in the image build, rebuilding the image, and verifying new VMs use the updated configuration while existing VMs remain unaffected.

**Acceptance Scenarios**:

1. **Given** RustDesk configuration needs to be updated (e.g., new firewall ports, different headless mode settings), **When** I update the base image configuration and rebuild, **Then** newly deployed VMs use the updated configuration
2. **Given** an image rebuild is in progress, **When** the build completes, **Then** the new image is available for deployment within 25 minutes (cold) or 5 minutes (with cache)
3. **Given** existing VMs are running with old configuration, **When** a new image with updated configuration is deployed, **Then** existing VMs continue running unchanged until explicitly recreated

---

### User Story 3 - Troubleshoot RustDesk Issues (Priority: P3)

As a platform operator, I need clear diagnostic information when RustDesk isn't working so that I can quickly identify whether the issue is in the base image configuration, VM deployment, or network connectivity.

**Why this priority**: Troubleshooting is important for operational maintenance but assumes the feature is already working. This is a support/maintenance priority.

**Independent Test**: Can be fully tested by intentionally misconfiguring RustDesk in the base image and verifying that diagnostic logs clearly indicate the configuration error source.

**Acceptance Scenarios**:

1. **Given** RustDesk service fails to start on VM boot, **When** I check VM service logs, **Then** I can determine if the failure is due to base image configuration, missing dependencies, or runtime issues
2. **Given** RustDesk service is running but connections fail, **When** I check network configuration, **Then** I can verify firewall rules and port availability
3. **Given** a VM exhibits RustDesk issues, **When** I check the base image build logs, **Then** I can verify whether RustDesk was correctly included in the image build

---

### Edge Cases

- What happens when the base image build fails due to RustDesk package availability issues?
- How does the system handle VMs deployed from an old image version when a new image with updated RustDesk configuration is available?
- What happens if a VM is deployed without network access during boot (can't reach binary cache)?
- How does the system handle RustDesk configuration conflicts between base image settings and cloud-init userdata?
- What happens when the binary cache is unavailable during image rebuild?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST include RustDesk service configuration in the base image build process so that all VMs inherit the configuration at deployment time
- **FR-002**: System MUST enable RustDesk headless mode by default to avoid graphical library dependencies and errors
- **FR-003**: System MUST configure RustDesk to start automatically on VM boot via system service
- **FR-004**: System MUST pre-install RustDesk package in base image to eliminate runtime package installation delays
- **FR-005**: Base image build MUST validate that RustDesk service is correctly configured before marking the build as successful
- **FR-006**: System MUST expose RustDesk connection details (ID, direct connection port) via standard VM metadata or accessible file location
- **FR-007**: Base image configuration MUST support firewall rule definition for RustDesk ports (default: 21116 for direct connection)
- **FR-008**: System MUST use declarative configuration (NixOS modules) rather than imperative runtime scripts for RustDesk setup
- **FR-009**: System MUST document the trade-off between configuration flexibility (cloud-init) and reliability (base image approach)
- **FR-010**: Base image build process MUST leverage binary cache to reduce rebuild time from 20-25 minutes (cold) to 3-5 minutes (cached)

### Key Entities

- **Base Image**: A pre-configured operating system image containing all necessary software (including RustDesk) for VM deployment. Built using declarative configuration and stored for reuse.
- **VM Instance**: A running virtual machine deployed from a base image. Inherits all configuration from the base image at deployment time.
- **RustDesk Service**: A system-level service running in headless mode that provides remote desktop access. Configured via base image, not runtime cloud-init.
- **Binary Cache**: A repository of pre-built software packages that accelerates base image rebuild by avoiding recompilation of unchanged components.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: VMs boot with RustDesk service running within 2 minutes of deployment (eliminates 5+ minute post-boot configuration delay)
- **SC-002**: RustDesk service start success rate is 99%+ on VM boot (no dependency on cloud-init execution)
- **SC-003**: Base image rebuild completes within 5 minutes when using binary cache (vs. 20-25 minutes cold build)
- **SC-004**: Remote desktop connection can be established within 30 seconds of RustDesk service becoming active
- **SC-005**: Configuration changes to RustDesk propagate to all new VMs after image rebuild without requiring manual intervention
- **SC-006**: Zero post-boot configuration failures related to cloud-init runcmd not executing

## Assumptions *(include if applicable)*

- The NixOS base image build infrastructure is already established and functional
- Binary cache (Attic + MinIO) is available and reachable during image rebuild
- The existing `/etc/nixos/modules/services/rustdesk.nix` module from the host is suitable for inclusion in the base image
- Base image rebuild time is acceptable for the frequency of RustDesk configuration changes (typically infrequent)
- VMs have network access during boot to reach cluster services (Tailscale, internal DNS)
- The declarative approach aligns with NixOS philosophy and is preferred over hybrid cloud-init/nixos-rebuild approaches

## Dependencies *(include if applicable)*

- **NixOS Image Build System**: Base image must be buildable via `nix build .#nixos-kubevirt-image`
- **Binary Cache (Attic + MinIO)**: Required for fast image rebuilds (3-5 min vs. 20-25 min)
- **RustDesk NixOS Module**: `/etc/nixos/modules/services/rustdesk.nix` or equivalent declarative configuration
- **Image Distribution**: Mechanism to push rebuilt images to image server (MinIO or external registry)
- **CDK8s Chart Update**: `cdk8s/charts/infra/nixos-vm-chart.ts` must reference updated base image URL after rebuild

## Out of Scope

- Runtime configuration of RustDesk via cloud-init (this approach has been proven unreliable)
- Hot-swapping RustDesk configuration on running VMs (requires VM recreation to pick up base image changes)
- Automated rollback of base image versions (manual process to revert to previous image URL)
- Support for non-NixOS base images (solution is NixOS-specific)
- Alternative remote desktop solutions (VNC, XRDP) - this spec is RustDesk-focused

## Constraints *(include if applicable)*

- **NixOS Immutability**: Cannot write to `/etc/systemd/system/` at runtime; all configuration must be in base image
- **Cloud-init Limitations**: NixOS cloud-init `runcmd` module is unreliable and cannot be used for RustDesk configuration
- **Image Rebuild Time**: Configuration changes require full base image rebuild (3-5 min with cache, 20-25 min cold)
- **Configuration Propagation**: Changes only apply to newly deployed VMs; existing VMs must be recreated to receive updates
- **Binary Cache Dependency**: Fast rebuilds depend on binary cache availability; cache unavailability increases rebuild time significantly

## Open Questions

None - the debugging summary has identified the root cause and recommended solution. Implementation approach is clear: pre-configure RustDesk in base image using declarative NixOS configuration.
