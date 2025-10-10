# Phase 1: Data Model & Entity Schemas

**Feature**: KubeVirt Installation with NixOS VM Images
**Date**: 2025-10-10

## Overview

This document defines the data models, entity schemas, and relationships for KubeVirt custom resources and NixOS VM configurations. All schemas are based on KubeVirt CRDs and will be imported into CDK8s for type-safe manifest generation.

## Entity Relationship Diagram

```
┌─────────────────────┐
│  KubeVirt Operator  │
│   (Deployment)      │
└──────────┬──────────┘
           │ manages
           ▼
┌─────────────────────┐
│   KubeVirt CR       │
│  (cluster config)   │
└─────────────────────┘

┌─────────────────────┐
│    CDI Operator     │
│   (Deployment)      │
└──────────┬──────────┘
           │ manages
           ▼
┌─────────────────────┐       imports      ┌─────────────────────┐
│    DataVolume       │────────────────────│  NixOS qcow2 Image  │
│  (image import)     │                    │   (HTTP source)     │
└──────────┬──────────┘                    └─────────────────────┘
           │ creates
           ▼
┌─────────────────────┐
│        PVC          │
│  (VM disk storage)  │
└──────────┬──────────┘
           │ referenced by
           ▼
┌─────────────────────┐      spawns      ┌─────────────────────┐
│   VirtualMachine    │──────────────────│ VirtualMachineInstance
│  (declarative spec) │                  │  (running instance) │
└─────────────────────┘                  └──────────┬──────────┘
                                                    │ creates
                                                    ▼
                                         ┌─────────────────────┐
                                         │   virt-launcher Pod │
                                         │   (QEMU process)    │
                                         └─────────────────────┘
```

## Core Entities

### 1. KubeVirt Custom Resource

**API Group**: `kubevirt.io/v1`
**Kind**: `KubeVirt`
**Scope**: Cluster-wide (one per cluster)

**Purpose**: Defines cluster-wide KubeVirt configuration, managed by KubeVirt operator.

**Schema**:

```typescript
// Imported from cdk8s/imports/kubevirt.io.ts
interface KubeVirtSpec {
  /**
   * Cluster-wide configuration for KubeVirt features
   */
  configuration?: {
    /**
     * Developer-focused configuration (software emulation, debug logging)
     */
    developerConfiguration?: {
      /**
       * Enable software emulation (QEMU without KVM)
       * Required for Kind cluster (no nested virtualization)
       * @default false
       */
      useEmulation?: boolean;

      /**
       * Additional feature gates to enable
       * @example ["LiveMigration", "CPUManager"]
       */
      featureGates?: string[];
    };

    /**
     * Network configuration
     */
    networkConfiguration?: {
      /**
       * Default pod network interface
       * @default "pod"
       */
      defaultNetworkInterface?: string;
    };
  };

  /**
   * Custom TLS certificate for KubeVirt API
   */
  certificateRotationStrategy?: {
    selfSigned?: {
      /**
       * Certificate authority configuration
       */
      ca?: {
        /**
         * Duration for CA certificate validity
         * @default "48h"
         */
        duration?: string;
      };
    };
  };

  /**
   * Image pull policy for KubeVirt components
   * @default "IfNotPresent"
   */
  imagePullPolicy?: 'Always' | 'IfNotPresent' | 'Never';

  /**
   * Workload placement configuration
   */
  workloadUpdateStrategy?: {
    /**
     * Update strategy for KubeVirt workloads
     * @default "RollingUpdate"
     */
    workloadUpdateMethods?: ('LiveMigrate' | 'Evict')[];
  };
}
```

**Validation Rules**:
- `useEmulation` MUST be `true` for Kind clusters (no KVM access)
- `featureGates` MUST be valid KubeVirt feature gate names
- Only one KubeVirt CR per cluster

**State Transitions**:
```
Created → Deploying → Deployed → Ready
         ↓ (error)
         Failed
```

**Example**:
```yaml
apiVersion: kubevirt.io/v1
kind: KubeVirt
metadata:
  name: kubevirt
  namespace: kubevirt
spec:
  configuration:
    developerConfiguration:
      useEmulation: true  # Required for Kind
  imagePullPolicy: IfNotPresent
```

---

### 2. VirtualMachine

**API Group**: `kubevirt.io/v1`
**Kind**: `VirtualMachine`
**Scope**: Namespaced

