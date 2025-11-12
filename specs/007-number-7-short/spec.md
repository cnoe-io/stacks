# Feature Specification: Migrate NixOS VM to Wayland/Sway with WayVNC

**Feature Branch**: `007-nixos-wayland-vm`
**Created**: 2025-11-12
**Status**: Draft
**Input**: User description: "review my kubevirt configuration for the local kind kubernetes cluster, using tailscale kubernetes operator, and idpbuilder a binary that helps create/update clusters quickly.  i've changed my nixos vm configuration such that i now use wayland with sway window manager.  determine how we can replace our current image with one that is based on hetzner-sway configuration in my nixos.  create a plan for building the image, deploying it, and access it via wayvnc or similar technology.  don't worry about backwards compatibility.  once we determine we have a working solution, make sure we fully replace our current image/approach"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Build Wayland/Sway NixOS Image (Priority: P1)

Platform operators need to build a NixOS VM disk image based on the hetzner-sway configuration that runs Wayland with Sway window manager in a headless cloud environment. The image must be ready for deployment to KubeVirt on the local Kind cluster.

**Why this priority**: Without a working image, the entire migration cannot proceed. This is the foundational artifact required for all subsequent work.

**Independent Test**: Can be fully tested by building the image from hetzner-sway.nix configuration, verifying the output QCOW2 file exists, and validating the image size is reasonable (under 10GB).

**Acceptance Scenarios**:

1. **Given** the hetzner-sway.nix configuration at /etc/nixos/configurations/hetzner-sway.nix, **When** the build process executes, **Then** a bootable QCOW2 disk image is produced
2. **Given** a completed image build, **When** checking the image contents, **Then** Sway compositor, WayVNC server, and all headless Wayland dependencies are present
3. **Given** the built image, **When** inspecting the configuration, **Then** greetd auto-login is configured to start Sway in headless mode with proper environment variables (WLR_BACKENDS=headless, WLR_RENDERER=pixman)
4. **Given** the image build process, **When** monitoring execution time, **Then** the build completes within a reasonable timeframe (leveraging Nix binary cache if available)

---

### User Story 2 - Deploy Image to KubeVirt (Priority: P2)

Platform operators need to deploy the Wayland/Sway NixOS image to the local Kind cluster using KubeVirt, replacing the existing X11/RustDesk-based VM deployment. The deployment must use the existing idpbuilder workflow and integrate with Tailscale operator for networking.

**Why this priority**: Once the image is built, deploying it validates the image works in the target environment and enables testing of remote access functionality.

**Independent Test**: Can be fully tested by synthesizing CDK8s manifests with the new image configuration, deploying via idpbuilder, and verifying the VirtualMachine resource reaches Running state.

**Acceptance Scenarios**:

1. **Given** the Wayland/Sway QCOW2 image is available via HTTP server or DataVolume, **When** synthesizing CDK8s manifests, **Then** the NixOsVmChart references the new image source
2. **Given** updated CDK8s configuration, **When** running `idpbuilder create --package cdk8s/dist/nixos-dev-vm`, **Then** the VirtualMachine is created successfully
3. **Given** a running VM, **When** checking pod status, **Then** the virt-launcher pod shows Running status
4. **Given** a running VM, **When** checking VirtualMachineInstance status, **Then** the VMI shows Agent Connected and the VM is accessible
5. **Given** deployment via idpbuilder, **When** reviewing ArgoCD applications, **Then** the nixos-dev-vm application shows Synced and Healthy status

---

### User Story 3 - Access VM via WayVNC (Priority: P3)

Platform operators and developers need to access the Wayland/Sway desktop environment remotely using VNC protocol through WayVNC server. Access must work through Tailscale network for secure connectivity.

**Why this priority**: Remote access validation proves the complete solution works end-to-end. This is the ultimate success criteria but depends on P1 and P2 being complete.

**Independent Test**: Can be fully tested by connecting a VNC client to the WayVNC server port (5900) via Tailscale hostname, entering credentials, and verifying the Sway desktop renders correctly.

**Acceptance Scenarios**:

