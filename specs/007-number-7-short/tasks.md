---
description: "Task list for NixOS Wayland/Sway VM migration"
---

# Tasks: NixOS Wayland/Sway VM Migration

**Input**: Design documents from `/home/vpittamp/stacks/specs/007-number-7-short/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not explicitly requested in the feature specification. Following TDD would add significant overhead for infrastructure migration tasks. Validation will be performed via deployment testing per quickstart.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions
This is an infrastructure-as-code project with the following structure:
- **CDK8s charts**: `cdk8s/charts/apps/`, `cdk8s/lib/`
- **NixOS configuration**: `/etc/nixos/` (external to repository)
- **Deployment scripts**: `deployment/scripts/`
- **Documentation**: `docs/`, `specs/007-number-7-short/`

---

## Phase 1: Setup (Image Build Preparation)

**Purpose**: Prepare NixOS build system and image distribution infrastructure

- [X] T001 Add hetzner-sway-qcow2 output to /etc/nixos/flake.nix with nixos-generators configuration
- [X] T002 Verify nixos-generators flake input is declared in /etc/nixos/flake.nix
- [ ] T003 [P] Configure MinIO bucket for VM image hosting in nix-cache namespace
- [ ] T004 [P] Optional: Push Hetzner host system closure to Attic cache for build acceleration

---

## Phase 2: Foundational (No Blocking Prerequisites)

**Purpose**: This feature builds on existing infrastructure with no foundational blockers

**⚠️ CRITICAL**: All dependencies (KubeVirt, CDI, Tailscale Operator, External Secrets, MinIO) are already deployed per plan.md assumptions. User stories can proceed immediately after Phase 1 setup.

**Checkpoint**: Setup complete - user story implementation can now begin

---

## Phase 3: User Story 1 - Build Wayland/Sway NixOS Image (Priority: P1) 🎯 MVP

**Goal**: Produce a bootable QCOW2 disk image based on hetzner-sway.nix configuration that includes Sway compositor, WayVNC server, and headless Wayland dependencies

**Independent Test**: Build the image from hetzner-sway.nix configuration, verify the output QCOW2 file exists at /etc/nixos/result/nixos.qcow2, validate image size is under 10GB using `qemu-img info`, and test boot in QEMU to confirm Sway starts automatically

**Acceptance Criteria** (from spec.md User Story 1):
- SC-001: NixOS image build completes in under 25 minutes (cold cache) or under 3 minutes (warm Attic cache)
- SC-002: Built QCOW2 image size is under 10GB
- Bootable QCOW2 disk image is produced from hetzner-sway.nix
- Image contains Sway compositor, WayVNC server, and all headless Wayland dependencies
- Greetd auto-login is configured to start Sway in headless mode with proper environment variables

### Implementation for User Story 1

- [ ] T005 [US1] Build NixOS image by running `nix build .#hetzner-sway-qcow2` from /etc/nixos directory
- [ ] T006 [US1] Verify image properties using `qemu-img info result/nixos.qcow2` to confirm virtual size is 50GiB and disk size is approximately 7GiB
- [ ] T007 [US1] Optional: Test boot in QEMU using `qemu-system-x86_64` to verify Sway starts automatically on boot
- [ ] T008 [US1] Upload QCOW2 image to MinIO bucket using `mc cp result/nixos.qcow2 local/nixos-images/hetzner-sway-v1.qcow2`
- [ ] T009 [US1] Set public read access on MinIO bucket using `mc anonymous set download local/nixos-images`
- [ ] T010 [US1] Verify HTTP URL is accessible from cluster by testing `http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2`

**Checkpoint**: At this point, User Story 1 should be complete - a working NixOS Wayland/Sway image is built and available via HTTP

---

## Phase 4: User Story 2 - Deploy Image to KubeVirt (Priority: P2)

**Goal**: Deploy the Wayland/Sway NixOS image to the local Kind cluster using KubeVirt, replacing the existing X11/RustDesk-based VM deployment with new DataVolume, updated VirtualMachine configuration, and simplified cloud-init

**Independent Test**: Synthesize CDK8s manifests with the new image configuration, deploy via idpbuilder using `cluster-update`, verify the VirtualMachine resource reaches Running state using `kubectl get vm,vmi -n default`, and confirm virt-launcher pod shows Running status

**Acceptance Criteria** (from spec.md User Story 2):
- SC-003: VM boots to running state within 90 seconds of VirtualMachine resource creation
- SC-004: Sway compositor initializes successfully in headless mode within 30 seconds of VM boot
- NixOsVmChart references the new Wayland/Sway image source
- VirtualMachine is created successfully via idpbuilder
- Virt-launcher pod shows Running status
- VirtualMachineInstance shows Agent Connected
- ArgoCD nixos-dev-vm application shows Synced and Healthy status

