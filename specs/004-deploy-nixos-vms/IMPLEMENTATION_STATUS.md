# Implementation Status: Deploy NixOS VMs using KubeVirt

**Feature Branch**: `004-deploy-nixos-vms`
**Last Updated**: 2025-10-15
**Status**: ✅ Production Ready - Desktop VM with Full Remote Access

## Current Status

### ✅ Completed

#### Phase 1: Core VM Deployment
- [x] NixOS qcow2 image generation using nixos-generators
- [x] Docker image packaging and nginx HTTP server
- [x] CDK8s charts for VirtualMachine, DataVolume, ImageServer
- [x] ArgoCD GitOps integration
- [x] Cloud-init configuration for user setup
- [x] SSH access via NodePort services
- [x] Attic binary cache integration (spec 003) - NOT USED (see learnings)

#### Phase 2: KubeVirt v1.6.2 Upgrade
- [x] Upgraded KubeVirt from v1.3.1 to v1.6.2
  - QEMU 9.1.0 (was 7.2.0)
  - libvirt 10.10.0 (was 9.0.0)
  - **Critical improvement**: TCG software emulation now functional
  - VMs boot successfully in 5-7 minutes (vs appearing to hang indefinitely before)

#### Phase 3: Desktop Environment & Image Optimization
- [x] KDE Plasma 6 desktop pre-installed in base image
- [x] SDDM display manager disabled (headless mode)
- [x] xrdp service for Microsoft Remote Desktop access ✅ **WORKING**
- [x] Audio support via PulseAudio (xrdp compatibility)
- [x] **Fast image building strategy**: Build on Hetzner host with KVM acceleration
  - Image built in ~5 minutes (vs 60-90 min in VM with TCG)
  - 19GB desktop image with full KDE + tools
  - Deployment time: ~8 minutes total (image upload + VM boot)

#### Phase 4: User Accounts & Access Methods
- [x] Created separate `kubevirt-desktop.nix` configuration for VM images
  - Includes both `nixos` and `vpittamp` users with password "nixos123"
  - Users baked into image (no cloud-init dependency for login)
  - Proper separation from Hetzner production config

- [x] Tailscale integration ✅ **WORKING**
  - Service enabled and authenticated
  - VM accessible at Tailscale IP: 100.108.95.21
  - Hostname: nixos-dev-vm-1

- [x] RustDesk integration ✅ **WORKING via Direct IP**
  - rustdesk-headless service running (systemd)
  - Password authentication configured
  - **RustDesk ID**: 211535874
  - **Password**: nixos123
  - **Direct IP Access via Tailscale**: 100.108.95.21 (confirmed working!)

- [x] XRDP integration ✅ **WORKING**
  - Service running and listening on port 3389
  - Accessible via Tailscale: 100.108.95.21:3389
  - Username: vpittamp, Password: nixos123

### 📋 Pending / Future Enhancements

- [ ] Azure Key Vault integration for RustDesk permanent password (currently hard-coded)
- [ ] Persistent storage for RustDesk ID (currently regenerates on VM recreation)
- [ ] VNC server configuration (alternative to RDP/RustDesk)
- [ ] Multi-user desktop support
- [ ] VM snapshot and restore workflows
- [ ] Automated Tailscale authentication via auth keys (currently manual)
- [ ] GPU passthrough for accelerated graphics (hardware limitation: nested virt required)

## Key Learnings & Discoveries

### 🎯 Critical Discovery: KubeVirt v1.6.2 TCG Performance

**Problem**: VMs appeared to hang indefinitely during boot with v1.3.1
**Root Cause**: QEMU 7.2.0 TCG emulation was extremely slow, creating perception of failure
**Solution**: Upgraded to KubeVirt v1.6.2 with QEMU 9.1.0
**Result**: VMs boot successfully in 5-7 minutes with TCG (no nested virtualization needed!)

**Key Insight**: The VMs were always booting, just very slowly. QEMU 9.1.0 has significant TCG improvements that make software emulation practical for development workloads.

### 🚀 Fast Image Building Strategy

**Challenge**: Building NixOS desktop image inside VM takes 60-90 minutes due to TCG
**Solution**: Build image on Hetzner host with KVM acceleration, then deploy

