# Data Model: NixOS Wayland/Sway VM

**Feature**: 007-number-7-short
**Date**: 2025-11-12
**Purpose**: Define entities, configuration structures, and state transitions for the Wayland/Sway VM migration

## Overview

This feature involves infrastructure-as-code changes, not application data models. The "entities" are configuration structures in TypeScript (CDK8s charts) and Nix (NixOS modules). This document defines:

1. **TypeScript Interfaces** - Chart props and helper function signatures
2. **Kubernetes Resources** - VirtualMachine, DataVolume, Service, Secret
3. **NixOS Configuration** - Declarative system configuration
4. **State Transitions** - VM lifecycle states

---

## 1. TypeScript Entities (CDK8s Charts)

### 1.1 NixOsVmChartProps Interface

**File**: `cdk8s/charts/apps/nixos-vm-chart.ts`

**Current State** (with RustDesk):
```typescript
export interface NixOsVmChartProps extends ChartProps {
  vmName?: string;
  dataVolumeName?: string;
  cpuCores?: number;
  memory?: string;
  cloudInitUserData?: string;
  targetNamespace?: string;
  enableTailscale?: boolean;
  tailscaleHostname?: string;
  runStrategy?: 'Always' | 'Manual' | 'RerunOnFailure' | 'Halted';
  enableGraphics?: boolean;
  tailscaleAuthKey?: string;
  rustdeskPassword?: string;              // ❌ REMOVE
  useExternalSecretsCloudInit?: boolean;
}
```

**Target State** (with WayVNC):
```typescript
export interface NixOsVmChartProps extends ChartProps {
  vmName?: string;
  dataVolumeName?: string;
  cpuCores?: number;
  memory?: string;
  cloudInitUserData?: string;
  targetNamespace?: string;
  enableTailscale?: boolean;
  tailscaleHostname?: string;
  runStrategy?: 'Always' | 'Manual' | 'RerunOnFailure' | 'Halted';
  enableGraphics?: boolean;
  tailscaleAuthKey?: string;
  wayvncPassword?: string;                // ✅ ADD (optional, for ExternalSecret reference)
  useExternalSecretsCloudInit?: boolean;
}
```

**Field Descriptions**:

| Field | Type | Required | Default | Purpose |
|-------|------|----------|---------|---------|
| `vmName` | string | No | `"nixos-dev-vm"` | VM resource name |
| `dataVolumeName` | string | No | `"nixos-dev-datavolume"` | DataVolume name (new image source) |
| `cpuCores` | number | No | `2` | CPU allocation |
| `memory` | string | No | `"4Gi"` | Memory allocation |
| `cloudInitUserData` | string | No | Generated | Custom cloud-init YAML |
| `targetNamespace` | string | No | `"default"` | Deployment namespace |
| `enableTailscale` | boolean | No | `false` | Tailscale LoadBalancer |
| `tailscaleHostname` | string | No | `"{vmName}-vnc"` | Tailscale hostname |
| `runStrategy` | enum | No | `"Always"` | VM lifecycle strategy |
| `enableGraphics` | boolean | No | `true` | VNC graphics device |
| `tailscaleAuthKey` | string | No | undefined | Tailscale auth key (ExternalSecret) |
| `wayvncPassword` | string | No | undefined | VNC password (ExternalSecret) |
| `useExternalSecretsCloudInit` | boolean | No | `false` | ExternalSecret-based cloud-init |

**Validation Rules**:
- `cpuCores` must be >= 1 and <= 8
- `memory` must match Kubernetes quantity format (e.g., "4Gi", "8192Mi")
- `runStrategy` must be one of: 'Always', 'Manual', 'RerunOnFailure', 'Halted'
- `tailscaleHostname` must be valid DNS hostname (lowercase, no spaces)

---

### 1.2 buildCloudInitUserData Function Signature

**File**: `cdk8s/lib/kubevirt-helpers.ts`

**Current Signature** (with RustDesk):
```typescript
export function buildCloudInitUserData(
  hostname: string,
  username: string,
  sshKeys?: string[],
  password?: string,
  installDesktop: boolean = false,
  enableTailscale: boolean = false,
  enableRustDesk: boolean = false,        // ❌ REMOVE
  tailscaleAuthKey?: string,
  rustdeskPassword?: string               // ❌ REMOVE
): string
```

**Target Signature** (without RustDesk):
```typescript
export function buildCloudInitUserData(
  hostname: string,
  username: string,
  sshKeys?: string[],
  password?: string,
  installDesktop: boolean = false,
  enableTailscale: boolean = false,
  tailscaleAuthKey?: string
): string
```

