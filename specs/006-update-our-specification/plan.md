# Implementation Plan: RustDesk Base Image Integration (Two-Stage Approach)

**Branch**: `006-update-our-specification` | **Date**: 2025-10-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/006-update-our-specification/spec.md`

## Summary

Pre-configure RustDesk remote desktop service in a **minimal NixOS KubeVirt VM base image** containing only essential connection services (SSH, RustDesk, Tailscale). The minimal image boots quickly (<2 min) with working remote access, then users can optionally apply full desktop configuration at runtime via cloud-init or manual nixos-rebuild. This two-stage approach provides:

1. **Stage 1 (Minimal Base Image)**: Fast boot, reliable connection services, small image size (~1-2 GB)
2. **Stage 2 (Runtime Configuration)**: Optional full desktop environment applied via cloud-init entrypoint or manual switch

**Key Innovation**: Separates "must work on boot" (connection services) from "nice to have later" (full desktop/dev tools), eliminating the 20-25 minute full image build for every change while maintaining 99%+ reliability for remote access.

## Technical Context

**Language/Version**: NixOS 24.11, Nix 2.x+
**Primary Dependencies**:
- **Nix build system**: For declarative base image builds with `nix build .#nixos-kubevirt-minimal-image`
- **nixos-generators**: For qcow2 VM image creation from NixOS configuration
- **KubeVirt CDI**: For DataVolume imports from qcow2 HTTP sources
- **Attic binary cache**: For fast rebuilds (3-5 min vs 20-25 min cold)
- **MinIO**: S3-compatible storage for qcow2 image distribution
- **CDK8s (TypeScript)**: For Kubernetes manifest generation

**Storage**:
- **Base Image Storage**: MinIO (`images` bucket) - serves qcow2 files via HTTP
- **Binary Cache**: Attic + MinIO - stores Nix store paths for fast rebuilds
- **Configuration Storage**: Git (flake.nix, NixOS modules) - version-controlled declarative config

**Testing**:
- **Build Validation**: `nix build` succeeds, RustDesk package present in closure
- **VM Boot Test**: VM reaches "Running" state within 2 minutes
- **Service Test**: RustDesk service active within 2 minutes of boot
- **Connection Test**: Remote desktop connection establishes successfully

**Target Platform**: KubeVirt VMs (qcow2 format), x86_64-linux
**Project Type**: Infrastructure/Platform (NixOS image build + Kubernetes deployment)
**Performance Goals**:
- Minimal image build: <10 minutes (cold), <3 minutes (cached)
- Full image build: <25 minutes (cold), <5 minutes (cached) - NOT required for connection services
- VM boot time: <2 minutes to RustDesk service active
- Image size: Minimal ~1-2 GB, Full ~3-5 GB

**Constraints**:
- **NixOS Immutability**: Runtime changes require nixos-rebuild or are ephemeral
- **KubeVirt Image Format**: Must be qcow2 compatible with CDI DataVolume imports
- **Binary Cache Dependency**: Fast rebuilds require Attic cache availability
- **Configuration Changes**: Minimal image changes require image rebuild + VM recreation (but fast: 3-5 min)

**Scale/Scope**:
- **Base Images**: 2 types (minimal, full) - shared across all VMs
- **VMs per Image**: Unlimited - VMs reference base image URL in DataVolume
- **Image Versions**: Simple versioning (v1, v2, ...) or date-based (2025-10-14)
- **Rebuild Frequency**: Infrequent (monthly for updates, as-needed for config changes)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Type-Safe Infrastructure as Code ✅

**Requirement**: All Kubernetes manifests MUST use CDK8s with TypeScript.

**Compliance**:
- ✅ Base image build is Nix/NixOS (outside CDK8s scope - infrastructure prerequisite)
- ✅ VM deployment uses CDK8s charts: `nixos-vm-chart.ts`, `nixos-datavolume-chart.ts`
- ✅ Image server uses CDK8s: `nixos-image-server-chart.ts`
- ✅ Secrets use CDK8s: `rustdesk-secrets-chart.ts` (ExternalSecret)
- ✅ All charts have TypeScript interfaces and type checking

**No violations** - Base image build is analogous to container image build (prerequisite, not K8s manifest)

### Principle II: GitOps-First Deployment ✅

**Requirement**: All deployments via ArgoCD, use `cluster-menu.sh` for cluster operations.

**Compliance**:
- ✅ VM deployment via ArgoCD Application (`nixos-dev-vm.yaml`)
- ✅ DataVolume via ArgoCD Application (`nixos-dev-datavolume.yaml`)
- ✅ Image server via ArgoCD Application (`nixos-image-server.yaml`)
- ✅ Secrets via ArgoCD Application (`rustdesk-secrets.yaml`)
- ✅ Deployment uses `cluster-update` (cluster-menu.sh wrapper)
- ✅ Sync waves enforce ordering (secrets -70, datavolume -40, VM 0)

**No violations** - Base image build is separate pipeline (documented workflow), K8s deployment is fully GitOps

### Principle III: Multi-Environment Isolation ⚠️

**Requirement**: Dev/staging use VClusters, production uses dedicated clusters.

**Status**: Currently single environment (default namespace in localdev cluster).

**Justification**: This feature establishes baseline VM deployment. Multi-environment VM deployment (dev/staging/prod VMs) is out of scope for this spec. Future work will add VCluster support.

**Compliance Path**: When multi-environment VMs needed, VMs will target vclusters via ArgoCD destination configuration.

### Principle IV: Declarative Configuration ✅

**Requirement**: All configuration declared in code, no imperative scripts except bootstrapping.

**Compliance**:
- ✅ Base image config is declarative NixOS (flake.nix, modules/)
- ✅ VM config in CDK8s TypeScript charts
- ✅ Application config in `config/applications.ts`
- ✅ Secrets via ESO ExternalSecret (declarative Azure Key Vault reference)
- ⚠️ **Exception**: Image build workflow (`nix build`) is imperative but documented
  - **Justification**: Similar to `docker build` - infrastructure prerequisite, not K8s resource
  - **Mitigation**: Workflow documented in quickstart.md, can be automated via CI/CD pipeline

**Minor exception justified** - Image builds are infrastructure prerequisites like container builds

### Principle V: CNOE Technology Alignment ✅

**Requirement**: Use CNOE-endorsed technologies.

**Compliance**:
- ✅ GitOps: ArgoCD for VM deployment
- ✅ Packaging: cdk8s (TypeScript) for manifests
- ✅ Secret Management: External Secrets Operator + Azure Key Vault
- ❓ **Non-CNOE**: Nix/NixOS for base image build
  - **Rationale**: NixOS is the most reliable way to build reproducible, declarative VM images
  - **Alternatives considered**: Packer (imperative), cloud-init-only (unreliable per debugging summary)
  - **CNOE alignment**: No CNOE-endorsed VM image builder exists; Nix is community-standard for declarative infrastructure

**No violations** - Nix/NixOS fills gap where CNOE has no recommendation (VM image building)

### Principle VI: Package-Based Architecture ✅

**Requirement**: Applications organized as self-contained packages.

**Compliance**:
- ✅ `nixos-dev-vm` package: manifests/, kustomization.yaml, ArgoCD Application
- ✅ `nixos-dev-datavolume` package: manifests/, kustomization.yaml, ArgoCD Application
- ✅ `nixos-image-server` package: manifests/, kustomization.yaml, ArgoCD Application
- ✅ `rustdesk-secrets` package: manifests/, kustomization.yaml, ArgoCD Application
- ✅ All charts in `cdk8s/charts/{apps,infra,secrets}/`
- ✅ Synthesis via `main-v2.ts` → `dist/<app>/manifests/`

**No violations** - Follows package-based architecture exactly

### Principle VII: Security by Default ✅

**Requirement**: External Secrets, SecurityContext, resource limits, NetworkPolicies.

