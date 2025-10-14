# Quickstart: RustDesk Base Image Integration

**Feature**: 006-update-our-specification
**Date**: 2025-10-14
**Status**: Implementation Guide

## Overview

This quickstart provides a step-by-step guide to integrate RustDesk remote desktop service into NixOS KubeVirt VM base images. By the end of this guide, you will have:

- NixOS base image with RustDesk pre-configured in headless mode
- VMs that boot with RustDesk service running within 2 minutes
- Secure password management via Azure Key Vault + External Secrets
- Remote desktop access via Tailscale subnet routing

**Time Estimate**:
- Initial setup (first time): ~45-60 minutes
- Subsequent image rebuilds: 3-5 minutes (with binary cache)

## Prerequisites

### On Hetzner Host (NixOS Base Image Build)

- [ ] NixOS with flakes enabled
- [ ] Nix build environment configured
- [ ] Access to `/etc/nixos/` directory (base image source)
- [ ] Existing `modules/services/rustdesk.nix` module
- [ ] Attic binary cache configured in `nix.conf`

### On Cluster (Kubernetes Deployment)

- [ ] Kubernetes cluster with KubeVirt installed
- [ ] MinIO deployed for image storage (from feature 003)
- [ ] Attic binary cache deployed (from feature 003)
- [ ] External Secrets Operator with Azure Key Vault ClusterSecretStore
- [ ] Tailscale subnet router configured (from feature 005)
- [ ] ArgoCD for GitOps deployment

### Required Tools

- [ ] `nix` (2.x+) for base image builds
- [ ] `kubectl` for Kubernetes operations
- [ ] `mc` (MinIO client) for image uploads
- [ ] `argocd` CLI for deployment verification
- [ ] `ssh` for VM access and testing

## Step 1: Prepare RustDesk Password in Azure Key Vault

**Time**: ~5 minutes

### 1.1 Generate Secure Password

```bash
# Generate random password (min 12 characters, recommended 16+)
RUSTDESK_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-16)
echo "Generated password: $RUSTDESK_PASSWORD"
# IMPORTANT: Save this password securely (1Password, etc.)
```

### 1.2 Store in Azure Key Vault

```bash
# Set your Azure Key Vault name
VAULT_NAME="your-keyvault-name"

# Create secret in Key Vault
az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name RUSTDESK-PASSWORD \
  --value "$RUSTDESK_PASSWORD"

# Verify secret created
az keyvault secret show \
  --vault-name $VAULT_NAME \
  --name RUSTDESK-PASSWORD \
  --query "value" -o tsv
```

**Verification**:
```bash
# Should return the password you just set
az keyvault secret show --vault-name $VAULT_NAME --name RUSTDESK-PASSWORD
```

## Step 2: Update NixOS Base Image with RustDesk Module

**Time**: ~10 minutes (configuration), 20-25 minutes (first build), 3-5 minutes (cached)

### 2.1 SSH to Hetzner Host

```bash
ssh root@hetzner-host
cd /etc/nixos
```

### 2.2 (Optional) Update RustDesk Module for VM Optimization

**Note**: The existing `/etc/nixos/modules/services/rustdesk.nix` module is already suitable for base image integration. This step adds minor optimizations for VM deployments.

```bash
# Edit the existing module
vim /etc/nixos/modules/services/rustdesk.nix
```

**Recommended updates** (see plan.md "NixOS Module Revision Analysis" for details):

1. Add headless mode flag to config generation (around line 140):
   ```nix
   allow-linux-headless = "Y"  # Enable headless mode for RustDesk-Flutter
   ```

2. Change default user to "root" for VM context (line 18):
   ```nix
   default = "root";  # Changed from "vpittamp" for VM deployments
   ```

**These updates are optional** - the module works without them, but they provide better VM defaults.

### 2.3 Update flake.nix (or configuration.nix)

Add RustDesk module import and configuration:

