# Implementation Plan: Consolidate Bootstrap Between KIND and Talos Clusters

**Branch**: `106-consolidate-bootstrap-between` | **Date**: 2025-12-07 | **Spec**: [spec.md](./spec.md)

## Summary

Consolidate CDK8s synthesis and configuration between KIND and Talos clusters by merging entry points, application configs, and environment files. The unified approach uses `CLUSTER_TYPE` environment variable to determine synthesis behavior while keeping cluster-specific orchestrators (cluster-menu.sh for KIND, bootstrap-cluster.sh for Talos).

## Technical Context

| Aspect | Value |
|--------|-------|
| Language | TypeScript 5.x (CDK8s), Bash 5.x (scripts) |
| Dependencies | Node.js 18+, npm, idpbuilder, Helm, kubectl |
| Storage | Azure Key Vault (secrets), Azure Storage (OIDC) |
| Testing | Manual validation via synthesis and deployment |
| Target Platform | KIND (local dev), Talos (production) |
| Constraints | No backward compatibility required |

## File Changes Overview

### Files to CREATE

| File | Purpose |
|------|---------|
| `cdk8s/main.ts` | Unified synthesis entry point |
| `cdk8s/lib/source-url.ts` | Centralized ArgoCD source URL logic |
| `.env-files/kind.env` | Renamed from wi.env |

### Files to DELETE (after merge)

| File | Replacement |
|------|-------------|
| `cdk8s/main-v2.ts` | `cdk8s/main.ts` |
| `cdk8s/main-talos.ts` | `cdk8s/main.ts` |
| `cdk8s/config/talos-applications.ts` | Merged into `cdk8s/config/applications.ts` |
| `.env-files/wi.env` | Renamed to `.env-files/kind.env` |

### Files to MODIFY

| File | Changes |
|------|---------|
| `cdk8s/config/applications.ts` | Add `clusterType` field, merge Talos apps |
| `cdk8s/package.json` | Update `synth` script to use `main.ts` |
| `scripts/wi-kind.sh` | Add deprecation warning |
| `scripts/wi-kind-lib.sh` | Add deprecation warning |
| `deployment/scripts/cluster-menu.sh` | Update synthesis command |
| `scripts/bootstrap-cluster.sh` | Update synthesis command |
| `CLAUDE.md` | Update documentation |

### Files to KEEP (no changes)

| File | Reason |
|------|--------|
| `scripts/lib/common.sh` | Already shared |
| `scripts/lib/azure.sh` | Already shared |
| `scripts/lib/talos.sh` | Talos-specific functions |

## Implementation Phases

### Phase 1: Create Source URL Utility

**Goal**: Centralized logic for ArgoCD source URL generation

**Deliverables**:
1. Create `cdk8s/lib/source-url.ts`
2. Export `getSourceUrl(appName: string): ApplicationSource` function
3. Handle KIND (`cnoe://`) vs Talos (GitHub) URL generation

**Key Logic**:
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
```

### Phase 2: Merge Application Configs

**Goal**: Single applications.ts with clusterType field

**Deliverables**:
1. Add `clusterType: 'kind' | 'talos' | 'both'` to ApplicationConfig interface
2. Merge all apps from `talos-applications.ts` into `applications.ts`
3. Add clusterType field to each app config
4. Delete `talos-applications.ts`

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

### Phase 3: Create Unified main.ts

**Goal**: Single synthesis entry point

**Deliverables**:
1. Create `cdk8s/main.ts` combining logic from both main files
2. Filter apps by clusterType during synthesis
3. Use `getSourceUrl()` for ArgoCD Application sources
4. Update `package.json` synth script
5. Delete `main-v2.ts` and `main-talos.ts`

**Key Logic**:
```typescript
const clusterType = (process.env.CLUSTER_TYPE || 'kind') as ClusterType;
const apps = applicationConfigs.filter(app =>
  app.clusterType === 'both' || app.clusterType === clusterType
);

for (const appConfig of apps) {
  const source = getSourceUrl(appConfig.name, clusterType);
  // Generate ArgoCD Application with source
}
```

### Phase 4: Environment File Consolidation

**Goal**: Consistent naming convention

**Deliverables**:
1. Rename `.env-files/wi.env` to `.env-files/kind.env`
2. Add `CLUSTER_TYPE=kind` to kind.env
3. Verify `CLUSTER_TYPE=talos` exists in talos.env
4. Update any scripts that reference wi.env

### Phase 5: Script Updates

**Goal**: Update orchestrators and deprecate legacy scripts

**Deliverables**:
1. Update `cluster-menu.sh` to use new synthesis
2. Update `bootstrap-cluster.sh` to use new synthesis
3. Add deprecation warnings to `wi-kind.sh` and `wi-kind-lib.sh`
4. Update CLAUDE.md documentation

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
```

### External Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| Node.js | 18+ | TypeScript compilation |
| npm | 9+ | Package management |
| idpbuilder | latest | KIND deployment |
| Helm | 3+ | Talos ArgoCD installation |

## Validation Plan

### Per-Phase Validation

| Phase | Validation Command |
|-------|-------------------|
| 1 | `npx tsc --noEmit` (compiles) |
| 2 | `npx tsc --noEmit` (compiles) |
| 3 | `CLUSTER_TYPE=kind npm run synth` (produces cnoe:// URLs) |
| 3 | `CLUSTER_TYPE=talos npm run synth` (produces GitHub URLs) |
| 4 | `source .env-files/kind.env && echo $CLUSTER_TYPE` (outputs "kind") |
| 5 | `cluster-deploy` on KIND cluster works |

### End-to-End Validation

1. **KIND Synthesis Test**:
   ```bash
   cd cdk8s
   CLUSTER_TYPE=kind npm run synth
   grep -r "cnoe://" dist/*.yaml  # Should find cnoe:// URLs
   ```

2. **Talos Synthesis Test**:
   ```bash
   cd cdk8s
   CLUSTER_TYPE=talos npm run synth
   grep -r "github.com" dist/*.yaml  # Should find GitHub URLs
   ```

3. **KIND Deployment Test**:
   ```bash
   source deployment/scripts/cluster-menu.sh
   cluster-deploy  # Full deployment on KIND
   kubectl get applications -n argocd  # Verify apps synced
   ```

4. **Talos Deployment Test**:
   ```bash
   ./scripts/bootstrap-cluster.sh
   kubectl get applications -n argocd  # Verify apps synced
   ```

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Files reduced | 3 files | main-v2.ts + main-talos.ts + talos-applications.ts → 0 |
| Single synth command | Works for both | `npm run synth` with CLUSTER_TYPE |
| TypeScript compiles | No errors | `npx tsc --noEmit` |
| KIND deployment | Works | `cluster-deploy` succeeds |
| Talos deployment | Works | `bootstrap-cluster.sh` succeeds |

## Next Steps

After plan approval, run `/speckit.tasks` to generate the implementation task list.
