# Implementation Plan: Consolidate Bootstrap Between KIND and Talos Clusters

**Branch**: `106-consolidate-bootstrap-between` | **Date**: 2025-12-07 | **Spec**: [spec.md](./spec.md)
**Constitution**: v1.3.0 | **Primary Principle**: IX (Unified Cluster Bootstrap)
**Input**: Feature specification from [spec.md](./spec.md)

## Summary

Consolidate CDK8s synthesis and configuration between KIND and Talos clusters by merging entry points, application configs, and environment files. The unified approach uses `CLUSTER_TYPE` environment variable to determine synthesis behavior while keeping cluster-specific orchestrators (cluster-menu.sh for KIND, bootstrap-cluster.sh for Talos).

**Key Outcomes**:
- Single `main.ts` replaces `main-v2.ts` and `main-talos.ts`
- Unified `applications.ts` with `clusterType: 'kind' | 'talos' | 'both'` field
- Centralized `source-url.ts` for ArgoCD Application source URL generation
- Environment files renamed to `.env-files/{cluster_type}.env` convention
- Legacy scripts marked deprecated with warnings

## Technical Context

| Aspect | Value |
|--------|-------|
| **Language/Version** | TypeScript 5.x (CDK8s), Bash 5.x (scripts) |
| **Primary Dependencies** | Node.js 18+, npm, cdk8s 2.x, idpbuilder, Helm 3+, kubectl |
| **Storage** | Azure Key Vault (secrets), Azure Storage (OIDC) |
| **Testing** | Manual validation via synthesis + deployment; TypeScript type checking |
| **Target Platform** | KIND (local dev), Talos (production bare-metal) |
| **Project Type** | Infrastructure-as-Code (CDK8s charts + Bash orchestration) |
| **Performance Goals** | Synthesis < 30s, KIND deploy < 10min, Talos deploy < 15min |
| **Constraints** | No backward compatibility required; full replacement strategy |
| **Scale/Scope** | ~50 applications across both cluster types |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Requirement | Status | Implementation |
|-----------|-------------|--------|----------------|
| **I. Type-Safe IaC** | Single `main.ts` entry point | ✅ PASS | Phase 3: Create unified main.ts |
| **I. Type-Safe IaC** | Reject cluster-specific entry points | ✅ PASS | Phase 3: Delete main-v2.ts, main-talos.ts |
| **II. GitOps-First** | Cluster-type-driven ArgoCD sources | ✅ PASS | Phase 1: source-url.ts utility |
| **II. GitOps-First** | Use cluster-menu.sh for idpbuilder | ✅ PASS | Phase 5: Update cluster-menu.sh |
| **IV. Declarative Config** | Unified `applications.ts` | ✅ PASS | Phase 2: Merge configs |
| **IV. Declarative Config** | `clusterType` field per app | ✅ PASS | Phase 2: Add clusterType field |
| **VI. Package-Based** | Output to `cdk8s/dist/<app>/manifests/` | ✅ PASS | No change needed (existing) |
| **VII. Security** | ESO for secrets (both clusters) | ✅ PASS | No change needed (existing) |
| **IX. Unified Bootstrap** | `CLUSTER_TYPE` environment variable | ✅ PASS | Phase 4: Environment files |
| **IX. Unified Bootstrap** | Deprecate legacy scripts | ✅ PASS | Phase 5: Add warnings |

**Gate Status**: ✅ PASS - All relevant constitution principles satisfied

## Project Structure

### Documentation (this feature)

```
specs/106-consolidate-bootstrap-between/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 research output ✅
├── data-model.md        # Phase 1 data model ✅
├── quickstart.md        # Phase 1 quickstart guide ✅
├── checklists/
│   └── requirements.md  # Spec quality checklist ✅
└── tasks.md             # Implementation tasks ✅
```

### Source Code Changes

```
cdk8s/
├── main.ts              # CREATE: Unified synthesis entry point
├── main-v2.ts           # DELETE: Replaced by main.ts
├── main-talos.ts        # DELETE: Replaced by main.ts
├── lib/
│   └── source-url.ts    # CREATE: Centralized ArgoCD source URL logic
├── config/
│   ├── applications.ts  # MODIFY: Add clusterType field, merge Talos apps
│   └── talos-applications.ts  # DELETE: Merged into applications.ts
└── package.json         # MODIFY: Update synth scripts

.env-files/
├── wi.env               # RENAME → kind.env
├── kind.env             # CREATE (from wi.env rename)
└── talos.env            # MODIFY: Ensure CLUSTER_TYPE=talos

scripts/
├── wi-kind.sh           # MODIFY: Add deprecation warning
├── wi-kind-lib.sh       # MODIFY: Add deprecation warning
└── bootstrap-cluster.sh # MODIFY: Update synthesis command

deployment/scripts/
└── cluster-menu.sh      # MODIFY: Update synthesis command

CLAUDE.md                # MODIFY: Update documentation
```

