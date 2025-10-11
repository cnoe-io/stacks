# Implementation Plan: KubeVirt Installation with NixOS VM Images

**Branch**: `002-i-want-to` | **Date**: 2025-10-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-i-want-to/spec.md`

## Summary

Install KubeVirt virtualization platform into Kind cluster using CDK8s charts, enabling virtual machine management alongside containerized workloads. Integrate custom NixOS/home-manager configurations as VM base images through Containerized Data Importer (CDI). Deploy via ArgoCD following GitOps patterns with type-safe Kubernetes resource definitions.

**Core Capabilities**: KubeVirt operator deployment, NixOS qcow2 image import via DataVolumes, VirtualMachine lifecycle management (start/stop/console access), GitOps-based VM resource deployment, configurable PVC retention policies.

**Technical Approach**:
- Import KubeVirt CRDs into CDK8s for type-safe VirtualMachine definitions
- Deploy KubeVirt with software emulation (useEmulation: true) for Kind compatibility
- Use Containerized Data Importer (CDI) to import NixOS qcow2 images into PVCs
- Define VirtualMachine resources in CDK8s charts with DataVolume references
- Deploy via ArgoCD with sync wave ordering (KubeVirt/CDI before VirtualMachines)

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s synthesis), NixOS unstable (VM image builds)
**Primary Dependencies**:
- `cdk8s` (v2.x) - Kubernetes manifest synthesis
- `cdk8s-plus-32` - High-level Kubernetes API (selective use)
- KubeVirt operator (v1.x) - VM management
- Containerized Data Importer (CDI) - VM disk image import
- `nixos-generators` - qcow2 VM image creation from NixOS configs
- `virtctl` CLI - VirtualMachine console access and operations

**Storage**:
- PersistentVolumeClaims (local-path-provisioner for Kind cluster)
- DataVolumes (CDI abstraction for image import to PVCs)
- NixOS qcow2 images (hosted via HTTP server - nginx with hostPath volume mount)
- **CRITICAL**: qcow2 files must be regular files, not symlinks (symlinks to Nix store break inside containers)

**Testing**:
- TypeScript compilation (`npm run compile`)
- CDK8s synthesis validation (`npx ts-node main-v2.ts`)
- Kubernetes manifest validation (`kubectl diff`)
- Integration testing (ArgoCD sync, VM boot to console)

**Target Platform**:
- Local development: Kind cluster (single-node, software emulation)
- Future production: Multi-node Kubernetes with nested virtualization or bare metal

**Project Type**: Infrastructure (CDK8s charts in `cdk8s/charts/`, synthesis to `cdk8s/dist/`)

**Performance Goals**:
- KubeVirt deployment: <5 minutes to all pods Running
- VM boot time: <3 minutes from start to console login
- DataVolume import: <10 minutes for 10GB qcow2 images
- ArgoCD sync: <3 minutes for VirtualMachine resource changes

**Constraints**:
- Kind cluster: Software emulation only (QEMU without KVM), single-node (no live migration)
- Resource limits: VMs default to 2 CPU cores, 4GB RAM (Kind cluster capacity constraints)
- Storage: ReadWriteOnce PVC access mode (local-path-provisioner limitation)
- Network: Pod network integration (masquerade mode), no strict isolation

**Scale/Scope**:
- Multiple NixOS VM configurations (development, testing, specialized workloads)
- Concurrent VMs limited by Kind cluster resources (2-4 VMs typical for 16GB host)
- Single namespace for VMs (future: multi-namespace with RBAC)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Type-Safe Infrastructure as Code ✅ PASS

**Requirement**: All Kubernetes manifests MUST be defined using CDK8s with TypeScript.

**Compliance**:
- ✅ KubeVirt CRDs will be imported via `npm run import` for type-safe VirtualMachine definitions
- ✅ All VirtualMachine, DataVolume, KubeVirt resources defined in CDK8s charts
- ✅ Use `imports/k8s` for exact YAML control of CRD resources
- ✅ TypeScript compilation enforced before synthesis (`npm run compile`)
- ✅ Chart classes extend `Chart` from `cdk8s` library

**Evidence**: FR-003, FR-013 (type-safe VirtualMachine CRD bindings), SC-007 (TypeScript compilation passes)

### Principle II: GitOps-First Deployment ✅ PASS

**Requirement**: All platform services MUST be deployed via ArgoCD. Use cluster-menu.sh for idpbuilder operations.

**Compliance**:
- ✅ KubeVirt deployed via ArgoCD Application with sync wave -100
- ✅ VirtualMachine resources deployed via ArgoCD with automated sync
- ✅ `cnoe://<package>/manifests` source URL for local development
- ✅ Sync waves control ordering: KubeVirt/CDI before VirtualMachines
- ✅ Automated sync policy with prune and selfHeal
- ✅ Deployment via `cluster-update` wrapper (cluster-menu.sh)

