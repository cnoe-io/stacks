# RustDesk Connection Guide for NixOS KubeVirt VM

## Summary

The Tailscale LoadBalancer approach doesn't work in Kind clusters due to missing iptables NAT support. However, you can use the **Tailscale subnet router** to access the VM directly via its pod IP.

## Direct IP Access (Recommended)

### VM Pod IP
```
10.244.0.59
```

### Prerequisites
1. Your device (M1 Mac) must be connected to the Tailscale network
2. The subnet router must have advertised routes approved in Tailscale admin console

### Check if Routes are Approved

From the Hetzner machine:
```bash
# Get the subnet router's Tailscale hostname
kubectl logs -n tailscale tailscale-subnet-router | grep -i hostname

# Or check Tailscale status
kubectl exec -n tailscale tailscale-subnet-router -- tailscale status
```

Then visit: https://login.tailscale.com/admin/machines
- Find the "tailscale-subnet-router" device
- Approve the subnet routes: `10.244.0.0/16` and `10.96.0.0/16` if not already approved

### RustDesk Connection

Once subnet routes are approved:

**From your M1 Mac (or any Tailscale-connected device):**
1. Open RustDesk
2. Connect to: **`10.244.0.59:21116`**
3. Get RustDesk ID and password (see below)

## Getting RustDesk Credentials

### Method 1: Via SSH

From Hetzner machine:
```bash
# Port-forward SSH
kubectl port-forward -n default svc/nixos-dev-vm-rdp 2222:22 &

# Connect and get credentials
ssh -p 2222 nixos@localhost 'cat ~/.config/rustdesk/RustDesk.toml' | grep -E "(^id = |^password = )"

# Cleanup
kill %1
```

### Method 2: Via RDP

From Hetzner machine:
```bash
# Port-forward RDP
kubectl port-forward -n default svc/nixos-dev-vm-rdp 3389:3389
```

Then on your local machine (M1 Mac):
```bash
# Create SSH tunnel to Hetzner
ssh -L 3389:localhost:3389 vpittamp@100.87.204.44
```

Connect with Microsoft Remote Desktop to `localhost:3389`:
- Username: `nixos`
- Password: `nixos123`

Once connected, open Konsole and run:
```bash
cat ~/.config/rustdesk/RustDesk.toml | grep -E "(^id = |^password = )"
```

## Alternative Connection Methods

### Method 1: Port-Forward (For Testing)

From Hetzner machine:
```bash
kubectl port-forward -n default svc/nixos-dev-vm-rdp 21116:21116
```

Then on your local machine (M1 Mac):
```bash
ssh -L 21116:localhost:21116 vpittamp@100.87.204.44
```

Connect RustDesk to: `localhost:21116`

### Method 2: NodePort (From Hetzner Only)

From Hetzner machine, connect directly to Kind node:
```
172.18.0.2:32076
```

This only works from the Hetzner machine because it's the Kind node IP.

## Why LoadBalancer Doesn't Work

The Tailscale LoadBalancer requires iptables NAT table support, which is not available in Kind clusters by default. The error was:

```
iptables v1.8.10 (legacy): can't initialize iptables table `nat': Table does not exist
```

**Solutions considered:**
1. ✗ Enable NAT in Kind config - requires cluster recreation
2. ✓ **Use subnet router** - works without changes
3. ✓ Use port-forward - works for testing

The subnet router approach is best because it provides direct access to all pod IPs without port-forwarding.

## Troubleshooting

### Subnet routes not working?

Check if routes are approved:
```bash
# From Hetzner
kubectl exec -n tailscale tailscale-subnet-router -- tailscale status

# Check advertised routes
kubectl exec -n tailscale tailscale-subnet-router -- tailscale status --json | jq '.Self.AllowedIPs'
```

### RustDesk not listening?

Check if RustDesk service is running:
```bash
# Via console (requires VM to be responsive)
virtctl console nixos-dev-vm -n default

# Login as: nixos / nixos123
# Then run:
systemctl --user status rustdesk
```

### VM not accessible?

Check VM status:
```bash
kubectl get vm,vmi -n default
kubectl get svc nixos-dev-vm-rdp -n default
```

VM should show:
- VM Status: Running
- VMI Phase: Running
- Service: Has NodePort mappings

## Current Configuration

- **VM IP**: 10.244.0.59
- **RustDesk Port**: 21116
- **SSH Port**: 22
- **RDP Port**: 3389
- **NodePort (RustDesk)**: 32076
- **NodePort (SSH)**: 31274
- **NodePort (RDP)**: 32284

## Next Steps

1. Approve subnet routes in Tailscale admin console
2. Test direct access from M1 Mac: `nc -zv 10.244.0.59 21116`
3. Get RustDesk credentials via SSH or RDP
4. Connect with RustDesk to `10.244.0.59:21116`

---

**Note**: The Tailscale LoadBalancer RBAC was fixed (Role updated to point to correct secret), but the underlying iptables NAT limitation in Kind prevents it from working. The subnet router approach is the recommended solution.
