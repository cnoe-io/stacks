# Quickstart Guide: Deploy NixOS VMs using KubeVirt

**Feature**: 004-deploy-nixos-vms
**Date**: 2025-10-11
**Target Audience**: Platform engineers, DevOps engineers, developers deploying NixOS VMs

## Prerequisites

### Required Software

- **Kubernetes cluster** with KubeVirt + CDI installed
  - KubeVirt version: 1.0.0+
  - CDI version: 1.57.0+
  - kubectl configured with cluster access

- **NixOS development environment**
  - Nix 2.x with flakes enabled
  - nixos-generators (install via: `nix-shell -p nixos-generators`)
  - qemu-img (for qcow2 validation)

- **Docker** for image packaging
  - Docker Engine 20.10+
  - Docker Hub account (for pushing images)

- **TypeScript development**
  - Node.js 18+
  - npm or yarn
  - TypeScript 5.x (installed via npm)

### Optional Tools

- `virtctl` - KubeVirt command-line tool (for VM console access)
- `libguestfs-tools` - For qcow2 inspection (`guestfish`)
- Remote desktop client - For RDP access (Microsoft Remote Desktop, Remmina)

### Cluster Requirements

Verify your cluster meets these requirements:

```bash
# Check KubeVirt is installed
kubectl get crds | grep kubevirt.io

# Check CDI is installed
kubectl get crds | grep cdi.kubevirt.io

# Check StorageClass exists
kubectl get storageclass

# Check available resources
kubectl top nodes
```

Expected: VirtualMachine and DataVolume CRDs exist, at least one StorageClass with dynamic provisioning.

## Quick Start (5 Minutes)

This guide walks through deploying a minimal NixOS VM in <10 minutes.

### Step 1: Build Minimal NixOS Image (5 min)

The minimal base image provides SSH access only (no desktop).

```bash
# Clone/navigate to repository
cd ~/stacks

# Build qcow2 image using existing configuration
nixos-generate \
  --format kubevirt \
  --configuration /etc/nixos/configurations/kubevirt-minimal.nix \
  --out-link /tmp/kubevirt-base-image

# Verify output
ls -lh /tmp/kubevirt-base-image/nixos.qcow2
# Expected: ~1.7GB qcow2 file

# Validate format
qemu-img info /tmp/kubevirt-base-image/nixos.qcow2
# Expected: file format: qcow2, virtual size: ~10GB
```

**Time**: ~5 minutes (with Nix binary cache)

**Troubleshooting**:
- Build fails with "permission denied": Run with sudo or fix /nix permissions
- "nixos-generate: command not found": Install via `nix-shell -p nixos-generators`
- Slow build (>10 min): Check internet connection, binary cache availability

### Step 2: Package into Docker Image (1 min)

Package the qcow2 image into a Docker container with nginx.

```bash
# Create temporary directory
mkdir -p /tmp/docker-build
cd /tmp/docker-build

# Create Dockerfile
cat > Dockerfile <<'EOF'
FROM nginx:alpine
COPY nixos.qcow2 /usr/share/nginx/html/
RUN chmod 644 /usr/share/nginx/html/nixos.qcow2
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

# Copy qcow2 to build context
cp /tmp/kubevirt-base-image/nixos.qcow2 .

# Build Docker image
docker build -t vpittamp23/nixos-kubevirt-minimal:latest .

# Verify image
docker images vpittamp23/nixos-kubevirt-minimal:latest
# Expected: ~1.8GB image

# Test locally (optional)
docker run -d --rm -p 8080:80 --name test-nginx vpittamp23/nixos-kubevirt-minimal:latest
curl -I http://localhost:8080/nixos.qcow2
docker stop test-nginx
```

**Time**: ~1 minute

**Troubleshooting**:
- "Cannot connect to Docker daemon": Start Docker service
- Build fails: Check qcow2 file exists in build context

### Step 3: Push to Docker Hub (2 min)

```bash
# Login to Docker Hub
docker login
# Enter username: vpittamp23
# Enter password: <from 1Password>

# Push image
docker push vpittamp23/nixos-kubevirt-minimal:latest

# Verify push
docker pull vpittamp23/nixos-kubevirt-minimal:latest
```

**Time**: ~2 minutes (1.8GB upload, depends on bandwidth)

**Alternative**: Use existing image `vpittamp23/nixos-kubevirt-minimal:latest` (skip Steps 1-3 for testing)

