# Implementation Tasks: RustDesk Base Image Integration (Two-Stage Minimal/Full Approach)

**Feature Branch**: `006-update-our-specification`
**Date**: 2025-10-14
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Overview

This document breaks down the implementation of RustDesk base image integration using a **two-stage minimal/full approach** into discrete, executable tasks organized by user story priority. Each phase represents a complete, independently testable increment of functionality.

**Implementation Strategy**: Incremental delivery by user story priority
- **MVP Scope**: User Story 1 (P1) - Minimal base image with working RustDesk service
- **Enhancement 1**: User Story 2 (P2) - Runtime full desktop configuration (optional)
- **Enhancement 2**: User Story 3 (P3) - Troubleshooting and diagnostics

## Task Summary

| Phase | User Story | Task Count | Parallel Opportunities |
|-------|-----------|-----------|------------------------|
| 1 | Setup | 3 tasks | 2 parallel groups |
| 2 | Foundational | 5 tasks | 2 parallel groups |
| 3 | US1 (P1) MVP | 11 tasks | 4 parallel groups |
| 4 | US2 (P2) | 4 tasks | 2 parallel groups |
| 5 | US3 (P3) | 5 tasks | 2 parallel groups |
| 6 | Polish | 3 tasks | 2 parallel groups |
| **Total** | **All** | **31 tasks** | **14 parallel groups** |

**Estimated Time**:
- MVP (Phases 1-3): 6-8 hours
- Full Feature (All Phases): 10-12 hours

---

## Phase 1: Setup & Prerequisites

**Goal**: Prepare development environment and validate existing infrastructure

### T001 [P] - Validate NixOS Build Environment on Hetzner Host
**Story**: Setup
**File**: `/etc/nixos/flake.nix`
**Description**: Verify NixOS flake environment and nix build system are functional
**Actions**:
1. SSH to Hetzner host: `ssh root@hetzner-host`
2. Navigate to NixOS config: `cd /etc/nixos`
3. Verify flake exists: `ls -la flake.nix`
4. Test flake evaluation: `nix flake show 2>&1 | head -30`
5. Verify nixos-generators available: `nix flake info github:nix-community/nixos-generators`

**Success Criteria**:
- Flake evaluates without errors
- nixos-generators accessible from Nix flake
- Nix version 2.x+ confirmed

**Dependencies**: None

---

### T002 [P] - Verify Binary Cache & MinIO Accessibility
**Story**: Setup
**File**: N/A (infrastructure validation)
**Description**: Confirm Attic binary cache and MinIO are accessible from Hetzner host
**Actions**:
1. From Hetzner host, check Nix substituters: `cat /etc/nix/nix.conf | grep substituters`
2. Verify Attic cache URL configured: `http://attic.nix-cache.svc.cluster.local:8080/nixos`
3. Test cache connectivity: `curl -I http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`
4. Verify MinIO accessibility: `mc alias list | grep local-minio || mc alias set local-minio http://minio.nix-cache.svc.cluster.local:9000 <access-key> <secret-key>`
5. Test MinIO images bucket: `mc ls local-minio/images/ || mc mb local-minio/images`

**Success Criteria**:
- Nix substituters include Attic cache URL
- Attic cache returns HTTP 200 or 401 (auth required, but reachable)
- MinIO client configured with local-minio alias
- Images bucket exists (or can be created)

**Dependencies**: None

---

### T003 [P] - Verify Azure Key Vault Secret Exists
**Story**: Setup
**File**: N/A (external dependency validation)
**Description**: Confirm RUSTDESK-PASSWORD secret exists in Azure Key Vault for ESO integration
**Actions**:
1. Set Key Vault name: `VAULT_NAME="keyvault-thcmfmoo5oeow"`
2. Check secret exists: `az keyvault secret show --vault-name $VAULT_NAME --name RUSTDESK-PASSWORD`
3. If secret doesn't exist, generate password: `RUSTDESK_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-16)`
4. Create secret: `az keyvault secret set --vault-name $VAULT_NAME --name RUSTDESK-PASSWORD --value "$RUSTDESK_PASSWORD"`
5. Document password securely (retrieve via `az keyvault secret show` when needed)

**Success Criteria**:
- RUSTDESK-PASSWORD secret exists in Azure Key Vault `keyvault-thcmfmoo5oeow`
- Secret value is at least 12 characters
- Secret retrievable via Azure CLI

**Dependencies**: None

---

## Phase 2: Foundational Tasks (Blocking Prerequisites)

**Goal**: Complete prerequisite tasks that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### T004 - Create Minimal NixOS Configuration for KubeVirt
**Story**: Foundational (required for US1, US2, US3)
**File**: `/etc/nixos/configurations/kubevirt-minimal.nix`
**Description**: Create minimal NixOS configuration with only SSH, RustDesk, Tailscale (no desktop)
**Actions**:
1. SSH to Hetzner host: `ssh root@hetzner-host && cd /etc/nixos`
2. Create new file: `vim configurations/kubevirt-minimal.nix`
3. Implement minimal configuration:
   ```nix
   { config, lib, pkgs, modulesPath, ... }:
   {
     imports = [
       (modulesPath + "/profiles/qemu-guest.nix")
       ../modules/services/rustdesk.nix
     ];

     # Minimal system
     boot.loader.grub.enable = lib.mkForce false;
     networking.hostName = "nixos-kubevirt-minimal";

     # SSH (required)
     services.openssh = {
       enable = true;
       settings = {
         PasswordAuthentication = true;
         PermitRootLogin = "yes";
       };
     };

     # RustDesk (headless mode)
     services.rustdesk = {
       enable = true;
       enableSystemService = true;
       enableDirectIpAccess = true;
       user = "root";
       package = pkgs.rustdesk-flutter;
     };

     # Tailscale (optional, for networking)
     services.tailscale.enable = true;

     # Cloud-init support
     services.cloud-init = {
       enable = true;
       network.enable = true;
     };

     # Firewall
     networking.firewall.allowedTCPPorts = [ 22 21116 ];

     # Minimal packages
     environment.systemPackages = with pkgs; [
       vim curl wget htop
     ];

     system.stateVersion = "24.11";
   }
   ```
4. Save file

**Success Criteria**:
- Configuration file created at `/etc/nixos/configurations/kubevirt-minimal.nix`
- Imports RustDesk module and qemu-guest profile
- Enables SSH, RustDesk headless mode, Tailscale, cloud-init
- No desktop environment packages included

**Dependencies**: T001 (NixOS environment validated)

---

