# Hetzner Cloud Talos Cluster Setup Reference

This document provides step-by-step commands to reproduce the Talos Kubernetes cluster on Hetzner Cloud.

## Cluster Architecture

| Node | Type | vCPU | RAM | Disk | Role | Monthly Cost |
|------|------|------|-----|------|------|--------------|
| talos-cp-1 | CPX21 | 3 | 4GB | 80GB | control-plane | $8.50 |
| talos-cp-2 | CPX21 | 3 | 4GB | 80GB | control-plane | $8.50 |
| talos-cp-3 | CPX21 | 3 | 4GB | 80GB | control-plane | $8.50 |
| talos-worker-1 | CCX43 | 16 | 64GB | 360GB | worker | $100.00 |
| talos-worker-2 | CCX33 | 8 | 32GB | 240GB | worker | $50.00 |
| **Total** | | | | | | **~$175/mo** |

## Prerequisites

### Required Tools

```bash
# Verify tool versions
talosctl version --client    # >= 1.11.0
kubectl version --client     # >= 1.32.0
hcloud version               # any recent version
helm version                 # >= 3.x
```

### Hetzner Cloud Authentication

```bash
# Set up hcloud context
hcloud context create talos-cluster
# Enter your Hetzner API token when prompted

# Verify authentication
hcloud context active
```

---

## Phase 1: Network Infrastructure

### Create Private Network

```bash
# Create private network (10.0.0.0/16)
hcloud network create --name talos-cluster-net --ip-range 10.0.0.0/16

# Add subnet for nodes (10.0.1.0/24 in us-east zone)
hcloud network add-subnet talos-cluster-net \
  --type cloud \
  --network-zone us-east \
  --ip-range 10.0.1.0/24
```

### Create Firewall

```bash
# Create firewall
hcloud firewall create --name talos-cluster-fw

# Allow Tailscale UDP (for future Tailscale operator)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol udp \
  --port 41641 \
  --source-ips 0.0.0.0/0 \
  --source-ips ::/0

# Allow ICMP (ping)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol icmp \
  --source-ips 0.0.0.0/0 \
  --source-ips ::/0

# Allow all TCP within private network
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port any \
  --source-ips 10.0.0.0/16

# Allow all UDP within private network
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol udp \
  --port any \
  --source-ips 10.0.0.0/16

# TEMPORARY: Allow Talos API from operator IP (replace with your IP)
OPERATOR_IP=$(curl -s ifconfig.me)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 50000 \
  --source-ips ${OPERATOR_IP}/32

# TEMPORARY: Allow Kubernetes API from operator IP
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 6443 \
  --source-ips ${OPERATOR_IP}/32
```

---

## Phase 2: Talos Configuration

### Generate Cluster Secrets (One-Time)

```bash
# Generate secrets (store securely with git-crypt)
talosctl gen secrets --output-file secrets/secrets.yaml
```

### Generate Machine Configs

```bash
# Generate configs with patches
talosctl gen config talos-cluster https://10.0.1.1:6443 \
  --kubernetes-version 1.32.0 \
  --with-secrets secrets/secrets.yaml \
  --config-patch @patches/common.yaml \
  --config-patch-control-plane @patches/controlplane/all.yaml \
  --config-patch-worker @patches/worker/all.yaml \
  --output generated/

# Validate configs
talosctl validate --config generated/controlplane.yaml --mode cloud
talosctl validate --config generated/worker.yaml --mode cloud
```

---

## Phase 3: Control Plane Nodes

### Create Control Plane Servers (Stopped)

```bash
# Create CP1 (stopped - we'll attach ISO before starting)
hcloud server create \
  --name talos-cp-1 \
  --type cpx21 \
  --image ubuntu-24.04 \
  --location ash \
  --network talos-cluster-net \
  --firewall talos-cluster-fw \
  --label role=control-plane \
  --label cluster=talos-cluster \
  --start-after-create=false

# Create CP2
hcloud server create \
  --name talos-cp-2 \
  --type cpx21 \
  --image ubuntu-24.04 \
  --location ash \
  --network talos-cluster-net \
  --firewall talos-cluster-fw \
  --label role=control-plane \
  --label cluster=talos-cluster \
  --start-after-create=false

# Create CP3
hcloud server create \
  --name talos-cp-3 \
  --type cpx21 \
  --image ubuntu-24.04 \
  --location ash \
  --network talos-cluster-net \
  --firewall talos-cluster-fw \
  --label role=control-plane \
  --label cluster=talos-cluster \
  --start-after-create=false
```

### Attach Talos ISO and Start

