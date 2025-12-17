# Hub Cluster Setup Guide

Single-node Talos Kubernetes hub cluster on Hetzner Cloud for the hub-and-spoke ArgoCD architecture.

## Overview

The hub cluster runs centralized management workloads:
- **ArgoCD**: GitOps deployment to all spoke clusters
- **Kargo**: Progressive delivery pipelines
- **External Secrets Operator**: Secrets sync from Azure Key Vault
- **Tailscale**: Secure remote access

Spoke clusters run application workloads and are managed by the hub.

## Architecture

| Component | Value |
|-----------|-------|
| Server | hub-cp-1 (single node) |
| Type | cpx31 (4 vCPU, 8GB RAM, 160GB SSD) |
| Location | ash (Ashburn, VA) |
| Network | hub-cluster-net (10.1.0.0/16) |
| Kubernetes | v1.32.0 |
| Talos | v1.11.5 |
| CNI | Cilium 1.16.4 |
| Cost | ~$15/month |

## Prerequisites

- `hcloud` CLI with API token
- `talosctl` v1.11.5+
- `helm` v3.x
- `kubectl` v1.32+

```bash
# Verify tools
hcloud version
talosctl version --client
helm version --short
kubectl version --client
```

## Quick Start (Automated)

```bash
cd ~/repos/PittampalliOrg/talos-cluster/scripts
export HCLOUD_TOKEN="your-token-here"

# 1. Provision infrastructure
bash provision-hub.sh

# 2. Generate Talos config
bash gen-hub-config.sh

# 3. Bootstrap cluster
HUB_IP=$(hcloud server describe hub-cp-1 -o format='{{.PublicNet.IPv4.IP}}')
bash bootstrap-hub.sh $HUB_IP

# 4. Verify
KUBECONFIG=~/.kube/hub-config kubectl get nodes
```

## Manual Setup (Step-by-Step)

Use this if the automated scripts fail or you need more control.

### Step 1: Create Infrastructure

```bash
export HCLOUD_TOKEN="your-token-here"

# Create private network
hcloud network create --name hub-cluster-net --ip-range 10.1.0.0/16
hcloud network add-subnet hub-cluster-net \
  --type cloud \
  --network-zone us-east \
  --ip-range 10.1.1.0/24

# Create firewall
hcloud firewall create --name hub-cluster-fw
hcloud firewall add-rule hub-cluster-fw --direction in --protocol tcp --port 6443 --source-ips 0.0.0.0/0 --description "Kubernetes API"
hcloud firewall add-rule hub-cluster-fw --direction in --protocol tcp --port 50000 --source-ips 0.0.0.0/0 --description "Talos API"
hcloud firewall add-rule hub-cluster-fw --direction in --protocol udp --port 41641 --source-ips 0.0.0.0/0 --description "Tailscale"
hcloud firewall add-rule hub-cluster-fw --direction in --protocol icmp --source-ips 0.0.0.0/0 --description "ICMP"

# Create server (use cpx31, NOT cx32 - deprecated in ash)
hcloud server create \
  --name hub-cp-1 \
  --type cpx31 \
  --image ubuntu-24.04 \
  --location ash \
  --start-after-create=false

# Attach to network
hcloud server attach-to-network hub-cp-1 --network hub-cluster-net --ip 10.1.1.1

# Apply firewall
hcloud firewall apply-to-resource hub-cluster-fw --type server --server hub-cp-1

# Attach Talos ISO and start
hcloud server attach-iso hub-cp-1 122630  # Talos 1.11.2 amd64
hcloud server poweron hub-cp-1

# Get public IP
HUB_IP=$(hcloud server describe hub-cp-1 -o format='{{.PublicNet.IPv4.IP}}')
echo "Hub IP: $HUB_IP"
```

### Step 2: Wait for Talos Maintenance Mode

```bash
# Wait ~60 seconds for boot, then verify
talosctl --nodes $HUB_IP version --insecure
# Expected: "API is not implemented in maintenance mode" = ready for config
```

### Step 3: Generate Talos Configuration

```bash
cd ~/repos/PittampalliOrg/talos-cluster

# Generate secrets (only once - reuse for recovery)
mkdir -p secrets
talosctl gen secrets -o secrets/hub-secrets.yaml

# Generate machine config
mkdir -p generated/hub
talosctl gen config hub-cluster https://10.1.1.1:6443 \
  --with-secrets secrets/hub-secrets.yaml \
  --config-patch @main/patches/common.yaml \
  --config-patch-control-plane @main/patches/controlplane/hub.yaml \
  --kubernetes-version 1.32.0 \
  --output-dir generated/hub \
  --force

# Validate
talosctl validate --mode cloud --config generated/hub/controlplane.yaml
```