```nix
# /etc/nixos/configuration.nix (or flake.nix)
{
  imports = [
    ./modules/services/rustdesk.nix  # Import existing RustDesk module
  ];

  services.rustdesk = {
    enable = true;
    enableSystemService = true;      # Run as system service (headless mode)
    enableDirectIpAccess = true;     # Port 21116 for direct connections
    user = "root";                   # Required for headless VMs
    package = pkgs.rustdesk-flutter; # Latest Flutter-based version
    # permanentPassword can be set here or via cloud-init
  };

  # Firewall ports are opened automatically by the module
}
```

**Note**: The module automatically:
- Creates Xvfb virtual framebuffer service (required for RustDesk-Flutter)
- Sets software GL rendering environment variables
- Opens firewall ports (21115-21119 TCP, 21116 UDP)
- Generates RustDesk2.toml configuration with direct-server enabled

**Alternative**: If using flake.nix, add to `modules` list in the base image configuration.

### 2.4 Build Base Image (First Time - Cold Build)

```bash
# Build the NixOS KubeVirt image
# First build: 20-25 minutes (no cache)
nix build .#nixos-kubevirt-image

# Check build output
ls -lh ./result
# Expected: Symlink to /nix/store/...-nixos-kubevirt-image
```

**Verification**:
```bash
# Verify RustDesk package is in the image
nix-store -q --references ./result | grep rustdesk
# Expected: /nix/store/...-rustdesk-flutter-...
```

### 2.5 Push to Attic Binary Cache (One-Time Setup)

```bash
# Push all store paths to Attic cache for faster subsequent builds
./deployment/scripts/nix-cache/push-to-cache.sh ./result

# This makes future rebuilds 3-5 minutes instead of 20-25 minutes
```

**Verification**:
```bash
# Check cache for RustDesk packages
curl http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info
# Expected: HTTP 200 OK
```

## Step 3: Upload Base Image to MinIO

**Time**: ~5 minutes (depends on upload speed)

### 3.1 Convert to qcow2 (if needed)

```bash
# Check image format
file ./result
# If not qcow2, convert:
qemu-img convert -f raw -O qcow2 ./result nixos-kubevirt-v2.qcow2

# Otherwise, just copy:
cp ./result nixos-kubevirt-v2.qcow2
```

### 3.2 Upload to MinIO

```bash
# Configure MinIO client (one-time setup)
mc alias set local-minio http://minio.nix-cache.svc.cluster.local:9000 \
  <MINIO_ACCESS_KEY> <MINIO_SECRET_KEY>

# Create bucket if it doesn't exist
mc mb local-minio/images

# Upload image
mc cp nixos-kubevirt-v2.qcow2 local-minio/images/

# Verify upload
mc ls local-minio/images/
# Expected: nixos-kubevirt-v2.qcow2 (size ~1-3 GB)
```

**Verification**:
```bash
# Download image to verify integrity
mc cp local-minio/images/nixos-kubevirt-v2.qcow2 /tmp/test.qcow2
sha256sum /tmp/test.qcow2
sha256sum nixos-kubevirt-v2.qcow2
# Checksums should match
```

## Step 4: Create RustDesk Password ExternalSecret

**Time**: ~5 minutes

### 4.1 Create ExternalSecret Manifest

```bash
cd ~/stacks/cdk8s/charts/secrets/
# Edit or create rustdesk-secrets-chart.ts
```

Add ExternalSecret for RustDesk password (see `contracts/external-secret-rustdesk.yaml` for full spec):

```typescript
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { ExternalSecret } from '../../imports/external-secrets.io';

export class RustDeskSecretsChart extends Chart {
  constructor(scope: Construct, id: string, props: ChartProps = {}) {
    super(scope, id, props);

    new ExternalSecret(this, 'rustdesk-password', {
      metadata: {
        name: 'rustdesk-password',
        namespace: props.namespace || 'default',
        annotations: {
          'argocd.argoproj.io/sync-wave': '-70'
        }
      },
      spec: {
        refreshInterval: '1h',
        secretStoreRef: {
          name: 'azure-keyvault-store',
          kind: 'ClusterSecretStore'
        },
        target: {
          name: 'rustdesk-password',
          creationPolicy: 'Owner'
        },
        data: [{
          secretKey: 'password',
          remoteRef: {
            key: 'RUSTDESK-PASSWORD'
          }
        }]
      }
    });
  }
}
```