**Evidence**: FR-005, FR-019, FR-020, FR-021, FR-022, FR-023 (ArgoCD integration), US-004 (GitOps lifecycle)

### Principle III: Multi-Environment Isolation ⚠️ DEFERRED

**Requirement**: Dev/staging MUST use VClusters, production MUST use dedicated clusters/namespaces.

**Compliance**:
- ⚠️ Initial implementation: Single environment (local Kind cluster)
- 📋 Future work: Multi-environment VirtualMachine deployments with environment-specific configs
- 📋 VMs will support parameterized chart props for environment-specific resource allocation

**Justification**: KubeVirt installation is infrastructure-level (runs on host cluster, not in VClusters). VirtualMachine resources can be deployed to VClusters in Phase 2.

**Evidence**: Assumption #6 (single-node Kind cluster), FR-006 (declarative configuration for future parameterization)

### Principle IV: Declarative Configuration ✅ PASS

**Requirement**: All configuration MUST be declared in code, no manual imperative scripts (except bootstrapping).

**Compliance**:
- ✅ KubeVirt configuration declared in `config/applications.ts`
- ✅ Chart registered in `IdpBuilderChartFactory`
- ✅ VirtualMachine specs defined in CDK8s charts (not manual kubectl)
- ✅ DataVolume image sources declared in chart properties
- ✅ No environment variables or ConfigMaps outside CDK8s synthesis

**Evidence**: FR-004, FR-006 (declarative configuration), FR-013 (VirtualMachine resources in charts), US-004 (version-controlled VMs)

### Principle V: CNOE Technology Alignment ✅ PASS

**Requirement**: Platform choices MUST align with CNOE-endorsed technologies.

**Compliance**:
- ✅ CDK8s for packaging & templating (CNOE-endorsed)
- ✅ ArgoCD for continuous delivery (CNOE-endorsed)
- ✅ Kubernetes compute platform (CNOE-endorsed)
- ✅ Git-based configuration management (CNOE-endorsed)
- ℹ️ KubeVirt: VM management on Kubernetes (extends CNOE compute platform)

**Justification**: KubeVirt extends Kubernetes compute platform with VM workloads, aligns with CNOE principle of Kubernetes as de-facto operating environment.

**Evidence**: Constitution Principle V (Compute Platform: Kubernetes), architecture alignment with CNOE stack

### Principle VI: Package-Based Architecture ✅ PASS

**Requirement**: All applications MUST be self-contained packages with manifests, kustomization.yaml, ArgoCD Application.

**Compliance**:
- ✅ KubeVirt package: `cdk8s/dist/kubevirt/manifests/` with kustomization.yaml
- ✅ VirtualMachine packages: Separate packages per VM group (e.g., nixos-vms)
- ✅ ArgoCD Application manifests in `cdk8s/dist/<app>.yaml`
- ✅ Chart organization: `cdk8s/charts/infra/` for KubeVirt, `cdk8s/charts/apps/` for VMs
- ✅ Shared helpers in `cdk8s/lib/` (sync-wave builders, kustomization generator)

**Evidence**: FR-001 (kubevirt namespace), FR-019 (synthesis to dist/), FR-020 (ArgoCD Application manifests)

### Principle VII: Security by Default ⚠️ PARTIAL

**Requirement**: All workloads MUST implement security best practices (SecurityContext, resource limits, NetworkPolicies).

**Compliance**:
- ✅ VirtualMachines will define resource limits (2 CPU, 4GB RAM defaults)
- ⚠️ VirtualMachinePods (virt-launcher) SecurityContext: Controlled by KubeVirt operator (uses privileged mode for VM emulation)
- ⚠️ NetworkPolicies: Not required for development environment (full pod network access per FR-026)
- ✅ RBAC: KubeVirt ServiceAccounts follow least privilege (defined by operator)
- ⚠️ Secrets: NixOS cloud-init secrets (SSH keys, passwords) SHOULD use ESO in production