**Compliance**:
- ✅ RustDesk password via ESO + Azure Key Vault
- ✅ Tailscale auth keys via ESO + Azure Key Vault
- ⚠️ VM SecurityContext: KubeVirt VMs run in privileged context (required by KubeVirt architecture)
  - **Justification**: VMs are workload isolation boundary (equivalent to Pod), not containers
  - **Mitigation**: VMs isolated by KubeVirt VMI security model, not container securityContext
- ✅ Resource limits: CPU/memory defined in VM spec
- ❓ NetworkPolicies: Not implemented (out of scope for MVP)

**Minor exception justified** - VM security model differs from container security model

### Principle VIII: AI-Augmented Platform Engineering ✅

**Requirement**: AI agents MAY be used for automation with human approval.

**Compliance**: This feature does not introduce AI agents. Human-driven implementation.

**No violations** - N/A for this feature

### Constitution Check Summary

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type-Safe IaC | ✅ PASS | CDK8s for all K8s manifests |
| II. GitOps-First | ✅ PASS | ArgoCD + cluster-menu.sh |
| III. Multi-Env Isolation | ⚠️ DEFER | Single env for MVP, VCluster support in future |
| IV. Declarative Config | ✅ PASS | Minor exception for image build (justified) |
| V. CNOE Alignment | ✅ PASS | Nix fills gap where CNOE has no standard |
| VI. Package-Based | ✅ PASS | Full package architecture |
| VII. Security by Default | ✅ PASS | ESO secrets, VM security model differs from containers |
| VIII. AI-Augmented | ✅ N/A | Not applicable |

**GATE PASSED** - All principles satisfied with documented justifications for minor exceptions.

## Project Structure

### Documentation (this feature)

```
specs/006-update-our-specification/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - image building approaches
├── data-model.md        # Phase 1 output - entities and relationships
├── quickstart.md        # Phase 1 output - end-to-end workflow
├── contracts/           # Phase 1 output - NixOS module, CDK8s chart interfaces
│   ├── nixos-minimal-image-flake.nix   # Flake output for minimal image
│   ├── nixos-full-image-flake.nix      # Flake output for full image (optional)
│   ├── external-secret-rustdesk.yaml   # ExternalSecret contract
│   └── datavolume-source.yaml          # DataVolume HTTP source contract
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
# NixOS Configuration (Hetzner host)
/etc/nixos/
├── flake.nix                         # Flake with minimal/full image outputs
├── configurations/
│   ├── kubevirt-minimal.nix          # NEW: Minimal image (SSH, RustDesk, Tailscale)
│   ├── kubevirt-desktop.nix          # NEW: Full desktop image (or applied at runtime)
│   └── vm-hetzner.nix                # Existing full Hetzner config (reference)
└── modules/
    └── services/
        └── rustdesk.nix              # Existing RustDesk module (may need updates)

# CDK8s Charts (this repo)
cdk8s/
├── charts/
│   ├── apps/
│   │   ├── nixos-vm-chart.ts         # UPDATED: Support minimal/full image URLs
│   │   └── nixos-datavolume-chart.ts # UPDATED: Reference MinIO image URLs
│   ├── infra/
│   │   └── nixos-image-server-chart.ts # EXISTING: Serves images via HTTP
│   └── secrets/
│       └── rustdesk-secrets-chart.ts # NEW: ExternalSecret for RustDesk password
├── lib/
│   └── kubevirt-helpers.ts           # UPDATED: Remove cloud-init RustDesk setup
├── config/
│   └── applications.ts               # UPDATED: Add rustdesk-secrets application
└── dist/                              # Synthesized packages
    ├── nixos-dev-vm.yaml
    ├── nixos-dev-vm/manifests/
    ├── nixos-dev-datavolume.yaml
    ├── nixos-dev-datavolume/manifests/
    ├── rustdesk-secrets.yaml
    └── rustdesk-secrets/manifests/

# Build Scripts (Optional - CI/CD Pipeline)
deployment/scripts/
└── nix-cache/
    ├── build-minimal-image.sh        # NEW: Build minimal image + push to cache/MinIO
    ├── build-full-image.sh           # NEW: Build full image (optional)
    └── push-to-cache.sh              # EXISTING: Push Nix store paths to Attic
```