**Workflow**:
1. Build qcow2 on host: `nix run github:nix-community/nixos-generators -- --format qcow --configuration /etc/nixos/configurations/kubevirt-desktop.nix`
2. Upload to nginx server: ~2 minutes (19GB)
3. Deploy VM: ~5 minutes (DataVolume import + boot)
4. **Total**: ~8 minutes vs 90+ minutes

**Why This Works**:
- Nix cache on host (most packages cached)
- KVM acceleration for any compilation
- Only 15 derivations changed between v1 and v2 (Nix hermetic builds!)

### 👤 User Account Architecture

**Problem**: Cloud-init not applying configuration, users couldn't login
**Root Cause**: Pre-built image doesn't reset machine-id, cloud-init doesn't detect "first boot"
**Solution**: Bake users directly into base image

**Implementation**:
- Created `kubevirt-desktop.nix` separate from `vm-hetzner.nix`
- Added both `nixos` and `vpittamp` users with password "nixos123"
- `vpittamp` needed because home-manager expects it
- Users persist across VM deployments

**Trade-off**: Cloud-init can still override passwords/keys, but users always exist for console access

### 🖥️ Remote Desktop: Three Working Methods

**1. XRDP (Primary Recommendation)**
- ✅ Works out of the box
- ✅ Listening on port 3389
- ✅ Standard RDP protocol
- ✅ Works with Microsoft Remote Desktop, Remmina, xfreerdp
- ✅ Audio support via PulseAudio
- Connection: `xfreerdp /v:100.108.95.21:3389 /u:vpittamp /p:nixos123 /cert:ignore /dynamic-resolution /sound /clipboard`

**2. RustDesk (Direct IP Mode)**
- ✅ Works via Tailscale direct IP
- ✅ Service running as `rustdesk-headless.service`
- ⚠️ Not listening on TCP ports (uses UDP for direct connections)
- ⚠️ Password must be set via `rustdesk --password <pass>` command
- ID: 211535874, Password: nixos123
- **Direct IP connection confirmed working by user**

**3. SSH + X11 Forwarding**
- ✅ Always available as fallback
- Port 22 exposed via Service
- Useful for debugging

### ⚙️ RustDesk Configuration Details

**Service Type**: `rustdesk-headless.service` (systemd system service)
**User**: root (required for headless mode)
**Configuration**: `/root/.config/rustdesk/RustDesk2.toml`
**Key Settings**:
```toml
direct-server = "Y"
direct-access-port = "21116"
allow-linux-headless = "Y"
enable-keyboard = true
enable-clipboard = true
enable-file-transfer = true
enable-audio = true
```

**Password Management**:
- Set via: `sudo rustdesk --password <password>`
- Stored as hash in RustDesk.toml
- Must be set on each VM deployment (not persisted in image)

**Network Behavior**:
- Does NOT listen on TCP ports (confirmed via `ss -tlnp`)
- Uses UDP for direct connections
- Direct IP mode works when connecting from RustDesk client

### 🌐 Tailscale Integration

**Status**: ✅ Working perfectly
**Setup**: Manual authentication required (`sudo tailscale up`)
**VM Hostname**: nixos-dev-vm-1 (suffix appended by Tailscale)
**VM IP**: 100.108.95.21
**Access Pattern**: All remote desktop protocols accessible via this IP

**Future Improvement**: Use Tailscale auth keys in cloud-init for zero-touch setup

### 📦 Attic Binary Cache: Not Used

**Original Plan**: Use Attic in-cluster cache for fast rebuilds
**Reality**: Building pre-configured image is faster than rebuilding in VM
**Reason**: TCG emulation makes in-VM builds impractical (60-90 min)
**Decision**: Keep Attic for host-level caching, not VM-level

### 🏗️ Configuration File Separation

**Problem**: `vm-hetzner.nix` locks accounts with `initialPassword = ""`
**Solution**: Created `kubevirt-desktop.nix` specifically for KubeVirt images

**Key Differences**:
- `lib.mkDefault` for filesystem device (allows nixos-generators override)
- Users with actual passwords (not locked)
- Optimized for image building, not runtime application
- SDDM disabled (headless mode)
- RustDesk headless service enabled

## Configuration Files

### Updated Files

