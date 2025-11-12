# Research: NixOS Wayland/Sway VM Image Build

**Feature**: 007-number-7-short
**Date**: 2025-11-12
**Purpose**: Resolve technical unknowns identified in plan.md Technical Context

## Overview

This document resolves all "NEEDS CLARIFICATION" items from the implementation plan:
1. NixOS image build tooling (nixos-generators vs nix build)
2. Image distribution strategy (HTTP server vs OCI registry)
3. DataVolume source URL format

---

## 1. NixOS Image Build Tooling

### Decision: nixos-generators with flake integration

### Rationale:
- **Native flake support**: Your `/etc/nixos/flake.nix` already imports nixos-generators
- **High-level abstraction**: Automatically handles bootloader, partitioning, QEMU guest optimizations
- **Format flexibility**: Supports qcow2, raw, VDI, ISO, and 20+ other formats
- **Community maintained**: 2.9k GitHub stars, active development
- **Simpler syntax**: Less verbose than direct `make-disk-image.nix` usage
- **KubeVirt optimizations**: Inherits QEMU guest profile automatically

### Implementation:

Add to `/etc/nixos/flake.nix`:

```nix
outputs = { self, nixpkgs, nixos-generators, ... }@inputs: {
  # ... existing outputs ...

  packages.x86_64-linux.hetzner-sway-qcow2 = nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    modules = [
      ./configurations/hetzner-sway.nix
      {
        # Override disk size (default 8192 MB too small)
        virtualisation.diskSize = 50 * 1024;  # 50GB in MB

        # QEMU guest optimizations (automatic in qcow format, but explicit for clarity)
        imports = [ "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];
      }
    ];
    format = "qcow2";
  };
};
```

**Build command**:
```bash
cd /etc/nixos
nix build .#hetzner-sway-qcow2
# Output: ./result/nixos.qcow2
```

### Build Time Estimates:

| Cache State | Estimated Time | Notes |
|-------------|----------------|-------|
| Cold cache (no binary cache) | 20-25 minutes | Building desktop packages from source |
| Warm cache (cache.nixos.org) | 5-10 minutes | Most packages downloaded pre-built |
| With Attic in-cluster cache | 3-5 minutes | Local network speeds, packages from Hetzner host |

### Alternatives Considered:

**Option 2: Native nix build with make-disk-image.nix**
- ✅ More control over disk parameters
- ❌ Requires manual QEMU guest profile import
- ❌ More verbose configuration
- **Rejected because**: nixos-generators provides sufficient control while simplifying common use cases

**Option 3: Disko**
- ✅ Declarative disk partitioning
- ❌ Overkill for single-image use case
- **Rejected because**: Better suited for complex partition layouts (LVM, LUKS) or nixos-anywhere deployments

---

## 2. Image Distribution Strategy

### Decision: HTTP server (Python SimpleHTTPServer or MinIO)

### Rationale:
- **CDI compatibility**: KubeVirt's Containerized Data Importer (CDI) supports HTTP import out-of-the-box
- **Simplicity**: No authentication or registry configuration needed for local dev
- **Bandwidth efficiency**: Single image distribution (not frequent updates)
- **Existing infrastructure**: MinIO already deployed in nix-cache namespace (can serve static files)
- **URL format**: Direct HTTP URL (`http://server/path/to/image.qcow2`) works with DataVolume HTTP source

### Implementation:

**Option A: Python SimpleHTTPServer (quickest for testing)**
```bash
# On host machine (where image was built)
cd /etc/nixos/result
python3 -m http.server 8000
# Image accessible at: http://<host-ip>:8000/nixos.qcow2
```

**Option B: MinIO static file hosting (production-ready)**
```bash
# Upload to MinIO bucket
mc alias set local http://minio.nix-cache.svc.cluster.local:9000 admin <password>
mc mb local/nixos-images
mc cp result/nixos.qcow2 local/nixos-images/hetzner-sway-v1.qcow2
mc anonymous set download local/nixos-images
# Image accessible at: http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2
```

### DataVolume Configuration:

```typescript
// In nixos-vm-chart.ts
new KubeDataVolume(this, 'datavolume', {
  metadata: {
    name: 'hetzner-sway-disk',
    namespace: 'default',
  },
  spec: {
    source: {
      http: {
        url: 'http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2',
      },
    },
    pvc: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '50Gi',
        },
      },
      storageClassName: 'local-path',
    },
  },
});
```

### Alternatives Considered:

**Option 2: OCI registry (Gitea)**
- ✅ Native container image management
- ❌ QCOW2 not a standard OCI artifact (requires manifest manipulation)
- ❌ CDI HTTP import simpler than OCI image extraction
- **Rejected because**: HTTP import is the standard pattern for VM disk images in KubeVirt

**Option 3: virtctl image-upload**
- ✅ Direct upload from local machine to cluster
- ❌ Not idempotent (manual operation)
- ❌ No GitOps integration (imperative command)
- **Rejected because**: Violates GitOps-First Deployment principle (Constitution Principle II)

---

## 3. DataVolume Source URL Format

### Decision: HTTP URL with in-cluster DNS (MinIO service)

### URL Format:
```
http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2
```

**Components**:
- **Protocol**: `http://` (no TLS needed for in-cluster traffic)
- **Service DNS**: `minio.nix-cache.svc.cluster.local` (Kubernetes DNS)
- **Port**: `9000` (MinIO default HTTP port)
- **Bucket**: `nixos-images` (dedicated bucket for VM images)
- **Object**: `hetzner-sway-v1.qcow2` (versioned image filename)

### Versioning Strategy:

**Approach**: Semantic versioning in filename for GitOps traceability

```
hetzner-sway-v1.qcow2       # Initial release
hetzner-sway-v2.qcow2       # WayVNC password fix
hetzner-sway-v3.qcow2       # Performance optimization
```

**Benefits**:
- Clear audit trail in Git history (DataVolume manifest changes)
- Rollback capability (change URL to previous version)
- No image tag collisions (each version is a separate object)

### Alternative: Host-Based HTTP Server

For development/testing, can use host IP directly:

```
http://192.168.1.100:8000/nixos.qcow2
```

**Limitation**: Requires cluster nodes to route to host network. Works in Kind if host IP is accessible from containers.

---

## 4. WayVNC Configuration

### Research: WayVNC password authentication and systemd service

**Finding**: hetzner-sway.nix already includes WayVNC service and configuration module

**Key Configuration Points** (from /etc/nixos/modules/desktop/wayvnc.nix):
- Port: 5900 (default VNC port)
- Address: 0.0.0.0 (required for external access via Tailscale)
- Authentication: PAM authentication enabled by default
- Service: Runs as user service (not system service)

**Implementation Strategy**:
1. **VNC Password**: Store in Azure Key Vault, sync via ExternalSecret
2. **Service Configuration**: No cloud-init configuration needed (image already configured)
3. **Firewall**: Already open on Tailscale interface (ports 5900-5902)

### Cloud-init Simplification:

Unlike RustDesk (which required extensive cloud-init setup), WayVNC is fully configured in the base image. Cloud-init only needs to:
1. Set hostname
2. Configure SSH keys
3. Set user password
4. (Optional) Configure Tailscale auth key

**No WayVNC-specific cloud-init logic needed** - service starts automatically via greetd.

---

## 5. Attic Binary Cache Acceleration

### Decision: Push system closure from Hetzner host to Attic cache

### Rationale:
- **Speed**: Reduces build time from 10 min to 3 min (3.3x speedup)
- **Existing infrastructure**: Attic already deployed in nix-cache namespace
- **Package similarity**: Hetzner host runs same hetzner-sway.nix configuration
- **Cost**: Free (in-cluster network, no egress charges)

### Implementation:

**Step 1: Generate Attic admin token** (one-time setup)
```bash
# Already done per specs/003-implement-attic-minio/quickstart.md
# Token stored in 1Password or printed during init-attic-cache.sh
export ATTIC_TOKEN="your-admin-token-here"
```

