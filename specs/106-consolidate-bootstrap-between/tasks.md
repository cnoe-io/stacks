# Implementation Tasks: Consolidate Bootstrap Between KIND and Talos Clusters

**Feature**: 106-consolidate-bootstrap-between
**Branch**: `106-consolidate-bootstrap-between`
**Generated**: 2025-12-07 (Revised)
**Plan**: [plan.md](./plan.md) | **Spec**: [spec.md](./spec.md)

## Task Legend

- `[ ]` Not started
- `[x]` Completed
- Priority: P1 (Critical), P2 (High), P3 (Medium)
- Effort: S (Small, <1hr), M (Medium, 1-4hr), L (Large, 4-8hr)

---

## Phase 1: Source URL Utility

Create centralized ArgoCD source URL logic.

### Task 1.1: Create cdk8s/lib/source-url.ts
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Create utility for generating ArgoCD Application source URLs based on cluster type
- **Files**:
  - `cdk8s/lib/source-url.ts` (CREATE)
- **Implementation**:
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
- **Validation**:
  ```bash
  cd cdk8s
  npx tsc --noEmit  # Compiles without errors
  ```

---

## Phase 2: Merge Application Configs

Consolidate application configurations into single file.

### Task 2.1: Add clusterType to ApplicationConfig interface
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Update ApplicationConfig interface to include clusterType field
- **Files**:
  - `cdk8s/config/applications.ts` (MODIFY)
- **Changes**:
  - Add `clusterType: 'kind' | 'talos' | 'both'` to interface
  - Add type export for ClusterType
- **Validation**:
  ```bash
  npx tsc --noEmit
  ```

### Task 2.2: Merge talos-applications.ts into applications.ts
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Copy all Talos app configs into applications.ts with clusterType field
- **Files**:
  - `cdk8s/config/applications.ts` (MODIFY)
  - `cdk8s/config/talos-applications.ts` (DELETE after merge)
- **Steps**:
  1. Add `clusterType: 'kind'` to all existing KIND apps
  2. Copy Talos apps with `clusterType: 'talos'`
  3. Identify shared apps and mark as `clusterType: 'both'`
  4. Delete talos-applications.ts
- **Validation**:
  ```bash
  npx tsc --noEmit
  ls cdk8s/config/talos-applications.ts  # Should fail (file deleted)
  ```

---

## Phase 3: Unified main.ts

Create single synthesis entry point.

### Task 3.1: Create cdk8s/main.ts with merged logic
- **Priority**: P1 | **Effort**: L
- **Status**: [ ]
- **Description**: Create unified main.ts combining logic from main-v2.ts and main-talos.ts
- **Files**:
  - `cdk8s/main.ts` (CREATE)
- **Key Features**:
  - Read CLUSTER_TYPE from environment
  - Filter apps by clusterType field
  - Use getSourceUrl() for ArgoCD sources
  - Validate required environment variables for Talos
  - Generate kustomization.yaml per app
- **Validation**:
  ```bash
  CLUSTER_TYPE=kind npx ts-node main.ts
  CLUSTER_TYPE=talos npx ts-node main.ts
  ```

### Task 3.2: Update package.json synth script
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Update npm scripts to use new main.ts
- **Files**:
  - `cdk8s/package.json` (MODIFY)
- **Changes**:
  ```json
  {
    "scripts": {
      "synth": "ts-node main.ts",
      "synth:kind": "CLUSTER_TYPE=kind ts-node main.ts",
      "synth:talos": "CLUSTER_TYPE=talos ts-node main.ts"
    }
  }
  ```
- **Validation**:
  ```bash
  npm run synth:kind
  npm run synth:talos
  ```

### Task 3.3: Delete old main files
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Remove main-v2.ts and main-talos.ts after main.ts is working
- **Files**:
  - `cdk8s/main-v2.ts` (DELETE)
  - `cdk8s/main-talos.ts` (DELETE)
- **Dependencies**: Task 3.1, 3.2 must pass validation
- **Validation**:
  ```bash
  ls cdk8s/main-v2.ts cdk8s/main-talos.ts  # Both should fail (files deleted)
  npm run synth  # Still works
  ```

### Task 3.4: Verify synthesis output for both cluster types
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: End-to-end validation of synthesis for both cluster types
- **Files**: N/A (testing)
- **Test Steps**:
  1. KIND synthesis produces `cnoe://` URLs
  2. Talos synthesis produces GitHub URLs
  3. Both produce valid YAML (kubectl --dry-run=client)
  4. Workload identity annotations are correct
- **Validation**:
  ```bash
  cd cdk8s
  CLUSTER_TYPE=kind npm run synth
  grep -r "cnoe://" dist/*.yaml | head -5  # Should find cnoe:// URLs

  CLUSTER_TYPE=talos npm run synth
  grep -r "github.com" dist/*.yaml | head -5  # Should find GitHub URLs
  ```

---

## Phase 4: Environment File Consolidation

Standardize environment file naming.

### Task 4.1: Rename wi.env to kind.env
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Rename environment file for consistency
- **Files**:
  - `.env-files/wi.env` → `.env-files/kind.env` (RENAME)
- **Validation**:
  ```bash
  ls .env-files/kind.env  # Exists
  ls .env-files/wi.env 2>&1 | grep "No such file"  # Gone
  ```

