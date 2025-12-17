# Quickstart: Hub-and-Spoke ArgoCD Setup

**Feature**: 108-hub-and-spoke
**Time Required**: ~45 minutes
**Prerequisites**: Hetzner Cloud account, Azure Key Vault access, Tailscale tailnet

## Overview

This guide walks through setting up a dedicated Talos hub cluster and registering spoke clusters for centralized ArgoCD management.

```
Phase 1: Provision Hub Cluster (15 min)
    ↓
Phase 2: Bootstrap GitOps on Hub (10 min)
    ↓
Phase 3: Register Spoke Clusters (15 min)
    ↓
Phase 4: Deploy Cross-Cluster Application (5 min)
```

---

## Phase 1: Provision Hub Cluster

### 1.1 Using Automation Scripts (Recommended)

The hub cluster provisioning is fully automated with scripts:

```bash
# Navigate to talos-cluster repo
cd ~/repos/PittampalliOrg/talos-cluster

# Set required environment variables
export HCLOUD_TOKEN="your-hetzner-api-token"

# Step 1: Provision Hetzner infrastructure
# Creates: CX32 server, private network (10.1.0.0/16), firewall, attaches Talos ISO
./scripts/provision-hub.sh

# Note the public IP from output:
# export HUB_PUBLIC_IP=<output-ip>

# Step 2: Generate Talos machine configuration
# Creates: secrets, controlplane.yaml, talosconfig
./scripts/gen-hub-config.sh

# Step 3: Bootstrap the cluster
# Applies config, bootstraps etcd, installs Cilium, exports kubeconfig
./scripts/bootstrap-hub.sh $HUB_PUBLIC_IP

# Verify cluster
export KUBECONFIG=~/.kube/hub-config
kubectl get nodes
# Expected: hub-cp-1 Ready control-plane
```

### 1.2 Manual Steps (Alternative)

If you prefer manual control, follow these steps:

<details>
<summary>Click to expand manual provisioning steps</summary>

#### Prepare Hub Configuration

```bash
# The hub patch already exists at:
# talos-cluster/main/patches/controlplane/hub.yaml
```

#### Provision Hetzner Infrastructure

```bash
# Set environment variables
export HCLOUD_TOKEN="your-hetzner-api-token"
export HUB_NODE_TYPE="cx32"  # 4 vCPU, 8GB RAM

# Create hub server (stopped, with Talos ISO)
hcloud server create \
  --name hub-cp-1 \
  --type $HUB_NODE_TYPE \
  --image ubuntu-24.04 \
  --location ash \
  --start-after-create=false

# Attach Talos ISO
hcloud server attach-iso hub-cp-1 122630

# Create private network
hcloud network create --name hub-cluster-net --ip-range 10.1.0.0/16
hcloud network add-subnet hub-cluster-net --type cloud --network-zone us-east --ip-range 10.1.1.0/24

# Attach server to network
hcloud server attach-to-network hub-cp-1 --network hub-cluster-net --ip 10.1.1.1

# Create firewall
hcloud firewall create --name hub-cluster-fw
hcloud firewall add-rule hub-cluster-fw --direction in --protocol tcp --port 6443 --source-ips 0.0.0.0/0
hcloud firewall add-rule hub-cluster-fw --direction in --protocol tcp --port 50000 --source-ips 0.0.0.0/0
hcloud firewall add-rule hub-cluster-fw --direction in --protocol udp --port 41641 --source-ips 0.0.0.0/0
hcloud firewall apply-to-server hub-cluster-fw --server hub-cp-1

# Start server (boots into Talos maintenance mode)
hcloud server poweron hub-cp-1

# Get public IP
HUB_PUBLIC_IP=$(hcloud server describe hub-cp-1 -o json | jq -r '.public_net.ipv4.ip')
echo "Hub public IP: $HUB_PUBLIC_IP"
```

#### Generate and Apply Machine Config

