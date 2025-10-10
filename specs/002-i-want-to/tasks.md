# Tasks: KubeVirt Installation with NixOS VM Images

**Input**: Design documents from `/home/vpittamp/stacks/specs/002-i-want-to/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Organization**: Tasks are grouped by user story (US1-US4 in priority order) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions
- Infrastructure charts: `cdk8s/charts/infra/`
- Application charts: `cdk8s/charts/apps/`
- Shared libraries: `cdk8s/lib/`
- Configuration: `cdk8s/config/applications.ts`
- CRD imports: `cdk8s/imports/`
- NixOS configs: `/etc/nixos/configurations/`
- VM images: `~/stacks/nixos-images/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and CDK8s environment setup

- [ ] T001 [P] Import KubeVirt CRDs to `cdk8s/imports/kubevirt.io.ts` via `npm run import` (add KubeVirt v1.3.1 operator.yaml URL to cdk8s.yaml)
- [ ] T002 [P] Import CDI CRDs to `cdk8s/imports/cdi.kubevirt.io.ts` via `npm run import` (add CDI v1.59.0 operator.yaml URL to cdk8s.yaml)
- [ ] T003 Verify TypeScript compilation passes after CRD imports: `npm run compile` in cdk8s/
- [ ] T004 Create nixos-images directory: `mkdir -p ~/stacks/nixos-images` for storing built qcow2 images

**Checkpoint**: CRD imports complete, TypeScript types available for VirtualMachine and DataVolume

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 Create NixOS vm-minimal.nix configuration in `/etc/nixos/configurations/vm-minimal.nix` (imports base.nix + qemu-guest profile, enables cloud-init and qemu-guest-agent, sets boot.loader.grub.device = "/dev/vda")
- [ ] T006 Build NixOS qcow2 image using nixos-generators: `nix run github:nix-community/nixos-generators -- --format qcow --configuration /etc/nixos/configurations/vm-minimal.nix --out-link ~/stacks/nixos-images/kubevirt-vm.qcow2`
- [ ] T007 Verify qcow2 image created successfully (1-2GB size): `ls -lh ~/stacks/nixos-images/kubevirt-vm.qcow2`
- [ ] T008 [P] Create shared KubeVirt helper library in `cdk8s/lib/kubevirt-helpers.ts` (VirtualMachine builder functions for cloud-init, resources, volumes)
- [ ] T009 [P] Create shared DataVolume helper library in `cdk8s/lib/datavolume-helpers.ts` (DataVolume source configuration helpers for HTTP/registry sources)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Deploy KubeVirt to Kind Cluster (Priority: P1) 🎯 MVP

**Goal**: Deploy KubeVirt operator and custom resources to Kind cluster using CDK8s charts so VMs can be managed declaratively

**Independent Test**: Synthesize CDK8s chart, deploy via ArgoCD, verify all KubeVirt components (operator, controllers, handlers) running in kubevirt namespace

### Implementation for User Story 1

- [ ] T010 [P] [US1] Create KubeVirtChart in `cdk8s/charts/infra/kubevirt-chart.ts` (KubeNamespace for 'kubevirt' with sync wave -110, KubeVirt CR with useEmulation: true and sync wave -90)
- [ ] T011 [P] [US1] Create CDIChart in `cdk8s/charts/infra/cdi-chart.ts` (KubeNamespace for 'cdi' with sync wave -110, CDI CR with sync wave -90)
- [ ] T012 [US1] Register KubeVirtChart in IdpBuilderChartFactory in `cdk8s/main-v2.ts`: `IdpBuilderChartFactory.register('KubeVirtChart', KubeVirtChart)`
- [ ] T013 [US1] Register CDIChart in IdpBuilderChartFactory in `cdk8s/main-v2.ts`: `IdpBuilderChartFactory.register('CDIChart', CDIChart)`
- [ ] T014 [US1] Add KubeVirt application config to `cdk8s/config/applications.ts` (name: 'kubevirt', namespace: 'kubevirt', chart type: 'KubeVirtChart', props: { useEmulation: true }, syncWave: '-100', automated sync policy)
- [ ] T015 [US1] Add CDI application config to `cdk8s/config/applications.ts` (name: 'cdi', namespace: 'cdi', chart type: 'CDIChart', syncWave: '-100', automated sync policy)
- [ ] T016 [US1] Synthesize all packages: `cd cdk8s && npx ts-node main-v2.ts`
- [ ] T017 [US1] Verify synthesized manifests in `cdk8s/dist/kubevirt/manifests/` (kubevirt-namespace.yaml, kubevirt-cr.yaml, kustomization.yaml)
- [ ] T018 [US1] Verify synthesized manifests in `cdk8s/dist/cdi/manifests/` (cdi-namespace.yaml, cdi-cr.yaml, kustomization.yaml)
- [ ] T019 [US1] Deploy via cluster-menu.sh: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
- [ ] T020 [US1] Verify KubeVirt operator running: `kubectl get pods -n kubevirt` (expect: virt-operator, virt-controller, virt-handler, virt-api pods Running)
- [ ] T021 [US1] Verify CDI operator running: `kubectl get pods -n cdi` (expect: cdi-operator, cdi-apiserver, cdi-deployment, cdi-uploadproxy pods Running)
- [ ] T022 [US1] Verify KubeVirt CR status: `kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.status.phase}'` (expect: "Deployed")
- [ ] T023 [US1] Verify VirtualMachine CRD registered: `kubectl get crd virtualmachines.kubevirt.io` (expect: CRD exists)
- [ ] T024 [US1] Verify DataVolume CRD registered: `kubectl get crd datavolumes.cdi.kubevirt.io` (expect: CRD exists)

