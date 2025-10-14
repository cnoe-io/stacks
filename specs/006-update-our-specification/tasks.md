# Implementation Tasks: RustDesk Base Image Integration

**Feature Branch**: `006-update-our-specification`
**Date**: 2025-10-14
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Overview

This document breaks down the implementation of RustDesk base image integration into discrete, executable tasks organized by user story priority. Each phase represents a complete, independently testable increment of functionality.

**Implementation Strategy**: Incremental delivery by user story priority
- **MVP Scope**: User Story 1 (P1) - Deploy VM with Working RustDesk Service
- **Enhancement 1**: User Story 2 (P2) - Update RustDesk Configuration workflow
- **Enhancement 2**: User Story 3 (P3) - Troubleshooting and diagnostics

## Task Summary

| Phase | User Story | Task Count | Parallel Opportunities |
|-------|-----------|-----------|------------------------|
| 1 | Setup | 3 tasks | 2 parallel groups |
| 2 | Foundational | 4 tasks | 2 parallel groups |
| 3 | US1 (P1) | 9 tasks | 3 parallel groups |
| 4 | US2 (P2) | 3 tasks | 1 parallel group |
| 5 | US3 (P3) | 4 tasks | 2 parallel groups |
| 6 | Polish | 2 tasks | 1 parallel group |
| **Total** | **All** | **25 tasks** | **11 parallel groups** |

**Estimated Time**:
- MVP (Phases 1-3): 4-6 hours
- Full Feature (All Phases): 6-8 hours

---

## Phase 1: Setup & Prerequisites

**Goal**: Prepare development environment and validate existing infrastructure

### T001 [P] - Validate NixOS Module Exists
**Story**: Setup
**File**: `/etc/nixos/modules/services/rustdesk.nix`
**Description**: Verify existing RustDesk NixOS module is present and review its current implementation
**Actions**:
1. SSH to Hetzner host: `ssh root@hetzner-host`
2. Navigate to NixOS config: `cd /etc/nixos`
3. Verify module exists: `ls -la modules/services/rustdesk.nix`
4. Review module options: `grep -A 5 "options.services.rustdesk" modules/services/rustdesk.nix`
5. Note current defaults (user, enableSystemService, permanentPassword)

**Success Criteria**:
- Module file exists at expected path
- Module defines required options: `enable`, `enableSystemService`, `enableDirectIpAccess`, `user`, `package`, `permanentPassword`
- Xvfb service is already implemented in module

**Dependencies**: None

---

### T002 [P] - Verify Binary Cache Accessibility
**Story**: Setup
**File**: N/A (infrastructure validation)
**Description**: Confirm Attic binary cache and MinIO are accessible from Hetzner host
**Actions**:
1. From Hetzner host, check Nix substituters: `cat /etc/nix/nix.conf | grep substituters`
2. Verify Attic cache URL is configured: `http://attic.nix-cache.svc.cluster.local:8080/nixos`
3. Test cache connectivity: `curl -I http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`
4. Verify MinIO accessibility: `mc alias list | grep local-minio`
5. Test MinIO images bucket: `mc ls local-minio/images/`

**Success Criteria**:
- Nix substituters include Attic cache URL
- Attic cache returns HTTP 200 on nix-cache-info request
- MinIO client configured with local-minio alias
- Images bucket exists (or can be created)

**Dependencies**: None

---

### T003 [P] - Verify Azure Key Vault Secret Exists
**Story**: Setup
**File**: N/A (external dependency validation)
**Description**: Confirm RUSTDESK-PASSWORD secret exists in Azure Key Vault for ESO integration
**Actions**:
1. Set Key Vault name: `VAULT_NAME="your-keyvault-name"`
2. Check secret exists: `az keyvault secret show --vault-name $VAULT_NAME --name RUSTDESK-PASSWORD`
3. If secret doesn't exist, generate password: `RUSTDESK_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-16)`
4. Create secret: `az keyvault secret set --vault-name $VAULT_NAME --name RUSTDESK-PASSWORD --value "$RUSTDESK_PASSWORD"`
5. Document password securely (1Password, etc.)

**Success Criteria**:
- RUSTDESK-PASSWORD secret exists in Azure Key Vault
- Secret value is at least 12 characters
- Password is documented in secure password manager

**Dependencies**: None

---

## Phase 2: Foundational Tasks (Blocking Prerequisites)

**Goal**: Complete prerequisite tasks that ALL user stories depend on

### T004 [X] - Update RustDesk NixOS Module for VM Context
**Story**: Foundational (required for US1, US2, US3)
**File**: `/etc/nixos/modules/services/rustdesk.nix`
**Description**: Add headless mode flag and environment variable support to existing module
**Actions**:
1. SSH to Hetzner host: `ssh root@hetzner-host && cd /etc/nixos`
2. Edit RustDesk module: `vim modules/services/rustdesk.nix`
3. **Update 1**: Add headless mode flag to config generation (around line 140):
   ```nix
   # In system.activationScripts.rustdeskConfig, add to RustDesk2.toml content:
   allow-linux-headless = "Y"
   ```
