# Research & Technical Decisions: Deploy NixOS VMs using KubeVirt

**Feature**: 004-deploy-nixos-vms
**Date**: 2025-10-11
**Purpose**: Document technical research, design decisions, and rationale for NixOS VM deployment on KubeVirt

## Research Questions

Based on the Technical Context, the following unknowns required research:

1. **nixos-generators format selection**: Should we use `--format kubevirt` or `--format qcow`?
2. **Image distribution**: How to serve qcow2 images for CDI DataVolume import?
3. **Cloud-init integration**: How to configure VM initialization with user/SSH/network setup?
4. **Desktop deployment strategy**: Install KDE in base image or via nixos-rebuild?
5. **Binary cache integration**: How to configure VMs to use Attic cache from spec 003?
6. **KubeVirt networking**: Which network mode (pod, bridge, masquerade) for SSH/RDP access?
7. **Storage backend**: PVC provisioning requirements for DataVolume imports?

## Technical Decisions

### Decision 1: nixos-generators Format

**Chosen**: `--format kubevirt`

**Rationale**:
- nixos-generators has dedicated `kubevirt` format providing KubeVirt-specific configuration out-of-the-box
- Includes GRUB bootloader on /dev/vda (required for qcow2 boot)
- Serial console on ttyS0 for KubeVirt console access
- Filesystem auto-resize for PVC expansion
- Cloud-init enabled by default
- Proper virtio networking configuration

**Alternatives Considered**:
1. **`--format qcow`**: Generic QCOW2 format without KubeVirt-specific optimizations
   - Rejected: Requires manual GRUB configuration, networking setup, cloud-init enablement
   - Previous attempts had networking issues (no DHCP, static eth0 only)
   - More manual configuration increases error surface

2. **Custom format**: Fork kubevirt format and customize
   - Rejected: Unnecessary complexity; kubevirt format already provides what we need
   - Would require maintaining custom nixos-generators fork

**Impact**:
- Image build command: `nixos-generate --format kubevirt --configuration /etc/nixos/configurations/kubevirt-minimal.nix`
- Output: bootable qcow2 with GRUB, cloud-init, virtio drivers
- Future: Can extend kubevirt-minimal.nix config without changing format

### Decision 2: Image Distribution Strategy

**Chosen**: Docker image containing nginx + qcow2 file

**Rationale**:
- CDI DataVolume requires HTTP/HTTPS URL for image import
- Docker Hub provides free public image hosting (vpittamp23/nixos-kubevirt-minimal)
- In-cluster nginx deployment provides 100-500 MB/s download speeds
- No external dependencies (S3, cloud storage) for minimal implementation
- Consistent with existing cdk8s/charts/platform/ pattern

**Implementation**:
```dockerfile
FROM nginx:alpine
COPY nixos.qcow2 /usr/share/nginx/html/
```

**Alternatives Considered**:
1. **S3 bucket (MinIO)**: Leverage existing MinIO from Attic (spec 003)
   - Rejected for P1-P3: Adds dependency on MinIO deployment
   - Pro: More scalable, versioning support
   - Con: More complex setup, external dependency
   - Future: Consider for multi-image registry in P4+

2. **hostPath volume**: Mount qcow2 from host filesystem
   - Rejected: Not portable across nodes, doesn't work in cloud clusters
   - Breaks GitOps principle (manual file placement required)

3. **ConfigMap/Secret**: Embed qcow2 in Kubernetes resource
   - Rejected: 1.7GB image exceeds 1MB resource size limit

**Impact**:
- NixOsImageServerChart creates Deployment + Service in `default` namespace
- DataVolume references `http://nixos-image-server.default.svc.cluster.local/nixos.qcow2`
- Build pipeline: build qcow2 → package in Docker → push to Docker Hub
- ArgoCD sync wave `-50` ensures image server ready before DataVolume import

### Decision 3: Cloud-init Configuration

**Chosen**: Kubernetes Secret with cloud-config YAML, referenced by VirtualMachine

**Rationale**:
- Cloud-init supports >2048 bytes of userData (inline VirtualMachine limit)
- Kubernetes Secret provides ConfigMap-like semantics with base64 encoding
- Enables templated user configuration (hostname, SSH keys, passwords)
- Existing `buildCloudInitUserData` helper in kubevirt-helpers.ts