### Implementation for User Story 2

- [X] T011 [P] [US2] Update NixOsVmChartProps interface in cdk8s/charts/apps/nixos-vm-chart.ts to replace `rustdeskPassword` with `wayvncPassword` property
- [X] T012 [P] [US2] Update buildCloudInitUserData function signature in cdk8s/lib/kubevirt-helpers.ts to remove `enableRustDesk` and `rustdeskPassword` parameters
- [X] T013 [US2] Remove RustDesk installation and configuration logic from buildCloudInitUserData function in cdk8s/lib/kubevirt-helpers.ts (approximately 240 lines of cloud-init commands)
- [X] T014 [US2] Remove X11/RDP configuration logic from buildCloudInitUserData function in cdk8s/lib/kubevirt-helpers.ts
- [X] T015 [US2] Update VirtualMachine port configuration in cdk8s/charts/apps/nixos-vm-chart.ts to remove RDP port 3389 and RustDesk port 21116, keeping only SSH port 22 and adding VNC port 5900
- [ ] T016 [US2] Update DataVolume source URL in cdk8s/charts/apps/nixos-vm-chart.ts to reference new image: `http://minio.nix-cache.svc.cluster.local:9000/nixos-images/hetzner-sway-v1.qcow2`
- [X] T017 [US2] Rename Service resource from `nixos-dev-vm-rdp` to `nixos-dev-vm-vnc` in cdk8s/charts/apps/nixos-vm-chart.ts
- [X] T018 [US2] Update Service ports in cdk8s/charts/apps/nixos-vm-chart.ts to remove RDP and RustDesk ports, keeping only SSH port 22 and VNC port 5900
- [X] T019 [US2] Update Tailscale Service hostname annotation in cdk8s/charts/apps/nixos-vm-chart.ts from `nixos-dev-vm-rdp` to `nixos-dev-vm-vnc`
- [X] T020 [US2] Update cloud-init generation call in cdk8s/charts/apps/nixos-vm-chart.ts to remove RustDesk parameters
- [X] T021 [US2] Synthesize CDK8s manifests by running `npx ts-node main-v2.ts` from cdk8s/ directory
- [ ] T022 [US2] Deploy updated configuration by running `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
- [ ] T023 [US2] Monitor DataVolume import progress using `kubectl get dv hetzner-sway-disk -n default -w` and verify it reaches Succeeded state within 7 minutes
- [ ] T024 [US2] Monitor VirtualMachine status using `kubectl get vm,vmi -n default -w` and verify VM reaches Running state within 90 seconds
- [ ] T025 [US2] Verify virt-launcher pod is Running using `kubectl get pods -n default -l kubevirt.io/vm=nixos-dev-vm`
- [ ] T026 [US2] Verify VirtualMachineInstance shows Agent Connected using `kubectl get vmi nixos-dev-vm -n default -o yaml | grep -A 5 conditions`
- [ ] T027 [US2] Verify ArgoCD application status using `argocd app get argocd/nixos-dev-vm --insecure` to confirm Synced and Healthy

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - the VM is deployed and running with the new Wayland/Sway image

---

## Phase 5: User Story 3 - Access VM via WayVNC (Priority: P3)

**Goal**: Establish remote VNC access to the Wayland/Sway desktop environment through WayVNC server, accessible via Tailscale network from M1 MacBook, with responsive keyboard/mouse interaction and proper rendering using software rendering

**Independent Test**: Connect a VNC client from M1 MacBook to the WayVNC server port (5900) via Tailscale hostname `nixos-dev-vm-vnc.tail286401.ts.net`, enter authentication credentials (username: vpittamp, password from cloud-init or Azure Key Vault), verify the Sway desktop renders correctly, test keyboard/mouse inputs are responsive, and navigate between workspaces using Sway shortcuts

**Acceptance Criteria** (from spec.md User Story 3):
- SC-005: WayVNC service is active and accepting connections within 60 seconds of Sway initialization
- SC-006: VNC client can establish connection to VM within 5 seconds via Tailscale hostname
- SC-007: VNC session latency is under 100ms for keyboard/mouse input
- SC-008: Sway desktop environment renders correctly with all three virtual outputs accessible via workspaces
- SC-009: M1 MacBook device can successfully connect to VM via Tailscale with full keyboard/mouse functionality
- Connection establishes successfully to Tailscale hostname on port 5900
- Authentication credentials grant access and Sway desktop environment is visible
- Keyboard and mouse inputs are registered and desktop responds correctly
- Workspaces can be navigated across virtual monitors
- Applications (terminal, browser) render correctly using software rendering (pixman)

### Implementation for User Story 3

- [ ] T028 [US3] Verify Tailscale LoadBalancer is provisioned by checking `kubectl get svc nixos-dev-vm-vnc -n default` for LoadBalancer IP assignment
- [ ] T029 [US3] Retrieve Tailscale hostname by checking Service annotations or Tailscale operator logs: `kubectl logs -n tailscale deployment/tailscale-operator | grep nixos-dev-vm-vnc`
- [ ] T030 [US3] Verify WayVNC service is running inside VM by SSH-ing into VM (via port-forward if needed) and checking `systemctl --user status wayvnc` for vpittamp user
- [ ] T031 [US3] Test VNC connection from M1 MacBook using built-in Screen Sharing: `open vnc://nixos-dev-vm-vnc.tail286401.ts.net:5900`
- [ ] T032 [US3] Verify VNC authentication prompt appears and test credentials (username: vpittamp, password: nixos123 or from Azure Key Vault)
- [ ] T033 [US3] Verify Sway desktop environment is visible in VNC viewer and three virtual outputs are configured (WLR_HEADLESS_OUTPUTS=3)
- [ ] T034 [US3] Test keyboard input by opening a terminal in Sway (Mod+Return) and typing commands
- [ ] T035 [US3] Test mouse input by clicking on Sway workspace indicators and dragging windows
- [ ] T036 [US3] Test workspace navigation by pressing Sway keybindings (Mod+1, Mod+2, Mod+3) to switch between virtual outputs
- [ ] T037 [US3] Test application rendering by launching Ghostty terminal and Firefox browser to verify software rendering (pixman) works correctly
- [ ] T038 [US3] Measure VNC connection latency by testing responsiveness of keyboard/mouse input (target: <100ms)