4. **Update 2** (Optional): Change default user to "root" for VM deployments (line 18):
   ```nix
   default = "root";  # Changed from "vpittamp"
   ```
5. Save changes and test module syntax: `nix-instantiate --eval -E 'import <nixpkgs/nixos> { configuration = ./modules/services/rustdesk.nix; }'`

**Success Criteria**:
- Module file updated with `allow-linux-headless = "Y"` in config generation
- Nix syntax validation passes (no errors)
- Module remains backward-compatible (no breaking changes for desktop use)

**Dependencies**: T001 (module exists)

---

### T005 [P] [X] - Create RustDesk Password ExternalSecret Chart
**Story**: Foundational (required for US1, US2, US3)
**File**: `cdk8s/charts/secrets/rustdesk-secrets-chart.ts`
**Description**: Create CDK8s chart to sync RUSTDESK-PASSWORD from Azure Key Vault
**Actions**:
1. Navigate to secrets charts: `cd ~/stacks/cdk8s/charts/secrets/`
2. Create new chart file: `rustdesk-secrets-chart.ts`
3. Implement chart based on contract: `contracts/external-secret-rustdesk.yaml`
   - Import ExternalSecret from `../../imports/external-secrets.io`
   - Create ExternalSecret named `rustdesk-password` in `default` namespace
   - Set sync wave `-70` (before VM deployment at wave 0)
   - Reference ClusterSecretStore: `azure-keyvault-store`
   - Map Key Vault secret `RUSTDESK-PASSWORD` to K8s Secret key `password`
4. Export chart class: `export class RustDeskSecretsChart extends Chart { ... }`

**Success Criteria**:
- Chart file compiles without TypeScript errors
- ExternalSecret resource correctly formatted
- Sync wave annotation set to `-70`
- Secret references Azure Key Vault correctly

**Dependencies**: T003 (Azure Key Vault secret exists)

---

### T006 [P] [X] - Register RustDesk Secrets Chart in Factory
**Story**: Foundational (required for US1, US2, US3)
**File**: `cdk8s/lib/idpbuilder-chart-factory.ts` and `cdk8s/config/applications.ts`
**Description**: Register RustDeskSecretsChart and add to applications configuration
**Actions**:
1. Register chart in factory: `cdk8s/lib/idpbuilder-chart-factory.ts`
   ```typescript
   import { RustDeskSecretsChart } from '../charts/secrets/rustdesk-secrets-chart';
   IdpBuilderChartFactory.register('RustDeskSecretsChart', RustDeskSecretsChart);
   ```
2. Add to applications config: `cdk8s/config/applications.ts`
   ```typescript
   {
     name: 'rustdesk-secrets',
     namespace: 'default',
     chart: {
       type: 'RustDeskSecretsChart',
       props: {}
     },
     argocd: {
       syncWave: '-70',
       labels: { 'app.kubernetes.io/name': 'rustdesk-secrets' }
     }
   }
   ```

**Success Criteria**:
- Chart registered in IdpBuilderChartFactory
- Application configuration added for rustdesk-secrets
- TypeScript compilation succeeds

**Dependencies**: T005 (chart created)

---

### T007 [X] - Synthesize and Deploy RustDesk Secrets
**Story**: Foundational (required for US1, US2, US3)
**Files**: `cdk8s/dist/rustdesk-secrets/manifests/`, ArgoCD
**Description**: Synthesize RustDesk secrets manifests and deploy via ArgoCD
**Actions**:
1. Navigate to CDK8s: `cd ~/stacks/cdk8s`
2. Synthesize all packages: `npx ts-node main-v2.ts`
3. Verify rustdesk-secrets package generated: `ls dist/rustdesk-secrets/manifests/`
4. Deploy via cluster-update: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
5. Wait for ArgoCD sync: Monitor ArgoCD UI for `rustdesk-secrets` application
6. Verify ExternalSecret status: `kubectl get externalsecret rustdesk-password -n default`
7. Verify K8s Secret created: `kubectl get secret rustdesk-password -n default`

**Success Criteria**:
- `dist/rustdesk-secrets/manifests/` directory contains ExternalSecret YAML
- ArgoCD Application `rustdesk-secrets` shows `Synced` and `Healthy`
- ExternalSecret status shows `READY=True`, `STATUS=SecretSynced`
- Kubernetes Secret `rustdesk-password` exists with `password` key

**Dependencies**: T006 (chart registered and configured)

---

## Phase 3: User Story 1 (P1) - Deploy VM with Working RustDesk Service

**Goal**: VMs boot with RustDesk service running within 2 minutes

