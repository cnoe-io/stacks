# Implementation Plan: Deploy NixOS VMs using KubeVirt

**Branch**: `004-deploy-nixos-vms` | **Date**: 2025-10-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-deploy-nixos-vms/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Deploy bootable NixOS virtual machines on Kubernetes using KubeVirt VirtualMachine resources. The feature implements a two-phase deployment strategy: (1) build and deploy minimal SSH-only base image for fast provisioning (<5 min), (2) apply full desktop configuration via nixos-rebuild with Attic binary cache for fast rebuilds (<3 min). This approach minimizes initial deployment time while maintaining full NixOS customization capability. The solution integrates with existing Attic binary cache infrastructure (spec 003) for 8x performance improvement and uses CDK8s/ArgoCD for GitOps automation.

## Technical Context

**Language/Version**: TypeScript 5.x (cdk8s), Nix 2.x (nixos-generators), Bash (build scripts)
**Primary Dependencies**:
  - cdk8s 2.x (Kubernetes manifest generation)
  - nixos-generators (NixOS image building with --format kubevirt)
  - KubeVirt/CDI CRDs (VirtualMachine, DataVolume resources)
  - kubevirt-helpers library (buildVirtualMachine, buildCloudInitUserData)
  - nginx (image server for qcow2 distribution)
  - Attic (binary cache, from spec 003)

**Storage**:
  - qcow2 disk images (NixOS VM root filesystem)
  - DataVolume PVCs (imported from HTTP source via CDI)
  - Docker registry (image server container: vpittamp23/nixos-kubevirt-minimal)
  - Attic cache (MinIO S3 backend, from spec 003)

**Testing**:
  - TypeScript compilation (`npm run compile`)
  - CDK8s synthesis validation
  - kubectl dry-run validation
  - Manual VM boot testing (SSH access, cloud-init verification)
  - ArgoCD sync validation

**Target Platform**: Kubernetes cluster with KubeVirt + CDI installed (local kind or cloud)

**Project Type**: Infrastructure/Platform (GitOps with CDK8s charts)

**Performance Goals**:
  - Image build time: <5 minutes (minimal base)
  - DataVolume import time: <3 minutes (1.7GB qcow2 over in-cluster network)
  - VM boot time: <2 minutes (from DataVolume ready to SSH accessible)
  - Desktop rebuild time: <3 minutes (with Attic cache hit >80%)
  - End-to-end automation: <10 minutes (full deployment via ArgoCD)

**Constraints**:
  - Image size: ~1.7GB compressed qcow2 (minimal base)
  - Memory requirements: 4Gi per VM (default), 128Mi-2Gi for image server
  - Network bandwidth: 100-500 MB/s in-cluster (for DataVolume import)
  - Bootstrap time: Must support cloud-init configuration (<30 seconds)
  - Desktop environment: KDE Plasma via nixos-rebuild (not in base image)

**Scale/Scope**:
  - 3 CDK8s charts (NixOsImageServerChart, NixOsDataVolumeChart, NixOsVmChart)
  - 1 NixOS configuration file (/etc/nixos/configurations/kubevirt-minimal.nix)
  - 2 build scripts (image build + Docker packaging)
  - 4 user stories (P1: base image → P4: GitOps automation)
  - 59 functional requirements
  - Integration with existing Attic infrastructure (5 additional requirements)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Type-Safe Infrastructure as Code ✅ PASS

**Compliance**: All Kubernetes manifests will be defined using CDK8s with TypeScript.

- NixOsImageServerChart, NixOsDataVolumeChart, NixOsVmChart extend `Chart` from cdk8s
- Use `imports/k8s` for KubeVirt CRDs (VirtualMachine, DataVolume)
- Use `kubevirt-helpers` library functions (buildVirtualMachine, buildCloudInitUserData)
- All charts will pass TypeScript compilation before synthesis
- Resource naming follows pattern: `{vmName}-{resource}` (e.g., `nixos-dev-vm-rdp`)

**Enforcement**: TypeScript compilation via `npm run compile` before deployment.

### Principle II: GitOps-First Deployment ✅ PASS

**Compliance**: All resources deployed via ArgoCD using GitOps patterns.

