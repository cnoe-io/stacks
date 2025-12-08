# Hetzner Cloud Talos Cluster Setup

Creates a 5-node Talos Kubernetes cluster on Hetzner Cloud (3 control plane + 2 workers).

## Prerequisites

- `hcloud` CLI with API token
- `talosctl` v1.11.5 (must run from **amd64 machine**, not ARM Mac)
- Azure infrastructure for Workload Identity (run `scripts/00-bootstrap-azure-infra.sh` first)

## Cluster Architecture

| Node | Type | vCPU | RAM | Role | Cost |
|------|------|------|-----|------|------|
| talos-cp-{1,2,3} | CPX21 | 3 | 4GB | control-plane | ~$9 ea |
| talos-worker-1 | CCX43 | 16 | 64GB | worker | ~$100 |
| talos-worker-2 | CCX33 | 8 | 32GB | worker | ~$50 |
| **Total** | | **32** | **108GB** | 5 nodes | **~$177/mo** |

## Quick Start

```bash
# 1. SSH to amd64 machine (CRITICAL - ARM Mac generates wrong image digests)
ssh hetzner

# 2. Set environment
cd ~/repos/PittampalliOrg/stacks/106-consolidate-bootstrap-between
source scripts/.env
export HCLOUD_TOKEN="your-token"

# 3. Generate Talos configs with OIDC issuer
cat > talos-configs/patches/oidc-issuer.yaml << EOF
cluster:
  apiServer:
    extraArgs:
      service-account-issuer: ${SERVICE_ACCOUNT_ISSUER}
EOF

talosctl gen config talos-cluster https://10.0.1.1:6443 \
  --kubernetes-version 1.32.0 \
  --install-image ghcr.io/siderolabs/installer:v1.11.5 \
  --with-secrets talos-configs/secrets.yaml \
  --config-patch @talos-configs/patches/oidc-issuer.yaml \
  --output talos-configs/ --force

# 4. Create servers
NETWORK_ID=$(hcloud network list -o noheader | awk '{print $1}')
TALOS_ISO_ID=122630

for i in 1 2 3; do
  hcloud server create --name talos-cp-$i --type cpx21 --location ash \
    --image ubuntu-24.04 --network $NETWORK_ID --start-after-create=false
done
hcloud server create --name talos-worker-1 --type ccx43 --location ash \
  --image ubuntu-24.04 --network $NETWORK_ID --start-after-create=false
hcloud server create --name talos-worker-2 --type ccx33 --location ash \
  --image ubuntu-24.04 --network $NETWORK_ID --start-after-create=false

# 5. Attach ISO and start
for node in talos-cp-1 talos-cp-2 talos-cp-3 talos-worker-1 talos-worker-2; do
  hcloud server attach-iso $node $TALOS_ISO_ID
  hcloud server poweron $node
done
sleep 60

# 6. Get IPs
CP1_IP=$(hcloud server describe talos-cp-1 -o format='{{.PublicNet.IPv4.IP}}')
CP2_IP=$(hcloud server describe talos-cp-2 -o format='{{.PublicNet.IPv4.IP}}')
CP3_IP=$(hcloud server describe talos-cp-3 -o format='{{.PublicNet.IPv4.IP}}')
W1_IP=$(hcloud server describe talos-worker-1 -o format='{{.PublicNet.IPv4.IP}}')
W2_IP=$(hcloud server describe talos-worker-2 -o format='{{.PublicNet.IPv4.IP}}')

# 7. Apply configs
talosctl config endpoints $CP1_IP $CP2_IP $CP3_IP --talosconfig talos-configs/talosconfig
for IP in $CP1_IP $CP2_IP $CP3_IP; do
  talosctl apply-config --insecure --nodes $IP --file talos-configs/controlplane.yaml
done
for IP in $W1_IP $W2_IP; do
  talosctl apply-config --insecure --nodes $IP --file talos-configs/worker.yaml
done
sleep 90

# 8. Detach ISO and reset
for node in talos-cp-1 talos-cp-2 talos-cp-3 talos-worker-1 talos-worker-2; do
  hcloud server detach-iso $node
  hcloud server reset $node
done
sleep 90

# 9. Bootstrap etcd
talosctl bootstrap --nodes $CP1_IP --talosconfig talos-configs/talosconfig
sleep 90

# 10. Get kubeconfig
talosctl kubeconfig --nodes $CP1_IP --talosconfig talos-configs/talosconfig --force talos-configs/kubeconfig
sed -i "s|https://10.0.1.1:6443|https://$CP1_IP:6443|" talos-configs/kubeconfig

# 11. Verify
KUBECONFIG=talos-configs/kubeconfig kubectl get nodes
# Expected: 5 nodes Ready
```

## Next Step

After cluster creation, run GitOps bootstrap:
```bash
cd scripts && ./bootstrap-argocd.sh
```

See [bootstrap-argocd.md](bootstrap-argocd.md) for details.

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| kubelet exit 139 | Generated configs from ARM Mac | Regenerate from amd64 machine |
| etcd won't form quorum | Firewall blocking 2379-2380 | Add firewall rules for CP IPs |
| kubeconfig connection refused | Using private IP (10.0.1.1) | Replace with public CP IP |
| Nodes NotReady | Flannel not started yet | Wait 60s, Flannel is built-in |

## Teardown

```bash
for node in talos-cp-1 talos-cp-2 talos-cp-3 talos-worker-1 talos-worker-2; do
  hcloud server delete $node
done
```