**Independent Test Criteria**:
- Deploy VM from base image
- Verify RustDesk service is `active (running)` within 2 minutes of boot
- Establish remote desktop connection via RustDesk client
- VM recreation results in same behavior (RustDesk starts automatically)

---

### T008 [US1] [X] - Update Base Image flake.nix with RustDesk Configuration
**Story**: User Story 1 (P1)
**File**: `/etc/nixos/flake.nix` or `/etc/nixos/configuration.nix`
**Description**: Add RustDesk module import and configuration to NixOS base image
**Actions**:
1. SSH to Hetzner host: `ssh root@hetzner-host && cd /etc/nixos`
2. Edit flake.nix (or configuration.nix if using that): `vim flake.nix`
3. Add module import:
   ```nix
   imports = [
     ./modules/services/rustdesk.nix
   ];
   ```
4. Add RustDesk configuration:
   ```nix
   services.rustdesk = {
     enable = true;
     enableSystemService = true;      # System service for headless mode
     enableDirectIpAccess = true;     # Port 21116 direct connections
     user = "root";                   # Required for headless VMs
     package = pkgs.rustdesk-flutter;
     # permanentPassword will be set via cloud-init from Azure Key Vault Secret
   };
   ```
5. Firewall ports are automatically opened by the module (no additional config needed)

**Success Criteria**:
- RustDesk module imported in flake.nix/configuration.nix
- RustDesk service configured with correct options
- Configuration uses declarative NixOS patterns

**Dependencies**: T004 (module updated)

---

### T009 [US1] - Build NixOS Base Image with RustDesk
**Story**: User Story 1 (P1)
**File**: `/etc/nixos/flake.nix`, output: `result` symlink
**Description**: Build NixOS KubeVirt base image with RustDesk pre-configured
**Actions**:
1. From Hetzner host: `cd /etc/nixos`
2. Build base image: `nix build .#nixos-kubevirt-image`
   - **First build**: 20-25 minutes (cold, no cache)
   - **Subsequent builds**: 3-5 minutes (with Attic cache)
3. Verify build succeeded: `ls -lh ./result`
4. Verify RustDesk package included: `nix-store -q --references ./result | grep rustdesk`
5. Expected output: `/nix/store/...-rustdesk-flutter-...`

**Success Criteria**:
- Build completes without errors
- `result` symlink points to Nix store path
- RustDesk package is included in image store references
- Build time is under 25 minutes (cold) or under 5 minutes (cached)

**Dependencies**: T008 (flake.nix updated), T002 (binary cache accessible)

---

### T010 [US1] - Push Base Image to Attic Binary Cache
**Story**: User Story 1 (P1)
**File**: N/A (uses script `deployment/scripts/nix-cache/push-to-cache.sh`)
**Description**: Push built base image Nix store paths to Attic cache for fast rebuilds
**Actions**:
1. From Hetzner host: `cd /etc/nixos`
2. Push to cache: `./deployment/scripts/nix-cache/push-to-cache.sh ./result`
3. Monitor upload progress (may take 10-15 minutes for first push)
4. Verify cache population: `curl http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`

**Success Criteria**:
- Push completes without errors
- Attic cache contains new store paths
- Future rebuilds will use cached artifacts

**Dependencies**: T009 (image built), T002 (Attic accessible)

---

### T011 [US1] - Upload Base Image to MinIO
**Story**: User Story 1 (P1)
**File**: N/A (MinIO object storage)
**Description**: Upload qcow2 base image to MinIO for DataVolume consumption
**Actions**:
1. From Hetzner host: `cd /etc/nixos`
2. Convert to qcow2 if needed: `qemu-img convert -f raw -O qcow2 ./result nixos-kubevirt-v2.qcow2`
   (or just `cp ./result nixos-kubevirt-v2.qcow2` if already qcow2)
3. Upload to MinIO: `mc cp nixos-kubevirt-v2.qcow2 local-minio/images/`
4. Verify upload: `mc ls local-minio/images/nixos-kubevirt-v2.qcow2`
5. Expected: ~1-3 GB file size

**Success Criteria**:
- qcow2 image uploaded to MinIO `images` bucket
- Image is accessible via URL: `http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2`
- File size is reasonable (1-3 GB)

**Dependencies**: T009 (image built), T002 (MinIO accessible)

---

### T012 [US1] [P] - Update NixOsVmChart DataVolume imageURL
**Story**: User Story 1 (P1)
**File**: `cdk8s/charts/infra/nixos-vm-chart.ts`
**Description**: Update DataVolume source to reference new base image in MinIO
**Actions**:
1. Navigate to infra charts: `cd ~/stacks/cdk8s/charts/infra/`
2. Edit nixos-vm-chart.ts: `vim nixos-vm-chart.ts`
3. Locate DataVolume source configuration (around line 50-60)
4. Update imageURL:
   ```typescript
   source: {
     http: {
       url: 'http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2'
     }
   }
   ```
5. Save changes

**Success Criteria**:
- DataVolume imageURL updated to new base image location
- TypeScript compiles without errors
- imageURL is accessible from cluster network

**Dependencies**: T011 (image uploaded to MinIO)

---

### T013 [US1] [P] - Remove Cloud-Init RustDesk Setup from kubevirt-helpers
**Story**: User Story 1 (P1)
**File**: `cdk8s/lib/kubevirt-helpers.ts`
**Description**: Remove cloud-init RustDesk configuration (now handled by base image)
**Actions**:
1. Navigate to helpers: `cd ~/stacks/cdk8s/lib/`
2. Edit kubevirt-helpers.ts: `vim kubevirt-helpers.ts`
3. Find `generateCloudInitUserData` function
4. **Remove** these sections (cloud-init RustDesk setup):
   - RustDesk systemd service creation
   - RustDesk config directory setup (`/root/.config/rustdesk/`)
   - RustDesk permanent password configuration
   - RustDesk headless mode CLI commands
5. **Keep** these sections (still needed):
   - User creation (`users:` section)
   - SSH keys (`ssh_authorized_keys`)
   - Tailscale auth key setup
   - Password configuration (via `chpasswd` using `$RUSTDESK_PASSWORD` env var)

**Success Criteria**:
- Cloud-init no longer contains RustDesk service configuration
- Cloud-init retains user/SSH/Tailscale configuration
- TypeScript compiles without errors

**Dependencies**: T008 (RustDesk in base image)

---

### T014 [US1] - Add VM Environment Variable for RustDesk Password
**Story**: User Story 1 (P1)
**File**: `cdk8s/charts/infra/nixos-vm-chart.ts`
**Description**: Add environment variable referencing rustdesk-password Secret
**Actions**:
1. Edit nixos-vm-chart.ts: `cd ~/stacks/cdk8s/charts/infra/ && vim nixos-vm-chart.ts`
2. Locate VM spec (around line 100-150)
3. Add environment variable to VM:
   ```typescript
   env: [
     {
       name: 'RUSTDESK_PASSWORD',
       valueFrom: {
         secretKeyRef: {
           name: 'rustdesk-password',
           key: 'password'
         }
       }
     }
   ]
   ```
4. Ensure cloud-init userdata references `$RUSTDESK_PASSWORD` for nixos user password

**Success Criteria**:
- VM spec includes RUSTDESK_PASSWORD environment variable
- Environment variable sources value from rustdesk-password Secret
- TypeScript compiles without errors

**Dependencies**: T007 (Secret exists), T013 (cloud-init updated)

---

### T015 [US1] - Synthesize and Deploy Updated VM Manifests
**Story**: User Story 1 (P1)
**Files**: `cdk8s/dist/nixos-dev-datavolume/manifests/`, `cdk8s/dist/nixos-dev-vm/manifests/`
**Description**: Synthesize updated VM charts and deploy via ArgoCD
**Actions**:
1. Navigate to CDK8s: `cd ~/stacks/cdk8s`
2. Synthesize: `npx ts-node main-v2.ts`
3. Verify updated manifests:
   - DataVolume imageURL: `grep -A 5 "source:" dist/nixos-dev-datavolume/manifests/*.yaml`
   - VM environment: `grep -A 10 "env:" dist/nixos-dev-vm/manifests/*.yaml`
4. Deploy: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
5. Monitor ArgoCD sync for `nixos-dev-datavolume` and `nixos-dev-vm` applications

**Success Criteria**:
- Synthesis succeeds without errors
- DataVolume manifest references new image URL
- VM manifest includes RUSTDESK_PASSWORD environment variable
- ArgoCD applications show `Synced` status

**Dependencies**: T012, T013, T014 (all chart updates complete)

---

### T016 [US1] - Verify VM Boots with RustDesk Service Running
**Story**: User Story 1 (P1)
**Files**: VM runtime (kubectl commands)
**Description**: Test that VM boots with RustDesk service active within 2 minutes
**Actions**:
1. Delete old VM to trigger recreation: `kubectl delete vm nixos-dev-vm -n default`
2. Delete old DataVolume: `kubectl delete datavolume nixos-dev-vm-rootdisk -n default`
3. Wait for ArgoCD to recreate resources (sync wave ordering: DataVolume first, then VM)
4. Monitor VM boot: `kubectl get vm,vmi -n default -w`
5. Wait for VMI to reach "Running" phase: `kubectl wait --for=condition=Ready vmi/nixos-dev-vm -n default --timeout=5m`
6. Port-forward SSH: `kubectl port-forward -n default svc/nixos-dev-vm-rdp 2222:22 &`
7. SSH to VM: `ssh -p 2222 nixos@localhost`
8. Check RustDesk service status: `sudo systemctl status rustdesk-headless`
9. Expected output:
   ```
   ● rustdesk-headless.service - RustDesk Headless Service
        Loaded: loaded
        Active: active (running) since ...
   ```
10. Verify headless mode: `sudo cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless`
11. Expected: `allow-linux-headless = "Y"`

**Success Criteria**: ✅ **USER STORY 1 COMPLETE**
- VM boots successfully
- RustDesk service reaches `active (running)` within 2 minutes of boot
- Headless mode is enabled
- Port 21116 is listening: `sudo ss -tlnp | grep 21116`

**Dependencies**: T015 (VM deployed)

---

## Phase 4: User Story 2 (P2) - Update RustDesk Configuration

**Goal**: Enable fast configuration updates via image rebuild

**Independent Test Criteria**:
- Modify RustDesk configuration in base image
- Rebuild image (completes within 5 minutes with cache)
- Deploy new VM with updated configuration
- Verify new VM uses updated config, old VMs unaffected

---

### T017 [US2] - Document Image Rebuild Workflow
**Story**: User Story 2 (P2)
**File**: `docs/RUSTDESK_CONNECTION_GUIDE.md`
**Description**: Update documentation with image rebuild and update workflow
**Actions**:
1. Navigate to docs: `cd ~/stacks/docs/`
2. Edit connection guide: `vim RUSTDESK_CONNECTION_GUIDE.md`
3. Add section: "Updating RustDesk Configuration in Base Image"
4. Document workflow:
   - Update `/etc/nixos/flake.nix` or `configuration.nix`
   - Rebuild image: `nix build .#nixos-kubevirt-image` (3-5 min with cache)
   - Push to Attic cache: `./deployment/scripts/nix-cache/push-to-cache.sh ./result`
   - Upload to MinIO: `mc cp nixos-kubevirt-v2.qcow2 local-minio/images/` (overwrite or version)
   - Update CDK8s chart imageURL if using versioned images
   - Deploy via `cluster-update`
   - Recreate VMs: `kubectl delete vm <vm-name>`
5. Document trade-offs:
   - Configuration changes require VM recreation (not hot-swap)
   - Existing VMs unaffected until manually recreated
   - Rebuild time acceptable for infrequent config changes

**Success Criteria**:
- Documentation clearly explains image rebuild workflow
- Trade-offs between flexibility and reliability documented
- Step-by-step instructions for configuration updates provided

**Dependencies**: T016 (initial deployment verified)

---

### T018 [US2] [P] - Test Configuration Update Workflow
**Story**: User Story 2 (P2)
**File**: `/etc/nixos/flake.nix`, MinIO, Kubernetes
**Description**: Validate that configuration changes propagate correctly
**Actions**:
1. Make a test configuration change on Hetzner host:
   - Edit `/etc/nixos/flake.nix`
   - Example: Change RustDesk port from 21116 to 21117 (for testing only)
2. Rebuild image: `nix build .#nixos-kubevirt-image`
3. Verify rebuild completes in <5 minutes (with cache)
4. Upload new image: `mc cp result local-minio/images/nixos-kubevirt-test.qcow2`
5. Create test VM with new image:
   - Update chart to use `nixos-kubevirt-test.qcow2`
   - Deploy test VM
   - Verify new configuration is active: `ssh test-vm 'sudo ss -tlnp | grep 21117'`
6. Verify existing VM unaffected:
   - Check original VM: `ssh nixos-dev-vm 'sudo ss -tlnp | grep 21116'`
7. Revert test changes (restore port 21116)

**Success Criteria**: ✅ **USER STORY 2 COMPLETE**
- Image rebuild completes within 5 minutes with cache
- New VMs use updated configuration
- Existing VMs remain unaffected
- Configuration propagation workflow validated

**Dependencies**: T017 (workflow documented)

---

### T019 [US2] [P] - Update CLAUDE.md with Base Image Approach
**Story**: User Story 2 (P2)
**File**: `docs/CLAUDE.md`
**Description**: Update CLAUDE.md NixOS VM section to reflect base image approach
**Actions**:
1. Navigate to docs: `cd ~/stacks/docs/`
2. Edit CLAUDE.md: `vim CLAUDE.md`
3. Find "NixOS VMs with RustDesk Remote Desktop" section
4. Update to document:
   - RustDesk pre-configured in base image (not cloud-init)
   - Image rebuild workflow for configuration changes
   - Xvfb virtual framebuffer requirement
   - Binary cache acceleration (3-5 min rebuilds)
   - Remove references to cloud-init RustDesk setup
5. Update example commands to reflect new workflow

**Success Criteria**:
- CLAUDE.md accurately reflects base image approach
- Cloud-init approach documented as "deprecated/unreliable"
- New workflow clearly explained for future developers

**Dependencies**: T017 (workflow documented in connection guide)

---

## Phase 5: User Story 3 (P3) - Troubleshoot RustDesk Issues

**Goal**: Provide diagnostic capabilities for RustDesk issues

**Independent Test Criteria**:
- Intentionally misconfigure RustDesk in base image
- Verify diagnostic logs clearly indicate error source
- Test failure scenarios (service won't start, connections fail)
- Verify troubleshooting documentation is accurate

---

### T020 [US3] [P] - Add RustDesk Build Validation to Image Build
**Story**: User Story 3 (P3)
**File**: `/etc/nixos/flake.nix` or build scripts
**Description**: Add validation step to verify RustDesk is correctly included in image
**Actions**:
1. Create build validation script: `/etc/nixos/scripts/validate-rustdesk-image.sh`
   ```bash
   #!/usr/bin/env bash
   # Validate RustDesk is included in base image
   IMAGE_PATH="$1"

   echo "Validating RustDesk in base image: $IMAGE_PATH"

   # Check 1: RustDesk package present
   if nix-store -q --references "$IMAGE_PATH" | grep -q rustdesk; then
     echo "✅ RustDesk package found"
   else
     echo "❌ RustDesk package NOT found"
     exit 1
   fi

   # Check 2: Xvfb package present (required for headless mode)
   if nix-store -q --references "$IMAGE_PATH" | grep -q xorg.xorgserver; then
     echo "✅ Xvfb package found"
   else
     echo "❌ Xvfb package NOT found"
     exit 1
   fi

   echo "✅ Base image validation passed"
   ```
2. Make script executable: `chmod +x scripts/validate-rustdesk-image.sh`
3. Add to build workflow: After `nix build`, run `./scripts/validate-rustdesk-image.sh ./result`

**Success Criteria**:
- Validation script detects missing RustDesk package
- Validation script detects missing Xvfb dependency
- Build process includes validation step

**Dependencies**: T009 (image build workflow established)

---

### T021 [US3] [P] - Document Troubleshooting Procedures
**Story**: User Story 3 (P3)
**File**: `docs/RUSTDESK_CONNECTION_GUIDE.md`
**Description**: Add comprehensive troubleshooting section to connection guide
**Actions**:
1. Navigate to docs: `cd ~/stacks/docs/`
2. Edit connection guide: `vim RUSTDESK_CONNECTION_GUIDE.md`
3. Add "Troubleshooting" section with:
   - **Issue 1**: RustDesk service not starting
     - Check service logs: `journalctl -u rustdesk-headless --since "5 min ago"`
     - Verify Xvfb running: `systemctl status xvfb`
     - Check config exists: `ls -la /root/.config/rustdesk/RustDesk2.toml`
     - Verify headless mode: `grep allow-linux-headless /root/.config/rustdesk/RustDesk2.toml`
   - **Issue 2**: Service running but connections fail
     - Check port listening: `ss -tlnp | grep 21116`
     - Verify firewall: `iptables -L -n | grep 21116`
     - Test Tailscale connectivity: `ping <VM_POD_IP>`
   - **Issue 3**: Base image build failures
     - Check build logs for RustDesk package errors
     - Verify binary cache accessible: `curl attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`
     - Run validation script: `./scripts/validate-rustdesk-image.sh ./result`
   - **Issue 4**: GL errors (shouldn't occur with headless mode)
     - Verify LIBGL_ALWAYS_SOFTWARE=1: `systemctl show rustdesk-headless | grep Environment`
     - Check Xvfb DISPLAY: `systemctl show xvfb | grep ExecStart`

**Success Criteria**:
- Troubleshooting guide covers all major failure scenarios from spec edge cases
- Each issue has clear diagnostic commands
- Solutions reference specific files and line numbers where applicable

**Dependencies**: T016 (base deployment complete for reference)

---

### T022 [US3] - Add Diagnostic Commands to VM Service
**Story**: User Story 3 (P3)
**File**: `/etc/nixos/modules/services/rustdesk.nix` (optional enhancement)
**Description**: Add systemd service health checks and diagnostic output
**Actions**:
1. SSH to Hetzner host: `ssh root@hetzner-host && cd /etc/nixos`
2. Edit RustDesk module: `vim modules/services/rustdesk.nix`
3. Add ExecStartPost to rustdesk-headless service (around line 78):
   ```nix
   ExecStartPost = pkgs.writeShellScript "rustdesk-healthcheck" ''
     # Wait for service to start
     sleep 5

     # Verify port listening
     if ${pkgs.iproute2}/bin/ss -tlnp | grep -q 21116; then
       echo "✅ RustDesk listening on port 21116"
     else
       echo "⚠️ WARNING: RustDesk not listening on port 21116"
     fi

     # Verify config exists
     if [ -f /root/.config/rustdesk/RustDesk2.toml ]; then
       echo "✅ RustDesk configuration found"
     else
       echo "❌ ERROR: RustDesk configuration missing"
     fi
   '';
   ```
4. Rebuild image to test (optional for this task)

**Success Criteria**:
- Service health check provides diagnostic output
- Logs clearly indicate configuration status
- Failures are easily identifiable in `journalctl` output

**Dependencies**: T004 (module accessible for editing)

---

### T023 [US3] - Test Diagnostic Procedures
**Story**: User Story 3 (P3)
**File**: N/A (testing and validation)
**Description**: Validate troubleshooting procedures by intentionally breaking RustDesk
**Actions**:
1. **Test Scenario 1**: Missing headless mode flag
   - Edit base image config, remove `allow-linux-headless = "Y"`
   - Rebuild image, deploy VM
   - Verify diagnostic logs clearly indicate headless mode not enabled
   - Follow troubleshooting guide to fix
2. **Test Scenario 2**: Xvfb service failure
   - Temporarily disable Xvfb service in module
   - Verify RustDesk service fails with clear dependency error
   - Verify logs point to Xvfb as root cause
3. **Test Scenario 3**: Base image build failure
   - Intentionally misspell RustDesk package name in flake.nix
   - Verify build fails with clear error message
   - Run validation script, verify it detects missing package
4. Document any gaps in troubleshooting guide found during testing

**Success Criteria**: ✅ **USER STORY 3 COMPLETE**
- All test scenarios produce clear diagnostic information
- Troubleshooting guide accurately reflects failure modes
- Diagnostic commands successfully identify root causes

**Dependencies**: T020, T021, T022 (diagnostics and documentation complete)

---

## Phase 6: Polish & Integration

**Goal**: Final documentation updates and cross-cutting concerns

### T024 [P] - Update Debugging Summary with Resolution
**Story**: Polish
**File**: `docs/RUSTDESK_DEBUGGING_SUMMARY.md`
**Description**: Update debugging summary to document successful base image implementation
**Actions**:
1. Navigate to docs: `cd ~/stacks/docs/`
2. Edit debugging summary: `vim RUSTDESK_DEBUGGING_SUMMARY.md`
3. Add new section at end: "## Resolution - Base Image Approach Implemented"
4. Document:
   - Implementation date
   - Final approach chosen (Solution 1 from summary)
   - Key implementation files modified
   - Testing results (success criteria met)
   - Lessons learned vs. initial investigation
5. Update status from "Recommended" to "Implemented"

**Success Criteria**:
- Debugging summary reflects successful implementation
- Closure provided for initial investigation
- Future developers can see full history from problem to solution

**Dependencies**: T016, T018, T023 (all user stories complete)

---

### T025 [P] - Create Implementation Retrospective
**Story**: Polish
**File**: `specs/006-update-our-specification/IMPLEMENTATION_NOTES.md`
**Description**: Document implementation experience for future reference
**Actions**:
1. Create retrospective document in specs directory
2. Document:
   - **What worked well**:
     - Existing NixOS module saved ~30 minutes of development time
     - Binary cache made rebuilds fast (3-5 min vs. 20-25 min)
     - Declarative approach more reliable than cloud-init
   - **Challenges encountered**:
     - [Document any unexpected issues during implementation]
   - **Deviations from plan**:
     - [Document any changes from original plan]
   - **Recommendations for similar features**:
     - Always check for existing NixOS modules before creating new ones
     - Use declarative configuration over imperative scripts when possible
     - Test module updates on host before base image build
3. Include actual time spent vs. estimates

**Success Criteria**:
- Retrospective provides value for future features
- Lessons learned are actionable
- Time tracking helps improve future estimates

**Dependencies**: T024 (all implementation complete)

---

## Dependency Graph

```
Setup Phase (Phase 1):
T001 [P] ──┐
T002 [P] ──┼──> (Independent, can run in parallel)
T003 [P] ──┘

Foundational Phase (Phase 2):
T001 ──> T004 (Update NixOS module)
T003 ──> T005 [P] ──> T006 [P] ──> T007 (ESO chain)

User Story 1 Phase (Phase 3):
T004 ──> T008 ──> T009 ──> T010 [P] ──┐
                           └──> T011 [P] ──> T012 [P] ──┐
                                                          ├──> T015 ──> T016
T004 ──────────────────────────────────> T013 [P] ────>──┤
T007 ──────────────────────────────────> T014 [P] ────>──┘

User Story 2 Phase (Phase 4):
T016 ──> T017 ──> T018 [P] ──┐
                 └──> T019 [P] (Parallel documentation updates)

User Story 3 Phase (Phase 5):
T009 ──> T020 [P] ──┐
T016 ──> T021 [P] ──┼──> T023 (Test diagnostics)
T004 ──> T022 ────>─┘

Polish Phase (Phase 6):
T016, T018, T023 ──> T024 [P] ──┐
                     └──> T025 [P] (Parallel final docs)
```

## Parallel Execution Examples

### Setup Phase (All parallel):
```bash
# Run concurrently:
Terminal 1: Task T001 (Validate module)
Terminal 2: Task T002 (Verify binary cache)
Terminal 3: Task T003 (Verify Azure Key Vault)
```

### User Story 1 - Image Build & Upload (After T009):
```bash
# T010 and T011 can run in parallel
Terminal 1: Task T010 (Push to Attic cache)
Terminal 2: Task T011 (Upload to MinIO)

# After both complete, T012 and T013 can run in parallel
Terminal 1: Task T012 (Update DataVolume imageURL)
Terminal 2: Task T013 (Remove cloud-init RustDesk setup)
```

### User Story 2 - Documentation (After T017):
```bash
# T018 and T019 can run in parallel
Terminal 1: Task T018 (Test configuration update)
Terminal 2: Task T019 (Update CLAUDE.md)
```

---

## Implementation Strategy

### MVP Delivery (Phases 1-3)

**Goal**: Deploy VM with working RustDesk service (User Story 1)

**Tasks**: T001-T016 (16 tasks)
**Time Estimate**: 4-6 hours
**Deliverable**: VM boots with RustDesk service running within 2 minutes

**MVP Validation**:
1. Deploy VM from new base image
2. Verify RustDesk service active within 2 minutes: `systemctl status rustdesk-headless`
3. Establish remote desktop connection via RustDesk client
4. Verify connection ID and password work correctly
5. Recreate VM, verify same behavior (no cloud-init dependency)

### Enhancement 1 (Phase 4)

**Goal**: Configuration update workflow (User Story 2)

**Tasks**: T017-T019 (3 tasks)
**Time Estimate**: 1-2 hours
**Deliverable**: Documented and tested image rebuild workflow

### Enhancement 2 (Phase 5)

**Goal**: Troubleshooting capabilities (User Story 3)

**Tasks**: T020-T023 (4 tasks)
**Time Estimate**: 1-2 hours
**Deliverable**: Diagnostic tools and troubleshooting documentation

### Final Polish (Phase 6)

**Goal**: Documentation and retrospective

**Tasks**: T024-T025 (2 tasks)
**Time Estimate**: 30-60 minutes
**Deliverable**: Complete documentation and lessons learned

---

## Testing & Validation

### Manual Testing (Required for each user story)

**User Story 1 (P1) - Acceptance Criteria**:
- [ ] VM boots successfully from new base image
- [ ] RustDesk service reaches `active (running)` status within 2 minutes
- [ ] Remote desktop connection established successfully
- [ ] Connection ID auto-generated and accessible
- [ ] Password from Azure Key Vault works for authentication
- [ ] VM recreation results in same behavior

**User Story 2 (P2) - Acceptance Criteria**:
- [ ] Configuration change in flake.nix rebuilds image in <5 minutes (with cache)
- [ ] New VM uses updated configuration
- [ ] Existing VMs remain unaffected
- [ ] Workflow documented and reproducible

**User Story 3 (P3) - Acceptance Criteria**:
- [ ] Service failure produces clear diagnostic logs
- [ ] Troubleshooting guide accurately identifies root causes
- [ ] Build validation detects missing RustDesk package
- [ ] Diagnostic commands successfully resolve issues

### Regression Testing (After all phases)

- [ ] Original VM deployment still works (T016)
- [ ] Binary cache improves rebuild time (T010)
- [ ] External Secrets sync password correctly (T007)
- [ ] ArgoCD sync ordering correct (secrets before VM)
- [ ] Documentation is accurate and complete

---

## Success Metrics

### User Story 1 (P1)
- **SC-001**: VMs boot with RustDesk running within 2 minutes ✅
- **SC-002**: RustDesk service start success rate 99%+ ✅
- **SC-006**: Zero cloud-init runcmd failures ✅

### User Story 2 (P2)
- **SC-003**: Image rebuild completes within 5 minutes with cache ✅
- **SC-005**: Configuration propagates to new VMs ✅

### User Story 3 (P3)
- **SC-004**: Diagnostic information clearly indicates error source ✅

### Overall Success
- **Total Tasks**: 25 tasks
- **MVP**: 16 tasks (User Story 1)
- **Parallel Opportunities**: 11 groups
- **Estimated Total Time**: 6-8 hours (MVP: 4-6 hours)

---

## Notes

- **No automated tests required**: Spec doesn't request TDD approach, only manual validation
- **Parallel execution**: Tasks marked [P] can run in parallel with other [P] tasks in same phase
- **Module updates optional**: Tasks T004 (Priority 2 updates) can be skipped if default behavior is acceptable
- **Existing module advantage**: Reusing existing RustDesk module saved ~30 minutes vs. creating new module
- **Binary cache critical**: T010 (push to cache) enables fast rebuilds for User Story 2 workflow

---

**Generated**: 2025-10-14
**Status**: Ready for implementation
**Next Step**: Execute Phase 1 (Setup) tasks T001-T003 in parallel