### 4.2 Register Chart and Add to Applications

```typescript
// In config/applications.ts
{
  name: 'rustdesk-secrets',
  namespace: 'default',
  chart: {
    type: 'RustDeskSecretsChart',
    props: {}
  },
  argocd: {
    syncWave: '-70',
    labels: { 'app.kubernetes.io/name': 'rustdesk-secrets' }
  }
}
```

### 4.3 Synthesize and Deploy

```bash
cd ~/stacks/cdk8s
npx ts-node main-v2.ts

# Deploy via cluster-update
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update
```

**Verification**:
```bash
# Check ExternalSecret status
kubectl get externalsecret rustdesk-password -n default
# Expected: READY=True, STATUS=SecretSynced

# Verify Kubernetes Secret created
kubectl get secret rustdesk-password -n default
# Expected: Type=Opaque, Data: password

# Test password value (should match what you set in Key Vault)
kubectl get secret rustdesk-password -n default -o jsonpath='{.data.password}' | base64 -d
```

## Step 5: Update NixOS VM Chart to Use New Base Image

**Time**: ~10 minutes

### 5.1 Update nixos-vm-chart.ts

```bash
cd ~/stacks/cdk8s/charts/infra/
# Edit nixos-vm-chart.ts
```

Update the chart to:
1. Reference new base image URL
2. Remove cloud-init RustDesk setup (now in base image)
3. Add Secret reference for password

```typescript
// Update DataVolume source
source: {
  http: {
    url: 'http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2'
  }
}

// Add environment variable for RustDesk password
env: [
  {
    name: 'RUSTDESK_PASSWORD',
    valueFrom: {
      secretKeyRef: {
        name: 'rustdesk-password',
        key: 'password'
      }
    }
  }
]

// Remove RustDesk setup from cloud-init (handled by base image)
// Only keep: users, SSH keys, passwords, Tailscale
```

### 5.2 Update kubevirt-helpers.ts

Remove RustDesk configuration from `generateCloudInitUserData` function:

```typescript
// REMOVE these sections (now in base image):
// - RustDesk systemd service creation
// - RustDesk config directory setup
// - RustDesk permanent password setting
// - RustDesk headless mode configuration

// KEEP:
// - User creation
// - SSH keys
// - Tailscale auth key setup
```

### 5.3 Synthesize and Deploy

```bash
cd ~/stacks/cdk8s
npx ts-node main-v2.ts

# Deploy via cluster-update
source ~/stacks/deployment/scripts/cluster-menu.sh
cluster-update
```

**Verification**:
```bash
# Check DataVolume status
kubectl get datavolume nixos-dev-vm-rootdisk -n default
# Expected: PHASE=Succeeded

# Verify image URL is updated
kubectl get datavolume nixos-dev-vm-rootdisk -n default -o jsonpath='{.spec.source.http.url}'
# Expected: http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2
```

## Step 6: Deploy VM and Test RustDesk

**Time**: ~5 minutes (VM boot + verification)

### 6.1 Delete Old VM (if exists)

```bash
# Delete VM to trigger recreation with new base image
kubectl delete vm nixos-dev-vm -n default

# Delete DataVolume to pull new image
kubectl delete datavolume nixos-dev-vm-rootdisk -n default

# ArgoCD will recreate both automatically
```

### 6.2 Wait for VM to Boot

```bash
# Watch VM status
kubectl get vm,vmi -n default -w

# Wait for VMI to reach "Running" phase
kubectl wait --for=condition=Ready vmi/nixos-dev-vm -n default --timeout=5m
```

**Expected Output**:
```
NAME                         AGE   STATUS    READY
virtualmachine.kubevirt.io/nixos-dev-vm   30s   Running   True
virtualmachineinstance.kubevirt.io/nixos-dev-vm   25s   Running   True
```

### 6.3 Verify RustDesk Service Running

```bash
# Port-forward SSH to VM
kubectl port-forward -n default svc/nixos-dev-vm-rdp 2222:22 &

# SSH to VM
ssh -p 2222 nixos@localhost

# Inside VM: Check RustDesk service status
sudo systemctl status rustdesk
```