**Checkpoint**: All user stories 1, 2, and 3 should now be independently functional - the complete migration is working end-to-end

---

## Phase 6: User Story 4 - Replace Existing Configuration (Priority: P4)

**Goal**: Fully replace the existing X11/RustDesk VM configuration with the new Wayland/Sway/WayVNC configuration by removing all deprecated components, verifying no references to RustDesk or X11 remain, and updating documentation with WayVNC instructions

**Independent Test**: Remove old configuration files, synthesize manifests, deploy the updated configuration, verify no Service ports for RustDesk (21116) or RDP (3389) are defined in synthesized manifests, verify no RustDesk references remain in buildCloudInitUserData function, and confirm only WayVNC port (5900) is exposed via Tailscale LoadBalancer

**Acceptance Criteria** (from spec.md User Story 4):
- SC-010: All RustDesk and X11 references are completely removed from codebase (zero deprecated configuration remaining)
- SC-011: Documentation is updated with WayVNC connection instructions (100% accuracy for connection steps)
- All RustDesk-specific configuration is removed from kubevirt-helpers.ts
- No Service ports for RustDesk (21116) or RDP (3389) are defined
- No RustDesk installation or configuration logic remains in buildCloudInitUserData function
- Only WayVNC port (5900) is exposed via Tailscale LoadBalancer
- All references to RustDesk remote access are replaced with WayVNC instructions in documentation

### Implementation for User Story 4

- [ ] T039 [US4] Verify all RustDesk references are removed from cdk8s/lib/kubevirt-helpers.ts by searching for "rustdesk" (case-insensitive) and confirming zero matches
- [ ] T040 [US4] Verify all X11/RDP references are removed from cdk8s/lib/kubevirt-helpers.ts by searching for "xrdp", "rdp", "X11" and confirming zero matches in cloud-init generation
- [ ] T041 [US4] Verify NixOsVmChartProps interface has no rustdeskPassword property in cdk8s/charts/apps/nixos-vm-chart.ts
- [ ] T042 [US4] Verify Service resource ports in synthesized manifests (cdk8s/dist/nixos-dev-vm/manifests/) do not include port 3389 or 21116
- [ ] T043 [US4] Verify VirtualMachine resource ports in synthesized manifests (cdk8s/dist/nixos-dev-vm/manifests/) do not include port 3389 or 21116
- [ ] T044 [US4] Update CLAUDE.md agent context documentation to replace RustDesk section with WayVNC connection instructions
- [ ] T045 [US4] Create or update docs/WAYVNC_CONNECTION_GUIDE.md (similar to existing RUSTDESK_CONNECTION_GUIDE.md) with M1 MacBook connection instructions
- [ ] T046 [US4] Update docs/WAYVNC_CONNECTION_GUIDE.md with Tailscale hostname format, authentication credentials, and troubleshooting steps
- [ ] T047 [US4] Optional: Remove or archive old docs/RUSTDESK_CONNECTION_GUIDE.md if it exists to avoid confusion
- [ ] T048 [US4] Run final deployment verification by synthesizing manifests and deploying with `cluster-update`, confirming VM boots and VNC access works
- [ ] T049 [US4] Verify zero RustDesk/X11 references remain by running global search: `cd ~/stacks && grep -r "rustdesk\|xrdp" cdk8s/ docs/ --exclude-dir=node_modules | grep -v "\.md:"`