- Each chart synthesizes to `cdk8s/dist/<app>/manifests/` with ArgoCD Application manifest
- Local dev uses `cnoe://<package>/manifests` source URL
- Sync waves control ordering:
  - `-50`: NixOS image server (infrastructure prerequisite)
  - `5`: Cloud-init Secret (before VM)
  - `10`: VirtualMachine resource
  - `15`: Service for RDP/SSH exposure
- Deployment via `cluster-update` wrapper (not raw `idpbuilder create`)
- ArgoCD CLI operations use `--insecure` flag for local dev

**Enforcement**: All manifests deployed through ArgoCD, no imperative kubectl apply.

### Principle III: Multi-Environment Isolation ✅ PASS

**Compliance**: Charts support parameterized configuration for multi-environment deployment.

- NixOsVmChart accepts `environmentName`, `cpuCores`, `memory`, `runStrategy` props
- Development VMs can target `dev-vcluster`, production VMs target dedicated namespaces
- Environment-specific configuration via chart props (not hardcoded)
- No multi-environment deployment in initial implementation (P1-P3), but architecture supports it

**Enforcement**: Chart props enable environment-specific customization when needed.

### Principle IV: Declarative Configuration ✅ PASS

**Compliance**: All configuration declared in code, no manual configuration.

- Application config in `config/applications.ts` declarative format
- Chart types registered in `IdpBuilderChartFactory`
- Cloud-init configuration generated programmatically via `buildCloudInitUserData`
- SSH keys, passwords, user configuration in code (cloud-init Secret)
- No manual ConfigMaps or environment variables

**Enforcement**: All configuration version-controlled in Git, reproducible synthesis.

### Principle V: CNOE Technology Alignment ✅ PASS

**Compliance**: Uses CNOE-endorsed technologies throughout.

- **Continuous Delivery**: Argo CD (ArgoCD Applications for all resources)
- **Packaging & Templating**: cdk8s (TypeScript-based manifest generation)
- **Artifact Registry**: Docker Hub (vpittamp23/nixos-kubevirt-minimal image)
- **Compute Platform**: Kubernetes (KubeVirt for virtualization)
- **Secret Management**: External Secrets Operator (for production secrets - not in minimal implementation)

**Note**: NixOS and KubeVirt are not CNOE technologies, but are the subject of this feature (infrastructure extension).

**Enforcement**: All platform services use CNOE stack; feature extends platform capabilities.

### Principle VI: Package-Based Architecture ✅ PASS

**Compliance**: Each component organized as self-contained package.

- `nixos-image-server`: Image server Deployment + Service
- `nixos-dev-datavolume`: DataVolume for image import
- `nixos-dev-vm`: VirtualMachine + cloud-init Secret + RDP Service
- Each package synthesizes to `cdk8s/dist/<app>/manifests/` with kustomization.yaml
- Charts organized by domain: `cdk8s/charts/platform/` (image server) and `cdk8s/charts/apps/` (VM)
- Shared logic in `cdk8s/lib/kubevirt-helpers.ts`

**Enforcement**: Synthesis generates proper package structure, independent deployments.

### Principle VII: Security by Default ⚠️ PARTIAL COMPLIANCE

**Compliance Issues**:
- ✅ Cloud-init Secret for sensitive data (SSH keys, passwords)
- ❌ VM pods run with default securityContext (KubeVirt manages pod security)
- ❌ Initial passwords in plain text (nixos123) - acceptable for dev, not production
- ✅ Resource limits defined for image server (128Mi-2Gi memory, 100m-200m CPU)
- ❌ No NetworkPolicies initially (P1-P3 scope)
- ✅ SSH key-based authentication configured via cloud-init

**Justification**: KubeVirt VirtualMachine pods have different security model than standard Kubernetes workloads. VM guest security (inside NixOS) is managed separately from pod security. Initial implementation focuses on functional requirements; production hardening is follow-up work.

**Remediation Plan**:
- Phase 1: Functional base implementation with basic security (SSH keys, user accounts)
- Phase 2: Production hardening (ESO for secrets, NetworkPolicies, VM-specific security policies)

### Principle VIII: AI-Augmented Platform Engineering ✅ PASS

**Compliance**: No AI agents involved in this feature implementation.

- Feature is infrastructure extension, not AI/automation platform
- No autonomous operations or AI-generated changes
- Manual deployment and validation throughout
- If AI agents are added later (e.g., VM lifecycle management), they must follow least-privilege RBAC

**Enforcement**: N/A for this feature.

### Overall Gate Status: ✅ PASS WITH JUSTIFICATION

**Summary**: Feature passes 7/8 principles completely, with 1 partial compliance (Principle VII - Security).

**Justification for Partial Compliance**:
- Security by Default (Principle VII): KubeVirt VirtualMachine resources have different security model than standard Kubernetes pods. Initial implementation prioritizes functional requirements with basic security (SSH keys, user authentication). Production security hardening (ESO, NetworkPolicies, VM security policies) is planned for Phase 2 after functional validation.

**Decision**: Proceed with Phase 0 research. Re-evaluate security requirements after Phase 1 design.

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

```
# NixOS Configuration (external repository: nixos-config)
/etc/nixos/configurations/
└── kubevirt-minimal.nix     # Minimal NixOS base image config

# CDK8s Charts
cdk8s/
├── charts/
│   ├── platform/
│   │   └── nixos-image-server-chart.ts    # HTTP server for qcow2 images
│   └── apps/
│       ├── nixos-datavolume-chart.ts      # DataVolume for image import
│       └── nixos-vm-chart.ts              # VirtualMachine + cloud-init + Service
│
├── lib/
│   └── kubevirt-helpers.ts                # buildVirtualMachine, buildCloudInitUserData
│
├── config/
│   └── applications.ts                    # Declarative app configuration
│
├── main-v2.ts                             # Synthesis entry point
│
└── dist/                                  # Generated manifests (synthesis output)
    ├── nixos-image-server/
    │   ├── manifests/
    │   │   ├── Deployment.nixos-image-server.k8s.yaml
    │   │   ├── Service.nixos-image-server.k8s.yaml
    │   │   └── kustomization.yaml
    │   └── nixos-image-server.yaml        # ArgoCD Application
    │
    ├── nixos-dev-datavolume/
    │   ├── manifests/
    │   │   ├── DataVolume.nixos-dev-datavolume.k8s.yaml
    │   │   └── kustomization.yaml
    │   └── nixos-dev-datavolume.yaml      # ArgoCD Application
    │
    └── nixos-dev-vm/
        ├── manifests/
        │   ├── Secret.nixos-dev-vm-cloudinit.k8s.yaml
        │   ├── VirtualMachine.nixos-dev-vm.k8s.yaml
        │   ├── Service.nixos-dev-vm-rdp.k8s.yaml
        │   └── kustomization.yaml
        └── nixos-dev-vm.yaml              # ArgoCD Application

# Build Scripts (to be created)
scripts/
├── build-kubevirt-image.sh                # Build qcow2 using nixos-generators
└── package-image-docker.sh                # Package qcow2 into Docker image

# Docker Image (external: Docker Hub)
# vpittamp23/nixos-kubevirt-minimal:latest
# └── /usr/share/nginx/html/nixos.qcow2
```

**Structure Decision**: Infrastructure/Platform project using CDK8s for Kubernetes manifest generation. This is not a traditional application with src/tests directories, but rather:

1. **NixOS Configuration**: Declarative system configuration in /etc/nixos (external nixos-config repository)
2. **CDK8s Charts**: TypeScript classes generating Kubernetes manifests (cdk8s/charts/)
3. **Shared Libraries**: Reusable helper functions (cdk8s/lib/kubevirt-helpers.ts)
4. **Synthesis Output**: Generated YAML manifests (cdk8s/dist/)
5. **Build Scripts**: Image building and packaging automation (scripts/)

Testing is performed through:
- TypeScript compilation (type checking)
- CDK8s synthesis validation (manifest generation)
- kubectl dry-run (Kubernetes API validation)
- Manual VM deployment and verification (functional testing)

No traditional unit/integration test structure needed for infrastructure-as-code project.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle VII: Security by Default (partial) | KubeVirt VM pods have different security model; initial focus on functional requirements | Full production hardening upfront would delay functional validation; basic security (SSH keys, user auth) sufficient for P1-P3 dev/testing |
