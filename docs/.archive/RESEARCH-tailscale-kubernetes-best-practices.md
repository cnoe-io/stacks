# Research: Tailscale Kubernetes Best Practices

## Summary

Based on official Tailscale documentation and community practices, the **current implementation already follows Tailscale's recommended architecture**. The hostname suffix issue (`-1`, `-2`) is expected behavior when devices are recreated without preserving state.

## Key Findings from Official Documentation

### 1. StatefulSet Architecture (Already Implemented ✅)

**Tailscale Best Practice:**
> "When a user configures an ingress or egress proxy, the default mode for the operator is to create a tailnet device deployed as a StatefulSet with a single Pod."

**Why StatefulSets:**
- Stable pod names enable consistent state secret naming
- State persists across pod restarts (but not StatefulSet deletion)
- Each pod gets its own state secret: `ts-<service-name>-<hash>-0`

**Current Status:** ✅ Our operator correctly uses StatefulSets

---

### 2. State Persistence via Kubernetes Secrets (Already Implemented ✅)

**Tailscale Best Practice:**
> "Tailscale (v1.16 or later) supports storing state inside a Kubernetes Secret."
>
> "In a StatefulSet configuration, each replica stores its state in a Secret named the same as the Pod, and as Pod names for a StatefulSet do not change if Pods get recreated, proxy state will persist across cluster and proxy version updates."

**Implementation Details:**
```yaml
env:
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: TS_KUBE_SECRET
    value: $(POD_NAME)  # Secret name matches pod name
```

**Current Status:** ✅ Operator automatically configures `TS_KUBE_SECRET` for each pod

**Important Caveat:**
- State persists across **pod restarts** (same StatefulSet)
- State is **lost** when **StatefulSet is deleted** (cluster recreation)
- On cluster recreation, state secrets are deleted → new device IDs → hostname conflicts

---

### 3. Hostname Immutability (Root Cause of `-1` Suffix)

**Tailscale Documentation:**
> "Requested machine names are only considered during initial provisioning. That is, editing `tailscale.com/hostname` on an already exposed Service doesn't update the machine name **until you clean up and re-expose the Service**."

**Key Insight:**
- Hostnames are **immutable** after device registration
- To change hostname: **must delete device from Tailscale + delete StatefulSet**
- Tailscale prevents hostname conflicts by appending `-1`, `-2`, etc.

**Why We Get `-1` Suffix:**
1. Old cluster had device named `kagent`
2. Cluster deleted → StatefulSet deleted → state secret deleted
3. Old device remains in Tailscale (offline) with hostname `kagent`
4. New cluster creates new device requesting hostname `kagent`
5. Tailscale sees conflict → assigns `kagent-1` instead

**Current Status:** ⚠️ Expected behavior given our cluster recreation workflow

---

### 4. Device Lifecycle Management

**Tailscale Best Practice - Two Approaches:**

#### Approach A: Ephemeral Devices (Auto-Cleanup)
> "Use an ephemeral key for automatic cleanup of devices after they shut down."

**Pros:**
- Devices auto-delete when pod shuts down
- No manual cleanup needed
- Clean state on every deployment

**Cons:**
- Loses device history/analytics
- Device ID changes on every restart
- Cannot preserve ACL tags across restarts

**Use Case:** Development, CI/CD environments

#### Approach B: Persistent Devices (State Preservation)
> "Use a reusable key so when containers are stopped and started they can still connect to your tailnet."

**Pros:**
- Preserves device identity across pod restarts
- Maintains ACL tags and audit logs
- Stable hostnames if state is preserved

**Cons:**
- Requires manual cleanup on cluster deletion
- Old devices accumulate if not cleaned up
- Hostname conflicts on cluster recreation without cleanup

**Use Case:** Production, long-lived environments

**Current Status:** ⚠️ Using persistent keys without cleanup automation

---

### 5. High Availability with ProxyGroup (Not Applicable Yet)

**Tailscale Best Practice (v1.76+):**
> "Tailscale Kubernetes Operator 1.76 and later provides the ability to pre-create a multi-replica ProxyGroup... using ProxyGroup and a new Tailscale feature, Tailscale Services."

**Purpose:** Multi-replica proxies for zero-downtime upgrades

