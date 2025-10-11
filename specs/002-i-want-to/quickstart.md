# KubeVirt + NixOS VMs Quickstart Guide

**Feature**: KubeVirt Installation with NixOS VM Images
**Date**: 2025-10-10
**Audience**: Platform engineers deploying KubeVirt to Kind cluster

## Prerequisites

Before starting, ensure you have:

- ✅ **Kind cluster running** with at least 8GB RAM, 4 CPU cores allocated
- ✅ **ArgoCD deployed** via idpbuilder or manual installation
- ✅ **NixOS environment** with flakes enabled (`nix-command`, `flakes` experimental features)
- ✅ **virtctl CLI** installed (via krew or binary download)
- ✅ **kubectl** configured for Kind cluster access
- ✅ **Access to /etc/nixos** with existing base.nix configuration

**Verify Prerequisites**:
```bash
# Check Kind cluster
kubectl cluster-info
kubectl get nodes

# Check ArgoCD
kubectl get pods -n argocd

# Check Nix flakes
nix flake show /etc/nixos

# Check virtctl
virtctl version
```

---

## Phase 1: Create NixOS VM Configuration

### Step 1.1: Create vm-minimal.nix

Create a new NixOS configuration that reuses your existing base.nix:

```bash
# Create vm-minimal.nix in /etc/nixos/configurations/
cat > /etc/nixos/configurations/vm-minimal.nix <<'EOF'
# Minimal NixOS VM configuration for KubeVirt
{ config, pkgs, modulesPath, ... }:
{
  imports = [
    # Reuse existing base configuration (SSH keys, users, core packages)
    ./base.nix

    # QEMU guest optimizations (virtio drivers, agent)
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # VM-specific configuration
  networking.hostName = "nixos-kubevirt-vm";

  # Cloud-init support for KubeVirt (REQUIRED)
  services.cloud-init.enable = true;

  # QEMU guest agent for better VM integration (RECOMMENDED)
  services.qemu-guest-agent.enable = true;

  # Boot configuration for VM
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";  # virtio disk device
  };

  # Minimal additional packages (base.nix already provides vim, git, curl, jq, tmux)
  environment.systemPackages = with pkgs; [
    # Add VM-specific tools if needed:
    # kubectl
    # docker
  ];

  system.stateVersion = "24.11";
}
EOF
```

### Step 1.2: Build NixOS qcow2 Image

Build the VM image using nixos-generators:

```bash
# Create output directory
mkdir -p /home/vpittamp/stacks/nixos-images

# Build qcow2 image from vm-minimal.nix
nix run github:nix-community/nixos-generators -- \
  --format qcow \
  --configuration /etc/nixos/configurations/vm-minimal.nix \
  --out-link /home/vpittamp/stacks/nixos-images/kubevirt-vm.qcow2

# Verify image was created
ls -lh /home/vpittamp/stacks/nixos-images/kubevirt-vm.qcow2
# Expected: ~1-2GB qcow2 file
```

**Troubleshooting**:
- If build fails with "missing attribute": Check that base.nix exists in `/etc/nixos/configurations/`
- If build is slow: First build may take 10-20 minutes (downloads nixpkgs, builds packages)
- If out of disk space: Ensure at least 20GB free space for Nix store

---

## Phase 2: Deploy KubeVirt Operator

### Step 2.1: Import KubeVirt CRDs to CDK8s

```bash
cd /home/vpittamp/stacks/cdk8s

# Add KubeVirt and CDI imports to cdk8s.yaml
cat >> cdk8s.yaml <<'EOF'
  # KubeVirt CRDs
  - https://github.com/kubevirt/kubevirt/releases/download/v1.3.1/kubevirt-operator.yaml

  # CDI CRDs
  - https://github.com/kubevirt/containerized-data-importer/releases/download/v1.59.0/cdi-operator.yaml
EOF

# Import CRDs (generates TypeScript bindings)
npm run import

# Verify imports
ls imports/kubevirt.io.ts
ls imports/cdi.kubevirt.io.ts
```

