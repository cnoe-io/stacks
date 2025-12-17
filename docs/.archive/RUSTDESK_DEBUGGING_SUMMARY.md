# RustDesk on NixOS KubeVirt VMs - Debugging Summary

**Date**: 2025-10-14
**Issue**: RustDesk service not starting on NixOS VM boot
**Root Cause**: NixOS cloud-init runcmd not executing (known issue)

---

## Problem Statement

RustDesk headless mode was configured to be deployed via cloud-init runcmd, which creates a NixOS configuration.nix file and runs `nixos-rebuild switch`. However, the runcmd commands never execute, preventing RustDesk from being configured.

## Investigation Timeline

### 1. Initial Symptoms
- VM boots successfully
- RustDesk service not found: `systemctl status rustdesk.service` → "Unit rustdesk.service could not be found"
- `/etc/nixos/configuration.nix` does not exist
- `/var/lib/cloud/instance/scripts/runcmd` script not present

### 2. Verification Steps Taken
- ✅ Verified Secret contains correct cloud-init userdata with NixOS configuration
- ✅ Verified VM receives correct userdata (`/var/lib/cloud/instance/user-data.txt` contains runcmd section)
- ✅ Deleted VM and PVCs completely, recreated from scratch
- ✅ Pushed updated manifests to Gitea repository via `cluster-update`
- ❌ runcmd commands never execute

### 3. Key Finding

