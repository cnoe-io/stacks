# Hub Cluster Recovery Runbook

**Feature**: 108-hub-and-spoke
**Version**: 1.0
**Last Updated**: 2025-12-17

## Overview

This runbook documents recovery procedures for the hub cluster in the hub-and-spoke ArgoCD architecture. The hub cluster runs ArgoCD, Kargo, and centralized management workloads. Spoke clusters run application workloads.

### Key Design Principle

**Spoke workloads continue running during hub outage.** The hub only manages deployments - it doesn't run application traffic. Losing the hub means losing the ability to deploy changes, but existing workloads on spokes remain operational.

## Recovery Scenarios

| Scenario | Impact | RTO | Procedure |
|----------|--------|-----|-----------|
| Hub pod failure | ArgoCD temporarily unavailable | 5 min | Auto-heal (Kubernetes) |
| Hub node failure | ArgoCD unavailable | 15 min | Node replacement |
| Hub cluster failure | ArgoCD unavailable | 30-45 min | Full cluster reprovision |
| Spoke cluster failure | App workloads affected | Varies | Spoke-specific recovery |

## Pre-Requisites for Recovery

Before starting recovery, ensure you have:

1. **Hetzner Cloud credentials** (HCLOUD_TOKEN)
2. **Azure Key Vault access** for cluster secrets
3. **Git repository access** for GitOps manifests
4. **Tailscale admin access** for network configuration

## Spoke Continuity During Hub Outage

When the hub cluster is unavailable:

| Component | Behavior |
|-----------|----------|
| Spoke workloads | Continue running normally |
| Pod restarts | Handled by spoke kubelet |
| HPA scaling | Works on spoke |
| New deployments | BLOCKED - requires hub |
| Image updates | BLOCKED - requires hub |
| Kargo promotions | BLOCKED - requires hub |

**Important**: Spokes are self-sufficient for running workloads. Only management operations require the hub.

## Recovery Procedure

### Step 1: Assess the Situation

```bash
# Check if hub is reachable
curl -sI https://argocd-hub.tail286401.ts.net
# Expected: Connection refused or timeout if hub is down

# Verify spokes are still running
kubectl --context=thinkpad get pods -A | head -20
kubectl --context=ryzen get pods -A | head -20
kubectl --context=talos get pods -A | head -20
# Expected: Pods running normally on spokes
```

### Step 2: Determine Recovery Path

**If hub node exists but unresponsive:**
```bash
# Try Talos recovery first
export HUB_PUBLIC_IP=$(hcloud server describe hub-cp-1 -o json | jq -r '.public_net.ipv4.ip')
talosctl --talosconfig ~/.talos/hub-config --nodes $HUB_PUBLIC_IP reboot

# Wait 2-3 minutes, then check
talosctl --talosconfig ~/.talos/hub-config --nodes $HUB_PUBLIC_IP health
```

**If hub server must be replaced:**
Continue to Step 3.

### Step 3: Reprovision Hub Infrastructure

```bash
cd ~/repos/PittampalliOrg/talos-cluster

# Delete existing server (if exists)
hcloud server delete hub-cp-1 --force 2>/dev/null || true

# Reprovision infrastructure
./scripts/provision-hub.sh --force

# Note the new public IP
export HUB_PUBLIC_IP=$(hcloud server describe hub-cp-1 -o json | jq -r '.public_net.ipv4.ip')
echo "New hub public IP: $HUB_PUBLIC_IP"
```

### Step 4: Restore Hub Cluster

```bash
# Regenerate machine config with existing secrets
# (secrets are preserved in secrets/hub-secrets.yaml)
./scripts/gen-hub-config.sh

# Bootstrap the new cluster
./scripts/bootstrap-hub.sh $HUB_PUBLIC_IP

# Verify cluster health
export KUBECONFIG=~/.kube/hub-config
kubectl get nodes
# Expected: hub-cp-1 Ready
```

### Step 5: Restore GitOps Management