### Step 2.2: Create KubeVirt Chart

Create `cdk8s/charts/infra/kubevirt-chart.ts`:

```typescript
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { KubeVirt } from '../../imports/kubevirt.io';
import { addSyncWave } from '../../lib/argocd-sync-builders';

export interface KubeVirtChartProps extends ChartProps {
  version?: string;
  useEmulation?: boolean;
}

export class KubeVirtChart extends Chart {
  constructor(scope: Construct, id: string, props: KubeVirtChartProps = {}) {
    super(scope, id, props);

    const useEmulation = props.useEmulation ?? true; // Default true for Kind

    // Namespace
    const ns = new k8s.KubeNamespace(this, 'namespace', {
      metadata: { name: 'kubevirt' },
    });
    addSyncWave(ns, -110);

    // KubeVirt CR (software emulation for Kind)
    const kv = new KubeVirt(this, 'kubevirt', {
      metadata: {
        name: 'kubevirt',
        namespace: 'kubevirt',
      },
      spec: {
        configuration: {
          developerConfiguration: {
            useEmulation,  // Required for Kind (no KVM)
          },
        },
      },
    });
    addSyncWave(kv, -90);

    // Note: KubeVirt operator deployment is installed separately
    // (download operator.yaml and import resources, or use Helm)
  }
}
```

### Step 2.3: Register Chart and Add to Applications

```typescript
// In cdk8s/main-v2.ts
import { KubeVirtChart } from './charts/infra/kubevirt-chart';

// Register chart
IdpBuilderChartFactory.register('KubeVirtChart', KubeVirtChart);
```

```typescript
// In cdk8s/config/applications.ts
{
  name: 'kubevirt',
  namespace: 'kubevirt',
  chart: {
    type: 'KubeVirtChart',
    props: {
      useEmulation: true,  // Required for Kind
    },
  },
  argocd: {
    syncWave: '-100',
    labels: {
      'app.kubernetes.io/name': 'kubevirt',
      'app.kubernetes.io/component': 'infrastructure',
    },
    syncPolicy: {
      automated: {
        prune: true,
        selfHeal: true,
      },
    },
  },
},
```

### Step 2.4: Synthesize and Deploy

```bash
# Synthesize all packages
cd /home/vpittamp/stacks/cdk8s
npx ts-node main-v2.ts

# Verify synthesized manifests
ls dist/kubevirt/manifests/

# Deploy via cluster-menu.sh wrapper
cd /home/vpittamp/stacks
source deployment/scripts/cluster-menu.sh
cluster-update

# Verify KubeVirt deployment
kubectl get pods -n kubevirt
# Expected: virt-operator, virt-controller, virt-handler, virt-api pods Running

# Check KubeVirt CR status
kubectl get kubevirt -n kubevirt kubevirt -o jsonpath='{.status.phase}'
# Expected: Deployed
```

**Troubleshooting**:
- If pods are Pending: Check Kind cluster resources (`kubectl top nodes`)
- If CrashLoopBackOff: Check logs (`kubectl logs -n kubevirt <pod-name>`)
- If useEmulation not set: VMs will fail to start (no KVM in Kind)

---

## Phase 3: Host NixOS VM Image

### Option A: HTTP Server in Cluster (Recommended for Local Dev)

```bash
# Create nginx deployment to serve qcow2 images
cat > /tmp/nixos-image-server.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nixos-images
  namespace: default
data:
  # Base64-encoded qcow2 image (for small images <1MB)
  # For larger images, use PVC with hostPath or external HTTP server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nixos-image-server
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nixos-image-server
  template:
    metadata:
      labels:
        app: nixos-image-server
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: images
          mountPath: /usr/share/nginx/html
      volumes:
      - name: images
        hostPath:
          path: /home/vpittamp/stacks/nixos-images  # Kind hostPath
          type: Directory
---
apiVersion: v1
kind: Service
metadata:
  name: nixos-image-server
  namespace: default
spec:
  selector:
    app: nixos-image-server
  ports:
  - port: 80
    targetPort: 80
EOF

kubectl apply -f /tmp/nixos-image-server.yaml

# Verify service
kubectl get svc nixos-image-server
# Note the ClusterIP for DataVolume source URL
```