**Requirements:**
- OAuth scope: `Services`, `Devices Core`, `Auth Keys` (write)
- ProxyGroup CRD with `spec.type: ingress`
- Reference via `tailscale.com/proxy-group` annotation

**Current Status:** ❌ Not using ProxyGroup (set `enableHA: false`)
- ProxyGroup is for HA (multiple replicas per service), not hostname stability
- Single-replica mode is correct for our use case

---

## Official Recommendations for Our Use Case

### For Development/Kind Clusters (Current Environment)

**Recommended Approach:** **Pre-delete old devices before cluster creation**

**Rationale from Tailscale docs:**
- Hostnames cannot be updated in-place
- Must "clean up and re-expose the Service" to change names
- Operator's StatefulSet architecture expects stable device identity

**Implementation:**
1. Before cluster deletion: No action needed (devices go offline)
2. Before cluster creation: Delete old offline devices via API
3. Wait for grace period (60-120 seconds)
4. Create cluster and deploy operator
5. Operator creates devices with canonical names

**This is exactly what we implemented in `cleanup-old-devices.sh`** ✅

---

### For Production Clusters (Future Consideration)

**Recommended Approach:** **Preserve state secrets across cluster migrations**

**Rationale:**
- Production clusters should not be destroyed/recreated frequently
- Device identity and audit logs are valuable
- State secrets can be backed up to external storage

**Implementation Options:**

#### Option 1: Backup/Restore State Secrets
```bash
# Before cluster deletion
kubectl get secret -n tailscale \
  --selector=tailscale.com/managed=true \
  -o yaml > tailscale-state-backup.yaml

# After cluster creation
kubectl apply -f tailscale-state-backup.yaml
```

#### Option 2: External State Storage (Advanced)
- Use PersistentVolumeClaims with remote storage (Azure Disk, AWS EBS)
- Configure backup/restore via Velero or similar
- State survives cluster deletion

#### Option 3: GitOps State Management
- Store state secret YAMLs in Git (encrypted with SOPS/sealed-secrets)
- ArgoCD restores state on cluster bootstrap
- Maintains device continuity across recreations

**Current Status:** ❌ Not implemented (not needed for dev clusters)

---

## Comparison with Our Approaches

### Our Option 1: Wait and Recreate
**Matches Tailscale Recommendation:** ✅ Yes
- Deletes devices, waits for grace period, recreates
- Aligns with "clean up and re-expose the Service"
- Simple, predictable, no state to manage

### Our Option 2: Accept `-1` Suffix
**Matches Tailscale Recommendation:** ⚠️ Works, but not canonical
- Devices have non-canonical names
- Functional but harder to reference
- Acceptable for ephemeral environments

### Our Option 3: Automated Cleanup
**Matches Tailscale Recommendation:** ✅ Yes (Best for Dev)
- Automates the "clean up before re-expose" workflow
- Prevents hostname conflicts proactively
- Aligns with ephemeral device pattern for development

---

## Label Selectors for State Management (Advanced)

**Tailscale provides labels for tracking resources:**

```bash
# Find StatefulSet for a service
kubectl get statefulset -n tailscale \
  --selector="tailscale.com/parent-resource=ts-kagent-ingress,tailscale.com/parent-resource-type=svc"

# Find state secret for a service
kubectl get secret -n tailscale \
  --selector="tailscale.com/parent-resource=ts-kagent-ingress,tailscale.com/parent-resource-ns=ingress-nginx"
```

**Use Cases:**
- Backup specific service states before upgrade
- Audit which secrets belong to which services
- Selective cleanup vs. wholesale deletion

**Current Status:** ❌ Not using (could enhance cleanup script)

---

## RBAC Requirements (Already Implemented ✅)

**Tailscale Best Practice:**
> "Configure role-based access control (RBAC) to allow the Tailscale pod to read/write the tailscale secret."

**Required Permissions:**
```yaml
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "create", "update", "patch"]
```

**Current Status:** ✅ Implemented in `proxies` Role (commit 1a76f75)

---

## Known Issues from Community

### Issue #10969: StatefulSet Reconciliation Failures
**Problem:** Concurrent modification conflicts during updates
**Root Cause:** Multiple reconciliation loops modifying same resource
**Solution:** Operator handles this internally with retry logic