**Configuration Format**:
```yaml
#cloud-config
hostname: nixos-dev-vm
users:
  - name: vpittamp
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... k8s_ed_test
chpasswd:
  list: |
    vpittamp:nixos123
    root:nixos123
  expire: false
```

**Alternatives Considered**:
1. **Inline userData in VirtualMachine**: cloud-config directly in VirtualMachine.spec.template
   - Rejected: 2048 byte limit, no templating, clutters VM manifest

2. **ConfigMap**: Similar to Secret but plain text
   - Rejected: Passwords visible in plain text (not base64 encoded)
   - Secrets provide semantic distinction for sensitive data

3. **External script**: Bootstrap script fetching from external URL
   - Rejected: More complex, requires external dependency, slower boot

**Impact**:
- Secret created with sync wave `5` (before VirtualMachine at wave `10`)
- VM spec references: `cloudInitNoCloud: { secretRef: { name: nixos-dev-vm-cloudinit } }`
- SSH access available within 30 seconds of boot
- Console access available via `virtctl console nixos-dev-vm` (password: nixos123)

### Decision 4: Desktop Deployment Strategy

**Chosen**: Two-phase approach (minimal base → desktop via nixos-rebuild)

**Rationale**:
- Minimal base image (<2GB) provides fast initial provisioning (<5 min build + <3 min import)
- Full desktop image (>5GB) would slow initial deployment (>15 min build + >10 min import)
- nixos-rebuild with Attic cache provides 8x faster rebuilds (20min → 3min)
- Enables testing base image functionality (SSH, cloud-init) before desktop complexity
- Supports multiple desktop environments without rebuilding base image

**Phase 1: Minimal Base Image** (P1-P2)
- SSH server only
- Cloud-init for user setup
- Nix configured with Attic substituter
- Git, curl, wget for nixos-rebuild
- virtio drivers, GRUB bootloader

**Phase 2: Desktop Installation** (P3)
```bash
ssh vpittamp@VM_IP
sudo nixos-rebuild switch --flake github:PittampalliOrg/nixos-config#vm-hetzner
```
- Fetches full system closure from Attic (cache hit >80%)
- Installs KDE Plasma, XRDP, fonts, applications
- Desktop available via RDP within 3 minutes

**Alternatives Considered**:
1. **All-in-one image**: Include KDE Plasma in base qcow2
   - Rejected: >5GB image increases build/import time to >25 minutes
   - Harder to test SSH/cloud-init issues (desktop adds complexity)
   - Can't easily switch desktop environments without rebuilding

2. **Multi-image approach**: Separate images per desktop environment
   - Rejected: Multiplies storage requirements (2GB base + 5GB per desktop)
   - More complex image management and versioning
   - Future: Consider if multiple desktops become common use case

3. **Cloud-init desktop install**: Install KDE via cloud-init packages directive
   - Rejected: Cloud-init runs on every boot (slower, not declarative)
   - Doesn't leverage Nix's declarative configuration model
   - No rollback capability (Nix generations provide this)

**Impact**:
- User Story 1 (P1): Minimal base image build + test
- User Story 2 (P2): DataVolume import + VM boot
- User Story 3 (P3): Desktop deployment via nixos-rebuild
- Attic cache populated after first rebuild (subsequent VMs benefit)
- Total time: <5 min (build) + <3 min (import) + <3 min (desktop) = <11 minutes

### Decision 5: Binary Cache Integration

**Chosen**: Configure NixOS VM to use Attic cache from spec 003 as primary substituter

**Rationale**:
- Attic cache already deployed (spec 003 status: ✅ Implemented)
- Provides 8x faster rebuilds (20min → 3min with cache hit >80%)
- Essential for practical VM deployment at scale (multiple VMs benefit from shared cache)
- In-cluster cache provides 100-500 MB/s download speeds (vs 10-50 MB/s from cache.nixos.org)

**Configuration**:
NixOS VM `/etc/nixos/configuration.nix`:
```nix
nix.settings = {
  substituters = [
    "http://attic.nix-cache.svc.cluster.local:8080/nixos"
    "https://cache.nixos.org"
  ];
  trusted-public-keys = [
    "nixos:KHwIGHpt5UQKnVhA9..." # Attic cache public key
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
};
```

