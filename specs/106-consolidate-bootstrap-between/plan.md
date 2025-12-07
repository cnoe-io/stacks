# Implementation Plan: Consolidate Bootstrap Between KIND and Talos Clusters

**Branch**: `106-consolidate-bootstrap-between` | **Date**: 2025-12-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/106-consolidate-bootstrap-between/spec.md`

## Summary

Consolidate shared scripting and configuration between KIND and Talos cluster bootstrap workflows while preserving cluster-specific deployment strategies. The unified bootstrap will use environment-driven configuration (`.env-files/{cluster_type}.env`) and shared libraries (`scripts/lib/`) with a common entry point (`scripts/bootstrap-cluster.sh`) that dispatches to cluster-appropriate implementations.

## Technical Context

**Language/Version**: Bash 5.x, TypeScript 5.x (CDK8s)
**Primary Dependencies**: Azure CLI, kubectl, direnv, Node.js 18+, npm
**Storage**: Azure Key Vault (secrets), Azure Storage (OIDC static website)
**Testing**: Manual validation via quickstart.md scenarios, shell script validation
**Target Platform**: Linux/macOS (development), Kubernetes 1.29+ (runtime)
**Project Type**: Infrastructure scripts + CDK8s TypeScript
**Performance Goals**: Bootstrap completes in < 10 minutes for either cluster type
**Constraints**: Must maintain backwards compatibility with existing KIND workflow
**Scale/Scope**: 2 cluster types (KIND, Talos), 50+ ArgoCD applications

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

No constitution file exists for this project. Proceeding with best practices:

- [x] Keep implementation simple (shell scripts + TypeScript)
- [x] Avoid over-abstraction (use strategy pattern only where needed)
- [x] Maintain backwards compatibility (keep `wi-kind-lib.sh` as fallback)
- [x] Prefer composition over inheritance in script design

## Project Structure

### Documentation (this feature)

```
specs/106-consolidate-bootstrap-between/
├── plan.md              # This file
├── research.md          # Phase 0 output - completed
├── data-model.md        # Phase 1 output - completed
├── quickstart.md        # Phase 1 output - completed
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```
# Shared Libraries (NEW/MODIFIED)
scripts/
├── lib/
│   ├── common.sh        # Shared utilities (EXISTS - from Talos)
│   ├── azure.sh         # Azure infrastructure (EXISTS - consolidate KIND functions)
│   ├── kind.sh          # NEW: KIND-specific deployment
│   └── talos.sh         # EXISTS: Talos-specific deployment
├── bootstrap-cluster.sh # Unified entry point (MODIFY)
└── .bootstrap-phase     # Phase tracking file

# Environment Configuration (MODIFY)
.env-files/
├── kind.env             # RENAME from wi.env
└── talos.env            # EXISTS

# direnv Configuration (MODIFY)
.envrc                   # Root direnv with cluster detection

# CDK8s (MODIFY)
cdk8s/
├── config/
│   └── applications.ts  # Add CLUSTER_TYPE checks
└── lib/
    └── source-url.ts    # NEW: Centralized source URL logic
```

**Structure Decision**: Infrastructure scripts in `scripts/lib/` with TypeScript CDK8s charts. No separate frontend/backend - this is infrastructure tooling.

## Complexity Tracking

*No constitution violations identified. Design follows simplicity principles.*

## Implementation Phases

### Phase 1: Environment Consolidation

**Goal**: Unified environment file structure and direnv configuration

**Deliverables**:
1. Rename `.env-files/wi.env` to `.env-files/kind.env`
2. Update root `.envrc` with unified `detect_cluster_type()` function
3. Update `cdk8s/.envrc` to use new pattern
4. Document environment variable requirements

**Validation**:
- `cd` into project with KIND context → `echo $CLUSTER_TYPE` returns "kind"
- `cd` into project with Talos context → `echo $CLUSTER_TYPE` returns "talos"

### Phase 2: Common Library Consolidation

**Goal**: Single set of shared utilities

**Deliverables**:
1. Merge KIND `wi-kind-lib.sh` Azure functions into `scripts/lib/azure.sh`
2. Add `detect_cluster_type()` to `scripts/lib/common.sh`
3. Add `require_tool()` function for CLI validation
4. Update logging to match Talos pattern (consistent colors)