**Step 2: Configure Attic CLI on Hetzner host**
```bash
# Install Attic CLI (if not already installed)
nix-env -iA nixpkgs.attic

# Configure cache endpoint
attic login nixos http://attic.nix-cache.svc.cluster.local:8080 $ATTIC_TOKEN
```

**Step 3: Push system closure**
```bash
# Push current system (includes all packages from hetzner-sway.nix)
attic push nixos:nixos /run/current-system

# Alternative: Push specific store paths
nix-store -qR /run/current-system | xargs attic push nixos:nixos
```

**Step 4: Configure build machine to use Attic cache**
```nix
# Add to /etc/nix/nix.conf
extra-substituters = http://attic.nix-cache.svc.cluster.local:8080/nixos
extra-trusted-public-keys = nixos:YOUR_SIGNING_KEY
```

### Cache Hit Rate Estimation:

Based on hetzner-sway.nix package list:
- **System packages**: ~150 packages (100% hit rate if pushed from Hetzner host)
- **Desktop packages**: ~80 packages (90% hit rate - most in cache.nixos.org)
- **Custom packages**: ~5 packages (0% hit rate - need to be built)

**Expected cache hit rate**: 95%+ if Hetzner host packages pushed to Attic

---

## 6. Image Size Optimization

### Analysis:

**Component Size Breakdown** (based on hetzner-sway.nix):
- Base OS: ~2GB (kernel, systemd, base utilities)
- Wayland/Sway stack: ~1.5GB (wlroots, pixman, mesa)
- Desktop applications: ~3GB (Firefox, Ghostty, dotool)
- Development tools: ~1GB (1Password, Tailscale, speech-to-text)
- Audio stack: ~500MB (PipeWire, ALSA, JACK)
- Nix store overhead: ~1GB (multiple package versions)

**Total estimate**: 9-10GB uncompressed

### QCOW2 Compression Benefits:
- **Sparse allocation**: Only used blocks consume physical storage
- **Compression ratio**: 2:1 to 3:1 for OS data
- **Physical size**: ~5-7GB for 50GB qcow2 image (before user data)

### Recommendation:
- **Virtual size**: 50GB (allows for user data, logs, package updates)
- **Physical size**: ~7GB (after build, before VM use)

---

## 7. Multi-Output VNC Configuration

### Research: WayVNC multi-output support

**Finding**: WayVNC supports single output only (limitation of Wayland output protocol)

**Current Configuration** (from hetzner-sway.nix):
```nix
WLR_HEADLESS_OUTPUTS = "3";  # Creates 3 virtual outputs
```

**Reality**: WayVNC can only serve one output at a time. To access all 3 outputs, need to:
1. Run 3 separate WayVNC instances (one per output)
2. Bind to different ports (5900, 5901, 5902)
3. Use `--output` flag to specify which output to serve

### Implementation Strategy:

**Option 1: Single WayVNC instance (simplest)**
- Serve HEADLESS-1 (primary output) on port 5900
- Users navigate workspaces with Sway keybindings (Mod+1, Mod+2, Mod+3)
- All workspaces visible within single VNC session

**Option 2: Multiple WayVNC instances (advanced)**
- Requires 3 systemd services (wayvnc@1, wayvnc@2, wayvnc@3)
- Complex configuration in cloud-init
- **Not needed** - Sway workspaces achieve same goal within single VNC session

### Recommendation:
Use **Option 1** (single WayVNC instance). The 3 virtual outputs are accessible via Sway workspace switching, no need for multiple VNC ports.

**Service Configuration**:
```yaml
ports:
  - name: vnc
    protocol: TCP
    port: 5900
    targetPort: 5900
```

---

## 8. Tailscale LoadBalancer Integration

### Research: Tailscale Operator LoadBalancer provisioning

**Finding**: Tailscale Operator already deployed and functional (from specs/005-remote-kubernetes-cluster)