**Structure Decision**: Two-stage approach with separate minimal and full image configurations. Minimal image is the primary artifact for reliable remote access. Full image is either:
1. **Option A**: Pre-built and selectable at VM creation time (separate base image)
2. **Option B**: Applied at runtime via cloud-init entrypoint (nixos-rebuild switch to full config)

Implementation will use **Option B** (runtime application) initially for flexibility, with Option A available for performance-critical use cases.

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | No violations | N/A |

## Phase 0: Research (NEEDS CLARIFICATION Resolution)

**Research Tasks** (generated from Technical Context):

1. **nixos-generators Usage**
   - Research: How to create qcow2 VM images from NixOS configurations using nixos-generators
   - Output: Example flake with `nixosConfigurations` → `packages` mapping for qcow2 format
   - Reference: https://github.com/nix-community/nixos-generators

2. **Minimal Image Package Selection**
   - Research: Essential packages for SSH, RustDesk, Tailscale (no desktop)
   - Output: Package list with sizes, dependencies, and justifications
   - Target: <500 MB total package closure

3. **Runtime Configuration Application**
   - Research: Best practices for applying full NixOS configuration at VM runtime
   - Options: cloud-init nixos-rebuild, user-triggered script, systemd oneshot service
   - Output: Recommended approach with trade-offs

4. **Image Versioning Strategy**
   - Research: How to version minimal vs. full images, update strategy
   - Output: Versioning scheme (semantic, date-based, git-hash) and CDK8s chart patterns

5. **Binary Cache Workflow**
   - Research: How to push minimal image store paths to Attic efficiently
   - Output: Script workflow for build → push → verify cache population

**Output**: `research.md` with decisions for all above unknowns

## Phase 1: Design & Contracts

**Prerequisites**: `research.md` complete

### Data Model (`data-model.md`)

**Entities**:
1. **MinimalBaseImage**: NixOS VM image with only connection services
   - Fields: imageUrl, version, buildDate, packageClosure, sizeBytes
   - Relationships: Referenced by DataVolume
2. **FullBaseImage**: Optional full desktop NixOS VM image
   - Fields: imageUrl, version, buildDate, packageClosure, sizeBytes
   - Relationships: Optional reference from VM or applied at runtime
3. **DataVolume**: KubeVirt data volume importing base image
   - Fields: name, namespace, imageUrl (MinimalBaseImage), storageSize
   - Relationships: Consumed by VM
4. **VirtualMachine**: KubeVirt VM instance
   - Fields: name, namespace, cpuCores, memory, dataVolumeRef
   - Relationships: Uses DataVolume, optionally applies FullBaseImage at runtime
5. **RustDeskPassword**: Secret synced from Azure Key Vault
   - Fields: secretName, keyVaultKey, refreshInterval
   - Relationships: Mounted in VM for RustDesk authentication

**State Transitions**:
- **MinimalBaseImage**: `building` → `pushing to cache` → `uploading to MinIO` → `available`
- **DataVolume**: `pending` → `importing` → `ready` → `bound to VM`
- **VirtualMachine**: `stopped` → `starting` → `running (minimal)` → `running (full)` (if runtime config applied)

### API Contracts (`contracts/`)

1. **`nixos-minimal-image-flake.nix`**: Flake output definition for minimal image
   - Package: `nixos-kubevirt-minimal-image`
   - Format: qcow2
   - Target: `packages.x86_64-linux.nixos-kubevirt-minimal-image`

2. **`external-secret-rustdesk.yaml`**: ExternalSecret contract
   - ClusterSecretStore: `azure-keyvault-store`
   - RemoteRef: `RUSTDESK-PASSWORD`
   - Target Secret: `rustdesk-password` (namespace: default)

3. **`datavolume-source.yaml`**: DataVolume HTTP source contract
   - Source URL: `http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-minimal-v1.qcow2`
   - Storage: ReadWriteOnce, size from image + 10% overhead

