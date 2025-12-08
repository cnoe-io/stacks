# Hetzner Cloud Talos Cluster Setup Reference

This document provides step-by-step commands to reproduce the Talos Kubernetes cluster on Hetzner Cloud. It is based on actual production deployments and includes lessons learned from troubleshooting.

## Quick Reference

```bash
# Essential variables (set these before running any commands)
export HCLOUD_TOKEN="your-hcloud-api-token"
export TALOS_ISO_ID=122630  # Hetzner public Talos v1.11.2 amd64 ISO (hcloud-v1-11-2-amd64.iso)
export TALOS_CONFIG_DIR=~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd/generated
```

## Version Compatibility Matrix

> **CRITICAL**: When generating Talos configs for amd64 servers (like Hetzner Cloud), you **MUST run `talosctl gen config` from an amd64 machine**. Running it from an ARM64 machine (M1/M2/M3 Mac) produces configs that cause "exec format error" on etcd/kubelet.

| Component | Version | Notes |
|-----------|---------|-------|
| **Hetzner ISO** | 122630 (v1.11.2) | `hcloud-v1-11-2-amd64.iso` - boots to maintenance mode only |
| **talosctl client** | v1.11.5 | Must be amd64 binary on amd64 machine |
| **--install-image** | **v1.11.5** | **Must match talosctl client version** |
| **--kubernetes-version** | **1.32.0** | Default K8s version for Talos v1.11.5 |

### The Architecture Problem

**The Problem**: `talosctl gen config` embeds architecture-specific image digests based on the host machine's architecture. When you run it from an ARM64 Mac, the generated configs contain ARM64 image references, which fail on amd64 servers with "exec format error".

**What You See:**
- Talos services (apid, machined, containerd) run fine - they're from the ISO
- etcd and kubelet crash immediately with exit code 255
- No logs from etcd/kubelet (they never start)
- `talosctl version` shows Talos server is `linux/amd64` (correct)
- But container images are ARM64 (wrong)

**Diagnosis:**
```bash
# Check host architecture where you generated configs
talosctl version --client
# If it shows "linux/arm64" and your servers are amd64, that's the problem!

# Check etcd service status
talosctl service etcd -n <node-ip> -e <node-ip>
# Shows: STATE=Waiting, HEALTH=Fail, exit code 255
```

**The Solution - Generate Configs from an amd64 Machine:**
```bash
# Option 1: SSH to an amd64 server (like nixos-hetzner)
ssh nixos-hetzner
cd ~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd
talosctl gen config ...  # Now uses amd64-native talosctl

# Option 2: Run in a Docker container on ARM64
docker run --rm -it -v $(pwd):/work -w /work \
  --platform linux/amd64 \
  ghcr.io/siderolabs/talosctl:v1.11.5 \
  gen config talos-cluster https://10.0.1.1:6443 ...

# Option 3: Use Nix with amd64 emulation
nix-shell -p talosctl --argstr system x86_64-linux
```

**Key Insight**: The Hetzner ISO (v1.11.2) only boots the node into maintenance mode. The configs define which container images are pulled. If those configs have ARM64 digests, etcd/kubelet will fail.

**What works (on amd64 machine):**
```bash
# Run FROM an amd64 machine!
# talosctl v1.11.5 client + installer v1.11.5 + K8s 1.32.0 = SUCCESS
talosctl gen config talos-cluster https://10.0.1.1:6443 \
  --kubernetes-version 1.32.0 \
  --install-image ghcr.io/siderolabs/installer:v1.11.5 \
  ...
```

**What causes "exec format error":**
1. **Running `talosctl gen config` from ARM64 machine for amd64 targets** (most common)
2. Mismatched installer version with talosctl client
3. Using Talos 1.11.2 installer (ISO version) with talosctl 1.11.5 client

> **IMPORTANT - Architecture**: Hetzner Cloud servers are **amd64** (x86_64). Always generate Talos configs from an amd64 machine, not from ARM64 (M1/M2/M3 Mac).

## Cluster Architecture

