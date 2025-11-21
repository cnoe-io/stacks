# Implementation Plan: Migrate NixOS VM to Wayland/Sway with WayVNC

**Branch**: `007-number-7-short` | **Date**: 2025-11-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-number-7-short/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Replace the existing X11/RustDesk-based NixOS VM deployment with a Wayland/Sway headless environment accessible via WayVNC. Build a QCOW2 disk image from the hetzner-sway.nix configuration (which already includes Sway compositor, WayVNC server, and headless Wayland setup), update KubeVirt CDK8s charts to reference the new image, remove all RustDesk/X11 configuration, and validate VNC access from M1 MacBook via Tailscale network. No backwards compatibility required - full replacement strategy.

## Technical Context

**Language/Version**: TypeScript 5.x (CDK8s charts), Nix 2.x (NixOS image build), Bash (deployment scripts)
**Primary Dependencies**:
- CDK8s 2.x for Kubernetes manifest generation
- KubeVirt for VM orchestration
- CDI (Containerized Data Importer) for image import
- Tailscale Operator for LoadBalancer provisioning
- External Secrets Operator for Azure Key Vault integration
- NixOS 24.11 with Wayland/Sway/WayVNC packages
- idpbuilder for local GitOps deployment
**Storage**: QCOW2 disk images (NixOS VM), DataVolume/PVC (KubeVirt storage), MinIO/Attic (Nix binary cache)
**Testing**: Manual VNC connection testing from M1 MacBook, kubectl validation, ArgoCD sync verification
**Target Platform**: KubeVirt on Kind (local Kubernetes cluster), NixOS 24.11 VM (headless Wayland)
**Project Type**: Infrastructure-as-Code (CDK8s charts + NixOS declarative configuration)
**Performance Goals**:
- NixOS image build: <25 minutes (cold cache), <3 minutes (warm cache via Attic)
- VM boot time: <90 seconds from VirtualMachine creation to Running state
- VNC connection: <5 seconds to establish, <100ms input latency
**Constraints**:
- No GPU acceleration (software rendering via pixman)
- Tailscale-only network access (no public VNC exposure)
- Single-user VNC sessions (no multi-user support)
- Kind cluster resource limits (CPU, memory, storage)
**Scale/Scope**:
- 1 NixOS VM configuration (hetzner-sway.nix)
- 2 CDK8s charts to modify (NixOsVmChart, kubevirt-helpers)
- ~600 lines of RustDesk configuration to remove
- 1 new image build workflow (NEEDS CLARIFICATION: nixos-generators or nix build?)
- 3 VNC service ports (5900, 5901, 5902 for multi-output support)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. Type-Safe Infrastructure as Code ✅ PASS

**Evaluation**: All Kubernetes manifests will be defined using CDK8s with TypeScript. No YAML templating involved.

**Evidence**:
- Modifications to existing TypeScript charts: `NixOsVmChart`, `kubevirt-helpers.ts`
- Use of `imports/k8s` low-level API for exact YAML control
- TypeScript type checking via `npm run compile` before synthesis
- Chart classes extend `Chart` from `cdk8s` library

**Actions**: Update chart props interface to remove RustDesk properties, add WayVNC port configuration

---

### II. GitOps-First Deployment ✅ PASS

**Evaluation**: All changes deployed via ArgoCD using GitOps patterns. No imperative kubectl commands. cluster-menu.sh wrapper will be used for deployment.

**Evidence**:
- NixOS VM deployed via ArgoCD Application manifest (`nixos-dev-vm.yaml`)
- Uses `cnoe://<package>/manifests` source URL for local development
- Sync waves control resource ordering (Secret at wave 5, VM at wave 10, Service at wave 15)
- Deployment via `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`

**Actions**: Update existing ArgoCD Application manifest for nixos-dev-vm package, no new applications required

---

### III. Multi-Environment Isolation ✅ PASS

**Evaluation**: Single environment (default namespace) for development VM. No multi-environment concerns.

**Evidence**:
- VM targets `default` namespace (development environment)
- No cross-environment promotion needed (single VM instance)

**Actions**: None - feature scoped to single development VM

---

### IV. Declarative Configuration ✅ PASS

**Evaluation**: All configuration declared in code. NixOS image uses declarative hetzner-sway.nix configuration. CDK8s charts define all Kubernetes resources.

**Evidence**:
- NixOS configuration: `/etc/nixos/configurations/hetzner-sway.nix` (declarative Nix modules)
- Cloud-init configuration generated via `buildCloudInitUserData` function
- VNC password synced from Azure Key Vault via External Secrets Operator
- No manual kubectl commands or imperative scripts

**Actions**: Update `buildCloudInitUserData` to remove RustDesk logic, add WayVNC password configuration

---

### V. CNOE Technology Alignment ✅ PASS

**Evaluation**: All technologies align with CNOE endorsed stack.