**Purpose**: Declarative specification of a virtual machine (like Deployment for containers).

**Schema**:

```typescript
// Imported from cdk8s/imports/kubevirt.io.ts
interface VirtualMachineSpec {
  /**
   * Run strategy determines VM lifecycle management
   */
  runStrategy?: 'Always' | 'Manual' | 'Halted' | 'RerunOnFailure';

  /**
   * Deprecated: Use runStrategy instead
   * @deprecated
   */
  running?: boolean;

  /**
   * DataVolume templates for ephemeral disks
   * DataVolumes created with ownerReference to VM (deleted when VM deleted)
   */
  dataVolumeTemplates?: DataVolumeSpec[];

  /**
   * VM instance template (like Pod template in Deployment)
   */
  template: {
    metadata?: {
      labels?: { [key: string]: string };
      annotations?: { [key: string]: string };
    };
    spec: VirtualMachineInstanceSpec;
  };
}

interface VirtualMachineInstanceSpec {
  /**
   * Domain is the virtual hardware configuration
   */
  domain: {
    /**
     * CPU configuration
     */
    cpu?: {
      /**
       * Number of CPU cores
       * @default 1
       */
      cores?: number;

      /**
       * Number of CPU sockets
       * @default 1
       */
      sockets?: number;

      /**
       * Number of threads per core
       * @default 1
       */
      threads?: number;
    };

    /**
     * Memory configuration
     */
    memory?: {
      /**
       * Guest memory (e.g., "4Gi", "512Mi")
       */
      guest?: string;
    };

    /**
     * Resource requests and limits (Kubernetes-style)
     */
    resources?: {
      requests?: {
        memory?: string;
        cpu?: string;
      };
      limits?: {
        memory?: string;
        cpu?: string;
      };
    };

    /**
     * Devices attached to VM
     */
    devices: {
      /**
       * Disks attached to VM
       */
      disks: Array<{
        name: string;
        /**
         * Disk type configuration
         */
        disk?: {
          /**
           * Bus type (virtio, sata, scsi)
           * @default "virtio"
           */
          bus?: string;
        };
      }>;

      /**
       * Network interfaces
       */
      interfaces?: Array<{
        name: string;
        /**
         * Masquerade interface (pod network integration)
         */
        masquerade?: {};
        /**
         * Bridge interface (direct network access)
         */
        bridge?: {};
      }>;
    };
  };

  /**
   * Networks available to VM
   */
  networks?: Array<{
    name: string;
    /**
     * Pod network (default Kubernetes network)
     */
    pod?: {};
  }>;

  /**
   * Volumes attached to VM
   */
  volumes: Array<{
    name: string;
    /**
     * DataVolume reference (for persistent or ephemeral disks)
     */
    dataVolume?: {
      name: string;
    };
    /**
     * PVC reference (for existing PVCs)
     */
    persistentVolumeClaim?: {
      claimName: string;
    };
    /**
     * Cloud-init configuration
     */
    cloudInitNoCloud?: {
      /**
       * Cloud-init user data (YAML format)
       */
      userData?: string;
      /**
       * Secret reference for cloud-init data
       */
      secretRef?: {
        name: string;
      };
    };
  }>;

  /**
   * Termination grace period (seconds)
   * @default 30
   */
  terminationGracePeriodSeconds?: number;
}

interface VirtualMachineStatus {
  /**
   * Current VM state
   */
  printableStatus?: 'Stopped' | 'Starting' | 'Running' | 'Paused' | 'Stopping' | 'Terminating' | 'Migrating' | 'Unknown';

  /**
   * Conditions for VM lifecycle
   */
  conditions?: Array<{
    type: 'Ready' | 'Paused' | 'LiveMigratable';
    status: 'True' | 'False' | 'Unknown';
    reason?: string;
    message?: string;
    lastTransitionTime?: string;
  }>;

  /**
   * Reference to created VirtualMachineInstance
   */
  created?: boolean;

  /**
   * Is VM ready (Running and healthy)
   */
  ready?: boolean;
}
```

**Validation Rules**:
- `runStrategy` MUST be one of: `Always`, `Manual`, `Halted`, `RerunOnFailure`
- `domain.resources.requests` MUST be specified (CPU and memory)
- Default resources (when not specified): `cpu: "2"`, `memory: "4Gi"` (FR-028)
- `volumes[].name` MUST match `devices.disks[].name`
- DataVolume referenced in `volumes[]` MUST exist (unless using `dataVolumeTemplates`)
- Cloud-init `userData` MUST be valid YAML with `#cloud-config` header

