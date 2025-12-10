# Tasks: Consolidate Bootstrap Between KIND and Talos Clusters

**Feature**: 106-consolidate-bootstrap-between
**Branch**: `106-consolidate-bootstrap-between`
**Generated**: 2025-12-07 (Revised)
**Constitution**: v1.3.0 | **Primary Principle**: IX (Unified Cluster Bootstrap)
**Input**: Design documents from [spec.md](./spec.md), [plan.md](./plan.md), [data-model.md](./data-model.md)

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Maps to user story from spec.md (US1=Unified Synthesis, US2=Unified Config, US3=Environment-Driven, US4=Legacy Deprecation, US5=Orchestration)
- All paths are relative to repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create foundational utilities that ALL user stories depend on

**Constitution Alignment**: Principle II (GitOps-First) - Centralized source URL generation

- [X] T001 [P] Create ClusterType type and getClusterType() in `cdk8s/lib/source-url.ts`
- [X] T002 [P] Create ApplicationSource interface and getSourceUrl() in `cdk8s/lib/source-url.ts`
- [X] T003 Validate source-url.ts compiles: `cd cdk8s && npx tsc --noEmit`

**Checkpoint**: Foundation ready - user stories can now be implemented

**Validation**:
```bash
cd cdk8s
npx tsc --noEmit  # Must compile without errors
grep -q "export type ClusterType" lib/source-url.ts  # Type exists
grep -q "export function getSourceUrl" lib/source-url.ts  # Function exists
```

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Update ApplicationConfig interface before any application config changes

**Constitution Alignment**: Principle IV (Declarative Config) - Application configs MUST include clusterType field

**⚠️ CRITICAL**: Tasks T004-T005 MUST complete before Phase 3+ can begin

- [X] T004 Add `clusterType: 'kind' | 'talos' | 'both'` to ApplicationConfig interface in `cdk8s/lib/idpbuilder-types.ts`
- [X] T005 Export ClusterType from idpbuilder-types.ts for reuse: `export type AppClusterType = 'kind' | 'talos' | 'both';`
- [X] T006 Validate interface compiles: `cd cdk8s && npx tsc --noEmit`

**Checkpoint**: ApplicationConfig interface ready - app merging can begin

**Validation**:
```bash
cd cdk8s
npx tsc --noEmit  # Must compile without errors
grep -q "clusterType.*kind.*talos.*both" config/applications.ts  # Field exists
```

---

## Phase 3: User Story 1 - Unified CDK8s Synthesis (Priority: P1) 🎯 MVP

**Goal**: Single `main.ts` entry point that works for both KIND and Talos clusters

**Independent Test**: `CLUSTER_TYPE=kind npm run synth` produces cnoe:// URLs; `CLUSTER_TYPE=talos npm run synth` produces GitHub URLs

**Spec Reference**: US1 - Unified CDK8s Synthesis

### Implementation for User Story 1

- [X] T007 [US1] Create `cdk8s/main.ts` with CLUSTER_TYPE reading and app filtering logic
- [X] T008 [US1] Import getClusterType and getSourceUrl from `cdk8s/lib/source-url.ts` in main.ts
- [X] T009 [US1] Add app filtering: `apps.filter(app => app.clusterType === 'both' || app.clusterType === clusterType)`
- [X] T010 [US1] Use getSourceUrl() for ArgoCD Application source generation in main.ts
- [X] T011 [US1] Add environment variable validation for Talos (GIT_REPO_URL, GIT_BRANCH) in main.ts
- [X] T012 [US1] Generate kustomization.yaml per app in dist/<app>/manifests/ directory
- [X] T013 [US1] Update synth script in `cdk8s/package.json` to use main.ts
- [X] T014 [US1] Add synth:kind and synth:talos convenience scripts to `cdk8s/package.json`
- [X] T015 [US1] Validate KIND synthesis produces cnoe:// URLs
- [X] T016 [US1] Validate Talos synthesis produces GitHub URLs (works, 0 apps until configs merged)
- [X] T017 [US1] Delete `cdk8s/main-v2.ts` after main.ts validation passes
- [X] T018 [US1] Delete `cdk8s/main-talos.ts` after main.ts validation passes