**Simplified Logic**:
- Remove RustDesk installation commands (~240 lines)
- Remove X11/RDP configuration
- Keep Tailscale auto-authentication
- Keep user/SSH key configuration
- Keep hostname and password setup

**Return Value**: Cloud-init YAML string (RFC-822 format, starts with `#cloud-config`)

---

## 2. Kubernetes Resource Entities

### 2.1 VirtualMachine Resource

**API Version**: `kubevirt.io/v1`
**Kind**: `VirtualMachine`
**Namespace**: `default`

**Metadata**:
```yaml
metadata:
  name: nixos-dev-vm
  namespace: default
  labels:
    app.kubernetes.io/name: nixos-dev-vm
    app.kubernetes.io/component: virtual-machine
    kubevirt.io/vm: nixos-dev-vm
  annotations:
    argocd.argoproj.io/sync-wave: "10"
```

**Spec Structure**:
```yaml
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/vm: nixos-dev-vm
    spec:
      domain:
        cpu:
          cores: 2
        memory:
          guest: 4Gi
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
              ports:
                - name: ssh
                  protocol: TCP
                  port: 22
                - name: vnc
                  protocol: TCP
                  port: 5900           # ✅ CHANGED: Only VNC port (no RDP 3389, no RustDesk 21116)
          graphics:
            - type: vnc              # Required for VNC access
              listenAddress: 0.0.0.0
        resources:
          requests:
            memory: 4Gi
            cpu: 2
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: hetzner-sway-disk  # ✅ CHANGED: New DataVolume with Wayland/Sway image
        - name: cloudinitdisk
          cloudInitNoCloud:
            secretRef:
              name: nixos-dev-vm-cloudinit
```

**Key Changes**:
1. **Ports**: Remove RDP (3389) and RustDesk (21116), keep only SSH (22) and VNC (5900)
2. **RootDisk Volume**: Change DataVolume name from old X11 image to new Wayland/Sway image
3. **Cloud-init**: Simplified (no RustDesk configuration)

---

### 2.2 DataVolume Resource

**API Version**: `cdi.kubevirt.io/v1beta1`
**Kind**: `DataVolume`
**Namespace**: `default`

**Metadata**:
```yaml
metadata:
  name: hetzner-sway-disk
  namespace: default
  labels:
    app.kubernetes.io/name: nixos-dev-vm
  annotations:
    argocd.argoproj.io/sync-wave: "5"
```

**Spec Structure**:
```yaml
spec:
  source:
    http:
      url: http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 50Gi
    storageClassName: local-path
```

**Source Options**:

| Source Type | URL Format | Use Case |
|-------------|------------|----------|
| HTTP (MinIO) | `http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2` | Production (persistent storage) |
| HTTP (Python) | `http://192.168.1.100:8000/nixos.qcow2` | Development (temporary testing) |

**Import Lifecycle**:
1. CDI creates importer pod (`importer-hetzner-sway-disk-xxxxx`)
2. Downloads QCOW2 from HTTP source
3. Converts to raw format and writes to PVC
4. Importer pod completes, PVC becomes Bound
5. VM can use PVC as rootdisk

**State Transitions**:
```
Pending → WaitForFirstConsumer → ImportScheduled → ImportInProgress → Succeeded → Bound
```

---

### 2.3 Service Resource

**API Version**: `v1`
**Kind**: `Service`
**Namespace**: `default`

**Current Metadata** (with RustDesk):
```yaml
metadata:
  name: nixos-dev-vm-rdp
  namespace: default
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: nixos-dev-vm-rdp
    tailscale.com/tags: tag:k8s
    argocd.argoproj.io/sync-wave: "15"
```

**Target Metadata** (with WayVNC):
```yaml
metadata:
  name: nixos-dev-vm-vnc        # ✅ CHANGED: Rename from -rdp to -vnc
  namespace: default
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: nixos-dev-vm-vnc
    tailscale.com/tags: tag:k8s
    argocd.argoproj.io/sync-wave: "15"
```

**Current Spec** (with RustDesk):
```yaml
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  selector:
    kubevirt.io/vm: nixos-dev-vm
  ports:
    - name: ssh
      protocol: TCP
      port: 22
      targetPort: 22
    - name: rdp
      protocol: TCP
      port: 3389
      targetPort: 3389
    - name: rustdesk
      protocol: TCP
      port: 21116
      targetPort: 21116
```

**Target Spec** (with WayVNC):
```yaml
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  selector:
    kubevirt.io/vm: nixos-dev-vm
  ports:
    - name: ssh
      protocol: TCP
      port: 22
      targetPort: 22
    - name: vnc
      protocol: TCP
      port: 5900
      targetPort: 5900
```

