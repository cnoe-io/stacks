# Implementation Status: Deploy NixOS VMs using KubeVirt

**Feature Branch**: `004-deploy-nixos-vms`
**Last Updated**: 2025-10-12
**Status**: Active Development - Desktop Image with Remote Access

## Current Status

### ✅ Completed

#### Phase 1: Core VM Deployment
- [x] NixOS qcow2 image generation using nixos-generators
- [x] Docker image packaging and registry push
- [x] CDK8s charts for VirtualMachine, DataVolume, ImageServer
- [x] ArgoCD GitOps integration
- [x] Cloud-init configuration for user setup
- [x] SSH access via NodePort services
- [x] Attic binary cache integration (spec 003)

#### Phase 2: Desktop Environment
- [x] KDE Plasma 6 desktop pre-installed in base image
- [x] SDDM display manager configuration
- [x] xrdp service for Microsoft Remote Desktop access
- [x] Audio support via PipeWire
- [x] Increased VM memory to 16GB for desktop workloads

#### Phase 3: Enhanced Remote Access (Current)
- [x] Tailscale service integration
  - Service enabled in NixOS configuration
  - Firewall rules configured (`checkReversePath = "loose"`)
  - Auto-start on boot
  - Client package installed system-wide

- [x] RustDesk integration
  - rustdesk-flutter package installed
  - Firewall ports opened (21115-21119 TCP, 21116 UDP)
  - Ready for Tailscale direct IP access
  - Package available system-wide

### 🚧 In Progress

- [ ] Rebuild NixOS desktop image with Tailscale + RustDesk
- [ ] Push updated image to Docker Hub (vpittamp/kubevirt-nixos-desktop:latest)
- [ ] Deploy updated image-server with new desktop image
- [ ] Test RustDesk connection via Tailscale from Mac

### 📋 Pending

#### User Configuration (Per-User Setup)
- [ ] Run `tailscale up` on first VM boot (one-time authentication)
- [ ] Launch RustDesk GUI and enable "Direct IP Access" setting
- [ ] Test connection from Mac RustDesk client using Tailscale IP

#### Future Enhancements
- [ ] Pre-configure RustDesk "Direct IP Access" via config file
- [ ] Automate Tailscale authentication via auth key
- [ ] VNC server configuration (alternative to RDP/RustDesk)
- [ ] Multi-user desktop support
- [ ] VM snapshot and restore workflows

## Configuration Files

### Updated Files

1. **`/etc/nixos/configurations/kubevirt-desktop.nix`**
   - Added Tailscale service (`services.tailscale.enable = true`)
   - Added RustDesk package (`rustdesk-flutter`)
   - Configured firewall for RustDesk ports
   - Added Tailscale firewall setting (`checkReversePath = "loose"`)
   - Includes: KDE Plasma 6, xrdp, audio, networking

2. **`cdk8s/config/applications.ts`**
   - VM memory increased from 8Gi to 16Gi
   - CPU remains at 4 cores
   - Comment updated to reflect RustDesk + KDE requirements

### Key Features in Current Configuration

**Desktop Environment:**
- KDE Plasma 6 with Wayland support
- SDDM display manager
- Audio via PipeWire (PulseAudio disabled)

**Remote Access:**
- **SSH**: Port 22 (always available)
- **xrdp**: Port 3389 (Microsoft Remote Desktop)
- **RustDesk**: Ports 21115-21119 (with Tailscale direct IP)
- **Tailscale**: Zero-config VPN for secure access

**System Resources:**
- CPU: 4 cores
- Memory: 16GB (increased from 8GB)
- Disk: 50GB root volume

**Network:**
- KubeVirt masquerade networking
- NodePort services for SSH/RDP
- Tailscale for direct peer-to-peer access

## Access Methods

### 1. SSH Access
```bash
SSH_PORT=$(kubectl get svc nixos-dev-vm-rdp -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}')
ssh vpittamp@localhost -p $SSH_PORT
# Password: nixos123
```

### 2. RDP via Microsoft Remote Desktop
```bash
RDP_PORT=$(kubectl get svc nixos-dev-vm-rdp -o jsonpath='{.spec.ports[?(@.name=="rdp")].nodePort}')
# Connect to: localhost:$RDP_PORT
# Username: vpittamp
# Password: nixos123
```

### 3. RDP via Tailscale (After Setup)
```bash
# Inside VM (one-time setup):
tailscale up
# Authorize via browser link

# From Mac:
# Connect to VM's Tailscale IP:3389
```

### 4. RustDesk via Tailscale (After Setup)
```bash
# Inside VM (one-time setup):
rustdesk &
# Enable "Direct IP Access" in Settings → Security

# From Mac RustDesk client:
# Enter VM's Tailscale IP (e.g., 100.116.100.54)
# Password: test123
```

## Next Steps

### Immediate (This Session)

1. **Build Updated Image:**
   ```bash
   cd /tmp
   sudo nixos-generate --format qcow2 \
     --configuration /etc/nixos/configurations/kubevirt-desktop.nix \
     -o /tmp/kubevirt-desktop-image
   ```

2. **Package and Push:**
   ```bash
   docker load < /tmp/kubevirt-desktop-image/nixos.qcow2.tar.gz
   docker tag <image-id> vpittamp/kubevirt-nixos-desktop:latest
   docker push vpittamp/kubevirt-nixos-desktop:latest
   ```

3. **Deploy Updated Image:**
   ```bash
   kubectl rollout restart deployment nixos-image-server -n default
   kubectl delete vm nixos-dev-vm -n default
   kubectl delete pvc nixos-dev-datavolume -n default
   source ~/stacks/deployment/scripts/cluster-menu.sh
   cluster-update
   ```

### Post-Deployment Testing

1. **Verify Tailscale:**
   ```bash
   virtctl console nixos-dev-vm
   # Login: vpittamp / nixos123
   which tailscale
   sudo tailscale up
   # Follow auth link
   ```

2. **Verify RustDesk:**
   ```bash
   which rustdesk
   rustdesk --get-id
   # Note the ID
   export DISPLAY=:0
   rustdesk &
   # Enable "Direct IP Access" in GUI
   ```

3. **Test Connection:**
   - Open RustDesk on Mac
   - Enable "Direct IP Access" in Mac RustDesk settings
   - Enter VM Tailscale IP
   - Connect with password: test123

## Known Issues & Workarounds

### Issue: RustDesk GUI Crashes on Headless Systems
**Symptom**: RustDesk exits with GTK/memory errors when no display session exists
**Workaround**: Connect via RDP first, then launch RustDesk from within RDP session

### Issue: First-Time Tailscale Setup Requires Console Access
**Symptom**: Need to visit browser URL to authenticate Tailscale
**Future Fix**: Use Tailscale auth keys in cloud-init for automated setup

### Issue: RDP Performance Over Network
**Symptom**: Slow/laggy RDP sessions especially for desktop rendering
**Mitigation**: Use RustDesk for better performance, or reduce RDP quality settings

## Documentation Updates Needed

- [ ] Update quickstart.md with desktop image approach
- [ ] Add RustDesk + Tailscale setup guide
- [ ] Document memory requirements (16GB for desktop + remote access)
- [ ] Add troubleshooting section for remote desktop issues

## Success Metrics

- ✅ VM boots with 16GB memory successfully
- ✅ Tailscale service starts automatically
- ✅ RustDesk package available system-wide
- ✅ All firewall ports configured correctly
- ⏳ RustDesk connects via Tailscale from Mac (pending test)
- ⏳ Total setup time: <5 minutes from image to working remote desktop

## Related Specifications

- **spec-003**: Attic/MinIO binary cache (dependency)
- **spec-004**: This feature (NixOS VM deployment)
- **Tailscale Blog**: https://tailscale.com/blog/tailscale-rustdesk-remote-desktop-access
- **RustDesk Docs**: https://rustdesk.com/docs/

---

**Note**: This document tracks the implementation status separate from the formal spec.md. It reflects the actual current state including ongoing work and iterations.