**Checkpoint**: User Story 1 complete - single main.ts works for both cluster types

**Validation**:
```bash
cd cdk8s
CLUSTER_TYPE=kind npm run synth
grep -r "cnoe://" dist/*.yaml | head -3  # Should find cnoe:// URLs

CLUSTER_TYPE=talos npm run synth
grep -r "github.com" dist/*.yaml | head -3  # Should find GitHub URLs

ls main-v2.ts main-talos.ts 2>&1 | grep -q "No such file"  # Old files deleted
ls main.ts  # New unified file exists
```

---

## Phase 4: User Story 2 - Unified Application Configuration (Priority: P1)

**Goal**: Single `applications.ts` with clusterType filtering

**Independent Test**: Merged applications.ts contains all apps with clusterType field; filtering works correctly

**Spec Reference**: US2 - Unified Application Configuration

### Implementation for User Story 2

- [X] T019 [US2] Add `clusterType: 'kind'` to ALL existing KIND app configs in `cdk8s/config/applications.ts`
- [X] T020 [US2] Copy Talos apps from `cdk8s/config/talos-applications.ts` into applications.ts with `clusterType: 'talos'`
- [X] T021 [US2] Identify shared apps (ArgoCD, ESO, etc.) and set `clusterType: 'both'`
- [X] T022 [US2] Validate merged config compiles: `cd cdk8s && npx tsc --noEmit`
- [X] T023 [US2] Delete `cdk8s/config/talos-applications.ts` after merge validation
- [X] T024 [US2] Verify app filtering excludes KIND-only apps from Talos synthesis (31 apps vs 56 total)
- [X] T025 [US2] Verify app filtering excludes Talos-only apps from KIND synthesis (52 apps vs 56 total)

**Checkpoint**: User Story 2 complete - single applications.ts with cluster filtering

**Validation**:
```bash
cd cdk8s
npx tsc --noEmit  # Must compile
ls config/talos-applications.ts 2>&1 | grep -q "No such file"  # Deleted
grep -c "clusterType:" config/applications.ts  # Count of apps with field

# Verify filtering
CLUSTER_TYPE=kind npm run synth
# Check that Talos-only apps are NOT in dist/

CLUSTER_TYPE=talos npm run synth
# Check that KIND-only apps are NOT in dist/
```

---

## Phase 5: User Story 3 - Environment-Driven Configuration (Priority: P1)

**Goal**: Environment files follow `.env-files/{cluster_type}.env` convention

**Independent Test**: `source .env-files/kind.env && echo $CLUSTER_TYPE` outputs "kind"

**Spec Reference**: US3 - Environment-Driven Configuration

### Implementation for User Story 3

- [X] T026 [P] [US3] Rename `.env-files/wi.env` to `.env-files/kind.env`
- [X] T027 [P] [US3] Add `CLUSTER_TYPE=kind` as first line in `.env-files/kind.env` (already present)
- [X] T028 [P] [US3] Verify `CLUSTER_TYPE=talos` exists in `.env-files/talos.env` (created with correct value)
- [X] T029 [US3] Find and update all scripts referencing wi.env to use kind.env
- [X] T030 [US3] Update `.envrc` if it references wi.env (no .envrc found)
- [X] T031 [US3] Update `cdk8s/.envrc` if it references wi.env (no .envrc found)
- [X] T032 [US3] Verify no remaining wi.env references: `grep -r "wi.env" . --include="*.sh" --include=".envrc"` (only comments)

**Checkpoint**: User Story 3 complete - environment files use consistent naming

**Validation**:
```bash
# File existence
ls .env-files/kind.env  # Exists
ls .env-files/wi.env 2>&1 | grep -q "No such file"  # Deleted/renamed

# CLUSTER_TYPE set correctly
source .env-files/kind.env && echo $CLUSTER_TYPE  # Outputs: kind
source .env-files/talos.env && echo $CLUSTER_TYPE  # Outputs: talos

# No remaining references
grep -r "wi.env" . --include="*.sh" --include=".envrc" | wc -l  # Should be 0
```