**Structure Decision**: Infrastructure-as-Code project with TypeScript CDK8s charts and Bash orchestration scripts. No web frontend/backend separation needed.

## File Changes Overview

### Files to CREATE

| File | Purpose | Constitution Principle |
|------|---------|----------------------|
| `cdk8s/main.ts` | Unified synthesis entry point | I, IX |
| `cdk8s/lib/source-url.ts` | Centralized ArgoCD source URL logic | II, IX |
| `.env-files/kind.env` | KIND environment config (from wi.env) | IX |

### Files to DELETE (after merge)

| File | Replacement | Constitution Principle |
|------|-------------|----------------------|
| `cdk8s/main-v2.ts` | `cdk8s/main.ts` | I (reject cluster-specific) |
| `cdk8s/main-talos.ts` | `cdk8s/main.ts` | I (reject cluster-specific) |
| `cdk8s/config/talos-applications.ts` | Merged into `applications.ts` | IV (unified config) |
| `.env-files/wi.env` | Renamed to `kind.env` | IX (naming convention) |

### Files to MODIFY

| File | Changes | Constitution Principle |
|------|---------|----------------------|
| `cdk8s/config/applications.ts` | Add `clusterType` field, merge Talos apps | IV |
| `cdk8s/package.json` | Update `synth` script to use `main.ts` | I |
| `scripts/wi-kind.sh` | Add deprecation warning | IX |
| `scripts/wi-kind-lib.sh` | Add deprecation warning | IX |
| `deployment/scripts/cluster-menu.sh` | Update synthesis command | II, IX |
| `scripts/bootstrap-cluster.sh` | Update synthesis command | IX |
| `CLAUDE.md` | Update documentation | Documentation |

### Files to KEEP (no changes)

| File | Reason |
|------|--------|
| `scripts/lib/common.sh` | Already shared between clusters |
| `scripts/lib/azure.sh` | Already shared between clusters |
| `scripts/lib/talos.sh` | Talos-specific (legitimate distinction) |

## Implementation Phases

### Phase 1: Create Source URL Utility

**Goal**: Centralized logic for ArgoCD source URL generation (Constitution II, IX)

**Deliverables**:
1. Create `cdk8s/lib/source-url.ts`
2. Export `getSourceUrl(appName: string, clusterType: ClusterType): ApplicationSource`
3. Export `getClusterType(): ClusterType` with validation
4. Handle KIND (`cnoe://`) vs Talos (GitHub) URL generation

**Key Implementation**:
```typescript
export type ClusterType = 'kind' | 'talos';

export interface ApplicationSource {
  repoURL: string;
  path?: string;
  targetRevision?: string;
}

export function getSourceUrl(appName: string, clusterType: ClusterType): ApplicationSource {
  if (clusterType === 'kind') {
    return { repoURL: `cnoe://${appName}/manifests` };
  }
  const gitUrl = process.env.GIT_REPO_URL || 'https://github.com/PittampalliOrg/stacks.git';
  const gitBranch = process.env.GIT_BRANCH || 'main';
  return {
    repoURL: gitUrl,
    path: `cdk8s/dist/${appName}/manifests`,
    targetRevision: gitBranch,
  };
}

