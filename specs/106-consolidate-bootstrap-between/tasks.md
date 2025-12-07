# Implementation Tasks: Consolidate Bootstrap Between KIND and Talos Clusters

**Feature**: 106-consolidate-bootstrap-between
**Branch**: `106-consolidate-bootstrap-between`
**Generated**: 2025-12-07
**Plan**: [plan.md](./plan.md) | **Spec**: [spec.md](./spec.md)

## Task Legend

- `[ ]` Not started
- `[x]` Completed
- Priority: P1 (Critical), P2 (High), P3 (Medium)
- Effort: S (Small, <1hr), M (Medium, 1-4hr), L (Large, 4-8hr)

---

## Phase 1: Setup

Pre-implementation setup tasks.

### Task 1.1: Create feature branch and worktree
- **Priority**: P1 | **Effort**: S
- **Status**: [x] Completed (branch already exists)
- **Description**: Create feature branch 106-consolidate-bootstrap-between and worktree
- **Files**: N/A
- **Validation**: `git worktree list` shows 106-consolidate-bootstrap-between worktree

### Task 1.2: Document current state baseline
- **Priority**: P1 | **Effort**: S
- **Status**: [x] Completed
- **Description**: Document line counts and duplication metrics for KIND/Talos scripts
- **Files**: `specs/106-consolidate-bootstrap-between/research.md`
- **Validation**: Research document contains consolidation scorecard

---

## Phase 2: Foundational (Common Infrastructure)

Tasks required before user story implementation.

### Task 2.1: Add detect_cluster_type() to common.sh
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Add cluster type detection function to `scripts/lib/common.sh` using kubectl context pattern matching and talosctl availability check
- **Files**:
  - `scripts/lib/common.sh`
- **Dependencies**: None
- **Validation**:
  ```bash
  source scripts/lib/common.sh
  detect_cluster_type  # Returns "kind" or "talos" based on context
  ```

### Task 2.2: Add require_tool() function to common.sh
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Add CLI validation function to check for required tools (kubectl, az, node, npm, direnv)
- **Files**:
  - `scripts/lib/common.sh`
- **Dependencies**: None
- **Validation**:
  ```bash
  source scripts/lib/common.sh
  require_tool kubectl  # Succeeds silently
  require_tool nonexistent  # Exits with error message
  ```

### Task 2.3: Add require_env() function to common.sh
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Add environment variable validation function with clear error messages
- **Files**:
  - `scripts/lib/common.sh`
- **Dependencies**: None
- **Validation**:
  ```bash
  source scripts/lib/common.sh
  AZURE_CLIENT_ID="test" require_env AZURE_CLIENT_ID  # Succeeds
  require_env NONEXISTENT_VAR  # Exits with error
  ```

---

## Phase 3: User Story 1 - Unified Bootstrap Experience (P1)

> As a platform operator, I want a single bootstrap command that works across both KIND and Talos clusters.

### Task 3.1: Create scripts/lib/kind.sh with KIND-specific functions
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Create KIND-specific library with idpBuilder deployment functions extracted from existing `wi-kind-lib.sh`
- **Files**:
  - `scripts/lib/kind.sh` (NEW)
  - `scripts/wi-kind-lib.sh` (reference)
- **Dependencies**: Task 2.1, 2.2, 2.3
- **Functions to include**:
  - `deploy_argocd_kind()` - Deploy ArgoCD via idpBuilder
  - `apply_manifests_kind()` - Push manifests to Gitea via idpBuilder
  - `verify_deployment_kind()` - Verify idpBuilder deployment
- **Validation**:
  ```bash
  source scripts/lib/kind.sh
  type deploy_argocd_kind  # Function exists
  ```

### Task 3.2: Ensure scripts/lib/talos.sh has matching interface
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Verify Talos library has functions with same names as KIND library for consistent dispatch
- **Files**:
  - `scripts/lib/talos.sh`
- **Dependencies**: Task 3.1
- **Functions to verify/add**:
  - `deploy_argocd_talos()` - Deploy ArgoCD via Helm
  - `apply_manifests_talos()` - Apply manifests via kubectl/git
  - `verify_deployment_talos()` - Verify Helm deployment
- **Validation**:
  ```bash
  source scripts/lib/talos.sh
  type deploy_argocd_talos  # Function exists
  ```

### Task 3.3: Update bootstrap-cluster.sh with cluster type dispatch
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Modify main bootstrap script to detect cluster type and dispatch to appropriate library functions
- **Files**:
  - `scripts/bootstrap-cluster.sh`