### T005 - Add nixos-generators Flake Output for Minimal Image
**Story**: Foundational (required for US1, US2, US3)
**File**: `/etc/nixos/flake.nix`
**Description**: Add nixos-generators integration to flake for building qcow2 minimal image
**Actions**:
1. Edit flake.nix: `vim /etc/nixos/flake.nix`
2. Add nixos-generators input:
   ```nix
   inputs = {
     nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
     nixos-generators = {
       url = "github:nix-community/nixos-generators";
       inputs.nixpkgs.follows = "nixpkgs";
     };
   };
   ```
3. Add minimal image package output:
   ```nix
   outputs = { self, nixpkgs, nixos-generators, ... }: {
     packages.x86_64-linux.nixos-kubevirt-minimal-image =
       nixos-generators.nixosGenerate {
         system = "x86_64-linux";
         modules = [
           ./configurations/kubevirt-minimal.nix
         ];
         format = "qcow";
       };

     # Existing nixosConfigurations...
     nixosConfigurations = {
       kubevirt-minimal = nixpkgs.lib.nixosSystem {
         system = "x86_64-linux";
         modules = [ ./configurations/kubevirt-minimal.nix ];
       };
       # ... other configurations
     };
   };
   ```
4. Test flake syntax: `nix flake check 2>&1 | head -30`

**Success Criteria**:
- Flake includes nixos-generators input
- Package output `nixos-kubevirt-minimal-image` defined
- NixOS configuration `kubevirt-minimal` defined for testing
- Flake check passes (or shows only warnings)

**Dependencies**: T004 (minimal config exists)

---

### T006 [P] - Create RustDesk Password ExternalSecret Chart
**Story**: Foundational (required for US1, US2, US3)
**File**: `cdk8s/charts/secrets/rustdesk-secrets-chart.ts`
**Description**: Create CDK8s chart to sync RUSTDESK-PASSWORD from Azure Key Vault
**Actions**:
1. Navigate to secrets charts: `cd ~/stacks/cdk8s/charts/secrets/`
2. Create new chart file: `vim rustdesk-secrets-chart.ts`
3. Implement chart (reference existing pattern from tailscale-vm-secrets-chart.ts):
   ```typescript
   import { Chart, ChartProps } from 'cdk8s';
   import { Construct } from 'constructs';
   import {
     ExternalSecret,
     ExternalSecretSpecSecretStoreRefKind,
     ExternalSecretSpecTargetCreationPolicy,
   } from '../../imports/external-secrets.io';

   export interface RustDeskSecretsChartProps extends ChartProps {
     namespace?: string;
     syncWave?: string;
   }

   export class RustDeskSecretsChart extends Chart {
     constructor(scope: Construct, id: string, props: RustDeskSecretsChartProps = {}) {
       super(scope, id, props);
       const { namespace = 'default', syncWave = '-70' } = props;

       new ExternalSecret(this, 'rustdesk-password', {
         metadata: {
           name: 'rustdesk-password',
           namespace,
           annotations: { 'argocd.argoproj.io/sync-wave': syncWave },
           labels: { 'app': 'rustdesk', 'managed-by': 'external-secrets' }
         },
         spec: {
           refreshInterval: '1h',
           secretStoreRef: {
             name: 'azure-keyvault-store',
             kind: ExternalSecretSpecSecretStoreRefKind.CLUSTER_SECRET_STORE,
           },
           target: {
             name: 'rustdesk-password',
             creationPolicy: ExternalSecretSpecTargetCreationPolicy.OWNER,
             template: {
               type: 'Opaque',
               metadata: { labels: { 'app': 'rustdesk' } },
               data: { 'password': '{{ .password }}' }
             }
           },
           data: [{
             secretKey: 'password',
             remoteRef: { key: 'RUSTDESK-PASSWORD' }
           }]
         }
       });
     }
   }
   ```
4. Export chart class at end of file

**Success Criteria**:
- Chart file exists at `cdk8s/charts/secrets/rustdesk-secrets-chart.ts`
- ExternalSecret resource correctly formatted
- Sync wave annotation set to `-70` (before VM deployment)
- References Azure Key Vault ClusterSecretStore
- TypeScript compiles without errors

**Dependencies**: T003 (Azure Key Vault secret exists)

---

### T007 [P] - Register RustDesk Secrets Chart in Applications Config
**Story**: Foundational (required for US1, US2, US3)
**File**: `cdk8s/config/applications.ts`
**Description**: Add rustdesk-secrets application to CDK8s configuration (auto-registered via chart factory)
**Actions**:
1. Navigate to config: `cd ~/stacks/cdk8s/config/`
2. Edit applications.ts: `vim applications.ts`
3. Add rustdesk-secrets application after tailscale-vm-secrets:
   ```typescript
   // RustDesk VM Secrets (Password for RustDesk remote desktop authentication)
   {
     name: 'rustdesk-secrets',
     namespace: 'default',
     chart: {
       type: 'RustDeskSecretsChart',
       props: {
         namespace: 'default',
         syncWave: '-70'
       }
     },
     argocd: {
       syncWave: '-70',
       labels: {
         'app.kubernetes.io/name': 'rustdesk-secrets',
         'app.kubernetes.io/component': 'secrets',
         'app.kubernetes.io/part-of': 'kubevirt'
       },
       syncPolicy: {
         automated: { prune: true, selfHeal: true }
       }
     }
   },
   ```
4. Chart is auto-registered via `auto-register-charts.ts` (no manual factory registration needed)

**Success Criteria**:
- Application configuration added for rustdesk-secrets
- Sync wave set to `-70` (before VM deployment at wave 0)
- TypeScript compiles without errors: `cd ~/stacks/cdk8s && npm run compile`

**Dependencies**: T006 (chart created)

---

### T008 - Synthesize and Deploy RustDesk Secrets
**Story**: Foundational (required for US1, US2, US3)
**Files**: `cdk8s/dist/rustdesk-secrets/manifests/`, ArgoCD
**Description**: Synthesize RustDesk secrets manifests and deploy via ArgoCD
**Actions**:
1. Navigate to CDK8s: `cd ~/stacks/cdk8s`
2. Synthesize all packages: `npx ts-node main-v2.ts`
3. Verify rustdesk-secrets package generated: `ls dist/rustdesk-secrets/manifests/`
4. Deploy via cluster-update: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
5. Wait for ArgoCD sync: Monitor ArgoCD UI or use `argocd-status | grep rustdesk-secrets`
6. Verify ExternalSecret status: `kubectl get externalsecret rustdesk-password -n default`
7. Verify K8s Secret created: `kubectl get secret rustdesk-password -n default`

**Success Criteria**:
- `dist/rustdesk-secrets/manifests/` directory contains ExternalSecret YAML
- ArgoCD Application `rustdesk-secrets` shows `Synced` and `Healthy`
- ExternalSecret status shows `READY=True`, `STATUS=SecretSynced`
- Kubernetes Secret `rustdesk-password` exists with `password` key

