# ArgoCD API Integration

This document describes the ArgoCD API integration for the CAIPE platform, including authentication, endpoints, and usage examples.

## Overview

ArgoCD provides a REST API for managing GitOps deployments programmatically. The CAIPE platform includes automated token management and API access configuration.

## API Configuration

### Endpoints
- **Internal API URL**: `http://argocd-server.argocd.svc.cluster.local`
- **External Web UI**: `https://cnoe.localtest.me:8443/argocd`
- **API Port**: `80` (HTTP internal), `443` (HTTPS external)

### Authentication

The platform automatically manages ArgoCD API tokens through a CronJob that:
1. Generates API tokens for the `developer` account
2. Stores tokens securely in Vault at `secret/ai-platform-engineering/argocd-secret`
3. Rotates tokens every 10 minutes for security

#### Retrieving API Token

```bash
# From Vault (requires vault CLI and access)
vault kv get -field=ARGOCD_TOKEN secret/ai-platform-engineering/argocd-secret

# From Kubernetes secret (for agents)
kubectl get secret agent-argocd-secret -n ai-platform-engineering -o jsonpath='{.data.ARGOCD_TOKEN}' | base64 -d
```

## Current Applications

The ArgoCD instance manages the following applications:

| Application | Status | Health | Description |
|-------------|--------|--------|-------------|
| ai-platform-engineering | Synced | Healthy | AI platform engineering agents |
| argo-workflows | OutOfSync | Missing | Workflow orchestration |
| argocd | Synced | Healthy | ArgoCD itself |
| backstage | Synced | Healthy | Developer portal |
| backstage-templates | Synced | Healthy | Backstage templates |
| cluster-config | Synced | Healthy | Cluster configuration |
| external-secrets | Synced | Healthy | Secret synchronization |
| gitea | Synced | Healthy | Git repository server |
| keycloak | Synced | Healthy | Identity and access management |
| metric-server | Synced | Healthy | Metrics collection |
| nginx | Synced | Healthy | Ingress controller |
| spark-operator | Synced | Healthy | Apache Spark operator |
| vault | Synced | Healthy | Secret management |

## API Usage Examples

### Authentication Header

```bash
# Set the API token
ARGOCD_TOKEN="your-api-token-here"
ARGOCD_API_URL="http://argocd-server.argocd.svc.cluster.local"

# Use in API calls
curl -H "Authorization: Bearer $ARGOCD_TOKEN" \
     -H "Content-Type: application/json" \
     "$ARGOCD_API_URL/api/v1/applications"
```

### Common API Endpoints

#### List Applications
```bash
GET /api/v1/applications
```

#### Get Application Details
```bash
GET /api/v1/applications/{app-name}
```

#### Sync Application
```bash
POST /api/v1/applications/{app-name}/sync
```

#### Get Application Resources
```bash
GET /api/v1/applications/{app-name}/resource-tree
```

### Python Example

```python
import requests
import os

# Get token from environment or Kubernetes secret
argocd_token = os.getenv('ARGOCD_TOKEN')
argocd_url = "http://argocd-server.argocd.svc.cluster.local"

headers = {
    'Authorization': f'Bearer {argocd_token}',
    'Content-Type': 'application/json'
}

# List all applications
response = requests.get(f"{argocd_url}/api/v1/applications", headers=headers)
applications = response.json()

for app in applications['items']:
    print(f"App: {app['metadata']['name']}, Status: {app['status']['sync']['status']}")
```

### Shell Script Example

```bash
#!/bin/bash

# Get ArgoCD token from Vault
ARGOCD_TOKEN=$(vault kv get -field=ARGOCD_TOKEN secret/ai-platform-engineering/argocd-secret)
ARGOCD_API_URL="http://argocd-server.argocd.svc.cluster.local"

# Function to call ArgoCD API
argocd_api() {
    local endpoint="$1"
    curl -s -H "Authorization: Bearer $ARGOCD_TOKEN" \
         -H "Content-Type: application/json" \
         "$ARGOCD_API_URL$endpoint"
}

# List applications
echo "Applications:"
argocd_api "/api/v1/applications" | jq -r '.items[].metadata.name'

# Get specific application status
echo "Vault application status:"
argocd_api "/api/v1/applications/vault" | jq -r '.status.sync.status'
```

## Security Considerations

1. **Token Rotation**: API tokens are automatically rotated every 10 minutes
2. **Internal Access**: API is accessible only within the cluster by default
3. **RBAC**: The `developer` account has limited permissions for safety
4. **Vault Storage**: Tokens are stored encrypted in Vault
5. **No SSL Verification**: Internal API uses HTTP (SSL verification disabled)

## Troubleshooting

### Token Issues
```bash
# Check if token is valid
curl -H "Authorization: Bearer $ARGOCD_TOKEN" \
     "$ARGOCD_API_URL/api/v1/account"

# Check token generation logs
kubectl logs -n vault job/argocd-token-sync-$(date +%Y%m%d%H%M | cut -c1-10)
```

### API Connectivity
```bash
# Test internal connectivity
kubectl run test-pod --rm -i --tty --image=curlimages/curl -- \
  curl -H "Authorization: Bearer $ARGOCD_TOKEN" \
  http://argocd-server.argocd.svc.cluster.local/api/v1/version
```

### Application Sync Issues
```bash
# Force sync an application
curl -X POST -H "Authorization: Bearer $ARGOCD_TOKEN" \
     -H "Content-Type: application/json" \
     "$ARGOCD_API_URL/api/v1/applications/vault/sync" \
     -d '{"prune": false, "dryRun": false}'
```

## Integration with AI Agents

The ArgoCD API is integrated with AI platform engineering agents for:

- **Deployment Monitoring**: Track application sync status and health
- **Automated Remediation**: Trigger syncs when applications drift
- **Resource Management**: Query application resources and configurations
- **GitOps Workflows**: Coordinate with Git repositories for deployments

Agents can access the API using the automatically managed tokens stored in Vault and synchronized to Kubernetes secrets.
