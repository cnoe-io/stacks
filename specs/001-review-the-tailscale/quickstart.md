# Quickstart: Deploy Tailscale Operator for Remote Cluster Access

**Feature**: Tailscale Remote Kubernetes Cluster Access
**Phase**: 1 (Design & Contracts)
**Date**: 2025-10-07

## Prerequisites

Before starting, ensure you have:

- [ ] Tailscale CLI installed and authenticated (`tailscale version` and `tailscale status`)
- [ ] Tailnet admin permissions (required for OAuth client creation and policy management)
- [ ] HTTPS enabled for your tailnet (verify: `tailscale status --json | jq -r '.MagicDNSSuffix'`)
- [ ] Azure CLI authenticated (`az account show`)
- [ ] Access to Azure Key Vault for storing OAuth credentials
- [ ] Kubernetes cluster running version 1.23.0 or later
- [ ] `kubectl` configured with cluster access
- [ ] CDK8s development environment set up (`npm install` in `cdk8s/` directory)

## Deployment Steps

### Step 1: Configure Tailscale

#### 1.1 Create OAuth Client

```bash
# Set cluster name from wi.env (dev environment)
source .env-files/wi.env
export CLUSTER_NAME="${CLUSTER_NAME}"  # Uses "kind" from wi.env

# Create OAuth client with required scopes
tailscale oauth create \
  --name "k8s-operator-${CLUSTER_NAME}" \
  --device-write \
  --auth-keys

# Output example:
# {
#   "id": "k8s-abc123",
#   "secret": "tskey-client-kABC...",
#   "created": "2025-10-07T12:00:00Z"
# }
```

#### 1.2 Store Credentials in Azure Key Vault

```bash
# Set Key Vault name from wi.env
source .env-files/wi.env
export KEYVAULT_NAME="${AZURE_KEYVAULT_NAME}"  # Uses keyvault-thcmfmoo5oeow

# Extract OAuth credentials (save output from previous command)
export CLIENT_ID="k8s-abc123"
export CLIENT_SECRET="tskey-client-kABC..."

# Store in Key Vault
az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "TAILSCALE-OAUTH-CLIENT-ID" \
  --value "${CLIENT_ID}"

az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "TAILSCALE-OAUTH-CLIENT-SECRET" \
  --value "${CLIENT_SECRET}"

# Verify secrets stored
az keyvault secret list --vault-name "${KEYVAULT_NAME}" --query "[?name=='TAILSCALE-OAUTH-CLIENT-ID' || name=='TAILSCALE-OAUTH-CLIENT-SECRET']"
```

#### 1.3 Configure Tailnet Policy

Create policy file with tags and impersonation grants:

```bash
cat > tailnet-policy.json <<'EOF'
{
  "tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"]
  },
  "grants": [
    {
      "src": ["group:admins"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["system:masters"]
          }
        }]
      }
    },
    {
      "src": ["group:developers"],
      "dst": ["tag:k8s-operator"],
      "app": {
        "tailscale.com/cap/kubernetes": [{
          "impersonate": {
            "groups": ["developers"]
          }
        }]
      }
    }
  ]
}
EOF

# Validate policy
tailscale acl validate tailnet-policy.json

# Apply policy
tailscale acl set tailnet-policy.json
```

**Note**: Customize grants based on your Tailscale groups and desired Kubernetes RBAC permissions.

---

### Step 2: Configure External Secrets Operator

Ensure External Secret is configured to sync Tailscale credentials:

```bash
# Verify ClusterSecretStore exists
kubectl get clustersecretstore cluster-secret-store

# If using Azure Workload Identity, verify identity binding
kubectl get serviceaccount external-secrets -n external-secrets -o yaml | grep azure.workload.identity
```

The CDK8s chart will automatically create the External Secret for Tailscale OAuth credentials referencing these Key Vault secrets.

---

### Step 3: Configure CDK8s Chart

#### 3.1 Add Application Configuration

Edit `cdk8s/config/applications.ts` and add Tailscale operator configuration:

```typescript
// Add to applicationConfigs array
{
  name: 'tailscale-operator',
  namespace: 'tailscale',
  chart: {
    type: 'TailscaleOperatorChart',
    props: {
      environmentName: 'dev',  // Dev environment only for this implementation
      clusterName: process.env.CLUSTER_NAME || 'kind',
      oauthSecretName: 'tailscale-oauth',
      enableHA: false,  // Set true for staging/production
      proxyReplicas: 2,
      impersonationGrants: [
        {
          tailscaleGroup: 'group:admins',
          kubernetesGroups: ['system:masters'],
          description: 'Full cluster admin access'
        },
        {
          tailscaleGroup: 'group:developers',
          kubernetesGroups: ['developers'],
          description: 'Developer namespace access'
        }
      ]
    }
  },
  argocd: {
    syncWave: '-90',
    labels: {
      'app.kubernetes.io/name': 'tailscale-operator',
      'app.kubernetes.io/component': 'network-proxy'
    },
    syncPolicy: {
      automated: { prune: true, selfHeal: true }
    }
  }
}
```

