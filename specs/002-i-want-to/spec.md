# Feature Specification: KubeVirt Installation with NixOS VM Images

**Feature Branch**: `002-i-want-to`
**Created**: 2025-10-10
**Status**: Draft
**Input**: User description: "i want to install kubevirt into my kind cluster using cdk8s charts. we will want to use a version of our nixos/home-manager configuration as the base of the image for the kubevirt machine. review @docs/kubevirt-documentation.md to understand the service."

## Clarifications

### Session 2025-10-10

- Q: When a VirtualMachine resource is deleted (either manually or via ArgoCD prune), what should happen to the underlying PersistentVolumeClaim containing the VM's disk data? → A: Configurable per VM via retention policy (some ephemeral, some persistent)
- Q: How should VirtualMachines communicate with each other and with containerized pods in the cluster? → A: Full network access - VMs can communicate freely with all pods and other VMs
- Q: What should be the default CPU and memory allocation for NixOS VirtualMachines when not explicitly specified in the chart? → A: 2 CPU cores and 4GB RAM
- Q: Which NixOS configuration should be used as the base for VM images? → A: Use existing /etc/nixos flake with new vm-minimal.nix configuration that imports base.nix (reuses SSH keys, user config, core packages)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy KubeVirt to Kind Cluster (Priority: P1)

As a platform engineer, I want to deploy KubeVirt operator and custom resources to my Kind cluster using CDK8s charts so that I can manage virtual machines declaratively alongside containerized workloads.

**Why this priority**: This is the foundational capability required before any VMs can be created. Without KubeVirt installed, no other functionality is possible.

**Independent Test**: Can be fully tested by synthesizing the CDK8s chart, deploying it via ArgoCD, and verifying all KubeVirt components (operator, controllers, handlers) are running in the kubevirt namespace.

**Acceptance Scenarios**:

1. **Given** I have a Kind cluster running with ArgoCD installed, **When** I synthesize and deploy the KubeVirt CDK8s chart, **Then** the KubeVirt operator pod is running in the kubevirt namespace
2. **Given** the KubeVirt operator is deployed, **When** I check the KubeVirt custom resource status, **Then** it shows phase "Deployed" and condition "Available"
3. **Given** KubeVirt is fully deployed, **When** I list all pods in the kubevirt namespace, **Then** I see virt-controller, virt-handler, and virt-api pods in Running state
4. **Given** KubeVirt is installed, **When** I query for VirtualMachine CRD availability, **Then** the CRD is registered and accessible via kubectl

---

### User Story 2 - Create NixOS-based VM Image (Priority: P2)

As a platform engineer, I want to build a VM disk image from my NixOS/home-manager configuration so that I can run virtual machines with my customized NixOS environment.

**Why this priority**: This enables the core value proposition of running NixOS VMs in Kubernetes. Without a NixOS-based image, VMs would need to use generic Linux distributions.

**Independent Test**: Can be fully tested by building a NixOS disk image (qcow2 format), creating a DataVolume from that image, and verifying the DataVolume import completes successfully.

**Acceptance Scenarios**:

1. **Given** I have a NixOS/home-manager configuration, **When** I build a VM disk image from that configuration, **Then** a qcow2 image file is created containing the NixOS system
2. **Given** I have a NixOS qcow2 image, **When** I create a DataVolume pointing to that image, **Then** the Containerized Data Importer (CDI) successfully imports the image into a PersistentVolumeClaim
3. **Given** the DataVolume import is complete, **When** I check the DataVolume status, **Then** it shows phase "Succeeded" and the PVC is bound
4. **Given** I have multiple NixOS configurations, **When** I build images for different configurations, **Then** each configuration produces a unique, identifiable VM image

---

### User Story 3 - Launch NixOS Virtual Machine (Priority: P3)

As a platform engineer, I want to create and start a VirtualMachine resource using my NixOS disk image so that I can run a fully functional NixOS VM in my Kubernetes cluster.

**Why this priority**: This delivers the end-to-end experience of running custom NixOS VMs. It demonstrates the integration of KubeVirt with custom VM images.

