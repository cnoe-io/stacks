# Phase 0: Research & Technology Decisions

**Feature**: KubeVirt Installation with NixOS VM Images
**Date**: 2025-10-10

## Overview

This document resolves all "NEEDS CLARIFICATION" items from the Technical Context and provides research-backed decisions for technology choices, integration patterns, and implementation approaches.

## Research Questions

### Q1: NixOS Image Hosting Strategy

**Question**: How should NixOS qcow2 images be made accessible to Kubernetes DataVolumes for import?

**Options Evaluated**:

1. **HTTP Server (Simple file server)**
   - Pros: Straightforward, CDI has native HTTP source support, no special authentication
   - Cons: Requires external HTTP server (nginx, Python SimpleHTTPServer), manual file uploads
   - Use case: Local development, small number of images

2. **OCI Registry (Container registry)**
   - Pros: Reuses Gitea OCI registry (already deployed), versioning support, standardized artifact storage
   - Cons: Requires converting qcow2 to OCI artifact format, CDI registry source requires authentication
   - Use case: Production, automated builds, versioned VM images

3. **Local File Access (hostPath or PVC)**
   - Pros: Fastest for local development, no network transfer
   - Cons: Kind cluster limitations (limited hostPath support), not portable across nodes
   - Use case: Quick testing only

**Decision**: **HTTP Server for Phase 1, OCI Registry for Phase 2**

**Rationale**:
- HTTP server provides simplest integration for local Kind cluster development
- CDI DataVolume supports HTTP sources natively via `spec.source.http.url`
- Can use Python SimpleHTTPServer or nginx container in cluster
- Future migration to Gitea OCI registry enables versioned VM images and automated builds

**Implementation**:
```yaml
# DataVolume with HTTP source
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: nixos-dev-vm
spec:
  source:
    http:
      url: "http://nixos-image-server.default.svc.cluster.local/nixos-dev.qcow2"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 20Gi
```

**Phase 2 Migration** (OCI Registry):
- Use `oras push` to upload qcow2 as OCI artifact
- CDI DataVolume with registry source and imagePullSecrets
- Automated builds push to Gitea OCI registry