**Expected Output**:
```
● rustdesk.service - RustDesk Remote Desktop Service
     Loaded: loaded (/etc/systemd/system/rustdesk.service; enabled)
     Active: active (running) since ...
   Main PID: 1234 (rustdesk)
```

### 6.4 Get RustDesk Connection Details

```bash
# Still in VM: Get RustDesk ID
sudo cat /root/.config/rustdesk/RustDesk2.toml | grep "^id ="
# Expected: id = "123456789"

# Verify headless mode enabled
sudo cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless
# Expected: allow-linux-headless = "Y"

# Check port listening
sudo ss -tlnp | grep 21116
# Expected: LISTEN 0 ... *:21116 *:* users:(("rustdesk",pid=1234,fd=10))
```

### 6.5 Test Remote Desktop Connection

**Option A: Via Tailscale Subnet Routing** (Recommended)

```bash
# Get VM pod IP
VM_POD_IP=$(kubectl get vmi nixos-dev-vm -n default -o jsonpath='{.status.interfaces[0].ipAddress}')
echo "RustDesk ID: (from step 6.4)"
echo "VM IP: $VM_POD_IP"
echo "Port: 21116"
echo "Password: (from Azure Key Vault - RUSTDESK-PASSWORD)"

# On your Mac/laptop (connected to Tailscale):
# 1. Open RustDesk client
# 2. Enter ID: <RustDesk ID from VM>
# 3. Click "Connect"
# 4. Enter password from Azure Key Vault
# 5. Should connect successfully
```

**Option B: Via Port-Forward** (For Testing)

```bash
# Port-forward RustDesk port
kubectl port-forward -n default svc/nixos-dev-vm-rdp 21116:21116 &

# Connect RustDesk client to: localhost:21116
```

## Step 7: Verify Success Criteria

**Time**: ~5 minutes

### SC-001: VMs boot with RustDesk service running within 2 minutes

```bash
# Check VM boot time and RustDesk service start time
kubectl get vmi nixos-dev-vm -n default -o jsonpath='{.status.phase}:{.status.guestOSInfo.kernel}'

# SSH to VM and check RustDesk start time
ssh -p 2222 nixos@localhost 'sudo systemctl show rustdesk --property=ActiveEnterTimestamp'
# Compare with VM boot timestamp (should be < 2 min apart)
```

**Expected**: ✅ PASS (service starts within 2 minutes of boot)

### SC-002: RustDesk service start success rate is 99%+

```bash
# Check service status
kubectl exec -n default <vm-pod-name> -- systemctl is-active rustdesk
# Expected: active
```

**Expected**: ✅ PASS (service is active)

### SC-003: Base image rebuild completes within 5 minutes with binary cache

```bash
# On Hetzner host: Time a rebuild
time nix build .#nixos-kubevirt-image
# Expected: < 5 minutes (with cache hits)
```

**Expected**: ✅ PASS (if binary cache is populated from Step 2.4)

### SC-004: Remote desktop connection established within 30 seconds

```bash
# Manual test: Time from clicking "Connect" in RustDesk client to desktop appearing
# Expected: < 30 seconds
```

**Expected**: ✅ PASS (measured manually)

### SC-005: Configuration changes propagate to all new VMs after image rebuild

```bash
# Test: Change RustDesk config in base image, rebuild, deploy new VM
# Expected: New VM has updated configuration
```

**Expected**: ✅ PASS (verified by deploying new VM)

### SC-006: Zero post-boot configuration failures related to cloud-init runcmd

```bash
# Check cloud-init logs (should NOT contain RustDesk setup)
ssh -p 2222 nixos@localhost 'cat /var/log/cloud-init-output.log | grep -i rustdesk'
# Expected: No RustDesk setup in cloud-init (handled by base image)
```

**Expected**: ✅ PASS (no cloud-init RustDesk config)

## Troubleshooting

### Issue: ExternalSecret not syncing

**Symptoms**: `kubectl get externalsecret rustdesk-password` shows `READY=False`