### Step 4: Deploy via CDK8s + ArgoCD (2 min)

Generate Kubernetes manifests and deploy via GitOps.

```bash
# Navigate to CDK8s directory
cd ~/stacks/cdk8s

# Synthesize manifests
npx ts-node main-v2.ts
# Expected: Generates dist/nixos-image-server/, dist/nixos-dev-vm/ directories

# Verify synthesis
ls -la dist/nixos-image-server/manifests/
ls -la dist/nixos-dev-vm/manifests/

# Deploy to cluster using cluster-menu wrapper
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update

# Alternatively, deploy specific packages only
idpbuilder create --package dist/nixos-image-server
idpbuilder create --package dist/nixos-dev-vm
```

**Time**: ~2 minutes (synthesis + ArgoCD sync)

**Troubleshooting**:
- "TypeError" during synthesis: Run `npm install` in cdk8s directory
- ArgoCD sync errors: Check ArgoCD UI at https://argocd.cnoe.localtest.me:8443

### Step 5: Verify VM Deployment (2 min)

Wait for VM to boot and verify SSH access.

```bash
# Watch VM status
watch kubectl get vm,vmi,pods -n default

# Expected states:
# vm/nixos-dev-vm     Running
# vmi/nixos-dev-vm    Running
# pod/virt-launcher-nixos-dev-vm-xxxxx   Running

# Wait for VMI to reach Running state (~2 minutes)

# Check VM details
kubectl get vm nixos-dev-vm -o yaml
kubectl get vmi nixos-dev-vm -o jsonpath='{.status.interfaces[0].ipAddress}'

# Get Service details
kubectl get svc nixos-dev-vm-rdp -n default
```

**Expected Output**:
```
NAME                    TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)
nixos-dev-vm-rdp        NodePort   10.96.xxx.xxx   <none>        22:3xxxx/TCP,3389:3xxxx/TCP
```

### Step 6: Access VM via SSH (<1 min)

```bash
# Method 1: Via Service (NodePort)
# Get NodePort for SSH
SSH_PORT=$(kubectl get svc nixos-dev-vm-rdp -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}')
echo "SSH port: $SSH_PORT"

# SSH to VM (password: nixos123)
ssh vpittamp@localhost -p $SSH_PORT
# Or use SSH key (already configured in cloud-init)

# Method 2: Via virtctl console
virtctl console nixos-dev-vm
# Login: vpittamp / nixos123

# Method 3: Via port-forward
kubectl port-forward svc/nixos-dev-vm-rdp 2222:22 &
ssh vpittamp@localhost -p 2222
```

**Inside VM**: Verify cloud-init configuration

```bash
# Check hostname
hostname
# Expected: nixos-dev-vm

# Check user
whoami
# Expected: vpittamp

# Check Nix configuration (Attic cache)
cat /etc/nix/nix.conf
# Expected: substituters includes http://attic.nix-cache.svc.cluster.local:8080/nixos

# Check services
systemctl status sshd
# Expected: active (running)
```

## Phase 2: Install Desktop Environment (3 min)

Now that the minimal base is deployed, install KDE Plasma via nixos-rebuild.

### Prerequisites

- Attic binary cache deployed (spec 003)
- VM has network connectivity
- nixos-config repository accessible (github.com/PittampalliOrg/nixos-config)

### Install Desktop

```bash
# SSH into VM
ssh vpittamp@localhost -p $SSH_PORT

# Run nixos-rebuild with vm-hetzner configuration
sudo nixos-rebuild switch --flake github:PittampalliOrg/nixos-config#vm-hetzner

# This will:
# 1. Query Attic cache for packages (cache hit >80%)
# 2. Download packages from Attic (100-500 MB/s in-cluster)
# 3. Install KDE Plasma, XRDP, fonts, applications
# 4. Configure desktop environment
# 5. Enable XRDP service

# Wait for rebuild to complete (~3 minutes with Attic cache)
```

**Time**: ~3 minutes (with Attic cache hit >80%)

**Without Attic cache**: 20+ minutes (building KDE from source)

### Verify Desktop Installation

```bash
# Check XRDP service
systemctl status xrdp
# Expected: active (running)

# Check desktop packages
nix-store --query --requisites /run/current-system | grep -i plasma
# Expected: Multiple plasma packages listed

# Reboot VM to start desktop session
sudo reboot
```

### Access Desktop via RDP