| Node | Type | vCPU | RAM | Disk | Role | Monthly Cost |
|------|------|------|-----|------|------|--------------|
| talos-cp-1 | CPX21 | 3 | 4GB | 80GB | control-plane | $8.50 |
| talos-cp-2 | CPX21 | 3 | 4GB | 80GB | control-plane | $8.50 |
| talos-cp-3 | CPX21 | 3 | 4GB | 80GB | control-plane | $8.50 |
| talos-worker-1 | CCX43 | 16 | 64GB | 360GB | worker | $100.00 |
| talos-worker-2 | CCX33 | 8 | 32GB | 240GB | worker | $50.00 |
| **Total** | | | | | | **~$175/mo** |

**CNI**: Flannel (built into Talos config - no separate CNI installation required)

## Network Topology Recommendations

> **IMPORTANT**: Hetzner Cloud has a complex networking model that affects Talos cluster configuration. Read this section carefully to avoid networking issues.

### The Mixed IP Problem

Hetzner Cloud assigns both:
- **Private IPs** (10.0.x.x) via the private network
- **Public IPs** (5.x.x.x, 178.x.x.x) for external access

By default, nodes may advertise their private IP to the Kubernetes API, but this IP is **only routable from other nodes on the private network**. Pods running on nodes with only public IPs cannot reach private IP endpoints.

### Recommended Network Configuration

**Option 1: All Nodes on Private Network (Recommended)**

Place all nodes on the Hetzner private network and use a load balancer or Tailscale for external access:

```yaml
# In Talos machine config, ensure private network is used for K8s communication
machine:
  network:
    interfaces:
      - interface: eth0
        dhcp: true
        # Private network is primary for K8s
```

**Option 2: All Public IPs with Comprehensive Firewall**

If using public IPs, ensure all inter-node communication ports are open:
- Ports 2379-2380 (etcd) between control planes
- Port 4789/UDP (Flannel VXLAN) between all nodes
- Port 6443 (API) between all nodes
- Port 10250 (kubelet) between all nodes
- Port 50000 (Talos API) for management

### Avoid Mixed Topologies

**DO NOT** mix private-IP-only nodes with public-IP-only nodes. This causes:
- etcd peer communication failures
- Kubernetes service endpoint routing issues
- Pod-to-API server communication timeouts

### Kubernetes Endpoint Topology

Check your Kubernetes API endpoints:
```bash
kubectl get endpoints kubernetes -n default
```

If you see a mix of private (10.0.x.x) and public IPs, pods on public-IP nodes will intermittently fail to reach the API when kube-proxy routes to the private IP.

**Solution**: Ensure all control plane nodes are either:
1. All on private network (10.0.x.x endpoints)
2. All on public network with all ports open (public IP endpoints)

---

## Prerequisites

### Required Tools

```bash
# Verify tool versions
talosctl version --client    # >= 1.11.0
kubectl version --client     # >= 1.32.0
hcloud version               # any recent version
```

### Hetzner Cloud Authentication

> **IMPORTANT**: The hcloud CLI does not persist contexts well. Always export `HCLOUD_TOKEN` before running commands.

```bash
# REQUIRED: Set HCLOUD_TOKEN for every session
export HCLOUD_TOKEN="your-api-token"

# Verify authentication works
hcloud server list
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

> **CRITICAL**: The firewall rules below are essential for cluster functionality. Missing rules will cause etcd cluster formation failures, pod networking issues, and API server communication problems.

```bash
# Create firewall
hcloud firewall create --name talos-cluster-fw

# ============================================================
# EXTERNAL ACCESS RULES
# ============================================================

# Allow Tailscale UDP (for Tailscale operator)
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

# Allow Talos API from operator IP (for talosctl commands)
OPERATOR_IP=$(curl -s ifconfig.me)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 50000 \
  --source-ips ${OPERATOR_IP}/32

# Allow Kubernetes API from operator IP (for kubectl)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 6443 \
  --source-ips ${OPERATOR_IP}/32

# ============================================================
# PRIVATE NETWORK RULES (10.0.0.0/16)
# ============================================================

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

# ============================================================
# INTER-NODE COMMUNICATION (CRITICAL FOR PUBLIC IPs)
# ============================================================
# These rules are REQUIRED when nodes use public IPs.
# Without them, etcd won't form quorum and pod networking fails.

