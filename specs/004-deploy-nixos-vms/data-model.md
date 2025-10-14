# Data Model: Deploy NixOS VMs using KubeVirt

**Feature**: 004-deploy-nixos-vms
**Date**: 2025-10-11
**Purpose**: Define domain entities, their attributes, relationships, and state transitions

## Overview

This feature involves infrastructure resources (Kubernetes manifests, NixOS configurations, VM instances) rather than traditional application data models. The "data" in this context refers to:

1. **Kubernetes Resources**: CDK8s-generated manifests representing desired state
2. **VM State**: Runtime state of VirtualMachine and VirtualMachineInstance resources
3. **Configuration Data**: NixOS system configuration, cloud-init user data
4. **Image Artifacts**: qcow2 disk images, Docker containers

## Domain Entities

### Entity 1: NixOS Image

**Description**: Bootable qcow2 disk image containing minimal NixOS system with SSH, cloud-init, and virtio drivers.

**Attributes**:
- `filePath`: string - Path to qcow2 file (e.g., `/tmp/kubevirt-base-image/nixos.qcow2`)
- `format`: string - Disk format (always `qcow2`)
- `sizeBytes`: number - Compressed image size (~1.7GB)
- `generatorFormat`: string - nixos-generators format used (`kubevirt`)
- `configPath`: string - NixOS configuration file path (`/etc/nixos/configurations/kubevirt-minimal.nix`)
- `hasGrub`: boolean - GRUB bootloader installed (true for kubevirt format)
- `hasCloudInit`: boolean - Cloud-init service enabled (true for kubevirt format)
- `buildCommand`: string - Command to rebuild image

**Relationships**:
- Built FROM: NixOS Configuration (kubevirt-minimal.nix)
- Packaged INTO: Docker Image (nginx container)
- Imported BY: DataVolume (HTTP source)

**Lifecycle**:
```
[Source Config] --(nixos-generate)--> [qcow2 File] --(docker build)--> [Docker Image] --(docker push)--> [Docker Hub]
```

**Validation Rules**:
- File must exist and be readable qcow2 format
- Size must be <5GB (preferably <2GB for fast transfers)
- Must contain GRUB bootloader on /dev/vda
- Must have cloud-init.service enabled in systemd

### Entity 2: Docker Image (Image Server Container)

**Description**: Container image packaging nginx + qcow2 file for in-cluster HTTP distribution.

**Attributes**:
- `repository`: string - Docker Hub repository (e.g., `vpittamp23/nixos-kubevirt-minimal`)
- `tag`: string - Image tag (e.g., `latest`, `v1.0.0`)
- `digest`: string - Content-addressable SHA256 digest
- `sizeBytes`: number - Total image size (~1.8GB including nginx + qcow2)
- `qcow2Path`: string - Path to qcow2 inside container (`/usr/share/nginx/html/nixos.qcow2`)
- `nginxPort`: number - HTTP port (80)

**Relationships**:
- Contains: NixOS Image (qcow2 file)
- Deployed AS: Image Server Deployment (NixOsImageServerChart)
- Serves TO: DataVolume imports via HTTP

**Lifecycle**:
```
[Local qcow2] --(Dockerfile)--> [Docker Image] --(push)--> [Docker Hub] --(pull)--> [Kubernetes Pod]
```

**Validation Rules**:
- Image must exist in registry and be pullable
- qcow2 file must exist at /usr/share/nginx/html/nixos.qcow2
- nginx must be configured to serve static files
- Container must listen on port 80

### Entity 3: Image Server Deployment

**Description**: Kubernetes Deployment resource running nginx containers serving qcow2 images via HTTP.

**Attributes**:
- `name`: string - Deployment name (`nixos-image-server`)
- `namespace`: string - Kubernetes namespace (`default`)
- `image`: string - Docker image reference (`vpittamp23/nixos-kubevirt-minimal:latest`)
- `replicas`: number - Number of pods (default: 1)
- `cpuRequest`: string - CPU request (`100m`)
- `cpuLimit`: string - CPU limit (`200m`)
- `memoryRequest`: string - Memory request (`128Mi`)
- `memoryLimit`: string - Memory limit (`2Gi`)
- `syncWave`: string - ArgoCD sync wave (`-50`)