**Checkpoint**: At this point, KubeVirt and CDI are fully deployed and ready to manage VMs

---

## Phase 4: User Story 2 - Create NixOS-based VM Image (Priority: P2)

**Goal**: Build VM disk image from NixOS/home-manager configuration and import into Kubernetes via DataVolume

**Independent Test**: Build NixOS qcow2 image, create DataVolume pointing to image, verify DataVolume import completes successfully (phase "Succeeded", PVC bound)

### Implementation for User Story 2

- [ ] T025 [P] [US2] Create NixOS image server deployment in `cdk8s/charts/platform/nixos-image-server-chart.ts` (nginx Deployment with hostPath volume mount to ~/stacks/nixos-images, Service on port 80, sync wave -50)
- [ ] T026 [US2] Register NixOsImageServerChart in IdpBuilderChartFactory in `cdk8s/main-v2.ts`
- [ ] T027 [US2] Add nixos-image-server application config to `cdk8s/config/applications.ts` (name: 'nixos-image-server', namespace: 'default', chart type: 'NixOsImageServerChart', syncWave: '-50')
- [ ] T028 [US2] Create NixOsDataVolumeChart in `cdk8s/charts/apps/nixos-datavolume-chart.ts` (DataVolume with HTTP source pointing to nixos-image-server service URL, PVC size 20Gi, sync wave 0)
- [ ] T029 [US2] Register NixOsDataVolumeChart in IdpBuilderChartFactory in `cdk8s/main-v2.ts`
- [ ] T030 [US2] Add nixos-dev-datavolume application config to `cdk8s/config/applications.ts` (name: 'nixos-dev-datavolume', namespace: 'default', chart type: 'NixOsDataVolumeChart', props: { dataVolumeName: 'nixos-dev-datavolume', imageUrl: 'http://nixos-image-server.default.svc.cluster.local/kubevirt-vm.qcow2', storageSize: '20Gi' }, syncWave: '0')
- [ ] T031 [US2] Synthesize all packages: `cd cdk8s && npx ts-node main-v2.ts`
- [ ] T032 [US2] Deploy via cluster-menu.sh: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
- [ ] T033 [US2] Verify nixos-image-server pod running: `kubectl get pods -n default -l app=nixos-image-server` (expect: Running)
- [ ] T034 [US2] Verify image accessible via HTTP: `kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -I http://nixos-image-server.default.svc.cluster.local/kubevirt-vm.qcow2` (expect: HTTP 200)
- [ ] T035 [US2] Verify DataVolume created: `kubectl get datavolume nixos-dev-datavolume` (expect: exists)
- [ ] T036 [US2] Monitor DataVolume import progress: `kubectl get datavolume nixos-dev-datavolume -w` (wait for Status: Succeeded)
- [ ] T037 [US2] Verify PVC bound: `kubectl get pvc nixos-dev-datavolume` (expect: Status: Bound)
- [ ] T038 [US2] Check DataVolume conditions: `kubectl describe datavolume nixos-dev-datavolume` (expect: Ready condition True)