**Validation**:
- Both KIND and Talos scripts can source `scripts/lib/common.sh`
- Azure functions work for both cluster types

### Phase 3: Bootstrap Unification

**Goal**: Single entry point that works for both clusters

**Deliverables**:
1. Create `scripts/lib/kind.sh` with KIND-specific deployment functions
2. Modify `scripts/bootstrap-cluster.sh` to dispatch based on `CLUSTER_TYPE`
3. Add phase tracking for resumable bootstrap
4. Implement common validation phase

**Functions in unified bootstrap**:
```
bootstrap-cluster.sh
├── load_environment()      # Load from .env-files/{type}.env
├── validate_prerequisites() # Common validation
├── setup_azure()           # Azure AD app + federated creds
├── synthesize_manifests()  # CDK8s synthesis
├── deploy_argocd()         # Dispatch to kind.sh or talos.sh
└── verify_deployment()     # Common verification
```

**Validation**:
- `./scripts/bootstrap-cluster.sh --setup-azure` works on KIND
- `./scripts/bootstrap-cluster.sh --setup-azure` works on Talos
- Running twice is idempotent for both clusters

### Phase 4: CDK8s Source URL Logic

**Goal**: Synthesis produces correct ArgoCD source URLs per cluster type

**Deliverables**:
1. Create `cdk8s/lib/source-url.ts` utility
2. Update ArgoCD Application charts to use `getSourceUrl()`
3. Test synthesis for both cluster types

**Logic**:
```typescript
export function getSourceUrl(appName: string): string {
  const clusterType = process.env.CLUSTER_TYPE || 'kind';
  const environment = process.env.ENVIRONMENT || 'dev';

  if (clusterType === 'kind' && environment === 'dev') {
    return `cnoe://${appName}/manifests`;
  }
  return process.env.GIT_REPO_URL || 'https://github.com/PittampalliOrg/stacks.git';
}
```

**Validation**:
- KIND synthesis produces `cnoe://` URLs
- Talos synthesis produces GitHub URLs

### Phase 5: Cluster Menu Updates

**Goal**: Consistent cluster menu experience

**Deliverables**:
1. Update `deployment/scripts/cluster-menu.sh` to use shared libraries
2. Ensure `cluster-menu-talos.sh` uses same patterns
3. Add unified status commands

**Validation**:
- `cluster-update` works for KIND
- `tclu` works for Talos
- Both use same underlying synthesis and git logic

## Risk Mitigation

### Backwards Compatibility

- Keep `scripts/wi-kind-lib.sh` unchanged during transition
- Add deprecation warnings if old script is sourced directly
- Document migration path in quickstart.md

### Testing Strategy

1. **Before merge**: Test bootstrap on existing KIND cluster
2. **Before merge**: Test bootstrap on existing Talos cluster
3. **Regression check**: Verify all ArgoCD applications sync successfully
4. **Idempotency check**: Run bootstrap twice, verify no duplicates

## Dependencies

### External Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Azure CLI | 2.50+ | Azure infrastructure management |
| kubectl | 1.29+ | Kubernetes cluster access |
| direnv | 2.32+ | Environment auto-loading |
| Node.js | 18+ | CDK8s synthesis |
| npm | 9+ | Package management |

### Internal Dependencies

| File | Depends On |
|------|------------|
| `scripts/bootstrap-cluster.sh` | `scripts/lib/common.sh`, `scripts/lib/azure.sh` |
| `scripts/lib/azure.sh` | `scripts/lib/common.sh` |
| `scripts/lib/kind.sh` | `scripts/lib/common.sh` |
| `scripts/lib/talos.sh` | `scripts/lib/common.sh` |

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Single bootstrap command | Works for both clusters | Manual test |
| Code duplication reduction | 50%+ | Line count comparison |
| Bootstrap time | < 10 minutes | Timed execution |
| Azure AD app idempotency | No duplicates | `az ad app list` |
| Error message clarity | 95% actionable | Review error outputs |

## Next Steps

After plan approval, run `/speckit.tasks` to generate the implementation task list.