**Relationships**:
- Deploys: Docker Image (nginx + qcow2)
- Exposed BY: Image Server Service (ClusterIP on port 80)
- Referenced BY: DataVolume HTTP source URLs

**Lifecycle**:
```
[CDK8s Synthesis] --> [Deployment Manifest] --> [ArgoCD Application] --> [Running Pods] --> [HTTP Availability]
```

**State Transitions**:
- **Pending**: Waiting for image pull
- **Running**: Pod(s) running and serving HTTP traffic
- **Failed**: Image pull failure or pod crash loop

**Validation Rules**:
- Must have at least 1 replica
- Image must be pullable from registry
- Memory limit must be >= image size + buffer (2Gi for 1.7GB image)
- Sync wave must be negative (deployed before DataVolumes)

### Entity 4: Image Server Service

**Description**: Kubernetes Service exposing image server pods via ClusterIP for in-cluster HTTP access.

**Attributes**:
- `name`: string - Service name (`nixos-image-server`)
- `namespace`: string - Kubernetes namespace (`default`)
- `type`: string - Service type (`ClusterIP`)
- `port`: number - Service port (80)
- `targetPort`: number - Container port (80)
- `selector`: map<string,string> - Pod selector labels (`app: nixos-image-server`)
- `clusterIP`: string - Assigned ClusterIP (auto-assigned)
- `dnsName`: string - Service DNS name (`nixos-image-server.default.svc.cluster.local`)

**Relationships**:
- Routes TO: Image Server Deployment pods
- Referenced BY: DataVolume HTTP source URLs

**Lifecycle**:
```
[Service Manifest] --> [Kubernetes API] --> [Endpoints Ready] --> [DNS Resolvable]
```

**Validation Rules**:
- Must exist before DataVolume import attempts
- Must have ready endpoints (at least 1 pod)
- DNS name must resolve to ClusterIP
- Port 80 must be accessible from other pods

### Entity 5: DataVolume

**Description**: CDI (Containerized Data Importer) resource that imports qcow2 image from HTTP source into PersistentVolumeClaim.

**Attributes**:
- `name`: string - DataVolume name (e.g., `nixos-dev-datavolume`)
- `namespace`: string - Kubernetes namespace (`default`)
- `sourceType`: string - Import source type (`http`)
- `sourceUrl`: string - HTTP URL to qcow2 (`http://nixos-image-server.default.svc.cluster.local/nixos.qcow2`)
- `storageSize`: string - PVC size (`20Gi`)
- `storageClassName`: string - StorageClass name (cluster default or explicit)
- `accessMode`: string - PVC access mode (`ReadWriteOnce`)
- `syncWave`: string - ArgoCD sync wave (default: `0`)

**Relationships**:
- Imports FROM: Image Server Service (HTTP URL)
- Creates: PersistentVolumeClaim (underlying storage)
- Referenced BY: VirtualMachine volumes

**Lifecycle**:
```
[DataVolume Created] --> [PVC Provisioned] --> [Image Importing] --> [Import Complete] --> [PVC Bound]
```

**State Transitions**:
1. **Pending**: DataVolume created, waiting for PVC provisioning
2. **ImportScheduled**: CDI importer pod scheduled
3. **ImportInProgress**: Downloading qcow2 from HTTP source
4. **Succeeded**: Import complete, PVC bound and ready
5. **Failed**: Import failure (HTTP error, storage error, timeout)

**Validation Rules**:
- sourceUrl must be reachable and return valid qcow2
- storageSize must be >= 2x compressed image size (for expansion + buffer)
- StorageClass must support ReadWriteOnce and dynamic provisioning
- Import must complete within 20 minutes (CDI default timeout)

### Entity 6: PersistentVolumeClaim (PVC)

**Description**: Kubernetes storage claim created by DataVolume, containing imported qcow2 disk image.

**Attributes**:
- `name`: string - PVC name (auto-generated by CDI, e.g., `nixos-dev-datavolume`)
- `namespace`: string - Kubernetes namespace (`default`)
- `storageSize`: string - Requested size (`20Gi`)
- `storageClassName`: string - StorageClass used
- `accessMode`: string - Access mode (`ReadWriteOnce`)
- `phase`: string - PVC phase (`Pending`, `Bound`)
- `volumeName`: string - Bound PersistentVolume name

