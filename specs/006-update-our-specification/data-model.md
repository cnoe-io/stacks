# Data Model: RustDesk Base Image Integration

**Feature**: 006-update-our-specification
**Date**: 2025-10-14

## Overview

This document defines the key entities, their attributes, relationships, and state transitions for the RustDesk base image integration feature. Since this is an infrastructure feature (not a data-driven application), entities represent configuration artifacts and runtime resources rather than database models.

## Entity Diagram

```
┌─────────────────────┐
│   NixOS Base Image  │
│   (Artifact)        │
└──────────┬──────────┘
           │ contains
           │
           ▼
    ┌──────────────────┐
    │ RustDesk Service │
    │  Configuration   │
    └──────────────────┘
           │ references
           │
           ▼
    ┌──────────────────────┐
    │ RustDesk Credentials │
    │   (Secret)           │
    └──────────────────────┘

┌─────────────────────┐         ┌────────────────────┐
│   DataVolume        │────────▶│   Base Image       │
│   (K8s Resource)    │  pulls  │   (Artifact)       │
└──────────┬──────────┘         └────────────────────┘
           │ provides disk to
           │
           ▼
    ┌────────────────┐
    │  VM Instance   │
    │ (KubeVirt VMI) │
    └────────────────┘
           │ runs
           │
           ▼
    ┌──────────────────┐
    │ RustDesk Service │
    │   (systemd)      │
    └──────────────────┘
```

## Entities

### 1. NixOS Base Image

**Description**: A pre-built operating system disk image containing the NixOS distribution with RustDesk service pre-configured. Built using Nix flakes and stored as a qcow2 file.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `imageURL` | URL string | Location of the qcow2 image file | Must be accessible from cluster (http/https) |
| `version` | Semantic version | Image version identifier (e.g., "v2.0.0") | Follows semver format |
| `buildHash` | SHA256 hash | Nix store path hash of the image | 32-character hex string |
| `rustdeskVersion` | Version string | RustDesk package version included | From nixpkgs (e.g., "1.2.3") |
| `headlessModeEnabled` | Boolean | Whether RustDesk headless mode is enabled | Must be `true` for this feature |
| `systemServiceEnabled` | Boolean | Whether RustDesk runs as system service | Must be `true` for this feature |
| `buildTimestamp` | ISO 8601 datetime | When the image was built | UTC timezone |
| `size` | Integer (bytes) | Compressed qcow2 file size | Typically 1-3 GB |

**Relationships**:
- **Contains**: RustDesk Service Configuration (1:1)
- **Referenced by**: DataVolume (1:N - one image, many VMs)
- **Stored in**: MinIO bucket or external registry (1:1)

**State Transitions**:
```
[Building] → [Built] → [Uploaded] → [Active]
                            ↓
                       [Deprecated] → [Archived]
```

**Validation Rules**:
- `imageURL` must return HTTP 200 on GET request
- `headlessModeEnabled` must be `true`
- `systemServiceEnabled` must be `true`
- Image must contain `/etc/systemd/system/rustdesk.service` file

---

### 2. RustDesk Service Configuration

**Description**: Declarative configuration for the RustDesk remote desktop service, defined in NixOS module syntax and baked into the base image.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `enable` | Boolean | Master enable switch for RustDesk | Must be `true` |
| `enableSystemService` | Boolean | Run as system service (vs. user service) | Must be `true` for headless |
| `enableDirectIpAccess` | Boolean | Enable port 21116 for direct connections | Recommended `true` |
| `user` | String | User account to run service as | Must be "root" for headless mode |
| `package` | Nix package | RustDesk package variant | Typically `pkgs.rustdesk-flutter` |
| `allowLinuxHeadless` | Boolean | Enable headless mode (no GUI) | Must be `true` |
| `firewallPorts` | Integer array | TCP ports to open in firewall | Must include `21116` |
| `glEnvironment` | String | OpenGL library override | Must be "LIBGL_ALWAYS_SOFTWARE=1" |