**State Transitions**:
```
Stopped ──start──→ Starting → Running
  ↑                             │
  └──────────stop───────────────┘

Running ──restart──→ Stopping → Starting → Running
Running ──migrate──→ Migrating → Running (on different node)
```

**Retention Policies** (FR-024):

**Ephemeral (delete PVC on VM deletion)**:
```yaml
spec:
  dataVolumeTemplates:  # Owned by VM, deleted when VM deleted
    - metadata:
        name: my-vm-disk
      spec:
        source:
          http:
            url: http://server/image.qcow2
        pvc:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 20Gi
  template:
    spec:
      volumes:
        - name: rootdisk
          dataVolume:
            name: my-vm-disk  # References dataVolumeTemplate
```

**Persistent (retain PVC on VM deletion)**:
```yaml
# Separate DataVolume resource (no ownerReference)
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: shared-nixos-disk
spec:
  source:
    http:
      url: http://server/nixos.qcow2
  pvc:
    accessModes: [ReadWriteOnce]
    resources:
      requests:
        storage: 20Gi
---
# VirtualMachine references existing DataVolume
apiVersion: kubevirt.io/v1
kind: VirtualMachine
spec:
  template:
    spec:
      volumes:
        - name: rootdisk
          dataVolume:
            name: shared-nixos-disk  # References external DataVolume
```

**Example (NixOS VM with cloud-init)**:
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: nixos-dev-vm
  namespace: default
spec:
  runStrategy: Manual  # Explicit start/stop
  template:
    spec:
      domain:
        resources:
          requests:
            memory: 4Gi
            cpu: "2"
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
        memory:
          guest: 4Gi
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: nixos-dev-datavolume
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              hostname: nixos-dev
              users:
                - name: dev
                  sudo: ALL=(ALL) NOPASSWD:ALL
                  ssh_authorized_keys:
                    - ssh-ed25519 AAAA... user@host
```

---

### 3. VirtualMachineInstance (VMI)

**API Group**: `kubevirt.io/v1`
**Kind**: `VirtualMachineInstance`
**Scope**: Namespaced

**Purpose**: Ephemeral running instance of a VirtualMachine (like Pod for containers). Created automatically by VirtualMachine controller.

**Schema**:

```typescript
interface VirtualMachineInstanceSpec {
  // Same structure as VirtualMachine.spec.template.spec
  domain: { /* ... */ };
  networks?: Array<{ /* ... */ }>;
  volumes: Array<{ /* ... */ }>;
}

interface VirtualMachineInstanceStatus {
  /**
   * Current phase of VMI lifecycle
   */
  phase?: 'Pending' | 'Scheduling' | 'Scheduled' | 'Running' | 'Succeeded' | 'Failed' | 'Unknown';

  /**
   * Node where VMI is running
   */
  nodeName?: string;

  /**
   * IP addresses assigned to VMI
   */
  interfaces?: Array<{
    ipAddress?: string;
    ipAddresses?: string[];
    mac?: string;
    name: string;
  }>;

  /**
   * Guest OS information (requires guest agent)
   */
  guestOSInfo?: {
    name?: string;
    version?: string;
    kernelRelease?: string;
  };

  /**
   * Conditions for VMI readiness
   */
  conditions?: Array<{
    type: 'Ready' | 'PodReady' | 'AgentConnected';
    status: 'True' | 'False' | 'Unknown';
    reason?: string;
  }>;
}
```

**Lifecycle**:
- **Created by**: VirtualMachine controller when `runStrategy` requires VM to run
- **Deleted by**: VirtualMachine controller when VM is stopped
- **Managed by**: virt-controller (creates virt-launcher Pod)

**State Transitions**:
```
Pending → Scheduling → Scheduled → Running → Succeeded
         ↓ (error)                  ↓ (error)
         Failed ←───────────────────┘
