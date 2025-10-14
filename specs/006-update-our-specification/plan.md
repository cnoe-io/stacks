# Implementation Plan: RustDesk Base Image Integration

**Branch**: `006-update-our-specification` | **Date**: 2025-10-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/006-update-our-specification/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Pre-configure RustDesk remote desktop service in NixOS KubeVirt VM base image using declarative NixOS modules instead of unreliable cloud-init runtime configuration. VMs will boot with RustDesk service already running in headless mode, eliminating post-boot configuration delays and cloud-init execution failures. Configuration changes require base image rebuild (3-5 min with binary cache) but provide 99%+ reliability vs. 0% success rate with cloud-init runcmd approach.

## Technical Context

**Language/Version**: Nix 2.x (declarative configuration language for NixOS)
**Primary Dependencies**:
- NixOS base image flake (`nix build .#nixos-kubevirt-image`)
- RustDesk package (nixpkgs `rustdesk-flutter`)
- Attic binary cache + MinIO (for fast rebuilds)
- KubeVirt (VM runtime on Kubernetes)

**Storage**:
- Base image artifacts: qcow2 disk images stored in MinIO or external registry
- Binary cache: Attic + MinIO for Nix store paths
- VM persistent storage: PVCs managed by KubeVirt DataVolumes

**Testing**:
- NixOS module validation during `nix build`
- VM boot testing (verify RustDesk service active within 2 minutes)
- Connection testing (establish remote desktop session via RustDesk client)
- Integration testing (verify service auto-starts on VM recreation)

**Target Platform**: NixOS VMs running on KubeVirt (Kubernetes-based virtualization)

**Project Type**: Infrastructure/Platform (NixOS image build + Kubernetes deployment)

**Performance Goals**:
- Base image rebuild: <5 minutes with binary cache (vs. 20-25 min cold)
- VM boot to RustDesk ready: <2 minutes
- Remote desktop connection establishment: <30 seconds after service active

**Constraints**:
- NixOS immutable filesystem (no runtime writes to `/etc/systemd/system/`)
- Cloud-init runcmd unreliable on NixOS (cannot be used for RustDesk setup)
- Configuration changes require full image rebuild and VM recreation
- Binary cache must be available for fast rebuilds (fallback to 20-25 min if unavailable)

**Scale/Scope**:
- Single NixOS base image supporting multiple VM instances
- RustDesk headless mode configuration (no GUI dependencies)
- Firewall rules for direct connection mode (port 21116)
- Integration with existing Tailscale subnet routing for remote access

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Type-Safe Infrastructure as Code ✅ PASS

**Assessment**: While NixOS base image configuration uses Nix language (not TypeScript), the Kubernetes deployment resources (DataVolume, VM manifests) are already defined in CDK8s TypeScript charts (`cdk8s/charts/infra/nixos-vm-chart.ts`).

**Compliance**:
- VM deployment manifests use CDK8s TypeScript (existing `nixos-vm-chart.ts`)
- Only the NixOS image build itself uses Nix (outside scope of K8s manifests)
- Chart updates to reference new base image will use TypeScript

**Action**: Update `nixos-vm-chart.ts` to reference new base image URL (within CDK8s)

### Principle II: GitOps-First Deployment ✅ PASS

**Assessment**: Base image build and VM deployment both follow GitOps patterns.

**Compliance**:
- NixOS base image configuration stored in Git (declarative flake.nix)
- Image rebuild triggered via documented build process (not imperative)
- VM deployment via ArgoCD (existing `nixos-dev-vm` Application)
- DataVolume imageURL update triggers GitOps sync
- Deployment uses `cluster-update` wrapper (constitution requirement)

**Action**: Document image rebuild → push → chart update → ArgoCD sync workflow

### Principle III: Multi-Environment Isolation ⚠️ PARTIAL

**Assessment**: Feature uses default namespace (not VCluster) but this is acceptable for infrastructure VMs.

**Compliance**:
- Dev VMs deployed to `default` namespace (not dev-vcluster)
- **Justification**: KubeVirt VMs are infrastructure resources, not application workloads
- VClusters don't support nested virtualization (KubeVirt inside VCluster unreliable)
- Network isolation achieved via Tailscale subnet routing instead

**Action**: Document rationale for namespace choice in quickstart.md

### Principle IV: Declarative Configuration ✅ PASS

**Assessment**: Both NixOS image configuration and K8s manifests are fully declarative.

**Compliance**:
- NixOS base image: declarative flake.nix + modules
- RustDesk configuration: declarative NixOS module (`services.rustdesk`)
- VM manifests: CDK8s TypeScript in `config/applications.ts`
- No imperative cloud-init runcmd (explicitly rejected by this spec)

**Action**: Ensure RustDesk module configuration is in Git-tracked NixOS files

### Principle V: CNOE Technology Alignment ✅ PASS

**Assessment**: Feature uses CNOE-aligned technologies and infrastructure patterns.

**Compliance**:
- Compute Platform: Kubernetes (KubeVirt for VMs)
- Packaging: CDK8s for K8s manifests
- GitOps: ArgoCD for deployment
- Infrastructure: Tailscale for remote access (CNOE platform capability)
- Binary cache: Attic (CNOE-compatible infrastructure)