# Get node public IPs (run after nodes are created)
CP1_IP=$(hcloud server describe talos-cp-1 -o format='{{.PublicNet.IPv4.IP}}')
CP2_IP=$(hcloud server describe talos-cp-2 -o format='{{.PublicNet.IPv4.IP}}')
CP3_IP=$(hcloud server describe talos-cp-3 -o format='{{.PublicNet.IPv4.IP}}')
WORKER1_IP=$(hcloud server describe talos-worker-1 -o format='{{.PublicNet.IPv4.IP}}')
WORKER2_IP=$(hcloud server describe talos-worker-2 -o format='{{.PublicNet.IPv4.IP}}')

# Create source IP list for all nodes
NODE_IPS="${CP1_IP}/32,${CP2_IP}/32,${CP3_IP}/32,${WORKER1_IP}/32,${WORKER2_IP}/32"

# etcd peer communication (CRITICAL - without this, etcd cluster won't form)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 2379-2380 \
  --source-ips ${CP1_IP}/32 \
  --source-ips ${CP2_IP}/32 \
  --source-ips ${CP3_IP}/32

# Kubernetes API between nodes (required for pod-to-API communication)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 6443 \
  --source-ips ${NODE_IPS}

# Kubelet API (required for kubectl exec/logs)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 10250 \
  --source-ips ${NODE_IPS}

# Flannel VXLAN (required for pod-to-pod networking)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol udp \
  --port 4789 \
  --source-ips ${NODE_IPS}

# Alternative: Flannel VXLAN on port 8472 (some Flannel versions)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol udp \
  --port 8472 \
  --source-ips ${NODE_IPS}

# Talos API between nodes (for cluster management)
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 50000 \
  --source-ips ${NODE_IPS}
```

### Firewall Rules Summary

| Port | Protocol | Purpose | Required For |
|------|----------|---------|--------------|
| 2379-2380 | TCP | etcd client/peer | Control plane formation |
| 4789 | UDP | Flannel VXLAN | Pod networking |
| 6443 | TCP | Kubernetes API | kubectl, pod-to-API |
| 8472 | UDP | Flannel VXLAN (alt) | Pod networking (backup) |
| 10250 | TCP | Kubelet API | kubectl exec/logs |
| 41641 | UDP | Tailscale | Remote access |
| 50000 | TCP | Talos API | talosctl commands |

> **Troubleshooting**: If pods show "connection refused" or "i/o timeout" when accessing the Kubernetes API service (10.96.0.1), the firewall is likely blocking inter-node communication. Check that ports 6443, 4789, and 10250 are allowed between all node public IPs.

---

## Phase 2: Talos Configuration

### Using Existing Configs

The Talos configs are pre-generated and stored in the repository. **Do not regenerate unless you need to change cluster configuration.**

```bash
# Configs location
export TALOS_CONFIG_DIR=~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd/talos-configs

# Directory contents:
# - controlplane.yaml  # Control plane machine config
# - worker.yaml        # Worker machine config
# - talosconfig        # talosctl client config
# - kubeconfig         # kubectl client config (generated after bootstrap)
# - secrets.yaml       # Cluster secrets (encrypted with git-crypt)
```

### Generate New Configs (Only If Needed)

> **WARNING**: Only regenerate configs if you need to change cluster configuration. Existing nodes will need to be rebuilt with new configs.

> **CRITICAL - Cross-Architecture Generation**: If running `talosctl` on ARM64 (M1/M2/M3 Mac), you MUST specify amd64 images explicitly. The Talos installer and system images are multi-arch, but containerd may pull the wrong architecture based on the host.

```bash
# Create directories if they don't exist
mkdir -p secrets generated patches/controlplane patches/worker

# Generate secrets (store securely with git-crypt)
talosctl gen secrets --output-file secrets/secrets.yaml

# =============================================================================
# IMPORTANT: --install-image MUST match your talosctl client version
# Check your version: talosctl version --client
# The Hetzner ISO version (v1.11.2) does NOT need to match
# =============================================================================
talosctl gen config talos-cluster https://10.0.1.1:6443 \
  --kubernetes-version 1.32.0 \
  --install-image ghcr.io/siderolabs/installer:v1.11.5 \
  --with-secrets secrets/secrets.yaml \
  --config-patch @patches/common.yaml \
  --config-patch-control-plane @patches/controlplane/all.yaml \
  --config-patch-worker @patches/worker/all.yaml \
  --with-examples=false \
  --with-docs=false \
  --output generated/ \
  --force