1. **`/etc/nixos/configurations/kubevirt-desktop.nix`** ⭐ NEW
   - Separate configuration for KubeVirt image building
   - Both `nixos` and `vpittamp` users with password "nixos123"
   - Tailscale service enabled
   - RustDesk headless service enabled (`enableSystemService = true`)
   - SDDM disabled (headless mode)
   - xrdp with PulseAudio audio support
   - KDE Plasma 6 desktop

2. **`cdk8s/config/applications.ts`**
   - VM resources: 4 cores, 12GB RAM (balanced for TCG)
   - DataVolume storage: 50Gi
   - Image URL: `http://nixos-image-server.default.svc.cluster.local/nixos-kubevirt-desktop.qcow2`

3. **`/etc/nixos/modules/services/rustdesk.nix`**
   - `enableSystemService` option for headless mode
   - Creates `rustdesk-headless.service` when enabled
   - Xvfb integration for software rendering
   - Configuration activation script

### Key Features in Current Configuration

**Desktop Environment:**
- KDE Plasma 6 with X11 (Wayland disabled for RDP compatibility)
- SDDM display manager disabled (headless mode)
- Audio via PulseAudio (xrdp audio redirection support)

**Remote Access:**
- **SSH**: Port 22 (always available)
- **xrdp**: Port 3389 (Microsoft Remote Desktop) ✅ **PRIMARY METHOD**
- **RustDesk**: Direct IP via Tailscale (UDP-based) ✅ **CONFIRMED WORKING**
- **Tailscale**: 100.108.95.21 (secure VPN access)

**System Resources:**
- CPU: 4 cores (balanced for TCG emulation)
- Memory: 12GB (desktop + services)
- Disk: 50GB root volume

**Network:**
- KubeVirt masquerade networking (pod network)
- NodePort services for SSH/RDP (host access)
- Tailscale for remote access (100.108.95.21)

## Access Methods

### 1. 🖥️ XRDP via Tailscale (PRIMARY RECOMMENDATION)
```bash
# From Linux (xfreerdp):
xfreerdp /v:100.108.95.21:3389 /u:vpittamp /p:nixos123 /cert:ignore /dynamic-resolution /sound /clipboard

# From Mac:
# Open Microsoft Remote Desktop app
# Add PC: 100.108.95.21
# Connect with username: vpittamp, password: nixos123

# From Windows:
mstsc /v:100.108.95.21
# Enter credentials: vpittamp / nixos123
```

### 2. 🖥️ RustDesk via Tailscale Direct IP ✅ CONFIRMED WORKING
```bash
# Setup password in VM (one-time):
virtctl console nixos-dev-vm
sudo rustdesk --password nixos123

# From RustDesk client (any platform):
# 1. Enable "Direct IP/DNS" in settings
# 2. Enter ID: 211535874
# 3. Or use direct IP: 100.108.95.21
# 4. Enter password: nixos123
# 5. Connect!
```

### 3. 🔐 SSH via Tailscale
```bash
ssh vpittamp@100.108.95.21
# Password: nixos123
```

### 4. 🔐 SSH via kubectl port-forward
```bash
kubectl port-forward -n default svc/nixos-dev-vm-rdp 2222:22
ssh vpittamp@localhost -p 2222
# Password: nixos123
```

### 5. 🖥️ Console via virtctl (emergency access)
```bash
virtctl console nixos-dev-vm
# Login: vpittamp or nixos
# Password: nixos123
```

## Deployment Workflow (Proven)

### Build and Deploy New Image

```bash
# 1. Build image on Hetzner host (with KVM acceleration)
cd /etc/nixos
nix run github:nix-community/nixos-generators -- \
  --format qcow \
  --configuration ./configurations/kubevirt-desktop.nix \
  -o /tmp/nixos-kubevirt-desktop-v2

# 2. Copy to nginx server
sudo cp /nix/store/<hash>-nixos-disk-image/nixos.qcow2 \
  /usr/share/nginx/html/nixos-kubevirt-desktop.qcow2

# 3. Force DataVolume recreation
kubectl delete datavolume nixos-dev-datavolume -n default --force --grace-period=0
argocd app sync nixos-dev-datavolume --insecure --force

# 4. Deploy VM
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update

# 5. Wait for VM to boot (~5 minutes)
kubectl get vm,vmi -n default -w
```

### First-Time VM Setup