**Independent Test**: Can be fully tested by creating a VirtualMachine manifest referencing the NixOS DataVolume, starting the VM, and accessing its console to verify NixOS is running.

**Acceptance Scenarios**:

1. **Given** I have a NixOS DataVolume available, **When** I create a VirtualMachine resource referencing that DataVolume, **Then** the VirtualMachine resource is created successfully
2. **Given** a VirtualMachine resource exists with runStrategy "Manual", **When** I start the VM, **Then** a VirtualMachineInstance is created and a virt-launcher pod is scheduled
3. **Given** a VirtualMachine is starting, **When** I check the VirtualMachineInstance status, **Then** it transitions through Scheduling → Running states
4. **Given** a VirtualMachine is running, **When** I connect to its console, **Then** I see the NixOS login prompt with my configured system settings
5. **Given** a running VirtualMachine, **When** I stop the VM, **Then** the VirtualMachineInstance is terminated and the virt-launcher pod is deleted

---

### User Story 4 - Manage VM Lifecycle via GitOps (Priority: P4)

As a platform engineer, I want to define VirtualMachine resources in CDK8s charts and deploy them via ArgoCD so that VM lifecycle management follows the same GitOps workflow as container workloads.

**Why this priority**: This ensures consistency with the platform's GitOps-first deployment principle. It allows VMs to be version-controlled and automatically synced.

**Independent Test**: Can be fully tested by creating a CDK8s chart that defines a VirtualMachine, synthesizing it to dist/, deploying via ArgoCD, and verifying the VM is created and managed by ArgoCD.

**Acceptance Scenarios**:

1. **Given** I have a CDK8s chart defining a VirtualMachine, **When** I synthesize the chart, **Then** valid Kubernetes manifests for the VirtualMachine are generated in dist/
2. **Given** I have VirtualMachine manifests in a package, **When** I deploy the package via ArgoCD, **Then** ArgoCD creates the VirtualMachine resource and shows it as Synced/Healthy
3. **Given** a VirtualMachine is managed by ArgoCD, **When** I update the VirtualMachine specification in the chart and re-synthesize, **Then** ArgoCD detects the drift and syncs the changes
4. **Given** a VirtualMachine is running, **When** I delete the ArgoCD Application, **Then** the VirtualMachine resource is deleted according to sync policy and configured PVC retention policy

---

### Edge Cases

- What happens when KubeVirt installation fails due to insufficient cluster resources (memory, CPU)?
- How does the system handle NixOS image build failures (missing dependencies, configuration errors)?
- What occurs when a DataVolume import times out or the image source is unreachable?
- How is VM state managed when the underlying node fails or the virt-launcher pod is evicted?
- What happens when multiple VirtualMachines reference the same DataVolume (PVC access mode conflicts)?
- How does the system handle VirtualMachine creation when the referenced DataVolume doesn't exist?
- What occurs when attempting to live migrate a VM on a single-node Kind cluster?
- How are resource limits enforced when VM memory/CPU requests exceed node capacity?
- What happens to PVC data when a VirtualMachine with "retain" policy is deleted then recreated with the same name?

## Requirements *(mandatory)*

### Functional Requirements

#### KubeVirt Installation

- **FR-001**: System MUST deploy KubeVirt operator to the kubevirt namespace using CDK8s-generated manifests
- **FR-002**: System MUST create KubeVirt custom resource with software emulation enabled (useEmulation: true) for Kind cluster compatibility
- **FR-003**: System MUST import KubeVirt CRDs into the CDK8s project to enable type-safe VirtualMachine resource definitions
- **FR-004**: System MUST register KubeVirt chart in IdpBuilderChartFactory for inclusion in application synthesis workflow
- **FR-005**: System MUST configure KubeVirt ArgoCD Application with sync wave -100 to ensure deployment before any VirtualMachine resources
- **FR-006**: System MUST support declarative KubeVirt configuration via CDK8s chart properties (version, feature gates, emulation settings)

#### NixOS VM Image Creation

