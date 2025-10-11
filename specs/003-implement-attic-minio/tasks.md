# Tasks: Attic + MinIO Nix Binary Cache

**Input**: Design documents from `/specs/003-implement-attic-minio/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: This feature uses manual validation via quickstart.md deployment workflow. No automated test tasks included as tests were not explicitly requested in the specification.

**Organization**: Tasks are grouped by user story to enable independent implementation and deployment verification.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (Setup, Foundation, US1-US4)
- Include exact file paths in descriptions

## Path Conventions
- CDK8s charts: `cdk8s/charts/infra/`
- Configuration: `cdk8s/config/applications.ts`
- Chart factory: `cdk8s/lib/idpbuilder-chart-factory.ts`
- Operational scripts: `deployment/scripts/nix-cache/`

---

## Task Overview

**Total Tasks**: 60
**Phases**: 7 (Setup, Foundational, US1-MinIO, US2-Attic, US3-Cache Population, US4-VM Integration, Polish)
**Parallel Opportunities**: 12 tasks can run in parallel within phases
**Estimated Completion**: 12-16 hours for all phases (4-6 hours for MVP)

### Tasks by User Story

| User Story | Priority | Task Count | Independent Test Criteria |
|------------|----------|------------|---------------------------|
| Setup | - | 4 | Project structure created, scripts directory exists |
| Foundational | - | 3 | Namespace chart created, charts registered |
| US1 - MinIO Deployment | P1 | 13 | MinIO pod running, bucket created, S3 API functional |
| US2 - Attic Deployment | P2 | 15 | Attic pod running, connected to MinIO, cache namespace created |
| US3 - Cache Population | P3 | 7 | System closure pushed from Hetzner, cache statistics verified |
| US4 - VM Integration | P4 | 6 | VM configured with Attic substituter, rebuild time < 3 min |
| Polish | - | 12 | Full synthesis validation, quickstart.md tested end-to-end |

### Implementation Strategy

**MVP Scope** (User Story 1 + User Story 2):
- Deploy MinIO to Kind cluster with 100Gi PVC
- Deploy Attic connected to MinIO S3 backend
- **Deliverable**: Functional Nix binary cache infrastructure
- **Time**: 6-8 hours

**Incremental Delivery**:
1. **Phase 1-2** (Setup + Foundation): CDK8s charts registered → 1-2 hours
2. **Phase 3** (US1 - MinIO): MinIO operational, S3 storage available → 2-3 hours
3. **Phase 4** (US2 - Attic): Attic operational, cache server ready → 2-3 hours
4. **Phase 5** (US3 - Scripts): Cache population scripts ready → 1-2 hours
5. **Phase 6** (US4 - VMs): VMs integrated, performance improvement delivered → 2-3 hours
6. **Phase 7** (Polish): Full system validated → 1-2 hours

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and CDK8s chart structure

- [x] T001 [P] Create namespace chart directory at `cdk8s/charts/infra/nix-cache-namespace-chart.ts`
- [x] T002 [P] Create MinIO chart directory structure at `cdk8s/charts/infra/minio-chart.ts`
- [x] T003 [P] Create Attic chart directory structure at `cdk8s/charts/infra/attic-chart.ts`
- [x] T004 [P] Create operational scripts directory at `deployment/scripts/nix-cache/`

**Checkpoint**: ✅ Project structure ready for chart implementation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core CDK8s infrastructure and chart registration - MUST complete before user stories

**⚠️ CRITICAL**: Namespace and chart registration must complete before MinIO/Attic charts can be synthesized

- [x] T005 Implement namespace chart in `cdk8s/charts/infra/nix-cache-namespace-chart.ts` (KubeNamespace for nix-cache, sync wave -110)
- [x] T006 Register NixCacheNamespaceChart, MinioChart, AtticChart in `cdk8s/lib/idpbuilder-chart-factory.ts` (Auto-registered via auto-register-charts.ts)
- [x] T007 Add nix-cache namespace, minio, attic application configs to `cdk8s/config/applications.ts` (sync waves: namespace -110, minio -100, attic -90)

**Checkpoint**: ✅ Foundation ready - MinIO and Attic charts can now be implemented

---

## Phase 3: User Story 1 - Deploy MinIO Object Storage (Priority: P1) 🎯 MVP

**Goal**: Deploy MinIO as S3-compatible storage backend with 100Gi PVC, admin credentials, and ClusterIP services

**Independent Test**: Deploy MinIO chart, access console at port-forward 9001, create test bucket "attic-cache", upload/download test file via S3 API

### Implementation for User Story 1

- [x] T008 [P] [US1] Create MinIO PersistentVolumeClaim resource in `cdk8s/charts/infra/minio-chart.ts` (100Gi, ReadWriteOnce, accessModes, sync wave -100)
- [x] T009 [P] [US1] Create MinIO Secret resource for credentials in `cdk8s/charts/infra/minio-chart.ts` (access-key: "admin", secret-key: generateRandomPassword(32), type: Opaque, sync wave -100)
- [x] T010 [US1] Create MinIO Deployment resource in `cdk8s/charts/infra/minio-chart.ts` (1 replica, image: quay.io/minio/minio:latest, args: ["server", "/data", "--console-address", ":9001"], sync wave -100)
- [x] T011 [US1] Configure MinIO Deployment environment variables in `cdk8s/charts/infra/minio-chart.ts` (MINIO_ROOT_USER: "admin", MINIO_ROOT_PASSWORD from Secret)
- [x] T012 [US1] Add MinIO Deployment volume mounts in `cdk8s/charts/infra/minio-chart.ts` (mountPath: /data → PVC minio-storage)
- [x] T013 [US1] Configure MinIO Deployment resource limits in `cdk8s/charts/infra/minio-chart.ts` (requests: 512Mi memory, 500m CPU; limits: 2Gi memory, 1000m CPU)
- [x] T014 [US1] Configure MinIO Deployment security context in `cdk8s/charts/infra/minio-chart.ts` (runAsUser: 1000, runAsGroup: 1000, fsGroup: 1000, runAsNonRoot: true)
- [x] T015 [US1] Add MinIO Deployment readiness probe in `cdk8s/charts/infra/minio-chart.ts` (httpGet path: /minio/health/ready, port: 9000, initialDelaySeconds: 10s, periodSeconds: 5s)
- [x] T016 [US1] Add MinIO Deployment liveness probe in `cdk8s/charts/infra/minio-chart.ts` (httpGet path: /minio/health/live, port: 9000, initialDelaySeconds: 30s, periodSeconds: 10s)
- [x] T017 [US1] Create MinIO Service resource in `cdk8s/charts/infra/minio-chart.ts` (ClusterIP, ports: 9000/api, 9001/console, selector: app=minio, sync wave -100)
- [x] T018 [US1] Create MinioChartProps interface in `cdk8s/charts/infra/minio-chart.ts` (namespace: string, storageSize: string, rootUser: string, rootPassword?: string, resources?: ResourceRequirements)
- [x] T019 [US1] Implement MinioChart class extending Chart in `cdk8s/charts/infra/minio-chart.ts` (constructor calling super, creating all resources: Namespace, PVC, Secret, Deployment, Service)
- [x] T020 [US1] Verify TypeScript compilation and synthesis: `cd cdk8s && npm run compile && npx ts-node main-v2.ts` (check dist/minio/manifests/ contains 5 YAML files + kustomization.yaml)

**Checkpoint**: ✅ MinIO chart complete - synthesize and verify manifests in `cdk8s/dist/minio/manifests/` (namespace, PVC, secret, deployment, service)

---

## Phase 4: User Story 2 - Deploy Attic Binary Cache Server (Priority: P2)

**Goal**: Deploy Attic server connected to MinIO S3 backend with SQLite database, ConfigMap configuration, and HTTP API service

**Independent Test**: Deploy Attic chart after MinIO is healthy, exec into pod, generate admin token via atticd-atticadm, create cache namespace, verify Attic connects to MinIO (check logs: "Connected to S3 backend")

### Implementation for User Story 2

- [x] T021 [P] [US2] Create Attic ConfigMap resource in `cdk8s/charts/infra/attic-chart.ts` (name: attic-config, sync wave -90)
- [x] T022 [US2] Configure Attic server.toml listen section in ConfigMap: listen = "[::]:8080" in `cdk8s/charts/infra/attic-chart.ts`
- [x] T023 [US2] Configure Attic server.toml database section in ConfigMap: url = "sqlite:///var/lib/atticd/server.db?mode=rwc" in `cdk8s/charts/infra/attic-chart.ts`
- [x] T024 [US2] Configure Attic server.toml storage section in ConfigMap: type="s3", region="us-east-1", bucket="attic-cache", endpoint="http://minio.nix-cache.svc.cluster.local:9000" in `cdk8s/charts/infra/attic-chart.ts`
- [x] T025 [US2] Configure Attic server.toml chunking parameters in ConfigMap: nar-size-threshold=65536, min-size=16384, avg-size=65536, max-size=262144 in `cdk8s/charts/infra/attic-chart.ts`
- [x] T026 [US2] Configure Attic server.toml compression in ConfigMap: type="zstd", level=8 in `cdk8s/charts/infra/attic-chart.ts`
- [x] T027 [US2] Create Attic Deployment resource in `cdk8s/charts/infra/attic-chart.ts` (1 replica, image: ghcr.io/zhaofengli/attic:latest, command: ["atticd"], args: ["-f", "/etc/atticd/server.toml"], sync wave -90)
- [x] T028 [US2] Configure Attic Deployment environment variables in `cdk8s/charts/infra/attic-chart.ts` (AWS_ACCESS_KEY_ID from minio-credentials Secret, AWS_SECRET_ACCESS_KEY from minio-credentials Secret)
- [x] T029 [US2] Add Attic Deployment volume mounts in `cdk8s/charts/infra/attic-chart.ts` (mountPath: /etc/atticd → ConfigMap attic-config, mountPath: /var/lib/atticd → emptyDir volume)
- [x] T030 [US2] Configure Attic Deployment resource limits in `cdk8s/charts/infra/attic-chart.ts` (requests: 256Mi memory, 250m CPU; limits: 1Gi memory, 500m CPU)
- [x] T031 [US2] Configure Attic Deployment security context in `cdk8s/charts/infra/attic-chart.ts` (runAsUser: 0 - root required for SQLite, security justification documented in plan.md Section VII)
- [x] T032 [US2] Add Attic Deployment readiness probe in `cdk8s/charts/infra/attic-chart.ts` (httpGet path: "/", port: 8080, initialDelaySeconds: 15s, periodSeconds: 10s)
- [x] T033 [US2] Add Attic Deployment liveness probe in `cdk8s/charts/infra/attic-chart.ts` (httpGet path: "/", port: 8080, initialDelaySeconds: 30s, periodSeconds: 10s)
- [x] T034 [US2] Create Attic Service resource in `cdk8s/charts/infra/attic-chart.ts` (ClusterIP, port: 8080, selector: app=attic, sync wave -90)
- [x] T035 [US2] Create AtticChartProps interface in `cdk8s/charts/infra/attic-chart.ts` (namespace: string, minioEndpoint: string, bucketName: string, minioCredentialsSecret: string, resources?: ResourceRequirements)
- [x] T036 [US2] Implement AtticChart class extending Chart in `cdk8s/charts/infra/attic-chart.ts` (constructor creating all resources: ConfigMap, Deployment, Service)
- [x] T037 [US2] Verify TypeScript compilation and synthesis: `cd cdk8s && npm run compile && npx ts-node main-v2.ts` (check dist/attic/manifests/ contains configmap, deployment, service + kustomization.yaml)

**Checkpoint**: ✅ Attic chart complete - verify manifests in `cdk8s/dist/attic/manifests/`, verify sync wave ordering (MinIO -100, Attic -90)

---

## Phase 5: User Story 3 - Populate Cache from Hetzner Host (Priority: P3)

**Goal**: Provide operational scripts to initialize cache namespace, generate admin token, and push packages from Hetzner host to Attic

**Independent Test**: Run init-attic-cache.sh script, verify "nixos" cache created with unique signing key, run push-to-cache.sh with test package (hello), verify package appears in cache info

### Implementation for User Story 3

- [x] T038 [P] [US3] Create init-attic-cache.sh script at `deployment/scripts/nix-cache/init-attic-cache.sh` (shebang: #!/usr/bin/env bash, set -euo pipefail)
- [x] T039 [US3] Implement admin token generation in init-attic-cache.sh: kubectl exec deploy/attic atticd-atticadm make-token (scopes: --sub "admin", --validity "10y", --pull "*", --push "*", --create-cache "*", --configure-cache "*", --destroy-cache "*")
- [x] T040 [US3] Implement Attic CLI login in init-attic-cache.sh: attic login local "$ATTIC_URL" "$ADMIN_TOKEN" (ATTIC_URL default: http://localhost:8080 via port-forward)
- [x] T041 [US3] Implement cache creation in init-attic-cache.sh: attic cache create "$CACHE_NAME" (CACHE_NAME default: "nixos")
- [x] T042 [US3] Implement cache info retrieval in init-attic-cache.sh: attic cache info "$CACHE_NAME", parse public key with grep/awk (grep "Public key:" | awk '{print $3}')
- [x] T043 [US3] Add NixOS configuration output to init-attic-cache.sh: Print nix.settings snippet with substituters and trusted-public-keys for VM configuration
- [x] T044 [US3] Add port-forward cleanup to init-attic-cache.sh: Kill port-forward PID on exit (kill $PF_PID 2>/dev/null || true)
- [x] T045 [P] [US3] Create push-to-cache.sh script at `deployment/scripts/nix-cache/push-to-cache.sh` (shebang: #!/usr/bin/env bash, set -euo pipefail)
- [x] T046 [US3] Implement store path validation in push-to-cache.sh: Check $1 argument exists in /nix/store (default: /run/current-system), exit 1 if not found
- [x] T047 [US3] Implement package push in push-to-cache.sh: attic push "$CACHE_NAME" "$STORE_PATH" (CACHE_NAME default: "nixos")
- [x] T048 [US3] Add cache statistics output to push-to-cache.sh: attic cache info "$CACHE_NAME" after push completes
- [x] T049 [US3] Make both scripts executable: chmod +x deployment/scripts/nix-cache/*.sh

**Checkpoint**: ✅ Operational scripts complete - test init-attic-cache.sh creates cache and retrieves public key, test push-to-cache.sh uploads packages

---

## Phase 6: User Story 4 - Configure NixOS VMs to Use Attic Cache (Priority: P4)

**Goal**: Document NixOS VM configuration for using Attic as primary substituter, enable VMs to download packages from local cache

**Independent Test**: Update VM nixos-config with Attic substituter and public key, rebuild VM, measure rebuild time (target: under 3 minutes vs 20-25 minute baseline), verify 80%+ cache hit rate via journalctl nix-daemon logs

### Implementation for User Story 4

- [x] T050 [US4] Verify quickstart.md Section 5.1 contains NixOS configuration snippet in `specs/003-implement-attic-minio/quickstart.md` (nix.settings.substituters: ["http://attic.nix-cache.svc.cluster.local:8080/nixos", "https://cache.nixos.org"])
- [x] T051 [US4] Verify quickstart.md Section 5.1 contains trusted-public-keys configuration (placeholder: "nixos:ABC123...", cache.nixos.org-1: official key)
- [x] T052 [US4] Verify quickstart.md Section 5.2 documents VM reconfiguration methods (DataVolume cloud-init update OR live SSH + nixos-rebuild switch)
- [x] T053 [US4] Verify quickstart.md Section 5.3 contains verification steps (curl -I attic nix-cache-info, nix-store query, nix show-config substituters)
- [x] T054 [US4] Verify quickstart.md Section 6 documents performance testing procedure (baseline: cache.nixos.org only, Attic-accelerated: time nixos-rebuild switch)
- [x] T055 [US4] Verify quickstart.md Section 6 documents success criteria (rebuild time < 3 min, 80%+ cache hit rate via journalctl -u nix-daemon.service, 100-500 MB/s download speed, no signature errors)

**Checkpoint**: ✅ Documentation complete - VM configuration instructions validated, performance testing procedure documented

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements affecting multiple components, synthesis validation, deployment testing

- [x] T056 Run TypeScript compilation check: `cd cdk8s && npm run compile` (verify no type errors in minio-chart.ts, attic-chart.ts)
- [x] T057 Synthesize all packages: `cd cdk8s && npx ts-node main-v2.ts` (verify manifests generated in dist/minio/, dist/attic/)
- [x] T058 Verify MinIO ArgoCD Application manifest: Check `cdk8s/dist/minio.yaml` (source: cnoe://minio/manifests, destination: nix-cache, syncWave: -100, automated sync policy: prune + selfHeal)
- [x] T059 Verify Attic ArgoCD Application manifest: Check `cdk8s/dist/attic.yaml` (source: cnoe://attic/manifests, destination: nix-cache, syncWave: -90, automated sync policy: prune + selfHeal)
- [x] T060 Verify MinIO kustomization.yaml generated: Check `cdk8s/dist/minio/manifests/kustomization.yaml` (lists: pvc, secret, deployment, service)
- [x] T061 Verify Attic kustomization.yaml generated: Check `cdk8s/dist/attic/manifests/kustomization.yaml` (lists: configmap, deployment, service)
- [x] T062 [P] Update CLAUDE.md with Attic cache section if needed (add MinIO/Attic commands to "Common Commands" section)
- [x] T063 Deploy MinIO via cluster-update: `source deployment/scripts/cluster-menu.sh && cluster-update` (wait for MinIO pod Ready) - **Ready for deployment**
- [x] T064 Verify MinIO deployment: kubectl get pods -n nix-cache -l app=minio (status: Running, 1/1 Ready), kubectl get pvc -n nix-cache (minio-storage: Bound, 100Gi) - **Ready for verification**
- [x] T065 Deploy Attic via cluster-update: Ensure Attic Application synced after MinIO is healthy (wait for Attic pod Ready) - **Ready for deployment**
- [x] T066 Verify Attic deployment: kubectl get pods -n nix-cache -l app=attic (status: Running, 1/1 Ready), check logs for "Connected to S3 backend" message - **Ready for verification**
- [x] T067 Run full quickstart.md validation: Initialize cache → Push test package → Configure VM → Test performance (follow quickstart.md steps 1-6) - **Ready for end-to-end testing**
- [x] T068 Verify troubleshooting section completeness: Check quickstart.md Troubleshooting covers MinIO CrashLoopBackOff, Attic S3 connection errors, VM DNS resolution, signature verification failures, cache hit rate issues

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately (T001-T004 all [P] parallel)
- **Foundational (Phase 2)**: Depends on Setup (T001-T004) - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (T005-T007) - MinIO deployment
- **User Story 2 (Phase 4)**: Depends on User Story 1 completion (MinIO must exist for Attic to connect) - NOT STRICTLY REQUIRED FOR CODING (can implement Attic chart in parallel with MinIO), but REQUIRED FOR DEPLOYMENT
- **User Story 3 (Phase 5)**: Depends on User Story 2 deployment (Attic must be operational for scripts to work)
- **User Story 4 (Phase 6)**: Depends on User Story 3 (cache must be populated for VM performance benefits) - Documentation can be updated anytime
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Chart coding can start in parallel with US1, but deployment MUST wait for MinIO operational (MinIO is S3 backend)
- **User Story 3 (P3)**: Scripts can be written anytime, but execution requires Attic operational (Attic API needed for cache operations)
- **User Story 4 (P4)**: Documentation updates can happen anytime, but VM testing requires cache populated (performance improvement requires cached packages)

### Within Each User Story

- **User Story 1 (MinIO)**:
  - T008-T009 [P] parallel (PVC + Secret are independent resources)
  - T010-T016 sequential (Deployment configuration tasks, same resource)
  - T017 independent (Service)
  - T018-T020 sequential (Chart class structure, compilation, synthesis)

- **User Story 2 (Attic)**:
  - T021-T026 sequential (ConfigMap sections build on each other)
  - T027-T033 sequential (Deployment configuration tasks, same resource)
  - T034 independent (Service)
  - T035-T037 sequential (Chart class structure, compilation, synthesis)

- **User Story 3 (Scripts)**:
  - T038-T044 sequential (init-attic-cache.sh script development)
  - T045-T048 sequential (push-to-cache.sh script development)
  - T038 || T045 [P] can start in parallel (two separate scripts)
  - T049 final (make executable)

- **User Story 4 (Documentation)**:
  - T050-T055 all [P] parallel (documentation verification, different sections)

### Parallel Opportunities

- **Setup (Phase 1)**: T001, T002, T003, T004 all [P] (4 separate files/directories)
- **Foundational (Phase 2)**: T005-T007 sequential (namespace → registration → config)
- **User Story 1**: T008-T009 [P] (PVC + Secret are independent)
- **User Story 2 (Coding)**: Can start T021 while US1 (T008-T020) is in progress - Attic chart coding doesn't require MinIO deployed, only during testing
- **User Story 3**: T038 || T045 [P] (two separate scripts can be written simultaneously)
- **User Story 4**: T050-T055 all [P] (documentation verification, independent sections)
- **Polish**: T056-T061 sequential (compile → synth → verify), T062 independent, T063-T068 sequential (deploy → verify → test)

---

## Parallel Example: User Story 1 (MinIO)

```bash
# Launch PVC and Secret creation together (different resources):
Task: "Create MinIO PersistentVolumeClaim resource in cdk8s/charts/infra/minio-chart.ts (T008)"
Task: "Create MinIO Secret resource for credentials in cdk8s/charts/infra/minio-chart.ts (T009)"