# Validate configs
talosctl validate --config generated/controlplane.yaml --mode cloud
talosctl validate --config generated/worker.yaml --mode cloud

# =============================================================================
# VERIFY: Check that install image matches talosctl version
# =============================================================================
grep "install:" -A2 generated/controlplane.yaml
# Expected output:
#     install:
#         disk: /dev/sda
#         image: ghcr.io/siderolabs/installer:v1.11.5
```

**Key Flags Explained:**

| Flag | Purpose |
|------|---------|
| `--install-image` | **CRITICAL**: Sets the Talos installer version. Must match talosctl client version (v1.11.5) |
| `--kubernetes-version` | Use 1.32.0 with Talos v1.11.5. This combination is tested and works. |
| `--with-examples=false` | Reduces config size (Hetzner userdata limit is 32KB) |
| `--with-docs=false` | Further reduces config size |
| `--force` | Overwrites existing generated configs |

**Tested Working Combinations:**

| talosctl | --install-image | --kubernetes-version | Status |
|----------|-----------------|---------------------|--------|
| v1.11.5 | v1.11.5 | 1.32.0 | **Works** |
| v1.11.5 | v1.11.2 | 1.34.1 | **Fails** (exec format error on etcd) |
| v1.11.5 | v1.11.2 | 1.32.0 | **Fails** (exec format error) |

> **TIP**: Always check your talosctl version first: `talosctl version --client`. Use the same version for `--install-image`.

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

# Wait for nodes to boot (~30-45 seconds)
sleep 45
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

# Wait for etcd to form quorum (~30-60 seconds)
sleep 30

# Verify etcd members (should show 3 members, may start as learners)
TALOSCONFIG=generated/talosconfig talosctl etcd members \
  --endpoints ${CP1_IP} \
  --nodes ${CP1_IP}
```

> **Note**: etcd members may initially show as "learners" (LEARNER=true). Wait 30-60 seconds for them to be promoted to full members. If a stale learner persists from a previous failed attempt, remove it:
> ```bash
> TALOSCONFIG=generated/talosconfig talosctl etcd remove-member <member-id> \
>   --endpoints ${CP1_IP} --nodes ${CP1_IP}
> ```

### Get Kubeconfig

```bash
# Generate kubeconfig
talosctl kubeconfig \
  --endpoints ${CP1_IP} \
  --nodes ${CP1_IP} \
  --talosconfig generated/talosconfig \
  generated/kubeconfig

# IMPORTANT: The kubeconfig uses the private IP by default (10.0.1.1)
# Update it to use a public IP for external access:
sed -i 's|https://10.0.1.1:6443|https://'${CP1_IP}':6443|' generated/kubeconfig

# Verify nodes (will show NotReady - no CNI yet)
kubectl --kubeconfig generated/kubeconfig get nodes
```

---

## Phase 4: CNI Configuration

### Flannel (Default - Built into Talos Config)

> **NOTE**: Our Talos configuration uses **Flannel CNI** which is built into Talos and requires no separate installation. Nodes will become Ready automatically once Flannel pods start.

```bash
# Verify Flannel pods are running
kubectl --kubeconfig ${TALOS_CONFIG_DIR}/kubeconfig -n kube-system get pods | grep flannel

# Verify nodes are Ready
kubectl --kubeconfig ${TALOS_CONFIG_DIR}/kubeconfig get nodes
```

Expected output:
```
NAME            STATUS   ROLES           AGE   VERSION
talos-cp-1      Ready    control-plane   5m    v1.34.1
talos-cp-3      Ready    control-plane   5m    v1.34.1
```

### Alternative: Cilium CNI

If you need Cilium instead of Flannel, you must:
1. Generate new Talos configs with CNI disabled (`cluster.network.cni.name: none`)
2. Apply those configs before the bootstrap phase
3. Install Cilium with Talos-specific settings

**CRITICAL**: Talos requires specific security context capabilities for Cilium. Without these settings, the `clean-cilium-state` init container will crash with `unable to apply caps: operation not permitted`.