- **FR-007**: System MUST build qcow2 VM disk images from NixOS/home-manager configurations
- **FR-008**: System MUST make NixOS disk images accessible to Kubernetes (via registry, HTTP server, or local storage)
- **FR-009**: System MUST deploy Containerized Data Importer (CDI) operator and custom resources for importing VM images
- **FR-010**: System MUST create DataVolume resources that import NixOS qcow2 images into PersistentVolumeClaims
- **FR-011**: System MUST track DataVolume import progress and report completion status
- **FR-012**: System MUST support multiple NixOS configurations with distinct VM images

#### Virtual Machine Management

- **FR-013**: System MUST define VirtualMachine resources in CDK8s charts with type-safe VirtualMachine CRD bindings
- **FR-014**: System MUST allow VirtualMachines to reference DataVolumes as boot disks
- **FR-015**: System MUST support starting, stopping, and restarting VirtualMachines via runStrategy configuration
- **FR-016**: System MUST provide console access to running VirtualMachineInstances via virtctl command-line tool
- **FR-017**: System MUST expose VirtualMachine lifecycle state (Stopped, Starting, Running, Stopping) via status fields
- **FR-018**: System MUST support cloud-init configuration for VirtualMachines (hostname, users, SSH keys, network config)
- **FR-024**: System MUST support configurable PVC retention policies per VirtualMachine (delete PVC on VM deletion, or retain PVC for data persistence)
- **FR-028**: System MUST use default resource allocation of 2 CPU cores and 4GB RAM for VirtualMachines when resources are not explicitly specified in chart properties

#### Networking

- **FR-025**: System MUST use default pod networking for VirtualMachines (masquerade mode with pod network integration)
- **FR-026**: System MUST allow VirtualMachines to communicate freely with all pods and other VMs in the cluster
- **FR-027**: System MUST assign VirtualMachineInstances IP addresses from the pod network CIDR

#### GitOps Integration

- **FR-019**: System MUST synthesize VirtualMachine manifests to dist/ directory following package-based architecture
- **FR-020**: System MUST create ArgoCD Application manifests for packages containing VirtualMachine resources
- **FR-021**: System MUST use cnoe:// URL syntax for local development deployment via idpbuilder
- **FR-022**: System MUST support automated sync policy for VirtualMachine resources (prune, selfHeal)
- **FR-023**: System MUST declare sync wave dependencies ensuring KubeVirt/CDI are deployed before VirtualMachines

### Key Entities

- **KubeVirt Operator**: Manages KubeVirt lifecycle, deploys controllers and handlers, reconciles KubeVirt custom resource
- **KubeVirt Custom Resource**: Defines cluster-wide KubeVirt configuration (version, emulation mode, feature gates)
- **VirtualMachine (VM)**: Declarative specification of a virtual machine (disk, memory, CPU, runStrategy, PVC retention policy, default resources: 2 CPU cores, 4GB RAM)
- **VirtualMachineInstance (VMI)**: Ephemeral running instance of a VirtualMachine (like Pod for containers)
- **DataVolume**: High-level abstraction for importing VM disk images into PersistentVolumeClaims
- **PersistentVolumeClaim (PVC)**: Kubernetes storage resource backing VirtualMachine disks (lifecycle controlled by retention policy)
- **NixOS Disk Image**: qcow2 format VM image built from NixOS/home-manager configuration
- **Containerized Data Importer (CDI)**: Operator that manages DataVolume imports from various sources
- **virtctl**: Command-line tool for interacting with VirtualMachines (start, stop, console access)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: KubeVirt operator and all components deploy successfully within 5 minutes of ArgoCD sync
- **SC-002**: Platform engineer can create a new VirtualMachine from a NixOS image in under 10 minutes (including image import)
- **SC-003**: VirtualMachine boot time from "start" command to console login prompt is under 3 minutes
- **SC-004**: DataVolume import completes successfully for NixOS qcow2 images up to 10GB in size
- **SC-005**: VirtualMachine resources sync via ArgoCD without manual intervention (automated: prune, selfHeal)
- **SC-006**: Platform engineer can access VirtualMachine console and execute commands within 30 seconds of VM running state
- **SC-007**: All KubeVirt manifests pass TypeScript compilation and synthesize without errors
- **SC-008**: VirtualMachine state changes (start, stop, restart) complete within 60 seconds of command execution
- **SC-009**: Multiple VirtualMachines can run concurrently on Kind cluster limited only by node resources (CPU, memory)
- **SC-010**: Platform engineer can modify VirtualMachine configuration in CDK8s chart, re-synthesize, and ArgoCD auto-syncs changes within 3 minutes
- **SC-011**: VirtualMachine with "retain" PVC policy preserves disk data after VM deletion and allows reattachment to new VM
- **SC-012**: VirtualMachines can communicate with all pods and other VMs on the cluster network without additional configuration
- **SC-013**: VirtualMachines created without explicit resource specifications allocate 2 CPU cores and 4GB RAM by default

