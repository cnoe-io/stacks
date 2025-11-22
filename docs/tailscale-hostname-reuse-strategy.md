# Tailscale Hostname Reuse Strategy for Cluster Recreations

## Problem

When recreating the Kubernetes cluster, Tailscale proxy pods get new device IDs and the old devices remain in the Tailscale network as offline. Tailscale then appends `-1`, `-2`, etc. suffixes to avoid hostname conflicts.

Example:
- First deployment: `kagent.tail286401.ts.net`
- After cluster recreation: `kagent-1.tail286401.ts.net` (old device still exists but offline)
- After another recreation: `kagent-2.tail286401.ts.net`

## Root Cause

Tailscale devices are identified by their **device ID** (stored in Tailscale state), not by hostname. When a pod is deleted and recreated:

1. New pod gets fresh state (no device ID)
2. Pod registers as NEW device with Tailscale
3. Tailscale sees hostname conflict with old (offline) device
4. Tailscale appends suffix to resolve conflict

## Solutions

### Option 1: Persist Tailscale State (Recommended for Production)

**How it works:**
- Store Tailscale device state in a Kubernetes Secret or PVC
- Operator mounts state volume into proxy pods
- On recreation, pod reuses same device ID
- Tailscale recognizes it as same device, no suffix needed

**Implementation:**
```typescript
// In TailscaleSubnetRouterChart or similar
new k8s.KubePersistentVolumeClaim(this, 'state-pvc', {
  metadata: { name: 'tailscale-state', namespace },
  spec: {
    accessModes: ['ReadWriteOnce'],
    resources: { requests: { storage: k8s.Quantity.fromString('1Gi') } }
  }
});

// Mount in pod spec:
volumeMounts: [{
  name: 'state',
  mountPath: '/var/lib/tailscale'
}],
volumes: [{
  name: 'state',
  persistentVolumeClaim: { claimName: 'tailscale-state' }
}]
```

**Pros:**
- Canonical hostnames maintained across recreations
- Device appears as "same device reconnecting" in Tailscale
- Preserves Tailscale ACL tags and metadata