**Relationships**:
- **Contained in**: NixOS Base Image (1:1)
- **Uses**: RustDesk Package from nixpkgs (N:1)
- **Creates**: systemd service unit (1:1)

**Validation Rules**:
- If `enableSystemService = true`, then `user` must be "root"
- If `allowLinuxHeadless = true`, then `glEnvironment` must include LIBGL_ALWAYS_SOFTWARE
- `firewallPorts` must include 21116 if `enableDirectIpAccess = true`

**Example Configuration** (Nix syntax):
```nix
services.rustdesk = {
  enable = true;
  enableSystemService = true;
  enableDirectIpAccess = true;
  user = "root";
  package = pkgs.rustdesk-flutter;
};

systemd.services.rustdesk.environment = {
  LIBGL_ALWAYS_SOFTWARE = "1";
};

networking.firewall.allowedTCPPorts = [ 21116 ];
```

---

### 3. RustDesk Credentials

**Description**: Authentication credentials for connecting to RustDesk service. Includes permanent password and auto-generated connection ID.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `password` | String (secret) | Permanent password for RustDesk connections | Min 8 characters, stored in Azure Key Vault |
| `connectionId` | String | Auto-generated RustDesk ID (9-10 digits) | Generated on first RustDesk startup |
| `directConnectionPort` | Integer | Port for direct P2P connections | Default 21116 |
| `secretName` | String | Kubernetes Secret name | Must exist in VM namespace |
| `keyVaultKey` | String | Azure Key Vault secret name | Format: "RUSTDESK-PASSWORD" |

**Relationships**:
- **Referenced by**: RustDesk Service Configuration (N:1 - many VMs, one password)
- **Stored in**: Azure Key Vault (1:1)
- **Synced by**: External Secrets Operator (1:1)
- **Exposed to**: VM via environment variable or cloud-init (1:N)

**State Transitions**:
```
[In Key Vault] → [Synced to K8s Secret] → [Injected to VM] → [Active in RustDesk]
                       ↑
                  [Rotated] (triggers resync)
```

**Validation Rules**:
- `password` must be at least 8 characters
- `password` must not be hardcoded in code or manifests
- `keyVaultKey` must exist in Azure Key Vault
- `secretName` must exist before VM starts (sync wave -70)

**Security Requirements**:
- Password stored only in Azure Key Vault (single source of truth)
- Synced to Kubernetes Secret via ESO (ephemeral, cluster-scoped)
- Never logged or displayed in plain text
- Rotation triggers automatic Secret update (VMs must be recreated to pick up new password)

---

### 4. DataVolume

**Description**: Kubernetes custom resource (KubeVirt CDI) that provisions a persistent volume by importing a VM disk image from an external source.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `name` | String | DataVolume resource name | Must match `<vm-name>-rootdisk` |
| `namespace` | String | Kubernetes namespace | Typically "default" |
| `storageSize` | Quantity | Size of provisioned PVC | Must be ≥ base image size (e.g., "50Gi") |
| `storageClass` | String | Storage class for PVC | Cluster-specific (e.g., "standard") |
| `imageURL` | URL string | Source image URL | Must reference NixOS Base Image |
| `imageFormat` | String | Disk image format | Must be "qcow2" |
| `syncWave` | Integer | ArgoCD sync wave annotation | Recommended -100 (before VM) |

**Relationships**:
- **Pulls from**: NixOS Base Image (N:1 - many DataVolumes can reference same image)
- **Creates**: PersistentVolumeClaim (1:1)
- **Used by**: VM Instance (1:1 - DataVolume provides root disk to VM)

**State Transitions**:
```
[Pending] → [ImportScheduled] → [ImportInProgress] → [Succeeded]
                                         ↓
                                      [Failed] → [Retry]
```

**Validation Rules**:
- `storageSize` must be at least as large as the base image size
- `imageURL` must be accessible from cluster network
- `imageFormat` must match actual image file format
- DataVolume must succeed before VM can start (sync wave ordering)

