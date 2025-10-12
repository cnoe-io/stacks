# Feature Specification: Deploy NixOS VMs using KubeVirt

**Feature Branch**: `004-deploy-nixos-vms`
**Created**: 2025-10-11
**Status**: Draft
**Input**: User description: "Deploy NixOS VMs using KubeVirt with bootable images and cloud-init configuration"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generate Bootable NixOS qcow2 Image (Priority: P1)

As a platform engineer, I want to generate a minimal bootable NixOS qcow2 image using nixos-generators with the `kubevirt` format so that I have a working base image that boots correctly in KubeVirt with proper networking, serial console, and cloud-init support.

**Why this priority**: Without a bootable image, no VMs can be deployed. The kubevirt format includes KubeVirt-specific configuration (GRUB bootloader, serial console, filesystem auto-resize, cloud-init) that custom formats lack.

**Independent Test**: Can be fully tested by building the image with `nixos-generate --format kubevirt`, importing it into a Kind cluster via DataVolume, deploying a VirtualMachine resource, and verifying the VM boots with network connectivity and SSH access.

**Acceptance Scenarios**:

1. **Given** I have a minimal NixOS configuration file, **When** I run `nixos-generate --format kubevirt --configuration kubevirt-base.nix`, **Then** a bootable qcow2 image is generated at the output path
2. **Given** the qcow2 image is generated, **When** I inspect its properties, **Then** it contains GRUB bootloader on /dev/vda, serial console support (ttyS0), and cloud-init packages
3. **Given** the image is packaged into a Docker container with nginx, **When** I push it to docker.io/vpittamp23/nixos-kubevirt-minimal, **Then** the image is publicly accessible for DataVolume import
4. **Given** the Docker image is available, **When** I create a DataVolume pointing to the image HTTP endpoint, **Then** CDI imports the qcow2 into a PVC within 1 minute

---

### User Story 2 - Deploy Minimal NixOS VM with SSH Access (Priority: P2)

As a platform engineer, I want to deploy a minimal NixOS VM using the kubevirt image with cloud-init configuration so that I can SSH into the VM and verify it has working network connectivity and basic tooling.

**Why this priority**: SSH access is the gateway to VM customization. Without it, we cannot proceed to Phase 2 (applying full desktop configuration). This validates the image boots correctly and network configuration works.

**Independent Test**: Can be fully tested by deploying a VirtualMachine with cloud-init user data (SSH keys, user account), waiting for the VM to reach Running status, and SSH-ing into the VM to execute basic commands.

**Acceptance Scenarios**:

1. **Given** a DataVolume with the NixOS image exists, **When** I deploy a VirtualMachine resource referencing that DataVolume with cloud-init configuration, **Then** the VM pod starts and KubeVirt reports status "Running"
2. **Given** the VM is running, **When** cloud-init completes execution, **Then** the configured user (vpittamp) exists with sudo privileges and authorized SSH keys
3. **Given** cloud-init has configured the user, **When** I SSH to the VM IP using the private key, **Then** I successfully authenticate and receive a shell prompt
4. **Given** I have SSH access, **When** I run network commands (ping, curl), **Then** the VM has working DNS resolution and internet connectivity via KubeVirt masquerade networking
5. **Given** I have SSH access, **When** I check installed packages, **Then** essential tools (vim, git, wget, curl) are available

---

### User Story 3 - Apply Full Desktop Configuration via nixos-rebuild (Priority: P3)

As a platform engineer, I want to apply my full NixOS configuration (vm-hetzner.nix with KDE Plasma desktop, RDP, VNC) to the running minimal VM so that I transform it into a fully-featured development workstation without rebuilding the entire image.

**Why this priority**: This is the two-phase deployment strategy - start with a fast minimal base, then customize on-demand. This approach reduces deployment time from 20+ minutes to under 5 minutes for the initial boot.

**Independent Test**: Can be fully tested by SSH-ing into a minimal VM, cloning the nixos-config repository, running `sudo nixos-rebuild switch --flake .#vm-hetzner`, and verifying KDE Plasma desktop is installed and accessible via RDP.

**Acceptance Scenarios**:

1. **Given** I have SSH access to a minimal NixOS VM, **When** I clone the nixos-config repository to ~/nixos-config, **Then** the repository is available with all configuration modules
2. **Given** the nixos-config repository is cloned, **When** I run `sudo nixos-rebuild switch --flake .#vm-hetzner`, **Then** NixOS rebuilds the system with the full configuration (KDE Plasma, xrdp, development tools)
3. **Given** the rebuild completes, **When** I check running services, **Then** xrdp, VNC server, and KDE session manager are active
4. **Given** xrdp is running, **When** I connect via RDP client to the VM IP:3389, **Then** I see the KDE Plasma login screen and can authenticate
5. **Given** the desktop is accessible, **When** I log in and launch applications, **Then** Firefox, terminal, and development tools work correctly
6. **Given** Attic binary cache is configured, **When** nixos-rebuild downloads packages, **Then** packages are retrieved from the in-cluster Attic cache at 100-500 MB/s (8x faster than internet)