**Relationships**:
- Created BY: DataVolume (CDI controller)
- Backed BY: PersistentVolume (provisioned by StorageClass)
- Mounted BY: VirtualMachine/VMI pod

**Lifecycle**:
```
[PVC Created] --> [PV Provisioned] --> [PVC Bound] --> [Mounted in Pod] --> [Released on Delete]
```

**Validation Rules**:
- Must be Bound before VirtualMachine can use it
- Must have sufficient capacity for qcow2 + filesystem overhead
- Must be in same namespace as VirtualMachine

### Entity 7: Cloud-init Secret

**Description**: Kubernetes Secret containing cloud-config YAML for VM initialization (users, SSH keys, hostname).

**Attributes**:
- `name`: string - Secret name (e.g., `nixos-dev-vm-cloudinit`)
- `namespace`: string - Kubernetes namespace (`default`)
- `userData`: string - cloud-config YAML content (base64 encoded)
- `syncWave`: string - ArgoCD sync wave (`5`, before VirtualMachine)

**Cloud-config Content**:
```yaml
#cloud-config
hostname: <vm-name>
users:
  - name: <username>
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - <ssh-public-key>
chpasswd:
  list: |
    <username>:<password>
    root:<password>
  expire: false
```

**Relationships**:
- Referenced BY: VirtualMachine (cloudInitNoCloud volume)
- Generated BY: buildCloudInitUserData helper function

**Lifecycle**:
```
[Cloud-config Template] --> [Secret Manifest] --> [Kubernetes API] --> [Referenced by VM] --> [Applied at Boot]
```

**Validation Rules**:
- Must be valid YAML cloud-config format
- userData must be <2048 bytes if inline (Secret avoids this limit)
- Must exist before VirtualMachine starts
- SSH keys must be valid public key format

### Entity 8: VirtualMachine

**Description**: KubeVirt resource defining desired state of a virtual machine (declarative VM configuration).

**Attributes**:
- `name`: string - VM name (e.g., `nixos-dev-vm`)
- `namespace`: string - Kubernetes namespace (`default`)
- `runStrategy`: string - Lifecycle policy (`Always`, `Manual`, `RerunOnFailure`, `Halted`)
- `cpuCores`: number - Number of CPU cores (default: 2)
- `cpuSockets`: number - Number of CPU sockets (default: 1)
- `memory`: string - Memory allocation (default: `4Gi`)
- `volumes`: array - Volume specifications (rootdisk, cloudinitdisk)
- `networks`: array - Network specifications (pod, bridge, masquerade)
- `enableGraphics`: boolean - VNC graphics device (default: true)
- `syncWave`: string - ArgoCD sync wave (`10`)

**Volume Specifications**:
```typescript
volumes: [
  {
    name: 'rootdisk',
    type: 'dataVolume',
    source: 'nixos-dev-datavolume', // DataVolume name
    bus: 'virtio'
  },
  {
    name: 'cloudinitdisk',
    type: 'cloudInit',
    cloudInitSecretName: 'nixos-dev-vm-cloudinit',
    bus: 'virtio'
  }
]
```

**Network Specifications**:
```typescript
networks: [
  {
    name: 'default',
    type: 'pod',
    interfaceType: 'masquerade',
    ports: [
      { name: 'ssh', protocol: 'TCP', port: 22 },
      { name: 'rdp', protocol: 'TCP', port: 3389 }
    ]
  }
]
```

**Relationships**:
- References: DataVolume (rootdisk volume)
- References: Cloud-init Secret (cloudinitdisk volume)
- Creates: VirtualMachineInstance (running instance)
- Exposed BY: Service (SSH/RDP access)

**Lifecycle**:
```
[VM Created] --> [VMI Scheduled] --> [Pod Created] --> [VM Booting] --> [VM Running] --> [VM Stopped/Deleted]
```

**State Transitions** (`.status.printableStatus`):
1. **Stopped**: VM exists but not running (runStrategy: Manual/Halted)
2. **Starting**: VMI being created and scheduled
3. **Running**: VMI running, guest OS booted
4. **Paused**: VM paused (virtctl pause)
5. **Stopping**: Graceful shutdown in progress
6. **Terminating**: Force shutdown in progress
7. **CrashLoopBackOff**: VM repeatedly failing to start
8. **Unknown**: Unable to determine state