### Task 4.2: Add CLUSTER_TYPE to environment files
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Ensure CLUSTER_TYPE is set in both env files
- **Files**:
  - `.env-files/kind.env` (MODIFY)
  - `.env-files/talos.env` (MODIFY if needed)
- **Validation**:
  ```bash
  grep "CLUSTER_TYPE=kind" .env-files/kind.env
  grep "CLUSTER_TYPE=talos" .env-files/talos.env
  ```

### Task 4.3: Update scripts referencing wi.env
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Find and update any hardcoded references to wi.env
- **Files**:
  - `deployment/scripts/cluster-menu.sh` (MODIFY if needed)
  - `.envrc` (MODIFY if needed)
  - `cdk8s/.envrc` (MODIFY if needed)
- **Validation**:
  ```bash
  grep -r "wi.env" . --include="*.sh" --include=".envrc"  # Should return nothing
  ```

---

## Phase 5: Script Updates

Update orchestrators and deprecate legacy scripts.

### Task 5.1: Update cluster-menu.sh synthesis command
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Ensure cluster-menu.sh uses unified synthesis
- **Files**:
  - `deployment/scripts/cluster-menu.sh` (MODIFY)
- **Changes**:
  - Update synthesis to use `npm run synth` (already uses this)
  - Ensure CLUSTER_TYPE=kind is set before synthesis
- **Validation**:
  ```bash
  source deployment/scripts/cluster-menu.sh
  cluster-synth  # Works with new main.ts
  ```

### Task 5.2: Update bootstrap-cluster.sh synthesis command
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Update Talos bootstrap to use unified synthesis
- **Files**:
  - `scripts/bootstrap-cluster.sh` (MODIFY)
- **Changes**:
  - Update synthesis command to use `npm run synth` instead of `npx ts-node main-talos.ts`
  - Ensure CLUSTER_TYPE=talos is set
- **Validation**:
  ```bash
  CLUSTER_TYPE=talos ./scripts/bootstrap-cluster.sh --dry-run  # If available
  ```

### Task 5.3: Add deprecation warning to legacy scripts
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Add warnings to wi-kind.sh and wi-kind-lib.sh
- **Files**:
  - `scripts/wi-kind.sh` (MODIFY)
  - `scripts/wi-kind-lib.sh` (MODIFY)
- **Warning to add**:
  ```bash
  echo "⚠️  DEPRECATED: This script is deprecated."
  echo "   Use: source deployment/scripts/cluster-menu.sh && cluster-deploy"
  echo "   See CLAUDE.md for updated documentation."
  ```
- **Validation**:
  ```bash
  source scripts/wi-kind-lib.sh 2>&1 | grep -i "deprecated"
  ```

### Task 5.4: Update CLAUDE.md documentation
- **Priority**: P2 | **Effort**: M
- **Status**: [ ]
- **Description**: Update documentation with new unified workflow
- **Files**:
  - `CLAUDE.md` (MODIFY)
- **Sections to update**:
  - CDK8s synthesis commands
  - Environment file references (wi.env → kind.env)
  - Remove references to separate main-talos.ts
  - Add CLUSTER_TYPE documentation
- **Validation**: Manual review of CLAUDE.md accuracy

---

## Phase 6: End-to-End Testing

Validate complete deployment flows.

### Task 6.1: Test KIND deployment end-to-end
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Full deployment test on KIND cluster
- **Files**: N/A (testing)
- **Test Steps**:
  1. Source environment: `source .env-files/kind.env`
  2. Run synthesis: `cd cdk8s && npm run synth`
  3. Verify output: `grep -r "cnoe://" dist/*.yaml`
  4. Deploy: `source deployment/scripts/cluster-menu.sh && cluster-deploy`
  5. Verify: `kubectl get applications -n argocd`
- **Validation**: All ArgoCD applications sync successfully

### Task 6.2: Test Talos deployment end-to-end
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Full deployment test on Talos cluster
- **Files**: N/A (testing)
- **Test Steps**:
  1. Source environment: `source .env-files/talos.env`
  2. Run synthesis: `cd cdk8s && npm run synth`
  3. Verify output: `grep -r "github.com" dist/*.yaml`
  4. Deploy: `./scripts/bootstrap-cluster.sh`
  5. Verify: `kubectl get applications -n argocd`
- **Validation**: All ArgoCD applications sync successfully

---

## Summary

| Phase | Tasks | Priority Mix | Est. Effort |
|-------|-------|--------------|-------------|
| Phase 1: Source URL Utility | 1 | P1 | S |
| Phase 2: Merge App Configs | 2 | P1 | S+M |
| Phase 3: Unified main.ts | 4 | P1 | L+S+S+M |
| Phase 4: Environment Files | 3 | P1 | S+S+S |
| Phase 5: Script Updates | 4 | P2 | S+S+S+M |
| Phase 6: E2E Testing | 2 | P1 | M+M |

**Total Tasks**: 16 (reduced from 33 in original plan)
**Critical Path**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 6

---

## Progress Tracking

### Completed
- [x] Research codebase and document current state
- [x] Revise spec.md with simplified requirements
- [x] Revise plan.md with merged file approach
- [x] Revise tasks.md with reduced task count

### In Progress
- [ ] Phase 1 tasks (next to implement)

### Blocked
- None

---

*Generated by /speckit.tasks workflow (revised)*