---

### User Story 4 - Automate VM Deployment via CDK8s Charts (Priority: P4)

As a platform engineer, I want to define VirtualMachine, DataVolume, and Service resources using CDK8s TypeScript charts so that VM deployments are version-controlled, repeatable, and integrate with the GitOps workflow via ArgoCD.

**Why this priority**: Automation enables scaling and consistency. Once manual deployment works, codifying it as CDK8s charts allows deploying multiple VMs with different configurations without manual kubectl commands.

**Independent Test**: Can be fully tested by synthesizing CDK8s charts to YAML manifests, deploying them via ArgoCD, and verifying VMs are created automatically with the correct configuration and sync status.

**Acceptance Scenarios**:

1. **Given** I have NixOsVmChart, NixOsDataVolumeChart, and NixOsImageServerChart TypeScript classes, **When** I run `npx ts-node main-v2.ts`, **Then** YAML manifests are generated in dist/ directory
2. **Given** manifests are generated, **When** I deploy via `idpbuilder create --package dist/nixos-dev-vm`, **Then** ArgoCD Application is created and syncs the VM resources
3. **Given** ArgoCD is syncing, **When** I check ArgoCD UI, **Then** nixos-image-server, nixos-dev-datavolume, and nixos-dev-vm applications show Synced/Healthy status
4. **Given** VM is deployed via ArgoCD, **When** I modify the CDK8s chart (e.g., change VM memory), **Then** re-synthesizing and syncing applies the changes automatically
5. **Given** multiple VMs are defined in applications.ts config, **When** I synthesize and deploy, **Then** each VM gets its own ArgoCD Application and deploys independently

---

### Edge Cases

- What happens when the DataVolume import fails due to unreachable image server?
- How does the system handle VMs that fail to boot (stuck in "Scheduling" or "ContainerCreating" status)?
- What occurs when cloud-init execution fails (e.g., invalid userdata format)?
- How does the VM behave when the root filesystem is full after nixos-rebuild?
- What happens to running VMs when the underlying PVC is accidentally deleted?
- How does KubeVirt handle VM pod crashes or node failures?
- What occurs when SSH keys in cloud-init are malformed or missing?
- How does the system handle network connectivity issues during nixos-rebuild (Attic cache unavailable)?
- What happens when multiple VMs try to use the same DataVolume simultaneously (not supported)?
- How does the system handle VM resource limits (CPU, memory) being exceeded during desktop usage?

## Requirements *(mandatory)*

### Functional Requirements

#### Image Generation

- **FR-001**: System MUST use nixos-generators with `--format kubevirt` to build NixOS qcow2 images
- **FR-002**: Base image configuration MUST include GRUB bootloader on /dev/vda with timeout=0
- **FR-003**: Base image configuration MUST enable serial console on ttyS0 with kernel parameter console=ttyS0
- **FR-004**: Base image configuration MUST enable cloud-init service with network support
- **FR-005**: Base image configuration MUST enable OpenSSH server with password and key-based authentication
- **FR-006**: Base image configuration MUST enable QEMU guest agent for KubeVirt integration
- **FR-007**: Base image configuration MUST configure filesystem auto-resize for root partition
- **FR-008**: Base image configuration MUST use ext4 filesystem on /dev/disk/by-label/nixos
- **FR-009**: Base image MUST include essential packages (vim, git, wget, curl) for basic operations
- **FR-010**: Base image MUST configure DHCP networking via networking.useDHCP=true

#### Image Distribution

- **FR-011**: System MUST package qcow2 image into Docker container with nginx serving the file
- **FR-012**: System MUST push Docker image to docker.io/vpittamp23/nixos-kubevirt-minimal registry
- **FR-013**: System MUST deploy nginx image server in Kubernetes cluster (nix-image-server) exposing HTTP on port 80
- **FR-014**: Image server MUST be accessible via cluster-internal DNS (nixos-image-server.default.svc.cluster.local)
- **FR-015**: Image server Deployment MUST have resource limits (512Mi-2Gi memory, 100m-200m CPU)

#### DataVolume Import

- **FR-016**: System MUST create DataVolume resources pointing to image server HTTP URL
- **FR-017**: DataVolumes MUST use "http" source type with URL http://nixos-image-server.default.svc.cluster.local/nixos-kubevirt-minimal.qcow2
- **FR-018**: DataVolumes MUST specify storage size of 50Gi for root disk (sufficient for KDE Plasma + development tools)
- **FR-019**: DataVolumes MUST use accessMode ReadWriteOnce (single VM per disk)
- **FR-020**: System MUST wait for DataVolume phase "Succeeded" before starting VM