### Step 4: Apply Configuration and Bootstrap

```bash
# Apply config to node
talosctl apply-config --insecure \
  --nodes $HUB_IP \
  --file generated/hub/controlplane.yaml

# Wait for installation (~3 minutes)
echo "Waiting for Talos installation..."
sleep 180

# Detach ISO and reset
hcloud server detach-iso hub-cp-1
hcloud server reset hub-cp-1

# Wait for reboot (~60 seconds)
sleep 60

# Setup talosconfig
mkdir -p ~/.talos
cp generated/hub/talosconfig ~/.talos/hub-config
talosctl --talosconfig ~/.talos/hub-config config endpoint $HUB_IP

# Bootstrap etcd
talosctl --talosconfig ~/.talos/hub-config --nodes $HUB_IP bootstrap

# Wait for Kubernetes API
talosctl --talosconfig ~/.talos/hub-config --nodes $HUB_IP health --wait-timeout 5m
```

### Step 5: Get Kubeconfig

```bash
# Generate kubeconfig
talosctl --talosconfig ~/.talos/hub-config --nodes $HUB_IP kubeconfig --force ~/.kube/hub-config

# IMPORTANT: Update to use public IP (private IP not routable externally)
sed -i "s|https://10.1.1.1:6443|https://$HUB_IP:6443|g" ~/.kube/hub-config

# Verify - node will be NotReady until CNI installed
KUBECONFIG=~/.kube/hub-config kubectl get nodes
```

### Step 6: Install Cilium CNI

```bash
# Add Cilium repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium with Talos-specific settings
KUBECONFIG=~/.kube/hub-config helm install cilium cilium/cilium \
  --version 1.16.4 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445

# Wait for Cilium
sleep 30
KUBECONFIG=~/.kube/hub-config kubectl get pods -n kube-system | grep cilium

# Verify node is Ready
KUBECONFIG=~/.kube/hub-config kubectl get nodes
```

### Step 7: Verify Cluster Health

```bash
# Full Talos health check
talosctl --talosconfig ~/.talos/hub-config --nodes $HUB_IP health

# Expected output: all checks OK
# - etcd healthy
# - kubelet healthy
# - all k8s nodes ready
# - coredns ready
```

## Generated Files

| File | Purpose |
|------|---------|
| `~/.kube/hub-config` | Kubernetes access |
| `~/.talos/hub-config` | Talos API access |
| `secrets/hub-secrets.yaml` | Cluster secrets (encrypt with git-crypt!) |
| `generated/hub/controlplane.yaml` | Machine configuration |

## Access Commands

```bash
# Kubernetes
export KUBECONFIG=~/.kube/hub-config
kubectl get nodes
kubectl get pods -A

# Talos
export TALOSCONFIG=~/.talos/hub-config
talosctl --nodes $HUB_IP health
talosctl --nodes $HUB_IP services
talosctl --nodes $HUB_IP logs kubelet
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `cx32` not available | Deprecated in ash location | Use `cpx31` instead |
| Node NotReady | CNI not installed | Install Cilium (Step 6) |
| Connection refused to 10.1.1.1 | Using private IP externally | Update kubeconfig to public IP |
| `--server` flag unknown | Old hcloud syntax | Use `--type server --server` |
| Health check timeout | CNI not ready | Install Cilium first, then re-run health |
| Bootstrap hangs | Server still in maintenance mode | Wait for Talos installation to complete |

## Server Type Selection

**Use `cpx31` for the hub cluster.**

| Type | vCPU | RAM | Status | Notes |
|------|------|-----|--------|-------|
| cx32 | 4 | 8GB | Deprecated | Not available in ash after 2025-12-31 |
| cpx31 | 4 | 8GB | Available | Recommended replacement |
| cpx21 | 3 | 4GB | Available | Budget option (may be tight for ArgoCD) |

## Teardown

```bash
export HCLOUD_TOKEN="your-token"

# Delete server
hcloud server delete hub-cp-1

# Delete network (optional - may want to keep for rebuild)
hcloud network delete hub-cluster-net

# Delete firewall (optional)
hcloud firewall delete hub-cluster-fw

# Clean local configs
rm -f ~/.kube/hub-config ~/.talos/hub-config
```

## Next Steps

After hub cluster is running:

1. **Install ArgoCD**: Deploy ArgoCD for GitOps management
2. **Configure Tailscale**: Enable remote access via Tailscale serve
3. **Setup ESO**: Configure External Secrets Operator with Azure Key Vault
4. **Register Spokes**: Add spoke clusters to hub ArgoCD

See [hub-recovery-runbook.md](hub-recovery-runbook.md) for recovery procedures.