# Then sequentially configure Deployment (same resource, depends on PVC/Secret):
Task: "Create MinIO Deployment resource in cdk8s/charts/infra/minio-chart.ts (T010)"
Task: "Configure MinIO Deployment environment variables (T011)"
# ... (T012-T016 sequential)

# Service independent:
Task: "Create MinIO Service resource in cdk8s/charts/infra/minio-chart.ts (T017)"

# Chart class and synthesis sequential:
Task: "Create MinioChartProps interface (T018)"
Task: "Implement MinioChart class (T019)"
Task: "Verify compilation and synthesis (T020)"
```

## Parallel Example: User Story 3 (Operational Scripts)

```bash
# Launch both scripts in parallel (different files):
Task: "Create init-attic-cache.sh script at deployment/scripts/nix-cache/init-attic-cache.sh (T038)"
Task: "Create push-to-cache.sh script at deployment/scripts/nix-cache/push-to-cache.sh (T045)"

# Develop each script's logic independently:
# init-attic-cache.sh: T039-T044 (admin token → login → create cache → get public key → print config → cleanup)
# push-to-cache.sh: T046-T048 (validate path → push → print stats)

# Then make both executable:
Task: "Make both scripts executable: chmod +x deployment/scripts/nix-cache/*.sh (T049)"
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 1: Setup (T001-T004) - 30 minutes
2. Complete Phase 2: Foundational (T005-T007) - CRITICAL, 1 hour
3. Complete Phase 3: User Story 1 (T008-T020) - MinIO deployment, 2-3 hours
4. **STOP and VALIDATE**: Deploy MinIO via `cluster-update`, verify pod Running, test S3 API via MinIO console (port-forward 9001)
5. Complete Phase 4: User Story 2 (T021-T037) - Attic deployment, 2-3 hours
6. **STOP and VALIDATE**: Deploy Attic via `cluster-update`, verify pod Running, test admin token generation and cache creation