```bash
# 1. Console access
virtctl console nixos-dev-vm
# Login: vpittamp / nixos123

# 2. Authenticate Tailscale (one-time)
sudo tailscale up
# Visit auth URL in browser

# 3. Set RustDesk password (one-time)
sudo rustdesk --password nixos123

# 4. Verify services
sudo systemctl status xrdp
sudo systemctl status rustdesk-headless
```

## Known Issues & Solutions

### ✅ RESOLVED: TCG Performance (KubeVirt v1.6.2)
**Was**: VMs appeared to hang during boot
**Now**: VMs boot successfully in 5-7 minutes with QEMU 9.1.0

### ✅ RESOLVED: Cloud-init User Creation
**Was**: Users not created, couldn't login
**Now**: Users baked into image, always available

### ✅ RESOLVED: RustDesk Direct IP Not Working
**Was**: RustDesk not listening on network ports
**Now**: Confirmed working via direct IP (UDP-based)

### ⚠️ KNOWN: RustDesk Password Not Persistent
**Issue**: Password must be set on each VM deployment
**Workaround**: Run `sudo rustdesk --password nixos123` after boot
**Future Fix**: Azure Key Vault integration

### ⚠️ KNOWN: Tailscale Auth Required on Each Deployment
**Issue**: Manual authentication needed (`tailscale up`)
**Workaround**: Console access + browser auth
**Future Fix**: Tailscale auth keys in cloud-init

## Success Metrics

### ✅ Achieved

- ✅ VM boots successfully with TCG emulation (5-7 minutes)
- ✅ Image builds in ~5 minutes on host with KVM
- ✅ Total deployment time: ~8 minutes (image upload + VM boot)
- ✅ Tailscale integration working (100.108.95.21)
- ✅ RustDesk headless service running
- ✅ RustDesk direct IP confirmed working by user
- ✅ XRDP working perfectly (primary recommendation)
- ✅ SSH access via multiple methods
- ✅ Console access via virtctl
- ✅ Users persist across deployments (nixos, vpittamp)
- ✅ All firewall ports configured correctly
- ✅ Audio support via PulseAudio
- ✅ KDE Plasma 6 desktop fully functional

### Performance Metrics

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Image build (host) | <10 min | ~5 min | ✅ PASS |
| Image upload | <3 min | ~2 min | ✅ PASS |
| DataVolume import | <5 min | ~3 min | ✅ PASS |
| VM boot | <10 min | 5-7 min | ✅ PASS |
| Total deployment | <15 min | ~8 min | ✅ PASS |
| XRDP connection | Works | ✅ | ✅ PASS |
| RustDesk connection | Works | ✅ | ✅ PASS |

## Related Specifications & Documentation

- **spec-003**: Attic/MinIO binary cache (deployed but not used for VM builds)
- **spec-004**: This feature (NixOS VM deployment)
- **spec-005**: Tailscale remote cluster access (used for VM access)
- **KubeVirt v1.6.2**: https://github.com/kubevirt/kubevirt/releases/tag/v1.6.2
- **QEMU 9.1.0 Release**: https://www.qemu.org/2024/08/13/qemu-9-1-0/
- **nixos-generators**: https://github.com/nix-community/nixos-generators
- **RustDesk Docs**: https://rustdesk.com/docs/
- **Tailscale RustDesk Guide**: https://tailscale.com/blog/tailscale-rustdesk-remote-desktop-access

## Quick Reference

**VM Details:**
- Name: nixos-dev-vm
- Tailscale IP: 100.108.95.21
- Tailscale Hostname: nixos-dev-vm-1
- RustDesk ID: 211535874
- Users: nixos, vpittamp
- Password: nixos123

**Access:**
- XRDP: `xfreerdp /v:100.108.95.21:3389 /u:vpittamp /p:nixos123 /cert:ignore /dynamic-resolution /sound /clipboard`
- RustDesk: ID 211535874 or direct IP 100.108.95.21
- SSH: `ssh vpittamp@100.108.95.21`
- Console: `virtctl console nixos-dev-vm`

**Key Files:**
- Configuration: `/etc/nixos/configurations/kubevirt-desktop.nix`
- CDK8s Config: `cdk8s/config/applications.ts`
- RustDesk Module: `/etc/nixos/modules/services/rustdesk.nix`

---

**Status**: ✅ **PRODUCTION READY** - All core functionality verified and working. Minor enhancements (Azure Key Vault secrets, persistent RustDesk ID) remain for future iterations.
