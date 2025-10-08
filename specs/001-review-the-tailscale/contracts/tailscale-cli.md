# Contract: Tailscale CLI Commands

**Feature**: Tailscale Remote Kubernetes Cluster Access
**Phase**: 1 (Design & Contracts)
**Date**: 2025-10-07

## Overview

This document defines the command-line interface contracts for Tailscale CLI operations required for operator deployment and configuration. These commands are executed during setup and configuration phases to provision OAuth credentials and configure tailnet policies.

## Prerequisites

```bash
# Verify Tailscale CLI is installed
tailscale version

# Verify authenticated to tailnet
tailscale status

# Expected output: Shows current device and tailnet information
```

## OAuth Client Management

### Create OAuth Client

**Command**:
```bash
tailscale oauth create \
  --name "k8s-operator-${CLUSTER_NAME}" \
  --device-write \
  --auth-keys
```

**Parameters**:
- `--name`: Human-readable identifier for the OAuth client (use cluster name for clarity)
- `--device-write`: Grant permission to create and manage devices in tailnet
- `--auth-keys`: Grant permission to create auth keys for device enrollment

**Output**:
```json
{
  "id": "k8s-abcd1234",
  "secret": "tskey-client-kABC123...",
  "created": "2025-10-07T12:00:00Z",
  "scopes": ["devices:write", "auth_keys:write"]
}
```

**Post-Processing**:
```bash
# Extract client ID and secret from JSON output
CLIENT_ID=$(tailscale oauth create --name "..." --device-write --auth-keys | jq -r '.id')
CLIENT_SECRET=$(tailscale oauth create --name "..." --device-write --auth-keys | jq -r '.secret')

# Store in Azure Key Vault
az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "TAILSCALE-OAUTH-CLIENT-ID" \
  --value "${CLIENT_ID}"

az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "TAILSCALE-OAUTH-CLIENT-SECRET" \
  --value "${CLIENT_SECRET}"
```

**Error Handling**:
- **403 Forbidden**: User lacks permission to create OAuth clients (requires tailnet admin)
- **400 Bad Request**: Invalid scope combination
- **409 Conflict**: OAuth client with same name already exists (use different name or delete existing)

---

### List OAuth Clients

**Command**:
```bash
tailscale oauth list
```

**Output**:
```json
[
  {
    "id": "k8s-prod-us-east-1",
    "name": "k8s-operator-prod-us-east-1",
    "created": "2025-10-07T12:00:00Z",
    "scopes": ["devices:write", "auth_keys:write"]
  },
  {
    "id": "k8s-dev-local",
    "name": "k8s-operator-dev-local",
    "created": "2025-10-06T10:30:00Z",
    "scopes": ["devices:write", "auth_keys:write"]
  }
]
```

**Use Case**: Verify OAuth client exists before deployment, check for duplicates

---

### Delete OAuth Client

**Command**:
```bash
tailscale oauth delete <client-id>
```

**Example**:
```bash
tailscale oauth delete k8s-dev-local
```

**Output**:
```
OAuth client 'k8s-dev-local' deleted successfully
```

**Use Case**: Clean up OAuth clients when decommissioning clusters

---

## Tailnet Policy Management

### Get Current Policy

**Command**:
```bash
tailscale acl get > current-policy.json
```

**Output**: JSON file containing current tailnet ACL policy

**Example Output**:
```json
{
  "tagOwners": {
    "tag:production": ["user:admin@example.com"]
  },
  "acls": [
    {"action": "accept", "src": ["*"], "dst": ["*:*"]}
  ]
}
```

**Use Case**: Backup current policy before making changes

---

### Set Policy with Tags and Grants

**Command**:
```bash
tailscale acl set policy.json
```

**Input File** (`policy.json`):
```json
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
  ],
  "acls": [
    {"action": "accept", "src": ["*"], "dst": ["*:*"]}
  ]
}
```

**Output**:
```
ACL policy updated successfully
```