**Example Manifest** (K8s YAML):
```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: nixos-dev-vm-rootdisk
  namespace: default
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
spec:
  source:
    http:
      url: http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 50Gi
```

---

### 5. VM Instance

**Description**: A running virtual machine managed by KubeVirt, booted from the DataVolume containing the NixOS base image with RustDesk pre-configured.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `name` | String | VM resource name | Must be unique in namespace |
| `namespace` | String | Kubernetes namespace | Typically "default" |
| `cpuCores` | Integer | Number of CPU cores allocated | Min 1, recommended 2+ |
| `memory` | Quantity | RAM allocated to VM | Min "2Gi", recommended "4Gi"+ |
| `rootDiskRef` | String | DataVolume name for root disk | Must reference existing DataVolume |
| `running` | Boolean | Desired running state | `true` to start, `false` to stop |
| `podIP` | IP address | Internal cluster IP of VM pod | Auto-assigned, accessible via Tailscale |
| `bootTimestamp` | ISO 8601 datetime | When VM last booted | Updated on each VM start |

**Relationships**:
- **Boots from**: DataVolume (N:1 - many VMs can boot from same base image if cloned)
- **Runs**: RustDesk Service (1:1)
- **Receives credentials from**: RustDesk Credentials Secret (N:1)
- **Accessible via**: Tailscale subnet routing (1:1)

**State Transitions**:
```
[Stopped] → [Starting] → [Running] → [Ready]
                             ↓          ↓
                         [Failed]   [Stopping] → [Stopped]
                             ↓
                         [Migrating] → [Running]
```

**Validation Rules**:
- `rootDiskRef` DataVolume must be in "Succeeded" state before VM starts
- `cpuCores` and `memory` must not exceed cluster capacity
- `running = true` requires DataVolume to be ready
- RustDesk service must start within 2 minutes of boot (success criteria SC-001)

**Success Indicators**:
- VMI shows "Running" phase
- RustDesk service is "active (running)" in systemd
- RustDesk connection ID is generated and accessible
- Direct connection on port 21116 is reachable

---

### 6. RustDesk Service (Runtime)

**Description**: The running RustDesk remote desktop service instance inside a VM, managed by systemd.

**Attributes**:

| Attribute | Type | Description | Validation |
|-----------|------|-------------|------------|
| `serviceStatus` | Enum | systemd service state | "active", "inactive", "failed" |
| `connectionId` | String | RustDesk connection ID (auto-generated) | 9-10 digit string |
| `directConnectionPort` | Integer | Port for direct connections | Must be 21116 |
| `headlessModeActive` | Boolean | Whether headless mode is enabled | Must be `true` |
| `configDirectory` | Path | RustDesk config location | `/root/.config/rustdesk/` |
| `startTime` | ISO 8601 datetime | When service last started | Within 2 min of VM boot |
| `processId` | Integer | PID of rustdesk process | Non-zero if running |

**Relationships**:
- **Runs in**: VM Instance (1:1)
- **Configured by**: RustDesk Service Configuration in base image (N:1)
- **Authenticated with**: RustDesk Credentials (N:1)

**State Transitions**:
```
[Inactive] → [Activating] → [Active] → [Running]
                                ↓          ↓
                            [Failed]   [Stopping] → [Inactive]
                                ↓
                           [Restarting] → [Active]
```

**Validation Rules**:
- Service must reach "active (running)" state within 2 minutes of VM boot
- `connectionId` must be generated and stored in `$configDirectory/RustDesk2.toml`
- Port 21116 must be listening (verified via `ss -tlnp | grep 21116`)
- `headlessModeActive` must be true (verified via `allow-linux-headless = "Y"` in config)

**Diagnostic Queries**:
- Status check: `systemctl status rustdesk`
- Connection ID: `cat /root/.config/rustdesk/RustDesk2.toml | grep id`
- Headless mode: `cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless`
- Port listening: `ss -tlnp | grep 21116`
- Service logs: `journalctl -u rustdesk --since "5 min ago"`

---

## Entity Relationships Summary