**Tailscale LoadBalancer Behavior**:
1. Tailscale Operator creates tailscale-sts-{svc-name} StatefulSet
2. StatefulSet pod joins Tailscale network with hostname `nixos-dev-vm-vnc`
3. Tailscale DNS provides MagicDNS name: `nixos-dev-vm-vnc.tail286401.ts.net`
4. Service LoadBalancer IP becomes Tailscale IP (100.x.x.x)
5. Traffic routes: Client → Tailscale → LoadBalancer IP → VM pod → WayVNC (port 5900)

---

### 2.4 Secret Resource (Cloud-Init)

**API Version**: `v1`
**Kind**: `Secret`
**Namespace**: `default`

**Metadata**:
```yaml
metadata:
  name: nixos-dev-vm-cloudinit
  namespace: default
  annotations:
    argocd.argoproj.io/sync-wave: "5"
```

**Data Structure**:
```yaml
type: Opaque
stringData:
  userdata: |
    #cloud-config
    hostname: nixos-dev-vm
    users:
      - name: vpittamp
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYPmr7VOVazmcseVIUsqiXIcPBwzownP4ejkOuNg+o7
    chpasswd:
      list: |
        vpittamp:nixos123
        root:nixos123
      expire: false
    runcmd:
      # Tailscale auto-authentication (if enabled)
      - systemctl enable tailscaled
      - systemctl start tailscaled
      - tailscale up --authkey ${TAILSCALE_AUTH_KEY} --hostname nixos-dev-vm
```

**Key Changes**:
- Remove RustDesk installation (~240 lines)
- Remove X11/RDP configuration
- Remove desktop environment installation (already in base image)
- Keep minimal cloud-init for hostname, users, SSH keys, Tailscale

---

## 3. NixOS Configuration Entities

### 3.1 hetzner-sway.nix Configuration

**File**: `/etc/nixos/configurations/hetzner-sway.nix`
**Status**: Read-only input (already complete)

**Key Modules Imported**:
```nix
imports = [
  ./base.nix
  ../disk-config.nix
  ../modules/desktop/sway.nix           # Sway compositor
  ../modules/desktop/wayvnc.nix         # WayVNC server
  ../modules/services/tailscale.nix     # Tailscale VPN
];
```

**Critical Configuration**:
```nix
# Headless Wayland environment
environment.sessionVariables = {
  WLR_BACKENDS = "headless";
  WLR_HEADLESS_OUTPUTS = "3";
  WLR_LIBINPUT_NO_DEVICES = "1";
  WLR_RENDERER = "pixman";
  WLR_NO_HARDWARE_CURSORS = "1";
  XDG_SESSION_TYPE = "wayland";
  XDG_CURRENT_DESKTOP = "sway";
  QT_QPA_PLATFORM = "wayland";
  GDK_BACKEND = "wayland";
  GSK_RENDERER = "cairo";
};

# WayVNC service
services.wayvnc = {
  enable = true;
  port = 5900;
  address = "0.0.0.0";
  enableAuth = true;
  enablePAM = true;
};

# Greetd auto-login
services.greetd = {
  enable = true;
  settings = {
    default_session = {
      command = "${pkgs.writeShellScript "sway-with-env" ''
        export WLR_BACKENDS=headless
        export WLR_HEADLESS_OUTPUTS=3
        export WLR_LIBINPUT_NO_DEVICES=1
        export WLR_RENDERER=pixman
        export XDG_SESSION_TYPE=wayland
        export XDG_CURRENT_DESKTOP=sway
        exec ${pkgs.sway}/bin/sway
      ''}";
      user = "vpittamp";
    };
  };
};

# Firewall
networking.firewall = {
  allowedTCPPorts = [ 22 5900 8080 ];
  interfaces."tailscale0".allowedTCPPorts = [ 5900 5901 5902 ];
};
```

**Packages** (relevant to feature):
```nix
environment.systemPackages = with pkgs; [
  wl-clipboard      # Clipboard utilities
  wlr-randr         # Output management
  wayvnc            # VNC server CLI
  dotool            # Keyboard/mouse automation
  ghostty           # Terminal emulator
  tailscale         # Zero-config VPN
];
```

---

### 3.2 NixOS Image Build Configuration

**Flake Output Definition**:
```nix
# Add to /etc/nixos/flake.nix
outputs = { self, nixpkgs, nixos-generators, ... }@inputs: {
  packages.x86_64-linux.hetzner-sway-qcow2 = nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    modules = [
      ./configurations/hetzner-sway.nix
      {
        virtualisation.diskSize = 50 * 1024;  # 50GB in MB
        imports = [ "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];
      }
    ];
    format = "qcow2";
  };
};
```

**Build Attributes**:
- **System**: x86_64-linux (AMD64)
- **Format**: QCOW2 (compressed disk image)
- **Disk Size**: 50GB (virtual), ~7GB (physical after build)
- **Boot Loader**: GRUB (EFI + legacy BIOS)
- **Kernel Modules**: virtio_pci, virtio_scsi, ahci, xhci_pci

---

## 4. State Transitions

### 4.1 VirtualMachine Lifecycle States

```
┌─────────────┐
│   Stopped   │
└──────┬──────┘
       │ runStrategy: Always
       ▼
┌─────────────┐
│  Starting   │ ← VirtualMachineInstance created
└──────┬──────┘
       │ Pod scheduled
       ▼
┌─────────────┐
│ Scheduling  │ ← virt-launcher pod created
└──────┬──────┘
       │ Pod Running
       ▼
┌─────────────┐
│   Running   │ ← Guest OS booted, VMI.Status.Phase = "Running"
└──────┬──────┘
       │ Stop request or runStrategy: Halted
       ▼
┌─────────────┐
│  Stopping   │ ← Graceful shutdown
└──────┬──────┘
       │ Pod terminated
       ▼
┌─────────────┐
│   Stopped   │
└─────────────┘
```

**Key States**:

| State | Description | Conditions |
|-------|-------------|------------|
| Stopped | VM definition exists, no VMI | runStrategy: Halted or Manual |
| Starting | VMI created, waiting for pod | Pod phase: Pending |
| Scheduling | virt-launcher pod created | Pod phase: ContainerCreating |
| Running | Guest OS booted, services active | VMI phase: Running, Ready: True |
| Stopping | Graceful shutdown in progress | VMI phase: Succeeded, Pod terminating |

**Health Checks**:
- **VMI Ready**: Guest agent connected (qemu-guest-agent)
- **Sway Running**: greetd started Sway compositor
- **WayVNC Active**: Port 5900 accepting connections
- **Tailscale Connected**: LoadBalancer IP assigned

---

### 4.2 DataVolume Import States

```
┌──────────────┐
│   Pending    │
└──────┬───────┘
       │ PVC created
       ▼
┌──────────────┐
│ ImportScheduled │ ← Importer pod created
└──────┬───────┘
       │ Pod Running
       ▼
┌──────────────┐
│ ImportInProgress │ ← Downloading from HTTP source
└──────┬───────┘
       │ Download complete
       ▼
┌──────────────┐
│  Succeeded   │ ← Conversion complete, PVC Bound
└──────┬───────┘
       │ VM attaches volume
       ▼
┌──────────────┐
│   In Use     │ ← VirtualMachine using PVC
└──────────────┘
```

**Key Conditions**:

| Condition | Status | Reason | Description |
|-----------|--------|--------|-------------|
| Bound | False | WaitForFirstConsumer | PVC waiting for pod to claim |
| Running | True | ImportScheduled | Importer pod scheduled |
| Running | True | ImportInProgress | Downloading and converting |
| Ready | True | Succeeded | PVC ready for use |
| Bound | True | InUse | VM using PVC |

---

### 4.3 Service LoadBalancer States

```
┌───────────────┐
│    Pending    │
└───────┬───────┘
        │ Tailscale Operator reconciles
        ▼
┌───────────────┐
│ Provisioning  │ ← tailscale-sts-{svc} StatefulSet created
└───────┬───────┘
        │ StatefulSet pod joins Tailscale
        ▼
┌───────────────┐
│    Ready      │ ← LoadBalancer.Ingress[0].IP = Tailscale IP
└───────┬───────┘
        │ Traffic routing active
        ▼
┌───────────────┐
│    Active     │ ← Clients can connect via MagicDNS
└───────────────┘
```

**Key Events**:
1. Service created with `tailscale.com/expose: "true"` annotation
2. Tailscale Operator creates StatefulSet with proxy pod
3. Proxy pod authenticates to Tailscale network
4. LoadBalancer status updated with Tailscale IP
5. MagicDNS hostname active (e.g., `nixos-dev-vm-vnc.tail286401.ts.net`)

---

## 5. Configuration Contracts

### 5.1 Cloud-Init Contract

**Format**: RFC-822 YAML (starts with `#cloud-config`)
**Size Limit**: 2048 bytes inline, unlimited via Secret reference
**Encoding**: UTF-8 plain text (no base64 encoding in Secret)