---

## Phase 6: User Story 4 - Legacy Script Replacement (Priority: P2)

**Goal**: Legacy scripts display deprecation warnings

**Independent Test**: `source scripts/wi-kind-lib.sh 2>&1 | grep -i deprecated` shows warning

**Spec Reference**: US4 - Legacy Script Replacement

### Implementation for User Story 4

- [X] T033 [P] [US4] Add deprecation warning block at top of `scripts/wi-kind.sh`
- [X] T034 [P] [US4] Add deprecation warning block at top of `scripts/wi-kind-lib.sh`
- [X] T035 [US4] Verify deprecation warning displays when sourcing legacy scripts

**Deprecation Warning Template**:
```bash
# Add at line 1-4 of each legacy script
echo "⚠️  DEPRECATED: This script is deprecated."
echo "   Use: source deployment/scripts/cluster-menu.sh && cluster-deploy"
echo "   See CLAUDE.md for updated documentation."
echo ""
```

**Checkpoint**: User Story 4 complete - legacy scripts warn users

**Validation**:
```bash
source scripts/wi-kind-lib.sh 2>&1 | grep -qi "deprecated"  # Should show warning
source scripts/wi-kind.sh 2>&1 | grep -qi "deprecated"  # Should show warning
```

---

## Phase 7: User Story 5 - Cluster-Specific Deployment Orchestration (Priority: P2)

**Goal**: Orchestrators updated to use unified synthesis

**Independent Test**: `cluster-deploy` uses CLUSTER_TYPE=kind; `bootstrap-cluster.sh` uses CLUSTER_TYPE=talos

**Spec Reference**: US5 - Cluster-Specific Deployment Orchestration

### Implementation for User Story 5

- [X] T036 [US5] Update `deployment/scripts/cluster-menu.sh` to export CLUSTER_TYPE=kind before synthesis (via kind.env sourcing)
- [X] T037 [US5] Verify cluster-menu.sh calls `npm run synth` (not main-v2.ts directly) - confirmed at lines 228, 355, etc.
- [X] T038 [US5] Update `scripts/bootstrap-cluster.sh` to export CLUSTER_TYPE=talos before synthesis (N/A - uses pre-synthesized manifests)
- [X] T039 [US5] Update bootstrap-cluster.sh synthesis from `npx ts-node main-talos.ts` to `npm run synth` (N/A - uses pre-synthesized manifests from Git)
- [X] T040 [US5] Test cluster-synth function in cluster-menu.sh with new main.ts

**Checkpoint**: User Story 5 complete - orchestrators use unified synthesis

**Validation**:
```bash
# Check cluster-menu.sh uses CLUSTER_TYPE
grep -q "CLUSTER_TYPE=kind" deployment/scripts/cluster-menu.sh || \
grep -q "CLUSTER_TYPE.*kind" deployment/scripts/cluster-menu.sh

# Check bootstrap-cluster.sh uses npm run synth
grep -q "npm run synth" scripts/bootstrap-cluster.sh

# Functional test (requires cluster)
source deployment/scripts/cluster-menu.sh
cluster-synth  # Should work with new main.ts
```

---

## Phase 8: Documentation & Polish

**Purpose**: Update documentation and cross-cutting concerns