```bash
# Add Cilium Helm repo (only if using Cilium)
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium with Talos-specific settings
helm install cilium cilium/cilium --version 1.16.4 \
  --namespace kube-system \
  --kubeconfig ${TALOS_CONFIG_DIR}/kubeconfig \
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

# Wait for boot (~45 seconds for larger dedicated CPU servers)
sleep 45

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

> **IMPORTANT**: Wait at least 5 seconds after applying config before detaching ISO. The config apply triggers the installation process - detaching too early can result in the server booting back into Ubuntu instead of Talos.

```bash
# Short delay to ensure install starts
sleep 5

# Detach ISO
hcloud server detach-iso talos-worker-1
hcloud server detach-iso talos-worker-2

# Reset to boot from disk
hcloud server reset talos-worker-1
hcloud server reset talos-worker-2

# Wait for workers to join cluster (~90 seconds for dedicated CPU servers)
sleep 90
```

### Label Worker Nodes

```bash
# Workers get random hostnames - list them first
kubectl --kubeconfig generated/kubeconfig get nodes

# Label each worker node (replace <hostname> with actual hostname)
# Example: talos-ofc-xhf, talos-zc8-e1s
kubectl --kubeconfig generated/kubeconfig label node <worker-hostname-1> node-role.kubernetes.io/worker=""
kubectl --kubeconfig generated/kubeconfig label node <worker-hostname-2> node-role.kubernetes.io/worker=""
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

## Phase 7: Remote Access (kubeconfig Merge)

### Merge to Local Machine (M1 Mac)

To access the cluster from your local machine (e.g., M1 Mac), merge the kubeconfig:

```bash
# On the Hetzner host, get the kubeconfig
scp hetzner:~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd/talos-configs/kubeconfig /tmp/talos-kubeconfig

# Backup existing kubeconfig
cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)

# Merge kubeconfigs
export KUBECONFIG=~/.kube/config:/tmp/talos-kubeconfig
kubectl config view --flatten > /tmp/config.merged
cp /tmp/config.merged ~/.kube/config

# Switch to the Talos context
kubectl config use-context admin@talos-cluster

# Verify connection
kubectl get nodes
```

> **NOTE**: The kubeconfig must use a public IP (not 10.0.1.1) for remote access. The config apply already updates this during the merge.

### Using k9s

Once the kubeconfig is merged, you can use k9s:

```bash
k9s --context admin@talos-cluster
```

---

## Phase 8: Configure OIDC Issuer for Azure Workload Identity

> **IMPORTANT**: For Azure Workload Identity to work, the cluster's OIDC issuer must be configured to use the Azure Storage URL, not the default API server IP.

### Check Current OIDC Issuer

```bash
# Check current issuer (will show API server IP by default)
kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer'
# Default: https://5.161.92.89:6443 (API server IP)
# Required: https://oidcissuerXXXX.z13.web.core.windows.net/
```

### Configure OIDC Issuer via Talos Patch

```bash
# Get your Azure Storage URL
OIDC_ISSUER_URL="https://oidcissuer65846b7df97b.z13.web.core.windows.net"

# Create the patch file
cat > /tmp/oidc-patch.yaml << EOF
cluster:
  apiServer:
    extraArgs:
      service-account-issuer: ${OIDC_ISSUER_URL}/
EOF

# Apply patch to all control plane nodes
for CP_IP in ${CP1_IP} ${CP2_IP} ${CP3_IP}; do
  echo "Patching node ${CP_IP}..."
  talosctl apply-config \
    --endpoints ${CP_IP} \
    --nodes ${CP_IP} \
    --mode no-reboot \
    --config-patch @/tmp/oidc-patch.yaml
done

# Verify the change (takes effect immediately, no reboot needed)
kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer'
# Should now show: https://oidcissuerXXXX.z13.web.core.windows.net/
```

### Sync JWKS to Azure Storage

After configuring the issuer, sync the cluster's signing keys:

```bash
cd ~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd/scripts
source .env
./02-sync-jwks.sh --force
```

---

## Phase 9: ArgoCD Bootstrap

After the cluster is operational, bootstrap ArgoCD and the GitOps platform:

```bash
# On the Hetzner host
export KUBECONFIG=~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd/talos-configs/kubeconfig
cd ~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd/scripts

# Run the bootstrap (installs ArgoCD, syncs JWKS, applies base apps)
./bootstrap-cluster.sh

# If CNI check fails (because we use Flannel, not Cilium), run scripts individually:
source .env
./01-install-argocd.sh    # Install ArgoCD via Helm
./02-sync-jwks.sh         # Sync OIDC JWKS to Azure Storage
./03-apply-base-apps.sh   # Apply root ArgoCD application
```

### Verify ArgoCD Installation

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Expected: All pods Running (Redis HA may take ~2 minutes to initialize)
# argocd-application-controller-0                    1/1     Running
# argocd-server-*                                    1/1     Running
# argocd-repo-server-*                               1/1     Running
# argocd-redis-ha-server-*                           3/3     Running  (takes longer)

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Current Cluster Details (2025-12-08)

> **NOTE**: Worker node K8s hostnames are randomly generated by Talos (e.g., `talos-pc8-mo6`). They do NOT match Hetzner server names.

| Node | Public IP | Private IP | K8s Hostname | Notes |
|------|-----------|------------|--------------|-------|
| talos-cp-1 | 178.156.172.34 | 10.0.1.1 | talos-cp-1 | API endpoint |
| talos-cp-2 | N/A | 10.0.1.2 | (not joined) | May need troubleshooting |
| talos-cp-3 | 5.161.92.89 | 10.0.1.3 | talos-cp-3 | |
| talos-worker-1 | 5.161.219.173 | 10.0.1.4 | talos-pc8-mo6 | CCX43 (16 vCPU, 64GB) |
| talos-worker-2 | 178.156.156.43 | 10.0.1.5 | talos-vr4-z4y | CCX33 (8 vCPU, 32GB) |

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

### etcd Won't Form Quorum (CRITICAL)

**Symptoms:**
- `talosctl service etcd` shows "FAIL" health state
- Logs show "context deadline exceeded" or "dial tcp X.X.X.X:2380: i/o timeout"
- API server pods missing on some control plane nodes

**Root Cause:** Firewall blocking etcd peer communication on ports 2379-2380.

**Solution:**
```bash
# 1. Add firewall rules for etcd ports between control plane nodes
hcloud firewall add-rule talos-cluster-fw \
  --direction in \
  --protocol tcp \
  --port 2379-2380 \
  --source-ips ${CP1_IP}/32 \
  --source-ips ${CP2_IP}/32 \
  --source-ips ${CP3_IP}/32

# 2. Verify etcd members
talosctl etcd members --endpoints ${CP1_IP} --nodes ${CP1_IP}
```

### etcd Member Stuck as Learner

**Symptoms:**
- `talosctl etcd members` shows a node with `LEARNER=true`
- etcd logs show "rpc not supported for learner"

**Cause:** Node joined during network disruption and didn't get promoted.

**Solution:**
```bash
# 1. Remove the stuck learner from healthy node
talosctl --nodes ${HEALTHY_CP_IP} etcd remove-member <learner-member-id>

# 2. Wait for removal (check members list)
talosctl etcd members --nodes ${HEALTHY_CP_IP}

# 3. The stuck node will now show "permanently removed" errors
# Reboot it to rejoin as a new member
talosctl --nodes ${STUCK_NODE_IP} reboot
```

### etcd "Member Has Been Permanently Removed"

**Symptoms:**
- etcd logs: "the member has been permanently removed from the cluster"
- "data-dir used by this member must be removed"
- Node in restart loop

**Cause:** Node has stale etcd data from when it was removed.

**Solution:**
```bash
# 1. Tell the node to leave etcd (wipes data directory)
talosctl --nodes ${STUCK_NODE_IP} etcd leave

# 2. Reboot the node to rejoin with fresh etcd data
talosctl --nodes ${STUCK_NODE_IP} reboot

# 3. Wait 60-90 seconds, then verify
talosctl etcd members --nodes ${HEALTHY_CP_IP}
```

### Pod Networking Failures (Connection Refused to 10.96.0.1)

**Symptoms:**
- Pods can't reach Kubernetes API service at 10.96.0.1:443
- ArgoCD/External Secrets show "dial tcp 10.96.0.1:443: i/o timeout"
- DNS works (can resolve kubernetes.default.svc)