**Validation Rules**:
- DataVolume must exist and be ready (PVC Bound)
- Cloud-init Secret must exist
- cpuCores and memory must be within cluster resource limits
- runStrategy must be valid value
- volumes must include at least one bootable disk

### Entity 9: VirtualMachineInstance (VMI)

**Description**: KubeVirt resource representing running instance of a virtual machine (created by VirtualMachine controller).

**Attributes**:
- `name`: string - VMI name (matches VirtualMachine name)
- `namespace`: string - Kubernetes namespace
- `nodeName`: string - Kubernetes node running the VM
- `phase`: string - VMI phase (`Pending`, `Scheduling`, `Scheduled`, `Running`, `Succeeded`, `Failed`)
- `ipAddress`: string - VM's pod IP address
- `vncPort`: number - VNC server port (if graphics enabled)
- `interfaces`: array - Network interface status

**Relationships**:
- Created BY: VirtualMachine controller
- Runs IN: virt-launcher pod (created by KubeVirt)
- Accessible VIA: Service (SSH/RDP), virtctl (console)

**Lifecycle**:
```
[VM runStrategy=Always] --> [VMI Created] --> [virt-launcher Pod] --> [QEMU Process] --> [Guest OS Boot] --> [Running]
```

**State Transitions**:
1. **Pending**: VMI created, waiting for scheduling
2. **Scheduling**: Finding suitable node
3. **Scheduled**: Node assigned, pod being created
4. **Running**: Guest OS running, services available
5. **Succeeded**: VM shut down cleanly (runStrategy: Manual)
6. **Failed**: VM failed to start or crashed

**Validation Rules**:
- VMI name must match parent VirtualMachine
- Must have pod IP address when Running
- virt-launcher pod must be Running
- Guest agent (qemu-guest-agent) should be running for better management

### Entity 10: VM Service

**Description**: Kubernetes Service exposing VirtualMachine SSH and RDP ports for external access.

**Attributes**:
- `name`: string - Service name (e.g., `nixos-dev-vm-rdp`)
- `namespace`: string - Kubernetes namespace (`default`)
- `type`: string - Service type (`NodePort`, `LoadBalancer`, `ClusterIP`)
- `selector`: map<string,string> - VMI selector (`kubevirt.io/vm: nixos-dev-vm`)
- `ports`: array - Port mappings (SSH 22, RDP 3389)
- `loadBalancerClass`: string - `tailscale` for Tailscale LoadBalancer (optional)
- `syncWave`: string - ArgoCD sync wave (`15`, after VM)

**Port Specifications**:
```typescript
ports: [
  { name: 'ssh', protocol: 'TCP', port: 22, targetPort: 22 },
  { name: 'rdp', protocol: 'TCP', port: 3389, targetPort: 3389 }
]
```

**Tailscale Annotations** (if `enableTailscale: true`):
```yaml
annotations:
  tailscale.com/expose: "true"
  tailscale.com/hostname: "nixos-dev-vm-rdp"
  tailscale.com/tags: "tag:k8s"
```

**Relationships**:
- Routes TO: VirtualMachineInstance pod (via selector)
- Optionally EXPOSED VIA: Tailscale LoadBalancer (for external access)

**Lifecycle**:
```
[Service Created] --> [Endpoints Created] --> [VMI IP Added] --> [Accessible via Service IP/Hostname]
```

**Validation Rules**:
- Must exist after VirtualMachine is Running
- Endpoints must include VMI pod IP
- Port 22 (SSH) and 3389 (RDP) must be accessible
- Tailscale hostname must be unique (if Tailscale enabled)

### Entity 11: NixOS Configuration

**Description**: Declarative NixOS system configuration defining minimal base image contents.