**Evidence**:
- **Artifact Registry**: Gitea OCI registry (local) for QCOW2 image hosting (NEEDS CLARIFICATION: HTTP server or OCI registry?)
- **Continuous Delivery**: Argo CD for GitOps deployment
- **Secret Management**: External Secrets Operator with Azure Key Vault
- **Packaging & Templating**: cdk8s (TypeScript)
- **Compute Platform**: Kubernetes (kind for local)
- **Remote Access**: Tailscale for secure VNC access

**Actions**: Clarify image distribution strategy (HTTP server vs OCI registry)

---

### VI. Package-Based Architecture ✅ PASS

**Evaluation**: Follows package-based architecture. Existing nixos-dev-vm package structure maintained.

**Evidence**:
- Package directory: `cdk8s/dist/nixos-dev-vm/manifests/`
- Includes `kustomization.yaml` (generated by `KustomizationGenerator`)
- ArgoCD Application: `cdk8s/dist/nixos-dev-vm.yaml`
- Chart location: `cdk8s/charts/apps/nixos-vm-chart.ts` (existing infrastructure chart)

**Actions**: Update existing package manifests, no new packages required

---

### VII. Security by Default ✅ PASS

**Evaluation**: Security best practices maintained. VNC password from Azure Key Vault, Tailscale-only access, no public exposure.

**Evidence**:
- VNC password stored in Azure Key Vault, synced via External Secrets Operator (FR-013)
- Tailscale LoadBalancer for network access (no public NodePort)
- SecurityContext defined in VirtualMachine pods (inherited from KubeVirt defaults)
- Resource limits defined: cpuCores=2, memory=4Gi

**Actions**: Update ExternalSecret to sync WayVNC password instead of RustDesk password

---

### VIII. AI-Augmented Platform Engineering ⚪ NOT APPLICABLE

**Evaluation**: No AI agents involved in this feature. Manual implementation and testing.

**Evidence**: Feature is infrastructure migration, not AI/automation platform work

**Actions**: None

---

### Summary

**Status**: ✅ **ALL GATES PASS**

**Identified Clarifications Needed** (resolved in Phase 0 research):
1. ✅ NixOS image build tooling: **nixos-generators with flake integration**
2. ✅ Image distribution: **HTTP server (MinIO in nix-cache namespace)**
3. ✅ DataVolume source URL format: **`http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2`**

**Post-Design Re-evaluation** (completed 2025-11-12):

All constitution principles remain satisfied after design phase:
- ✅ **Principle I**: TypeScript charts using `imports/k8s` API (data-model.md sections 1-2)
- ✅ **Principle II**: GitOps deployment via ArgoCD, cluster-update wrapper (quickstart.md phase 4)
- ✅ **Principle III**: Single environment (default namespace), no multi-environment concerns
- ✅ **Principle IV**: Declarative configuration in CDK8s + NixOS flake (research.md section 1)
- ✅ **Principle V**: CNOE-aligned technologies (MinIO, ArgoCD, CDK8s, Tailscale)
- ✅ **Principle VI**: Package-based architecture maintained (cdk8s/dist/nixos-dev-vm/)
- ✅ **Principle VII**: Security maintained (VNC password from Azure Key Vault, Tailscale-only access)
- ✅ **Principle VIII**: No AI agents involved (N/A)

**No Constitution Violations**: All principles satisfied. No complexity justification required.

## Project Structure

### Documentation (this feature)

```
specs/007-number-7-short/
├── spec.md              # Feature specification (already complete)
├── checklists/
│   └── requirements.md  # Quality checklist (already complete)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   └── wayvnc-config.yaml  # WayVNC configuration contract
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
# Infrastructure-as-Code structure (CDK8s + NixOS)

cdk8s/
├── charts/
│   └── apps/
│       └── nixos-vm-chart.ts              # MODIFY: Update chart to remove RustDesk, add WayVNC
├── lib/
│   └── kubevirt-helpers.ts                # MODIFY: Update buildCloudInitUserData function
├── config/
│   └── applications.ts                     # REVIEW: May need prop updates for nixos-dev-vm
└── dist/
    └── nixos-dev-vm/
        ├── manifests/                      # GENERATED: Updated manifests after synthesis
        └── nixos-dev-vm.yaml               # GENERATED: ArgoCD Application (no changes expected)

/etc/nixos/
├── configurations/
│   └── hetzner-sway.nix                   # INPUT: Source configuration for new image (read-only)
└── modules/
    └── desktop/
        └── wayvnc.nix                      # INPUT: WayVNC module configuration (read-only)

deployment/
└── scripts/
    └── nixos-image/                        # CREATE: New directory for image build scripts
        ├── build-sway-image.sh             # CREATE: Image build automation
        └── upload-to-registry.sh           # CREATE: Image distribution (HTTP/OCI)
```

**Structure Decision**: This is an infrastructure migration project combining:
1. **CDK8s TypeScript charts** for Kubernetes manifest generation (cdk8s/ directory)
2. **NixOS declarative configuration** for VM image definition (/etc/nixos/)
3. **Bash deployment scripts** for image build and distribution (deployment/scripts/)

No application code (src/, frontend/, backend/) involved. All changes are infrastructure-as-code modifications to existing charts plus new image build automation.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**No violations**: All constitution principles satisfied. No complexity justification required.