export function getClusterType(): ClusterType {
  const clusterType = process.env.CLUSTER_TYPE;
  if (!clusterType) {
    console.warn('CLUSTER_TYPE not set, defaulting to "kind"');
    return 'kind';
  }
  if (clusterType !== 'kind' && clusterType !== 'talos') {
    throw new Error(`Unsupported CLUSTER_TYPE: ${clusterType}. Supported: kind, talos`);
  }
  return clusterType;
}
```

**Validation**: `npx tsc --noEmit` (compiles without errors)

### Phase 2: Merge Application Configs

**Goal**: Single applications.ts with clusterType field (Constitution IV)

**Deliverables**:
1. Add `clusterType: 'kind' | 'talos' | 'both'` to ApplicationConfig interface
2. Add `clusterType` field to all existing KIND apps
3. Merge all apps from `talos-applications.ts` with `clusterType: 'talos'`
4. Identify shared apps and mark as `clusterType: 'both'`
5. Delete `talos-applications.ts`

**Example Config**:
```typescript
export interface ApplicationConfig {
  name: string;
  namespace: string;
  clusterType: 'kind' | 'talos' | 'both';
  chart: { type: string; props?: Record<string, unknown> };
  argocd?: { syncWave?: string; labels?: Record<string, string> };
}
```

**Validation**: `npx tsc --noEmit` + verify talos-applications.ts deleted

### Phase 3: Create Unified main.ts

**Goal**: Single synthesis entry point (Constitution I, IX)

**Deliverables**:
1. Create `cdk8s/main.ts` combining logic from both main files
2. Filter apps by clusterType during synthesis
3. Use `getSourceUrl()` for ArgoCD Application sources
4. Validate required environment variables for each cluster type
5. Generate kustomization.yaml per app
6. Update `package.json` synth scripts
7. Delete `main-v2.ts` and `main-talos.ts`

**Key Logic**:
```typescript
import { getClusterType, getSourceUrl } from './lib/source-url';

const clusterType = getClusterType();
const apps = applicationConfigs.filter(app =>
  app.clusterType === 'both' || app.clusterType === clusterType
);

for (const appConfig of apps) {
  const source = getSourceUrl(appConfig.name, clusterType);
  // Generate ArgoCD Application with source
}
```

**Validation**:
- `CLUSTER_TYPE=kind npm run synth` produces cnoe:// URLs
- `CLUSTER_TYPE=talos npm run synth` produces GitHub URLs

### Phase 4: Environment File Consolidation

**Goal**: Consistent naming convention (Constitution IX)

**Deliverables**:
1. Rename `.env-files/wi.env` to `.env-files/kind.env`
2. Add `CLUSTER_TYPE=kind` to kind.env
3. Verify `CLUSTER_TYPE=talos` exists in talos.env
4. Update any scripts that reference wi.env

**Validation**:
- `source .env-files/kind.env && echo $CLUSTER_TYPE` outputs "kind"
- `source .env-files/talos.env && echo $CLUSTER_TYPE` outputs "talos"
- `grep -r "wi.env" . --include="*.sh"` returns nothing

### Phase 5: Script Updates

**Goal**: Update orchestrators and deprecate legacy scripts (Constitution II, IX)

**Deliverables**:
1. Update `cluster-menu.sh` to use new synthesis with `CLUSTER_TYPE=kind`
2. Update `bootstrap-cluster.sh` to use new synthesis with `CLUSTER_TYPE=talos`
3. Add deprecation warnings to `wi-kind.sh` and `wi-kind-lib.sh`
4. Update CLAUDE.md documentation

**Deprecation Warning**:
```bash
echo "⚠️  DEPRECATED: This script is deprecated."
echo "   Use: source deployment/scripts/cluster-menu.sh && cluster-deploy"
echo "   See CLAUDE.md for updated documentation."
```

### Phase 6: End-to-End Testing

**Goal**: Validate complete deployment flows (Constitution IX enforcement)

**Test Matrix**:

| Test | KIND | Talos | Validation |
|------|------|-------|------------|
| Synthesis produces correct URLs | `cnoe://` | GitHub URLs | grep output |
| TypeScript compiles | ✅ | ✅ | `npx tsc --noEmit` |
| kubectl --dry-run=client | ✅ | ✅ | Valid YAML |
| Full deployment | cluster-deploy | bootstrap-cluster.sh | ArgoCD apps sync |

### Phase 7: Constitution Compliance Verification

**Goal**: Final verification of all constitution requirements

**Checklist**:
- [ ] Single `main.ts` is the only synthesis entry point (Principle I)
- [ ] No `main-*.ts` files exist in cdk8s/ (Principle I enforcement)
- [ ] `source-url.ts` generates correct URLs for both cluster types (Principle II)
- [ ] Single `applications.ts` with `clusterType` field (Principle IV)
- [ ] No `*-applications.ts` files exist (Principle IV enforcement)
- [ ] Synthesis succeeds with `CLUSTER_TYPE=kind` (Principle IX)
- [ ] Synthesis succeeds with `CLUSTER_TYPE=talos` (Principle IX)
- [ ] Legacy scripts display deprecation warnings (Principle IX)

## Dependencies