#### VirtualMachine Configuration

- **FR-021**: System MUST create VirtualMachine resources with runStrategy "Always" (auto-start, auto-restart)
- **FR-022**: VirtualMachines MUST allocate 2 CPU cores (cpuCores=2) and 4Gi memory by default
- **FR-023**: VirtualMachines MUST use virtio bus for disk devices (optimal KubeVirt performance)
- **FR-024**: VirtualMachines MUST attach root disk from DataVolume PVC
- **FR-025**: VirtualMachines MUST attach cloud-init disk with user data from Kubernetes Secret
- **FR-026**: VirtualMachines MUST configure networking with pod network using masquerade interface type
- **FR-027**: VirtualMachines MUST expose SSH port 22 and RDP port 3389 in network ports list
- **FR-028**: VirtualMachines MUST enable graphics device for VNC access (enableGraphics=true)
- **FR-029**: VirtualMachines MUST have labels for app.kubernetes.io/name and kubevirt.io/vm

#### Cloud-Init Configuration

- **FR-030**: Cloud-init userdata MUST be stored in Kubernetes Secret (required when >2048 bytes)
- **FR-031**: Cloud-init MUST configure hostname matching VM name
- **FR-032**: Cloud-init MUST create vpittamp user with sudo privileges (NOPASSWD:ALL)
- **FR-033**: Cloud-init MUST inject SSH public key (k8s_ed_test) into vpittamp user authorized_keys
- **FR-034**: Cloud-init MUST set password "nixos123" for vpittamp and root users for emergency console access
- **FR-035**: Cloud-init MUST NOT install desktop environment or additional packages (minimal phase)
- **FR-036**: Cloud-init MUST enable SSH service and configure firewall to allow port 22

#### Service Exposure

- **FR-037**: System MUST create Kubernetes Service exposing VM SSH and RDP ports
- **FR-038**: Service MUST use selector kubevirt.io/vm={vm-name} to target VM pod
- **FR-039**: Service MUST expose port 22 (SSH) and port 3389 (RDP) with TCP protocol
- **FR-040**: Service type MUST be NodePort by default or LoadBalancer with Tailscale annotations when enableTailscale=true
- **FR-041**: When Tailscale is enabled, Service MUST include annotations tailscale.com/expose=true and tailscale.com/hostname

#### Desktop Configuration

- **FR-042**: Full desktop configuration (vm-hetzner.nix) MUST disable GRUB (KubeVirt boots via hypervisor, not GRUB in running VMs)
- **FR-043**: Full configuration MUST import modules for KDE Plasma, xrdp, VNC, and development tools
- **FR-044**: Full configuration MUST configure PulseAudio (not PipeWire) for RDP audio redirection compatibility
- **FR-045**: Full configuration MUST disable SDDM auto-login to prevent D-Bus conflicts with RDP sessions
- **FR-046**: Full configuration MUST enable xrdp service with xfce4-session window manager
- **FR-047**: Full configuration MUST configure VNC server on port 5901 with password authentication
- **FR-048**: Full configuration MUST open firewall ports 22, 3389, 5900, 5901

#### Binary Cache Integration

- **FR-049**: System MUST configure NixOS VMs to use Attic cache as primary substituter before cache.nixos.org
- **FR-050**: VM Nix configuration MUST include substituter URL http://attic.nix-cache.svc.cluster.local:8080/nixos
- **FR-051**: VM Nix configuration MUST include Attic cache public key in trusted-public-keys list
- **FR-052**: NixOS rebuild MUST query Attic first for packages, falling back to cache.nixos.org if not found
- **FR-053**: System MUST support pushing VM system closure to Attic after first build to populate cache

#### GitOps Integration

- **FR-054**: System MUST synthesize VirtualMachine manifests using CDK8s charts (NixOsVmChart, NixOsDataVolumeChart, NixOsImageServerChart)
- **FR-055**: System MUST generate ArgoCD Application manifests for each VM package
- **FR-056**: System MUST use cnoe:// URL syntax for local development with idpbuilder
- **FR-057**: System MUST configure ArgoCD sync waves ensuring image-server → datavolume → vm order (waves: -50, 0, 10)
- **FR-058**: System MUST register VM charts in IdpBuilderChartFactory for discovery
- **FR-059**: System MUST support automated sync policy with prune and selfHeal enabled

### Key Entities