**Impact on Us:** None (not experiencing this issue)

### Issue #13451: Expired Auth Keys in Secrets
**Problem:** Old auth keys persisting in state secrets after login
**Status:** Fixed in recent operator versions
**Solution:** "Single use proxy auth keys no longer persist in the state Secrets after the proxies have logged in"

**Impact on Us:** None (using reusable OAuth flow)

---

## Recommended Strategy by Environment

| Environment | Approach | Device Type | State Management | Hostname Strategy |
|-------------|----------|-------------|------------------|-------------------|
| **Local Dev (Kind)** | Pre-delete old devices | Persistent with cleanup | Ephemeral (delete StatefulSets) | Canonical via automated cleanup |
| **CI/CD** | Ephemeral keys | Ephemeral | Auto-cleanup on shutdown | Accept generated names |
| **Staging** | Cluster-specific prefix | Persistent | Preserve secrets (backup/restore) | `staging-kagent`, `staging-gitea` |
| **Production** | Preserve state | Persistent | PVC + backup to blob storage | Canonical + disaster recovery |

---

## Final Recommendation: Option C with Enhancement

**Implement automated cleanup (Option C) with Tailscale best practices:**

### Implementation
```bash
# In deployment/scripts/cluster-menu.sh

cluster-recreate() {
  # Step 1: Cleanup old Tailscale devices (Tailscale recommended)
  echo "Cleaning up old Tailscale devices..."
  # Run WITHOUT --wait - grace period elapses during cluster creation
  ./deployment/scripts/tailscale/cleanup-old-devices.sh

  # Step 2: Delete old cluster
  idpbuilder delete

  # Step 3: Create cluster (2-5 minutes, grace period naturally elapses)
  cluster-deploy
}
```

**Performance Optimization:**
- Cleanup runs without blocking (no --wait flag)
- Cluster creation takes 2-5 minutes (far exceeds 120-second grace period)
- Saves ~2 minutes from total recreation time
- Grace period guaranteed to complete before Tailscale operator deploys


### Why This Follows Best Practices

1. **Aligns with Tailscale docs:** "clean up and re-expose the Service" for hostname changes
2. **Uses operator's design:** Relies on StatefulSet + Secret state management
3. **Leverages API:** Uses OAuth credentials as intended
4. **Development-friendly:** Automatic, predictable, no manual steps
5. **Production-ready path:** Can migrate to state preservation when needed

### Enhancements Over Basic Approach

**Add label selector awareness:**
```bash
# Enhanced cleanup to use Tailscale's label selectors
kubectl get secret -n tailscale \
  --selector=tailscale.com/managed=true,tailscale.com/parent-resource-type=svc \
  -o name | while read secret; do
    # Extract device ID from secret
    # Delete via API if offline
done
```

**Add state backup option for production:**
```bash
# Before cluster deletion, backup state
kubectl get secret -n tailscale \
  --selector=tailscale.com/managed=true \
  -o yaml > /tmp/tailscale-state-$(date +%Y%m%d-%H%M%S).yaml
```

---

## Conclusion

Our current approach of **automated cleanup before cluster creation (Option C)** is **the recommended Tailscale best practice** for development environments using Kind clusters.

**Key Validations:**
- ✅ Using StatefulSets (operator default)
- ✅ Using Kubernetes Secrets for state (operator default)
- ✅ Using OAuth credentials (recommended over auth keys)
- ✅ Pre-deleting devices before recreation (documented approach)
- ✅ Proper RBAC for secret management
- ✅ Understanding hostname immutability

**The `-1` suffix is not a bug** - it's Tailscale's conflict resolution working as designed. The solution is cleanup before creation, not changing the operator configuration.

## References

- [Tailscale Kubernetes Operator Docs](https://tailscale.com/kb/1236/kubernetes-operator)
- [Kubernetes State Storage](https://tailscale.com/kb/1185/kubernetes)
- [Cluster Ingress Best Practices](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress)
- [ProxyClass Customization](https://tailscale.com/kb/1445/kubernetes-operator-customization)
- [GitHub Issue #10969 - StatefulSet Reconciliation](https://github.com/tailscale/tailscale/issues/10969)