**Required Fields**:
```yaml
#cloud-config
hostname: <string>        # VM hostname (must match VirtualMachine name)
users:                    # At least one user
  - name: <string>
    sudo: <string>
    shell: <string>
    ssh_authorized_keys:
      - <string>          # SSH public key (ed25519 or RSA)
chpasswd:                 # Password configuration
  list: |
    <username>:<password>
  expire: false
```

**Optional Fields**:
```yaml
runcmd:                   # Post-boot commands
  - <command>
packages:                 # Additional packages (if supported)
  - <package>
write_files:              # File creation
  - path: <path>
    content: <content>
    permissions: <mode>
```

---

### 5.2 Tailscale Annotation Contract

**Required Annotations**:
```yaml
tailscale.com/expose: "true"
tailscale.com/hostname: <hostname>
tailscale.com/tags: tag:k8s
```

**Optional Annotations**:
```yaml
tailscale.com/tailnet: <tailnet>                    # Custom tailnet (default: from operator config)
tailscale.com/funnel: "true"                        # Enable Tailscale Funnel (public HTTPS)
tailscale.com/serve-config: <serve-config-json>     # Tailscale Serve configuration
```

**Validation Rules**:
- `hostname` must be valid DNS label (lowercase, alphanumeric, hyphens)
- `tags` must start with `tag:` prefix
- `expose` must be `"true"` (string, not boolean)

---

## 6. Validation Rules

### 6.1 Chart Props Validation

```typescript
// In NixOsVmChart constructor
if (cpuCores < 1 || cpuCores > 8) {
  throw new Error('cpuCores must be between 1 and 8');
}

if (!memory.match(/^\d+(Mi|Gi|M|G)$/)) {
  throw new Error('memory must be valid Kubernetes quantity (e.g., "4Gi")');
}

if (tailscaleHostname && !tailscaleHostname.match(/^[a-z0-9-]+$/)) {
  throw new Error('tailscaleHostname must be lowercase alphanumeric with hyphens');
}

if (!['Always', 'Manual', 'RerunOnFailure', 'Halted'].includes(runStrategy)) {
  throw new Error('runStrategy must be one of: Always, Manual, RerunOnFailure, Halted');
}
```

---

### 6.2 Resource Validation

**DataVolume**:
- URL must be valid HTTP/HTTPS URL
- Storage size must be >= image size (50Gi recommended for 50GB image)
- StorageClass must exist in cluster

**VirtualMachine**:
- CPU cores must be positive integer
- Memory must be valid Kubernetes quantity
- All volume names must match volumes[] array entries
- All interface names must match networks[] array entries

**Service**:
- Port numbers must be 1-65535
- Tailscale hostname must be unique across tailnet
- LoadBalancerClass must be "tailscale" when using Tailscale annotations

---

## 7. Summary of Entity Changes

| Entity | Current State | Target State | Change Type |
|--------|---------------|--------------|-------------|
| `NixOsVmChartProps` | Has `rustdeskPassword` | Has `wayvncPassword` | Replace property |
| `buildCloudInitUserData` | 7 parameters (incl. RustDesk) | 5 parameters (no RustDesk) | Remove 2 parameters |
| `VirtualMachine.spec.template.spec.domain.devices.interfaces[0].ports` | 3 ports (SSH, RDP, RustDesk) | 2 ports (SSH, VNC) | Remove 2 ports |
| `DataVolume.spec.source.http.url` | Old X11 image URL | New Wayland/Sway image URL | Update URL |
| `Service.metadata.name` | `nixos-dev-vm-rdp` | `nixos-dev-vm-vnc` | Rename service |
| `Service.spec.ports` | 3 ports (SSH, RDP, RustDesk) | 2 ports (SSH, VNC) | Remove 2 ports |
| `Secret.stringData.userdata` | ~800 lines (with RustDesk) | ~80 lines (without RustDesk) | Simplify cloud-init |

**Total Code Removals**: ~600 lines (RustDesk configuration in `buildCloudInitUserData`)
**Total Code Additions**: ~50 lines (WayVNC port configuration, chart prop updates)
**Net Change**: -550 lines (significant simplification)

---

## References

- **KubeVirt VirtualMachine API**: https://kubevirt.io/api-reference/v1.0.0/definitions.html#_v1_virtualmachine
- **CDI DataVolume API**: https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md
- **Cloud-Init Format**: https://cloudinit.readthedocs.io/en/latest/reference/examples.html
- **Tailscale Kubernetes Operator**: https://tailscale.com/kb/1185/kubernetes
- **CDK8s Chart API**: https://cdk8s.io/docs/latest/basics/chart/