**Workflow**:
1. First VM: nixos-rebuild queries Attic (miss) → downloads from cache.nixos.org → builds (~20 min)
2. Post-build: Push system closure to Attic: `attic push nixos /nix/store/...-system`
3. Second VM: nixos-rebuild queries Attic (hit >80%) → downloads from Attic → applies (~3 min)

**Alternatives Considered**:
1. **No binary cache**: Always build from source
   - Rejected: 20+ minutes for full desktop rebuild unacceptable for user experience
   - Multiplied by number of VMs = hours of unnecessary building

2. **Only cache.nixos.org**: Use public cache only
   - Rejected: 10-50 MB/s external bandwidth slower than in-cluster
   - Doesn't cache custom configurations or local packages

3. **Local nix store**: NFS-mounted /nix/store across VMs
   - Rejected: Complex setup, doesn't work in cloud environments
   - No deduplication or compression (Attic provides this)

**Impact**:
- FR-049 to FR-053: Binary cache functional requirements
- User Story 3 acceptance scenario 6: Cache hit rate >80%
- Success Criterion SC-008: Cache hit rate >80% for subsequent rebuilds
- Assumption #10: Attic cache deployed and operational
- First-time setup: Bootstrap cache by pushing first VM's closure

### Decision 6: KubeVirt Networking

**Chosen**: Pod network with masquerade interface

**Rationale**:
- Pod network integrates with Kubernetes networking (no CNI plugin changes)
- Masquerade mode provides NAT for VM traffic through pod network
- Port forwarding (22, 3389) maps VM ports to pod ports for external access
- Service resource exposes SSH/RDP via ClusterIP, NodePort, or LoadBalancer
- Consistent with Kubernetes networking model (Services, Ingress)

**Configuration**:
```typescript
networks: [{
  name: 'default',
  type: 'pod',
  interfaceType: 'masquerade',
  ports: [
    { name: 'ssh', protocol: 'TCP', port: 22 },
    { name: 'rdp', protocol: 'TCP', port: 3389 }
  ]
}]
```

**Service Exposure**:
- **Development**: NodePort Service (access via `<node-ip>:<nodeport>`)
- **Production**: LoadBalancer Service with Tailscale (tailscale.com/expose: true)
- **Optional**: Ingress for HTTP/HTTPS traffic (future: web-based VNC)

**Alternatives Considered**:
1. **Bridge network**: VM connected to external network bridge
   - Rejected: Requires CNI plugin support (Multus), complex setup
   - VM gets external IP (bypasses Kubernetes networking)
   - Not portable across cloud providers

2. **SR-IOV**: Hardware-accelerated networking
   - Rejected: Requires SR-IOV capable hardware, not available in all environments
   - Overkill for SSH/RDP use case (no high-bandwidth requirements)

3. **Host network**: VM uses host network namespace
   - Rejected: Security risk (VM can access host network), port conflicts
   - Breaks Kubernetes network isolation model

**Impact**:
- VirtualMachine uses masquerade network mode (default for pod network)
- Service exposes SSH (22) and RDP (3389) ports
- Tailscale integration for secure external access (optional via `enableTailscale: true`)
- FR-037 to FR-041: Service exposure functional requirements
- Success Criterion SC-006: VM accessible via Service within 30 seconds of running

### Decision 7: Storage Backend for DataVolumes

**Chosen**: Use cluster's default StorageClass for PVC provisioning

**Rationale**:
- Portable across Kubernetes environments (local, cloud)
- No manual PV provisioning required (dynamic provisioning)
- CDI automatically creates PVC from DataVolume
- Cluster admin responsible for StorageClass configuration (out of scope)