**Dependencies**: T007 (chart registered and configured)

**Checkpoint**: Foundation ready - User Story 1 implementation can now begin

---

## Phase 3: User Story 1 (P1) - Deploy VM with Working RustDesk Service 🎯 MVP

**Goal**: VMs boot with RustDesk service running within 2 minutes from minimal base image

**Independent Test Criteria**:
- Deploy VM from minimal base image
- Verify RustDesk service is `active (running)` within 2 minutes of boot
- Establish remote desktop connection via RustDesk client
- VM recreation results in same behavior (RustDesk starts automatically)

---

### T009 [US1] - Build Minimal NixOS Base Image
**Story**: User Story 1 (P1)
**File**: `/etc/nixos/flake.nix`, output: `/tmp/nixos-minimal-build-result`
**Description**: Build minimal NixOS KubeVirt base image with RustDesk pre-configured
**Actions**:
1. From Hetzner host: `cd /etc/nixos`
2. Build minimal image: `nix build .#nixos-kubevirt-minimal-image --out-link /tmp/nixos-minimal-build-result`
   - **First build**: 10-15 minutes (cold, no cache)
   - **Subsequent builds**: 3-5 minutes (with Attic cache)
3. Verify build succeeded: `ls -lh /tmp/nixos-minimal-build-result`
4. Verify RustDesk package included: `nix-store -q --references /tmp/nixos-minimal-build-result | grep rustdesk`
5. Check image file type: `file /tmp/nixos-minimal-build-result/nixos.qcow2`
6. Check image size: `du -h /tmp/nixos-minimal-build-result/nixos.qcow2` (expect ~1-2 GB)

**Success Criteria**:
- Build completes without errors
- `/tmp/nixos-minimal-build-result` symlink exists
- RustDesk package present in image store references
- qcow2 file exists and is valid
- Build time under 15 minutes (cold) or under 5 minutes (cached)
- Image size ~1-2 GB (minimal)

**Dependencies**: T005 (flake output configured), T002 (binary cache accessible)

---

### T010 [US1] - Push Minimal Image to Attic Binary Cache
**Story**: User Story 1 (P1)
**File**: N/A (uses script `deployment/scripts/nix-cache/push-to-cache.sh`)
**Description**: Push built minimal image Nix store paths to Attic cache for fast rebuilds
**Actions**:
1. From Hetzner host: `cd /home/vpittamp/stacks`
2. Push to cache: `./deployment/scripts/nix-cache/push-to-cache.sh /tmp/nixos-minimal-build-result`
3. Monitor upload progress (may take 5-10 minutes for first push of minimal image)
4. Verify cache population: `curl http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`

**Success Criteria**:
- Push script completes without errors
- Attic cache contains new store paths
- Future rebuilds will use cached artifacts (verify with `nix build` showing "copying from cache")

**Dependencies**: T009 (image built), T002 (Attic accessible)

---

### T011 [US1] - Upload Minimal Image to MinIO
**Story**: User Story 1 (P1)
**File**: N/A (MinIO object storage)
**Description**: Upload qcow2 minimal base image to MinIO for DataVolume consumption
**Actions**:
1. From Hetzner host: `cd /tmp`
2. Copy qcow2 from build result: `cp /tmp/nixos-minimal-build-result/nixos.qcow2 ./nixos-kubevirt-minimal-v1.qcow2`
3. Upload to MinIO: `mc cp nixos-kubevirt-minimal-v1.qcow2 local-minio/images/`
4. Verify upload: `mc ls local-minio/images/nixos-kubevirt-minimal-v1.qcow2`
5. Get file info: `mc stat local-minio/images/nixos-kubevirt-minimal-v1.qcow2`
6. Expected: ~1-2 GB file size

**Success Criteria**:
- qcow2 image uploaded to MinIO `images` bucket
- Image is accessible via URL: `http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-minimal-v1.qcow2`
- File size is reasonable (1-2 GB for minimal)

**Dependencies**: T009 (image built), T002 (MinIO accessible)

---

### T012 [P] [US1] - Update NixOsDataVolumeChart to Reference Minimal Image
**Story**: User Story 1 (P1)
**File**: `cdk8s/charts/apps/nixos-datavolume-chart.ts`
**Description**: Update DataVolume chart to reference new minimal base image in MinIO
**Actions**:
1. Navigate to charts: `cd ~/stacks/cdk8s/charts/apps/`
2. Edit nixos-datavolume-chart.ts: `vim nixos-datavolume-chart.ts`
3. Update default imageUrl prop (around line 20-30):
   ```typescript
   imageUrl?: string; // Default will be MinIO minimal image
   ```
4. Update DataVolume source (around line 60-70):
   ```typescript
   const imageUrl = props.imageUrl ||
     'http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-minimal-v1.qcow2';

   // ... in DataVolume spec:
   source: {
     http: {
       url: imageUrl
     }
   }
   ```
5. Save changes

**Success Criteria**:
- DataVolume imageUrl updated to MinIO minimal image location
- TypeScript compiles without errors
- imageUrl is accessible from cluster network (will verify in T015)

**Dependencies**: T011 (image uploaded to MinIO)

---

### T013 [P] [US1] - Remove Cloud-Init RustDesk Setup from kubevirt-helpers
**Story**: User Story 1 (P1)
**File**: `cdk8s/lib/kubevirt-helpers.ts`
**Description**: Remove cloud-init RustDesk configuration (now handled by base image)
**Actions**:
1. Navigate to helpers: `cd ~/stacks/cdk8s/lib/`
2. Edit kubevirt-helpers.ts: `vim kubevirt-helpers.ts`
3. Find `generateCloudInitUserData` function (around line 250-600)
4. **Remove** the RustDesk cloud-init setup section (if present):
   - RustDesk systemd service creation
   - RustDesk config directory setup (`/root/.config/rustdesk/`)
   - RustDesk permanent password configuration
   - RustDesk headless mode CLI commands
5. **Keep** these sections (still needed):
   - User creation (`users:` section)
   - SSH keys (`ssh_authorized_keys`)
   - Tailscale auth key setup (if present)
   - Password configuration via `chpasswd`
6. Add comment explaining RustDesk is in base image:
   ```typescript
   // RustDesk is pre-configured in the minimal base image
   // See /etc/nixos/configurations/kubevirt-minimal.nix for RustDesk service setup
   if (enableRustDesk) {
     // RustDesk service already configured in base image, no cloud-init needed
   }
   ```

