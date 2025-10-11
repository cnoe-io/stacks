# KubeVirt Documentation

> **Comprehensive installation and operational guide for KubeVirt**
> Documentation scraped from: https://kubevirt.io/
> Latest KubeVirt version: v1.6.2
> Last updated: 2025-10-10

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
   - [Prerequisites](#prerequisites)
   - [Standard Installation](#standard-installation)
   - [Installation on Minikube](#installation-on-minikube)
   - [Installation on Kind](#installation-on-kind)
   - [Installation on Cloud Providers](#installation-on-cloud-providers)
4. [Getting Started](#getting-started)
   - [Installing virtctl](#installing-virtctl)
   - [Creating Your First VM](#creating-your-first-vm)
   - [VM Lifecycle Management](#vm-lifecycle-management)
5. [Operations](#operations)
   - [Updating KubeVirt](#updating-kubevirt)
   - [Deletion Procedures](#deletion-procedures)
   - [Live Migration](#live-migration)
6. [Advanced Topics](#advanced-topics)
   - [Containerized Data Importer (CDI)](#containerized-data-importer-cdi)
   - [Storage and Volumes](#storage-and-volumes)
   - [Networking](#networking)
7. [Resources](#resources)

---

## Overview

**KubeVirt** is a virtual machine management add-on for Kubernetes that extends Kubernetes by adding virtualization resource types through Custom Resource Definitions (CRDs).

### What is KubeVirt?

KubeVirt enables you to:
- Create, schedule, launch, stop, and delete virtual machines declaratively
- Integrate VMs directly into the Kubernetes API
- Manage VMs alongside containerized workloads using familiar Kubernetes tools

### Key Features

- **Kubernetes-native:** Uses CRDs and controllers for VM management
- **Declarative management:** Define VMs as Kubernetes resources
- **Integration:** Works with existing Kubernetes tooling (kubectl, ArgoCD, etc.)
- **Migration:** Supports live migration of VMs between nodes
- **Storage:** Integrates with Kubernetes storage classes and PVCs

### Project Information

- **GitHub:** https://github.com/kubevirt/kubevirt
- **Website:** https://kubevirt.io
- **Latest Release:** v1.6.2
- **License:** Apache License, Version 2.0
- **Community:**
  - Slack: #virtualization on kubernetes.slack.com
  - Google Group: kubevirt-dev
  - Twitter: @kubevirt

---

## Architecture

### Design Principles

**The KubeVirt Razor:**
> "If something is useful for Pods, it should not be implemented only for VMs"

KubeVirt follows a service-oriented architecture built on Kubernetes, using a choreography pattern for managing virtual machines.

### Core Design Concepts

1. **Kubernetes-native integration:** Leverages Kubernetes mechanisms for scheduling, networking, and storage
2. **Compatibility:** Maintains compatibility with existing Kubernetes workloads
3. **Modularity:** Emphasizes modularity, reusability, and seamless ecosystem integration
4. **Security parity:** Maintains security parity with native Kubernetes workloads

### Core Components

#### 1. Custom Resource Definitions (CRDs)

- **VirtualMachineInstance (VMI):** Basic ephemeral building block
  - Represents a running VM
  - Ephemeral (like a Pod)
  - Direct execution resource

- **VirtualMachine (VM):** Management wrapper providing:
  - API stability
  - Start/stop/restart capabilities
  - Offline configuration changes
  - State management (ensures VM state matches desired configuration)

#### 2. Controllers and Agents

- **virt-controller:** Cluster-wide logic and VM lifecycle management
- **virt-handler:** Node-specific daemon handling VM operations on each node
- **libvirtd:** Underlying virtualization layer

### Interaction Model

```
User → Kubernetes API → KubeVirt Controllers → virt-handler → libvirtd → VM
```

- Runs on top of Kubernetes cluster
- Uses Kubernetes API server to define and manage VM resources
- Integrates with Kubernetes scheduling, networking, and storage subsystems

---

## Installation

### Prerequisites

#### Kubernetes Cluster Requirements

- **Kubernetes version:** Based on one of the latest three releases
- **API server configuration:** `--allow-privileged=true`
- **kubectl client:** Installed and matching Kubernetes version
- **Container runtimes:** containerd or crio (with runv)

#### Supported Platforms

- Kubernetes
- OKD (OpenShift)
- k3OS

#### Hardware Prerequisites

- **Recommended:** Hardware with virtualization support (Intel VT-x or AMD-V)
- **Validation:** Use `virt-host-validate` to check hardware support
- **SELinux nodes:** Require Container-selinux version 2.170.0+ (recommended)
- **Disk space:** At least 30 GiB for labs and VM images

#### Software Emulation

If hardware virtualization is not available, KubeVirt can run with software emulation by setting `useEmulation: true` in the KubeVirt CR.

---

### Standard Installation

#### Step 1: Get Latest Release

```bash
export RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo $RELEASE
```

#### Step 2: Deploy KubeVirt Operator

```bash
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
```

The operator will be deployed in the `kubevirt` namespace.

#### Step 3: Create KubeVirt Deployment

```bash
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-cr.yaml
```

#### Step 4: Verify Installation

```bash
# Wait for KubeVirt to be available
kubectl -n kubevirt wait kv kubevirt --for condition=Available

# Check deployment status
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"

# List all components
kubectl get all -n kubevirt
```

Expected output should show `Deployed` status and all pods running.

#### Optional: Enable Software Emulation

If you don't have nested virtualization support:

```bash
kubectl -n kubevirt patch kubevirt kubevirt --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

---

### Installation on Minikube

#### Prerequisites

- Install kubectl (matching Kubernetes version)
- Install Minikube

#### Step 1: Start Minikube Cluster

```bash
# Single node cluster with Flannel CNI
minikube start --cni=flannel

# Optional: Multi-node setup
minikube start --nodes=2 --cni=flannel
```

#### Step 2: Deploy KubeVirt

**Method 1: Using Minikube Addon (Currently Broken)**

```bash
minikube addons enable kubevirt
```

**Method 2: Manual Deployment (Recommended)**

```bash
# Get latest version
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)

# Deploy operator
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml"

# Enable emulation if needed (for non-nested virtualization)
kubectl -n kubevirt patch kubevirt kubevirt --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

# Deploy KubeVirt custom resources
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml"
```

#### Step 3: Verify Installation

```bash
# Check KubeVirt status
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"

# Check all components
kubectl get all -n kubevirt
```

---

### Installation on Kind

#### Prerequisites

1. Install kubectl (matching Kubernetes version)
2. Install Kind

#### Step 1: Create Kind Cluster

```bash
kind create cluster
```

#### Step 2: Deploy KubeVirt

```bash
# Get latest KubeVirt version
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)

# Deploy KubeVirt operator
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml"

# Enable emulation (required for Kind)
kubectl -n kubevirt patch kubevirt kubevirt --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

# Deploy KubeVirt custom resources
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml"
```

#### Step 3: Verify Installation

```bash
# Check KubeVirt deployment status
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"

# Check all KubeVirt components
kubectl get all -n kubevirt
```

---

### Installation on Cloud Providers

#### Supported Cloud Providers

- AWS (Amazon Web Services)
- GCP (Google Cloud Platform)
- Azure (Microsoft Azure)
- Other Kubernetes-compatible cloud platforms

#### Prerequisites

- Kubernetes cluster on cloud provider (refer to Kubernetes.io "Turnkey Cloud Solutions" guide)
- kubectl client matching Kubernetes version
- Be aware of cloud infrastructure costs
- Ensure at least 30 GiB disk space for labs

#### Deployment Steps

```bash
# Step 1: Deploy KubeVirt operator
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml"

# Step 2: If running on a VM (nested virtualization), enable emulation
kubectl -n kubevirt patch kubevirt kubevirt --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

# Step 3: Deploy KubeVirt custom resources
kubectl create -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml"
```

#### Verification

```bash
# Check deployment status
kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.phase}"

# Check all components
kubectl get all -n kubevirt
```

---

## Getting Started

### Installing virtctl

`virtctl` is the command-line utility for interacting with KubeVirt VMs. It provides convenient commands for VM management.

#### Installation Steps

```bash
# Retrieve KubeVirt version
VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.observedKubeVirtVersion}")

# Determine architecture
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/')

# Download virtctl
curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH}

# Make executable and install
chmod +x virtctl
sudo install virtctl /usr/local/bin

# Verify installation
virtctl version
```

#### Alternative: kubectl virt Plugin

You can also use `kubectl virt` as an alternative to `virtctl`:

```bash
kubectl virt version
```

---

### Creating Your First VM

#### Step 1: Download VM Manifest

```bash
wget https://kubevirt.io/labs/manifests/vm.yaml
less vm.yaml
```

Example VM manifest structure:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: testvm
spec:
  runStrategy: Manual
  template:
    metadata:
      labels:
        kubevirt.io/vm: testvm
    spec:
      domain:
        devices:
          disks:
          - name: containerdisk
            disk:
              bus: virtio
          - name: cloudinitdisk
            disk:
              bus: virtio
        resources:
          requests:
            memory: 1024M
      volumes:
      - name: containerdisk
        containerDisk:
          image: quay.io/kubevirt/cirros-container-disk-demo
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            password: password
            chpasswd: { expire: False }
```

#### Step 2: Create the Virtual Machine

```bash
kubectl apply -f https://kubevirt.io/labs/manifests/vm.yaml
```

#### Step 3: List VMs

```bash
# List VMs
kubectl get vms

# List VMIs (running instances)
kubectl get vmis
```

---

### VM Lifecycle Management

#### Starting a VM

**Method 1: Using virtctl**

```bash
virtctl start testvm
```

**Method 2: Using kubectl virt**

```bash
kubectl virt start testvm
```

**Method 3: Patching the VM (declarative)**

```bash
kubectl patch virtualmachine testvm --type merge -p '{"spec":{"runStrategy": "Always"}}'
```

#### Accessing VM Console

```bash
# Connect to console
virtctl console testvm

# Disconnect from console
# Press: Ctrl + ]
```

#### Stopping a VM

```bash
virtctl stop testvm
```

#### Restarting a VM

```bash
virtctl restart testvm
```

#### Deleting a VM

```bash
kubectl delete vm testvm
```

#### Checking VM Status

```bash
# Get VM details
kubectl get vm testvm -o yaml

# Get VMI details (running instance)
kubectl get vmi testvm -o yaml

# Get VM events
kubectl describe vm testvm
```

---

## Operations

### Updating KubeVirt

#### Update Strategy

- **Zero-downtime rolling updates** supported from `v0.17.0` onwards
- **Only update from N-1 to N release** (one version at a time)
- Existing VirtualMachineInstances remain untouched by default

#### Update Methods

**Method 1: Change imageTag in KubeVirt CR**

```bash
kubectl patch kv kubevirt -n kubevirt --type=json \
  -p '[{ "op": "add", "path": "/spec/imageTag", "value": "v1.6.2" }]'
```

**Method 2: Update KubeVirt Operator (Recommended)**

```bash
# Set target version
export KUBEVIRT_VERSION=v1.6.2

# Update operator
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
```

#### Updating KubeVirt Workloads (Opt-in, v0.39.0+)

Two workload update strategies:

**1. LiveMigrate (Recommended)**
- Migrates VMIs to new pods with updated components
- Zero downtime

**2. Evict**
- Shutdown VMI pods
- Allows controlled replacement

Configure in KubeVirt CR:

```yaml
spec:
  workloadUpdateStrategy:
    workloadUpdateMethods:
    - LiveMigrate
```

#### Verification After Update

```bash
# Check operator version
kubectl get deployment.apps virt-operator -n kubevirt -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check all pods are running
kubectl get pods -n kubevirt

# Verify VMs are still running
kubectl get vmis
```

---

### Deletion Procedures

#### Step 1: Delete KubeVirt Custom Resource

```bash
kubectl delete kubevirt kubevirt -n kubevirt
```

#### Step 2: Delete KubeVirt Operator

```bash
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl delete -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml
```

#### Step 3: Manual Cleanup (if needed)

If resources have finalizers preventing deletion:

```bash
# Remove finalizers from apiservices
kubectl patch apiservice v1.subresources.kubevirt.io -p '{"metadata":{"finalizers":null}}' --type=merge

# Delete webhook configurations
kubectl delete validatingwebhookconfiguration virt-operator-validator
kubectl delete mutatingwebhookconfiguration virt-operator-mutator

# Delete namespace
kubectl delete namespace kubevirt
```

---

### Live Migration

Live migration allows you to move virtual machines running on one cluster node to another cluster node without shutting down the guest OS or applications.

#### Prerequisites

- Kubernetes cluster with **two or more nodes**
- CNI plugin installed (Flannel recommended)
- Nested or emulated virtualization enabled
- KubeVirt installed

#### Step 1: Enable Live Migration Feature

Create a ConfigMap in the `kubevirt` namespace:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubevirt-config
  namespace: kubevirt
data:
  feature-gates: "LiveMigration"
```

Apply the configuration:

```bash
kubectl apply -f kubevirt-config.yaml
```

#### Step 2: Create and Start a VM

```bash
# Apply VM manifest
kubectl apply -f https://kubevirt.io/labs/manifests/vm.yaml

# Start the VM
virtctl start testvm
```

#### Step 3: Check VM Node Placement

```bash
# Find which node the VM is running on
kubectl get vmi testvm -o wide
```

#### Step 4: Migrate the VM

```bash
# Trigger migration
virtctl migrate testvm

# Monitor migration status
kubectl get virtualmachineinstancemigration -w
```

#### Step 5: Verify Migration

```bash
# Check new node placement
kubectl get vmi testvm -o wide

# Original pod should be in "Completed" state
kubectl get pods -l kubevirt.io/vm=testvm

# New pod should be running on a different node
```

#### Migration Behavior

- Services continue running without interruption
- No downtime for applications
- Original VMI pod enters "Completed" state
- New VMI pod starts on different node
- Network connectivity maintained

#### Exposing VM Services

To test migration with services:

```bash
# Expose VM as a service
virtctl expose vmi testvm --name=testvm-service --port=80

# Access service during migration to verify continuity
```

---

## Advanced Topics

### Containerized Data Importer (CDI)

CDI simplifies importing virtual machine disk images into Kubernetes. It provides a declarative way to build and import Virtual Machine Disks into PVCs.

#### What is CDI?

- **Purpose:** Import VM images from various sources (HTTP, S3, registry, etc.)
- **Abstraction:** DataVolumes abstract PersistentVolumeClaims
- **Integration:** Seamlessly integrates with KubeVirt

#### Installing CDI

```bash
# Get latest CDI version
export VERSION=$(basename $(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest))

# Deploy CDI operator
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml

# Deploy CDI custom resource
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
```

#### Verify CDI Installation

```bash
# Check CDI CustomResource status
kubectl get cdi -A

# Check CDI pods
kubectl get pods -n cdi
```

#### Creating a DataVolume

Example DataVolume manifest:

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: fedora-dv
spec:
  source:
    http:
      url: "https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/Fedora-Cloud-Base-38-1.6.x86_64.qcow2"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
```

Apply the DataVolume:

```bash
kubectl apply -f fedora-dv.yaml
```

#### Monitor Import Progress

```bash
# Watch DataVolume status
kubectl get dv fedora-dv -w

# Check importer pod logs
kubectl logs -f $(kubectl get pods -l cdi.kubevirt.io/dataVolume=fedora-dv -o name)
```

#### Using DataVolume with VM

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: fedora-vm
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/vm: fedora-vm
    spec:
      domain:
        devices:
          disks:
          - name: datavolumedisk
            disk:
              bus: virtio
        resources:
          requests:
            memory: 2Gi
      volumes:
      - name: datavolumedisk
        dataVolume:
          name: fedora-dv
```

---

### Storage and Volumes

KubeVirt supports multiple volume types for VM storage.

#### Volume Types

1. **containerDisk**
   - Ephemeral disk from container image
   - Non-persistent (data lost on VM deletion)
   - Good for testing and stateless workloads

2. **persistentVolumeClaim**
   - Persistent storage using Kubernetes PVCs
   - Data survives VM restarts and deletions
   - Backed by storage classes

3. **dataVolume**
   - High-level abstraction over PVCs
   - Managed by CDI
   - Supports importing from various sources

4. **cloudInitNoCloud**
   - For cloud-init configuration
   - User data and metadata injection

5. **emptyDir**
   - Ephemeral storage
   - Shared between containers in the same pod

#### Example: Persistent VM with PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-vm-disk
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: standard
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: my-persistent-vm
spec:
  running: false
  template:
    spec:
      domain:
        devices:
          disks:
          - name: disk0
            disk:
              bus: virtio
        resources:
          requests:
            memory: 2Gi
      volumes:
      - name: disk0
        persistentVolumeClaim:
          claimName: my-vm-disk
```

---

### Networking

KubeVirt VMs integrate with Kubernetes networking.

#### Default Networking

- VMs use pod networking by default
- Each VMI gets an IP from the pod network
- Services can expose VMs

#### Exposing VMs

**Using virtctl:**

```bash
# Expose VM with NodePort
virtctl expose vmi testvm --name=testvm-http --port=80 --type=NodePort

# Expose with LoadBalancer (if available)
virtctl expose vmi testvm --name=testvm-lb --port=80 --type=LoadBalancer

# Expose with ClusterIP (default)
virtctl expose vmi testvm --name=testvm-svc --port=80
```

**Using kubectl:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: testvm-service
spec:
  selector:
    kubevirt.io/vm: testvm
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  type: ClusterIP
```

#### DNS Records

VMs are accessible via Kubernetes DNS:

- From same namespace: `http://testvm-service`
- From other namespace: `http://testvm-service.default.svc.cluster.local`

#### Advanced Networking

For advanced networking scenarios, KubeVirt supports:
- Multus for multiple network interfaces
- SR-IOV for high-performance networking
- Bridge networking
- Custom CNI plugins

---

## Resources

### Official Resources

- **Website:** https://kubevirt.io
- **User Guide:** https://kubevirt.io/user-guide
- **GitHub:** https://github.com/kubevirt/kubevirt
- **API Reference:** https://kubevirt.io/api-reference/

### Quickstart Guides

- **Minikube:** https://kubevirt.io/quickstart_minikube/
- **Kind:** https://kubevirt.io/quickstart_kind/
- **Cloud Providers:** https://kubevirt.io/quickstart_cloud/

### Interactive Labs

- **Killercoda KubeVirt 101:** https://killercoda.com/kubevirt/scenario/kubevirt-101
- **Lab 1 - Use KubeVirt:** https://kubevirt.io/labs/kubernetes/lab1.html
- **Lab 2 - CDI:** https://kubevirt.io/labs/kubernetes/lab2.html
- **Lab 3 - Upgrades:** https://kubevirt.io/labs/kubernetes/lab3.html
- **Lab 4 - Live Migration:** https://kubevirt.io/labs/kubernetes/migration.html

### Community

- **Slack:** #virtualization on kubernetes.slack.com
- **Google Group:** kubevirt-dev@googlegroups.com
- **GitHub Issues:** https://github.com/kubevirt/kubevirt/issues
- **Twitter:** @kubevirt

### Related Projects

- **CDI (Containerized Data Importer):** https://github.com/kubevirt/containerized-data-importer
- **CDI Documentation:** https://kubevirt.io/user-guide/operations/containerized_data_importer/
- **Kubernetes:** https://kubernetes.io
- **Libvirt:** https://libvirt.org

---

## Integration with Your Project

### For CDK8s/GitOps Projects

To integrate KubeVirt into your CDK8s-based GitOps repository:

#### Step 1: Import KubeVirt CRDs

```bash
cd cdk8s
cdk8s import kubevirt.io
```

#### Step 2: Create KubeVirt Chart

```typescript
// cdk8s/charts/infra/kubevirt-chart.ts
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';

export class KubeVirtChart extends Chart {
  constructor(scope: Construct, id: string, props?: ChartProps) {
    super(scope, id, props);

    // KubeVirt resources will be defined here
    // You can reference the operator and CR YAMLs
  }
}
```

#### Step 3: Add to Application Configuration

```typescript
// cdk8s/config/applications.ts
{
  name: 'kubevirt',
  namespace: 'kubevirt',
  chart: {
    type: 'KubeVirtChart',
    props: {}
  },
  argocd: {
    syncWave: '-100',
    labels: { 'app.kubernetes.io/name': 'kubevirt' },
    syncPolicy: { automated: { prune: true, selfHeal: true } }
  }
}
```

#### Step 4: Synthesize and Deploy

```bash
cd cdk8s
npx ts-node main-v2.ts
idpbuilder create --package dist/kubevirt
```

### ArgoCD Integration

For ArgoCD-based deployment, you can create an Application manifest:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubevirt
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/kubevirt/kubevirt
    targetRevision: v1.6.2
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: kubevirt
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### VM Examples for Your Platform

```yaml
# Example: Development VM
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: dev-workstation
  namespace: dev-vcluster
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: dev-workstation
    spec:
      domain:
        devices:
          disks:
          - name: rootdisk
            disk:
              bus: virtio
          - name: cloudinit
            disk:
              bus: virtio
        resources:
          requests:
            memory: 4Gi
            cpu: 2
      volumes:
      - name: rootdisk
        dataVolume:
          name: ubuntu-22-04-dv
      - name: cloudinit
        cloudInitNoCloud:
          userData: |
            #cloud-config
            hostname: dev-workstation
            users:
            - name: developer
              sudo: ALL=(ALL) NOPASSWD:ALL
              ssh_authorized_keys:
              - ssh-rsa AAAA...
```

---

## Troubleshooting

### Common Issues

#### Issue: VMs not starting

**Check:**
```bash
# Check VM events
kubectl describe vm <vm-name>

# Check VMI events
kubectl describe vmi <vm-name>

# Check virt-launcher pod logs
kubectl logs -l kubevirt.io/vm=<vm-name>
```

#### Issue: Hardware virtualization not available

**Solution:**
Enable software emulation:
```bash
kubectl -n kubevirt patch kubevirt kubevirt --type=merge \
  --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
```

#### Issue: CDI import failing

**Check:**
```bash
# Check DataVolume status
kubectl describe dv <datavolume-name>

# Check importer pod logs
kubectl logs -l cdi.kubevirt.io/dataVolume=<datavolume-name>

# Check CDI controller logs
kubectl logs -n cdi -l cdi.kubevirt.io/name=cdi-controller
```

#### Issue: Live migration not working

**Check:**
```bash
# Ensure LiveMigration feature gate is enabled
kubectl get cm kubevirt-config -n kubevirt -o yaml

# Check migration status
kubectl get virtualmachineinstancemigration

# Check virt-handler logs on both nodes
kubectl logs -n kubevirt -l kubevirt.io=virt-handler
```

### Getting Help

- **GitHub Issues:** https://github.com/kubevirt/kubevirt/issues
- **Slack:** #virtualization channel on kubernetes.slack.com
- **Mailing List:** https://groups.google.com/forum/#!forum/kubevirt-dev

---

**End of Documentation**