```bash
# ArgoCD and other management components are deployed via GitOps
# Apply the root application from your Git repository

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/PittampalliOrg/stacks.git
    path: 108-hub-and-spoke/cdk8s/dist
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# Wait for ArgoCD to sync
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### Step 6: Verify Spoke Reconnection

```bash
# ArgoCD should automatically reconnect to spokes
# (credentials are stored in Azure Key Vault and synced via ESO)

# Wait for ExternalSecrets to sync
sleep 60

# Check cluster secrets
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster
# Expected: cluster-hetzner, cluster-thinkpad, cluster-ryzen, cluster-talos

# Check ArgoCD connectivity
argocd cluster list --insecure
# Expected: All spokes showing "Connected"

# Verify applications are syncing
argocd app list --insecure
# Expected: All apps Synced or Syncing
```

### Step 7: Verify Kargo Pipelines

```bash
# Check Kargo project
kubectl get projects -n kargo-pipelines
# Expected: kargo-pipelines Ready

# Check warehouses
kubectl get warehouses -n kargo-pipelines
# Expected: All warehouses showing Ready

# Check stages
kubectl get stages -n kargo-pipelines
# Expected: All stages showing current Freight
```

## Post-Recovery Validation

Run the validation script to ensure full recovery:

```bash
./scripts/validate-hub-recovery.sh

# Expected output:
# ✅ Hub cluster healthy
# ✅ ArgoCD server running
# ✅ Tailscale connected
# ✅ ESO operator running
# ✅ All 4 spokes connected
# ✅ Kargo pipelines ready
# ✅ Applications syncing
```

## State Management

### What is Preserved

| State | Storage | Recovery |
|-------|---------|----------|
| Cluster secrets | `talos-cluster/secrets/hub-secrets.yaml` (git-crypt) | Reuse existing |
| Spoke credentials | Azure Key Vault | Automatic via ESO |
| ArgoCD apps | Git repository | Automatic via GitOps |
| Kargo freight | Kargo CRDs | Recreated from warehouses |
| Application state | Git repository | Automatic via GitOps |

### What is NOT Persisted

| State | Impact | Recovery |
|-------|--------|----------|
| In-flight promotions | Lost | Re-trigger manually |
| Pending syncs | Lost | Automatic re-sync |
| Dashboard sessions | Lost | Re-login |
| Metrics history | Lost | Starts fresh |

## Backup Recommendations

Since this is a GitOps architecture, the primary backup is **Git**:

1. **Git Repository**: All declarative state
2. **Azure Key Vault**: Secrets (spoke credentials, API keys)
3. **Hub Secrets File**: `talos-cluster/secrets/hub-secrets.yaml`

**etcd backup is NOT required** - all state is reconstructed from Git and Key Vault.

## Troubleshooting

### Spokes Not Reconnecting

```bash
# Check ExternalSecret status
kubectl describe externalsecret -n argocd spoke-credentials-thinkpad

# Check cluster secret
kubectl get secret cluster-thinkpad -n argocd -o yaml

# Manually test connectivity
kubectl run test-connectivity --rm -it --image=curlimages/curl -- \
  curl -sk https://k8s-api-thinkpad.tail286401.ts.net/healthz
```

### ArgoCD Sync Failures

```bash
# Check application events
kubectl describe application -n argocd <app-name>

# Force sync
argocd app sync <app-name> --insecure --force

# Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

### Tailscale Not Connecting

```bash
# Check Tailscale operator
kubectl logs -n tailscale -l app.kubernetes.io/name=tailscale-operator --tail=50

# Check auth key secret
kubectl get secret tailscale-operator-oauth -n tailscale

# Verify Tailscale admin console for device registration
```

## Recovery Time Objectives

| Component | RTO |
|-----------|-----|
| Hub cluster provisioning | 15 minutes |
| Talos bootstrap | 5 minutes |
| Cilium installation | 3 minutes |
| ArgoCD deployment | 5 minutes |
| ESO sync | 2 minutes |
| Spoke reconnection | 5 minutes |
| Full validation | 5 minutes |
| **Total RTO** | **40 minutes** |

## Contact and Escalation

For recovery assistance:
1. Check this runbook first
2. Review ArgoCD and Kargo logs
3. Escalate to platform team if RTO exceeded

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-17 | Initial runbook |