- **qcow2 Image**: Bootable NixOS disk image (~1.7GB) with GRUB, cloud-init, SSH, and minimal packages, generated by nixos-generators kubevirt format
- **DataVolume**: KubeVirt/CDI resource that imports qcow2 image from HTTP source into a 50Gi PVC for VM root disk
- **VirtualMachine**: KubeVirt resource defining VM configuration (CPU: 2 cores, Memory: 4Gi, disks, network interfaces, cloud-init)
- **VirtualMachineInstance**: Running instance of a VM with status (IP address, phase, conditions), created automatically by VirtualMachine resource
- **Cloud-Init Secret**: Kubernetes Secret storing userdata YAML with user configuration, SSH keys, and passwords for VM initialization
- **Image Server**: nginx Deployment serving qcow2 files via HTTP (port 80) from Docker container image for DataVolume import
- **VM Service**: Kubernetes Service exposing VM SSH (22) and RDP (3389) ports via NodePort or Tailscale LoadBalancer
- **Attic Binary Cache**: Nix package cache (deployed per spec 003) providing 8x faster rebuilds by serving packages at in-cluster speeds (100-500 MB/s)
- **Full Configuration**: vm-hetzner.nix flake target with KDE Plasma desktop, xrdp, VNC, development tools, applied via nixos-rebuild after initial deployment

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: NixOS qcow2 image builds successfully in under 10 minutes using nixos-generate --format kubevirt
- **SC-002**: Docker image containing qcow2 pushes to registry and deploys image server within 2 minutes
- **SC-003**: DataVolume imports qcow2 image from image server within 1 minute (1.7GB at 100+ MB/s cluster networking speeds)
- **SC-004**: VirtualMachine reaches "Running" status within 2 minutes of DataVolume import completion
- **SC-005**: SSH connection to VM succeeds within 30 seconds of VM reaching Running status (cloud-init completes quickly)
- **SC-006**: Engineer can SSH into VM and execute basic commands (ping, curl, vim) immediately after first connection
- **SC-007**: Applying full desktop configuration via nixos-rebuild completes in under 3 minutes when Attic cache is populated (8x faster than 20+ minute internet download)
- **SC-008**: RDP connection to VM succeeds and displays KDE Plasma desktop within 10 seconds of nixos-rebuild completion
- **SC-009**: Desktop applications (Firefox, terminal) launch and function correctly on first attempt after RDP connection
- **SC-010**: Total time from "no VM" to "working KDE desktop via RDP" is under 10 minutes for first deployment (image build + deploy + cloud-init + SSH + rebuild)
- **SC-011**: Subsequent VM deployments (using cached image) complete in under 5 minutes from ArgoCD sync to RDP-ready desktop
- **SC-012**: CDK8s charts synthesize successfully and ArgoCD applications reach Synced/Healthy status within 3 minutes
- **SC-013**: VMs automatically restart and resume operation after cluster node restarts or VM pod failures within 2 minutes

### Assumptions

1. **KubeVirt installation**: Assumes KubeVirt operator and CDI are already installed in the Kind cluster with default configuration
2. **Storage provisioner**: Assumes Kind cluster uses local-path-provisioner for PVC creation with sufficient disk space (minimum 60GB per VM)
3. **Nixos-generators availability**: Assumes nixos-generators tool is installed on the build machine (Hetzner host) with Nix flakes enabled
4. **Docker registry access**: Assumes docker.io/vpittamp23 registry is publicly accessible and credentials are configured for push operations
5. **Network connectivity**: Assumes VMs can reach external internet for nixos-rebuild downloads (when Attic cache misses occur)
6. **Attic cache availability**: Assumes Attic binary cache from spec 003 is deployed and operational in nix-cache namespace
7. **SSH key availability**: Assumes SSH public key k8s_ed_test is available and private key is accessible from operator's machine
8. **Git repository access**: Assumes nixos-config repository at github.com/vpittamp/nixos-config is accessible from VMs for cloning
9. **CDK8s environment**: Assumes CDK8s project is set up with TypeScript, imports are generated, and npm dependencies are installed
10. **ArgoCD installation**: Assumes ArgoCD is installed and configured with access to Gitea repository for cnoe:// URLs
11. **Namespace creation**: Assumes "default" namespace is used for VM resources; can be customized via chart props
12. **Resource availability**: Assumes cluster has sufficient resources for VM allocation (minimum 4 cores, 8Gi memory available)
13. **Tailscale optional**: Assumes Tailscale LoadBalancer integration is optional; VMs are accessible via NodePort by default
14. **Single VM per DataVolume**: Assumes each VM gets its own DataVolume/PVC; sharing disks between VMs is not supported
15. **Image updates**: Assumes image server Docker image can be updated by re-pushing with :latest tag; VMs use existing DataVolumes and are not automatically recreated
16. **Desktop memory requirements**: Assumes 4Gi memory is sufficient for KDE Plasma + basic development usage; can be increased via chart props if needed