**Requirements** (Assumption #2):
- Cluster must have default StorageClass or explicitly specified storageClassName
- StorageClass must support ReadWriteOnce access mode
- Minimum 20Gi capacity per VM (10Gi for image + growth buffer)
- Local development: kind uses local-path provisioner (hostPath-based)
- Cloud: CSI drivers (EBS, Azure Disk, GCE PD)

**DataVolume Spec**:
```yaml
spec:
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 20Gi
    # storageClassName: <default> or explicit class
  source:
    http:
      url: http://nixos-image-server.default.svc.cluster.local/nixos.qcow2
```

**Alternatives Considered**:
1. **Static PVs**: Pre-create PersistentVolume resources
   - Rejected: Manual provisioning doesn't scale, breaks automation
   - Requires cluster admin intervention for each VM

2. **hostPath volumes**: Direct host filesystem access
   - Rejected: Not portable, requires node affinity, no replication
   - Doesn't work in cloud environments

3. **NFS/CephFS**: Shared filesystem for VM disks
   - Rejected: ReadWriteMany not needed (VMs are single-instance)
   - Block storage (RWO) provides better performance for VM root disks

**Impact**:
- Assumption #2: Cluster must have StorageClass with dynamic provisioning
- DataVolume automatically provisions PVC (no manual PV creation)
- FR-016: System MUST create DataVolume resource for qcow2 import
- Success Criterion SC-003: DataVolume import <3 minutes for 1.7GB qcow2
- Edge Case EC-003: Handle missing StorageClass gracefully (documented error)

## Best Practices Research

### KubeVirt VirtualMachine Best Practices

**Learned**:
1. **runStrategy over running field**: Use `runStrategy: Always/Manual/RerunOnFailure` instead of boolean `running: true/false`
   - More flexible lifecycle management
   - Automatic restart on failure with `RerunOnFailure`
   - Chart implements `runStrategy` prop (default: `Always`)

2. **Cloud-init via Secret**: Use Secret reference for userData >2048 bytes
   - Inline userData limited to 2048 bytes
   - Secret enables templating and larger configurations
   - Implemented in NixOsVmChart

3. **Sync waves for dependencies**: Order resource creation via ArgoCD sync waves
   - Image server (-50) → Secret (5) → DataVolume (default/0) → VirtualMachine (10) → Service (15)
   - Prevents dependency errors during sync

4. **Resource limits**: Define CPU/memory to prevent unbounded resource usage
   - Default: 2 CPU cores, 4Gi memory (configurable via chart props)
   - Image server: 100m-200m CPU, 128Mi-2Gi memory

5. **Disk naming**: Use consistent volume names (rootdisk, cloudinitdisk)
   - VirtualMachine references DataVolume by name via `dataVolume: { name: ... }`
   - Cloud-init disk separate volume (cloudInitNoCloud type)

### CDI DataVolume Best Practices

**Learned**:
1. **HTTP source validation**: CDI validates HTTP response headers (Content-Type, Content-Length)
   - nginx must serve qcow2 with proper Content-Type (application/octet-stream or leave unset)
   - Implemented in NixOsImageServerChart (nginx default config works)

2. **Import timeout**: CDI has default 20-minute import timeout
   - 1.7GB qcow2 imports in <3 minutes (in-cluster)
   - No timeout override needed for minimal base image

3. **Storage overhead**: qcow2 compressed image expands on disk
   - 1.7GB qcow2 compressed → ~10Gi PVC required (with growth buffer)
   - Specified 20Gi PVC to allow desktop installation growth

4. **Import retry**: CDI automatically retries failed HTTP imports (3 attempts)
   - Edge Case EC-003: Image server unavailable → CDI retries
   - Edge Case EC-004: Network timeout → CDI retries

### NixOS Cloud-init Integration

**Learned**:
1. **cloud-init modules**: NixOS cloud-init supports subset of modules
   - Supported: users, hostname, ssh_authorized_keys, chpasswd, write_files
   - Not supported: package installation (use nixos-rebuild instead)

2. **User creation timing**: Cloud-init runs before systemd-user-sessions
   - Users available before SSH service starts
   - Acceptance Scenario US2-3: SSH access available within 30 seconds

3. **Password security**: Initial passwords in cloud-config are plain text
   - Development: Acceptable for testing (nixos123)
   - Production: Use SSH keys only, disable password auth
   - Future: ESO integration for password management (P4+)

4. **Hostname setting**: Cloud-init sets hostname via hostnamectl
   - Persists across reboots
   - FR-036: VM hostname matches cloud-config hostname directive

### Attic Binary Cache Integration

**Learned**:
1. **Substituter priority**: Nix queries substituters in order
   - Attic first → cache.nixos.org fallback
   - Implemented in nix.settings.substituters list order

2. **Public key trust**: Nix requires trusted-public-keys for binary cache signatures
   - Attic public key obtained from cache metadata
   - Added to VM's nix.settings.trusted-public-keys

3. **Cache population strategy**: Push system closure after first successful build
   - Command: `attic push nixos /nix/store/...-system`
   - Subsequent VMs benefit from cached closure (>80% hit rate)

4. **Network reliability**: Use HTTP for in-cluster Attic access
   - URL: `http://attic.nix-cache.svc.cluster.local:8080/nixos`
   - No TLS overhead for in-cluster traffic
   - Assumption #10: Attic service accessible from VM pods

## Technology Stack Decisions

### Core Technologies (Confirmed)

| Component | Technology | Version | Rationale |
|-----------|-----------|---------|-----------|
| Manifest Generation | cdk8s | 2.x | CNOE-aligned, type-safe IaC (Principle I) |
| VM Platform | KubeVirt | Latest | Kubernetes-native virtualization, CDI for image import |
| Image Format | qcow2 | N/A | KubeVirt standard, compressed disk images |
| Image Builder | nixos-generators | Latest | Official NixOS image builder, kubevirt format support |
| Image Distribution | nginx | alpine | Lightweight HTTP server, 128Mi-2Gi footprint |
| Container Registry | Docker Hub | N/A | Free public hosting for development |
| Binary Cache | Attic | Latest | From spec 003, 8x rebuild performance |
| GitOps | ArgoCD | Latest | CNOE-aligned, sync waves, automated deployments |
| Cloud-init | cloud-init | Latest | Standard VM initialization, KubeVirt integration |
| Networking | Masquerade | N/A | KubeVirt pod networking, port forwarding |
| Storage | PVC + StorageClass | N/A | Kubernetes-native, dynamic provisioning |

### Development Tools

| Tool | Purpose | Usage |
|------|---------|-------|
| TypeScript | CDK8s chart development | Chart classes, type checking, IDE support |
| npm | Dependency management | cdk8s, @types/node, constructs |
| Nix | NixOS configuration | kubevirt-minimal.nix declarative config |
| Docker | Image packaging | Dockerfile for nginx + qcow2 |
| virtctl | VM management | Console access, VM lifecycle (kubectl virt plugin) |
| ssh | VM access | Remote shell to VMs via Service |

## Open Questions & Future Research

### Short-term (P1-P3)

✅ **Resolved**: All critical questions resolved for minimal implementation.

### Long-term (P4+)

1. **Desktop alternatives**: GNOME, XFCE, i3 support?
   - Research: Multi-image strategy vs runtime selection
   - Rationale: User preference, resource constraints

2. **VNC integration**: Web-based console access?
   - Research: noVNC + KubeVirt VNC configuration
   - Rationale: Browser-based access without RDP client

3. **Snapshot/restore**: VM state preservation?
   - Research: KubeVirt VirtualMachineSnapshot CRD
   - Rationale: Quick rollback, testing workflows

4. **Multi-VM orchestration**: Deploy VM clusters?
   - Research: Kargo pipelines for VM fleets
   - Rationale: Dev/staging/prod VM environments

5. **Production secrets**: ESO integration for passwords/keys?
   - Research: ExternalSecret for cloud-init Secret
   - Rationale: Azure Key Vault integration (Principle VII)

6. **Tailscale automation**: Automatic hostname registration?
   - Research: Tailscale operator for VM registration
   - Rationale: Secure external access without VPN

## Validation Checklist

- [x] All NEEDS CLARIFICATION items from Technical Context resolved
- [x] Technology choices aligned with CNOE stack (Principle V)
- [x] Best practices researched for KubeVirt, CDI, cloud-init
- [x] Alternatives considered with explicit rejection rationale
- [x] Performance constraints validated (timing, resource limits)
- [x] Security implications documented (Principle VII partial compliance)
- [x] Integration points verified (Attic cache, ArgoCD sync waves)
- [x] Future research questions captured for P4+ work

## References

- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [CDI Documentation](https://github.com/kubevirt/containerized-data-importer)
- [nixos-generators Formats](https://github.com/nix-community/nixos-generators)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Attic Binary Cache](https://github.com/zhaofengli/attic)
- [spec 003: Attic + MinIO Implementation](../003-implement-attic-minio/spec.md)
- [cdk8s Documentation](https://cdk8s.io/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