**Cons:**
- State tied to cluster (not portable across clusters)
- Requires persistent storage
- StatefulSets become stateful (can't easily scale horizontally)

**Use case:** Production environments with stable clusters

---

### Option 2: Auto-Delete Old Devices (Current Approach)

**How it works:**
- On cluster recreation, manually or automatically delete old offline devices from Tailscale
- Wait for Tailscale grace period (60-120 seconds)
- Recreate StatefulSets to get canonical hostnames

**Implementation:**
```bash
# Script: deployment/scripts/tailscale/cleanup-old-devices.sh
# 1. Get list of offline devices matching our patterns
# 2. Use Tailscale API with OAuth credentials to delete them
# 3. Wait 120 seconds for grace period
# 4. Delete and recreate StatefulSets
```

**Pros:**
- Clean slate on each recreation
- No persistent storage needed
- Simple to understand

**Cons:**
- Manual or scripted cleanup required
- Grace period creates deployment delay
- Old devices accumulate if cleanup forgotten

**Use case:** Development environments with frequent recreations

---

### Option 3: Accept Suffixed Hostnames (Pragmatic)

**How it works:**
- Accept that hostnames will have `-1`, `-2`, etc. suffixes
- Update documentation/scripts to use latest suffix
- Optionally, use Tailscale DNS search domains to avoid hardcoding

**Implementation:**
```bash
# Use MagicDNS without hardcoding suffix
curl https://kagent.tail286401.ts.net  # Fails (old offline device)
curl https://kagent-1.tail286401.ts.net  # Works

# Or use Tailscale service discovery
KAGENT_IP=$(tailscale status --json | jq -r '.Peer[] | select(.HostName | startswith("kagent")) | select(.Online) | .TailscaleIPs[0]')
curl http://$KAGENT_IP
```

**Pros:**
- Zero configuration changes
- Works immediately
- No cleanup needed

**Cons:**
- Non-canonical names
- Confusion about which suffix is current
- URLs change after each recreation

**Use case:** Quick demos, ephemeral environments

---

### Option 4: Use Stable Hostname Prefix (Hybrid Approach)

**How it works:**
- Configure operator to use `{clusterName}-{serviceName}` pattern
- Example: `kind-kagent.tail286401.ts.net` instead of `kagent.tail286401.ts.net`
- On recreation, different cluster name = different hostname = no conflict

**Implementation:**
```typescript
// In LoadBalancer service annotation
metadata: {
  annotations: {
    'tailscale.com/hostname': `${clusterName}-${serviceName}`  // e.g., "kind-kagent"
  }
}
```

**Pros:**
- No cleanup needed
- Hostnames indicate cluster identity
- Supports multiple clusters simultaneously

**Cons:**
- Longer hostnames
- Need to update all references when cluster name changes
- Doesn't solve problem if cluster name is stable

**Use case:** Multi-cluster environments, staging vs production

---

## Recommended Approach by Environment

### Development (Local Kind)
**Option 2: Auto-Delete Old Devices**
- Script: `deployment/scripts/cluster-cleanup.sh` runs on `cluster-create`
- Deletes old devices via Tailscale API
- Waits for grace period before deploying operator

### Staging/Testing
**Option 4: Stable Hostname Prefix**
- Use cluster name in hostnames: `staging-kagent`, `testing-kagent`
- Allows parallel testing without conflicts
- Easy to identify which cluster a device belongs to

### Production
**Option 1: Persist Tailscale State**
- Use PersistentVolumeClaims for operator proxy state
- Backup state to external storage (Azure Blob, S3)
- On disaster recovery, restore state to maintain same device IDs

---

## Implementation for Kind Clusters

### Automated Cleanup on Cluster Creation

Integrated into `deployment/scripts/cluster-menu.sh`:

```bash
cluster-recreate() {
  # Delete old Tailscale devices before recreating cluster
  if command -v tailscale &>/dev/null; then
    echo "Cleaning up old Tailscale devices..."
    # No --wait flag - grace period elapses during cluster creation
    bash deployment/scripts/tailscale/cleanup-old-devices.sh
  fi

  # Delete existing cluster
  idpbuilder delete

  # Create cluster (2-5 minutes - grace period naturally elapses)
  cluster-deploy
}
```

**Performance Optimization:**
- Cleanup runs without blocking wait
- Cluster creation (2-5 min) exceeds grace period (120 sec)
- Saves ~2 minutes from total recreation time
- Canonical hostnames guaranteed when Tailscale operator deploys


### Cleanup Script

```bash
#!/bin/bash
# deployment/scripts/tailscale/cleanup-old-devices.sh

# Get OAuth credentials from 1Password or environment
CLIENT_ID=$(op read "op://Private/tailscale-oauth/client-id")
CLIENT_SECRET=$(op read "op://Private/tailscale-oauth/client-secret")

# Get OAuth token
TOKEN=$(curl -s -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  https://api.tailscale.com/api/v2/oauth/token | jq -r '.access_token')

# Get list of offline devices matching our patterns
DEVICES=$(tailscale status --json | jq -r '.Peer[] |
  select(.HostName | test("^(kagent|gitea|argocd|agentgateway|keycloak|headlamp|cnoe|kargo)$")) |
  select(.Online == false) | .ID')

# Delete each device
for DEVICE_ID in $DEVICES; do
  echo "Deleting device: $DEVICE_ID"
  curl -s -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://api.tailscale.com/api/v2/device/${DEVICE_ID}"
done

echo "Deleted $(echo "$DEVICES" | wc -l) old devices"
```

---

## Current Status

- **Implemented:** Option 2 (manual cleanup via API)
- **Old devices:** Successfully deleted (kagent, gitea, argocd, etc.)
- **Current devices:** Using `-1` suffix due to grace period
- **Next step:** Wait 2-3 minutes, then recreate StatefulSets for canonical names

## Future Enhancements

1. **Automation Hook:** Add pre-cluster-create hook to auto-cleanup old devices
2. **State Persistence:** Implement PVC-based state storage for production
3. **Monitoring:** Alert when offline devices accumulate (>10 devices)
4. **DNS Aliases:** Create Tailscale DNS aliases for stable references regardless of suffix