### Assumptions

1. **Kind cluster configuration**: Assumes Kind cluster has sufficient resources (minimum 8GB RAM, 4 CPU cores) to run KubeVirt with software emulation
2. **NixOS build environment**: Assumes NixOS build tools (nix-build, nixos-generate) are available in development environment for creating qcow2 images; uses existing /etc/nixos flake configuration
3. **Storage class**: Assumes Kind cluster has a default StorageClass that supports ReadWriteOnce PersistentVolumeClaims (typically local-path-provisioner)
4. **Image hosting**: Assumes NixOS qcow2 images can be hosted via HTTP server, OCI registry, or direct file access for DataVolume import
5. **Software emulation**: Assumes software emulation (QEMU without KVM) is acceptable for development/testing; production would require nested virtualization or bare metal
6. **Single-node cluster**: Assumes live migration feature is not required for Kind (single-node) deployment; migration would require multi-node cluster
7. **virtctl installation**: Assumes virtctl CLI tool is installed manually or via package manager for console access and VM operations
8. **CDI storage**: Assumes CDI's scratch space requirements (temporary storage for image conversion) are met by cluster storage capacity
9. **Network isolation**: Assumes development/testing environment does not require strict network isolation between VMs and pods; production deployments may require NetworkPolicies

## Implementation Lessons Learned *(added 2025-10-11)*

### Critical Insights from Production Deployment

1. **Kind Cluster Configuration Must Be Dynamic**
   - **Lesson**: The deployment script (`deployment/scripts/deploy-linux-ssh.sh`) generates kind-config.yaml dynamically at runtime (lines 136-163). Static config files (kind-config.yaml, kind-config-linux-ssh.yaml) are NOT used.
   - **Action**: Always update the dynamic config generation in the deployment script, never edit static config files.
   - **Impact**: Required mount for `/home/vpittamp/stacks/nixos-images` must be added to the script's config generation, not to static YAML files.

2. **DataVolume Specs Are Immutable**
   - **Lesson**: Once a DataVolume is created, its spec cannot be modified. Attempting to update via ArgoCD results in webhook validation errors: "Cannot update DataVolume Spec".
   - **Action**: To change DataVolume configuration (imageUrl, storageSize), must delete the existing DataVolume and recreate it.
   - **Workaround**: `kubectl delete dv <name>`, then sync ArgoCD application to recreate with new spec.
   - **Impact**: DataVolume updates require careful planning and downtime for attached VMs.

3. **Symlinks Break Inside Containers**
   - **Lesson**: Symlinks pointing to host-only paths (e.g., Nix store `/nix/store/...`) don't work inside containers. The nginx image server cannot serve symlinked qcow2 files.
   - **Action**: Use actual qcow2 files or copy symlink targets to regular files before deployment.
   - **Example**: `kubevirt-vm.qcow2` (symlink to Nix store) → Create `kubevirt-vm-actual.qcow2` as a regular file or use the Nix store path directly if mounted.