### Option B: External HTTP Server (For Testing)

```bash
# Simple Python HTTP server (for quick testing)
cd /home/vpittamp/stacks/nixos-images
python3 -m http.server 8000

# Access from Kind cluster (use host.docker.internal on macOS/Windows)
# On Linux, use host network IP
```

---

## Phase 4: Create and Start NixOS VM

### Step 4.1: Create DataVolume for Image Import

Create `cdk8s/charts/apps/nixos-datavolume-chart.ts`:

```typescript
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { DataVolume } from '../../imports/cdi.kubevirt.io';
import { addSyncWave } from '../../lib/argocd-sync-builders';

export interface NixOsDataVolumeChartProps extends ChartProps {
  dataVolumeName: string;
  imageUrl: string;
  storageSize?: string;
}

export class NixOsDataVolumeChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsDataVolumeChartProps) {
    super(scope, id, props);

    const dv = new DataVolume(this, 'datavolume', {
      metadata: {
        name: props.dataVolumeName,
        namespace: 'default',
      },
      spec: {
        source: {
          http: {
            url: props.imageUrl,
          },
        },
        pvc: {
          accessModes: ['ReadWriteOnce'],
          resources: {
            requests: {
              storage: props.storageSize || '20Gi',
            },
          },
        },
      },
    });
    addSyncWave(dv, 0);
  }
}
```

### Step 4.2: Create VirtualMachine Chart

Create `cdk8s/charts/apps/nixos-vm-chart.ts`:

```typescript
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import { VirtualMachine } from '../../imports/kubevirt.io';
import { addSyncWave } from '../../lib/argocd-sync-builders';

export interface NixOsVmChartProps extends ChartProps {
  vmName: string;
  dataVolumeName: string;
  cpuCores?: number;
  memory?: string;
  cloudInitUserData?: string;
}

export class NixOsVmChart extends Chart {
  constructor(scope: Construct, id: string, props: NixOsVmChartProps) {
    super(scope, id, props);

    const vm = new VirtualMachine(this, 'vm', {
      metadata: {
        name: props.vmName,
        namespace: 'default',
      },
      spec: {
        runStrategy: 'Manual',  // Explicit start/stop
        template: {
          spec: {
            domain: {
              resources: {
                requests: {
                  memory: props.memory || '4Gi',
                  cpu: `${props.cpuCores || 2}`,
                },
              },
              devices: {
                disks: [
                  { name: 'rootdisk', disk: { bus: 'virtio' } },
                  { name: 'cloudinitdisk', disk: { bus: 'virtio' } },
                ],
              },
            },
            networks: [{ name: 'default', pod: {} }],
            volumes: [
              {
                name: 'rootdisk',
                dataVolume: { name: props.dataVolumeName },
              },
              {
                name: 'cloudinitdisk',
                cloudInitNoCloud: {
                  userData: props.cloudInitUserData || `#cloud-config
hostname: ${props.vmName}
users:
  - name: vpittamp
    sudo: ALL=(ALL) NOPASSWD:ALL
`,
                },
              },
            ],
          },
        },
      },
    });
    addSyncWave(vm, 10);
  }
}
```

### Step 4.3: Add VM Application to Config

```typescript
// In cdk8s/config/applications.ts
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
    },
  },
  argocd: {
    syncWave: '10',
    syncPolicy: {
      automated: { prune: true, selfHeal: true },
    },
  },
},
```

### Step 4.4: Deploy VM

```bash
# Synthesize and deploy
cd /home/vpittamp/stacks/cdk8s
npx ts-node main-v2.ts
source ../deployment/scripts/cluster-menu.sh
cluster-update

# Check DataVolume import progress
kubectl get datavolume nixos-dev-datavolume
# Wait for Status: Succeeded

# Check VirtualMachine created
kubectl get vm nixos-dev-vm
# Expected: Status: Stopped (runStrategy: Manual)

# Start VM
virtctl start nixos-dev-vm

# Watch VM boot
kubectl get vmi nixos-dev-vm -w
# Expected: Pending → Scheduling → Scheduled → Running

# Access VM console
virtctl console nixos-dev-vm
# Expected: NixOS login prompt

# Login with vpittamp user (cloud-init SSH keys)
# Password not set, use SSH keys from base.nix
```