1. **Given** the VM is running with WayVNC service active, **When** connecting VNC client to the Tailscale hostname on port 5900, **Then** the connection establishes successfully
2. **Given** a VNC connection is established, **When** entering authentication credentials, **Then** access is granted and the Sway desktop environment is visible
3. **Given** an active VNC session, **When** interacting with the Sway desktop (keyboard, mouse), **Then** inputs are registered and the desktop responds correctly
4. **Given** multiple headless outputs configured (WLR_HEADLESS_OUTPUTS=3), **When** using Sway workspace shortcuts, **Then** workspaces can be navigated across virtual monitors
5. **Given** an active VNC session, **When** launching applications (terminal, browser), **Then** applications render correctly using software rendering (pixman)

---

### User Story 4 - Replace Existing Configuration (Priority: P4)

Platform operators need to fully replace the existing X11/RustDesk VM configuration with the new Wayland/Sway/WayVNC configuration, removing all deprecated components while maintaining GitOps workflow integrity.

**Why this priority**: This is the final cleanup step that ensures the codebase is maintainable and doesn't carry technical debt from the old approach. Can only be done after validation of P1-P3.

**Independent Test**: Can be fully tested by removing old configuration files, synthesizing manifests, deploying the updated configuration, and verifying no references to RustDesk or X11 components remain.

**Acceptance Scenarios**:

1. **Given** the new Wayland/Sway configuration is validated and working, **When** reviewing cdk8s chart code, **Then** all RustDesk-specific configuration is removed from kubevirt-helpers.ts
2. **Given** updated CDK8s charts, **When** synthesizing manifests, **Then** no Service ports for RustDesk (21116) or RDP (3389) are defined
3. **Given** cloud-init configuration, **When** reviewing buildCloudInitUserData function, **Then** no RustDesk installation or configuration logic remains
4. **Given** updated configuration, **When** deploying to cluster, **Then** only WayVNC port (5900) is exposed via Tailscale LoadBalancer
5. **Given** final deployment, **When** reviewing documentation, **Then** all references to RustDesk remote access are replaced with WayVNC instructions

---

### Edge Cases

- What happens when WayVNC service fails to start in the VM (e.g., Sway not running, permissions issue)?
- How does the system handle network connectivity loss during image download to DataVolume?
- What happens if Tailscale operator fails to provision LoadBalancer for VNC service?
- How does the system behave when connecting multiple concurrent VNC clients to the same VM?
- What happens when the VM is started without proper headless environment variables (WLR_BACKENDS not set)?
- How does cloud-init handle authentication secrets (VNC password) retrieval from Azure Key Vault if the ExternalSecret sync fails?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST build a NixOS disk image from hetzner-sway.nix configuration producing a QCOW2 format output
- **FR-002**: System MUST include Sway compositor configured for headless operation with wlroots headless backend
- **FR-003**: System MUST include WayVNC server package and systemd service configuration for remote desktop access
- **FR-004**: System MUST configure greetd display manager to auto-login and start Sway with headless environment variables
- **FR-005**: System MUST configure headless rendering using pixman software renderer (WLR_RENDERER=pixman)
- **FR-006**: System MUST configure three virtual outputs for multi-monitor workflow (WLR_HEADLESS_OUTPUTS=3)
- **FR-007**: System MUST disable libinput device detection in headless mode (WLR_LIBINPUT_NO_DEVICES=1)
- **FR-008**: System MUST package the built image for distribution via HTTP server or OCI registry
- **FR-009**: System MUST update NixOsVmChart to reference the new Wayland/Sway image source
- **FR-010**: System MUST remove all RustDesk-related configuration from kubevirt-helpers.ts buildCloudInitUserData function
- **FR-011**: System MUST remove RDP port (3389) and RustDesk port (21116) from VM network port definitions
- **FR-012**: System MUST configure Kubernetes Service to expose only WayVNC port (5900) via Tailscale LoadBalancer
- **FR-013**: System MUST configure cloud-init to set WayVNC authentication password from Azure Key Vault via ExternalSecret
- **FR-014**: System MUST configure WayVNC to bind to 0.0.0.0 address to accept connections from outside the VM
- **FR-015**: System MUST validate the VM boots successfully with the new image and reaches Running state
- **FR-016**: System MUST ensure Sway compositor starts automatically on VM boot without requiring user login
- **FR-017**: System MUST provide VNC connection instructions documenting Tailscale hostname, port, and authentication