### Execution Order

```
Phase 1 (source-url.ts)
    ↓
Phase 2 (merge configs)
    ↓
Phase 3 (main.ts)
    ↓
Phase 4 (env files)
    ↓
Phase 5 (scripts)
    ↓
Phase 6 (E2E testing)
    ↓
Phase 7 (compliance verification)
```

### External Dependencies

| Tool | Version | Purpose | Required For |
|------|---------|---------|--------------|
| Node.js | 18+ | TypeScript compilation | All phases |
| npm | 9+ | Package management | All phases |
| idpbuilder | latest | KIND deployment | Phase 6 (KIND) |
| Helm | 3+ | Talos ArgoCD installation | Phase 6 (Talos) |
| kubectl | 1.29+ | Kubernetes CLI | Phase 6 |
| talosctl | latest | Talos cluster management | Phase 6 (Talos) |

## Validation Plan

### Per-Phase Validation

| Phase | Validation Command | Expected Result |
|-------|-------------------|-----------------|
| 1 | `npx tsc --noEmit` | Compiles without errors |
| 2 | `npx tsc --noEmit` | Compiles without errors |
| 2 | `ls cdk8s/config/talos-applications.ts` | File not found |
| 3 | `CLUSTER_TYPE=kind npm run synth` | cnoe:// URLs in output |
| 3 | `CLUSTER_TYPE=talos npm run synth` | GitHub URLs in output |
| 3 | `ls cdk8s/main-v2.ts cdk8s/main-talos.ts` | Files not found |
| 4 | `source .env-files/kind.env && echo $CLUSTER_TYPE` | Outputs "kind" |
| 4 | `grep -r "wi.env" . --include="*.sh"` | No matches |
| 5 | `source scripts/wi-kind-lib.sh 2>&1` | Shows deprecation warning |
| 6 | `cluster-deploy` on KIND cluster | ArgoCD apps sync |
| 6 | `bootstrap-cluster.sh` on Talos cluster | ArgoCD apps sync |

### End-to-End Validation

1. **KIND Synthesis Test**:
   ```bash
   cd cdk8s
   CLUSTER_TYPE=kind npm run synth
   grep -r "cnoe://" dist/*.yaml | head -5  # Should find cnoe:// URLs
   ```

2. **Talos Synthesis Test**:
   ```bash
   cd cdk8s
   CLUSTER_TYPE=talos npm run synth
   grep -r "github.com" dist/*.yaml | head -5  # Should find GitHub URLs
   ```

3. **KIND Deployment Test**:
   ```bash
   source deployment/scripts/cluster-menu.sh
   cluster-deploy  # Full deployment on KIND
   kubectl get applications -n argocd  # Verify apps synced
   ```

4. **Talos Deployment Test**:
   ```bash
   source .env-files/talos.env
   ./scripts/bootstrap-cluster.sh
   kubectl get applications -n argocd  # Verify apps synced
   ```

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Files reduced | 3 files eliminated | main-v2.ts + main-talos.ts + talos-applications.ts → 0 |
| Single synth command | Works for both | `npm run synth` with CLUSTER_TYPE |
| TypeScript compiles | No errors | `npx tsc --noEmit` |
| Line count reduction | main.ts < main-v2.ts + main-talos.ts | wc -l comparison |
| KIND deployment | Works | `cluster-deploy` succeeds |
| Talos deployment | Works | `bootstrap-cluster.sh` succeeds |
| Constitution compliance | 100% | All checklist items pass |

## Complexity Tracking

*No constitution violations requiring justification*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Break existing KIND workflow | Medium | High | Keep wi-kind-lib.sh as fallback during transition |
| Environment file migration issues | Low | Medium | Document migration steps in CLAUDE.md |
| CDK8s synthesis regression | Medium | High | Add CI tests for both cluster types |
| Azure credential confusion | Low | High | Validate env vars early in synthesis |

## References

- **Spec**: [spec.md](./spec.md)
- **Research**: [research.md](./research.md)
- **Data Model**: [data-model.md](./data-model.md)
- **Tasks**: [tasks.md](./tasks.md)
- **Constitution**: [.specify/memory/constitution.md](../../.specify/memory/constitution.md)
- **CLAUDE.md**: [../../CLAUDE.md](../../CLAUDE.md)

## Next Steps

Implementation tasks are defined in [tasks.md](./tasks.md) with 19 total tasks across 7 phases.

**Critical Path**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 6 → Phase 7