**Checkpoint**: All user stories are complete - the migration is fully validated and documented, with no deprecated configuration remaining

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final improvements and validation across all user stories

- [ ] T050 [P] Update spec.md status to "Complete" or "Deployed" in /home/vpittamp/stacks/specs/007-number-7-short/spec.md
- [ ] T051 [P] Optional: Add code comments in cdk8s/charts/apps/nixos-vm-chart.ts explaining WayVNC port configuration and headless Wayland environment
- [ ] T052 Run complete quickstart.md validation from Phase 1 to Phase 6 to ensure all steps work end-to-end
- [ ] T053 Optional: Measure and document actual build times (cold cache, warm cache, Attic cache) for future reference
- [ ] T054 Optional: Create troubleshooting section in docs/WAYVNC_CONNECTION_GUIDE.md based on any issues encountered during testing
- [ ] T055 Optional: Commit all changes to Git with message referencing feature 007-number-7-short

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately (requires NixOS system access and MinIO deployed)
- **Foundational (Phase 2)**: SKIPPED - all infrastructure dependencies already exist (KubeVirt, CDI, Tailscale Operator, External Secrets, MinIO)
- **User Stories (Phase 3-6)**: Each depends on the previous user story completing successfully
  - User Story 1 (Phase 3): Can start after Setup (Phase 1)
  - User Story 2 (Phase 4): Depends on User Story 1 completion (needs built image)
  - User Story 3 (Phase 5): Depends on User Story 2 completion (needs deployed VM)
  - User Story 4 (Phase 6): Depends on User Story 3 completion (needs validated working solution)
- **Polish (Phase 7)**: Depends on User Story 4 completion

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Setup (Phase 1) - No dependencies on other stories
- **User Story 2 (P2)**: Depends on User Story 1 (needs built QCOW2 image available via HTTP)
- **User Story 3 (P3)**: Depends on User Story 2 (needs deployed VM running with WayVNC service)
- **User Story 4 (P4)**: Depends on User Story 3 (needs validated working solution before cleanup)

**Note**: Unlike typical feature development, this migration has sequential dependencies between user stories because each story builds on the previous one (build → deploy → test → cleanup).

### Within Each User Story

**User Story 1 (Image Build)**:
- T001-T004 (Setup) can run in parallel
- T005 (build) must complete before T006 (verify)
- T006 (verify) must complete before T008 (upload)
- T007 (optional QEMU test) can run in parallel with T006
- T008 (upload) must complete before T009 (set permissions)
- T009 (permissions) must complete before T010 (verify HTTP)

**User Story 2 (Deploy)**:
- T011-T020 (CDK8s updates) can proceed in any order but all must complete before T021 (synthesis)
- T021 (synthesis) must complete before T022 (deploy)
- T022 (deploy) must complete before T023-T027 (verification steps)
- T023-T027 (verification) can run concurrently with `kubectl` watch commands

**User Story 3 (VNC Access)**:
- T028-T030 (infrastructure verification) can run in any order
- T031-T032 (connection and auth) must be sequential
- T033-T038 (interaction testing) must be sequential (depends on successful connection)

**User Story 4 (Cleanup)**:
- T039-T043 (verification tasks) can run in parallel
- T044-T047 (documentation) can run in parallel
- T048 (final deployment) must complete before T049 (final verification)

### Parallel Opportunities

**Within Setup (Phase 1)**:
- T003 and T004 can run in parallel (MinIO bucket setup vs Attic cache population)

**Within User Story 2 (Phase 4)**:
- T011, T012 can run in parallel (different files: nixos-vm-chart.ts vs kubevirt-helpers.ts)
- T013, T014 can run sequentially in same file (kubevirt-helpers.ts)
- T015-T020 all edit nixos-vm-chart.ts (sequential within same file)

**Within User Story 3 (Phase 5)**:
- T028, T029, T030 can run in parallel (different verification checks)