4. **`vm-spec-contract.yaml`**: VirtualMachine spec contract
   - CPU: configurable (default 2 cores)
   - Memory: configurable (default 4Gi)
   - DataVolumeRef: references DataVolume name
   - Cloud-init: Optional full config application entrypoint

### Quickstart (`quickstart.md`)

End-to-end workflow:
1. Build minimal image on Hetzner host
2. Push to Attic cache
3. Upload to MinIO
4. Update CDK8s chart with new image URL
5. Synthesize and deploy
6. Verify VM boots with RustDesk service active
7. (Optional) Apply full configuration at runtime

### Agent Context Update

Run `.specify/scripts/bash/update-agent-context.sh claude` to add:
- **New Technologies**: nixos-generators, MinIO image distribution
- **New Patterns**: Two-stage minimal/full image approach
- **Preserve Manual Additions**: Existing NixOS, KubeVirt, RustDesk context

## Phase 2: Task Breakdown (Not Created by `/speckit.plan`)

**Note**: Phase 2 tasks are generated by the `/speckit.tasks` command after plan approval. Preliminary task outline:

### Phase 1: Minimal Base Image Setup
- T001: Create kubevirt-minimal.nix configuration (SSH, RustDesk, Tailscale only)
- T002: Add nixos-generators flake output for qcow2 minimal image
- T003: Build minimal image and verify package closure size
- T004: Create RustDeskSecretsChart (ExternalSecret)
- T005: Update kubevirt-helpers.ts (remove cloud-init RustDesk setup)

### Phase 2: Image Build & Distribution
- T006: Build minimal image on Hetzner host
- T007: Push minimal image store paths to Attic binary cache
- T008: Upload minimal qcow2 to MinIO images bucket
- T009: Update NixOsDataVolumeChart with MinIO minimal image URL

### Phase 3: Deployment & Verification
- T010: Synthesize and deploy updated manifests (cluster-update)
- T011: Verify VM boots with RustDesk service active within 2 minutes
- T012: Test RustDesk remote desktop connection
- T013: (Optional) Test runtime full config application

### Phase 4: Documentation & Cleanup
- T014: Document minimal image build workflow in quickstart.md
- T015: Document runtime full config application pattern
- T016: Update CLAUDE.md with two-stage image approach

**Full task breakdown will be created by `/speckit.tasks` command.**

## Design Decisions

### Decision: Two-Stage Minimal/Full Image Approach

**Chosen**: Minimal base image with runtime full configuration option

**Rationale**:
- **Reliability**: Connection services (SSH, RustDesk, Tailscale) pre-configured in minimal image → 99%+ reliability
- **Speed**: Minimal image builds in 3-5 minutes (cached) vs. 20-25 minutes for full desktop
- **Flexibility**: Users can apply full desktop config when needed, not forced on every VM
- **Image Size**: Minimal ~1-2 GB (fast download/import) vs. Full ~3-5 GB

**Alternatives Considered**:
1. **Single Full Image**: Slow build (20-25 min), large size, overkill for VMs needing only remote access
2. **Cloud-init Only**: Unreliable (0% success rate per debugging summary), defeats purpose of spec
3. **Three Images (minimal/medium/full)**: Over-engineering, two stages sufficient

**Trade-offs**:
- **Pro**: Fast builds, small images, reliable connection services
- **Con**: Runtime full config application adds 5-10 minutes (acceptable for optional feature)

### Decision: Runtime Full Config via Cloud-Init Entrypoint

**Chosen**: Cloud-init executes `nixos-rebuild switch --flake .#kubevirt-desktop` on first boot (if enabled)

**Rationale**:
- **Declarative**: Full config still in flake.nix, not imperative cloud-init scripts
- **Optional**: VMs not needing desktop don't pay the cost
- **Testable**: Same nixos-rebuild command works on Hetzner host for testing

**Alternatives Considered**:
1. **Separate Full Image**: Extra maintenance burden (two image builds), slow updates
2. **Manual nixos-rebuild**: Requires SSH access, not automated
3. **Systemd oneshot service**: Similar to cloud-init but less standard