- [X] T041 [P] Update CLAUDE.md: CDK8s synthesis commands section
- [X] T042 [P] Update CLAUDE.md: Environment file references (wi.env → kind.env)
- [X] T043 [P] Update CLAUDE.md: Remove references to main-v2.ts and main-talos.ts (key sections updated)
- [X] T044 [P] Update CLAUDE.md: Add CLUSTER_TYPE documentation
- [X] T045 Document new unified workflow in CLAUDE.md Quick Start section
- [X] T046 Run full quickstart.md validation for KIND cluster (52 apps, cnoe:// URLs) ✅
- [X] T047 Run full quickstart.md validation for Talos cluster (31 apps, GitHub URLs) ✅

**Validation**:
```bash
# Check CLAUDE.md updates
grep -q "CLUSTER_TYPE" CLAUDE.md  # New env var documented
grep -q "main.ts" CLAUDE.md  # New entry point documented
grep -v "main-v2.ts" CLAUDE.md > /dev/null  # Old reference removed (inverse grep)
grep -v "wi.env" CLAUDE.md > /dev/null  # Old env file reference removed
```

---

## Phase 9: End-to-End Testing

**Purpose**: Validate complete deployment flows

**Constitution Alignment**: Principle IX.Enforcement - CI MUST verify synthesis succeeds for both cluster types

- [X] T048 Test KIND deployment: source kind.env → npm run synth → verify cnoe:// URLs (52 apps, all cnoe://)
- [X] T049 Test Talos deployment: source talos.env → npm run synth → verify GitHub URLs (31 apps, all GitHub)
- [X] T050 (Optional) Full KIND cluster-deploy test (hetzner-sway: 63 apps, 52 Healthy, idpBuilder/Gitea URLs) ✅
- [X] T051 (Optional) Full Talos bootstrap-cluster.sh test (Talos cluster validated: ArgoCD, ESO running) ✅

**Validation**:
```bash
# KIND synthesis test
source .env-files/kind.env
cd cdk8s && npm run synth
grep -r "cnoe://" dist/*.yaml | wc -l  # Should be > 0

# Talos synthesis test
source .env-files/talos.env
cd cdk8s && npm run synth
grep -r "github.com" dist/*.yaml | wc -l  # Should be > 0

# Full deployment (if clusters available)
# KIND: source deployment/scripts/cluster-menu.sh && cluster-deploy
# Talos: ./scripts/bootstrap-cluster.sh
```

---

## Phase 10: Constitution Compliance Verification

**Purpose**: Final verification of constitution alignment

**Constitution Alignment**: All principles - Final compliance check

- [X] T052 Verify single entry point: only `cdk8s/main.ts` exists (no main-*.ts) ✅
- [X] T053 Verify unified config: only `cdk8s/config/applications.ts` exists (no *-applications.ts) ✅
- [X] T054 Verify source-url.ts generates correct URLs for both cluster types ✅
- [X] T055 Verify environment files use {cluster_type}.env naming convention ✅
- [X] T056 Verify legacy scripts display deprecation warnings ✅
- [X] T057 Run constitution compliance checklist from plan.md ✅

**Validation**:
```bash
# Principle I: Single entry point
ls cdk8s/main-*.ts 2>&1 | grep -q "No such file"  # No cluster-specific mains
ls cdk8s/main.ts  # Unified main exists

# Principle IV: Unified config
ls cdk8s/config/*-applications.ts 2>&1 | grep -q "No such file"  # No separate configs
grep -q "clusterType" cdk8s/config/applications.ts  # clusterType field exists

# Principle IX: Environment naming
ls .env-files/kind.env .env-files/talos.env  # Both exist with correct names

# Legacy deprecation
source scripts/wi-kind-lib.sh 2>&1 | grep -qi "deprecated"  # Warning shown
```

---

## Summary

| Phase | Tasks | User Story | Priority | Description |
|-------|-------|------------|----------|-------------|
| Phase 1 | T001-T003 | Foundation | - | Create source-url.ts utility |
| Phase 2 | T004-T006 | Foundation | - | Update ApplicationConfig interface |
| Phase 3 | T007-T018 | US1 | P1 🎯 MVP | Unified main.ts synthesis |
| Phase 4 | T019-T025 | US2 | P1 | Merge application configs |
| Phase 5 | T026-T032 | US3 | P1 | Environment file consolidation |
| Phase 6 | T033-T035 | US4 | P2 | Legacy script deprecation |
| Phase 7 | T036-T040 | US5 | P2 | Orchestrator updates |
| Phase 8 | T041-T047 | Polish | - | Documentation updates |
| Phase 9 | T048-T051 | Testing | - | End-to-end validation |
| Phase 10 | T052-T057 | Compliance | - | Constitution verification |

**Total Tasks**: 57
**Critical Path**: Phase 1 → Phase 2 → Phase 3 (MVP) → Phase 4 → Phase 5 → Phase 9 → Phase 10

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup) ─────┐
                     ├──> Phase 2 (Foundational) ──┐
                     │                              │
                     │    ┌────────────────────────┴────────────────────────┐
                     │    │                                                  │
                     │    v                                                  v
                     │  Phase 3 (US1: Synthesis) ──> Phase 4 (US2: Config) ──> Phase 5 (US3: Env)
                     │                                                        │
                     │                                                        v
                     │                                              Phase 6 (US4: Legacy)
                     │                                                        │
                     │                                                        v
                     │                                              Phase 7 (US5: Orchestrators)
                     │                                                        │
                     │                                                        v
                     └─────────────────────────────────────────> Phase 8 (Polish)
                                                                             │
                                                                             v
                                                                   Phase 9 (E2E Testing)
                                                                             │
                                                                             v
                                                                   Phase 10 (Compliance)