**Checkpoint**: At this point, NixOS image is imported into PVC and ready for VM attachment

---

## Phase 5: User Story 3 - Launch NixOS Virtual Machine (Priority: P3)

**Goal**: Create and start VirtualMachine resource using NixOS disk image to run fully functional NixOS VM in Kubernetes cluster

**Independent Test**: Create VirtualMachine manifest referencing NixOS DataVolume, start VM, access console to verify NixOS is running

### Implementation for User Story 3

- [ ] T039 [P] [US3] Create NixOsVmChart in `cdk8s/charts/apps/nixos-vm-chart.ts` (VirtualMachine with runStrategy: Manual, resources: 2 CPU / 4Gi RAM, volumes: rootdisk from dataVolume + cloudinitdisk with cloudInitNoCloud userData, devices: virtio disks, networks: pod network, sync wave 10)
- [ ] T040 [US3] Register NixOsVmChart in IdpBuilderChartFactory in `cdk8s/main-v2.ts`
- [ ] T041 [US3] Add nixos-dev-vm application config to `cdk8s/config/applications.ts` (name: 'nixos-dev-vm', namespace: 'default', chart type: 'NixOsVmChart', props: { vmName: 'nixos-dev-vm', dataVolumeName: 'nixos-dev-datavolume', cpuCores: 2, memory: '4Gi', cloudInitUserData: '#cloud-config\nhostname: nixos-dev\nusers:\n  - name: vpittamp\n    sudo: ALL=(ALL) NOPASSWD:ALL\n' }, syncWave: '10', automated sync policy)
- [ ] T042 [US3] Synthesize all packages: `cd cdk8s && npx ts-node main-v2.ts`
- [ ] T043 [US3] Verify synthesized VirtualMachine manifest in `cdk8s/dist/nixos-dev-vm/manifests/nixos-dev-vm.yaml` (check runStrategy, resources, volumes)
- [ ] T044 [US3] Deploy via cluster-menu.sh: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
- [ ] T045 [US3] Verify VirtualMachine created: `kubectl get vm nixos-dev-vm` (expect: Status: Stopped, runStrategy: Manual)
- [ ] T046 [US3] Start VM using virtctl: `virtctl start nixos-dev-vm`
- [ ] T047 [US3] Verify VirtualMachineInstance created: `kubectl get vmi nixos-dev-vm` (expect: Phase: Pending → Scheduling → Scheduled → Running)
- [ ] T048 [US3] Verify virt-launcher pod scheduled: `kubectl get pods -l kubevirt.io/domain=nixos-dev-vm` (expect: Running)
- [ ] T049 [US3] Wait for VMI Running state: `kubectl wait --for=condition=Ready vmi/nixos-dev-vm --timeout=5m`
- [ ] T050 [US3] Access VM console: `virtctl console nixos-dev-vm` (expect: NixOS login prompt)
- [ ] T051 [US3] Verify NixOS system inside VM: Connect to console, check `uname -a`, `nix --version`, `cloud-init status` (expect: NixOS kernel, Nix available, cloud-init done)
- [ ] T052 [US3] Check VM IP address: `kubectl get vmi nixos-dev-vm -o jsonpath='{.status.interfaces[0].ipAddress}'` (expect: IP from pod network CIDR)
- [ ] T053 [US3] Verify VM can communicate with pods: From VM console, `ping <pod-ip>` (expect: successful ping)
- [ ] T054 [US3] Stop VM using virtctl: `virtctl stop nixos-dev-vm`
- [ ] T055 [US3] Verify VirtualMachineInstance deleted: `kubectl get vmi nixos-dev-vm` (expect: NotFound)
- [ ] T056 [US3] Verify virt-launcher pod deleted: `kubectl get pods -l kubevirt.io/domain=nixos-dev-vm` (expect: no pods)

**Checkpoint**: At this point, NixOS VM can be started, accessed via console, and stopped successfully

---

## Phase 6: User Story 4 - Manage VM Lifecycle via GitOps (Priority: P4)

**Goal**: Define VirtualMachine resources in CDK8s charts and deploy via ArgoCD so VM lifecycle follows GitOps workflow

**Independent Test**: Create CDK8s chart defining VirtualMachine, synthesize to dist/, deploy via ArgoCD, verify VM is created and managed by ArgoCD

### Implementation for User Story 4