```

**Example**:
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstance
metadata:
  name: nixos-dev-vm
  namespace: default
  ownerReferences:  # Created and owned by VirtualMachine
    - apiVersion: kubevirt.io/v1
      kind: VirtualMachine
      name: nixos-dev-vm
status:
  phase: Running
  nodeName: localdev-control-plane
  interfaces:
    - ipAddress: 10.244.0.15
      mac: 02:00:00:00:00:01
      name: default
  guestOSInfo:
    name: "NixOS"
    version: "24.11"
    kernelRelease: "6.6.52"
```

---

### 4. DataVolume

**API Group**: `cdi.kubevirt.io/v1beta1`
**Kind**: `DataVolume`
**Scope**: Namespaced

**Purpose**: High-level abstraction for importing VM disk images into PersistentVolumeClaims.

**Schema**:

```typescript
interface DataVolumeSpec {
  /**
   * Source of the VM image data
   */
  source?: {
    /**
     * HTTP/HTTPS source
     */
    http?: {
      /**
       * URL of the image file
       * @example "http://nixos-image-server.default.svc.cluster.local/nixos-dev.qcow2"
       */
      url: string;

      /**
       * Secret containing HTTP basic auth credentials
       */
      secretRef?: string;

      /**
       * Extra headers to send with HTTP request
       */
      extraHeaders?: string[];
    };

    /**
     * Container registry source
     */
    registry?: {
      /**
       * Registry URL
       * @example "docker://gitea.cnoe.localtest.me:8443/giteaadmin/nixos-dev:latest"
       */
      url: string;

      /**
       * Secret containing registry credentials
       */
      secretRef?: string;

      /**
       * TLS certificate config map
       */
      certConfigMap?: string;
    };

    /**
     * PVC clone source (copy existing PVC)
     */
    pvc?: {
      namespace?: string;
      name: string;
    };

    /**
     * Blank disk (create empty PVC)
     */
    blank?: {};
  };

  /**
   * Target PVC specification
   */
  pvc: {
    /**
     * PVC access modes
     * @default ["ReadWriteOnce"]
     */
    accessModes?: ('ReadWriteOnce' | 'ReadOnlyMany' | 'ReadWriteMany')[];

    /**
     * PVC resources
     */
    resources: {
      requests: {
        /**
         * Storage size (should be 2x image size for overhead)
         * @example "20Gi"
         */
        storage: string;
      };
    };

    /**
     * Storage class name
     * @default cluster default StorageClass
     */
    storageClassName?: string;

    /**
     * Volume mode
     * @default "Filesystem"
     */
    volumeMode?: 'Filesystem' | 'Block';
  };

  /**
   * Content type of the source
   * @default "kubevirt" (auto-detect qcow2, raw, vmdk)
   */
  contentType?: 'kubevirt' | 'archive';
}

interface DataVolumeStatus {
  /**
   * Current phase of import process
   */
  phase?: 'Pending' | 'PVCBound' | 'ImportScheduled' | 'ImportInProgress' | 'Succeeded' | 'Failed' | 'Unknown';

  /**
   * Progress percentage (0-100)
   */
  progress?: string;

  /**
   * Conditions for DataVolume readiness
   */
  conditions?: Array<{
    type: 'Bound' | 'Ready' | 'Running';
    status: 'True' | 'False' | 'Unknown';
    reason?: string;
    message?: string;
  }>;
}
```

**Validation Rules**:
- `source` MUST have exactly one source type (http, registry, pvc, or blank)
- `pvc.resources.requests.storage` SHOULD be at least 2x source image size
- `pvc.accessModes` MUST be compatible with StorageClass (Kind: `ReadWriteOnce` only)
- HTTP `url` MUST be accessible from cluster network

**State Transitions**:
```
Pending → PVCBound → ImportScheduled → ImportInProgress → Succeeded
         ↓ (error)    ↓ (error)          ↓ (error)
         Failed ←──────┴──────────────────┘
```

**Example (HTTP source for NixOS image)**:
```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: nixos-dev-datavolume
  namespace: default
spec:
  source:
    http:
      url: "http://nixos-image-server.default.svc.cluster.local/nixos-dev.qcow2"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 20Gi  # 2x 10GB qcow2 image size
    storageClassName: standard  # Kind default: local-path
```

---

### 5. NixOS VM Configuration (Non-Kubernetes)

**Format**: Nix expression (`.nix` files)
**Location**: `nixos/vm-configs/`
**Purpose**: Defines NixOS system configuration for VM image builds.

**Schema** (Nix attribute set):