### Key Entities

- **NixOS Disk Image**: QCOW2 format virtual machine disk image containing NixOS operating system with Wayland/Sway desktop environment, built from hetzner-sway.nix declarative configuration. Attributes: file path, size, format, source configuration.
- **VirtualMachine Resource**: Kubernetes custom resource defining VM lifecycle, resource allocation (CPU, memory), storage volumes, and network configuration for KubeVirt.
- **DataVolume**: KubeVirt/CDI resource responsible for importing the QCOW2 image from HTTP source into persistent volume claim for VM boot disk.
- **Tailscale LoadBalancer Service**: Kubernetes Service resource configured with tailscale.com/expose annotation to provision Tailscale hostname for external VNC access.
- **WayVNC Service**: systemd user service running WayVNC server process, bound to port 5900, configured for authentication via PAM or password file.
- **Cloud-Init Configuration**: YAML configuration injected into VM as NoCloud data source, responsible for initial VM setup including hostname, users, SSH keys, and WayVNC password configuration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: NixOS image build completes in under 25 minutes using Nix binary cache (or under 3 minutes with warm cache)
- **SC-002**: Built QCOW2 image size is under 10GB for efficient storage and transfer
- **SC-003**: VM boots to running state within 90 seconds of VirtualMachine resource creation
- **SC-004**: Sway compositor initializes successfully in headless mode within 30 seconds of VM boot
- **SC-005**: WayVNC service is active and accepting connections within 60 seconds of Sway initialization
- **SC-006**: VNC client can establish connection to VM within 5 seconds of connection attempt via Tailscale hostname
- **SC-007**: VNC session latency is acceptable for interactive use (under 100ms response time for keyboard/mouse input on local network)
- **SC-008**: Sway desktop environment renders correctly in VNC viewer with all three virtual outputs accessible
- **SC-009**: All RustDesk and X11 references are completely removed from codebase with zero deprecated configuration remaining
- **SC-010**: Documentation is updated with WayVNC connection instructions, achieving 100% accuracy for connection steps

## Assumptions *(mandatory)*

- The hetzner-sway.nix configuration at /etc/nixos/configurations/hetzner-sway.nix is complete and tested
- NixOS image build tooling (nixos-generators or similar) is available and functional
- The Kind cluster has sufficient resources (CPU, memory, storage) to run KubeVirt VMs with desktop environments
- Tailscale operator is already deployed and functional in the cluster with valid OAuth credentials
- Azure Key Vault integration via External Secrets Operator is working for secret distribution
- The cluster has internet connectivity for downloading NixOS packages and pushing images to registries
- VNC client software is available on the operator's workstation for testing remote access
- The existing Nix binary cache (Attic + MinIO) is functional for accelerating builds

## Dependencies *(include if feature has external dependencies)*

- **KubeVirt Operator**: Must be deployed and healthy in the cluster for VM orchestration
- **CDI (Containerized Data Importer)**: Required for DataVolume image import functionality
- **Tailscale Operator**: Must be configured with valid OAuth credentials for LoadBalancer provisioning
- **External Secrets Operator**: Required for syncing VNC password from Azure Key Vault
- **Nix Binary Cache (Attic/MinIO)**: Recommended for fast image builds, documented in specs/003-implement-attic-minio
- **Image Server**: HTTP server or OCI registry for hosting the built QCOW2 image (Gitea registry available)
- **idpbuilder**: Local development tool for GitOps deployment workflow

## Out of Scope *(include if boundaries need clarification)*

- Multi-user VNC access (only single-user session required)
- GPU acceleration or hardware rendering (software rendering via pixman is sufficient)
- Audio support in VNC sessions (not required for development VM use case)
- Clipboard synchronization between VNC client and VM (nice-to-have but not required)
- VNC session recording or screen sharing capabilities
- Backwards compatibility with existing RustDesk-based VMs (full replacement strategy)
- Migration tooling for existing VM workloads (fresh deployment expected)
- Support for non-Tailscale network access to VNC port (Tailscale-only is acceptable)