**Justification**:
- KubeVirt's virt-launcher pods require elevated privileges for VM emulation (QEMU process management)
- Development environment doesn't require network isolation (per clarified requirements)
- Production deployments SHOULD add NetworkPolicies and ESO for cloud-init secrets

**Evidence**: FR-028 (resource limits), FR-026 (network access), Assumption #9 (network isolation not required for dev)

**Action Items for Production**:
- [ ] Add NetworkPolicies for VM namespace ingress/egress
- [ ] Use ESO for cloud-init secrets (SSH keys, user passwords)
- [ ] Review virt-launcher SecurityContext for minimal privilege escalation

### Principle VIII: AI-Augmented Platform Engineering ⚠️ NOT APPLICABLE

**Requirement**: AI agents MAY be used for automation/observability with human approval for production changes.

**Compliance**: N/A - This feature does not involve AI agents or kagent integration.

**Future Consideration**: kagent agents could assist with VM troubleshooting, resource optimization, or NixOS configuration generation.

---

### Gate Status: ✅ APPROVED WITH CONDITIONS

**Passing Gates**: I, II, IV, V, VI (5/8 applicable)
**Deferred**: III (multi-environment - Phase 2)
**Partial**: VII (security - acceptable for dev, production hardening required)
**Not Applicable**: VIII (no AI agents)

**Proceed to Phase 0**: ✅ YES

**Required Actions**:
1. ✅ Phase 0: Resolved - Using HTTP server (nginx) with hostPath volume mount
2. ✅ Phase 1: Documented - virt-launcher requires privileges for VM emulation (acceptable for dev)
3. Phase 2: Add production security hardening (NetworkPolicies, ESO for secrets)

**Implementation Status** (Updated 2025-10-11):
- ✅ KubeVirt and CDI operators deployed successfully
- ✅ Image server (nginx) serving qcow2 files via HTTP
- ✅ DataVolume import completed (100MB test image validated, 21GB production image ready)
- ✅ VirtualMachine running with runStrategy: Always
- ✅ All sync waves validated and working correctly
- ✅ Chart implementation patterns established (ApiObject for CRDs)
- ✅ Dynamic kind-config generation fixed in deployment script

## Project Structure

### Documentation (this feature)

```
specs/002-i-want-to/
├── spec.md              # Feature specification (/speckit.specify output)
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0: Technology research and decisions
├── data-model.md        # Phase 1: CRD schemas and VM configurations
├── quickstart.md        # Phase 1: Developer guide for creating NixOS VMs
├── contracts/           # Phase 1: API contracts and schemas
│   ├── kubevirt-crd-imports.yaml    # KubeVirt CRD definitions
│   └── nixos-vm-schema.yaml         # NixOS VM configuration schema
├── checklists/          # Quality validation checklists
│   └── requirements.md  # Requirements checklist (from /speckit.specify)
└── tasks.md             # Phase 2: Implementation tasks (/speckit.tasks - NOT yet created)
```

### Source Code (repository root)

