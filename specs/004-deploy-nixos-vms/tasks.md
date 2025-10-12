# Tasks: Deploy NixOS VMs using KubeVirt

**Branch**: `004-deploy-nixos-vms`
**Input**: Design documents from `/specs/004-deploy-nixos-vms/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: This feature focuses on infrastructure deployment. Testing is performed through:
- Manual validation (VM boot, SSH access, desktop deployment)
- ArgoCD sync validation
- CDK8s synthesis validation
- No unit/integration test suite required for infrastructure-as-code

**Organization**: Tasks are grouped by user story (P1-P4) to enable independent implementation and testing of each story increment.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

This is an **Infrastructure/Platform project** using CDK8s for Kubernetes manifest generation.

**Structure** (from plan.md):
```
/etc/nixos/configurations/       # NixOS configurations (external repository)
cdk8s/
├── charts/
│   ├── platform/                # Platform services (image server)
│   └── apps/                    # Applications (VM resources)
├── lib/                         # Shared helper functions
├── config/
│   └── applications.ts          # Declarative app configuration
├── main-v2.ts                   # Synthesis entry point
└── dist/                        # Generated manifests (synthesis output)
scripts/                         # Build scripts for images
```

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and prerequisite verification

- [ ] **T001** [P] [Setup] Verify KubeVirt + CDI installed in target cluster
  - Run: `kubectl get crds | grep kubevirt.io`
  - Expected: VirtualMachine, VirtualMachineInstance CRDs exist
  - Run: `kubectl get crds | grep cdi.kubevirt.io`
  - Expected: DataVolume CRD exists
  - **Exit early if missing**: Feature cannot proceed without KubeVirt

- [ ] **T002** [P] [Setup] Verify StorageClass with dynamic provisioning exists
  - Run: `kubectl get storageclass`
  - Expected: At least one StorageClass with provisioner
  - Verify: `kubectl get storageclass <default> -o yaml | grep provisioner`
  - **Note default StorageClass** for DataVolume configuration

- [ ] **T003** [P] [Setup] Verify Attic binary cache deployed (spec 003)
  - Run: `kubectl get pods -n nix-cache`
  - Expected: attic pods running
  - Verify HTTP access: `curl http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`
  - **If missing**: Deploy spec 003 first or accept slower rebuilds

- [ ] **T004** [P] [Setup] Install nixos-generators on build host
  - Run: `nix-shell -p nixos-generators`
  - Or: `nix profile install nixpkgs#nixos-generators`
  - Verify: `nixos-generate --help`
  - **Required for**: US1 (image building)

- [ ] **T005** [P] [Setup] Verify Docker installed and running
  - Run: `docker info`
  - Expected: Docker daemon running, registry access
  - Verify Docker Hub login: `docker login`
  - **Required for**: US1 (image packaging)

- [ ] **T006** [P] [Setup] Verify TypeScript + npm installed
  - Run: `npm --version` (expected: 8+)
  - Run: `npx tsc --version` (expected: 5+)
  - Install dependencies: `cd cdk8s && npm install`
  - Verify: `npm run compile` passes
  - **Required for**: All user stories (CDK8s synthesis)

**Checkpoint**: Prerequisites verified - ready for foundational tasks

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] **T007** [Foundational] Verify kubevirt-minimal.nix configuration exists
  - Path: `/etc/nixos/configurations/kubevirt-minimal.nix`
  - Verify: File exists and is valid Nix syntax
  - Verify: GRUB bootloader enabled on /dev/vda
  - Verify: cloud-init.service enabled
  - Verify: openssh.service enabled
  - **This file already exists** from previous work (see system reminders)
  - **If changes needed**: Edit and commit to nixos-config repository