**Cause:** Mixed public/private IP topology + missing firewall rules.

**Diagnosis:**
```bash
# Check kubernetes service endpoints
kubectl get endpoints kubernetes -n default
# If you see a mix of private (10.0.x.x) and public IPs, this is the issue

# Check which API servers are running
kubectl get pods -n kube-system -l component=kube-apiserver -o wide
```

**Solution:**
```bash
# 1. Add firewall rules for inter-node API access
hcloud firewall add-rule talos-cluster-fw \
  --direction in --protocol tcp --port 6443 \
  --source-ips ${CP1_IP}/32,${CP2_IP}/32,${CP3_IP}/32,${WORKER1_IP}/32,${WORKER2_IP}/32

# 2. Add Flannel VXLAN port
hcloud firewall add-rule talos-cluster-fw \
  --direction in --protocol udp --port 4789 \
  --source-ips ${CP1_IP}/32,${CP2_IP}/32,${CP3_IP}/32,${WORKER1_IP}/32,${WORKER2_IP}/32

# 3. Restart Flannel to pick up new routes
kubectl rollout restart daemonset -n kube-system kube-flannel

# 4. Restart affected pods
kubectl rollout restart deployment -n argocd argocd-application-controller
kubectl rollout restart deployment -n external-secrets external-secrets
```

### ArgoCD Redis HA CrashLoopBackOff

**Symptoms:**
- Redis HA pods in CrashLoopBackOff
- ArgoCD server can't connect to Redis

**Cause:** Redis HA requires more complex setup and stable networking.

**Solution:** Use single Redis replica (already configured in argocd-values.yaml):
```yaml
redis:
  enabled: true
redis-ha:
  enabled: false
```

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

Nodes show NotReady until CNI is deployed. With Flannel (built into Talos config), nodes should become Ready automatically within 60 seconds of boot.

If nodes stay NotReady:
```bash
# Check Flannel pods
kubectl get pods -n kube-system -l app=flannel

# Check for firewall issues (port 4789 UDP)
kubectl logs -n kube-system -l app=flannel --tail=20
```

### Cannot Connect to Talos API

1. Verify firewall allows port 50000 from your IP
2. Check server is running: `hcloud server list`
3. Wait 30-60 seconds after boot
4. Verify talosconfig has correct endpoints:
   ```bash
   talosctl config endpoints add ${CP1_IP} ${CP2_IP} ${CP3_IP}
   ```

### "exec format error" in etcd/kubelet (Architecture Mismatch)

**Symptoms:**
- etcd service shows "Fail" health state with exit code 255
- **No logs** from etcd (container fails to start)
- Talos services (apid, machined, containerd, trustd) work fine
- `talosctl version` shows server is `linux/amd64` (correct)
- But `talosctl image list` shows small image sizes (22-75 MB instead of 100+ MB)

**Root Cause**: You ran `talosctl gen config` from an ARM64 machine (M1/M2/M3 Mac). The tool embeds architecture-specific image digests based on the host architecture.

**Diagnosis:**
```bash
# Check where you generated configs
talosctl version --client
# If shows "linux/arm64" but servers are amd64 → PROBLEM!

# Check etcd service - will show exit code 255, no logs
TALOSCONFIG=generated/talosconfig talosctl service etcd -n <ip> -e <ip>

# Check images - ARM64 images are smaller than amd64
TALOSCONFIG=generated/talosconfig talosctl image list -n <ip> -e <ip>
# ARM64 etcd: ~22 MB, ARM64 kubelet: ~75 MB
# AMD64 etcd: ~60 MB, AMD64 kubelet: ~120 MB
```

**Solution - Regenerate configs from amd64 machine:**