```
NixOS Base Image (1) ──contains──> RustDesk Service Configuration (1)
                                            │
                                            └──references──> RustDesk Credentials (1)

DataVolume (1) ──pulls──> NixOS Base Image (1)
     │
     └──provides disk to──> VM Instance (1)
                                  │
                                  └──runs──> RustDesk Service (Runtime) (1)
                                                      │
                                                      └──uses──> RustDesk Credentials (1)
```

**Cardinality**:
- One base image → many DataVolumes (1:N)
- One DataVolume → one VM Instance (1:1)
- One VM Instance → one RustDesk Service Runtime (1:1)
- One RustDesk Credentials → many VM Instances (1:N)

**Data Flow**:
1. Build NixOS Base Image with RustDesk Service Configuration
2. Upload base image to MinIO
3. DataVolume imports image into PVC
4. VM Instance boots from DataVolume
5. RustDesk Service (Runtime) starts automatically on VM boot
6. RustDesk Service authenticates using credentials from Azure Key Vault (via ESO)

---

## Validation Rules Summary

### Cross-Entity Constraints

1. **Image Configuration Consistency**:
   - Base Image `headlessModeEnabled` ↔ RustDesk Service Configuration `allowLinuxHeadless` (must match)
   - Base Image `systemServiceEnabled` ↔ RustDesk Service Configuration `enableSystemService` (must match)

2. **Deployment Ordering** (ArgoCD sync waves):
   - RustDesk Credentials Secret: wave -70
   - DataVolume: wave -100
   - VM Instance: wave 0
   - (Ensures secrets and storage exist before VM starts)

3. **Resource Sizing**:
   - DataVolume `storageSize` ≥ Base Image `size`
   - VM Instance `memory` ≥ 2Gi (minimum for NixOS + RustDesk)
   - VM Instance `cpuCores` ≥ 1 (recommended 2 for responsive desktop)

4. **Security Constraints**:
   - RustDesk Credentials `password` MUST NOT appear in:
     - Git repository (code, manifests, documentation)
     - Kubernetes resource annotations or labels
     - Container logs or VM console output
   - Password MUST be stored only in:
     - Azure Key Vault (source of truth)
     - Kubernetes Secret (synced by ESO, ephemeral)

5. **Success Criteria Mappings**:
   - SC-001 (2-minute boot): VM `bootTimestamp` → RustDesk Service `startTime` < 2 min
   - SC-002 (99% success rate): RustDesk Service `serviceStatus` = "active" / total VM boots
   - SC-004 (30-second connection): RustDesk Service `startTime` → successful client connection < 30 sec

---

## State Machine: End-to-End VM Deployment

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Base Image Build                                      │
│ [Building Image] → [Image Built] → [Pushed to MinIO]           │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 2: Kubernetes Resource Creation                          │
│ [ArgoCD Sync] → [DataVolume Created] → [Secret Synced]         │
│                        ↓                       ↓                │
│                  [Importing Image]      [Password Available]   │
│                        ↓                                        │
│                  [Import Succeeded]                             │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3: VM Boot & RustDesk Startup                            │
│ [VM Starting] → [VM Running] → [RustDesk Starting]             │
│                                       ↓                         │
│                                 [RustDesk Active]               │
│                                       ↓                         │
│                                 [Connection ID Generated]       │
│                                       ↓                         │
│                              [Ready for Connections]            │
└─────────────────────────────────────────────────────────────────┘
```

**Total Time Budget** (from success criteria):
- Phase 1: Not time-constrained (one-time per image version, 3-5 min with cache)
- Phase 2: DataVolume import varies by image size (typically 2-5 min for 2GB image)
- Phase 3: Must complete within 2 minutes (SC-001 requirement)

---

## Next Steps

This data model provides the foundation for:
1. **Contracts** (Phase 1): Define APIs for NixOS module, CDK8s chart props, ESO specs
2. **Tasks** (Phase 2): Break down implementation into discrete steps (image build, chart updates, testing)
3. **Testing** (Phase 3): Validate entity states and relationships at each deployment phase
