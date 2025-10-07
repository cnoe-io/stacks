# ArgoCD Automation

Automatic ArgoCD CLI authentication without password prompts.

## Quick Start

```bash
# Source cluster functions (includes ArgoCD automation)
source ~/stacks/deployment/scripts/cluster-menu.sh

# Use native argocd CLI - authentication is automatic!
argocd app list --insecure
argocd app get argocd/backstage --insecure

# Or use helper functions
argocd-status
argocd-sync argocd/my-app
```

**No manual token management required!** `ARGOCD_AUTH_TOKEN` is automatically set, so the native `argocd` command works immediately.

## Helper Functions

| Function | Alias | Description |
|---------|-------|-------------|
| `argocd-status` | `argo-status` | Show formatted application status |
| `argocd-sync <app>` | `argo-sync` | Sync specific application |
| `argocd-sync-all` | `argo-sync-all` | Sync all applications |
| `argocd-list-outofsync` | `argo-outofsync` | List out-of-sync apps |

**Native argocd CLI works too!** Just add `--insecure` (or set `ARGOCD_OPTS`):

## How Authentication Works

**Token Priority:**
1. `ARGOCD_AUTH_TOKEN` env var (session)
2. 1Password vault (persistent)
3. Auto-generate from cluster (fallback)

**Automatic Token Saves:**
- After `cluster-deploy` or `cluster-recreate`
- On first ArgoCD CLI command
- When authentication fails (auto-regenerates)

## Usage Examples

```bash
# Use native argocd commands
argocd app list --insecure
argocd app get argocd/keycloak --insecure
argocd app sync argocd/backstage --prune --insecure

# Or use helper functions (adds formatting)
argocd-status
argocd-list-outofsync
argocd-sync argocd/backstage
```

## Cluster Integration

```bash
# Recreate cluster - token auto-generated and saved
cluster-recreate

# Deploy cluster - token auto-generated and saved
cluster-deploy

# Use ArgoCD immediately (no setup needed)
argocd app list --insecure
```

## 1Password Integration

**With 1Password:**
- Tokens saved to `op://CLI/ArgoCD Developer Token/credential`
- Tokens persist across shell sessions
- Automatically retrieved on next use

**Without 1Password:**
- Tokens work in current session
- Auto-regenerated in new sessions
- No persistence across sessions

**Sign in for persistence:**
```bash
eval $(op signin)
```

## Troubleshooting

### Authentication Fails

```bash
# Clear and regenerate token
unset ARGOCD_AUTH_TOKEN
argocd-auth-init
```

### Token Not in 1Password

```bash
# Sign in to 1Password
eval $(op signin)

# Force token save
argocd-save-token "$ARGOCD_AUTH_TOKEN"
```

### Connection Issues

```bash
# Check cluster is running
kubectl get pods -n argocd

# Test connectivity
curl -k https://argocd.cnoe.localtest.me:8443/api/version
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ARGOCD_SERVER` | `argocd.cnoe.localtest.me:8443` | Server address |
| `ARGOCD_AUTH_TOKEN` | Auto-generated | Session token |
| `ARGOCD_OPTS` | `--insecure` | Default CLI options |

## Implementation Details

**Scripts:**
- `argocd-auth.sh` - Core authentication logic
- `cluster-menu.sh` - Cluster integration, sources argocd-auth.sh

**Service Account:**
- Account: `developer`
- Capabilities: `apiKey, login`
- Token: JWT (no expiration by default)

**Token Generation:**
1. Get admin password from `argocd-initial-admin-secret`
2. Login as admin
3. Generate token for developer account
4. Save to 1Password (if available)
5. Export to `ARGOCD_AUTH_TOKEN`

## Security Notes

- Tokens stored in 1Password are encrypted
- Session tokens are ephemeral (env var only)
- Service account has full API access
- Rotate tokens periodically for security
- Never commit tokens to git

## References

- [ArgoCD CLI Docs](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/)
- [1Password Shell Plugins](https://developer.1password.com/docs/cli/shell-plugins/)
- Script: `~/stacks/deployment/scripts/argocd-auth.sh`
- Integration: `~/stacks/deployment/scripts/cluster-menu.sh`