```bash
# Get RDP NodePort
RDP_PORT=$(kubectl get svc nixos-dev-vm-rdp -o jsonpath='{.spec.ports[?(@.name=="rdp")].nodePort}')
echo "RDP port: $RDP_PORT"

# Open RDP client
# - Windows: mstsc.exe
# - macOS: Microsoft Remote Desktop
# - Linux: remmina

# Connect to: localhost:$RDP_PORT
# Username: vpittamp
# Password: nixos123
```

**Expected**: KDE Plasma desktop session opens

## Common Workflows

### Update Base Image

```bash
# 1. Edit NixOS configuration
vim /etc/nixos/configurations/kubevirt-minimal.nix

# 2. Rebuild image
nixos-generate --format kubevirt \
  --configuration /etc/nixos/configurations/kubevirt-minimal.nix \
  --out-link /tmp/kubevirt-base-image

# 3. Repackage Docker image
cd /tmp/docker-build
cp /tmp/kubevirt-base-image/nixos.qcow2 .
docker build -t vpittamp23/nixos-kubevirt-minimal:v1.1.0 .
docker push vpittamp23/nixos-kubevirt-minimal:v1.1.0

# 4. Update CDK8s chart
vim cdk8s/charts/platform/nixos-image-server-chart.ts
# Change: image = 'vpittamp23/nixos-kubevirt-minimal:v1.1.0'

# 5. Resynthesize and deploy
cd cdk8s
npx ts-node main-v2.ts
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update
```

### Deploy Additional VMs

```bash
# Method 1: Update config/applications.ts
vim cdk8s/config/applications.ts

# Add new application:
{
  name: 'nixos-vm-2',
  namespace: 'default',
  chart: {
    type: 'NixOsVmChart',
    props: {
      vmName: 'nixos-vm-2',
      dataVolumeName: 'nixos-datavolume-2', // Must create separate DataVolume
      cpuCores: 4,
      memory: '8Gi'
    }
  }
}

# Synthesize and deploy
cd cdk8s
npx ts-node main-v2.ts
cluster-update

# Method 2: Direct manifest application (for testing)
kubectl apply -f dist/nixos-vm-2/manifests/
```

### Enable Tailscale Exposure

```bash
# Update chart props in config/applications.ts
{
  name: 'nixos-dev-vm',
  chart: {
    type: 'NixOsVmChart',
    props: {
      vmName: 'nixos-dev-vm',
      enableTailscale: true,
      tailscaleHostname: 'nixos-dev-rdp'
    }
  }
}

# Synthesize and deploy
cd cdk8s
npx ts-node main-v2.ts
cluster-update

# Verify Tailscale Service
kubectl get svc nixos-dev-vm-rdp -o yaml | grep tailscale
# Expected: tailscale.com/expose, tailscale.com/hostname annotations

# Access via Tailscale
tailscale status | grep nixos-dev-rdp
# Expected: nixos-dev-rdp.ts.net with IP

# RDP via Tailscale
# Connect to: nixos-dev-rdp.ts.net:3389
```

### Snapshot & Restore VM

```bash
# Take VM snapshot (requires KubeVirt VirtualMachineSnapshot CRD)
# Note: This feature is for P4+ implementation

kubectl create -f - <<EOF
apiVersion: snapshot.kubevirt.io/v1alpha1
kind: VirtualMachineSnapshot
metadata:
  name: nixos-dev-vm-snapshot-1
  namespace: default
spec:
  source:
    apiGroup: kubevirt.io
    kind: VirtualMachine
    name: nixos-dev-vm
EOF

# Wait for snapshot to complete
kubectl wait --for=condition=Ready \
  vmsnap/nixos-dev-vm-snapshot-1 \
  --timeout=5m

# Restore snapshot
kubectl create -f - <<EOF
apiVersion: snapshot.kubevirt.io/v1alpha1
kind: VirtualMachineRestore
metadata:
  name: restore-nixos-dev-vm
  namespace: default
spec:
  target:
    apiGroup: kubevirt.io
    kind: VirtualMachine
    name: nixos-dev-vm
  virtualMachineSnapshotName: nixos-dev-vm-snapshot-1
EOF
```

### Populate Attic Cache

```bash
# SSH into VM after desktop installation
ssh vpittamp@localhost -p $SSH_PORT

# Push system closure to Attic cache
nix build --print-out-paths /run/current-system
SYSTEM_PATH=$(nix build --print-out-paths /run/current-system)

# Push to Attic (requires attic CLI configured)
attic push nixos $SYSTEM_PATH

# Verify cache contents
attic cache info nixos
# Expected: Cache size increases, >80% hit rate for next VM
```

## Troubleshooting

### VM Not Starting

**Symptom**: VM remains in "Starting" state

```bash
# Check VMI pod logs
kubectl logs virt-launcher-nixos-dev-vm-xxxxx -n default

# Check events
kubectl describe vm nixos-dev-vm

# Common causes:
# - DataVolume not ready: kubectl get dv
# - Insufficient resources: kubectl top nodes
# - Image pull failure: kubectl describe pod virt-launcher-nixos-dev-vm-xxxxx
```

**Fix**:
```bash
# Delete and recreate VM
kubectl delete vm nixos-dev-vm
cluster-update  # Resyncs ArgoCD application
```

### DataVolume Import Failing

**Symptom**: DataVolume stuck in "ImportInProgress" or "Failed"

```bash
# Check CDI importer pod logs
kubectl logs -n cdi importer-nixos-dev-datavolume-xxxxx

# Check image server accessibility
kubectl run curl-test --image=curlimages/curl:latest --rm -it -- \
  curl -I http://nixos-image-server.default.svc.cluster.local/nixos.qcow2

# Expected: HTTP 200 OK
```

**Fix**:
```bash
# Verify image server is running
kubectl get pods -l app=nixos-image-server

# Restart image server if needed
kubectl rollout restart deployment nixos-image-server

# Delete and recreate DataVolume
kubectl delete dv nixos-dev-datavolume
cluster-update
```

### SSH Access Denied

**Symptom**: "Permission denied (publickey, password)"

```bash
# Check cloud-init logs inside VM (via virtctl console)
virtctl console nixos-dev-vm
# Login: vpittamp / nixos123

# Check cloud-init status
sudo cloud-init status --long

# Check SSH configuration
sudo cat /etc/ssh/sshd_config | grep PasswordAuthentication
# Expected: PasswordAuthentication yes

# Check user exists
id vpittamp
```

**Fix**:
```bash
# Reset cloud-init (inside VM)
sudo cloud-init clean --logs --reboot

# Or recreate VM with correct cloud-init Secret
kubectl delete secret nixos-dev-vm-cloudinit
kubectl delete vm nixos-dev-vm
cluster-update
```

### Attic Cache Not Working

**Symptom**: nixos-rebuild still downloading from cache.nixos.org

```bash
# Check Attic service accessibility (inside VM)
curl -I http://attic.nix-cache.svc.cluster.local:8080/nixos

# Check Nix configuration
cat /etc/nix/nix.conf | grep substituters

# Check Attic cache has content
curl http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info
```

**Fix**:
```bash
# Verify Attic deployment (spec 003)
kubectl get pods -n nix-cache

# Populate cache from working VM
ssh vpittamp@localhost -p $SSH_PORT
SYSTEM_PATH=$(nix build --print-out-paths /run/current-system)
attic push nixos $SYSTEM_PATH
```

## Next Steps

- **User Story 4 (P4)**: Automate full workflow via Kargo pipelines
- **Production Security**: Integrate External Secrets Operator for passwords/keys
- **Multi-Environment**: Deploy VMs to dev-vcluster, staging-vcluster
- **Desktop Variants**: Support GNOME, XFCE, i3 desktop environments
- **Monitoring**: Add Prometheus metrics for VM performance
- **Backup**: Implement VirtualMachineSnapshot automation

## Resources

- **Spec**: [spec.md](spec.md) - Feature specification
- **Plan**: [plan.md](plan.md) - Implementation plan
- **Data Model**: [data-model.md](data-model.md) - Entity definitions
- **Contracts**: [contracts/](contracts/) - API contracts
- **Research**: [research.md](research.md) - Technical decisions

### External Documentation

- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [CDI DataVolumes](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)
- [nixos-generators](https://github.com/nix-community/nixos-generators)
- [Cloud-init Examples](https://cloudinit.readthedocs.io/en/latest/reference/examples.html)
- [virtctl CLI Reference](https://kubevirt.io/user-guide/operations/virtctl_client_tool/)

### Community Support

- KubeVirt Slack: #kubevirt on Kubernetes Slack
- NixOS Discourse: https://discourse.nixos.org/
- CDK8s GitHub: https://github.com/cdk8s-team/cdk8s

---

**Estimated Time to First Working VM**: ~10 minutes (with existing image) to ~20 minutes (building from scratch)