**Error Handling**:
- **400 Bad Request**: Invalid JSON syntax or schema violation
- **403 Forbidden**: User lacks permission to modify policy (requires tailnet admin)
- **422 Unprocessable Entity**: Policy references undefined groups or tags

**Validation**:
```bash
# Validate policy syntax before applying
tailscale acl validate policy.json

# Expected output if valid
Policy is valid
```

---

## Kubeconfig Generation

### Configure Kubeconfig for Remote Access

**Command** (run on remote machine):
```bash
tailscale configure kubeconfig <cluster-name>
```

**Parameters**:
- `<cluster-name>`: Name of the ProxyGroup or operator-managed API server proxy

**Output**:
```
Added Tailscale-managed kubeconfig for cluster: prod-us-east-1
Context: tailscale-prod-us-east-1
Server: https://prod-us-east-1.tailnet-xyz.ts.net:443

Use 'kubectl --context=tailscale-prod-us-east-1 get nodes' to test
```

**Post-Configuration**:
```bash
# Verify kubeconfig entry added
kubectl config get-contexts | grep tailscale

# Test connectivity
kubectl --context=tailscale-prod-us-east-1 get nodes

# Set as default context (optional)
kubectl config use-context tailscale-prod-us-east-1
```

**Error Handling**:
- **404 Not Found**: Cluster name does not exist or proxy not deployed
- **401 Unauthorized**: Device not authenticated to tailnet
- **403 Forbidden**: User lacks permission to access cluster (no matching grant)

---

## Status and Verification

### Check Tailscale Connection Status

**Command**:
```bash
tailscale status
```

**Output**:
```
100.64.0.1   device-hostname      user@example.com  linux   -
100.64.0.2   prod-api-server-1    tag:k8s          linux   active; relay "nyc"
100.64.0.3   prod-api-server-2    tag:k8s          linux   active; relay "nyc"
```

**Interpretation**:
- `tag:k8s` devices are API server proxy pods
- `active` status indicates proxies are reachable
- `relay` shows Tailscale relay being used (or `direct` for direct connection)

---

### Verify HTTPS Enabled

**Command**:
```bash
tailscale status --json | jq -r '.MagicDNSSuffix'
```

**Output**:
```
tailnet-xyz.ts.net
```

**Validation**:
```bash
# Check if HTTPS is enabled (presence of MagicDNS suffix indicates HTTPS-capable tailnet)
if tailscale status --json | jq -r '.MagicDNSSuffix' | grep -q '.ts.net'; then
  echo "✅ HTTPS enabled for tailnet"
else
  echo "❌ HTTPS not enabled - enable in Tailscale admin console"
  exit 1
fi
```

---

## Scripted Workflow Example

### Complete Setup Script