- [ ] **T008** [P] [Foundational] Create kubevirt-helpers.ts library
  - Path: `cdk8s/lib/kubevirt-helpers.ts`
  - Implement: `buildVirtualMachine(scope, id, options)` function
    - Accept: name, namespace, runStrategy, cpuCores, memory, volumes, networks
    - Return: KubeVirt VirtualMachine resource (k8s.ApiObject)
    - Use: apiVersion kubevirt.io/v1, kind VirtualMachine
  - Implement: `buildCloudInitUserData(hostname, username, sshKeys, password, installDesktop)` function
    - Accept: hostname, username, sshKeys[], password, installDesktop boolean
    - Return: cloud-config YAML string (starting with #cloud-config)
    - Format: users, ssh_authorized_keys, chpasswd directives
  - **Reference**: contracts/cdk8s-chart-interfaces.ts for signatures
  - **Note**: installDesktop=false for minimal base (desktop via nixos-rebuild)

- [ ] **T009** [P] [Foundational] Register chart types in IdpBuilderChartFactory
  - Path: `cdk8s/main-v2.ts` or `cdk8s/lib/idpbuilder-chart-factory.ts`
  - Register: `IdpBuilderChartFactory.register('NixOsImageServerChart', NixOsImageServerChart)`
  - Register: `IdpBuilderChartFactory.register('NixOsDataVolumeChart', NixOsDataVolumeChart)`
  - Register: `IdpBuilderChartFactory.register('NixOsVmChart', NixOsVmChart)`
  - **Required before**: Any chart synthesis

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Generate Minimal NixOS Base Image (Priority: P1) 🎯 MVP Prerequisite

**Goal**: Build bootable minimal NixOS qcow2 image (<5 min) with SSH, cloud-init, and virtio drivers. This is the base artifact for all other user stories.

**Independent Test**:
1. qcow2 file exists at expected path
2. `qemu-img info` shows valid qcow2 format
3. Image size <2GB compressed
4. GRUB bootloader present (via guestfish inspection)

### Implementation for User Story 1

- [ ] **T010** [US1] Create build-kubevirt-image.sh script
  - Path: `scripts/build-kubevirt-image.sh`
  - Implement per contract: contracts/build-scripts.sh
  - Accept options: --config, --output, --format, --verbose, --help
  - Default config: `/etc/nixos/configurations/kubevirt-minimal.nix`
  - Default output: `/tmp/kubevirt-base-image`
  - Default format: `kubevirt` (always)
  - Execute: `nixos-generate --format kubevirt --configuration <config> --out-link <output>`
  - Validate: qcow2 file exists, size <2GB, valid format
  - Exit codes: 0=success, 1=config error, 2=build fail, 3=validation fail, 4=disk space
  - Performance target: <5 minutes with Nix binary cache
  - **Success Criterion**: SC-001 (FR-010)

- [ ] **T011** [US1] Execute image build for first time
  - Run: `./scripts/build-kubevirt-image.sh --verbose`
  - Expected output: `/tmp/kubevirt-base-image/nixos.qcow2` (~1.7GB)
  - Verify: `qemu-img info /tmp/kubevirt-base-image/nixos.qcow2`
  - Expected: file format: qcow2, virtual size ~10GB
  - **Time**: ~5 minutes (first build with cache.nixos.org)
  - **Save timing** for performance validation

- [ ] **T012** [US1] Validate image bootloader and services
  - If libguestfs-tools available: `guestfish --ro -a /tmp/kubevirt-base-image/nixos.qcow2 -i command "test -d /boot/grub"`
  - Expected: Exit 0 (GRUB directory exists)
  - Verify cloud-init: `guestfish --ro -a <qcow2> -i command "systemctl list-unit-files | grep cloud-init"`
  - Expected: cloud-init.service enabled
  - Verify SSH: `guestfish --ro -a <qcow2> -i command "systemctl list-unit-files | grep sshd"`
  - Expected: sshd.service enabled
  - **If guestfish not available**: Skip, validate at boot time instead

- [ ] **T013** [US1] Document build process in quickstart.md
  - Path: `specs/004-deploy-nixos-vms/quickstart.md` (already exists)
  - Verify: Build instructions match actual script usage
  - Update: Any differences found during testing
  - **No changes needed if quickstart already accurate**

**Checkpoint**: Minimal NixOS base image built and validated - ready for User Story 2

---

## Phase 4: User Story 2 - Create NixOS-based VM Image Distribution (Priority: P2) 🎯 MVP Prerequisite

**Goal**: Package qcow2 into Docker image, push to Docker Hub, deploy HTTP image server in cluster for DataVolume imports (<3 min).

**Independent Test**:
1. Docker image exists in Docker Hub
2. Image server pod running in cluster
3. HTTP GET `http://nixos-image-server.default.svc.cluster.local/nixos.qcow2` returns 200 OK
4. DataVolume can successfully import from HTTP URL

### Implementation for User Story 2

- [ ] **T014** [US2] Create package-image-docker.sh script
  - Path: `scripts/package-image-docker.sh`
  - Implement per contract: contracts/build-scripts.sh
  - Accept options: --input, --tag, --push, --verbose, --help
  - Default input: `/tmp/kubevirt-base-image/nixos.qcow2`
  - Default tag: `vpittamp23/nixos-kubevirt-minimal:latest`
  - Generate Dockerfile: FROM nginx:alpine, COPY qcow2, EXPOSE 80
  - Build: `docker build -t <tag> <context>`
  - Test: Start container, curl qcow2, stop container
  - Push: `docker push <tag>` (if --push flag)
  - Exit codes: 0=success, 1=input error, 2=build fail, 3=push fail, 4=docker daemon error
  - Performance target: <1 min build, <2 min push
  - **Success Criterion**: SC-002 (FR-015)

- [ ] **T015** [US2] Execute Docker image packaging and push
  - Run: `./scripts/package-image-docker.sh --input /tmp/kubevirt-base-image/nixos.qcow2 --push`
  - Expected: Docker image vpittamp23/nixos-kubevirt-minimal:latest pushed
  - Verify: `docker images vpittamp23/nixos-kubevirt-minimal:latest`
  - Expected: ~1.8GB image
  - Verify push: `docker pull vpittamp23/nixos-kubevirt-minimal:latest`
  - **Time**: ~3 minutes total (build + push)

- [ ] **T016** [P] [US2] Create NixOsImageServerChart
  - Path: `cdk8s/charts/platform/nixos-image-server-chart.ts`
  - Implement per contract: contracts/cdk8s-chart-interfaces.ts
  - Export interface: `NixOsImageServerChartProps extends ChartProps`
  - Props: image (default: vpittamp23/nixos-kubevirt-minimal:latest), replicas (default: 1)
  - Create KubeDeployment: name=nixos-image-server, namespace=default
    - Container image: props.image
    - Port: 80
    - Resources: requests (100m CPU, 128Mi memory), limits (200m CPU, 2Gi memory)
    - Labels: app.kubernetes.io/name=nixos-image-server
    - Annotations: argocd.argoproj.io/sync-wave=-50
  - Create KubeService: name=nixos-image-server, type=ClusterIP
    - Port: 80, targetPort: 80
    - Selector: app=nixos-image-server
    - Annotations: argocd.argoproj.io/sync-wave=-50
  - **Parallel with**: T017 (different files)

- [ ] **T017** [P] [US2] Create NixOsDataVolumeChart
  - Path: `cdk8s/charts/apps/nixos-datavolume-chart.ts`
  - Implement per contract: contracts/cdk8s-chart-interfaces.ts
  - Export interface: `NixOsDataVolumeChartProps extends ChartProps`
  - Props: dataVolumeName, imageServerUrl, storageSize, storageClassName, targetNamespace
  - Defaults: dataVolumeName=nixos-dev-datavolume, storageSize=20Gi, namespace=default
  - Default URL: `http://nixos-image-server.default.svc.cluster.local/nixos.qcow2`
  - Create DataVolume resource (k8s.ApiObject):
    - apiVersion: cdi.kubevirt.io/v1beta1
    - kind: DataVolume
    - spec.source.http.url: imageServerUrl
    - spec.pvc: storageSize, accessModes=[ReadWriteOnce], storageClassName (if provided)
  - Annotations: argocd.argoproj.io/sync-wave=0 (default, after image server)
  - **Parallel with**: T016 (different files)

- [ ] **T018** [US2] Add nixos-image-server to config/applications.ts
  - Path: `cdk8s/config/applications.ts`
  - Add new ApplicationConfig:
    ```typescript
    {
      name: 'nixos-image-server',
      namespace: 'default',
      chart: {
        type: 'NixOsImageServerChart',
        props: {
          image: 'vpittamp23/nixos-kubevirt-minimal:latest',
          replicas: 1
        }
      },
      argocd: {
        syncWave: '-50',
        labels: { 'app.kubernetes.io/name': 'nixos-image-server' },
        syncPolicy: { automated: { prune: true, selfHeal: true } }
      }
    }
    ```
  - **Depends on**: T016 (chart must exist)

- [ ] **T019** [US2] Synthesize and deploy image server
  - Run: `cd cdk8s && npx ts-node main-v2.ts`
  - Expected: `dist/nixos-image-server/manifests/` directory created
  - Verify: Deployment.nixos-image-server.k8s.yaml, Service.nixos-image-server.k8s.yaml
  - Deploy: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
  - Verify: `kubectl get pods -l app=nixos-image-server`
  - Expected: Pod Running within 30 seconds
  - **Success Criterion**: SC-002 (image server ready <30 sec)

- [ ] **T020** [US2] Validate HTTP access to qcow2
  - Run: `kubectl run curl-test --image=curlimages/curl:latest --rm -it -- curl -I http://nixos-image-server.default.svc.cluster.local/nixos.qcow2`
  - Expected: HTTP 200 OK, Content-Type: application/octet-stream
  - Verify size header: Content-Length ~1.7GB
  - **If 404**: Check Docker image contents, verify qcow2 at /usr/share/nginx/html/
  - **If timeout**: Check Service endpoints, pod readiness

**Checkpoint**: Image server deployed and serving qcow2 - ready for User Story 3

---

## Phase 5: User Story 3 - Launch NixOS Virtual Machine (Priority: P3) 🎯 MVP

**Goal**: Deploy VirtualMachine resource with cloud-init configuration, achieve Running state with SSH access within 2 minutes.

**Independent Test**:
1. VirtualMachine resource exists and running
2. VirtualMachineInstance Running with pod IP
3. SSH accessible via Service within 30 seconds
4. Cloud-init configured (hostname, user, SSH keys)
5. Desktop install succeeds via nixos-rebuild (<3 min with Attic)

### Implementation for User Story 3

- [ ] **T021** [P] [US3] Create NixOsVmChart
  - Path: `cdk8s/charts/apps/nixos-vm-chart.ts`
  - Implement per contract: contracts/cdk8s-chart-interfaces.ts
  - Export interface: `NixOsVmChartProps extends ChartProps`
  - Props: vmName, dataVolumeName, cpuCores, memory, cloudInitUserData, targetNamespace, enableTailscale, tailscaleHostname, runStrategy, enableGraphics
  - Defaults: vmName=nixos-dev-vm, dataVolumeName=nixos-dev-datavolume, cpuCores=2, memory=4Gi, runStrategy=Always, enableGraphics=true
  - SSH public key (hardcoded): `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAq4r867qHnS9YUMbu+X7i40sfWZmkdymioHFmtewegC k8s_ed_test`
  - **Parallel with**: T022 (independent implementation)

- [ ] **T022** [P] [US3] Implement cloud-init Secret generation in NixOsVmChart
  - Path: Same file as T021: `cdk8s/charts/apps/nixos-vm-chart.ts`
  - Generate cloud-init userData using `buildCloudInitUserData()` helper
  - If cloudInitUserData prop not provided, generate default:
    - hostname: vmName
    - user: vpittamp
    - SSH keys: [hardcoded k8s_ed_test key]
    - password: nixos123 (for console access)
    - installDesktop: false (minimal base, desktop via nixos-rebuild)
  - Create KubeSecret: name=`${vmName}-cloudinit`, namespace=targetNamespace
    - stringData.userdata: generated cloud-config YAML
    - Annotations: argocd.argoproj.io/sync-wave=5 (before VM)
  - **Parallel with**: T021 (part of same chart, can implement together)

- [ ] **T023** [US3] Implement VirtualMachine resource in NixOsVmChart
  - Path: Same file as T021: `cdk8s/charts/apps/nixos-vm-chart.ts`
  - Use `buildVirtualMachine()` helper from kubevirt-helpers.ts
  - VM spec:
    - name: vmName
    - runStrategy: runStrategy prop
    - cpuCores: cpuCores prop
    - memory: memory prop
    - volumes: [rootdisk (dataVolume), cloudinitdisk (Secret)]
    - networks: [pod network with masquerade, ports: 22, 3389]
    - enableGraphics: enableGraphics prop
    - labels: app.kubernetes.io/name=vmName, kubevirt.io/vm=vmName
    - Annotations: argocd.argoproj.io/sync-wave=10
  - **Depends on**: T021, T022 (same file, sequential implementation)

- [ ] **T024** [US3] Implement Service resource in NixOsVmChart
  - Path: Same file as T021: `cdk8s/charts/apps/nixos-vm-chart.ts`
  - Create KubeService: name=`${vmName}-rdp`, namespace=targetNamespace
  - Service type: LoadBalancer if enableTailscale, else NodePort
  - Selector: kubevirt.io/vm=vmName
  - Ports: [SSH (22), RDP (3389)]
  - If enableTailscale:
    - loadBalancerClass: tailscale
    - Annotations: tailscale.com/expose=true, tailscale.com/hostname=tailscaleHostname, tailscale.com/tags=tag:k8s
  - Annotations: argocd.argoproj.io/sync-wave=15 (after VM)
  - **Depends on**: T023 (same file, sequential implementation)

- [ ] **T025** [US3] Add nixos-dev-vm to config/applications.ts
  - Path: `cdk8s/config/applications.ts`
  - Add two ApplicationConfigs:
    1. nixos-dev-datavolume (DataVolume for import):
       ```typescript
       {
         name: 'nixos-dev-datavolume',
         namespace: 'default',
         chart: {
           type: 'NixOsDataVolumeChart',
           props: {
             dataVolumeName: 'nixos-dev-datavolume',
             storageSize: '20Gi'
           }
         },
         argocd: { syncWave: '0' }
       }
       ```
    2. nixos-dev-vm (VirtualMachine):
       ```typescript
       {
         name: 'nixos-dev-vm',
         namespace: 'default',
         chart: {
           type: 'NixOsVmChart',
           props: {
             vmName: 'nixos-dev-vm',
             dataVolumeName: 'nixos-dev-datavolume',
             cpuCores: 2,
             memory: '4Gi',
             enableTailscale: false
           }
         },
         argocd: { syncWave: '10' }
       }
       ```
  - **Depends on**: T021-T024 (charts must exist)

- [ ] **T026** [US3] Synthesize and deploy VM resources
  - Run: `cd cdk8s && npx ts-node main-v2.ts`
  - Expected: `dist/nixos-dev-datavolume/manifests/`, `dist/nixos-dev-vm/manifests/` created
  - Verify manifests: DataVolume, Secret, VirtualMachine, Service YAMLs
  - Deploy: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
  - **Depends on**: T025 (config must be updated)

- [ ] **T027** [US3] Validate DataVolume import
  - Watch: `kubectl get datavolume nixos-dev-datavolume -w`
  - Expected phases: Pending → ImportScheduled → ImportInProgress → Succeeded
  - Time: <3 minutes for 1.7GB qcow2
  - Check PVC: `kubectl get pvc nixos-dev-datavolume`
  - Expected: Bound status, 20Gi size
  - **Success Criterion**: SC-003 (DataVolume import <3 min)
  - **If stuck**: Check CDI importer pod logs, verify image server HTTP access

- [ ] **T028** [US3] Validate VirtualMachine boot
  - Watch: `kubectl get vm,vmi -w`
  - Expected states: vm=Running, vmi=Running (phase: Running)
  - Time: <2 minutes from DataVolume Succeeded to VMI Running
  - Check virt-launcher pod: `kubectl get pods -l kubevirt.io/vm=nixos-dev-vm`
  - Expected: Pod Running
  - **Success Criterion**: SC-004 (VM boot time <2 min from DataVolume ready)
  - **If CrashLoopBackOff**: Check virt-launcher logs, verify DataVolume PVC Bound

- [ ] **T029** [US3] Validate SSH access via Service
  - Get SSH port: `SSH_PORT=$(kubectl get svc nixos-dev-vm-rdp -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}')`
  - Test SSH: `ssh vpittamp@localhost -p $SSH_PORT` (password: nixos123)
  - Expected: Login successful, prompt shows vpittamp@nixos-dev-vm
  - Verify hostname: `hostname` (expected: nixos-dev-vm)
  - Verify user: `whoami` (expected: vpittamp)
  - Verify sudo: `sudo -l` (expected: NOPASSWD:ALL)
  - **Success Criterion**: SC-006 (VM accessible via Service <30 sec after Running)
  - **Alternative**: Use `virtctl console nixos-dev-vm` for serial console access

- [ ] **T030** [US3] Validate Attic cache configuration
  - SSH into VM: `ssh vpittamp@localhost -p $SSH_PORT`
  - Check Nix config: `cat /etc/nix/nix.conf | grep substituters`
  - Expected: http://attic.nix-cache.svc.cluster.local:8080/nixos listed before cache.nixos.org
  - Check trusted keys: `cat /etc/nix/nix.conf | grep trusted-public-keys`
  - Expected: Attic public key present
  - Test cache access: `curl -I http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info`
  - Expected: HTTP 200 OK
  - **If missing/wrong**: Update kubevirt-minimal.nix, rebuild image (T010-T011), redeploy

- [ ] **T031** [US3] Execute desktop installation via nixos-rebuild
  - SSH into VM: `ssh vpittamp@localhost -p $SSH_PORT`
  - Run nixos-rebuild: `sudo nixos-rebuild switch --flake github:PittampalliOrg/nixos-config#vm-hetzner`
  - Expected: Downloads packages from Attic cache (cache hit >80%)
  - Time: <3 minutes with Attic cache
  - Verify KDE installation: `nix-store --query --requisites /run/current-system | grep plasma`
  - Expected: Multiple plasma packages listed
  - Reboot VM: `sudo reboot`
  - **Success Criterion**: SC-007 (Desktop rebuild <3 min with Attic)
  - **Success Criterion**: SC-008 (Cache hit rate >80% for subsequent rebuilds)
  - **If slow (>10 min)**: Check Attic cache access, may be building from source

- [ ] **T032** [US3] Validate RDP access to desktop
  - Get RDP port: `RDP_PORT=$(kubectl get svc nixos-dev-vm-rdp -o jsonpath='{.spec.ports[?(@.name=="rdp")].nodePort}')`
  - Open RDP client: mstsc.exe (Windows), Microsoft Remote Desktop (macOS), remmina (Linux)
  - Connect to: `localhost:$RDP_PORT`
  - Credentials: vpittamp / nixos123
  - Expected: KDE Plasma desktop session opens
  - Verify desktop: Open Konsole, run `echo $DESKTOP_SESSION`
  - Expected: plasmax11 or similar
  - **Success Criterion**: SC-009 (RDP access successful)
  - **If connection refused**: Check XRDP service `systemctl status xrdp`, verify port 3389 listening

- [ ] **T033** [US3] Document VM access methods in quickstart.md
  - Path: `specs/004-deploy-nixos-vms/quickstart.md` (already exists)
  - Verify: SSH, console, RDP access instructions accurate
  - Update: Any findings from testing (ports, credentials, troubleshooting)
  - **No changes needed if quickstart already accurate**

**Checkpoint**: NixOS VM deployed, running, accessible via SSH/RDP with desktop - MVP complete! 🎉

---

## Phase 6: User Story 4 - Automate NixOS VM Deployment via GitOps (Priority: P4)

**Goal**: Full end-to-end automation via ArgoCD with proper sync waves, enabling reproducible deployments (<10 min total).

**Independent Test**:
1. All resources deployed via ArgoCD Applications
2. Sync waves execute in correct order (image server → DataVolume → VM → Service)
3. ArgoCD shows all applications Synced + Healthy
4. End-to-end time from `cluster-update` to SSH accessible <10 minutes

### Implementation for User Story 4

- [ ] **T034** [US4] Verify ArgoCD Application manifests synthesized
  - Path: `cdk8s/dist/<app>.yaml` files
  - Expected files:
    - dist/nixos-image-server.yaml
    - dist/nixos-dev-datavolume.yaml
    - dist/nixos-dev-vm.yaml
  - Verify source URL: `cnoe://<app>/manifests` for local development
  - Verify syncWave annotations: -50 (image server), 0 (DataVolume), 10 (VM)
  - **Already synthesized in T019, T026** - just verify

- [ ] **T035** [US4] Validate ArgoCD sync wave ordering
  - Check ArgoCD UI: https://argocd.cnoe.localtest.me:8443
  - Verify application order:
    1. nixos-image-server (wave -50, should sync first)
    2. nixos-dev-datavolume (wave 0, after image server)
    3. nixos-dev-vm (wave 10, after DataVolume)
  - Watch sync: `argocd app list --insecure | grep nixos`
  - Expected: All applications Synced + Healthy
  - **Success Criterion**: SC-011 (ArgoCD sync succeeds)

- [ ] **T036** [US4] Create deploy-vm-image.sh end-to-end workflow
  - Path: `scripts/deploy-vm-image.sh`
  - Implement per contract: contracts/build-scripts.sh
  - Accept options: --push, --deploy
  - Workflow:
    1. Call build-kubevirt-image.sh (T010)
    2. Call package-image-docker.sh with --push if flag set (T014)
    3. Run CDK8s synthesis: `cd cdk8s && npx ts-node main-v2.ts`
    4. Run cluster-update if --deploy flag: `source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update`
  - Exit codes: Pass through from individual scripts
  - **Success Criterion**: SC-013 (End-to-end automation <10 min)

- [ ] **T037** [US4] Test full deployment from scratch
  - Delete existing resources: `kubectl delete vm,vmi,dv,pods -l app.kubernetes.io/name=nixos-dev-vm`
  - Run: `./scripts/deploy-vm-image.sh --push --deploy`
  - Measure time from start to SSH accessible
  - Expected: <10 minutes total
    - Build image: ~5 min
    - Package + push: ~3 min
    - Deploy + boot: ~2 min
  - Verify: All success criteria met (SC-001 through SC-013)
  - **Success Criterion**: SC-013 (End-to-end automation time <10 min)

- [ ] **T038** [US4] Document GitOps workflow in quickstart.md
  - Path: `specs/004-deploy-nixos-vms/quickstart.md` (already exists)
  - Verify: ArgoCD sync wave documentation accurate
  - Verify: cluster-update workflow documented
  - Update: End-to-end timing measurements from T037
  - **No changes needed if quickstart already accurate**

**Checkpoint**: Full GitOps automation complete - feature ready for production! 🚀

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements affecting multiple user stories, optional enhancements

- [ ] **T039** [P] [Polish] Add Tailscale support for external RDP access
  - Update NixOsVmChart (T021-T024) to support enableTailscale prop
  - Test: Deploy with `enableTailscale: true`, verify Tailscale LoadBalancer
  - Document: Add Tailscale workflow to quickstart.md
  - **Success Criterion**: SC-012 (Tailscale integration working)
  - **Optional**: Only if external access required

- [ ] **T040** [P] [Polish] Optimize Docker image size
  - Investigate: Multi-stage build to reduce nginx + qcow2 overhead
  - Test: Build optimized image, verify functionality unchanged
  - Measure: Image size reduction (target: <1.5GB total)
  - **Optional**: Current 1.8GB acceptable for development

- [ ] **T041** [P] [Polish] Add VM lifecycle helper functions
  - Path: `cdk8s/lib/vm-lifecycle-helpers.ts`
  - Implement: startVm(), stopVm(), snapshotVm(), restoreVm()
  - Use: virtctl CLI or Kubernetes API
  - **Optional**: For advanced use cases (not in minimal spec)

- [ ] **T042** [P] [Polish] Create production security configuration
  - Update: NixOsVmChart to support ESO for cloud-init passwords
  - Update: kubevirt-minimal.nix to disable PasswordAuthentication (SSH keys only)
  - Add: NetworkPolicies for VM traffic isolation
  - Document: Security hardening checklist
  - **Addresses**: Principle VII partial compliance from constitution check
  - **Future work**: Not required for MVP (P1-P3)

- [ ] **T043** [P] [Polish] Add support for multiple desktop environments
  - Research: GNOME, XFCE, i3 configuration via nixos-config
  - Design: Multi-image strategy vs runtime selection
  - Document: Desktop variant workflow
  - **Future enhancement**: Not in current spec

- [ ] **T044** [P] [Polish] Run complete quickstart.md validation
  - Follow: Every step in quickstart.md from fresh environment
  - Verify: All commands work as documented
  - Update: Any discrepancies found
  - Time: Validate <10 min quickstart claim
  - **Final validation** before marking feature complete

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - **US1** (Build Image): Can start after Foundational - No dependencies on other stories
  - **US2** (Image Server): Depends on US1 completion (needs qcow2 image)
  - **US3** (Launch VM): Depends on US2 completion (needs image server + DataVolume)
  - **US4** (GitOps): Depends on US1-US3 completion (integrates all components)
- **Polish (Phase 7)**: Depends on desired user stories being complete

### User Story Dependencies

```
Setup → Foundational → US1 → US2 → US3 → US4 → Polish
                        ↓      ↓      ↓
                     (Image) (HTTP) (VM)
```

**Critical Path**:
1. Setup (6 tasks, parallelizable) → 30 minutes
2. Foundational (3 tasks, 1 parallel) → 1 hour
3. US1 (4 tasks, sequential) → 5 minutes (build time)
4. US2 (7 tasks, some parallel) → 30 minutes
5. US3 (13 tasks, sequential) → 20 minutes
6. US4 (5 tasks, sequential) → 10 minutes
7. **Total**: ~2.5 hours development + <10 min deployment

### Within Each User Story

- **US1**: Sequential (build → validate → document)
- **US2**: T016+T017 parallel (different charts), rest sequential
- **US3**: T021+T022 parallel (part of same file), rest sequential
- **US4**: Sequential (test integration workflow)

### Parallel Opportunities

- **Setup Phase**: All 6 tasks [P] can run in parallel
- **Foundational Phase**: T008 [P] parallel with T007, T009
- **US2**: T016 [P] and T017 [P] can run together (different files)
- **Polish Phase**: All tasks [P] can run in parallel
- **Different User Stories**: Cannot parallelize due to dependencies (US1 → US2 → US3 → US4)

---

## Parallel Example: User Story 2

```bash
# These tasks can run in parallel (different files):
Task T016: "Create NixOsImageServerChart in cdk8s/charts/platform/nixos-image-server-chart.ts"
Task T017: "Create NixOsDataVolumeChart in cdk8s/charts/apps/nixos-datavolume-chart.ts"

# Wait for both to complete before T018 (config update)
```

---

## Implementation Strategy

### MVP First (User Stories 1-3)

1. **Complete Phase 1: Setup** (~30 min)
   - Verify cluster prerequisites
   - Install build tools

2. **Complete Phase 2: Foundational** (~1 hour)
   - Create kubevirt-helpers.ts library
   - Register chart types
   - Verify kubevirt-minimal.nix

3. **Complete Phase 3: US1 - Build Image** (~5 min)
   - Create build script
   - Execute first build
   - Validate output

4. **Complete Phase 4: US2 - Image Server** (~30 min)
   - Create packaging script
   - Implement charts
   - Deploy image server
   - Validate HTTP access

5. **Complete Phase 5: US3 - Launch VM** (~20 min)
   - Implement NixOsVmChart
   - Deploy VM resources
   - Validate SSH access
   - Install desktop
   - Validate RDP access

6. **STOP and VALIDATE**: Test full workflow end-to-end
   - Build → Package → Deploy → Access → Desktop
   - Measure timing against success criteria
   - **Deploy/demo if ready** - This is the MVP! 🎯

### Incremental Delivery

1. **Setup + Foundational** → Foundation ready (~1.5 hours)
2. **Add US1** → Image building works (~5 min)
3. **Add US2** → HTTP distribution works (~30 min)
4. **Add US3** → VM deployment works (~20 min) → **MVP Complete!** 🎉
5. **Add US4** → GitOps automation works (~10 min) → **Production Ready!** 🚀
6. **Add Polish** → Security, optimization, advanced features (optional)

### Sequential Team Strategy (Single Developer)

**Recommended path for single developer**:

1. Phase 1: Setup (verify everything first)
2. Phase 2: Foundational (create libraries)
3. **Critical path**: US1 → US2 → US3 (dependencies require sequential)
4. US4: GitOps integration
5. Polish: As needed

**Total time**: ~2.5 hours development + testing

### Parallel Team Strategy (Multiple Developers)

**Not recommended for this feature** - User stories have strong dependencies:
- US2 needs US1 output (qcow2 image)
- US3 needs US2 output (image server)
- US4 needs US1-US3 complete (integration)

**Better approach**: Have developers work on different phases of same story (e.g., one on charts, one on scripts, one on validation)

---

## Notes

- **[P] tasks** = different files, no dependencies, can run in parallel
- **[Story] label** (US1-US4) maps task to specific user story for traceability
- **Strong dependencies** between user stories due to artifact pipeline (image → HTTP → VM)
- **Tests are manual validation** - infrastructure-as-code doesn't need unit tests
- **Build/deploy timing critical** - measure against success criteria (SC-001 through SC-013)
- **Commit frequently** - after each completed task or logical group
- **Stop at checkpoints** - validate each user story independently before continuing
- **MVP is US1-US3** - US4 adds GitOps automation, Polish is optional enhancements
- **Avoid**: Skipping setup phase (cluster issues block everything), parallel story work (dependencies), building without validation (wastes time)

---

## Success Criteria Mapping

| Criterion | Tasks | Validation |
|-----------|-------|------------|
| SC-001: Image build 100% valid qcow2 | T010-T012 | qemu-img info, size <2GB |
| SC-002: Image server ready <30 sec | T019-T020 | kubectl get pods, HTTP 200 |
| SC-003: DataVolume import <3 min | T027 | kubectl get dv, PVC Bound |
| SC-004: VM boot <2 min | T028 | kubectl get vmi, phase Running |
| SC-006: SSH access <30 sec | T029 | ssh login successful |
| SC-007: Desktop rebuild <3 min | T031 | nixos-rebuild timing |
| SC-008: Cache hit >80% | T031 | Attic metrics |
| SC-009: RDP access successful | T032 | RDP client connection |
| SC-011: ArgoCD sync succeeds | T035 | argocd app list Synced |
| SC-013: E2E automation <10 min | T037 | Full workflow timing |

---

## Task Count Summary

- **Total Tasks**: 44 tasks
- **Phase 1 (Setup)**: 6 tasks (all [P] parallelizable)
- **Phase 2 (Foundational)**: 3 tasks (1 [P] parallelizable)
- **Phase 3 (US1)**: 4 tasks (sequential)
- **Phase 4 (US2)**: 7 tasks (2 [P] parallelizable)
- **Phase 5 (US3)**: 13 tasks (2 [P] parallelizable)
- **Phase 6 (US4)**: 5 tasks (sequential)
- **Phase 7 (Polish)**: 6 tasks (all [P] parallelizable, optional)

**Parallel Opportunities**: 11 tasks can run in parallel (25%)
**MVP Scope**: Phases 1-5 (User Stories 1-3) = 33 tasks
**Production Ready**: Add Phase 6 (User Story 4) = 38 tasks
**Full Feature**: All phases = 44 tasks

---

## Suggested MVP Scope

**Minimum Viable Product: User Stories 1-3 (P1-P3)**

- ✅ Build minimal NixOS base image
- ✅ Deploy HTTP image server for distribution
- ✅ Launch VirtualMachine with SSH + desktop access

**This provides**:
- Working VM deployment pipeline
- Manual desktop installation (via nixos-rebuild)
- SSH/RDP access
- All core functionality demonstrated

**Omit for MVP**:
- US4 (GitOps automation) - can deploy manually for initial testing
- Polish (security hardening, optimization) - functional requirements met

**Time to MVP**: ~2.5 hours development + ~20 minutes deployment/validation