```bash
# Generate hub cluster secrets
talosctl gen secrets -o secrets/hub-secrets.yaml

# Generate machine config
talosctl gen config hub-cluster https://10.1.1.1:6443 \
  --with-secrets secrets/hub-secrets.yaml \
  --config-patch @main/patches/common.yaml \
  --config-patch-control-plane @main/patches/controlplane/hub.yaml \
  --kubernetes-version 1.32.0 \
  --output-dir generated/hub

# Validate config
talosctl validate --mode cloud --config generated/hub/controlplane.yaml

# Apply config to hub node
talosctl apply-config --insecure \
  --nodes $HUB_PUBLIC_IP \
  --file generated/hub/controlplane.yaml

# Wait for installation (2-3 minutes)
sleep 180

# Detach ISO and reset
hcloud server detach-iso hub-cp-1
hcloud server reset hub-cp-1

# Wait for reboot
sleep 60
```

#### Bootstrap Cluster

```bash
# Set talosconfig endpoint
export TALOSCONFIG=~/.talos/hub-config
talosctl config merge generated/hub/talosconfig

# Bootstrap etcd
talosctl bootstrap --nodes $HUB_PUBLIC_IP

# Wait for Kubernetes API
talosctl health --nodes $HUB_PUBLIC_IP --wait-timeout 5m

# Get kubeconfig
talosctl kubeconfig --nodes $HUB_PUBLIC_IP -f ~/.kube/hub-config

# Verify cluster
export KUBECONFIG=~/.kube/hub-config
kubectl get nodes
# Expected: hub-cp-1 Ready control-plane 1/1
```

#### Install Cilium CNI

```bash
# Install Cilium
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --version 1.16.4 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set hubble.enabled=false

# Wait for Cilium
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cilium-agent -n kube-system --timeout=300s

# Verify node is Ready
kubectl get nodes
# Expected: hub-cp-1 Ready
```

</details>

**Checkpoint**: Hub cluster running with 1 Ready node.

---

## Phase 2: Bootstrap GitOps on Hub

### 2.1 Install ArgoCD

```bash
# Create argocd namespace
kubectl create namespace argocd

# Install ArgoCD with hub-optimized values
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.3.0 \
  --set server.replicas=1 \
  --set controller.replicas=1 \
  --set repoServer.replicas=1 \
  --set server.extraArgs[0]="--insecure" \
  --set applicationSet.enabled=true

# Wait for ArgoCD
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Get admin password
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: $ARGOCD_PASSWORD"
```

### 2.2 Install Tailscale Operator

```bash
# Store Tailscale OAuth credentials in secret
kubectl create namespace tailscale
kubectl create secret generic tailscale-operator-oauth \
  --namespace tailscale \
  --from-literal=client-id="$TAILSCALE_CLIENT_ID" \
  --from-literal=client-secret="$TAILSCALE_CLIENT_SECRET"

# Install Tailscale operator
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm install tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale \
  --set oauth.clientId="$TAILSCALE_CLIENT_ID" \
  --set oauth.clientSecret="$TAILSCALE_CLIENT_SECRET" \
  --set apiServerProxyConfig.mode=true

# Wait for operator
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tailscale-operator -n tailscale --timeout=300s
```

### 2.3 Expose ArgoCD via Tailscale

```bash
# Create Tailscale serve for ArgoCD
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: argocd-tailscale-serve
  namespace: tailscale
  labels:
    app: argocd-tailscale-serve
spec:
  serviceAccountName: tailscale-operator
  containers:
    - name: tailscale
      image: ghcr.io/tailscale/tailscale:latest
      env:
        - name: TS_KUBE_SECRET
          value: argocd-serve-state
        - name: TS_USERSPACE
          value: "true"
        - name: TS_SERVE_CONFIG
          value: /config/serve-config.json
        - name: TS_EXTRA_ARGS
          value: "--service=argocd-hub"
      volumeMounts:
        - name: config
          mountPath: /config
  volumes:
    - name: config
      configMap:
        name: argocd-serve-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-serve-config
  namespace: tailscale
data:
  serve-config.json: |
    {
      "TCP": {
        "443": {
          "HTTPS": true
        }
      },
      "Web": {
        "${TS_CERT_DOMAIN}:443": {
          "Handlers": {
            "/": {
              "Proxy": "http://argocd-server.argocd.svc.cluster.local:80"
            }
          }
        }
      }
    }
EOF

# Verify Tailscale service
# ArgoCD should be accessible at https://argocd-hub.<tailnet>.ts.net
```