```nix
{
  config,    # NixOS configuration object
  pkgs,      # Nixpkgs package set
  lib,       # NixOS library functions
  ...
}:
{
  # System configuration
  system.stateVersion = "24.11";

  # Networking
  networking = {
    hostName = "nixos-vm";
    useDHCP = false;  # Cloud-init configures network
  };

  # Users
  users.users.root = {
    # Disable password login (use SSH keys via cloud-init)
    hashedPassword = null;
  };

  # Cloud-init support (REQUIRED for KubeVirt)
  services.cloud-init.enable = true;

  # QEMU guest agent (RECOMMENDED for VM integration)
  services.qemu-guest-agent.enable = true;

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];

  # Home-manager integration
  imports = [
    <home-manager/nixos>
  ];

  home-manager.users.<username> = import ./home-manager/user.nix;

  # Boot loader (not used in KubeVirt, but required for image build)
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };
}
```

**Validation Rules** (enforced by Nix):
- `services.cloud-init.enable` MUST be `true` (for cloud-init integration)
- `services.qemu-guest-agent.enable` SHOULD be `true` (for VM metadata)
- `boot.loader.grub.device` MUST match VM disk device (typically `/dev/vda`)
- `system.stateVersion` SHOULD match NixOS channel version

**Build Output**:
- **File**: `nixos-dev-vm.qcow2` (VM disk image)
- **Size**: Varies (typically 2-10GB depending on packages)
- **Format**: qcow2 (QEMU Copy-On-Write version 2)

**Example** (Minimal NixOS VM configuration):
```nix
# nixos/vm-configs/dev-vm.nix
{ config, pkgs, ... }:
{
  imports = [
    ./base.nix
  ];

  networking.hostName = "nixos-dev";

  services.cloud-init.enable = true;
  services.qemu-guest-agent.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    jq
  ];

  # Allow wheel group sudo without password (cloud-init adds user to wheel)
  security.sudo.wheelNeedsPassword = false;
}
```

---

## Entity Relationships

### Ownership Chain

```
VirtualMachine (owner)
└── VirtualMachineInstance (owned, ephemeral)
    └── virt-launcher Pod (owned, ephemeral)

VirtualMachine (dataVolumeTemplates)
└── DataVolume (owned, deleted with VM)
    └── PVC (owned, deleted with DataVolume)

DataVolume (standalone, no owner)
└── PVC (owned, deleted with DataVolume)
    └── Referenced by VirtualMachine (not owned, retained after VM deletion)
```

### Data Flow

```
1. Image Build:
   NixOS Configuration (.nix)
   └─[nixos-generators]→ qcow2 Image

2. Image Hosting:
   qcow2 Image
   └─[HTTP Server/OCI Registry]→ Accessible URL

3. Image Import:
   DataVolume (source: HTTP URL)
   └─[CDI Importer Pod]→ PVC with VM disk data

4. VM Creation:
   VirtualMachine (volume: dataVolume reference)
   └─[virt-controller]→ VirtualMachineInstance
       └─[virt-handler]→ virt-launcher Pod
           └─[QEMU]→ Running VM process
```

### Network Flow

```
External Request
└→ Ingress (if exposed)
   └→ Service (type: ClusterIP or LoadBalancer)
      └→ VirtualMachineInstance (pod network IP)
         └→ VM network interface (masquerade mode)
            └→ VM internal services
```

---

## Configuration Schemas

### CDK8s Chart Properties

**KubeVirtChart**:
```typescript
interface KubeVirtChartProps extends ChartProps {
  /**
   * KubeVirt version to deploy
   * @example "v1.3.1"
   */
  version: string;

  /**
   * Enable software emulation (required for Kind)
   * @default false
   */
  useEmulation?: boolean;

  /**
   * Additional feature gates
   * @default []
   */
  featureGates?: string[];
}
```