```bash
# Option 1: SSH to Hetzner server (x86_64)
ssh nixos-hetzner  # or any amd64 machine
cd ~/repos/PittampalliOrg/stacks/102-bootstrap-talos-argocd

# Regenerate configs
talosctl gen config talos-cluster https://10.0.1.1:6443 \
  --kubernetes-version 1.32.0 \
  --install-image ghcr.io/siderolabs/installer:v1.11.5 \
  --with-secrets secrets/secrets.yaml \
  --config-patch @patches/common.yaml \
  --config-patch-control-plane @patches/controlplane/all.yaml \
  --config-patch-worker @patches/worker/all.yaml \
  --output generated/ \
  --force

# Option 2: Use Docker on ARM64 Mac
docker run --rm -it -v $(pwd):/work -w /work \
  --platform linux/amd64 \
  ghcr.io/siderolabs/talosctl:v1.11.5 \
  gen config talos-cluster https://10.0.1.1:6443 \
  --kubernetes-version 1.32.0 \
  --install-image ghcr.io/siderolabs/installer:v1.11.5 \
  --output generated/ --force
```

**After regenerating, wipe and re-apply:**
```bash
# Wipe the nodes (removes all data, returns to maintenance mode)
for IP in ${CP1_IP} ${CP2_IP} ${CP3_IP}; do
  talosctl reset --graceful=false --reboot=true \
    --endpoints ${IP} --nodes ${IP}
done

# Wait for reboot
sleep 60

# Apply new configs
for IP in ${CP1_IP} ${CP2_IP} ${CP3_IP}; do
  talosctl apply-config --insecure \
    --endpoints ${IP} --nodes ${IP} \
    --file generated/controlplane.yaml
done

# Wait, then bootstrap
sleep 90
talosctl bootstrap --endpoints ${CP1_IP} --nodes ${CP1_IP}
```

**Prevention**: **Always generate Talos configs from an amd64 machine** when targeting amd64 servers. Add this check to your workflow:
```bash
# Verify architecture before generating configs
if [ "$(uname -m)" != "x86_64" ]; then
  echo "ERROR: Must run talosctl gen config from amd64 machine!"
  echo "Current arch: $(uname -m)"
  exit 1
fi
```

---

### "exec format error" on Worker Nodes (Installation Incomplete)

This error indicates the Talos installation didn't complete properly. The server is booting from the Ubuntu image instead of the installed Talos system.

**Cause**: ISO was detached before the installation completed, or the reset happened too quickly.

**Solution**: Recreate the affected worker:
```bash
# Delete the problematic worker
hcloud server delete talos-worker-X

# Recreate with proper timing
hcloud server create \
  --name talos-worker-X \
  --type ccxXX \
  --image ubuntu-24.04 \
  --location ash \
  --network talos-cluster-net \
  --firewall talos-cluster-fw \
  --label role=worker \
  --label cluster=talos-cluster \
  --start-after-create=false

# Attach ISO and start
hcloud server attach-iso talos-worker-X ${TALOS_ISO_ID}
hcloud server poweron talos-worker-X

# Wait longer for boot (45s for dedicated CPU)
sleep 45

# Apply config
WORKER_IP=$(hcloud server describe talos-worker-X -o format='{{.PublicNet.IPv4.IP}}')
talosctl apply-config --insecure \
  --endpoints ${WORKER_IP} --nodes ${WORKER_IP} \
  --file generated/worker.yaml

# Wait briefly for install to start
sleep 5

# Detach and reset
hcloud server detach-iso talos-worker-X
hcloud server reset talos-worker-X

# Wait longer for join (90s for dedicated CPU)
sleep 90
```

### Kubeconfig Uses Private IP

The generated kubeconfig points to the private IP (10.0.1.1) by default, which isn't reachable from outside the Hetzner private network.

**Solution**: Update the kubeconfig to use a public IP:
```bash
sed -i 's|https://10.0.1.1:6443|https://'${CP1_IP}':6443|' generated/kubeconfig
```

### Worker Boot Time

Dedicated CPU servers (CCX series) take longer to boot than shared CPU servers (CPX series):
- CPX (shared): ~30 seconds
- CCX (dedicated): ~45-60 seconds

Adjust sleep times accordingly to avoid timing issues.

---

## Timing Reference

| Operation | CPX (Shared) | CCX (Dedicated) |
|-----------|--------------|-----------------|
| Boot to maintenance | 30s | 45s |
| Boot from disk | 60s | 90s |
| etcd quorum | 30s | 30-60s |
| Cilium startup | 30s | 30s |

---

## References

- [Talos Linux Documentation](https://www.talos.dev/v1.11/)
- [Deploying Cilium on Talos](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
- [Hetzner Cloud CLI](https://github.com/hetznercloud/cli)