#### 3.2 Update Environment Variables

Add Tailscale OAuth client ID to existing `.env-files/wi.env`:

```bash
# Add to .env-files/wi.env
echo "TAILSCALE_OAUTH_CLIENT_ID=${CLIENT_ID}" >> .env-files/wi.env

# Note: Client secret stored in Azure Key Vault (AZURE_KEYVAULT_NAME from wi.env)
```

---

### Step 4: Synthesize and Deploy

#### 4.1 Synthesize Manifests

```bash
# From repository root
cd cdk8s

# Run synthesis
npm run synth
# or
cluster-synth

# Verify output created
ls -la dist/tailscale-operator/manifests/
```

**Expected output**:
```
Namespace.tailscale.k8s.yaml
ExternalSecret.tailscale-oauth.k8s.yaml
Deployment.operator.k8s.yaml
ServiceAccount.operator.k8s.yaml
ClusterRole.operator.k8s.yaml
ClusterRoleBinding.operator.k8s.yaml
kustomization.yaml
```

#### 4.2 Deploy to Cluster

```bash
# From repository root
cluster-update

# This will:
# 1. Synthesize manifests
# 2. Push to Gitea (local dev)
# 3. Trigger ArgoCD sync
# 4. Display diff of changes
```

#### 4.3 Verify Deployment

```bash
# Check ArgoCD application status
argocd app get argocd/tailscale-operator --insecure

# Check operator pod
kubectl get pods -n tailscale

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# tailscale-operator-7b8f9d6c5d-abc12   1/1     Running   0          2m

# Check External Secret sync
kubectl get externalsecret -n tailscale
kubectl get secret tailscale-oauth -n tailscale

# Check operator logs
kubectl logs -n tailscale deployment/tailscale-operator
```

**Healthy Operator Logs**:
```
2025-10-07T12:05:00Z INFO Starting Tailscale Kubernetes Operator
2025-10-07T12:05:01Z INFO Successfully authenticated with OAuth client
2025-10-07T12:05:02Z INFO Watching for ProxyGroup resources
2025-10-07T12:05:03Z INFO Operator ready
```

---

### Step 5: Configure Remote Access

#### 5.1 Generate Kubeconfig on Remote Machine

On a machine connected to your Tailscale network (not the cluster):

```bash
# Verify connected to Tailscale
tailscale status

# Configure kubeconfig for cluster
tailscale configure kubeconfig ${CLUSTER_NAME}

# Example output:
# Added Tailscale-managed kubeconfig for cluster: dev-local
# Context: tailscale-dev-local
# Server: https://dev-local.tailnet-xyz.ts.net:443
```

#### 5.2 Test Connectivity

```bash
# List available contexts
kubectl config get-contexts | grep tailscale

# Test cluster access
kubectl --context=tailscale-${CLUSTER_NAME} get nodes

# Expected output: List of cluster nodes
# NAME                 STATUS   ROLES           AGE   VERSION
# localdev-control-plane   Ready    control-plane   1h    v1.30.0

# Test with your Tailscale identity
kubectl --context=tailscale-${CLUSTER_NAME} auth whoami

# Verify you're impersonated based on your Tailscale group
# If you're in group:admins, you should see:
# Username: <your-tailscale-email>
# Groups: [system:masters system:authenticated]
```

#### 5.3 Set as Default Context (Optional)

```bash
# Make Tailscale context the default
kubectl config use-context tailscale-${CLUSTER_NAME}

# Now kubectl commands work without --context flag
kubectl get pods -A
```

---

## High Availability Configuration (Deferred - P3)

**Note**: This initial implementation targets dev environment only with single-replica proxy. High availability ProxyGroup configuration is deferred to future production deployment.

For reference, staging and production environments would enable HA ProxyGroup:

### 1. Update Configuration

Edit `cdk8s/config/applications.ts`:

```typescript
{
  name: 'tailscale-operator',
  chart: {
    type: 'TailscaleOperatorChart',
    props: {
      environmentName: 'production',
      clusterName: 'prod-us-east-1',
      enableHA: true,        // Enable ProxyGroup
      proxyReplicas: 3,      // Odd number for consensus
      // ... other props
    }
  }
}
```

### 2. Enable Tailscale Services (Alpha)

**Note**: ProxyGroup requires Tailscale Services feature (currently alpha).

Contact Tailscale support to enable for your tailnet:
- Email: support@tailscale.com
- Subject: "Enable Tailscale Services for ProxyGroup"
- Include: Tailnet ID and use case (Kubernetes API server proxy)

### 3. Deploy and Verify

```bash
# Synthesize and deploy
cluster-update

# Verify ProxyGroup created
kubectl get proxygroup -n tailscale

# Check proxy pods (should see multiple replicas)
kubectl get pods -n tailscale -l app=api-server-proxy

# Expected output:
# NAME                              READY   STATUS    RESTARTS   AGE
# api-server-proxy-0                1/1     Running   0          5m
# api-server-proxy-1                1/1     Running   0          5m
# api-server-proxy-2                1/1     Running   0          5m
```