```
cdk8s/
├── charts/
│   ├── infra/
│   │   ├── kubevirt-chart.ts            # KubeVirt operator deployment
│   │   ├── cdi-chart.ts                 # Containerized Data Importer deployment
│   │   └── kubevirt-rbac-chart.ts       # KubeVirt RBAC (if needed beyond operator defaults)
│   └── apps/
│       ├── nixos-vm-chart.ts            # Parameterized NixOS VirtualMachine chart
│       └── nixos-datavolume-chart.ts    # DataVolume for NixOS image import
│
├── lib/
│   ├── kubevirt-helpers.ts              # Shared VirtualMachine builders (cloud-init, resources)
│   └── datavolume-helpers.ts            # DataVolume source configuration helpers
│
├── config/
│   └── applications.ts                  # KubeVirt and NixOS VM application configs
│
├── imports/
│   ├── kubevirt.io.ts                   # KubeVirt CRDs (VirtualMachine, VirtualMachineInstance)
│   └── cdi.kubevirt.io.ts               # CDI CRDs (DataVolume)
│
└── dist/                                # Synthesis output
    ├── kubevirt/
    │   ├── manifests/                   # KubeVirt operator manifests
    │   │   ├── kubevirt-namespace.yaml
    │   │   ├── kubevirt-operator.yaml
    │   │   ├── kubevirt-cr.yaml
    │   │   └── kustomization.yaml
    │   └── kubevirt.yaml                # ArgoCD Application for KubeVirt
    │
    ├── cdi/
    │   ├── manifests/                   # CDI operator manifests
    │   │   └── ...
    │   └── cdi.yaml                     # ArgoCD Application for CDI
    │
    └── nixos-vms/
        ├── manifests/                   # NixOS VirtualMachine resources
        │   ├── nixos-dev-datavolume.yaml
        │   ├── nixos-dev-vm.yaml
        │   └── kustomization.yaml
        └── nixos-vms.yaml               # ArgoCD Application for VMs

/etc/nixos/                              # Existing NixOS flake (referenced, not modified in stacks repo)
├── flake.nix                            # Multi-system flake (hetzner, m1, wsl, container)
├── configurations/
│   ├── base.nix                         # Shared base config (REUSED for VMs)
│   ├── hetzner.nix                      # Full desktop environment (too large for VMs)
│   └── vm-minimal.nix                   # NEW: Minimal KubeVirt VM config (imports base.nix)
│
└── modules/                             # Existing NixOS modules (not needed for minimal VMs)

stacks/                                  # This repository
├── nixos-images/                        # Built VM images (gitignored)
│   └── kubevirt-vm.qcow2                # qcow2 image built from /etc/nixos#vm-minimal
│
└── cdk8s/                               # CDK8s charts (unchanged)
    └── ...
```

**Structure Decision**:

This feature uses **Infrastructure + Application pattern with External NixOS Config**:

1. **Infrastructure charts** (`cdk8s/charts/infra/`): KubeVirt and CDI operators (platform-level, deployed once)
2. **Application charts** (`cdk8s/charts/apps/`): VirtualMachine and DataVolume resources (per-VM deployments)
3. **NixOS configurations** (`/etc/nixos/`): External flake-based config, referenced but not modified in stacks repo
4. **VM images** (`stacks/nixos-images/`): Built qcow2 images (gitignored), served via HTTP or pushed to OCI registry

**Rationale for using /etc/nixos**:
- ✅ **Reuses existing base.nix**: SSH keys, user config (`vpittamp`), core packages (vim, git, tmux, jq)
- ✅ **Consistency with Hetzner**: Same base configuration ensures familiar environment
- ✅ **Maintains flake inputs**: Leverages existing nixpkgs, home-manager, nix-community inputs
- ✅ **Minimal image size**: New `vm-minimal.nix` imports only base.nix + cloud-init (no desktop, ~1-2GB)
- ✅ **Separation of concerns**: NixOS config managed in `/etc/nixos`, Kubernetes manifests in `stacks/cdk8s`