**Resolution**:
```bash
# Check ClusterSecretStore exists
kubectl get clustersecretstore azure-keyvault-store

# Verify Azure Key Vault secret exists
az keyvault secret show --vault-name $VAULT_NAME --name RUSTDESK-PASSWORD

# Check ESO controller logs
kubectl logs -n external-secrets deploy/external-secrets --tail=50

# Common issue: Workload Identity not configured
kubectl describe pod -n external-secrets | grep -A 10 "Volumes:"
```

### Issue: DataVolume stuck in "ImportInProgress"

**Symptoms**: `kubectl get datavolume` shows `PHASE=ImportInProgress` for >10 minutes

**Resolution**:
```bash
# Check CDI importer pod logs
kubectl get pods -n cdi | grep importer
kubectl logs -n cdi <importer-pod-name>

# Verify image URL is accessible from cluster
kubectl run curl-test --image=curlimages/curl --rm -it -- curl -I http://minio.nix-cache.svc.cluster.local:9000/images/nixos-kubevirt-v2.qcow2
# Expected: HTTP/1.1 200 OK

# Check MinIO service
kubectl get svc -n nix-cache minio
```

### Issue: RustDesk service not starting on VM boot

**Symptoms**: `systemctl status rustdesk` shows "inactive (dead)" or "failed"

**Resolution**:
```bash
# Check service logs
sudo journalctl -u rustdesk --since "5 min ago"

# Common issues:
# 1. GL errors: Verify LIBGL_ALWAYS_SOFTWARE=1 in service environment
systemctl show rustdesk --property=Environment

# 2. Config directory missing: Check /root/.config/rustdesk exists
ls -la /root/.config/rustdesk/

# 3. Port already in use: Check nothing else uses 21116
sudo ss -tlnp | grep 21116

# 4. Headless mode not enabled: Check config
cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless
# Expected: allow-linux-headless = "Y"
```

### Issue: Can't connect via Tailscale subnet routing

**Symptoms**: RustDesk client can't reach VM pod IP

**Resolution**:
```bash
# Verify Tailscale subnet routes approved in Tailscale admin console
# Expected: 10.244.0.0/16 (cluster pod network) approved

# Check Tailscale subnet router status
kubectl exec -n tailscale tailscale-subnet-router -- tailscale status
# Expected: Subnet routes advertised and approved

# Test connectivity from Mac/laptop
ping <VM_POD_IP>
# Expected: Ping succeeds

# If ping works but RustDesk doesn't:
# - Verify firewall port 21116 is open on VM
# - Check RustDesk service is listening: sudo ss -tlnp | grep 21116
```

## Next Steps

After completing this quickstart:

1. **Update documentation**: Update `docs/RUSTDESK_CONNECTION_GUIDE.md` with base image approach
2. **Automate image builds**: Set up CI/CD pipeline for automatic rebuilds on config changes
3. **Add monitoring**: Track RustDesk service health, connection success rate
4. **Plan password rotation**: Define quarterly rotation schedule for RUSTDESK-PASSWORD in Key Vault
5. **Create runbooks**: Document operational procedures for base image updates

## Time Summary

| Step | Time (First Time) | Time (Subsequent) |
|------|-------------------|-------------------|
| 1. Azure Key Vault setup | 5 min | N/A (one-time) |
| 2. Base image build | 20-25 min (cold) | 3-5 min (cached) |
| 3. Image upload to MinIO | 5 min | 5 min |
| 4. ExternalSecret creation | 5 min | N/A (one-time) |
| 5. VM chart update | 10 min | N/A (one-time) |
| 6. VM deployment & testing | 5 min | 5 min |
| 7. Verification | 5 min | 5 min |
| **Total** | **55-60 min** | **18-20 min** |

**Note**: Subsequent deployments (after initial setup) only require steps 2, 3, 6, and 7.

## Success Indicators

✅ Base image contains RustDesk service configuration
✅ VM boots with RustDesk running within 2 minutes
✅ Remote desktop connection works via Tailscale
✅ Password securely stored in Azure Key Vault
✅ Zero cloud-init RustDesk configuration (all in base image)
✅ Image rebuilds complete in under 5 minutes with cache