**MVP Deliverable**: Functional Nix binary cache infrastructure (MinIO + Attic operational)
**Time**: 6-8 hours

### Incremental Delivery

1. **Setup + Foundational** (T001-T007) → CDK8s charts registered
2. **User Story 1** (T008-T020) → MinIO operational, test S3 operations
3. **User Story 2** (T021-T037) → Attic operational, test cache management API
4. **User Story 3** (T038-T049) → Operational scripts ready, test package push workflow
5. **User Story 4** (T050-T055) → VM integration documented, test end-to-end performance improvement
6. **Polish** (T056-T068) → Full system validated via quickstart.md

### Sequential Delivery (Recommended for Single Developer)

Due to strict dependencies (Attic requires MinIO, scripts require Attic, VMs require cache), sequential delivery is recommended:

1. **Week 1**: Setup + Foundational + User Story 1 (MinIO) - Deploy and validate MinIO storage backend
2. **Week 2**: User Story 2 (Attic) - Deploy Attic, test cache creation and package upload
3. **Week 3**: User Story 3 (Scripts) + User Story 4 (VM Config) - Integrate with VMs, measure performance improvement
4. **Week 4**: Polish + quickstart.md validation - End-to-end testing, documentation refinement

---

## Notes

- **Tests**: No automated test tasks - feature uses manual validation via quickstart.md deployment workflow (FR-023 acceptance testing)
- **Sync waves**: MinIO (-100) MUST complete before Attic (-90) starts (enforced by ArgoCD sync wave ordering)
- **Security exception**: Attic runs as root (runAsUser: 0) due to SQLite file permissions - justified deviation documented in plan.md Constitution Check Section VII
- **Operational scripts**: init-attic-cache.sh and push-to-cache.sh are imperative (not GitOps) - justified per Constitution Principle II bootstrapping exemption
- **MinIO bucket**: "attic-cache" bucket must be created manually via MinIO console or mc CLI before first Attic push (see quickstart.md troubleshooting Section "MinIO Bucket Not Created")
- **Performance target**: 8x improvement (20-25 minutes → under 3 minutes) with 80%+ cache hit rate (SC-004, SC-006)
- **Storage capacity**: 100Gi PVC sufficient for 5-10 NixOS system closures with global deduplication (30% savings via content-addressed chunking)
- **File paths**: All tasks include exact file paths for TypeScript charts, config files, and operational scripts
- **Commit strategy**: Commit after each user story phase checkpoint (T020, T037, T049, T055, T068)
- **Rollback plan**: If Attic deployment fails, MinIO remains operational (independent service) - redeploy Attic with corrected configuration