**References**:
- [CDI DataVolume HTTP Source](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md#https-source)
- [CDI Registry Source](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md#registry-source)

---

### Q2: KubeVirt Operator Deployment Method

**Question**: Should KubeVirt operator be deployed via CDK8s-generated manifests or Helm chart?

**Options Evaluated**:

1. **CDK8s with KubeVirt YAML manifests**
   - Pros: Aligns with Constitution Principle I (Type-Safe IaC), full control over operator configuration
   - Cons: Requires importing KubeVirt YAML, manual updates for new versions
   - Approach: Fetch operator YAML from KubeVirt releases, import to CDK8s chart

2. **Helm chart via CDK8s Helm integration**
   - Pros: Easier version updates, official KubeVirt Helm chart
   - Cons: Violates Constitution Principle I (prefer TypeScript over YAML templating), Helm is not CNOE-endorsed
   - Approach: Use cdk8s-cli to import Helm chart

3. **Operator via OLM (Operator Lifecycle Manager)**
   - Pros: Standardized operator management, automatic updates
   - Cons: Adds OLM dependency, overkill for local Kind cluster
   - Approach: Install OLM, then KubeVirt operator via OperatorGroup/Subscription

**Decision**: **CDK8s with KubeVirt YAML manifests**

**Rationale**:
- Aligns with Constitution Principle I: Type-Safe Infrastructure as Code (TypeScript over YAML templating)
- KubeVirt operator deployment is relatively stable (infrequent updates)
- Full control over KubeVirt CR configuration (software emulation, feature gates)
- Avoids Helm dependency (not CNOE-endorsed for new deployments)

**Implementation Approach**:
1. Download KubeVirt operator YAML from releases: `https://github.com/kubevirt/kubevirt/releases/download/v1.3.1/kubevirt-operator.yaml`
2. Import to CDK8s chart using `new k8s.KubeDeployment()`, `new k8s.KubeService()`, etc.
3. Create KubeVirt CR with `useEmulation: true` for Kind cluster
4. Register chart in `IdpBuilderChartFactory`

**Configuration**:
```typescript
// cdk8s/charts/infra/kubevirt-chart.ts
import { KubeVirt } from '../../imports/kubevirt.io';

new KubeVirt(this, 'kubevirt', {
  metadata: {
    name: 'kubevirt',
    namespace: 'kubevirt',
  },
  spec: {
    configuration: {
      developerConfiguration: {
        useEmulation: true, // Required for Kind (no KVM)
      },
    },
  },
});
```

**References**:
- [KubeVirt Installation](https://kubevirt.io/user-guide/operations/installation/)
- [KubeVirt Operator YAML](https://github.com/kubevirt/kubevirt/releases)

---

### Q3: CDI (Containerized Data Importer) Deployment

**Question**: Does CDI need to be deployed separately from KubeVirt, or is it bundled?

**Research Findings**:

- **CDI is a separate operator** from KubeVirt (developed under kubevirt org but independent)
- **KubeVirt does NOT bundle CDI** - must be installed separately
- **CDI provides DataVolume CRD** which is the recommended way to import VM images (higher-level than PVCs)

**Decision**: **Deploy CDI as separate ArgoCD Application**

**Rationale**:
- CDI is required for DataVolume-based image imports
- Separate deployment allows independent versioning and updates
- Follows package-based architecture (Principle VI)
- Enables sync wave ordering: CDI before DataVolumes

**Implementation**:
1. Create `cdk8s/charts/infra/cdi-chart.ts` for CDI operator
2. Download CDI operator YAML: `https://github.com/kubevirt/containerized-data-importer/releases/download/v1.59.0/cdi-operator.yaml`
3. Create CDI CR to configure storage, feature gates
4. Deploy via ArgoCD with sync wave -100 (same as KubeVirt)

**Sync Wave Ordering**:
- Sync wave `-100`: KubeVirt operator, CDI operator
- Sync wave `-90`: KubeVirt CR, CDI CR (wait for operators to be ready)
- Sync wave `0`: DataVolumes (wait for CDI to be ready)
- Sync wave `10`: VirtualMachines (wait for DataVolumes to import)

**References**:
- [CDI Installation](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/installation.md)
- [CDI DataVolumes](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)

---

### Q4: NixOS qcow2 Image Build Process

**Question**: What is the recommended process for building NixOS qcow2 images from NixOS/home-manager configurations?

**Options Evaluated**:

1. **nixos-generators**
   - Pros: Purpose-built for generating VM images from NixOS configs, supports qcow2 format
   - Cons: Additional tool dependency
   - Command: `nix run github:nix-community/nixos-generators -- --format qcow --configuration ./vm-config.nix`

2. **nixos-rebuild with VM target**
   - Pros: Built-in NixOS tool
   - Cons: Designed for local VM testing, not portable qcow2 images
   - Command: `nixos-rebuild build-vm --flake .#myvm`

3. **Custom NixOS configuration with image build**
   - Pros: Full control, integrates with existing NixOS configurations
   - Cons: More complex, requires understanding NixOS image generation internals
   - Approach: Define `system.build.qcow2` derivation in NixOS config

**Decision**: **nixos-generators for qcow2 image builds**

**Rationale**:
- Purpose-built for generating cloud/VM images from NixOS configurations
- Supports qcow2 format natively
- Integrates with existing NixOS configurations and home-manager
- Community-maintained with active development

**Implementation**:

```bash
# Build NixOS qcow2 image from existing flake configuration
cd /etc/nixos

# Option 1: Add vm-minimal to flake.nix nixosConfigurations
# Then build directly from flake
nixos-generate -f qcow -c vm-minimal -I nixpkgs=channel:nixos-unstable

# Option 2: Use standalone configuration file
cd /home/vpittamp/stacks
nix run github:nix-community/nixos-generators -- \
  --format qcow \
  --configuration /etc/nixos/configurations/vm-minimal.nix \
  --out-link ./nixos-images/kubevirt-vm.qcow2

# Option 3: Build from flake (if vm-minimal added to flake.nix)
nix build /etc/nixos#nixosConfigurations.vm-minimal.config.system.build.qcow2

# Image will be ~1-2GB (minimal base config without desktop environment)
# Includes: base.nix (SSH, user vpittamp, core CLI tools), cloud-init, QEMU guest agent
```

**NixOS Configuration Structure** (Using existing /etc/nixos flake):
```nix
# /etc/nixos/configurations/vm-minimal.nix
{ config, pkgs, modulesPath, ... }:
{
  imports = [
    # Reuse existing base configuration (SSH keys, users, core packages)
    ./base.nix

    # QEMU guest optimizations (virtio drivers, agent)
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # VM-specific configuration
  networking.hostName = "nixos-kubevirt-vm";

  # Cloud-init support for KubeVirt (REQUIRED)
  services.cloud-init.enable = true;

  # QEMU guest agent for better VM integration (RECOMMENDED)
  services.qemu-guest-agent.enable = true;

  # Boot configuration for VM
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";  # virtio disk device
  };

  # Minimal additional packages for VM workloads
  environment.systemPackages = with pkgs; [
    # Core from base.nix already included: vim, git, curl, jq, tmux
    # Add VM-specific tools if needed:
    # kubectl
    # docker
  ];

  # Note: base.nix already provides:
  # - SSH with authorized keys for vpittamp user
  # - Nix flakes enabled
  # - Essential CLI tools (vim, git, ripgrep, fd, tmux)
  # - Auto garbage collection
  # - Sudo without password

  system.stateVersion = "24.11";
}
```

**References**:
- [nixos-generators](https://github.com/nix-community/nixos-generators)
- [NixOS VM Building](https://nixos.org/manual/nixos/stable/#sec-building-image)

---

### Q5: VirtualMachine Cloud-Init Integration

**Question**: How should cloud-init be configured for NixOS VirtualMachines to support dynamic configuration (hostname, SSH keys, network)?

**Research Findings**:

- **KubeVirt supports cloud-init** via `spec.template.spec.volumes[].cloudInitNoCloud` or `cloudInitConfigDrive`
- **NixOS cloud-init support**: Available via `services.cloud-init.enable = true` in NixOS configuration
- **Cloud-init data sources**: NoCloud (inline YAML in VirtualMachine spec) or ConfigDrive (ISO image)

**Decision**: **Use cloudInitNoCloud with inline userData**

**Rationale**:
- NoCloud source is simplest for Kubernetes-native configuration
- Inline userData in VirtualMachine spec enables GitOps management
- No external ConfigDrive ISO required
- Supports all required configuration: hostname, users, SSH keys, network

**Implementation**:

```typescript
// cdk8s/charts/apps/nixos-vm-chart.ts
import { VirtualMachine } from '../../imports/kubevirt.io';

new VirtualMachine(this, 'nixos-dev-vm', {
  spec: {
    running: false, // Manual start/stop via runStrategy
    template: {
      spec: {
        domain: {
          devices: {
            disks: [{
              name: 'rootdisk',
              disk: { bus: 'virtio' },
            }, {
              name: 'cloudinitdisk',
              disk: { bus: 'virtio' },
            }],
          },
          resources: {
            requests: {
              memory: '4Gi',
              cpu: '2',
            },
          },
        },
        volumes: [{
          name: 'rootdisk',
          dataVolume: {
            name: 'nixos-dev-datavolume',
          },
        }, {
          name: 'cloudinitdisk',
          cloudInitNoCloud: {
            userData: `#cloud-config
hostname: nixos-dev
users:
  - name: dev
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... user@host
`,
          },
        }],
      },
    },
  },
});
```

**Production Enhancement** (Phase 2):
- Use ExternalSecret to inject SSH keys from Azure Key Vault
- Reference Secret in cloudInitNoCloud instead of inline userData

**References**:
- [KubeVirt Cloud-Init](https://kubevirt.io/user-guide/virtual_machines/startup_scripts/#cloud-init)
- [NixOS Cloud-Init Module](https://search.nixos.org/options?query=services.cloud-init)

---

### Q6: PVC Retention Policy Implementation

**Question**: How should configurable PVC retention policies be implemented for VirtualMachines (delete vs. retain on VM deletion)?

**Research Findings**:

- **VirtualMachine doesn't have native PVC retention field**
- **DataVolume has PVC deletion behavior** based on ownership
- **Kubernetes OwnerReferences** control cascading deletion

**Options**:

1. **ownerReferences on PVC**
   - Set VirtualMachine as owner → PVC deleted when VM deleted
   - No ownerReference → PVC retained when VM deleted

2. **DataVolume retention policy**
   - Use `dataVolumeTemplates` in VirtualMachine spec (ephemeral)
   - Use separate DataVolume resource (persistent)

**Decision**: **Use dataVolumeTemplates for ephemeral, separate DataVolume for persistent**

**Rationale**:
- `dataVolumeTemplates` creates DataVolume owned by VirtualMachine (cascading deletion)
- Separate DataVolume resource has no owner, survives VM deletion
- Aligns with Kubernetes ownership patterns
- Enables clear separation in chart properties

**Implementation**:

```typescript
// cdk8s/charts/apps/nixos-vm-chart.ts
export interface NixOsVmChartProps extends ChartProps {
  vmName: string;
  dataVolumeName?: string; // If provided, use existing DataVolume (persistent)
  imageUrl?: string;        // If provided, create dataVolumeTemplate (ephemeral)
  pvcRetention: 'delete' | 'retain';
}

export class NixOsVmChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsVmChartProps) {
    super(scope, id, props);

    if (props.pvcRetention === 'delete' && props.imageUrl) {
      // Ephemeral: Use dataVolumeTemplates (owned by VM, deleted with VM)
      new VirtualMachine(this, 'vm', {
        spec: {
          dataVolumeTemplates: [{
            metadata: { name: `${props.vmName}-disk` },
            spec: {
              source: { http: { url: props.imageUrl } },
              pvc: {
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '20Gi' } },
              },
            },
          }],
          template: {
            spec: {
              volumes: [{
                name: 'rootdisk',
                dataVolume: { name: `${props.vmName}-disk` },
              }],
            },
          },
        },
      });
    } else if (props.pvcRetention === 'retain' && props.dataVolumeName) {
      // Persistent: Reference existing DataVolume (not owned by VM, retained on deletion)
      new VirtualMachine(this, 'vm', {
        spec: {
          template: {
            spec: {
              volumes: [{
                name: 'rootdisk',
                dataVolume: { name: props.dataVolumeName },
              }],
            },
          },
        },
      });
    }
  }
}
```

**References**:
- [KubeVirt DataVolume Templates](https://kubevirt.io/user-guide/storage/disks_and_volumes/#datavolume-template)
- [Kubernetes OwnerReferences](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/)

---

### Q7: virtctl Installation and Usage

**Question**: How should developers install and use virtctl for VirtualMachine console access?

**Options Evaluated**:

1. **Manual installation (krew plugin manager)**
   - Command: `kubectl krew install virt`
   - Pros: Easy discovery via krew, automatic updates
   - Cons: Requires krew installation first

2. **Manual binary download**
   - Download from KubeVirt releases
   - Pros: No dependencies, direct installation
   - Cons: Manual version management

3. **Container image**
   - Run virtctl as Kubernetes Job
   - Pros: No local installation
   - Cons: Complex for interactive console access

**Decision**: **krew plugin manager (recommended), with binary download as fallback**

**Rationale**:
- krew is standard for kubectl plugins
- Easy version updates via `kubectl krew upgrade virt`
- Fallback to binary download for environments without krew

**Implementation**:

**Installation (krew)**:
```bash
# Install krew (if not already installed)
curl https://krew.sh/virt | bash

# Install virtctl via krew
kubectl krew install virt

# Usage
kubectl virt console <vm-name>
kubectl virt start <vm-name>
kubectl virt stop <vm-name>
```

**Installation (binary download)**:
```bash
# Download virtctl binary
VERSION=v1.3.1
wget https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64

# Install to PATH
sudo install virtctl-${VERSION}-linux-amd64 /usr/local/bin/virtctl

# Usage (same as krew)
virtctl console <vm-name>
```

**Documentation**: Include installation instructions in quickstart.md

**References**:
- [virtctl Installation](https://kubevirt.io/user-guide/operations/virtctl_client_tool/)
- [kubectl krew](https://krew.sigs.k8s.io/)

---

## Technology Stack Summary

| Component | Technology | Version | Rationale |
|-----------|------------|---------|-----------|
| **Manifest Generation** | CDK8s (TypeScript) | v2.x | Constitution Principle I: Type-Safe IaC |
| **VM Platform** | KubeVirt | v1.3.1 | Industry-standard Kubernetes VM management |
| **Image Import** | CDI (Containerized Data Importer) | v1.59.0 | DataVolume abstraction for image imports |
| **Image Storage (Phase 1)** | HTTP Server (nginx/Python) | - | Simplest for local dev, CDI native support |
| **Image Storage (Phase 2)** | Gitea OCI Registry | - | Versioned artifacts, reuses existing infrastructure |
| **VM Image Build** | nixos-generators | latest | Purpose-built for NixOS qcow2 image generation |
| **VM Configuration** | Cloud-Init (NoCloud) | - | Kubernetes-native, GitOps-friendly |
| **GitOps** | ArgoCD | - | CNOE-endorsed, existing platform deployment |
| **CLI Tool** | virtctl (krew) | v1.3.1 | Standard KubeVirt CLI for console access |

---

## Best Practices

### KubeVirt on Kind Cluster

1. **Software Emulation**: Always set `useEmulation: true` in KubeVirt CR for Kind clusters (no KVM access)
2. **Resource Limits**: Conservative VM resource allocation (2 CPU, 4GB RAM) to avoid exhausting host resources
3. **Storage Class**: Verify `local-path-provisioner` is default StorageClass for Kind
4. **Node Affinity**: Not applicable for single-node Kind cluster

### DataVolume Image Import

1. **Storage Size**: Allocate 2x qcow2 image size for PVC (allows for filesystem overhead and disk expansion)
2. **Import Progress**: Monitor DataVolume status via `kubectl get datavolume` and check conditions
3. **CDI Scratch Space**: Ensure cluster has sufficient storage for CDI scratch space (temporary during import)
4. **Timeout**: Set appropriate timeout for large image imports (default: 30 minutes)

### VirtualMachine Lifecycle

1. **runStrategy**: Use `Manual` for development (explicit start/stop), `Always` for production (auto-restart)
2. **Grace Period**: Configure graceful shutdown via `terminationGracePeriodSeconds`
3. **Readiness Probes**: Use cloud-init to signal readiness (write to file, VM annotation)
4. **Console Access**: Use `virtctl console` for interactive access, `virtctl vnc` for graphical console

### NixOS Image Optimization

1. **Minimal Base**: Use minimal NixOS configuration for smaller image sizes
2. **Cloud-Init**: Always include `services.cloud-init.enable = true` in base configuration
3. **QEMU Guest Agent**: Install `services.qemu-guest-agent.enable = true` for better VM integration
4. **Image Caching**: Reuse base NixOS image across multiple VMs via DataVolume cloning

---

## Integration Patterns

### CDK8s Chart Organization

```
cdk8s/charts/
├── infra/
│   ├── kubevirt-chart.ts       # KubeVirt operator + CR (sync wave -100)
│   └── cdi-chart.ts            # CDI operator + CR (sync wave -100)
├── apps/
│   ├── nixos-datavolume-chart.ts   # DataVolume for image import (sync wave 0)
│   └── nixos-vm-chart.ts           # VirtualMachine resource (sync wave 10)
└── platform/
    └── nixos-image-server-chart.ts # HTTP server for qcow2 images (sync wave -50)
```

### ArgoCD Application Dependencies

```
KubeVirt Application (sync wave -100)
  └── KubeVirt Operator Deployment
      └── KubeVirt CR (useEmulation: true)

CDI Application (sync wave -100)
  └── CDI Operator Deployment
      └── CDI CR

NixOS Image Server (sync wave -50)
  └── nginx Deployment + Service
      └── ConfigMap with image files

NixOS VMs Application (sync wave 0)
  └── DataVolume (waits for CDI)
      └── VirtualMachine (waits for DataVolume import)
```

### Git Repository Structure

```
stacks/
├── cdk8s/
│   ├── charts/           # CDK8s TypeScript charts
│   ├── imports/          # Generated CRD types
│   └── dist/             # Synthesized manifests
├── nixos/
│   ├── vm-configs/       # NixOS configurations
│   └── images/           # Built qcow2 images (gitignored or LFS)
└── docs/
    └── kubevirt-documentation.md  # KubeVirt reference docs
```

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **Kind cluster resource exhaustion** | VM fails to start | Set conservative defaults (2 CPU, 4GB RAM), document cluster requirements |
| **DataVolume import timeout** | VM deployment blocked | Increase timeout for large images, optimize NixOS image size |
| **Software emulation performance** | Slow VM boot times | Set expectations (3min boot acceptable), recommend bare metal for production |
| **PVC retention confusion** | Accidental data loss | Clear documentation of ephemeral vs. persistent patterns, chart property validation |
| **Cloud-init secrets in Git** | Security risk | Warn in docs, recommend ESO for production, use Secret references not inline |
| **KubeVirt operator updates** | Breaking changes | Pin operator version, test updates in dev before production |

---

## Alternatives Considered and Rejected

### 1. **Kata Containers instead of KubeVirt**

**Rejected**: Kata Containers provide VM-based container isolation, but don't support full VM lifecycle management (console access, stop/start, snapshots). KubeVirt provides richer VM management capabilities.

### 2. **Helm chart for KubeVirt deployment**

**Rejected**: Violates Constitution Principle I (Type-Safe IaC). CDK8s with TypeScript provides better type safety and aligns with project standards.

### 3. **Manual PVC creation instead of DataVolumes**

**Rejected**: DataVolumes provide higher-level abstraction with automatic PVC creation, import tracking, and better integration with KubeVirt. Manual PVC creation requires additional orchestration logic.

### 4. **Docker build for NixOS images instead of nixos-generators**

**Rejected**: Docker builds don't produce bootable qcow2 VM images. nixos-generators is purpose-built for creating cloud/VM images from NixOS configurations.

---

## Phase 0 Completion Checklist

- [x] NixOS image hosting strategy decided (HTTP server Phase 1, OCI registry Phase 2)
- [x] KubeVirt deployment method decided (CDK8s with YAML manifests)
- [x] CDI deployment approach decided (separate ArgoCD Application)
- [x] NixOS qcow2 build process decided (nixos-generators)
- [x] Cloud-init integration pattern decided (cloudInitNoCloud with inline userData)
- [x] PVC retention policy implementation decided (dataVolumeTemplates vs. separate DataVolume)
- [x] virtctl installation method decided (krew recommended, binary fallback)
- [x] Technology stack documented and justified
- [x] Best practices identified from KubeVirt documentation
- [x] Integration patterns defined for CDK8s and ArgoCD
- [x] Risks identified with mitigations
- [x] Alternatives considered and rejection rationales documented

**Status**: ✅ Phase 0 Complete - Ready for Phase 1 (Design & Contracts)