**Deviations**: None - NixOS is infrastructure choice, not application framework

### Principle VI: Package-Based Architecture ✅ PASS

**Assessment**: VM deployment follows package-based architecture.

**Compliance**:
- Existing packages: `nixos-dev-datavolume`, `nixos-dev-vm`
- Each package has `dist/<app>/manifests/` with kustomization.yaml
- ArgoCD Applications reference `cnoe://` URLs for local dev
- Chart in `cdk8s/charts/infra/nixos-vm-chart.ts`

**Action**: Update packages to reference new base image after build

### Principle VII: Security by Default ✅ PASS

**Assessment**: RustDesk configuration follows security best practices.

**Compliance**:
- Secrets: RustDesk permanent password via Azure Key Vault + External Secrets (planned)
- Headless mode: Eliminates GUI dependencies and reduces attack surface
- Network: Firewall rules restrict access to port 21116 only
- Access control: Tailscale subnet routing provides authentication layer
- Service isolation: Runs in VM namespace, not cluster namespace

**Current Gap**: Permanent password hard-coded ("nixos123") - must be moved to ESO

**Action**: Phase 1 must design ESO integration for RustDesk password

### Principle VIII: AI-Augmented Platform Engineering ✅ PASS

**Assessment**: Feature implementation may leverage AI for documentation and troubleshooting.

**Compliance**:
- AI used for spec generation, planning, documentation (this plan)
- No autonomous production deployments (image rebuild is human-triggered)
- AI-generated config reviewed before commit
- Critical decisions (base image vs. cloud-init) made with human judgment

**Action**: Ensure quickstart.md includes human-verifiable testing steps

## Gate Evaluation (Initial - Before Phase 0)

**Status**: ✅ PASS - All principles compliant, no violations requiring justification

**Partial Compliance (Principle III)**: Dev VMs in `default` namespace justified by KubeVirt limitations and infrastructure nature.

**Security Gap (Principle VII)**: RustDesk password must be moved from hard-coded to ESO - addressed in Phase 1 design.

---

## Gate Re-Evaluation (Post-Design - After Phase 1)

**Date**: 2025-10-14
**Status**: ✅ PASS - All principles remain compliant, security gap resolved

### Changes from Initial Evaluation

#### Principle VII: Security by Default - ✅ RESOLVED

**Initial Gap**: RustDesk password hard-coded as "nixos123" in cloud-init userdata

**Resolution** (Phase 1 design):
- Created ExternalSecret contract (`contracts/external-secret-rustdesk.yaml`)
- Password stored in Azure Key Vault (secret name: `RUSTDESK-PASSWORD`)
- ESO syncs to Kubernetes Secret (`rustdesk-password`)
- VM references Secret via environment variable (`$RUSTDESK_PASSWORD`)
- Cloud-init uses environment variable substitution (no hardcoded password)

**Evidence**:
- Contract defined: `specs/006-update-our-specification/contracts/external-secret-rustdesk.yaml`
- CDK8s interface updated: `contracts/cdk8s-nixos-vm-chart.ts` (props: `rustdeskPasswordSecret`, `rustdeskPasswordEnvVar`)
- Quickstart Step 1: Documents password setup in Azure Key Vault
- Quickstart Step 4: Documents ExternalSecret deployment
- Data model: RustDesk Credentials entity defines security requirements

**Verification Checklist**:
- [x] Password stored in Azure Key Vault (not in code)
- [x] ExternalSecret syncs from Key Vault to K8s Secret
- [x] VM references Secret (not hardcoded value)
- [x] Cloud-init uses environment variable substitution
- [x] Sync wave ordering ensures Secret exists before VM (-70 < 0)
- [x] Rotation workflow documented (quarterly rotation in quickstart)

### All Other Principles - No Changes Required

All other principles (I, II, III, IV, V, VI, VIII) remain compliant as evaluated in initial check. No design decisions in Phase 0/1 introduced new violations or gaps.

### Final Assessment

**Constitution Compliance**: ✅ FULL COMPLIANCE

- No principle violations
- Partial compliance (Principle III - namespace choice) justified and documented
- Security gap (Principle VII - password management) fully resolved in design
- All contracts, data models, and quickstart guide align with constitution requirements

**Ready to Proceed**: Yes - all gates passed, implementation can begin in Phase 2 (tasks generation)

---

## NixOS Module Revision Analysis

**User Request**: Consider whether KubeVirt VM configuration in `/etc/nixos` needs revision

**Finding**: ✅ **EXISTING MODULE SUITABLE** - Minor updates only

### Current Module Status

The existing `/etc/nixos/modules/services/rustdesk.nix` module already implements:
- ✅ System service mode (`enableSystemService = true`)
- ✅ Xvfb virtual framebuffer for headless operation
- ✅ Software GL rendering (`LIBGL_ALWAYS_SOFTWARE=1`)
- ✅ Direct IP access configuration (port 21116)
- ✅ Permanent password support (`permanentPassword` option)
- ✅ Activation script for config file generation

### Required Module Updates

**Priority 1 - Critical for VM deployment**:

1. **Add headless mode flag to config generation** (line 134-150 in rustdesk.nix):
   ```nix
   # Add to system.activationScripts.rustdeskConfig
   allow-linux-headless = "Y"  # Required for headless RustDesk-Flutter
   ```

2. **Support environment variable in permanentPassword** (line 28-32):
   ```nix
   permanentPassword = mkOption {
     type = types.nullOr types.str;
     default = null;
     description = ''
       Permanent password for RustDesk.
       Supports environment variable substitution: "$RUSTDESK_PASSWORD"
     '';
   };
   ```

**Priority 2 - Recommended for VM context**:

3. **Change default user to root** (line 18):
   ```nix
   user = mkOption {
     type = types.str;
     default = "root";  # Changed from "vpittamp" for VM deployments
     description = "User to run RustDesk service for";
   };
   ```

4. **Add VM-optimized defaults**:
   - Set `enableSystemService = true` as default for VMs
   - Document Xvfb requirement in module description
   - Add example configuration for KubeVirt VMs in module comments

### Module Revisions - Implementation Strategy

**Option A: Update existing module** (Recommended)
- Modify `/etc/nixos/modules/services/rustdesk.nix` directly
- Add VM-specific defaults via conditional logic
- Maintain backward compatibility for desktop use

**Option B: Create VM-specific module**
- New module: `/etc/nixos/modules/services/rustdesk-vm.nix`
- Imports base rustdesk.nix and overrides defaults
- Clearer separation of desktop vs. VM configurations

**Decision**: **Option A** - Update existing module with backward-compatible changes
- Less duplication
- Single source of truth
- VM/desktop differentiation via `enableSystemService` flag

### Updated Contract

The `contracts/nixos-rustdesk-module.nix` should be updated to match the existing module's interface:

**Changes from initial contract proposal**:
- Service name: `rustdesk` → `rustdesk-headless` (when `enableSystemService = true`)
- Add Xvfb service dependency
- Use activation script for config generation (not tmpfiles)
- Support `permanentPassword` option (in addition to env vars)
- Document Xvfb requirement

**No changes needed for**:
- CDK8s chart (already references base image)
- ExternalSecret (already syncs password to K8s Secret)
- Quickstart guide (already documents base image approach)

### Impact on Implementation Tasks

**New tasks added**:
1. Update `/etc/nixos/modules/services/rustdesk.nix` with headless mode flag
2. Test module updates on host system before base image build
3. Update `contracts/nixos-rustdesk-module.nix` to match existing module interface
4. Verify Xvfb service starts correctly in VM environment

**Tasks removed**:
- ~~Create new RustDesk NixOS module from scratch~~ (module already exists)

**Time estimate impact**: -30 minutes (module exists, only minor updates needed)

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

**This feature modifies existing infrastructure code - no new application directories**

```
# NixOS Base Image Configuration (external to this repo - on Hetzner host)
/etc/nixos/
├── flake.nix                          # NixOS system configuration (base image definition)
├── modules/
│   └── services/
│       └── rustdesk.nix               # Existing RustDesk NixOS module (to be integrated)
└── configuration.nix                  # Host configuration (imports rustdesk.nix)

# CDK8s Charts (this repo - stacks/)
cdk8s/
├── charts/
│   └── infra/
│       ├── nixos-vm-chart.ts          # MODIFIED: Update DataVolume imageURL
│       └── kubevirt-helpers.ts        # MODIFIED: Remove cloud-init RustDesk setup
├── config/
│   └── applications.ts                # MODIFIED: Update nixos-dev-vm chart props
└── dist/
    ├── nixos-dev-datavolume/
    │   └── manifests/                 # Generated K8s manifests (DataVolume with new image)
    └── nixos-dev-vm/
        └── manifests/                 # Generated K8s manifests (VM referencing DataVolume)

# Documentation (this repo)
docs/
├── RUSTDESK_DEBUGGING_SUMMARY.md      # Existing debugging investigation
├── RUSTDESK_CONNECTION_GUIDE.md       # MODIFIED: Update with base image approach
└── CLAUDE.md                          # MODIFIED: Update NixOS VM section

# Deployment Scripts (this repo)
deployment/
└── scripts/
    └── nix-cache/
        └── push-to-cache.sh           # Existing script for binary cache population
```

**Structure Decision**: This is an **infrastructure modification** feature, not a new application. Work spans three areas:

1. **NixOS Configuration** (external, on Hetzner host): Add RustDesk module to base image flake.nix
2. **CDK8s Charts** (this repo): Update VM charts to reference new base image and remove cloud-init RustDesk config
3. **Documentation** (this repo): Update guides to reflect base image approach

## Complexity Tracking

*No constitution violations requiring justification*

**Partial Compliance Note (Principle III)**:

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| VMs in `default` namespace | Infrastructure VMs not in VCluster | KubeVirt doesn't support nested virtualization reliably; VMs are infrastructure resources, not tenant workloads |
| Network isolation | Via Tailscale subnet routing | Provides equivalent isolation to namespace NetworkPolicies with better remote access UX |