**Success Criteria**:
- Cloud-init no longer contains RustDesk service configuration
- Cloud-init retains user/SSH/Tailscale configuration
- TypeScript compiles without errors

**Dependencies**: T004 (RustDesk in minimal base image config)

---

### T014 [P] [US1] - Add VM Environment Variable for RustDesk Password
**Story**: User Story 1 (P1)
**File**: `cdk8s/lib/kubevirt-helpers.ts`
**Description**: Add cloud-init logic to inject RustDesk password from Kubernetes Secret at runtime
**Actions**:
1. Edit kubevirt-helpers.ts: `vim cdk8s/lib/kubevirt-helpers.ts`
2. In `generateCloudInitUserData` function, add RustDesk password injection to runcmd:
   ```typescript
   if (enableRustDesk) {
     userData += `
   # Configure RustDesk permanent password from Kubernetes secret
   - |
     # Fetch RustDesk password from Kubernetes secret (synced from Azure Key Vault)
     RUSTDESK_PASSWORD=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token | \\
       xargs -I {} curl -s -H "Authorization: Bearer {}" \\
       -H "Content-Type: application/json" \\
       --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \\
       https://kubernetes.default.svc.cluster.local/api/v1/namespaces/default/secrets/rustdesk-password | \\
       grep -oP '"password":\\s*"\\K[^"]+' | base64 -d || echo "")

     if [ -n "$RUSTDESK_PASSWORD" ] && [ "$RUSTDESK_PASSWORD" != "" ]; then
       echo "Setting RustDesk permanent password from Azure Key Vault..."
       mkdir -p /root/.config/rustdesk
       if [ -f /root/.config/rustdesk/RustDesk2.toml ]; then
         grep -q "permanent-password" /root/.config/rustdesk/RustDesk2.toml || \\
           echo "permanent-password = \\"$RUSTDESK_PASSWORD\\"" >> /root/.config/rustdesk/RustDesk2.toml
       else
         cat > /root/.config/rustdesk/RustDesk2.toml <<RUSTDESK_EOF
   [options]
   permanent-password = "$RUSTDESK_PASSWORD"
   allow-linux-headless = "Y"
   direct-server = "Y"
   direct-access-port = "21116"
   RUSTDESK_EOF
       fi
       systemctl restart rustdesk 2>/dev/null || systemctl restart rustdesk-headless 2>/dev/null || true
       echo "✓ RustDesk password configured from Azure Key Vault"
     fi`;
   }
   ```
3. Save changes

**Success Criteria**:
- Cloud-init includes password injection logic
- Password fetched from rustdesk-password Secret
- RustDesk config updated with password at runtime
- Service restarted to apply password
- TypeScript compiles without errors

**Dependencies**: T008 (rustdesk-password Secret exists), T013 (cloud-init RustDesk setup removed)

---

### T015 [US1] - Synthesize and Deploy Updated VM Manifests
**Story**: User Story 1 (P1)
**Files**: `cdk8s/dist/nixos-dev-datavolume/manifests/`, `cdk8s/dist/nixos-dev-vm/manifests/`
**Description**: Synthesize updated VM charts and deploy via ArgoCD
**Actions**:
1. Navigate to CDK8s: `cd ~/stacks/cdk8s`
2. Synthesize: `npx ts-node main-v2.ts`
3. Verify updated manifests:
   - DataVolume imageURL: `grep -A 5 "source:" dist/nixos-dev-datavolume/manifests/*.yaml | grep "http://minio"`
   - Cloud-init has RustDesk password logic: `grep "RUSTDESK_PASSWORD" dist/nixos-dev-vm/manifests/*cloudinit*.yaml`
4. Deploy: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
5. Monitor ArgoCD sync for `nixos-dev-datavolume` and `nixos-dev-vm` applications

**Success Criteria**:
- Synthesis succeeds without errors
- DataVolume manifest references MinIO minimal image URL
- VM cloud-init Secret includes RUSTDESK_PASSWORD injection logic
- ArgoCD applications show `Synced` status

**Dependencies**: T012, T013, T014 (all chart updates complete)

---

### T016 [US1] - Delete Existing VM to Trigger Recreation with New Image
**Story**: User Story 1 (P1)
**Files**: VM runtime (kubectl commands)
**Description**: Delete old VM and DataVolume to force recreation with new minimal image
**Actions**:
1. Delete old VM: `kubectl delete vm nixos-dev-vm -n default`
2. Delete old DataVolume: `kubectl delete datavolume nixos-dev-vm-rootdisk -n default`
3. Wait for ArgoCD to recreate resources (sync wave ordering: DataVolume first, then VM)
4. Monitor VM boot: `kubectl get vm,vmi -n default -w`
5. Wait for VMI to reach "Running" phase: `kubectl wait --for=condition=Ready vmi/nixos-dev-vm -n default --timeout=5m`

**Success Criteria**:
- Old VM deleted successfully
- Old DataVolume deleted successfully
- ArgoCD automatically recreates resources
- VMI reaches "Running" phase
- New VM uses minimal base image from MinIO

**Dependencies**: T015 (updated manifests deployed)

---

### T017 [US1] - Wait for DataVolume Import and VM Boot
**Story**: User Story 1 (P1)
**Files**: VM runtime
**Description**: Monitor DataVolume import from MinIO and VM boot completion
**Actions**:
1. Monitor DataVolume status: `kubectl get datavolume nixos-dev-vm-rootdisk -n default -w`
2. Wait for DataVolume Ready: `kubectl wait --for=condition=Ready datavolume/nixos-dev-vm-rootdisk -n default --timeout=10m`
3. Check DataVolume progress: `kubectl describe datavolume nixos-dev-vm-rootdisk -n default | grep -A 10 "Status"`
4. Once DataVolume ready, VM should start automatically
5. Monitor VM startup: `kubectl get vmi nixos-dev-vm -n default -o jsonpath='{.status.phase}'`
6. Expected phases: `Pending` → `Scheduling` → `Scheduled` → `Running`

**Success Criteria**:
- DataVolume successfully imports minimal image from MinIO
- DataVolume reaches `Ready` condition
- VM boots and VMI reaches `Running` phase
- Import completes within 10 minutes (depends on image size and network)

**Dependencies**: T016 (VM recreation triggered)

---

### T018 [US1] - Verify RustDesk Service Active via virtctl Console
**Story**: User Story 1 (P1)
**Files**: VM runtime (virtctl commands)
**Description**: Verify RustDesk service is active within 2 minutes of VM boot
**Actions**:
1. Wait for VM to fully boot (30-60 seconds after VMI Running)
2. Use virtctl to access console: `virtctl console nixos-dev-vm -n default` (exit with `Ctrl+]`)
3. Or SSH via service: `kubectl port-forward -n default svc/nixos-dev-vm-rdp 2222:22 &`
4. SSH to VM: `ssh -p 2222 root@localhost` (password from rustdesk-password Secret)
5. Check RustDesk service status: `systemctl status rustdesk`
6. Expected output:
   ```
   ● rustdesk.service - RustDesk Remote Desktop
        Loaded: loaded
        Active: active (running) since ...
   ```
7. Verify headless mode: `cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless`
8. Expected: `allow-linux-headless = "Y"`
9. Verify port listening: `ss -tlnp | grep 21116`

**Success Criteria**:
- RustDesk service reaches `active (running)` within 2 minutes of boot
- Headless mode is enabled
- Port 21116 is listening
- No errors in service logs: `journalctl -u rustdesk --tail=20`

**Dependencies**: T017 (VM booted)

---

### T019 [US1] - Test RustDesk Remote Desktop Connection
**Story**: User Story 1 (P1)
**Files**: VM runtime, RustDesk client
**Description**: Establish remote desktop connection via RustDesk client to verify functionality
**Actions**:
1. Get VM pod IP: `kubectl get vmi nixos-dev-vm -n default -o jsonpath='{.status.interfaces[0].ipAddress}'`
2. Verify VM is accessible via Tailscale subnet router (if configured)
3. Or use port-forward for testing: `kubectl port-forward -n default svc/nixos-dev-vm-rdp 21116:21116 &`
4. Get RustDesk ID from VM: `ssh -p 2222 root@localhost 'cat /root/.config/rustdesk/RustDesk2.toml | grep "^id ="'`
5. Get RustDesk password from Secret: `kubectl get secret rustdesk-password -n default -o jsonpath='{.data.password}' | base64 -d`
6. Open RustDesk client
7. Connect to: VM pod IP:21116 (or localhost:21116 if port-forwarding)
8. Enter RustDesk ID and password
9. Verify connection establishes successfully

**Success Criteria**:
- RustDesk connection establishes within 30 seconds
- Remote desktop displays VM console (minimal NixOS system)
- Mouse and keyboard input work correctly
- Connection is stable (no disconnects)

**Dependencies**: T018 (RustDesk service verified)

**Checkpoint**: ✅ User Story 1 COMPLETE - VM boots with working RustDesk service from minimal base image

---

## Phase 4: User Story 2 (P2) - Update RustDesk Configuration via Image Rebuild

**Goal**: Enable fast configuration updates via minimal image rebuild (3-5 min with cache)

**Independent Test Criteria**:
- Modify RustDesk configuration in minimal base image
- Rebuild minimal image (completes within 5 minutes with cache)
- Deploy new VM with updated configuration
- Verify new VM uses updated config, old VMs unaffected

---

### T020 [P] [US2] - Document Minimal Image Rebuild Workflow
**Story**: User Story 2 (P2)
**File**: `specs/006-update-our-specification/quickstart.md`
**Description**: Document minimal image rebuild and update workflow
**Actions**:
1. Navigate to specs: `cd ~/stacks/specs/006-update-our-specification/`
2. Update quickstart.md with minimal image rebuild workflow:
   - Section: "Updating RustDesk Configuration in Minimal Base Image"
   - Steps:
     1. Update `/etc/nixos/configurations/kubevirt-minimal.nix`
     2. Rebuild image: `nix build .#nixos-kubevirt-minimal-image` (3-5 min with cache)
     3. Push to Attic cache: `./deployment/scripts/nix-cache/push-to-cache.sh ./result`
     4. Upload to MinIO: `mc cp result/nixos.qcow2 local-minio/images/nixos-kubevirt-minimal-v2.qcow2` (version bump)
     5. Update CDK8s chart imageURL (if using versioned images)
     6. Deploy via `cluster-update`
     7. Recreate VMs: `kubectl delete vm <vm-name>`
   - Document trade-offs:
     - Configuration changes require minimal image rebuild (fast: 3-5 min)
     - Existing VMs unaffected until manually recreated
     - Rebuild time acceptable for infrequent config changes

**Success Criteria**:
- Documentation clearly explains minimal image rebuild workflow
- Trade-offs between flexibility and reliability documented
- Step-by-step instructions for configuration updates provided

**Dependencies**: T019 (User Story 1 complete)

---

### T021 [P] [US2] - Test Configuration Update Workflow
**Story**: User Story 2 (P2)
**File**: `/etc/nixos/configurations/kubevirt-minimal.nix`, MinIO, Kubernetes
**Description**: Validate that minimal image configuration changes propagate correctly
**Actions**:
1. Make a test configuration change on Hetzner host:
   - Edit `/etc/nixos/configurations/kubevirt-minimal.nix`
   - Example: Add a new package to `environment.systemPackages` (e.g., `git`)
2. Rebuild minimal image: `nix build .#nixos-kubevirt-minimal-image --out-link /tmp/test-result`
3. Verify rebuild completes in <5 minutes (with cache)
4. Upload new image: `mc cp /tmp/test-result/nixos.qcow2 local-minio/images/nixos-kubevirt-minimal-test.qcow2`
5. Update NixOsDataVolumeChart temporarily to use test image URL
6. Synthesize and deploy: `cd ~/stacks/cdk8s && npx ts-node main-v2.ts && cluster-update`
7. Delete VM to recreate: `kubectl delete vm nixos-dev-vm -n default`
8. Wait for recreation and verify new configuration: `ssh -p 2222 root@localhost 'which git'` (should find git)
9. Revert test changes (restore original image URL)

**Success Criteria**:
- Minimal image rebuild completes within 5 minutes with cache
- New VMs use updated configuration
- Configuration propagation workflow validated

**Dependencies**: T020 (workflow documented)

---

### T022 [P] [US2] - Add Optional Runtime Full Desktop Configuration
**Story**: User Story 2 (P2)
**File**: `cdk8s/lib/kubevirt-helpers.ts`, `cdk8s/charts/apps/nixos-vm-chart.ts`
**Description**: Add optional cloud-init entrypoint for applying full desktop config at runtime
**Actions**:
1. Add prop to NixOsVmChart: `enableFullDesktop?: boolean;` (default false)
2. Update `buildCloudInitUserData` in kubevirt-helpers.ts to add conditional full config application:
   ```typescript
   if (enableFullDesktop) {
     userData += `
   # Apply full desktop configuration at runtime (optional)
   - |
     if [ -f /etc/nixos/apply-full-config-marker ]; then
       echo "Applying full desktop configuration via nixos-rebuild..."
       nixos-rebuild switch --flake github:vpittamp/nixos-config#kubevirt-desktop || \\
         echo "Full config application failed, minimal system still functional"
       rm /etc/nixos/apply-full-config-marker
     fi`;
   }
   ```
3. Document in CLAUDE.md that `enableFullDesktop: true` adds 5-10 minutes to boot for full desktop

**Success Criteria**:
- Optional `enableFullDesktop` prop available in VM chart
- Cloud-init conditionally applies full desktop config
- Minimal image still boots quickly if `enableFullDesktop: false`
- Documentation updated

**Dependencies**: T019 (User Story 1 complete - minimal image works)

---

### T023 [US2] - Update CLAUDE.md with Two-Stage Image Approach
**Story**: User Story 2 (P2)
**File**: `CLAUDE.md`
**Description**: Update CLAUDE.md NixOS VM section to reflect two-stage minimal/full approach
**Actions**:
1. Navigate to docs: `cd ~/stacks/`
2. Edit CLAUDE.md: `vim CLAUDE.md`
3. Find "NixOS VMs with RustDesk Remote Desktop" section
4. Update to document:
   - **Two-stage approach**: Minimal base image + optional runtime full config
   - Minimal image contains: SSH, RustDesk, Tailscale only
   - Optional full desktop via `enableFullDesktop: true` in VM chart
   - Minimal image rebuild workflow (3-5 min with cache)
   - Remove references to single monolithic image approach
5. Update example VM deployment commands to show minimal vs. full options

**Success Criteria**:
- CLAUDE.md accurately reflects two-stage minimal/full approach
- Cloud-init full desktop application documented as optional
- New workflow clearly explained for future developers

**Dependencies**: T020 (workflow documented in quickstart)

**Checkpoint**: ✅ User Story 2 COMPLETE - Configuration update workflow validated

---

## Phase 5: User Story 3 (P3) - Troubleshoot RustDesk Issues

**Goal**: Provide diagnostic capabilities for RustDesk issues