### 2.4 Install External Secrets Operator

```bash
# Install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true

# Wait for ESO
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets -n external-secrets --timeout=300s

# Create ClusterSecretStore for Azure Key Vault
kubectl apply -f - << EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault-store
spec:
  provider:
    azurekv:
      tenantId: "$AZURE_TENANT_ID"
      vaultUrl: "https://$AZURE_KEYVAULT_NAME.vault.azure.net"
      authType: WorkloadIdentity
      serviceAccountRef:
        name: external-secrets
        namespace: external-secrets
EOF
```

**Checkpoint**: ArgoCD accessible at `https://argocd-hub.<tailnet>.ts.net`.

---

## Phase 3: Register Spoke Clusters

### 3.1 Bootstrap Spoke ServiceAccount

Use the spoke helper library to manage spoke credentials:

```bash
# Navigate to stacks repo
cd ~/repos/PittampalliOrg/stacks/108-hub-and-spoke

# Source spoke helpers
source scripts/lib/spoke-helpers.sh

# Set Azure Key Vault name
export AZURE_KEYVAULT_NAME="idp-kv"

# For each spoke cluster, run these commands
# (ensure kubectl context is set to the spoke cluster)

# Register thinkpad spoke
kubectl config use-context thinkpad
create_spoke_service_account thinkpad
export_credentials_to_keyvault thinkpad

# Register ryzen spoke
kubectl config use-context ryzen
create_spoke_service_account ryzen
export_credentials_to_keyvault ryzen

# Register hetzner spoke
kubectl config use-context hetzner
create_spoke_service_account hetzner
export_credentials_to_keyvault hetzner

# Register talos spoke
kubectl config use-context talos
create_spoke_service_account talos
export_credentials_to_keyvault talos

# Verify all credentials stored
list_spoke_credentials
```

**Available spoke-helpers functions:**

| Function | Description |
|----------|-------------|
| `create_spoke_service_account <spoke>` | Create ArgoCD manager ServiceAccount on spoke |
| `generate_spoke_token <spoke>` | Generate long-lived bearer token |
| `get_spoke_ca <spoke>` | Extract cluster CA certificate |
| `export_credentials_to_keyvault <spoke>` | Store credentials in Azure Key Vault |
| `verify_spoke_connectivity <spoke>` | Test Tailscale connectivity to spoke |
| `list_spoke_credentials` | List all spoke credentials in Key Vault |

**Valid spoke names:** hetzner, thinkpad, ryzen, talos

### 3.2 Create ExternalSecrets for Spoke Credentials

On the hub cluster:

```bash
# Create ExternalSecrets for each spoke
for SPOKE in thinkpad ryzen hetzner talos; do
  kubectl apply -f - << EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-cluster-$SPOKE
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: azure-keyvault-store
  target:
    name: cluster-$SPOKE
    template:
      metadata:
        labels:
          argocd.argoproj.io/secret-type: cluster
          cluster-host: $SPOKE
      data:
        name: $SPOKE
        server: https://k8s-api-$SPOKE.tail286401.ts.net
        config: |
          {
            "tlsClientConfig": {
              "insecure": false,
              "caData": "{{ .caData }}"
            },
            "bearerToken": "{{ .bearerToken }}"
          }
  data:
    - secretKey: bearerToken
      remoteRef:
        key: ARGOCD-CLUSTER-${SPOKE^^}-TOKEN
    - secretKey: caData
      remoteRef:
        key: ARGOCD-CLUSTER-${SPOKE^^}-CA
EOF
done
```

