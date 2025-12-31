# Implementation Plan: Nixidy Migration - Complete cdk8s to Nixidy Transition

**Branch**: `114-nixidy` | **Date**: 2025-12-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/114-nixidy/spec.md`

## Summary

Replace the existing TypeScript/cdk8s manifest generation system with nixidy, a Nix-based Kubernetes GitOps framework. This migration involves translating 80+ application definitions and 90+ chart classes from TypeScript to Nix modules, establishing environment variable injection patterns using Nix's `builtins.getEnv`, and ensuring generated manifests are functionally equivalent to the current cdk8s output.

## Technical Context

**Language/Version**: Nix (nixpkgs unstable) with flake-based configuration
**Primary Dependencies**: nixidy (github:arnarg/nixidy), nixpkgs
**Storage**: N/A (manifest generation only - no runtime storage)
**Testing**: Manifest diff comparison (cdk8s output vs nixidy output), ArgoCD sync validation
**Target Platform**: Linux (NixOS development environment), outputs to Kubernetes YAML
**Project Type**: Infrastructure-as-Code / GitOps tooling
**Performance Goals**: Manifest generation under 60 seconds (matching cdk8s synthesis time)
**Constraints**: Must produce identical output structure (`dist/<app>/manifests/` + ArgoCD Applications)
**Scale/Scope**: 80+ applications, 90+ chart types, 30+ environment variables

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### CRITICAL: Constitution Violation Detected

**Principle I (Type-Safe Infrastructure as Code)** states:

> "All Kubernetes manifests MUST be defined using CDK8s with TypeScript, not YAML templating (Helm, Kustomize)."

The nixidy migration **directly violates** this core principle by replacing TypeScript with Nix.

**Violation Justification Required**:

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Principle I: TypeScript → Nix | User explicitly requested complete transition to nixidy for manifest generation | Keeping cdk8s was explicitly rejected by user ("don't worry about backwards compatibility. Use a full transition to nixidy") |
| Principle I: Single main.ts entry point | Replaced with flake.nix + Nix modules | nixidy's architecture uses flake-based environments, not TypeScript entry points |

**Other Principles Analysis**:

| Principle | Status | Notes |
|-----------|--------|-------|
| II. GitOps-First Deployment | ✅ Compatible | nixidy generates ArgoCD Applications natively |
| III. Multi-Environment Isolation | ✅ Compatible | nixidy supports environment-specific builds (`nixidy build .#kind`, `.#talos`) |
| IV. Declarative Configuration | ✅ Compatible | Nix is declarative; applications.ts → Nix modules |
| V. CNOE Technology Alignment | ⚠️ Deviation | CNOE endorses cdk8s; nixidy is not CNOE-endorsed |
| VI. Package-Based Architecture | ✅ Compatible | nixidy output matches `dist/<app>/manifests/` structure |
| VII. Security by Default | ✅ Compatible | ESO integration remains unchanged |
| VIII. AI-Augmented Platform Engineering | ✅ Compatible | No change to AI agent architecture |
| IX. Unified Cluster Bootstrap | ✅ Compatible | Environment-driven configuration via Nix modules |
| X-XIII (Talos-specific) | ✅ Compatible | Infrastructure patterns unchanged |

**Required Amendment**: This migration requires a constitution amendment to Principle I to allow Nix/nixidy as an alternative to TypeScript/cdk8s.

**User Decision (2025-12-31)**: User confirmed: "yes, we have decided to switch to nixidy from cdk8s. we should update the constitution to reflect this." Constitution update will be part of implementation tasks.

---

## Project Structure

### Documentation (this feature)

```
specs/114-nixidy/
├── plan.md              # This file
├── research.md          # Phase 0: nixidy patterns, env var injection
├── data-model.md        # Phase 1: Application/Environment configuration schema
├── quickstart.md        # Phase 1: Migration workflow guide
├── contracts/           # Phase 1: Not applicable (no API contracts)
└── tasks.md             # Phase 2: Implementation tasks
```

### Source Code (repository root)

```
nixidy/                      # New nixidy configuration root
├── flake.nix               # Flake entry point with environment declarations
├── flake.lock              # Dependency lockfile
├── env/                    # Environment-specific configurations
│   ├── base.nix           # Shared configuration across all environments
│   ├── kind.nix           # KIND cluster configuration
│   ├── talos.nix          # Talos cluster configuration
│   └── variables.nix      # Environment variable handling
├── apps/                   # Application definitions (replaces config/applications.ts)
│   ├── default.nix        # Application registry
│   ├── backstage.nix      # Backstage application
│   ├── keycloak.nix       # Keycloak application
│   ├── ...                # 80+ application definitions
│   └── lib/               # Shared application helpers
├── modules/                # Custom nixidy modules
│   ├── argocd.nix         # ArgoCD Application generation
│   ├── kustomization.nix  # Kustomization file generation
│   └── idpbuilder.nix     # idpBuilder package structure
├── generated/              # Auto-generated CRD options
│   └── crds.nix
└── lib/                    # Shared Nix functions
    ├── env-vars.nix       # Environment variable injection
    ├── sync-wave.nix      # Sync wave helpers
    └── source-url.nix     # ArgoCD source URL generation

# Output (generated by nixidy build)
dist/                       # Same structure as cdk8s output
├── <app-name>.yaml        # ArgoCD Application
└── <app-name>/
    └── manifests/
        ├── *.yaml
        └── kustomization.yaml

# Comparison tooling
scripts/
└── compare-manifests.sh   # Diff tool for cdk8s vs nixidy output
```

**Structure Decision**: Single project with Nix modules. The `nixidy/` directory is the new configuration root, replacing `cdk8s/`. During migration, both will coexist until validation is complete.

## Complexity Tracking

*Required justification for Constitution Principle I violation:*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Replace TypeScript with Nix | User explicitly requested nixidy migration with "full transition" - no hybrid approach | cdk8s enhancement explicitly rejected by user |
| Non-CNOE technology | nixidy provides NixOS-style declarative configuration for Kubernetes | No CNOE-endorsed Nix-based alternative exists |
| Multiple environment files | Nix module system requires separate files for environment-specific config | Single file approach incompatible with nixidy's flake-based architecture |

## Migration Strategy

### Phase 1: Parallel Implementation
1. Create `nixidy/` directory structure alongside existing `cdk8s/`
2. Implement 5-10 representative applications to validate approach
3. Compare generated manifests with `scripts/compare-manifests.sh`

### Phase 2: Incremental Migration
1. Migrate remaining 70+ applications in batches
2. Validate each batch against cdk8s output
3. Document any intentional differences

### Phase 3: Cutover
1. Update CLAUDE.md and documentation
2. Update CI/CD pipelines
3. Archive `cdk8s/` directory
4. Update constitution (Principle I amendment)

## Environment Variable Mapping

Current cdk8s environment variables → nixidy equivalents:

| cdk8s Variable | nixidy Approach |
|----------------|-----------------|
| `CLUSTER_TYPE` | Flake output selector (`.#kind`, `.#talos`) |
| `CLUSTER_NAME` | `builtins.getEnv "CLUSTER_NAME"` in env/variables.nix |
| `INGRESS_HOST` | Module option with default |
| `AZURE_CLIENT_ID` | Required option for talos environment |
| `AZURE_TENANT_ID` | Required option for talos environment |
| `AZURE_KEYVAULT_NAME` | Required option for talos environment |
| `GIT_REPO_URL` | Required option for talos environment |
| `GIT_BRANCH` | Optional with default "main" |