- **Dependencies**: Task 2.1, 3.1, 3.2
- **Logic**:
  ```bash
  deploy_argocd() {
      case "$CLUSTER_TYPE" in
          kind)  deploy_argocd_kind "$@" ;;
          talos) deploy_argocd_talos "$@" ;;
          *)     log_error "Unknown cluster type: $CLUSTER_TYPE"; return 1 ;;
      esac
  }
  ```
- **Validation**:
  ```bash
  ./scripts/bootstrap-cluster.sh --help  # Shows unified help
  ```

### Task 3.4: Add phase tracking for resumable bootstrap
- **Priority**: P2 | **Effort**: M
- **Status**: [ ]
- **Description**: Implement phase tracking file (`.bootstrap-phase`) to enable resuming failed bootstraps
- **Files**:
  - `scripts/bootstrap-cluster.sh`
  - `scripts/.bootstrap-phase` (generated at runtime)
- **Dependencies**: Task 3.3
- **Phases**: init, validate, azure-setup, synth, deploy, verify
- **Validation**:
  ```bash
  # Start bootstrap, interrupt at synth phase
  ./scripts/bootstrap-cluster.sh
  cat scripts/.bootstrap-phase  # Shows "synth"
  # Resume continues from synth
  ./scripts/bootstrap-cluster.sh
  ```

### Task 3.5: Add comprehensive prerequisite validation
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Add validate phase that checks all prerequisites before proceeding
- **Files**:
  - `scripts/bootstrap-cluster.sh`
- **Dependencies**: Task 2.2, 2.3, 3.3
- **Validations**:
  - kubectl available and context set
  - Azure CLI authenticated
  - Required environment variables set
  - Node.js 18+ available
  - direnv available
- **Validation**:
  ```bash
  # With missing prereq
  unset AZURE_CLIENT_ID
  ./scripts/bootstrap-cluster.sh 2>&1 | grep "AZURE_CLIENT_ID not set"
  ```

---

## Phase 4: User Story 2 - Environment-Driven Configuration (P1)

> As a platform operator, I want cluster-specific configuration to be loaded automatically from environment files.

### Task 4.1: Rename .env-files/wi.env to .env-files/kind.env
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Rename KIND environment file for consistency with naming convention
- **Files**:
  - `.env-files/wi.env` → `.env-files/kind.env`
- **Dependencies**: None
- **Validation**:
  ```bash
  ls .env-files/kind.env  # File exists
  ls .env-files/wi.env 2>&1 | grep "No such file"  # Old file removed
  ```

### Task 4.2: Add CLUSTER_TYPE variable to environment files
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Ensure both environment files have CLUSTER_TYPE variable set
- **Files**:
  - `.env-files/kind.env`
  - `.env-files/talos.env`
- **Dependencies**: Task 4.1
- **Validation**:
  ```bash
  grep "CLUSTER_TYPE=kind" .env-files/kind.env
  grep "CLUSTER_TYPE=talos" .env-files/talos.env
  ```

### Task 4.3: Update root .envrc with unified cluster detection
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Modify root `.envrc` to auto-detect cluster type and load appropriate environment file
- **Files**:
  - `.envrc`
- **Dependencies**: Task 4.1, 4.2
- **Logic**:
  ```bash
  detect_cluster_type() {
      local ctx=$(kubectl config current-context 2>/dev/null || echo "")
      [[ "$ctx" == kind-* ]] && echo "kind" && return
      command -v talosctl &>/dev/null && talosctl config info &>/dev/null && echo "talos" && return
      echo "kind"  # Default
  }

  CLUSTER_TYPE=$(detect_cluster_type)
  source_env ".env-files/${CLUSTER_TYPE}.env"
  ```
- **Validation**:
  ```bash
  # With KIND context
  kubectl config use-context kind-gitops
  cd .. && cd stacks
  echo $CLUSTER_TYPE  # kind

  # With Talos context
  kubectl config use-context admin@talos-cluster
  cd .. && cd stacks
  echo $CLUSTER_TYPE  # talos
  ```

### Task 4.4: Update cdk8s/.envrc to inherit from root
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Modify cdk8s directory `.envrc` to source parent `.envrc` for consistent environment
- **Files**:
  - `cdk8s/.envrc`
- **Dependencies**: Task 4.3
- **Validation**:
  ```bash
  cd cdk8s
  echo $CLUSTER_TYPE  # Inherits from parent
  echo $AZURE_CLIENT_ID  # Environment loaded
  ```