**Within User Story 4 (Phase 6)**:
- T039-T043 can run in parallel (verification tasks)
- T044-T047 can run in parallel (documentation tasks)

**Cross-Story Parallelization**: Not applicable - this migration requires sequential story completion (build → deploy → test → cleanup)

---

## Parallel Example: User Story 1 (Image Build)

```bash
# Phase 1 Setup - can run in parallel:
Task: "Configure MinIO bucket for VM image hosting in nix-cache namespace"
Task: "Optional: Push Hetzner host system closure to Attic cache for build acceleration"

# Phase 1 Setup complete, now User Story 1 tasks:
# T005: Build image (blocking, ~5-25 minutes depending on cache)
# T006 and T007 can run in parallel after T005:
Task: "Verify image properties using qemu-img info result/nixos.qcow2"
Task: "Optional: Test boot in QEMU using qemu-system-x86_64"

# Then sequential: T008 → T009 → T010 (upload → permissions → verify HTTP)
```

---

## Parallel Example: User Story 2 (Deploy)

```bash
# T011 and T012 can run in parallel (different files):
Task: "Update NixOsVmChartProps interface in cdk8s/charts/apps/nixos-vm-chart.ts"
Task: "Update buildCloudInitUserData function signature in cdk8s/lib/kubevirt-helpers.ts"

# Then all other T013-T020 tasks in sequence (most edit same file)
# After T022 (deploy), all verification tasks can run concurrently with watch commands:
Task: "Monitor DataVolume import using kubectl get dv -w"
Task: "Monitor VirtualMachine status using kubectl get vm,vmi -w"
Task: "Verify virt-launcher pod is Running"
```

---

## Parallel Example: User Story 4 (Cleanup)

```bash
# All verification tasks can run in parallel:
Task: "Verify all RustDesk references are removed from kubevirt-helpers.ts"
Task: "Verify all X11/RDP references are removed from kubevirt-helpers.ts"
Task: "Verify NixOsVmChartProps interface has no rustdeskPassword property"
Task: "Verify Service resource ports do not include port 3389 or 21116"
Task: "Verify VirtualMachine resource ports do not include port 3389 or 21116"

# Documentation tasks can run in parallel:
Task: "Update CLAUDE.md agent context documentation"
Task: "Create or update docs/WAYVNC_CONNECTION_GUIDE.md"
Task: "Optional: Remove or archive old docs/RUSTDESK_CONNECTION_GUIDE.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (image build preparation)
2. Complete Phase 3: User Story 1 (build image, upload to MinIO)
3. **STOP and VALIDATE**: Verify QCOW2 exists, size is correct, HTTP URL is accessible
4. Decision point: Continue to deployment or iterate on image build

**Estimated time**: 30-45 minutes (including 5-25 minute build time)

### Incremental Delivery

1. Complete Setup → Foundation ready (MinIO bucket configured)
2. Add User Story 1 → Test independently → Image built and accessible via HTTP (MVP!)
3. Add User Story 2 → Test independently → VM deployed and running with new image
4. Add User Story 3 → Test independently → VNC access working from M1 MacBook
5. Add User Story 4 → Test independently → All deprecated configuration removed
6. Each story adds value and validates the next step in the migration

**Total estimated time**: 60-90 minutes for complete migration (first-time setup)

### Sequential Story Strategy

Since this is infrastructure migration with hard dependencies between stories:

1. Complete Phase 1 (Setup) first
2. Complete User Story 1 (build image) - cannot proceed without working image
3. Complete User Story 2 (deploy) - cannot proceed without deployed VM
4. Complete User Story 3 (VNC access) - must validate solution before cleanup
5. Complete User Story 4 (cleanup) - only safe to remove old config after validation
6. Stories must complete in this exact order due to dependencies

**Alternative**: Stop after User Story 3 to run the new solution in parallel with old RustDesk configuration for a transition period, then complete User Story 4 cleanup later.

---

## Notes

- [P] tasks = different files or independent operations, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently testable at its completion checkpoint
- This migration has sequential dependencies between stories (not parallel-friendly)
- Build times vary significantly based on cache state (3-25 minutes range)
- All kubectl verification commands can use watch flags (-w) for real-time monitoring
- Optional tasks (T004, T007, T047, T051-T054) can be skipped to reduce implementation time
- Commit after completing each user story for clear rollback points
- Stop at any checkpoint to validate story independently before proceeding
- Avoid: skipping verification steps, removing old config before validating new solution, deploying without testing HTTP URL accessibility
- Performance targets from spec.md success criteria should be measured and documented during testing