---

## Troubleshooting

### Issue: OAuth credentials not syncing

**Symptoms**:
```bash
kubectl get externalsecret -n tailscale
# Shows SecretSyncError status
```

**Resolution**:
1. Verify secrets exist in Key Vault:
   ```bash
   az keyvault secret show --vault-name "${KEYVAULT_NAME}" --name "TAILSCALE-OAUTH-CLIENT-SECRET"
   ```

2. Check External Secrets Operator logs:
   ```bash
   kubectl logs -n external-secrets deployment/external-secrets
   ```

3. Verify Workload Identity binding:
   ```bash
   kubectl get serviceaccount external-secrets -n external-secrets -o yaml
   ```

### Issue: Operator pod crash looping

**Symptoms**:
```bash
kubectl get pods -n tailscale
# Shows CrashLoopBackOff status
```

**Resolution**:
1. Check operator logs:
   ```bash
   kubectl logs -n tailscale deployment/tailscale-operator
   ```

2. Common errors:
   - **"OAuth authentication failed"**: Verify OAuth client credentials are correct
   - **"Tag k8s-operator not authorized"**: Update tailnet policy with tag definitions
   - **"HTTPS not enabled"**: Enable HTTPS in Tailscale admin console

### Issue: Remote kubectl connection fails

**Symptoms**:
```bash
kubectl --context=tailscale-${CLUSTER_NAME} get nodes
# Error: Unable to connect to the server
```

**Resolution**:
1. Verify Tailscale connection:
   ```bash
   tailscale status
   # Ensure connected and showing proxy devices
   ```

2. Verify operator is running:
   ```bash
   kubectl get pods -n tailscale
   ```

3. Check proxy registration:
   ```bash
   tailscale status | grep "tag:k8s"
   # Should show API server proxy devices
   ```

4. Verify kubeconfig URL:
   ```bash
   kubectl config view --context=tailscale-${CLUSTER_NAME}
   # Check server URL matches Tailscale proxy address
   ```

### Issue: Permission denied errors

**Symptoms**:
```bash
kubectl --context=tailscale-${CLUSTER_NAME} get pods
# Error: forbidden: User cannot list pods
```

**Resolution**:
1. Check your Tailscale group membership:
   ```bash
   tailscale status --json | jq -r '.User.LoginName'
   # Verify you're in the expected group
   ```

2. Verify impersonation grants in tailnet policy:
   ```bash
   tailscale acl get | jq '.grants'
   ```

3. Check Kubernetes RBAC for impersonated group:
   ```bash
   kubectl get clusterrolebinding -o yaml | grep "developers"
   ```

---

## Clean Slate Validation

For end-to-end testing from scratch:

```bash
# 1. Delete existing deployment
argocd app delete argocd/tailscale-operator --yes --insecure

# 2. Recreate cluster (optional, for full clean state)
cluster-recreate

# 3. Re-run setup steps
# ... (Steps 1-4 from Deployment Steps)

# 4. Verify from remote machine
tailscale configure kubeconfig ${CLUSTER_NAME}
kubectl get nodes
```

---

## Next Steps

After successful deployment:

1. **Configure RBAC**: Create Kubernetes RoleBindings for impersonated groups
   ```bash
   kubectl create clusterrolebinding developers-binding \
     --clusterrole=view \
     --group=developers
   ```

2. **Set up monitoring**: Monitor operator health via ArgoCD UI and kubectl
   ```bash
   # Watch operator logs
   kubectl logs -n tailscale deployment/tailscale-operator -f
   ```

3. **Document team access**: Share kubeconfig instructions with team members
   ```markdown
   To access the cluster:
   1. Ensure you're connected to Tailscale
   2. Run: tailscale configure kubeconfig ${CLUSTER_NAME}
   3. Use: kubectl --context=tailscale-${CLUSTER_NAME} get pods
   ```

4. **Production checklist**:
   - [ ] Enable HA ProxyGroup (3+ replicas)
   - [ ] Configure NetworkPolicies for operator namespace
   - [ ] Set resource limits on operator and proxy pods
   - [ ] Enable Kubernetes audit logging for API server access
   - [ ] Document OAuth credential rotation procedure
   - [ ] Set up alerts for operator pod health
   - [ ] Test failover by terminating proxy pods

---

## Reference

- **Feature Specification**: [spec.md](./spec.md)
- **Implementation Plan**: [plan.md](./plan.md)
- **Research Decisions**: [research.md](./research.md)
- **Data Model**: [data-model.md](./data-model.md)
- **Tailscale CLI Commands**: [contracts/tailscale-cli.md](./contracts/tailscale-cli.md)
- **Tailscale Operator Docs**: https://tailscale.com/kb/1236/kubernetes-operator
- **API Server Proxy Docs**: https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy
