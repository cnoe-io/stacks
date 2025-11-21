# Research: RustDesk Base Image Integration

**Feature**: 006-update-our-specification
**Date**: 2025-10-14
**Status**: Complete

## Overview

This document captures research findings for integrating RustDesk remote desktop service into NixOS KubeVirt VM base images using declarative configuration. Research focused on four key areas:

1. NixOS base image configuration patterns for KubeVirt
2. RustDesk NixOS module integration and headless mode
3. Binary cache workflow optimization for fast rebuilds
4. External Secrets integration for RustDesk credentials

## 1. NixOS Base Image Configuration for KubeVirt

### Decision: Use NixOS module imports in flake.nix

**Chosen Approach**: Import the existing `/etc/nixos/modules/services/rustdesk.nix` module into the base image flake configuration and enable it with appropriate options.

**Rationale**:
- **Declarative**: Aligns with NixOS philosophy and Constitution Principle IV
- **Reusable**: Existing rustdesk.nix module is already tested on the host system
- **Type-safe**: NixOS module system provides validation and type checking
- **Maintainable**: Configuration changes are version-controlled in Git
- **No runtime execution**: Everything baked into image at build time

**Implementation Pattern**:

```nix
# In base image flake.nix or configuration.nix
{
  imports = [
    ./modules/services/rustdesk.nix  # Import existing module
  ];

  services.rustdesk = {
    enable = true;
    enableSystemService = true;      # Runs before user login
    enableDirectIpAccess = true;     # Port 21116 direct connections
    user = "root";                   # Required for headless mode
    package = pkgs.rustdesk-flutter; # Latest Flutter-based version
  };

  networking.firewall.allowedTCPPorts = [ 21116 ];

  # Headless mode environment (prevents GL errors)
  systemd.services.rustdesk.environment = {
    LIBGL_ALWAYS_SOFTWARE = "1";
  };
}
```

**Alternatives Considered**:

1. **Inline configuration in flake.nix** (no separate module):
   - **Rejected**: Duplicates logic already in rustdesk.nix, harder to maintain

2. **Nix package overlay** (customize rustdesk package itself):
   - **Rejected**: Module approach is cleaner, package doesn't need modification

3. **Custom systemd service definition**:
   - **Rejected**: rustdesk.nix module already creates proper systemd service

**Verification**:
- Build image: `nix build .#nixos-kubevirt-image`
- Check service included: `nix-store -q --references <image-path> | grep rustdesk`
- Mount image and verify: `/etc/systemd/system/rustdesk.service` exists

## 2. RustDesk Headless Mode Configuration

### Decision: Use existing NixOS module with Xvfb-based headless mode

**Chosen Approach**: Utilize the existing `/etc/nixos/modules/services/rustdesk.nix` module which already implements headless mode via Xvfb (X Virtual Framebuffer) + software GL rendering.

**Rationale**:
- **Module already exists**: No need to create new module from scratch
- **Xvfb approach is proven**: Provides virtual X server for RustDesk-Flutter
- **Headless mode implemented**: `enableSystemService = true` option creates system service
- **Software GL rendering**: `LIBGL_ALWAYS_SOFTWARE=1` prevents GPU requirement
- **System service runs before login**: Accessible immediately on boot without user session
- **All required features present**: Direct IP access, permanent password support, configurable user

**Existing Module Analysis** (from `/etc/nixos/modules/services/rustdesk.nix`):

**Module Options**:
- `enable`: Master enable switch
- `enableSystemService`: Creates system service (multi-user.target) instead of user service
- `enableDirectIpAccess`: Enables port 21116 for direct connections
- `user`: User to run service as (default: "vpittamp", should be "root" for VMs)
- `permanentPassword`: Pre-configured password (nullable, for cloud-init integration)
- `package`: RustDesk package variant (default: pkgs.rustdesk-flutter)

**Implementation Details**:
```nix
# System service with Xvfb dependency
systemd.services.rustdesk-headless = {
  after = [ "network-online.target" "xvfb.service" ];
  requires = [ "xvfb.service" ];  # Virtual X server required
  environment = [
    "LIBGL_ALWAYS_SOFTWARE=1"     # Software GL rendering
    "MESA_GL_VERSION_OVERRIDE=3.3"
    "GALLIUM_DRIVER=llvmpipe"
    "DISPLAY=:0"                  # Xvfb display
  ];
};

# Xvfb service (virtual framebuffer)
systemd.services.xvfb = {
  ExecStart = "Xvfb :0 -screen 0 1920x1080x24";
};

# Direct IP access configuration
systemd.user.tmpfiles.rules = [
  "d ${HOME}/.config/rustdesk 0700"
  "f ${HOME}/.config/rustdesk/RustDesk2.toml 0600"
];

# Config file generation
system.activationScripts.rustdeskConfig = ''
  cat > RustDesk2.toml << 'EOF'
  [options]
  direct-server = "Y"
  direct-access-port = "21116"
  permanent-password = "${cfg.permanentPassword}"
  EOF
'';
```

**Base Image Configuration** (to use this module):

```nix
# In base image flake.nix or configuration.nix
{
  imports = [ ./modules/services/rustdesk.nix ];

  services.rustdesk = {
    enable = true;
    enableSystemService = true;      # System service (not user service)
    enableDirectIpAccess = true;     # Port 21116 direct connections
    user = "root";                   # Run as root for headless VMs
    package = pkgs.rustdesk-flutter;
    # permanentPassword set via cloud-init (from Azure Key Vault)
  };
}
```

**Key Differences from Contract** (`contracts/nixos-rustdesk-module.nix`):

| Feature | Existing Module | Contract Proposal | Decision |
|---------|----------------|-------------------|----------|
| Xvfb dependency | Yes (required for Flutter) | Not mentioned | **Keep Xvfb** (required) |
| Service name | `rustdesk-headless` | `rustdesk` | **Use existing name** |
| Headless mode option | Via `enableSystemService` | Via `headlessMode` | **Use `enableSystemService`** |
| Config generation | Activation script | Not specified | **Keep activation script** |
| Password support | `permanentPassword` option | Environment variable | **Use both** (option + env var) |

**Module Revisions Needed**: ✅ **MINOR UPDATES ONLY**

The existing module is already suitable for base image integration. Only minor adjustments needed:

1. **User default**: Change default user from "vpittamp" to "root" for VM context
2. **Headless mode flag**: Add explicit `allow-linux-headless = "Y"` to config generation
3. **Password integration**: Support environment variable substitution in `permanentPassword` option

**Alternatives Considered**:

1. **Desktop mode with X11/Wayland**:
   - **Rejected**: Requires GUI stack (500+ MB), introduces GL complexity

2. **User service mode** (runs after user login):
   - **Rejected**: Delays availability until user session starts

3. **VNC/XRDP instead of RustDesk**:
   - **Rejected**: RustDesk provides better performance and P2P capabilities

**Verification**:
- Check headless mode enabled: `ssh VM 'cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless'`
- Should show: `allow-linux-headless = "Y"`
- Verify service running: `ssh VM 'systemctl status rustdesk'`
- Check for GL errors: `ssh VM 'journalctl -u rustdesk | grep -i "gl\|error"'`

## 3. Binary Cache Workflow for Fast Image Rebuilds

### Decision: Push base image Nix store paths to Attic cache after successful build

**Chosen Approach**: After building the NixOS base image, use existing `deployment/scripts/nix-cache/push-to-cache.sh` script to push all Nix store paths to the in-cluster Attic binary cache.

**Rationale**:
- **Dramatically faster rebuilds**: 3-5 min (cached) vs. 20-25 min (cold build)
- **Existing infrastructure**: Attic + MinIO already deployed (feature 003)
- **Automated workflow**: Script handles cache authentication and chunked uploads
- **Cross-host sharing**: Hetzner host pushes, other developers/CI pulls
- **Standard Nix pattern**: Binary caches are the Nix ecosystem's solution for build acceleration

**Workflow**:

```bash
# 1. Build base image on Hetzner host (initial cold build: 20-25 min)
nix build .#nixos-kubevirt-image

# 2. Push all store paths to Attic cache (one-time setup for this image version)
./deployment/scripts/nix-cache/push-to-cache.sh ./result

# 3. Subsequent builds with cache hits: 3-5 min
# (automatic - Nix checks substituters configured in nix.conf)
nix build .#nixos-kubevirt-image

# 4. Push rebuilt image to MinIO or external registry
# (Image distribution - separate from Nix cache)
```

**Cache Configuration** (already set up in feature 003):
- **Cache namespace**: `nixos` (in Attic)
- **Substituter URL**: `http://attic.nix-cache.svc.cluster.local:8080/nixos`
- **Public key**: Generated during `init-attic-cache.sh` setup
- **Storage backend**: MinIO S3 (100Gi PVC)

**Alternatives Considered**:

1. **No binary cache** (always build from source):
   - **Rejected**: 20-25 min rebuild for every config change is unacceptable

2. **External cache** (Cachix, official NixOS cache):
   - **Rejected**: Requires internet access from Hetzner host, adds external dependency

3. **Build image in CI/CD** (GitHub Actions, GitLab CI):
   - **Future enhancement**: Would enable automated rebuilds on config changes

**Verification**:
- Check cache hit rate: `nix build .#nixos-kubevirt-image --print-build-logs 2>&1 | grep "copying\|building"`
- "copying" = cache hit, "building" = cache miss
- Verify cache contents: `curl http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`

## 4. External Secrets Integration for RustDesk Password

### Decision: Use ESO to sync RustDesk permanent password from Azure Key Vault to cloud-init userdata

**Chosen Approach**: Create ExternalSecret in `default` namespace that syncs `RUSTDESK_PASSWORD` from Azure Key Vault, then reference this secret in cloud-init userdata via CDK8s chart.

**Rationale**:
- **Security compliance**: Aligns with Constitution Principle VII (no hardcoded secrets)
- **Existing pattern**: ESO already used for Tailscale auth keys, LLM API keys
- **GitOps-friendly**: Secret reference in code, actual value in Key Vault
- **Rotation support**: Password can be rotated in Key Vault without chart changes
- **Audit trail**: Azure Key Vault provides access logging

**Implementation Pattern**:

```typescript
// In cdk8s/charts/infra/nixos-vm-chart.ts or secrets chart
import { ExternalSecret } from '../../imports/external-secrets.io';

// Create ExternalSecret for RustDesk password
new ExternalSecret(this, 'rustdesk-password', {
  metadata: {
    name: 'rustdesk-password',
    namespace: 'default',
    annotations: {
      'argocd.argoproj.io/sync-wave': '-70'  // Before VM deployment
    }
  },
  spec: {
    secretStoreRef: {
      name: 'azure-keyvault-store',
      kind: 'ClusterSecretStore'
    },
    target: {
      name: 'rustdesk-password',
      creationPolicy: 'Owner'
    },
    data: [{
      secretKey: 'password',
      remoteRef: {
        key: 'RUSTDESK-PASSWORD'  // Azure Key Vault secret name
      }
    }]
  }
});

// In cloud-init userdata generation (kubevirt-helpers.ts)
// Reference secret in VM environment or cloud-init write_files
```

**Cloud-Init Integration**:

Cloud-init can't directly reference Kubernetes Secrets, so we have two options:

**Option A**: Pass password as VM environment variable (via KubeVirt)
- VM spec includes `env` referencing Secret
- Cloud-init script reads from environment: `$RUSTDESK_PASSWORD`

**Option B**: Write password to file in cloud-init write_files
- Secret mounted as volume in VM pod
- Cloud-init copies to RustDesk config location

**Recommended**: Option A (environment variable) - simpler, no file management

**Alternatives Considered**:

1. **Hardcoded password in chart** (current approach):
   - **Rejected**: Violates Constitution Principle VII (security by default)

2. **Generate random password at VM boot**:
   - **Rejected**: User can't know password to connect; would need separate retrieval mechanism

3. **Use SSH keys instead of password**:
   - **Rejected**: RustDesk uses its own authentication, separate from SSH

**Verification**:
- Check secret exists: `kubectl get secret rustdesk-password -n default`
- Verify sync: `kubectl get externalsecret rustdesk-password -n default -o jsonpath='{.status.conditions[0].status}'` (should be "True")
- Test in VM: `ssh VM 'env | grep RUSTDESK_PASSWORD'` (if using env var approach)

## 5. Image Distribution After Rebuild

### Decision: Push qcow2 image to MinIO, update DataVolume imageURL in CDK8s chart

**Chosen Approach**: After building and testing the new base image, push it to the in-cluster MinIO instance (or external registry), then update the `imageURL` in `nixos-vm-chart.ts` to reference the new image version.

**Rationale**:
- **Existing MinIO infrastructure**: Already deployed for Nix binary cache (feature 003)
- **In-cluster storage**: No external dependencies for VM image distribution
- **Version control**: Image URLs can include version tags or hashes
- **GitOps workflow**: Chart update triggers ArgoCD sync and VM recreation

**Workflow**:

```bash
# 1. Build image
nix build .#nixos-kubevirt-image

# 2. Convert to qcow2 (if needed - Nix may already output qcow2)
qemu-img convert -f raw -O qcow2 ./result/nixos.img ./nixos-kubevirt-v2.qcow2

# 3. Push to MinIO
mc alias set local-minio http://minio.nix-cache.svc.cluster.local:9000 <access-key> <secret-key>
mc cp ./nixos-kubevirt-v2.qcow2 local-minio/images/

# 4. Update CDK8s chart
# Edit cdk8s/charts/infra/nixos-vm-chart.ts:
#   imageURL: 'http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2'

# 5. Synthesize and deploy
cd cdk8s && npx ts-node main-v2.ts
source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update

# 6. ArgoCD syncs DataVolume, triggers VM recreation with new image
```

**Alternative Image Locations**:

1. **External registry** (GHCR, Docker Hub):
   - Useful for CI/CD pipelines or multi-cluster deployments
   - Requires image conversion to OCI format (buildah/skopeo)

2. **Gitea OCI registry** (in-cluster):
   - Alternative to MinIO, uses existing Gitea infrastructure
   - Same workflow as GHCR but local

3. **HTTP server** (nginx, Apache):
   - Simplest option for one-time testing
   - MinIO preferred for production (S3 API, versioning, lifecycle policies)

**Verification**:
- Check image uploaded: `mc ls local-minio/images/`
- Verify DataVolume references new URL: `kubectl get datavolume nixos-dev-vm-rootdisk -n default -o yaml | grep imageURL`
- Watch VM recreation: `kubectl get vmi -n default -w`

## Summary of Decisions

| Area | Decision | Primary Rationale |
|------|----------|------------------|
| Base image config | Import rustdesk.nix module in flake | Declarative, reuses existing module, version-controlled |
| Headless mode | enableSystemService + LIBGL_ALWAYS_SOFTWARE | Eliminates GUI dependencies, avoids GL errors |
| Binary cache | Push to Attic after build | 3-5 min rebuilds vs. 20-25 min cold builds |
| Password security | ESO + Azure Key Vault | Complies with security principles, enables rotation |
| Image distribution | MinIO (in-cluster S3) | Uses existing infrastructure, GitOps-friendly |

## Open Questions

None - all technical decisions have been made based on existing infrastructure and proven patterns from the debugging investigation.

## Next Steps

Proceed to Phase 1 (Design & Contracts):
1. Generate data-model.md (base image, VM instance, RustDesk service entities)
2. Generate contracts/ (NixOS module API, CDK8s chart API)
3. Generate quickstart.md (end-to-end workflow from image build to VM deployment)
