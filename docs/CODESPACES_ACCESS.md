# Accessing Services in Codespaces

This guide explains how to access platform services when running the stack in GitHub Codespaces.

## Port Forwarding Configuration

The `.devcontainer/devcontainer.json` is configured to automatically forward these ports:

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 8080 | ArgoCD | HTTPS | GitOps continuous delivery |
| 7007 | Backstage | HTTP | Developer portal |
| 3000 | Gitea | HTTP | Git server and OCI registry |
| 8081 | Keycloak | HTTP | Identity and SSO provider |
| 8082 | Kargo | HTTP | Progressive delivery |
| 8083 | Headlamp | HTTP | Kubernetes UI |
| 8084 | Kagent | HTTP | AI agent platform (when deployed) |
| 8085 | Argo Workflows | HTTP | Workflow orchestration |
| 8443 | Ingress | HTTPS | Kind cluster ingress |

## Quick Start

### Automatic Port Forwarding

After the cluster is created, run:

```bash
./scripts/port-forward-all.sh
```

This starts port forwards for all major services. Access them via the **PORTS** tab in VS Code:

1. Click the **PORTS** tab (bottom panel)
2. Find the service you want to access
3. Click the **🌐 globe icon** to open in browser

### Stop Port Forwarding

```bash
./scripts/stop-port-forwards.sh
```

## Service Access Details

### ArgoCD
- **Port:** 8080
- **Protocol:** HTTPS (accept self-signed certificate)
- **Username:** `admin`
- **Password:** `developer`
- **Get password:** `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`

### Backstage
- **Port:** 7007
- **Protocol:** HTTP
- **Username:** `user1` (admin) or `user2` (regular user)
- **Get password:** `idpbuilder get secrets -p backstage`

### Gitea
- **Port:** 3000
- **Protocol:** HTTP
- **Username:** `giteaAdmin`
- **Get credentials:** `idpbuilder get secrets -p gitea`
- **Note:** Anonymous read access enabled for repositories and OCI registry

### Keycloak
- **Port:** 8081
- **Protocol:** HTTP
- **Path:** `/` (main UI) or `/admin/master/console/` (admin console)
- **Username:** `cnoe-admin`
- **Get password:** `idpbuilder get secrets -p keycloak`

### Kargo
- **Port:** 8082
- **Protocol:** HTTP
- **Username:** `admin`
- **Get password:** `kubectl get secret kargo-admin-credentials -n kargo -o jsonpath='{.data.password}' | base64 -d`

### Headlamp
- **Port:** 8083
- **Protocol:** HTTP
- **Authentication:** OIDC via Keycloak
- **Note:** Uses same users as Backstage (user1/user2)

### Kagent Dashboard
- **Port:** 8084
- **Protocol:** HTTP
- **Note:** Only available if kagent is deployed

### Argo Workflows
- **Port:** 8085
- **Protocol:** HTTP
- **Note:** Only available if argo-workflows namespace exists

## Alternative: Path-Based Routing

For a production-like setup with path-based routing (e.g., `/argocd`, `/backstage`), recreate the cluster with:

```bash
idpbuilder create --protocol http \
  --host ${CODESPACE_NAME}-8080.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN} \
  --port 8080 --use-path-routing \
  --package /workspaces/stacks/cdk8s/dist/
```

This provides URLs like:
- ArgoCD: `https://{codespace}-8080.app.github.dev/argocd`
- Backstage: `https://{codespace}-8080.app.github.dev/`
- Gitea: `https://{codespace}-8080.app.github.dev/gitea`

## Troubleshooting

### Port Forward Not Working

Check if the service is running:
```bash
kubectl get pods -n <namespace>
```

Restart port forward:
```bash
./scripts/stop-port-forwards.sh
./scripts/port-forward-all.sh
```

### Service Not Ready

Check ArgoCD to see if the application is synced and healthy:
```bash
kubectl get applications -n argocd
```

### View Port Forward Logs

```bash
ls -la /tmp/port-forward-logs/
cat /tmp/port-forward-logs/<service>.log
```

### Check Active Port Forwards

```bash
cat /tmp/port-forwards.pids
ps -p $(cat /tmp/port-forwards.pids | tr '\n' ',')
```

## Manual Port Forwarding

If you need to forward a specific service manually:

```bash
kubectl port-forward -n <namespace> svc/<service-name> <local-port>:<remote-port>
```

Example:
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## VS Code Port Configuration

Ports are automatically configured in `.devcontainer/devcontainer.json` with labels and auto-forward behavior. When you rebuild the devcontainer, these ports will be automatically detected and labeled in the PORTS tab.