4. **Sync Wave Architecture Is Critical**
   - **Lesson**: Proper sync wave ordering prevents race conditions and deployment failures.
   - **Verified Order**:
     - `-110`: Operators (kubevirt-operator, cdi-operator) - Deploy CRDs
     - `-90`: Custom Resources (KubeVirt CR, CDI CR) - Use the CRDs
     - `-50`: Image server (nginx serving qcow2 files) - Must be ready before imports
     - `0`: DataVolumes - Import images from image server
     - `10`: VirtualMachines - Wait for DataVolumes to be ready
     - `15`: Services - Expose VM ports after VM creation
   - **Impact**: Without correct ordering, DataVolumes fail with 404 errors (image server not ready) or VMs fail to start (DataVolume not imported).

5. **VirtualMachine RunStrategy Configuration**
   - **Lesson**: `runStrategy: Manual` requires explicit start/stop commands. For auto-start behavior, use `runStrategy: Always`.
   - **Options**:
     - `Always`: VM starts automatically and restarts on failure (best for stateful services)
     - `Manual`: Explicit start/stop control via virtctl or kubectl patch (best for development)
     - `RerunOnFailure`: Restart only on failure
     - `Halted`: VM remains stopped
   - **Implementation**: Made runStrategy configurable in NixOsVmChart with default of `Always`.

6. **ArgoCD Operation Management**
   - **Lesson**: ArgoCD sync operations can get stuck in a loop when trying to patch immutable resources (like DataVolume specs).
   - **Resolution**: Use `argocd app terminate-op` to kill stuck operations, then perform necessary resource cleanup (delete immutable resources) before re-syncing.
   - **Command**: `argocd app terminate-op argocd/<app-name> --insecure`

7. **Test Images Before Production**
   - **Lesson**: Testing with small images (100MB) before using large images (21GB) saves time during development and debugging.
   - **Strategy**:
     - Create test image: `truncate -s 100M kubevirt-vm-test.qcow2`
     - Validate entire pipeline with test image (import, VM start, network)
     - Switch to production image only after validation
   - **Impact**: Reduced DataVolume import time from 10+ minutes to seconds during testing.

8. **Chart Implementation Patterns**
   - **Lesson**: Use `ApiObject` from cdk8s directly instead of CRD-specific imports to avoid TypeScript compilation issues with complex CRDs.
   - **Pattern**:
     ```typescript
     new ApiObject(this, 'vm', {
       apiVersion: 'kubevirt.io/v1',
       kind: 'VirtualMachine',
       metadata: { ... },
       spec: { ... }
     });
     ```
   - **Rationale**: KubeVirt and CDI CRDs are complex and frequently updated. Using ApiObject provides flexibility without import regeneration.

9. **Operator vs Custom Resource Charts**
   - **Lesson**: Separate operator deployment from custom resource creation into distinct charts with different sync waves.
   - **Structure**:
     - `KubeVirtOperatorChart`: Deploys operator using `Include` with upstream YAML (sync wave -110)
     - `KubeVirtCRChart`: Creates KubeVirt CR with configuration (sync wave -90)
     - `CDIOperatorChart`: Deploys CDI operator (sync wave -110)
     - `CDICRChart`: Creates CDI CR (sync wave -90)
   - **Benefit**: Operators deploy CRDs first, then custom resources can use those CRDs without race conditions.

10. **Image Server Architecture**
    - **Lesson**: Simple nginx-based HTTP server is sufficient for local development. Use hostPath volume to mount nixos-images directory into the pod.
    - **Configuration**:
      - hostPath mount from host → Kind container (kind-config)
      - hostPath volume in nginx Deployment referencing container path
      - Service exposing port 80 for CDI to fetch images
    - **Alternative**: For production, use OCI registry with proper versioning and authentication.

### Updated Requirements Based on Implementation

- **FR-029** (NEW): System MUST generate kind-config.yaml dynamically via deployment script with all required mounts (nixos-images, Azure Workload Identity keys)
- **FR-030** (NEW): System MUST use regular qcow2 files (not symlinks) for DataVolume imports when using HTTP source
- **FR-031** (NEW): System MUST separate operator deployment charts from custom resource charts with appropriate sync waves
- **FR-032** (NEW): System MUST support runStrategy configuration in VirtualMachine charts with sensible defaults (Always for production, Manual for development)