**Attributes**:
- `filePath`: string - Configuration file path (`/etc/nixos/configurations/kubevirt-minimal.nix`)
- `stateVersion`: string - NixOS release version (`24.11`)
- `bootLoader`: string - Boot loader type (`grub`, device `/dev/vda`)
- `networking.hostName`: string - Default hostname (`nixos-kubevirt`)
- `services.cloudInit.enable`: boolean - Cloud-init enabled (true)
- `services.openssh.enable`: boolean - SSH server enabled (true)
- `users`: array - Default user accounts
- `packages`: array - Installed system packages

**Key Settings**:
```nix
{
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
    timeout = 0;
  };

  services.cloud-init.enable = true;
  services.openssh.enable = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "http://attic.nix-cache.svc.cluster.local:8080/nixos"
      "https://cache.nixos.org"
    ];
  };
}
```

**Relationships**:
- Built BY: nixos-generators (--format kubevirt)
- Produces: NixOS Image (qcow2)
- Referenced BY: Build scripts

**Lifecycle**:
```
[Edit Config] --> [Commit to Git] --> [nixos-generate Build] --> [qcow2 Output]
```

**Validation Rules**:
- Must be valid Nix syntax
- Must include boot.loader configuration (GRUB for qcow2)
- Must enable cloud-init.service
- Must enable openssh.service
- system.stateVersion must be set

## Entity Relationship Diagram

```
┌─────────────────────────┐
│  NixOS Configuration    │
│  (kubevirt-minimal.nix) │
└──────────┬──────────────┘
           │ builds
           ↓
    ┌──────────────┐
    │ NixOS Image  │
    │ (qcow2)      │
    └──────┬───────┘
           │ packages
           ↓
   ┌────────────────────┐
   │  Docker Image      │
   │  (nginx + qcow2)   │
   └─────────┬──────────┘
             │ deploys
             ↓
   ┌─────────────────────────┐
   │  Image Server           │
   │  Deployment + Service   │
   └──────────┬──────────────┘
              │ serves HTTP
              ↓
       ┌──────────────┐          ┌────────────────────┐
       │  DataVolume  │          │ Cloud-init Secret  │
       │  (CDI)       │          │ (user config)      │
       └──────┬───────┘          └─────────┬──────────┘
              │ creates                    │
              ↓                            │
         ┌────────┐                        │
         │  PVC   │                        │
         └────┬───┘                        │
              │ mounts                     │ references
              ↓                            ↓
          ┌─────────────────────────────────────┐
          │      VirtualMachine                 │
          │   (rootdisk + cloudinitdisk)        │
          └───────────────┬─────────────────────┘
                          │ creates
                          ↓
              ┌────────────────────────┐
              │  VirtualMachineInstance│
              │  (running VM)          │
              └───────────┬────────────┘
                          │ exposes
                          ↓
                  ┌───────────────┐
                  │  VM Service   │
                  │  (SSH/RDP)    │
                  └───────────────┘
                          │ optional
                          ↓
                 ┌──────────────────┐
                 │ Tailscale        │
                 │ LoadBalancer     │
                 └──────────────────┘
```

## State Machine: VirtualMachine Lifecycle

```
                    ┌──────────────────┐
                    │  VM Created      │
                    │  (runStrategy)   │
                    └────────┬─────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
        Manual          Always           Halted
            │                │                │
            v                v                │
    ┌──────────┐     ┌──────────┐            │
    │ Stopped  │     │ Starting │            │
    └─────┬────┘     └─────┬────┘            │
          │                 │                 │
    virtctl start           │                 │
          │                 v                 │
          │          ┌──────────────┐         │
          └─────────>│   Running    │<────────┘
                     └──────┬───────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
     Failure            Stopped           Delete
          │                 │                 │
          v                 v                 v
  ┌───────────────┐   ┌──────────┐    ┌──────────────┐
  │CrashLoopBackOff│   │ Stopped  │    │ Terminating  │
  └───────────────┘   └──────────┘    └──────┬───────┘
          │                                    │
    RerunOnFailure                             │
          │                                    v
          └──────────> Starting           [Deleted]
```

**State Descriptions**:
- **Stopped**: VM defined but not running (runStrategy: Manual)
- **Starting**: VMI being created, pod scheduled, guest booting
- **Running**: Guest OS running, services available
- **CrashLoopBackOff**: Repeated boot failures, backoff delay
- **Terminating**: Graceful or forced shutdown in progress
- **Deleted**: VM resource removed from cluster