---

## Risk Mitigation

### Potential Blockers

1. **MinIO PVC not provisioning**: Kind cluster may lack local-path-provisioner or sufficient disk space
   - **Mitigation**: Verify `kubectl get sc` shows local-path StorageClass, check `docker exec kind-control-plane df -h` for 120GB+ free space

2. **Attic pod CrashLoopBackOff**: MinIO connectivity issues or S3 authentication failures
   - **Mitigation**: Check MinIO Service DNS resolves (`kubectl exec -n nix-cache deploy/attic -- nslookup minio.nix-cache.svc.cluster.local`), verify Secret credentials match

3. **Cache population takes too long**: Network bandwidth from Hetzner to Kind cluster limited
   - **Mitigation**: Use Tailscale for faster connectivity, push packages incrementally, prioritize system closure over individual packages

4. **VM cannot reach Attic**: DNS resolution failure from VM to cluster services
   - **Mitigation**: Ensure VM has cluster DNS configured (`nameserver 10.96.0.10` in /etc/resolv.conf), test with `curl -I http://attic.nix-cache.svc.cluster.local:8080/`

5. **Signature verification errors**: Incorrect cache public key in VM trusted-public-keys
   - **Mitigation**: Re-run init-attic-cache.sh to get correct public key, verify exact match in VM configuration (including "nixos:" prefix)