### Task 4.5: Document environment file requirements
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Update quickstart.md with complete environment variable reference
- **Files**:
  - `specs/106-consolidate-bootstrap-between/quickstart.md`
- **Dependencies**: Task 4.1, 4.2
- **Validation**: Quickstart shows all required variables with examples

---

## Phase 5: User Story 3 - CDK8s Synthesis Across Cluster Types (P2)

> As a platform operator, I want CDK8s synthesis to work for both KIND and Talos clusters.

### Task 5.1: Create cdk8s/lib/source-url.ts utility
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Create centralized utility for determining ArgoCD Application source URLs based on cluster type
- **Files**:
  - `cdk8s/lib/source-url.ts` (NEW)
- **Dependencies**: Task 4.2
- **Implementation**:
  ```typescript
  export function getSourceUrl(appName: string): string {
    const clusterType = process.env.CLUSTER_TYPE || 'kind';
    const environment = process.env.ENVIRONMENT || 'dev';

    if (clusterType === 'kind' && environment === 'dev') {
      return `cnoe://${appName}/manifests`;
    }
    return process.env.GIT_REPO_URL || 'https://github.com/PittampalliOrg/stacks.git';
  }

  export function getSourcePath(appName: string): string {
    const clusterType = process.env.CLUSTER_TYPE || 'kind';

    if (clusterType === 'kind') {
      return '';  // cnoe:// handles path
    }
    return `cdk8s/dist/${appName}/manifests`;
  }
  ```
- **Validation**:
  ```bash
  cd cdk8s
  CLUSTER_TYPE=kind npx ts-node -e "import {getSourceUrl} from './lib/source-url'; console.log(getSourceUrl('test'))"
  # Output: cnoe://test/manifests

  CLUSTER_TYPE=talos npx ts-node -e "import {getSourceUrl} from './lib/source-url'; console.log(getSourceUrl('test'))"
  # Output: https://github.com/PittampalliOrg/stacks.git
  ```

### Task 5.2: Update ArgoCD Application charts to use getSourceUrl()
- **Priority**: P2 | **Effort**: M
- **Status**: [ ]
- **Description**: Refactor ArgoCD Application generation to use centralized source URL logic
- **Files**:
  - `cdk8s/lib/idpbuilder-chart-factory.ts`
  - `cdk8s/main-v2.ts`
- **Dependencies**: Task 5.1
- **Validation**:
  ```bash
  # KIND synthesis
  cd cdk8s
  CLUSTER_TYPE=kind npm run synth
  grep -r "cnoe://" dist/  # Should find cnoe:// URLs

  # Talos synthesis
  CLUSTER_TYPE=talos npm run synth
  grep -r "github.com" dist/*.yaml  # Should find GitHub URLs
  ```

### Task 5.3: Add CLUSTER_TYPE to synthesis validation
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Add validation at synthesis start to warn if CLUSTER_TYPE is not set
- **Files**:
  - `cdk8s/main-v2.ts`
- **Dependencies**: Task 5.1
- **Validation**:
  ```bash
  unset CLUSTER_TYPE
  cd cdk8s && npm run synth 2>&1 | grep -i "cluster_type"
  # Should show warning about defaulting to 'kind'
  ```

### Task 5.4: Test synthesis for both cluster types
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: End-to-end validation of synthesis output for both cluster types
- **Files**: N/A (testing)
- **Dependencies**: Task 5.2
- **Test Plan**:
  1. KIND synthesis produces valid manifests with `cnoe://` URLs
  2. Talos synthesis produces valid manifests with GitHub URLs
  3. Both pass `kubectl --dry-run=client` validation
  4. Workload identity ServiceAccount annotations are correct
- **Validation**: All test cases pass

---

## Phase 6: User Story 4 - Shared Azure Infrastructure Setup (P2)

> As a platform operator, I want Azure AD app and federated credential setup to work identically for both cluster types.

### Task 6.1: Merge KIND Azure functions into scripts/lib/azure.sh
- **Priority**: P2 | **Effort**: M
- **Status**: [ ]
- **Description**: Consolidate Azure functions from `wi-kind-lib.sh` into the shared `azure.sh` library
- **Files**:
  - `scripts/lib/azure.sh`
  - `scripts/wi-kind-lib.sh` (reference only)
- **Dependencies**: Task 2.1, 2.2, 2.3
- **Functions to consolidate**:
  - `validate_azure_login()` - Check az login status
  - `create_azure_ad_app()` - Create/get AD app idempotently
  - `create_federated_credential()` - Create federated credential
  - `get_keyvault_secret()` - Retrieve Key Vault secret
  - `upload_to_web_container()` - Upload OIDC files to storage
- **Validation**:
  ```bash
  source scripts/lib/azure.sh
  validate_azure_login  # Works without cluster-specific code
  ```

### Task 6.2: Parameterize Azure functions for cluster type
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Ensure Azure functions use environment variables instead of hardcoded values
- **Files**:
  - `scripts/lib/azure.sh`
- **Dependencies**: Task 6.1
- **Parameters to use**:
  - `$CLUSTER_TYPE` - For app naming (gitops-{type}-{name})
  - `$CLUSTER_NAME` - For resource naming
  - `$SERVICE_ACCOUNT_ISSUER` - For OIDC issuer URL
  - `$AZURE_STORAGE_ACCOUNT` - For JWKS upload
- **Validation**:
  ```bash
  CLUSTER_TYPE=kind CLUSTER_NAME=gitops source scripts/lib/azure.sh
  # Functions use correct app naming
  ```

### Task 6.3: Validate federated credential trailing slash handling
- **Priority**: P1 | **Effort**: S
- **Status**: [ ]
- **Description**: Ensure SERVICE_ACCOUNT_ISSUER validation requires trailing slash
- **Files**:
  - `scripts/lib/azure.sh`
  - `scripts/bootstrap-cluster.sh`
- **Dependencies**: Task 6.2
- **Validation**:
  ```bash
  SERVICE_ACCOUNT_ISSUER="https://test.blob.core.windows.net"  # No trailing slash
  source scripts/lib/azure.sh
  validate_issuer_url "$SERVICE_ACCOUNT_ISSUER"
  # Should fail with "must end with /"
  ```

### Task 6.4: Test Azure setup idempotency
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Verify running `--setup-azure` twice creates no duplicates
- **Files**: N/A (testing)
- **Dependencies**: Task 6.1, 6.2, 6.3
- **Test Plan**:
  1. Run bootstrap with `--setup-azure`
  2. Count Azure AD apps with matching name pattern
  3. Run bootstrap with `--setup-azure` again
  4. Verify same app is reused (count unchanged)
- **Validation**:
  ```bash
  az ad app list --display-name "gitops-*" --query "length(@)"
  # Count before and after should match
  ```

---

## Phase 7: User Story 5 - Cluster-Specific Deployment Strategies (P3)

> As a platform operator, I want the bootstrap to use the appropriate deployment strategy for each cluster type.

### Task 7.1: Implement deploy_argocd_kind() with idpBuilder
- **Priority**: P3 | **Effort**: M
- **Status**: [ ]
- **Description**: Extract idpBuilder deployment logic into kind.sh
- **Files**:
  - `scripts/lib/kind.sh`
- **Dependencies**: Task 3.1
- **Logic**:
  - Run `idpbuilder create --package cdk8s/dist/`
  - Verify ArgoCD pods are running
  - Configure ArgoCD authentication
- **Validation**:
  ```bash
  # On KIND cluster
  source scripts/lib/kind.sh
  deploy_argocd_kind
  kubectl get pods -n argocd  # Should show running pods
  ```

### Task 7.2: Implement deploy_argocd_talos() with Helm
- **Priority**: P3 | **Effort**: S
- **Status**: [ ]
- **Description**: Verify/update Talos deployment using Helm
- **Files**:
  - `scripts/lib/talos.sh`
- **Dependencies**: Task 3.2
- **Logic**:
  - Run `helm install argocd argo/argo-cd`
  - Apply root ArgoCD Application via kubectl
  - Verify ArgoCD pods are running
- **Validation**:
  ```bash
  # On Talos cluster
  source scripts/lib/talos.sh
  deploy_argocd_talos
  kubectl get pods -n argocd  # Should show running pods
  ```

### Task 7.3: Implement apply_manifests dispatch
- **Priority**: P3 | **Effort**: S
- **Status**: [ ]
- **Description**: Add manifest application dispatch based on cluster type
- **Files**:
  - `scripts/bootstrap-cluster.sh`
  - `scripts/lib/kind.sh`
  - `scripts/lib/talos.sh`
- **Dependencies**: Task 7.1, 7.2
- **Logic**:
  - KIND: idpBuilder pushes to Gitea
  - Talos: kubectl apply or git push to GitHub
- **Validation**:
  ```bash
  ./scripts/bootstrap-cluster.sh --deploy-manifests
  # Correct method used for cluster type
  ```

### Task 7.4: Update cluster menu scripts to use shared libraries
- **Priority**: P3 | **Effort**: M
- **Status**: [ ]
- **Description**: Refactor cluster-menu.sh and cluster-menu-talos.sh to source shared libraries
- **Files**:
  - `deployment/scripts/cluster-menu.sh`
  - `deployment/scripts/cluster-menu-talos.sh`
- **Dependencies**: Task 3.1, 3.2
- **Validation**:
  ```bash
  source deployment/scripts/cluster-menu.sh
  cluster-update  # Uses shared synthesis logic

  source deployment/scripts/cluster-menu-talos.sh
  tclu  # Uses shared synthesis logic
  ```

---

## Phase 8: Polish

Final cleanup and documentation tasks.

### Task 8.1: Add deprecation warning to wi-kind-lib.sh
- **Priority**: P3 | **Effort**: S
- **Status**: [ ]
- **Description**: Add warning when old KIND script is sourced directly
- **Files**:
  - `scripts/wi-kind-lib.sh`
- **Dependencies**: Task 3.1
- **Validation**:
  ```bash
  source scripts/wi-kind-lib.sh 2>&1 | grep -i "deprecated"
  # Should show deprecation warning
  ```

### Task 8.2: Update CLAUDE.md with consolidated bootstrap documentation
- **Priority**: P2 | **Effort**: M
- **Status**: [ ]
- **Description**: Update Claude Code instructions with new unified bootstrap workflow
- **Files**:
  - `CLAUDE.md`
- **Dependencies**: All previous tasks
- **Sections to update**:
  - Bootstrap commands
  - Environment configuration
  - Cluster type detection
- **Validation**: CLAUDE.md accurately reflects new workflow

### Task 8.3: Measure and document consolidation metrics
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Calculate lines of code saved and document in research.md
- **Files**:
  - `specs/106-consolidate-bootstrap-between/research.md`
- **Dependencies**: All implementation tasks
- **Metrics**:
  - Lines of code before vs after
  - Number of duplicate functions eliminated
  - Script file count reduction
- **Validation**: Research.md updated with final metrics

### Task 8.4: End-to-end validation on KIND cluster
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Complete bootstrap test on KIND cluster
- **Files**: N/A (testing)
- **Dependencies**: All implementation tasks
- **Test Steps**:
  1. Fresh KIND cluster creation
  2. Run unified bootstrap
  3. Verify ArgoCD running
  4. Verify External Secrets working
  5. Verify workload identity authentication
- **Validation**: All ArgoCD applications sync successfully

### Task 8.5: End-to-end validation on Talos cluster
- **Priority**: P1 | **Effort**: M
- **Status**: [ ]
- **Description**: Complete bootstrap test on Talos cluster
- **Files**: N/A (testing)
- **Dependencies**: All implementation tasks
- **Test Steps**:
  1. Existing Talos cluster
  2. Run unified bootstrap
  3. Verify ArgoCD running
  4. Verify External Secrets working
  5. Verify workload identity authentication
- **Validation**: All ArgoCD applications sync successfully

### Task 8.6: Update spec.md with implementation notes
- **Priority**: P2 | **Effort**: S
- **Status**: [ ]
- **Description**: Add implementation status section to specification
- **Files**:
  - `specs/106-consolidate-bootstrap-between/spec.md`
- **Dependencies**: Task 8.4, 8.5
- **Validation**: Spec shows completed implementation status

---

## Summary

| Phase | Tasks | Priority Mix | Est. Effort |
|-------|-------|--------------|-------------|
| Phase 1: Setup | 2 | P1 | Completed |
| Phase 2: Foundational | 3 | P1 | S+S+S |
| Phase 3: US1 - Unified Bootstrap | 5 | P1/P2 | M+S+M+M+S |
| Phase 4: US2 - Environment Config | 5 | P1/P2 | S+S+M+S+S |
| Phase 5: US3 - CDK8s Synthesis | 4 | P1/P2 | S+M+S+M |
| Phase 6: US4 - Azure Setup | 4 | P1/P2 | M+S+S+M |
| Phase 7: US5 - Deployment Strategies | 4 | P3 | M+S+S+M |
| Phase 8: Polish | 6 | P1/P2/P3 | S+M+S+M+M+S |

**Total Tasks**: 33
**Critical Path**: Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 8 (E2E validation)

---

## Progress Tracking

### Completed
- [x] Task 1.1: Create feature branch and worktree
- [x] Task 1.2: Document current state baseline

### In Progress
- [ ] Phase 2 tasks (next to implement)

### Blocked
- None

---

*Generated by /speckit.tasks workflow*