```bash
#!/bin/bash
set -e

CLUSTER_NAME="${1:-dev-local}"
KEYVAULT_NAME="${2:-cluster-keyvault}"

echo "🔧 Setting up Tailscale for cluster: ${CLUSTER_NAME}"

# 1. Verify Tailscale CLI available
if ! command -v tailscale &>/dev/null; then
  echo "❌ Tailscale CLI not found. Install from https://tailscale.com/download"
  exit 1
fi

# 2. Verify authenticated
if ! tailscale status &>/dev/null; then
  echo "❌ Not authenticated to Tailscale. Run: tailscale up"
  exit 1
fi

# 3. Verify HTTPS enabled
if ! tailscale status --json | jq -r '.MagicDNSSuffix' | grep -q '.ts.net'; then
  echo "❌ HTTPS not enabled for tailnet. Enable in admin console."
  exit 1
fi
echo "✅ HTTPS enabled"

# 4. Create OAuth client
echo "📝 Creating OAuth client..."
OAUTH_JSON=$(tailscale oauth create \
  --name "k8s-operator-${CLUSTER_NAME}" \
  --device-write \
  --auth-keys)

CLIENT_ID=$(echo "$OAUTH_JSON" | jq -r '.id')
CLIENT_SECRET=$(echo "$OAUTH_JSON" | jq -r '.secret')

echo "✅ OAuth client created: ${CLIENT_ID}"

# 5. Store credentials in Azure Key Vault
echo "🔐 Storing credentials in Key Vault..."
az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "TAILSCALE-OAUTH-CLIENT-ID" \
  --value "${CLIENT_ID}" \
  --output none

az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "TAILSCALE-OAUTH-CLIENT-SECRET" \
  --value "${CLIENT_SECRET}" \
  --output none

echo "✅ Credentials stored in ${KEYVAULT_NAME}"

# 6. Update tailnet policy
echo "📋 Updating tailnet policy..."
cat > tailnet-policy.json <<EOF
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
    }
  ]
}
EOF

# Validate before applying
if ! tailscale acl validate tailnet-policy.json; then
  echo "❌ Policy validation failed"
  exit 1
fi

# Apply policy
tailscale acl set tailnet-policy.json
echo "✅ Tailnet policy updated"

# 7. Summary
echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Deploy operator: cluster-update"
echo "  2. Verify deployment: argocd app get tailscale-operator --insecure"
echo "  3. Configure remote kubeconfig: tailscale configure kubeconfig ${CLUSTER_NAME}"
echo "  4. Test connectivity: kubectl get nodes"
```

---

## Command Reference Summary

| Command | Purpose | Frequency |
|---------|---------|-----------|
| `tailscale oauth create` | Create OAuth credentials for operator | Once per cluster (setup) |
| `tailscale oauth list` | List existing OAuth clients | As needed (verification) |
| `tailscale oauth delete` | Remove OAuth client | When decommissioning cluster |
| `tailscale acl get` | Backup current policy | Before policy changes |
| `tailscale acl validate` | Validate policy syntax | Before applying changes |
| `tailscale acl set` | Apply tailnet policy | Setup + when adding user groups |
| `tailscale configure kubeconfig` | Generate kubectl config | Once per remote machine |
| `tailscale status` | Verify connection and proxy health | Troubleshooting |

---

## Error Code Reference

| Error Code | Description | Resolution |
|------------|-------------|------------|
| 400 | Bad Request (invalid parameters) | Check command syntax and parameter values |
| 401 | Unauthorized (not authenticated) | Run `tailscale up` to authenticate |
| 403 | Forbidden (insufficient permissions) | Ensure user is tailnet admin |
| 404 | Not Found (resource doesn't exist) | Verify cluster name and proxy deployment |
| 409 | Conflict (resource already exists) | Use different name or delete existing resource |
| 422 | Unprocessable Entity (invalid policy) | Validate policy references and syntax |

---

## Integration with CDK8s Deployment

The Tailscale CLI commands are **prerequisites** to CDK8s deployment, not part of the synthesized manifests. Execution order:

1. **Setup Phase** (manual or scripted):
   ```bash
   ./setup-tailscale.sh <cluster-name> <keyvault-name>
   ```
   - Creates OAuth client
   - Stores credentials in Key Vault
   - Updates tailnet policy

2. **Synthesis Phase** (CDK8s):
   ```bash
   cluster-synth
   ```
   - External Secret references Key Vault credentials
   - Operator Deployment consumes OAuth credentials
   - ProxyGroup (if HA) references `tag:k8s`

3. **Deployment Phase** (GitOps):
   ```bash
   cluster-update
   ```
   - ArgoCD deploys manifests to cluster
   - External Secrets syncs OAuth credentials
   - Operator starts and provisions proxies

4. **Client Configuration** (remote machine):
   ```bash
   tailscale configure kubeconfig <cluster-name>
   kubectl get nodes
   ```
   - Kubeconfig updated with Tailscale proxy endpoint
   - kubectl commands routed through Tailscale network

This separation ensures CLI operations (setup) are distinct from infrastructure-as-code (CDK8s) deployment.