---

## Phase 5: Verify and Test

### Verification Checklist

```bash
# 1. KubeVirt operator healthy
kubectl get pods -n kubevirt
kubectl get kubevirt -n kubevirt kubevirt -o yaml

# 2. DataVolume import succeeded
kubectl get datavolume -A
kubectl describe datavolume nixos-dev-datavolume

# 3. VirtualMachine created
kubectl get vm -A
kubectl describe vm nixos-dev-vm

# 4. VirtualMachineInstance running
kubectl get vmi -A
kubectl get vmi nixos-dev-vm -o jsonpath='{.status.interfaces[0].ipAddress}'

# 5. Console access works
virtctl console nixos-dev-vm

# 6. SSH access (if VM has network)
VM_IP=$(kubectl get vmi nixos-dev-vm -o jsonpath='{.status.interfaces[0].ipAddress}')
ssh vpittamp@$VM_IP

# 7. Cloud-init executed
virtctl console nixos-dev-vm
# Inside VM:
cloud-init status
# Expected: status: done

# 8. QEMU guest agent running
systemctl status qemu-guest-agent
```

### Common Issues

**DataVolume stuck in ImportInProgress**:
- Check CDI importer pod logs: `kubectl logs -n cdi <importer-pod>`
- Verify image URL is accessible: `kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -I <image-url>`
- Increase timeout if large image

**VM fails to start**:
- Check `useEmulation: true` in KubeVirt CR
- Verify DataVolume is Succeeded
- Check virt-handler logs: `kubectl logs -n kubevirt -l kubevirt.io=virt-handler`

**Cannot access VM console**:
- Verify VMI is Running: `kubectl get vmi`
- Check virt-launcher pod: `kubectl get pods -l kubevirt.io/domain=nixos-dev-vm`
- Try `virtctl vnc nixos-dev-vm` for graphical console

---

## Next Steps

1. **Multiple VMs**: Create additional NixOS configurations in `/etc/nixos/configurations/` (e.g., `vm-k8s-worker.nix`)
2. **PVC Retention**: Experiment with `dataVolumeTemplates` (ephemeral) vs. separate DataVolumes (persistent)
3. **Cloud-Init Secrets**: Use ExternalSecrets to inject SSH keys from Azure Key Vault
4. **Production Deployment**: Deploy to multi-node cluster with KVM for better performance
5. **VM Snapshots**: Explore VirtualMachineSnapshot CRD for backup/restore

---

## Reference Commands

```bash
# VM Lifecycle
virtctl start <vm-name>
virtctl stop <vm-name>
virtctl restart <vm-name>
virtctl pause <vm-name>
virtctl unpause <vm-name>

# Console Access
virtctl console <vm-name>  # Serial console
virtctl vnc <vm-name>      # Graphical console (if enabled)

# VM Information
kubectl get vm,vmi -A
kubectl describe vm <vm-name>
kubectl get vmi <vm-name> -o yaml

# DataVolume Management
kubectl get datavolume -A
kubectl describe datavolume <dv-name>

# Troubleshooting
kubectl logs -n kubevirt -l kubevirt.io=virt-operator
kubectl logs -n kubevirt -l kubevirt.io=virt-controller
kubectl logs -n cdi -l app=cdi-operator
```

---

## Additional Resources

- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [CDI DataVolumes Documentation](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/datavolumes.md)
- [NixOS Generators](https://github.com/nix-community/nixos-generators)
- [virtctl Reference](https://kubevirt.io/user-guide/operations/virtctl_client_tool/)
- [Cloud-Init Examples](https://cloudinit.readthedocs.io/en/latest/reference/examples.html)