## Validation & Constraints

### Cross-Entity Validations

1. **DataVolume → VirtualMachine**: DataVolume must be ready before VM can start
   - DataVolume.status.phase == "Succeeded"
   - PVC.status.phase == "Bound"

2. **Cloud-init Secret → VirtualMachine**: Secret must exist before VM creation
   - Secret must exist in same namespace as VM
   - userData must be valid cloud-config YAML

3. **Image Server → DataVolume**: Image server must be running before DataVolume import
   - Image Server Service must have ready endpoints
   - HTTP URL must be reachable from CDI importer pod

4. **VirtualMachine → VM Service**: Service must select correct VMI pod
   - Service selector must match VM labels (`kubevirt.io/vm: <vm-name>`)
   - Service endpoints must include VMI pod IP when Running

### Resource Dependencies (Sync Waves)

```
Wave -50: Image Server Deployment + Service (infrastructure)
Wave 0:   DataVolume (image import)
Wave 5:   Cloud-init Secret (VM config)
Wave 10:  VirtualMachine (VM definition)
Wave 15:  VM Service (external access)
```

### Performance Constraints

| Entity | Constraint | Validation |
|--------|-----------|------------|
| NixOS Image | Build time <5 min | Measure nixos-generate duration |
| Docker Image | Push time <2 min | Measure docker push duration |
| Image Server | Pod ready <30 sec | Check Deployment readiness |
| DataVolume | Import time <3 min | Check DataVolume phase transition |
| VirtualMachine | Boot time <2 min | Check VMI Running + SSH accessible |
| VM Service | Ready time <30 sec | Check Service endpoints ready |

### Storage Constraints

| Entity | Size Constraint | Rationale |
|--------|----------------|-----------|
| NixOS Image (qcow2) | <2GB compressed | Fast network transfer |
| Docker Image | <2GB total | Registry limits, pull time |
| PVC (DataVolume) | >=20Gi | qcow2 expansion + desktop install buffer |
| Image Server Memory | 128Mi-2Gi | Image + nginx footprint |
| VM Memory | 4Gi default | Desktop environment requirement |

## CDK8s Chart Interfaces

### NixOsImageServerChart Props

```typescript
interface NixOsImageServerChartProps extends ChartProps {
  image?: string;           // Default: vpittamp23/nixos-kubevirt-minimal:latest
  replicas?: number;        // Default: 1
}
```

### NixOsDataVolumeChart Props

```typescript
interface NixOsDataVolumeChartProps extends ChartProps {
  dataVolumeName?: string;  // Default: nixos-dev-datavolume
  imageServerUrl?: string;  // Default: http://nixos-image-server.default.svc.cluster.local/nixos.qcow2
  storageSize?: string;     // Default: 20Gi
  storageClassName?: string; // Optional, uses cluster default
  targetNamespace?: string; // Default: default
}
```

### NixOsVmChart Props

```typescript
interface NixOsVmChartProps extends ChartProps {
  vmName?: string;              // Default: nixos-dev-vm
  dataVolumeName?: string;      // Default: nixos-dev-datavolume
  cpuCores?: number;            // Default: 2
  memory?: string;              // Default: 4Gi
  cloudInitUserData?: string;   // Optional, generates default if not provided
  targetNamespace?: string;     // Default: default
  enableTailscale?: boolean;    // Default: false
  tailscaleHostname?: string;   // Default: {vmName}-rdp
  runStrategy?: 'Always' | 'Manual' | 'RerunOnFailure' | 'Halted'; // Default: Always
  enableGraphics?: boolean;     // Default: true
}
```

## Summary

This data model defines 11 core entities across infrastructure layers:

**Build Layer** (3 entities):
- NixOS Configuration → NixOS Image → Docker Image

**Distribution Layer** (2 entities):
- Image Server Deployment → Image Server Service

**Storage Layer** (3 entities):
- DataVolume → PersistentVolumeClaim + Cloud-init Secret

**VM Layer** (3 entities):
- VirtualMachine → VirtualMachineInstance → VM Service

All entities follow declarative configuration principles, with clear lifecycles, state transitions, and validation rules. The model supports GitOps deployment via ArgoCD sync waves and CDK8s-based manifest generation.