- [ ] T057 [US4] Verify ArgoCD Application for nixos-dev-vm exists: `kubectl get application -n argocd nixos-dev-vm` (expect: created by cluster-update)
- [ ] T058 [US4] Check ArgoCD Application status: `argocd app get argocd/nixos-dev-vm --insecure` (expect: Synced, Healthy)
- [ ] T059 [US4] Modify VirtualMachine spec in `cdk8s/charts/apps/nixos-vm-chart.ts` (change cpuCores to 4, memory to '8Gi')
- [ ] T060 [US4] Update nixos-dev-vm application config in `cdk8s/config/applications.ts` (props: { cpuCores: 4, memory: '8Gi' })
- [ ] T061 [US4] Synthesize updated manifests: `cd cdk8s && npx ts-node main-v2.ts`
- [ ] T062 [US4] Verify ArgoCD detects drift: `argocd app get argocd/nixos-dev-vm --insecure` (expect: OutOfSync)
- [ ] T063 [US4] Wait for ArgoCD auto-sync (automated sync policy enabled): Watch `argocd app get argocd/nixos-dev-vm --insecure` until Synced
- [ ] T064 [US4] Verify VirtualMachine updated with new resources: `kubectl get vm nixos-dev-vm -o jsonpath='{.spec.template.spec.domain.resources.requests.cpu}'` (expect: "4")
- [ ] T065 [US4] Verify VirtualMachine updated memory: `kubectl get vm nixos-dev-vm -o jsonpath='{.spec.template.spec.domain.resources.requests.memory}'` (expect: "8Gi")
- [ ] T066 [P] [US4] Test PVC retention policy - Ephemeral: Create test VM with dataVolumeTemplates (owned by VM), delete VM, verify PVC deleted
- [ ] T067 [P] [US4] Test PVC retention policy - Persistent: Create test VM referencing existing DataVolume (not owned), delete VM, verify PVC retained
- [ ] T068 [US4] Delete ArgoCD Application for test VMs: `argocd app delete argocd/<test-vm-name> --insecure --cascade`
- [ ] T069 [US4] Verify VirtualMachine resource deleted according to sync policy: `kubectl get vm <test-vm-name>` (expect: NotFound after cascade delete)
- [ ] T070 [US4] Verify PVC behavior matches retention policy (ephemeral deleted, persistent retained): `kubectl get pvc` (check expected PVCs exist/deleted)

**Checkpoint**: All user stories are now independently functional - VM lifecycle fully managed via GitOps

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T071 [P] Add KubeVirt version upgrade path documentation in `specs/002-i-want-to/quickstart.md` (update CRD import URLs, re-import, test)
- [ ] T072 [P] Add troubleshooting section to quickstart.md (common issues: DataVolume import timeout, VM fails to start, console access)
- [ ] T073 [P] Document PVC retention policy patterns in quickstart.md (ephemeral vs persistent with code examples)
- [ ] T074 Add multi-environment VM deployment guide (parameterized chart props for dev/staging/prod resource allocation)
- [ ] T075 [P] Create example VirtualMachine with multiple NixOS configurations (dev-vm.nix, k8s-worker-vm.nix) showing reusability
- [ ] T076 [P] Add NetworkPolicy example for production VM namespace (ingress/egress control)
- [ ] T077 [P] Add ExternalSecret example for cloud-init SSH keys from Azure Key Vault
- [ ] T078 Document virtctl CLI reference commands in quickstart.md (start, stop, restart, console, vnc)
- [ ] T079 Add performance tuning section (VM resource allocation, Kind cluster sizing, concurrent VM limits)
- [ ] T080 Run full quickstart.md validation (follow all steps from prerequisites through VM lifecycle)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2)
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2) AND User Story 1 (KubeVirt/CDI must be deployed)
- **User Story 3 (Phase 5)**: Depends on Foundational (Phase 2) AND User Story 2 (DataVolume with NixOS image must exist)
- **User Story 4 (Phase 6)**: Depends on User Story 3 (VirtualMachine must be deployed via ArgoCD)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Requires US1 complete (KubeVirt/CDI deployed) before DataVolume can import
- **User Story 3 (P3)**: Requires US2 complete (DataVolume with NixOS image available) before VM can start
- **User Story 4 (P4)**: Requires US3 complete (VirtualMachine resource exists) before GitOps lifecycle can be tested