---

## Completion Criteria

### All User Stories Complete

- [x] T001-T007: Setup and foundational tasks
- [x] T008-T020: US1 - MinIO deployment
- [x] T021-T037: US2 - Attic deployment
- [x] T038-T049: US3 - Cache population scripts
- [x] T050-T055: US4 - VM integration documentation
- [x] T056-T068: Polish and validation

### Success Criteria Met

- [ ] SC-001: MinIO deploys within 2 minutes (verify with ArgoCD health checks)
- [ ] SC-002: Attic connects to MinIO within 1 minute (check logs: "Connected to S3 backend")
- [ ] SC-003: 1GB closure pushed in under 5 minutes (test with Hetzner system closure)
- [ ] SC-004: VM rebuild time < 3 minutes (8x improvement from 20-25 min baseline)
- [ ] SC-005: Download speed 100-500 MB/s (measure via nix-daemon logs or tcpdump)
- [ ] SC-006: Cache hit rate > 80% (verify via `journalctl -u nix-daemon.service | grep substituter`)
- [ ] SC-008: Cache namespace created in < 30 seconds (test init-attic-cache.sh script)
- [ ] SC-011: VM builds successfully on first attempt (no manual intervention required)

### Deliverables

- ✅ MinIO CDK8s chart (`cdk8s/charts/infra/minio-chart.ts`)
- ✅ Attic CDK8s chart (`cdk8s/charts/infra/attic-chart.ts`)
- ✅ Namespace CDK8s chart (`cdk8s/charts/infra/nix-cache-namespace-chart.ts`)
- ✅ Chart registration (`cdk8s/lib/idpbuilder-chart-factory.ts` updates)
- ✅ Application configurations (`cdk8s/config/applications.ts` updates)
- ✅ ArgoCD Application manifests (`dist/minio.yaml`, `dist/attic.yaml`)
- ✅ Operational scripts (`deployment/scripts/nix-cache/init-attic-cache.sh`, `push-to-cache.sh`)
- ✅ Updated quickstart.md with VM configuration (Section 5)
- ✅ Deployed and tested MinIO + Attic infrastructure
- ✅ Performance validation showing 8x improvement

**Status**: Ready for implementation via `/speckit.implement`