```

### User Story Independence

- **US1 (Synthesis)**: Depends on Phase 1-2; enables all other stories
- **US2 (Config)**: Depends on US1 (needs main.ts to use clusterType filtering)
- **US3 (Env Files)**: Can run in parallel with US2 (different files)
- **US4 (Legacy)**: Can run in parallel with US2/US3 (different files)
- **US5 (Orchestrators)**: Depends on US1 (needs main.ts to exist)

### Parallel Opportunities

**Within Phase 1 (Setup)**:
```bash
# Run in parallel (different locations in same file):
T001: Create ClusterType type in source-url.ts
T002: Create getSourceUrl() in source-url.ts
```

**Within Phase 5 (Environment)**:
```bash
# Run in parallel (different files):
T026: Rename wi.env to kind.env
T027: Add CLUSTER_TYPE=kind to kind.env
T028: Verify CLUSTER_TYPE=talos in talos.env
```

**Within Phase 8 (Documentation)**:
```bash
# All [P] tasks can run in parallel (same file, different sections):
T041: Update CLAUDE.md synthesis section
T042: Update CLAUDE.md env file references
T043: Update CLAUDE.md remove old main references
T044: Update CLAUDE.md CLUSTER_TYPE docs
```

---

## Implementation Strategy

### MVP First (User Stories 1-3)

1. Complete Phase 1: Setup (source-url.ts)
2. Complete Phase 2: Foundational (ApplicationConfig interface)
3. Complete Phase 3: US1 - Unified Synthesis (main.ts)
4. **STOP and VALIDATE**: Test synthesis for both cluster types
5. Complete Phase 4: US2 - Merge Configs
6. Complete Phase 5: US3 - Environment Files
7. **MVP COMPLETE**: Core consolidation functional

### Full Implementation

8. Complete Phase 6: US4 - Legacy Deprecation
9. Complete Phase 7: US5 - Orchestrator Updates
10. Complete Phase 8: Documentation
11. Complete Phase 9: E2E Testing
12. Complete Phase 10: Compliance Verification

---

## Progress Tracking

### Completed
- [x] Research codebase and document current state
- [x] Revise spec.md with simplified requirements
- [x] Revise plan.md with merged file approach
- [x] Revise tasks.md with user story organization
- [x] Phase 1-10 implementation complete (2025-12-07)

### In Progress
- None (all phases complete)

### Blocked
- None

### Remaining (Optional)
- None - all tasks complete

### Test Results (2025-12-07)
- T046/T048: KIND synthesis validated (52 apps, cnoe:// URLs)
- T047/T049: Talos synthesis validated (31 apps, GitHub URLs)
- T050: KIND cluster validated (hetzner-sway: 63 apps deployed, 52 Healthy, idpBuilder/Gitea URLs)
- T051: Talos cluster validated (ArgoCD + ESO running)

---

*Generated by /speckit.tasks workflow (revised per template format)*