**NixOsVmChart**:
```typescript
interface NixOsVmChartProps extends ChartProps {
  /**
   * VM name (used for metadata and resource naming)
   */
  vmName: string;

  /**
   * Run strategy for VM lifecycle
   * @default "Manual"
   */
  runStrategy?: 'Always' | 'Manual' | 'Halted' | 'RerunOnFailure';

  /**
   * CPU cores allocation
   * @default 2 (FR-028)
   */
  cpuCores?: number;

  /**
   * Memory allocation (e.g., "4Gi")
   * @default "4Gi" (FR-028)
   */
  memory?: string;

  /**
   * PVC retention policy
   * @default "retain"
   */
  pvcRetention?: 'delete' | 'retain';

  /**
   * DataVolume configuration (for ephemeral or persistent)
   */
  dataVolume?: {
    /**
     * DataVolume name (for existing DataVolume)
     */
    name?: string;

    /**
     * Image URL (for new DataVolume via dataVolumeTemplates)
     */
    imageUrl?: string;

    /**
     * PVC storage size
     * @default "20Gi"
     */
    storageSize?: string;
  };

  /**
   * Cloud-init configuration
   */
  cloudInit?: {
    /**
     * Cloud-init user data (YAML string)
     */
    userData?: string;

    /**
     * Secret reference for cloud-init data
     */
    secretName?: string;
  };

  /**
   * Network configuration
   * @default pod network with masquerade
   */
  network?: {
    /**
     * Network type
     * @default "pod"
     */
    type?: 'pod' | 'multus';
  };
}
```

**NixOsDataVolumeChart**:
```typescript
interface NixOsDataVolumeChartProps extends ChartProps {
  /**
   * DataVolume name
   */
  dataVolumeName: string;

  /**
   * Image source URL
   */
  imageUrl: string;

  /**
   * Storage size
   * @default "20Gi"
   */
  storageSize?: string;

  /**
   * Storage class name
   * @default cluster default
   */
  storageClassName?: string;
}
```

---

## Validation & Constraints

### Resource Constraints

| Resource | Minimum | Default | Maximum (Kind) |
|----------|---------|---------|----------------|
| **VM CPU** | 1 core | 2 cores | 4 cores |
| **VM Memory** | 512Mi | 4Gi | 8Gi |
| **PVC Storage** | 5Gi | 20Gi | 100Gi |
| **DataVolume Import Timeout** | 10min | 30min | 60min |

### Cluster Requirements

**Kind Cluster**:
- Host RAM: ≥16GB (for 2-4 concurrent VMs)
- Host CPU: ≥4 cores
- Docker storage: ≥100GB (for VM images and PVCs)
- Kernel: Linux 4.x+ (for QEMU support)

**StorageClass**:
- Kind default: `local-path` (hostPath-based, ReadWriteOnce only)
- Required features: Dynamic provisioning, PVC expansion

---

## State Management

### VirtualMachine Lifecycle States

| State | Description | Transitions |
|-------|-------------|-------------|
| **Stopped** | VM exists but not running (no VMI) | → Starting (user start) |
| **Starting** | VMI created, virt-launcher scheduling | → Running (pod running) |
| **Running** | VM process active, console accessible | → Stopping (user stop) |
| **Stopping** | Graceful shutdown in progress | → Stopped (VMI deleted) |
| **Paused** | VM paused (memory frozen) | → Running (user unpause) |
| **Migrating** | Live migration in progress | → Running (on new node) |
| **Failed** | VM failed to start or crashed | → Starting (user restart) |

### DataVolume Import States

| Phase | Description | Next Phase |
|-------|-------------|------------|
| **Pending** | Waiting for PVC creation | PVCBound |
| **PVCBound** | PVC created, waiting for import | ImportScheduled |
| **ImportScheduled** | Importer pod scheduled | ImportInProgress |
| **ImportInProgress** | Actively importing image data | Succeeded/Failed |
| **Succeeded** | Import complete, PVC ready | (terminal) |
| **Failed** | Import failed (URL unreachable, disk full) | (terminal, manual retry) |

---

## Phase 1 Completion Checklist

- [x] Entity schemas defined for all KubeVirt CRDs (KubeVirt, VirtualMachine, VirtualMachineInstance, DataVolume)
- [x] NixOS configuration schema documented (Nix attribute set structure)
- [x] Entity relationships mapped (ownership, data flow, network flow)
- [x] Validation rules defined for each entity
- [x] State transitions documented (VM lifecycle, DataVolume import)
- [x] PVC retention policies clarified (ephemeral vs. persistent patterns)
- [x] CDK8s chart property interfaces defined (KubeVirtChart, NixOsVmChart, NixOsDataVolumeChart)
- [x] Resource constraints and cluster requirements documented
- [x] Default values specified per FR-028 (2 CPU, 4GB RAM)

**Status**: ✅ Data Model Complete - Ready for API Contracts