### Within Each User Story

- CRD imports before chart creation
- Chart creation before registration
- Registration before application config
- Synthesis before deployment
- Deployment before verification
- Sequential verification steps (operator → CR status → CRD registration)

### Parallel Opportunities

- **Setup (Phase 1)**: T001 (KubeVirt CRD import) and T002 (CDI CRD import) can run in parallel
- **Foundational (Phase 2)**: T008 (kubevirt-helpers.ts) and T009 (datavolume-helpers.ts) can run in parallel
- **User Story 1 (Phase 3)**: T010 (KubeVirtChart) and T011 (CDIChart) can run in parallel
- **User Story 2 (Phase 4)**: T025 (NixOsImageServerChart) can run in parallel with T028 (NixOsDataVolumeChart) creation (but deployment is sequential)
- **User Story 4 (Phase 6)**: T066 (ephemeral PVC test) and T067 (persistent PVC test) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch parallel chart creation for User Story 1:
Task: "Create KubeVirtChart in cdk8s/charts/infra/kubevirt-chart.ts"
Task: "Create CDIChart in cdk8s/charts/infra/cdi-chart.ts"

# Then sequential registration and deployment:
Task: "Register KubeVirtChart in IdpBuilderChartFactory"
Task: "Register CDIChart in IdpBuilderChartFactory"
Task: "Add KubeVirt application config to applications.ts"
Task: "Add CDI application config to applications.ts"
Task: "Synthesize all packages"
Task: "Deploy via cluster-menu.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (CRD imports)
2. Complete Phase 2: Foundational (NixOS vm-minimal.nix, qcow2 image build, helper libraries)
3. Complete Phase 3: User Story 1 (KubeVirt/CDI deployment)
4. **STOP and VALIDATE**: Test KubeVirt operator running, CRDs registered
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP: KubeVirt platform ready!)
3. Add User Story 2 → Test independently → Deploy/Demo (NixOS image import working!)
4. Add User Story 3 → Test independently → Deploy/Demo (NixOS VM running!)
5. Add User Story 4 → Test independently → Deploy/Demo (GitOps VM lifecycle complete!)
6. Each story adds value without breaking previous stories

### Full Feature Delivery

Complete all phases 1-7 in order for full KubeVirt + NixOS VM platform with GitOps lifecycle management.

---

## Notes

- [P] tasks = different files, no dependencies, can run in parallel
- [Story] label maps task to specific user story for traceability (US1, US2, US3, US4)
- Each user story should be independently completable and testable (with dependencies noted)
- Use `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update` for all deployments (cluster-menu.sh wrapper per Constitution Principle II)
- Always use `--insecure` flag for argocd CLI in local dev (self-signed certificates)
- Commit after each logical group of tasks (e.g., after each user story phase)
- Stop at any checkpoint to validate story independently
- Verify NixOS qcow2 image built before proceeding to User Story 2
- Verify KubeVirt/CDI deployed before proceeding to User Story 3
- Verify DataVolume imported before proceeding to User Story 4

---

## Success Criteria Mapping

| Success Criterion | Validated By Tasks |
|-------------------|-------------------|
| SC-001: KubeVirt deploys <5 min | T020, T021, T022 |
| SC-002: Create VM <10 min | T036, T045 |
| SC-003: VM boot <3 min | T049, T050 |
| SC-004: DataVolume import <10 min (10GB) | T036 |
| SC-005: ArgoCD auto-sync | T063 |
| SC-006: Console access <30s | T050, T051 |
| SC-007: TypeScript compilation passes | T003, T016, T042 |
| SC-008: VM state changes <60s | T054, T055 |
| SC-009: Multiple concurrent VMs | T075 (example) |
| SC-010: ArgoCD drift detection <3 min | T062, T063 |
| SC-011: PVC retention policy | T066, T067 |
| SC-012: VM network communication | T053 |
| SC-013: Default resources (2 CPU, 4Gi) | T041, T045 |

---

**Total Tasks**: 80
- Setup: 4 tasks
- Foundational: 5 tasks
- User Story 1 (P1): 15 tasks
- User Story 2 (P2): 14 tasks
- User Story 3 (P3): 18 tasks
- User Story 4 (P4): 14 tasks
- Polish: 10 tasks

**Estimated MVP Scope** (US1 only): 24 tasks (Setup + Foundational + US1)