**Implementation**:
```yaml
# Cloud-init userdata (only if enableFullDesktop: true in VM chart props)
runcmd:
  - |
    if [ -f /etc/nixos/apply-full-config-marker ]; then
      echo "Applying full desktop configuration..."
      nixos-rebuild switch --flake github:vpittamp/nixos-config#kubevirt-desktop
      rm /etc/nixos/apply-full-config-marker
    fi
```

### Decision: MinIO for Image Distribution (Not nixos-image-server Docker Image)

**Chosen**: Upload qcow2 directly to MinIO, DataVolume imports via HTTP URL

**Rationale**:
- **Existing Infrastructure**: MinIO already deployed for binary cache
- **Standard Pattern**: DataVolume HTTP source is standard KubeVirt pattern
- **Version Control**: MinIO allows versioned images (e.g., `nixos-kubevirt-minimal-v1.qcow2`)

**Alternatives Considered**:
1. **Docker Hub (nixos-image-server)**: Requires embedding qcow2 in Docker image, extra layer of indirection
2. **OCI Registry (Gitea)**: qcow2 as OCI artifact is non-standard, tooling immature

**Trade-offs**:
- **Pro**: Direct qcow2 distribution, standard HTTP import, versioning
- **Con**: MinIO requires storage (acceptable, already allocated for binary cache)

## Risk Analysis

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Minimal image missing critical package | Medium | High | Build validation step checks SSH, RustDesk, Tailscale packages present |
| Runtime full config fails | Medium | Medium | Graceful fallback - minimal image still functional, manual nixos-rebuild |
| Binary cache unavailable | Low | High | Document cold build time (10-15 min for minimal), cache is optimization not requirement |
| MinIO storage exhaustion | Low | Medium | Implement image retention policy (keep last 3 versions), ~5 GB per image |
| qcow2 import timeout | Medium | High | Increase DataVolume import timeout, verify MinIO network performance |

## Success Metrics (from spec.md)

- **SC-001**: VMs boot with RustDesk service running within 2 minutes ✅ (minimal image target)
- **SC-002**: RustDesk service start success rate 99%+ ✅ (pre-configured in minimal image)
- **SC-003**: Minimal image rebuild <5 minutes (cached) ✅ (vs. 25 min for full)
- **SC-004**: Remote desktop connection within 30 seconds ✅ (RustDesk direct connection)
- **SC-005**: Config changes propagate to new VMs after rebuild ✅ (declarative flake.nix)
- **SC-006**: Zero cloud-init runcmd failures ✅ (RustDesk in base image, not cloud-init)

## Appendix: Research Questions for Phase 0

1. **What is the minimal NixOS package set for SSH + RustDesk + Tailscale?**
   - Need: Package list with sizes and dependencies
   - Output: nixpkgs expression for minimal system

2. **How do we use nixos-generators to create qcow2 from nixosConfiguration?**
   - Need: Flake pattern for `nixosConfigurations.kubevirt-minimal` → `packages.nixos-kubevirt-minimal-image`
   - Output: Working flake.nix snippet

3. **What is the best cloud-init pattern for optional runtime config application?**
   - Need: Cloud-init runcmd that conditionally applies full config
   - Output: Cloud-init YAML with nixos-rebuild switch

4. **How do we version images in MinIO and update CDK8s charts?**
   - Need: Version string pattern (v1, v2 or date-based), CDK8s chart props
   - Output: Versioning convention and chart interface

5. **What is the expected minimal image size and build time?**
   - Need: Benchmarks for minimal vs. full image
   - Output: Size/time comparison table

These will be answered in `research.md` during Phase 0 execution.

---

**Next Steps**:
1. Run `/speckit.plan` (this command) to generate research.md, data-model.md, contracts/, quickstart.md
2. Review generated artifacts for completeness
3. Run `/speckit.tasks` to break down implementation into executable tasks
4. Implement tasks in priority order (MVP: minimal image + RustDesk service verification)