```bash
# Hetzner public Talos ISO ID for amd64
TALOS_ISO_ID=122630

# Attach ISO to all CP nodes
hcloud server attach-iso talos-cp-1 ${TALOS_ISO_ID}
hcloud server attach-iso talos-cp-2 ${TALOS_ISO_ID}
hcloud server attach-iso talos-cp-3 ${TALOS_ISO_ID}

# Start all CP nodes (they boot into Talos maintenance mode)
hcloud server poweron talos-cp-1
hcloud server poweron talos-cp-2
hcloud server poweron talos-cp-3

# Wait for nodes to boot (~30 seconds)
sleep 30
```

### Get Public IPs

```bash
# Record public IPs for each node
CP1_IP=$(hcloud server describe talos-cp-1 -o format='{{.PublicNet.IPv4.IP}}')
CP2_IP=$(hcloud server describe talos-cp-2 -o format='{{.PublicNet.IPv4.IP}}')
CP3_IP=$(hcloud server describe talos-cp-3 -o format='{{.PublicNet.IPv4.IP}}')

echo "CP1: ${CP1_IP}"
echo "CP2: ${CP2_IP}"
echo "CP3: ${CP3_IP}"
```

### Apply Talos Config to Control Plane

```bash
# Apply config to each CP node (via public IP, --insecure for maintenance mode)
talosctl apply-config --insecure \
  --endpoints ${CP1_IP} \
  --nodes ${CP1_IP} \
  --file generated/controlplane.yaml

talosctl apply-config --insecure \
  --endpoints ${CP2_IP} \
  --nodes ${CP2_IP} \
  --file generated/controlplane.yaml

talosctl apply-config --insecure \
  --endpoints ${CP3_IP} \
  --nodes ${CP3_IP} \
  --file generated/controlplane.yaml
```

### Detach ISO and Reset to Boot from Disk

```bash
# Detach ISO from all CP nodes
hcloud server detach-iso talos-cp-1
hcloud server detach-iso talos-cp-2
hcloud server detach-iso talos-cp-3

# Reset servers to boot from disk
hcloud server reset talos-cp-1
hcloud server reset talos-cp-2
hcloud server reset talos-cp-3

# Wait for nodes to boot (~60 seconds)
sleep 60
```

### Bootstrap the Cluster

```bash
# Bootstrap from first control plane node
talosctl bootstrap \
  --endpoints ${CP1_IP} \
  --nodes ${CP1_IP} \
  --talosconfig generated/talosconfig

# Wait for etcd to form quorum
sleep 30

# Verify etcd members (should show 3 members)
TALOSCONFIG=generated/talosconfig talosctl etcd members \
  --endpoints ${CP1_IP} \
  --nodes ${CP1_IP}
```

### Get Kubeconfig

```bash
# Generate kubeconfig
talosctl kubeconfig \
  --endpoints ${CP1_IP} \
  --nodes ${CP1_IP} \
  --talosconfig generated/talosconfig \
  generated/kubeconfig

# Verify nodes (will show NotReady - no CNI yet)
kubectl --kubeconfig generated/kubeconfig get nodes
```

---

## Phase 4: Deploy Cilium CNI

### Install Cilium with Talos-Compatible Settings

**CRITICAL**: Talos requires specific security context capabilities for Cilium.

```bash
# Add Cilium Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium with Talos-specific settings
helm install cilium cilium/cilium --version 1.16.4 \
  --namespace kube-system \
  --kubeconfig generated/kubeconfig \
  --set cluster.name=talos-cluster \
  --set cluster.id=1 \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

### Verify Cilium and Nodes

```bash
# Wait for Cilium pods
kubectl --kubeconfig generated/kubeconfig -n kube-system get pods -l app.kubernetes.io/part-of=cilium -w

# Verify nodes are now Ready
kubectl --kubeconfig generated/kubeconfig get nodes
```

---

## Phase 5: Worker Nodes

### Create Worker Servers

```bash
# Create CCX43 worker (stopped)
hcloud server create \
  --name talos-worker-1 \
  --type ccx43 \
  --image ubuntu-24.04 \
  --location ash \
  --network talos-cluster-net \
  --firewall talos-cluster-fw \
  --label role=worker \
  --label cluster=talos-cluster \
  --start-after-create=false

# Create CCX33 worker (stopped)
hcloud server create \
  --name talos-worker-2 \
  --type ccx33 \
  --image ubuntu-24.04 \
  --location ash \
  --network talos-cluster-net \
  --firewall talos-cluster-fw \
  --label role=worker \
  --label cluster=talos-cluster \
  --start-after-create=false
```

### Attach Talos ISO and Start Workers

```bash
# Attach ISO
hcloud server attach-iso talos-worker-1 ${TALOS_ISO_ID}
hcloud server attach-iso talos-worker-2 ${TALOS_ISO_ID}

# Start workers
hcloud server poweron talos-worker-1
hcloud server poweron talos-worker-2