The separation enables:
- KubeVirt platform deployment independent of VM resources
- Reusable NixOS VM chart with parameterized configurations
- Multiple NixOS configurations with distinct VM images (add more configs to /etc/nixos#nixosConfigurations)
- Clear dependency chain: KubeVirt/CDI → DataVolumes → VirtualMachines

## Post-Design Constitution Re-Evaluation

*Re-evaluated after Phase 1 (Design & Contracts) completion*

### Changes Since Initial Evaluation

**New Findings**:
1. ✅ **NixOS Configuration Reuse**: Design leverages existing `/etc/nixos#base.nix` config, aligning with Principle IV (Declarative Configuration)
2. ✅ **VM Image Build Process**: Research confirmed nixos-generators approach, maintains flake-based workflow
3. ✅ **HTTP Image Hosting**: Research selected HTTP server for Phase 1 (simple, CDI-native), OCI registry for Phase 2 (versioned, production-ready)

**Updated Compliance**:

| Principle | Initial Status | Post-Design Status | Notes |
|-----------|----------------|-------------------|-------|
| I. Type-Safe IaC | ✅ PASS | ✅ PASS | CRD import spec created, TypeScript bindings confirmed |
| II. GitOps-First | ✅ PASS | ✅ PASS | Quickstart.md confirms cluster-menu.sh usage |
| III. Multi-Environment | ⚠️ DEFERRED | ⚠️ DEFERRED | No change (Phase 2) |
| IV. Declarative Config | ✅ PASS | ✅ PASS | **Enhanced**: Reuses /etc/nixos flake, no new config silos |
| V. CNOE Alignment | ✅ PASS | ✅ PASS | KubeVirt extends CNOE compute platform |
| VI. Package-Based Arch | ✅ PASS | ✅ PASS | Project structure confirms separation |
| VII. Security by Default | ⚠️ PARTIAL | ⚠️ PARTIAL | No change (dev acceptable, prod TODO) |
| VIII. AI-Augmented | ⚠️ N/A | ⚠️ N/A | No change |

**Final Gate Status**: ✅ APPROVED (no new violations)

**Phase 2 Recommendations**:
1. Add NetworkPolicies for VM namespace (Principle VII)
2. Use ESO for cloud-init secrets in production (Principle VII)
3. Consider multi-environment VM deployments with parameterized charts (Principle III)

---

## Complexity Tracking

*No constitutional violations requiring justification. All deviations are documented in Constitution Check with rationale.*

## Implementation Lessons Learned (2025-10-11)

### Critical Technical Discoveries

**1. Dynamic Configuration Pattern**
- The `deployment/scripts/deploy-linux-ssh.sh` script generates kind-config.yaml dynamically (lines 136-163)
- Static config files (`deployment/config/kind-config.yaml`) are reference templates only, NOT used during deployment
- **Action**: Always update the script's dynamic config generation, never edit static files
- **Impact**: nixos-images mount was missing because static files were edited instead of script

**2. DataVolume Immutability**
- DataVolume specs cannot be modified after creation (enforced by admission webhook)
- Changing imageUrl or storageSize requires: delete DataVolume → sync ArgoCD application → recreate
- Stuck sync operations: Use `argocd app terminate-op argocd/<app-name> --insecure` to kill loops
- **Recommendation**: Plan DataVolume configuration carefully, use test images before production

**3. Container Symlink Limitation**
- Symlinks pointing to host-only paths (Nix store: `/nix/store/...`) don't resolve inside containers
- nginx image server cannot serve `kubevirt-vm.qcow2` if it's a symlink to Nix store
- **Solution**: Use regular qcow2 files (`kubevirt-vm-actual.qcow2`) or copy symlink targets

**4. Verified Sync Wave Architecture**
```
-110: Operators (kubevirt-operator, cdi-operator) → Deploy CRDs
 -90: Custom Resources (KubeVirt CR, CDI CR) → Use CRDs
 -50: Image Server (nginx) → Must be ready before DataVolume imports
   0: DataVolumes → Import images from HTTP server
  10: VirtualMachines → Wait for DataVolume ready
  15: Services → Expose VM ports
```
- Without correct ordering: 404 errors (image server not ready) or VM start failures (DataVolume not imported)

**5. Chart Implementation Patterns**
- Use `ApiObject` from cdk8s instead of CRD-specific imports (e.g., `KubeVirtualMachine` from imports)
- Avoids TypeScript compilation issues with complex/frequently-updated CRDs
- Pattern: `new ApiObject(this, 'id', { apiVersion: 'kubevirt.io/v1', kind: 'VirtualMachine', ... })`

**6. Operator vs Custom Resource Separation**
- Separate charts for operator deployment vs custom resource creation:
  - `KubeVirtOperatorChart`: Uses `Include` to deploy upstream YAML (sync wave -110)
  - `KubeVirtCRChart`: Creates KubeVirt CR with configuration (sync wave -90)
- Prevents race conditions where CRs are created before CRDs exist

**7. VirtualMachine RunStrategy**
- `runStrategy: Manual` requires explicit start/stop (good for development)
- `runStrategy: Always` auto-starts and restarts on failure (good for production)
- Made configurable in chart with sensible defaults

**8. Testing Strategy**
- Use small test images (100MB via `truncate -s 100M`) to validate pipeline quickly
- Test → Validate → Switch to production (21GB image)
- Reduced DataVolume import testing from 10+ minutes to seconds

### Updated Technical Approach

**Original**:
- Import KubeVirt CRDs into CDK8s for type-safe VirtualMachine definitions ❌

**Revised**:
- Use `ApiObject` pattern to avoid CRD import complexity ✅
- Import CRDs for documentation reference only, not for TypeScript bindings

**Original**:
- NixOS qcow2 images (hosted via NEEDS CLARIFICATION: HTTP server, OCI registry, or local file access) ❓

**Revised**:
- HTTP server (nginx) with hostPath volume mount ✅
- Regular qcow2 files, not symlinks ✅
- Service URL: `http://nixos-image-server.default.svc.cluster.local/` ✅