### 3.3 Verify Spoke Registration

```bash
# Check ExternalSecrets synced
kubectl get externalsecrets -n argocd
# Expected: All showing status "SecretSynced"

# Check cluster secrets
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster
# Expected: cluster-thinkpad, cluster-ryzen, cluster-hetzner, cluster-talos

# Verify in ArgoCD
argocd cluster list --insecure
# Expected: All spokes showing as "Connected"
```

**Checkpoint**: All 4 spoke clusters registered and connected.

---

## Phase 4: Deploy Cross-Cluster Application

### 4.1 Update ApplicationConfig

Add to `cdk8s/config/applications.ts`:

```typescript
// Spoke registration (on hub)
{
  name: 'argocd-cluster-thinkpad',
  namespace: 'argocd',
  chart: {
    type: 'ArgocdClusterSecretChart',
    props: { clusterName: 'thinkpad' }
  },
  argocd: {
    syncWave: '-80',
    targetCluster: 'hub'
  }
},

// Application targeting spoke
{
  name: 'backstage-dev',
  namespace: 'backstage',
  chart: {
    type: 'BackstageChart',
    props: { environment: 'dev' }
  },
  argocd: {
    syncWave: '100',
    targetCluster: 'thinkpad',
    labels: {
      'app.kubernetes.io/environment': 'dev'
    }
  }
}
```

### 4.2 Synthesize and Deploy

```bash
# Synthesize manifests
cd ~/repos/PittampalliOrg/stacks/108-hub-and-spoke/cdk8s
npm run synth

# Apply to hub ArgoCD
kubectl apply -f dist/backstage-dev.yaml

# Verify application synced to spoke
argocd app get argocd/backstage-dev --insecure
# Expected: Status: Synced, Health: Healthy, Destination: thinkpad
```

### 4.3 Verify Cross-Cluster Deployment

```bash
# Check pods on spoke cluster
kubectl --context=thinkpad get pods -n backstage
# Expected: backstage-xxx Running

# Access backstage via spoke's Tailscale URL
curl -I https://backstage.thinkpad.tail286401.ts.net
# Expected: HTTP/2 200
```

**Checkpoint**: Application deployed to spoke cluster via hub ArgoCD.

---

## Verification Checklist

| Item | Command | Expected |
|------|---------|----------|
| Hub cluster healthy | `kubectl get nodes` | hub-cp-1 Ready |
| ArgoCD running | `kubectl get pods -n argocd` | All pods Running |
| Tailscale connected | `tailscale status` | Hub in tailnet |
| ESO syncing | `kubectl get externalsecrets -A` | All SecretSynced |
| Spokes registered | `argocd cluster list --insecure` | 4 clusters Connected |
| Cross-cluster app | `argocd app get backstage-dev` | Synced, Healthy |

---

## Troubleshooting

### Hub Cluster Issues

```bash
# Check Talos health
talosctl health --nodes $HUB_PUBLIC_IP

# Check Cilium status
cilium status

# Check node resources
kubectl top nodes
```

### Spoke Registration Issues

```bash
# Check ExternalSecret status
kubectl describe externalsecret argocd-cluster-thinkpad -n argocd

# Check cluster secret
kubectl get secret cluster-thinkpad -n argocd -o yaml

# Test spoke connectivity from hub
kubectl run test-connectivity --rm -it --image=curlimages/curl -- \
  curl -k https://k8s-api-thinkpad.tail286401.ts.net/healthz
```

### ArgoCD Sync Issues

```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# Force sync
argocd app sync argocd/backstage-dev --insecure --force

# Check application events
kubectl describe application backstage-dev -n argocd
```

---

## Next Steps

1. **Add Kargo**: Install Kargo on hub for cross-cluster progressive delivery
2. **Add monitoring**: Deploy Prometheus/Grafana for hub observability
3. **Document recovery**: Create runbook for hub cluster recovery
4. **Add more spokes**: Register additional clusters as needed