# Wait for boot
sleep 30

# Get worker IPs
WORKER1_IP=$(hcloud server describe talos-worker-1 -o format='{{.PublicNet.IPv4.IP}}')
WORKER2_IP=$(hcloud server describe talos-worker-2 -o format='{{.PublicNet.IPv4.IP}}')

echo "Worker1: ${WORKER1_IP}"
echo "Worker2: ${WORKER2_IP}"
```

### Apply Worker Config

```bash
# Apply config to workers
talosctl apply-config --insecure \
  --endpoints ${WORKER1_IP} \
  --nodes ${WORKER1_IP} \
  --file generated/worker.yaml

talosctl apply-config --insecure \
  --endpoints ${WORKER2_IP} \
  --nodes ${WORKER2_IP} \
  --file generated/worker.yaml
```

### Detach ISO and Reset Workers

```bash
# Detach ISO
hcloud server detach-iso talos-worker-1
hcloud server detach-iso talos-worker-2

# Reset to boot from disk
hcloud server reset talos-worker-1
hcloud server reset talos-worker-2

# Wait for workers to join cluster
sleep 60
```

### Label Worker Nodes

```bash
# Workers get random hostnames - label them with worker role
kubectl --kubeconfig generated/kubeconfig get nodes

# For each worker node (replace <hostname> with actual hostname):
kubectl --kubeconfig generated/kubeconfig label node <worker-hostname> node-role.kubernetes.io/worker=""
```

---

## Phase 6: Verification

### Verify Cluster Health

```bash
# All 5 nodes should be Ready
kubectl --kubeconfig generated/kubeconfig get nodes

# Check etcd members (should show 3)
TALOSCONFIG=generated/talosconfig talosctl etcd members \
  --endpoints ${CP1_IP} \
  --nodes ${CP1_IP}

# Check all pods are running
kubectl --kubeconfig generated/kubeconfig get pods -A

# Cilium status
kubectl --kubeconfig generated/kubeconfig -n kube-system get pods -l app.kubernetes.io/part-of=cilium
```

### Test Workload Scheduling

```bash
# Deploy test workload
kubectl --kubeconfig generated/kubeconfig create deployment test-nginx --image=nginx --replicas=2

# Verify pods are on workers only (not control plane)
kubectl --kubeconfig generated/kubeconfig get pods -o wide

# Clean up
kubectl --kubeconfig generated/kubeconfig delete deployment test-nginx
```

---

## Current Cluster Details (2025-12-06)

| Node | Public IP | Private IP | K8s Hostname |
|------|-----------|------------|--------------|
| talos-cp-1 | 178.156.172.34 | 10.0.1.1 | talos-cp-1 |
| talos-cp-2 | 5.161.48.192 | 10.0.1.2 | talos-cp-2 |
| talos-cp-3 | 5.161.92.89 | 10.0.1.3 | talos-cp-3 |
| talos-worker-1 | 5.161.219.173 | 10.0.1.10 | talos-zug-ygp |
| talos-worker-2 | 178.156.156.43 | 10.0.1.4 | talos-iew-fwn |

---

## Teardown (Destroy Cluster)

```bash
# Delete all servers
hcloud server delete talos-cp-1
hcloud server delete talos-cp-2
hcloud server delete talos-cp-3
hcloud server delete talos-worker-1
hcloud server delete talos-worker-2

# Delete firewall
hcloud firewall delete talos-cluster-fw

# Delete network
hcloud network delete talos-cluster-net
```

---

## Troubleshooting

### Cilium Init Container CrashLoopBackOff

If you see `Init:CrashLoopBackOff` with error `unable to apply caps: operation not permitted`:

```bash
# Uninstall Cilium
helm --kubeconfig generated/kubeconfig uninstall cilium -n kube-system

# Reinstall with proper security context (see Phase 4 above)
```

The key settings are:
- `securityContext.capabilities.ciliumAgent`
- `securityContext.capabilities.cleanCiliumState`

### Node Shows NotReady

Nodes show NotReady until Cilium CNI is deployed. This is expected behavior.

### Cannot Connect to Talos API

1. Verify firewall allows port 50000 from your IP
2. Check server is running: `hcloud server list`
3. Wait 30-60 seconds after boot

### etcd Won't Form Quorum

1. Verify all 3 CP nodes are running
2. Check private network connectivity
3. Reset and re-bootstrap if needed:
   ```bash
   talosctl reset --graceful=false --endpoints ${CP1_IP} --nodes ${CP1_IP}
   ```

---

## References

- [Talos Linux Documentation](https://www.talos.dev/v1.10/)
- [Deploying Cilium on Talos](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
- [Hetzner Cloud CLI](https://github.com/hetznercloud/cli)
