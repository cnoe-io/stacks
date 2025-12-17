# Hetzner Cloud Talos Cluster Setup

Multi-node Talos Kubernetes cluster on Hetzner Cloud for running application workloads.

> **Hub Cluster?** For the single-node hub cluster (ArgoCD management), see [hub-cluster-setup.md](hub-cluster-setup.md).

## Cluster Types

| Cluster | Purpose | Nodes | Document |
|---------|---------|-------|----------|
| **Hub** | ArgoCD, Kargo, management | 1 (cpx31) | [hub-cluster-setup.md](hub-cluster-setup.md) |
| **Spoke** | Application workloads | 3-5 (cpx21/ccx) | This document |

## Spoke Cluster Architecture

| Node | Type | vCPU | RAM | Role | Cost |
|------|------|------|-----|------|------|
| talos-cp-{1,2,3} | cpx21 | 3 | 4GB | control-plane | ~$9 ea |
| talos-worker-1 | ccx43 | 16 | 64GB | worker | ~$100 |
| talos-worker-2 | ccx33 | 8 | 32GB | worker | ~$50 |
| **Total** | | **32** | **108GB** | 5 nodes | **~$177/mo** |

## Prerequisites

- `hcloud` CLI with API token
- `talosctl` v1.11.5+ (**run from amd64 machine**, not ARM Mac)
- Azure infrastructure for Workload Identity (optional)

## Quick Start

```bash
export HCLOUD_TOKEN="your-token"
cd ~/repos/PittampalliOrg/talos-cluster

# 1. Create network (if not exists)
hcloud network create --name talos-cluster-net --ip-range 10.0.0.0/16
hcloud network add-subnet talos-cluster-net --type cloud --network-zone us-east --ip-range 10.0.1.0/24

# 2. Create servers
TALOS_ISO_ID=122630  # Talos 1.11.2 amd64

for i in 1 2 3; do
  hcloud server create --name talos-cp-$i --type cpx21 --location ash \
    --image ubuntu-24.04 --start-after-create=false
  hcloud server attach-to-network talos-cp-$i --network talos-cluster-net --ip 10.0.1.$i
  hcloud server attach-iso talos-cp-$i $TALOS_ISO_ID
  hcloud server poweron talos-cp-$i
done

# 3. Wait for boot (~60s), get IPs
sleep 60
CP1_IP=$(hcloud server describe talos-cp-1 -o format='{{.PublicNet.IPv4.IP}}')
CP2_IP=$(hcloud server describe talos-cp-2 -o format='{{.PublicNet.IPv4.IP}}')
CP3_IP=$(hcloud server describe talos-cp-3 -o format='{{.PublicNet.IPv4.IP}}')

# 4. Generate and apply Talos config
talosctl gen secrets -o secrets/talos-secrets.yaml
talosctl gen config talos-cluster https://10.0.1.1:6443 \
  --with-secrets secrets/talos-secrets.yaml \
  --config-patch @main/patches/common.yaml \
  --config-patch-control-plane @main/patches/controlplane/all.yaml \
  --kubernetes-version 1.32.0 \
  --output-dir generated/talos --force

for IP in $CP1_IP $CP2_IP $CP3_IP; do
  talosctl apply-config --insecure --nodes $IP --file generated/talos/controlplane.yaml
done

# 5. Wait for installation, detach ISO, reset
sleep 180
for node in talos-cp-1 talos-cp-2 talos-cp-3; do
  hcloud server detach-iso $node
  hcloud server reset $node
done
sleep 90

# 6. Bootstrap etcd
talosctl --talosconfig generated/talos/talosconfig config endpoint $CP1_IP $CP2_IP $CP3_IP
talosctl --talosconfig generated/talos/talosconfig --nodes $CP1_IP bootstrap

# 7. Get kubeconfig
talosctl --talosconfig generated/talos/talosconfig --nodes $CP1_IP kubeconfig --force ~/.kube/talos-config
sed -i "s|https://10.0.1.1:6443|https://$CP1_IP:6443|g" ~/.kube/talos-config

# 8. Verify
KUBECONFIG=~/.kube/talos-config kubectl get nodes
```

## Critical: Node Naming

**Hetzner server name MUST match Talos hostname for proper networking.**

Mismatch causes:
- Flannel/Cilium routing failures
- Cross-node pod communication issues
- Service discovery failures

Fix mismatch:
```bash
# Check names
kubectl get nodes -o wide
hcloud server list

# Rename Hetzner server to match Talos hostname
hcloud server update old-name --name talos-cp-1
```

Or set hostname explicitly in Talos config:
```yaml
machine:
  network:
    hostname: talos-cp-1  # Must match Hetzner server name
```

## Server Types

| Type | vCPU | RAM | Use Case |
|------|------|-----|----------|
| cpx21 | 3 | 4GB | Control plane |
| cpx31 | 4 | 8GB | Hub cluster, small workloads |
| ccx33 | 8 | 32GB | Medium workers |
| ccx43 | 16 | 64GB | Large workers |

**Note:** `cx*` types are deprecated and being removed from ash location.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| kubelet exit 139 | ARM Mac generated configs | Regenerate from amd64 machine |
| etcd won't form quorum | Firewall blocking 2379-2380 | Add firewall rules |
| Connection refused | Using private IP (10.0.x.x) | Replace with public IP in kubeconfig |
| Nodes NotReady | CNI not ready | Wait 60s or install Cilium manually |
| Cross-node pod failures | Node name mismatch | See "Critical: Node Naming" above |

## Teardown

```bash
for node in talos-cp-1 talos-cp-2 talos-cp-3 talos-worker-1 talos-worker-2; do
  hcloud server delete $node 2>/dev/null
done
```

## Related Documentation

- [hub-cluster-setup.md](hub-cluster-setup.md) - Hub cluster for ArgoCD management
- [hub-recovery-runbook.md](hub-recovery-runbook.md) - Hub cluster recovery procedures
- [bootstrap-argocd.md](bootstrap-argocd.md) - ArgoCD installation