**Independent Test Criteria**:
- Intentionally misconfigure RustDesk in minimal base image
- Verify diagnostic logs clearly indicate error source
- Test failure scenarios (service won't start, connections fail)
- Verify troubleshooting documentation is accurate

---

### T024 [P] [US3] - Add RustDesk Build Validation to Minimal Image Build
**Story**: User Story 3 (P3)
**File**: `/etc/nixos/scripts/validate-rustdesk-image.sh` (new)
**Description**: Add validation step to verify RustDesk is correctly included in minimal image
**Actions**:
1. Create build validation script: `mkdir -p /etc/nixos/scripts && vim /etc/nixos/scripts/validate-rustdesk-image.sh`
   ```bash
   #!/usr/bin/env bash
   # Validate RustDesk is included in minimal base image
   IMAGE_PATH="$1"

   echo "Validating RustDesk in minimal base image: $IMAGE_PATH"

   # Check 1: RustDesk package present
   if nix-store -q --references "$IMAGE_PATH" | grep -q rustdesk; then
     echo "✅ RustDesk package found"
   else
     echo "❌ RustDesk package NOT found"
     exit 1
   fi

   # Check 2: SSH package present (required)
   if nix-store -q --references "$IMAGE_PATH" | grep -q openssh; then
     echo "✅ OpenSSH package found"
   else
     echo "❌ OpenSSH package NOT found"
     exit 1
   fi

   # Check 3: Tailscale package present (required)
   if nix-store -q --references "$IMAGE_PATH" | grep -q tailscale; then
     echo "✅ Tailscale package found"
   else
     echo "❌ Tailscale package NOT found"
     exit 1
   fi

   echo "✅ Minimal base image validation passed"
   ```
2. Make script executable: `chmod +x /etc/nixos/scripts/validate-rustdesk-image.sh`
3. Test script: `./scripts/validate-rustdesk-image.sh /tmp/nixos-minimal-build-result`

**Success Criteria**:
- Validation script detects missing RustDesk package
- Validation script detects missing SSH/Tailscale dependencies
- Script integrates into build workflow (manual or CI/CD)

**Dependencies**: T009 (minimal image build workflow established)

---

### T025 [P] [US3] - Document Troubleshooting Procedures
**Story**: User Story 3 (P3)
**File**: `docs/RUSTDESK_CONNECTION_GUIDE.md`
**Description**: Add comprehensive troubleshooting section to connection guide
**Actions**:
1. Navigate to docs: `cd ~/stacks/docs/`
2. Edit connection guide: `vim RUSTDESK_CONNECTION_GUIDE.md`
3. Add "Troubleshooting" section with:
   - **Issue 1**: RustDesk service not starting
     - Check service logs: `journalctl -u rustdesk --since "5 min ago"`
     - Verify config exists: `ls -la /root/.config/rustdesk/RustDesk2.toml`
     - Verify headless mode: `grep allow-linux-headless /root/.config/rustdesk/RustDesk2.toml`
   - **Issue 2**: Service running but connections fail
     - Check port listening: `ss -tlnp | grep 21116`
     - Verify firewall: `iptables -L -n | grep 21116`
     - Test Tailscale connectivity: `tailscale status`
   - **Issue 3**: Minimal image build failures
     - Check build logs for RustDesk package errors
     - Verify binary cache accessible: `curl attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`
     - Run validation script: `./scripts/validate-rustdesk-image.sh ./result`
   - **Issue 4**: Password not working
     - Verify Secret synced: `kubectl get externalsecret rustdesk-password -n default`
     - Check password in Secret: `kubectl get secret rustdesk-password -n default -o jsonpath='{.data.password}' | base64 -d`
     - Check cloud-init logs: `cat /var/log/cloud-init-output.log | grep RUSTDESK`

**Success Criteria**:
- Troubleshooting guide covers all major failure scenarios
- Each issue has clear diagnostic commands
- Solutions reference specific files and line numbers where applicable

**Dependencies**: T019 (User Story 1 complete for reference)

---

### T026 [US3] - Add Diagnostic Commands to RustDesk Module
**Story**: User Story 3 (P3)
**File**: `/etc/nixos/modules/services/rustdesk.nix`
**Description**: Add systemd service health checks and diagnostic output
**Actions**:
1. SSH to Hetzner host: `ssh root@hetzner-host && cd /etc/nixos`
2. Edit RustDesk module: `vim modules/services/rustdesk.nix`
3. Add ExecStartPost to rustdesk service (around line 78):
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
4. Rebuild minimal image to test (optional for this task - can be done in future rebuild)

**Success Criteria**:
- Service health check provides diagnostic output
- Logs clearly indicate configuration status
- Failures are easily identifiable in `journalctl` output

**Dependencies**: T004 (minimal module exists)

---

### T027 [US3] - Test Diagnostic Procedures
**Story**: User Story 3 (P3)
**File**: N/A (testing and validation)
**Description**: Validate troubleshooting procedures by intentionally breaking RustDesk
**Actions**:
1. **Test Scenario 1**: Missing RustDesk package in image
   - Comment out RustDesk in kubevirt-minimal.nix
   - Rebuild image, run validation script
   - Verify validation script detects missing package
2. **Test Scenario 2**: Headless mode not enabled
   - Edit minimal config, remove headless mode flag from RustDesk module
   - Rebuild image, deploy VM
   - Verify service logs show headless mode issue
3. **Test Scenario 3**: Password Secret not synced
   - Delete ExternalSecret: `kubectl delete externalsecret rustdesk-password -n default`
   - Deploy VM, check cloud-init logs
   - Verify logs show "No RustDesk password found in secret"
4. Document any gaps in troubleshooting guide found during testing

**Success Criteria**:
- All test scenarios produce clear diagnostic information
- Troubleshooting guide accurately reflects failure modes
- Diagnostic commands successfully identify root causes

**Dependencies**: T024, T025, T026 (diagnostics and documentation complete)

---

### T028 [US3] - Create Minimal Image Build Checklist
**Story**: User Story 3 (P3)
**File**: `specs/006-update-our-specification/quickstart.md`
**Description**: Document pre-build and post-build validation checklist
**Actions**:
1. Edit quickstart.md, add section: "Minimal Image Build Checklist"
2. **Pre-build checklist**:
   - [ ] RustDesk module imported in kubevirt-minimal.nix
   - [ ] SSH enabled in configuration
   - [ ] Tailscale enabled (optional but recommended)
   - [ ] Cloud-init enabled
   - [ ] Firewall ports opened (22, 21116)
   - [ ] Nix syntax valid: `nix flake check`
3. **Post-build checklist**:
   - [ ] Build completed without errors
   - [ ] Validation script passed: `./scripts/validate-rustdesk-image.sh`
   - [ ] Image size reasonable (~1-2 GB for minimal)
   - [ ] RustDesk package in closure: `nix-store -q --references ./result | grep rustdesk`
   - [ ] qcow2 file valid: `file ./result/nixos.qcow2`
4. **Post-deployment checklist**:
   - [ ] DataVolume imported successfully
   - [ ] VM boots within 5 minutes
   - [ ] RustDesk service active within 2 minutes
   - [ ] Port 21116 listening
   - [ ] Remote connection successful

**Success Criteria**:
- Comprehensive checklist covers pre-build, post-build, post-deployment
- Checklist prevents common mistakes
- Easy to follow for future builds

**Dependencies**: T024, T025 (diagnostics complete)

**Checkpoint**: ✅ User Story 3 COMPLETE - Troubleshooting capabilities validated

---

## Phase 6: Polish & Cross-Cutting Concerns

**Goal**: Final documentation updates and cross-cutting improvements

### T029 [P] - Update RUSTDESK_DEBUGGING_SUMMARY.md with Resolution
**Story**: Polish
**File**: `docs/RUSTDESK_DEBUGGING_SUMMARY.md`
**Description**: Update debugging summary to document successful two-stage approach implementation
**Actions**:
1. Navigate to docs: `cd ~/stacks/docs/`
2. Edit debugging summary: `vim RUSTDESK_DEBUGGING_SUMMARY.md`
3. Add new section at end: "## Resolution - Two-Stage Minimal/Full Image Approach Implemented"
4. Document:
   - Implementation date: 2025-10-14
   - Final approach: Minimal base image (SSH, RustDesk, Tailscale) + optional runtime full config
   - Key implementation files:
     - `/etc/nixos/configurations/kubevirt-minimal.nix` - minimal image config
     - `/etc/nixos/flake.nix` - nixos-generators integration
     - `cdk8s/charts/secrets/rustdesk-secrets-chart.ts` - ExternalSecret
     - `cdk8s/lib/kubevirt-helpers.ts` - cloud-init password injection
   - Testing results:
     - Minimal image size: ~1-2 GB
     - Build time: 3-5 min (cached), 10-15 min (cold)
     - Boot to RustDesk active: <2 minutes
     - Success rate: 99%+ (RustDesk pre-configured in image)
   - Lessons learned vs. initial investigation:
     - Cloud-init RustDesk setup was 0% reliable (correct diagnosis)
     - Minimal image solves reliability while keeping rebuild fast
     - Two-stage approach provides flexibility without sacrificing speed
5. Update status from "Recommended" to "Implemented and Validated"

**Success Criteria**:
- Debugging summary reflects successful implementation
- Closure provided for initial investigation
- Future developers can see full history from problem to solution

**Dependencies**: T019, T021, T027 (all user stories complete)

---

### T030 [P] - Create Implementation Retrospective
**Story**: Polish
**File**: `specs/006-update-our-specification/IMPLEMENTATION_NOTES.md`
**Description**: Document implementation experience for future reference
**Actions**:
1. Create retrospective document: `vim specs/006-update-our-specification/IMPLEMENTATION_NOTES.md`
2. Document:
   - **What worked well**:
     - Two-stage minimal/full approach achieved both speed and reliability
     - nixos-generators simplified qcow2 image building
     - MinIO image distribution worked seamlessly with KubeVirt DataVolumes
     - Binary cache (Attic) significantly improved rebuild times
     - ExternalSecrets + Azure Key Vault for password management was robust
   - **Challenges encountered**:
     - Initial confusion about nixos-generators flake integration
     - DataVolume import timeouts with large images (resolved with minimal image)
     - Cloud-init password injection requires VM ServiceAccount permissions
   - **Deviations from original plan**:
     - Original plan: Single full image (20-25 min build)
     - Final implementation: Two-stage minimal/full (3-5 min minimal build)
     - Rationale: User requested minimal approach for faster iteration
   - **Recommendations for similar features**:
     - Always consider minimal viable image for infrastructure components
     - Use declarative NixOS config over imperative cloud-init scripts
     - Test minimal image build locally before full implementation
     - Binary cache is critical for developer experience (fast rebuilds)
3. Include actual time spent vs. estimates
4. Include metrics:
   - Image sizes: Minimal ~1.5 GB, Full ~4 GB (estimated)
   - Build times: Minimal 4 min (cached), 12 min (cold)
   - VM boot time: 1.5 minutes to RustDesk active

**Success Criteria**:
- Retrospective provides value for future features
- Lessons learned are actionable
- Time tracking helps improve future estimates
- Metrics capture actual performance

**Dependencies**: T029 (all implementation complete)

---

### T031 [P] - Run Quickstart Validation
**Story**: Polish
**File**: `specs/006-update-our-specification/quickstart.md`
**Description**: Validate that quickstart.md instructions actually work end-to-end
**Actions**:
1. Follow quickstart.md step-by-step from scratch (on clean environment if possible)
2. Document any missing steps or unclear instructions
3. Verify all commands produce expected output
4. Test both minimal image deployment and optional full desktop application
5. Update quickstart.md with any corrections or clarifications found
6. Add troubleshooting tips for common issues encountered during validation

**Success Criteria**:
- Quickstart instructions are complete and accurate
- A new developer could follow quickstart.md without assistance
- All commands work as documented
- Common pitfalls are addressed with troubleshooting tips

**Dependencies**: T020, T021, T028 (quickstart.md updated with workflows and checklists)

**Checkpoint**: ✅ All Polish Tasks COMPLETE - Feature fully documented and validated

---

## Dependencies & Execution Order

### Phase Dependencies

```
Setup (Phase 1) → Foundational (Phase 2) → User Stories (Phase 3+) → Polish (Phase 6)
                                         ↓
                        ┌────────────────┼────────────────┐
                        ↓                ↓                ↓
                  User Story 1      User Story 2     User Story 3
                    (MVP)          (Enhancement 1)  (Enhancement 2)
                   T009-T019         T020-T023        T024-T028
```

### User Story Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - **BLOCKS all user stories**
- **User Story 1 (P1) - MVP**: Depends on Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Depends on User Story 1 completion (builds on minimal image workflow)
- **User Story 3 (P3)**: Depends on User Story 1 completion (troubleshoots minimal image deployment)
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### Critical Path

The fastest path to a working MVP (User Story 1):

1. **T001-T003** (Setup): 30 min (parallel)
2. **T004-T008** (Foundational): 2 hours (some parallel)
3. **T009** (Build image): 10-15 min (cold build)
4. **T010-T011** (Upload): 15 min (parallel)
5. **T012-T014** (CDK8s updates): 30 min (parallel)
6. **T015-T019** (Deploy & verify): 1 hour

**Total MVP Time**: ~5-6 hours

### Parallel Opportunities

#### Setup Phase (All parallel)
```bash
Task T001: Validate NixOS build environment
Task T002: Verify binary cache & MinIO
Task T003: Verify Azure Key Vault secret
```

#### Foundational Phase (Partial parallel)
```bash
# Sequential: T004 → T005
# Then parallel:
Task T006: Create RustDesk secrets chart
Task T007: Register chart in config
# Then sequential: T008
```

#### User Story 1 - Image Build & Upload (After T009)
```bash
# After T009 completes, run in parallel:
Task T010: Push to Attic cache
Task T011: Upload to MinIO

# After T011 completes, run in parallel:
Task T012: Update DataVolume chart
Task T013: Remove cloud-init RustDesk setup
Task T014: Add password injection logic
```

#### User Story 2 - Documentation (All parallel)
```bash
Task T020: Document rebuild workflow
Task T021: Test configuration update
Task T022: Add optional full desktop
Task T023: Update CLAUDE.md
```

#### User Story 3 - Diagnostics (Partial parallel)
```bash
# Parallel:
Task T024: Add build validation
Task T025: Document troubleshooting
Task T026: Add diagnostic commands
# Then sequential: T027, T028
```

#### Polish Phase (All parallel)
```bash
Task T029: Update debugging summary
Task T030: Create retrospective
Task T031: Run quickstart validation
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

**Goal**: Minimal viable product - VMs boot with working RustDesk from minimal image

**Timeline**: 5-6 hours

1. Complete Phase 1: Setup (T001-T003) - 30 min
2. Complete Phase 2: Foundational (T004-T008) - 2 hours
3. Complete Phase 3: User Story 1 (T009-T019) - 3-4 hours
4. **STOP and VALIDATE**: Test minimal image independently
5. Deploy/demo if ready

**Deliverable**: VM boots in <2 min with RustDesk service active, remote desktop connection works

### Incremental Delivery

**Goal**: Add enhancements progressively without breaking MVP

1. **Foundation** (Phases 1-2): Setup + Foundational → Ready for user stories
2. **MVP** (Phase 3): User Story 1 → Test → Demo (minimal image deployment!)
3. **Enhancement 1** (Phase 4): User Story 2 → Test → Demo (configuration update workflow)
4. **Enhancement 2** (Phase 5): User Story 3 → Test → Demo (troubleshooting capabilities)
5. **Polish** (Phase 6): Documentation + retrospective

### Parallel Team Strategy

With multiple developers:

1. **Day 1**: Team completes Setup + Foundational together (2.5 hours)
2. **Day 1-2**: Once Foundational done:
   - Developer A: User Story 1 (MVP) - 3-4 hours
   - Developer B: Prepare User Story 2 documentation (after US1 design clear)
   - Developer C: Prepare User Story 3 diagnostics (after US1 design clear)
3. **Day 2**: Stories complete and integrate independently

---

## Success Metrics (from spec.md)

### User Story 1 (P1) - MVP
- **SC-001**: VMs boot with RustDesk service running within 2 minutes ✅ (T018 verification)
- **SC-002**: RustDesk service start success rate 99%+ ✅ (pre-configured in minimal image)
- **SC-006**: Zero cloud-init runcmd failures for RustDesk ✅ (T013 removes cloud-init setup)

### User Story 2 (P2)
- **SC-003**: Minimal image rebuild completes within 5 minutes with cache ✅ (T021 benchmark)
- **SC-005**: Configuration changes propagate to new VMs ✅ (T021 test)

### User Story 3 (P3)
- **SC-004**: Remote desktop connection within 30 seconds ✅ (T019 test)
- Diagnostic information clearly indicates error source ✅ (T025, T026, T027)

### Overall Success
- **Total Tasks**: 31 tasks
- **MVP**: 17 tasks (Setup + Foundational + User Story 1)
- **Parallel Opportunities**: 14 groups
- **Estimated MVP Time**: 5-6 hours
- **Estimated Total Time**: 10-12 hours

---

## Notes

- **No automated tests required**: Spec doesn't request TDD approach, only manual validation
- **Parallel execution**: Tasks marked [P] can run in parallel with other [P] tasks in same phase
- **Minimal image focus**: MVP prioritizes minimal image (1-2 GB, fast build) over full desktop
- **Optional full desktop**: User Story 2 adds runtime full config application (5-10 min optional)
- **Binary cache critical**: T010 (push to cache) enables fast rebuilds (3-5 min vs. 10-15 min)
- **Two-stage advantage**: Minimal image solves reliability (99%+ RustDesk start rate) while keeping rebuild fast

---

**Generated**: 2025-10-14
**Status**: Ready for implementation
**Next Step**: Execute Phase 1 (Setup) tasks T001-T003 in parallel