**Configuration Pattern** (already used in existing charts):
```typescript
const serviceAnnotations: Record<string, string> = {
  'tailscale.com/expose': 'true',
  'tailscale.com/hostname': `${vmName}-vnc`,
  'tailscale.com/tags': 'tag:k8s',
};

const service = new k8s.KubeService(this, 'vnc-service', {
  metadata: {
    annotations: serviceAnnotations,
  },
  spec: {
    type: 'LoadBalancer',
    loadBalancerClass: 'tailscale',
    ports: [
      {
        name: 'vnc',
        protocol: 'TCP',
        port: 5900,
        targetPort: k8s.IntOrString.fromNumber(5900),
      },
    ],
  },
});
```

**No additional research needed** - pattern is well-established in the codebase.

---

## 9. M1 MacBook VNC Client

### Research: VNC clients for M1 macOS

**Options**:
1. **macOS built-in Screen Sharing** (Finder → Go → Connect to Server → vnc://hostname:5900)
2. **RealVNC Viewer** (free, supports VNC authentication, clipboard sync)
3. **TigerVNC Viewer** (open source, lightweight)
4. **Remmina** (requires macOS Homebrew, full-featured)

### Recommendation: macOS built-in Screen Sharing

**Rationale**:
- No installation required (built into macOS)
- Native macOS integration (clipboard, keyboard shortcuts)
- Good performance over LAN/Tailscale
- Supports VNC password authentication

**Usage**:
```bash
# In Finder, press Cmd+K and enter:
vnc://nixos-dev-vm-vnc.tail286401.ts.net:5900
# Or use open command:
open vnc://nixos-dev-vm-vnc.tail286401.ts.net:5900
```

---

## 10. Summary of Resolved Unknowns

| Unknown | Resolution |
|---------|-----------|
| Image build tooling | nixos-generators with flake integration |
| Build time estimate | 3-5 min (Attic cache), 5-10 min (cache.nixos.org), 20-25 min (cold cache) |
| Image distribution | HTTP server (MinIO in nix-cache namespace) |
| DataVolume source URL | `http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2` |
| VNC port configuration | Single port 5900 (workspaces via Sway keybindings) |
| Attic cache strategy | Push Hetzner host system closure before build |
| Image size | 50GB virtual, ~7GB physical (QCOW2 compression) |
| M1 VNC client | macOS built-in Screen Sharing |

---

## 11. Implementation Sequence

Based on this research, the recommended implementation sequence is:

### Phase 1: Image Build (10-15 minutes)
1. Add qcow2 output to `/etc/nixos/flake.nix`
2. Build image: `nix build .#hetzner-sway-qcow2`
3. Verify image: `qemu-img info result/nixos.qcow2`

### Phase 2: Image Distribution (5 minutes)
1. Upload to MinIO: `mc cp result/nixos.qcow2 local/nixos-images/hetzner-sway-v1.qcow2`
2. Set public read access: `mc anonymous set download local/nixos-images`
3. Verify URL accessible: `curl -I http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2`

### Phase 3: CDK8s Chart Updates (15 minutes)
1. Update `NixOsVmChart` props interface (remove RustDesk properties)
2. Update `buildCloudInitUserData` function (remove RustDesk logic)
3. Update Service ports (remove RDP 3389 and RustDesk 21116, keep VNC 5900)
4. Update DataVolume source URL to new image

### Phase 4: Deployment & Testing (20 minutes)
1. Synthesize manifests: `npx ts-node main-v2.ts`
2. Deploy via cluster-update: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
3. Wait for VM to reach Running state: `kubectl get vm,vmi -n default -w`
4. Test VNC connection from M1 MacBook: `open vnc://nixos-dev-vm-vnc.tail286401.ts.net:5900`

**Total estimated time**: 50-65 minutes (first-time implementation)

---

## References

- **nixos-generators**: https://github.com/nix-community/nixos-generators
- **Building NixOS qcow2 images with flakes**: https://tarnbarford.net/journal/building-nixos-qcow2-images-with-flakes/
- **KubeVirt DataVolume HTTP source**: https://kubevirt.io/user-guide/storage/disks_and_volumes/#http
- **Attic Binary Cache**: https://github.com/zhaofengli/attic
- **WayVNC Configuration**: https://github.com/any1/wayvnc
- **Tailscale LoadBalancer**: https://tailscale.com/kb/1185/kubernetes