**NixOS cloud-init runcmd Known Issue:**
- Cloud-init's `cloud_config_modules` stage (which includes runcmd) does not execute reliably on NixOS
- Confirmed by web research: Multiple GitHub issues (#151507, #39076) and community discussions
- Cloud-init command not available in PATH after first boot (`cloud-init: command not found`)
- Logs show cloud-init reaches "modules-final" stage but runcmd scripts are never created

### 4. Evidence

```bash
# user-data.txt contains runcmd section:
[root@nixos-dev-vm:~]# cat /var/lib/cloud/instance/user-data.txt | grep "runcmd:"
runcmd:

# But runcmd script never created:
[root@nixos-dev-vm:~]# ls /var/lib/cloud/instance/scripts/
ls: cannot access '/var/lib/cloud/instance/scripts/': No such file or directory

# Cloud-init not in PATH post-boot:
[root@nixos-dev-vm:~]# cloud-init --version
-bash: cloud-init: command not found

# No errors in cloud-init logs:
[root@nixos-dev-vm:~]# grep -i error /var/log/cloud-init.log
(no output)
```

---

## Root Cause Analysis

**NixOS Minimal Base Image Limitations:**

1. **Cloud-init Module Configuration**: The NixOS minimal base image used for KubeVirt VMs has incomplete cloud-init configuration
   - `cloud_init_modules` stage completes (handles users, SSH keys, chpasswd)
   - `cloud_config_modules` stage does NOT run (runcmd, scripts-user, etc.)
   - Cloud-init binary not available in system PATH after boot

2. **NixOS Immutability Constraints**: Even if runcmd executed, the approach has fundamental issues:
   - Cannot write to `/etc/systemd/system/` at runtime (read-only filesystem)
   - Requires `nixos-rebuild switch` which:
     - Takes 2-5 minutes to complete
     - Triggers VM reboot
     - Requires network access to download Nix packages during boot
     - May fail if binary cache is slow or unavailable

3. **Cloud-init vs NixOS Philosophy Mismatch**:
   - Cloud-init is designed for imperative runtime configuration
   - NixOS requires declarative configuration defined before system build
   - Hybrid approach (cloud-init → nixos-rebuild) adds complexity and fragility

---

## Failed Approaches

### Attempt 1: Direct systemd Service Creation via Cloud-init
**Approach**: Write systemd service file to `/etc/systemd/system/rustdesk.service` in runcmd

**Result**: ❌ FAILED
**Error**: `/etc/systemd/system/rustdesk.service: Read-only file system`

### Attempt 2: NixOS Configuration + nixos-rebuild via Cloud-init
**Approach**: Generate `/etc/nixos/configuration.nix` in runcmd, then run `nixos-rebuild switch`

**Result**: ❌ FAILED
**Error**: runcmd commands never execute due to NixOS cloud-init module configuration issue

### Attempt 3: Full VM Recreation with Updated Manifests
**Approach**: Delete VM and PVCs, push updated manifests to Gitea, let ArgoCD recreate

**Result**: ❌ FAILED
**Reason**: Same cloud-init runcmd issue persists across VM recreations

---

## Recommended Solutions

### Solution 1: Base Image with RustDesk Pre-configured (RECOMMENDED)

**Approach**: Build NixOS base image with RustDesk service already configured

**Advantages**:
- ✅ Declarative NixOS configuration (aligns with NixOS philosophy)
- ✅ No runtime nixos-rebuild required (fast boot)
- ✅ RustDesk service guaranteed to exist and start
- ✅ Avoids cloud-init runcmd issues entirely
- ✅ Configuration version-controlled in image build process

**Disadvantages**:
- ⚠️ Requires rebuilding image for configuration changes (20-25 min build time)
- ⚠️ Larger image size (includes RustDesk package)

**Implementation**:
1. Add RustDesk configuration to NixOS base image flake or configuration.nix
2. Use the existing `/etc/nixos/modules/services/rustdesk.nix` module from host
3. Enable in image build: `services.rustdesk.enable = true; services.rustdesk.enableSystemService = true;`
4. Build image: `nix build .#nixos-kubevirt-image`
5. Push to image server, update DataVolume image URL

**Example Configuration** (for image build):
```nix
# In base image configuration.nix or flake
{
  services.rustdesk = {
    enable = true;
    enableSystemService = true;  # Runs before user login
    enableDirectIpAccess = true;
    user = "root";  # For headless mode
    package = pkgs.rustdesk-flutter;
  };

  networking.firewall.allowedTCPPorts = [ 21116 ];
}
```

### Solution 2: Post-Boot Configuration Script (WORKAROUND)

**Approach**: Create a one-time systemd service that runs after boot to configure RustDesk

**Advantages**:
- ✅ Works around cloud-init runcmd issue
- ✅ Uses minimal base image
- ✅ Configuration still GitOps-managed

**Disadvantages**:
- ⚠️ Still triggers nixos-rebuild on first boot (slower)
- ⚠️ More complex than base image approach
- ⚠️ Requires careful timing/ordering of services

**Implementation**:
1. Create systemd oneshot service in base image that reads config from cloud-init userdata
2. Service runs after network-online.target
3. Writes `/etc/nixos/configuration.nix` and runs `nixos-rebuild switch`
4. Service disables itself after successful run

### Solution 3: External Configuration Management (NOT RECOMMENDED)

**Approach**: Use Ansible/Salt/Chef to configure VMs after boot

**Disadvantages**:
- ❌ Adds external dependency
- ❌ Not GitOps-native
- ❌ Doesn't align with Kubernetes-native workflows

---

## Decision

**RECOMMENDED**: **Solution 1 - Base Image with RustDesk Pre-configured**

**Rationale**:
1. Aligns with NixOS declarative philosophy
2. Most reliable (no cloud-init runtime issues)
3. Fastest boot time (no nixos-rebuild during boot)
4. Simplest architecture (no hybrid approaches)
5. Already have NixOS build infrastructure (flakes, Nix binary cache)

**Trade-off Accepted**:
- Image rebuild required for configuration changes
- Mitigated by: Nix binary cache (3-5 min rebuild with cache vs 20-25 min cold)

---

## Next Steps

1. **Update NixOS base image configuration**:
   - Add `modules/services/rustdesk.nix` from host to base image modules
   - Enable RustDesk system service in image configuration
   - Set headless mode parameters

2. **Rebuild and push base image**:
   - Build: `nix build .#nixos-kubevirt-image`
   - Push to image server (MinIO or external registry)
   - Update DataVolume imageURL in CDK8s chart

3. **Simplify cloud-init userdata**:
   - Remove RustDesk configuration from runcmd
   - Keep only: users, SSH keys, passwords, Tailscale auth
   - RustDesk will start automatically from base image configuration

4. **Update documentation**:
   - CLAUDE.md: Add RustDesk configuration instructions
   - RUSTDESK_CONNECTION_GUIDE.md: Update with new approach
   - Specification: Document base image decision

---

## Lessons Learned

1. **NixOS cloud-init limitations**: runcmd is not reliable on NixOS minimal images
2. **Declarative > Imperative**: For NixOS, pre-configuring in base image is more robust than runtime configuration
3. **GitOps trade-offs**: Fast iteration (cloud-init) vs reliability (base image)
4. **Testing importance**: Should have tested cloud-init runcmd execution early in development

---

## References

- GitHub Issue: [NixOS/nixpkgs#151507 - LXD cloud-init support is broken](https://github.com/NixOS/nixpkgs/issues/151507)
- GitHub Issue: [NixOS/nixpkgs#39076 - Add cloud-init service to minimal ISO](https://github.com/NixOS/nixpkgs/issues/39076)
- Blog Post: [Debugging cloud-init not executing runcmd commands](https://www.virtualthoughts.co.uk/2023/01/18/debugging-cloud-init-not-executing-runcmd-commands/)
- NixOS Discourse: [A cloudinit image for use in proxmox](https://discourse.nixos.org/t/a-cloudinit-image-for-use-in-proxmox/27519)

---

**Status**: Investigation complete, root cause identified, solution recommended
**Next Action**: Implement Solution 1 (base image approach)
