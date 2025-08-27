# Backstage Enhanced Chart

The Backstage Enhanced Chart provides SSH and VS Code tunnel support for all environments using External Secrets from Azure Key Vault.

## Features

- **SSH Access**: SSH keys managed in Azure Key Vault per environment
- **VS Code Tunnel Support**: Uses GITHUB-CODE-TUNNEL-PAT from Azure Key Vault
- **External Secrets Integration**: All secrets pulled from Azure Key Vault
- **Environment-aware Configuration**: Different SSH keys for dev, staging, and production

## Configuration

### Azure Key Vault Secrets

The following secrets must be configured in Azure Key Vault:

| Secret Key | Description | Example |
|------------|-------------|---------|
| `GITHUB-CODE-TUNNEL-PAT` | GitHub token with read:user and user:email scopes | `ghp_xxxx...` |
| `BACKSTAGE-SSH-AUTHORIZED-KEYS-DEV` | Authorized SSH public keys for dev | Multiple SSH public keys |
| `BACKSTAGE-SSH-AUTHORIZED-KEYS-STAGING` | Authorized SSH public keys for staging | Multiple SSH public keys |
| `BACKSTAGE-SSH-HOST-RSA-KEY-DEV` | SSH host RSA private key for dev | Generated once |
| `BACKSTAGE-SSH-HOST-ED25519-KEY-DEV` | SSH host ED25519 private key for dev | Generated once |

### Environment Variables

Only one environment variable is used (optional):

```bash
# Copy the example file (optional)
cp .env.example .env
```

```env
# Enable/disable Code tunnel (defaults to true for dev)
BACKSTAGE_CODE_TUNNEL_ENABLED=true
```

## Usage

### Generate Manifests

```bash
# Load environment variables and synthesize
cd /home/vpittamp/stacks/cdk8s
npm run synth
```

### Deploy to Kubernetes

```bash
# Apply the generated manifests
kubectl apply -f dist/backstage-dev
```

## Access Methods

### 1. SSH Access

SSH is always available with auto-generated or custom keys:

```bash
# Port-forward the SSH service
kubectl port-forward svc/backstage-dev-ssh -n backstage 2222:2222

# Connect via SSH
ssh -p 2222 code@localhost
```

To use the auto-generated development key:
```bash
# Extract the private key from the secret
kubectl get secret backstage-ssh-keys-dev -n backstage \
  -o jsonpath='{.data.id_rsa}' | base64 -d > ~/.ssh/backstage_dev
chmod 600 ~/.ssh/backstage_dev

# Connect using the key
ssh -i ~/.ssh/backstage_dev -p 2222 code@localhost
```

### 2. VS Code Tunnel

When `GITHUB_TOKEN` is configured:

**Browser Access:**
```
https://vscode.dev/tunnel/backstage-dev-tunnel
```

**VS Code Desktop:**
1. Install the "Remote - Tunnels" extension
2. Open Command Palette (Ctrl+Shift+P)
3. Run "Remote-Tunnels: Connect to Tunnel"
4. Select `backstage-dev-tunnel`

### 3. Direct HTTP Access

```bash
kubectl port-forward svc/backstage-dev -n backstage 7007:7007
# Access at http://localhost:7007
```

## SSH Key Management

### Initial Setup in Azure Key Vault

1. **Generate SSH Host Keys** (one-time per environment):
```bash
# Generate RSA host key
ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key -N ""

# Generate ED25519 host key
ssh-keygen -t ed25519 -f ssh_host_ed25519_key -N ""

# Store in Azure Key Vault
az keyvault secret set --vault-name "your-vault" \
  --name "BACKSTAGE-SSH-HOST-RSA-KEY-DEV" \
  --file ssh_host_rsa_key

az keyvault secret set --vault-name "your-vault" \
  --name "BACKSTAGE-SSH-HOST-ED25519-KEY-DEV" \
  --file ssh_host_ed25519_key
```

2. **Add Authorized SSH Keys**:
```bash
# Create authorized_keys file with team's public keys
cat > authorized_keys <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICL0HQDqVWr/dIbulpqzSFtpicPYLurmGHwa6uohLde3 vpittamp@nixos-wsl
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... developer@machine
EOF

# Store in Azure Key Vault
az keyvault secret set --vault-name "your-vault" \
  --name "BACKSTAGE-SSH-AUTHORIZED-KEYS-DEV" \
  --file authorized_keys
```

## Troubleshooting

### Code Tunnel Not Starting

1. Check if `GITHUB_TOKEN` is set:
```bash
kubectl logs deployment/backstage-dev -n backstage | grep tunnel
```

2. Verify the token has correct scopes (read:user, user:email)

3. Check the secret was created:
```bash
kubectl get secret backstage-code-tunnel-dev -n backstage
```

### SSH Connection Refused

1. Verify SSH service is running:
```bash
kubectl get svc backstage-dev-ssh -n backstage
```

2. Check SSH daemon logs:
```bash
kubectl logs deployment/backstage-dev -n backstage | grep sshd
```

3. Ensure port-forward is active:
```bash
kubectl port-forward svc/backstage-dev-ssh -n backstage 2222:2222
```

## Integration with Existing Infrastructure

The enhanced chart is designed to work alongside the existing `BackstageParameterizedChart`:

- Set `BACKSTAGE_USE_ENHANCED_CHART=true` to use enhanced features
- Leave unset or `false` to use the standard chart
- Both charts use the same image and core configuration
- Enhanced chart adds SSH and Code tunnel capabilities

## Security Considerations

1. **Development Keys**: The auto-generated SSH keys are for development only. Never use them in production.

2. **GitHub Token**: Store securely and rotate regularly. Use fine-grained personal access tokens with minimal scopes.

3. **External Secrets**: For production, always use External Secrets Operator with a proper secret manager (AWS Secrets Manager, HashiCorp Vault, etc.)

4. **Network Security**: Consider using NetworkPolicies to restrict SSH access to authorized sources.