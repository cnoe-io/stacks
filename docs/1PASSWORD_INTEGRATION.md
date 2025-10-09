# 1Password Integration

This document describes how to use 1Password with this repository for secrets management.

## Service Account

A 1Password service account has been created for automated access to secrets.

**Service Account Details:**
- Name: `devcontainer-sa-20251009-213227`
- Vault Access: CLI vault (read_items, write_items)
- Expiry: 90 days (2025-01-07)
- Token Location: Azure Key Vault secret `ONEPASSWORD-SERVICE-ACCOUNT-TOKEN`

## Secrets Available

### DEVCONTAINER-SP-CLIENT-SECRET
Azure Service Principal client secret for devcontainer operations.

**1Password References:**
- Employee vault: `op://Employee/DEVCONTAINER-SP-CLIENT-SECRET/password`
- CLI vault: `op://CLI/DEVCONTAINER-SP-CLIENT-SECRET/password`

**Note:** Service accounts can only access the CLI vault, not Employee/Personal/Private vaults.

## Usage

### Using the Service Account Token

```bash
# Set the token from Azure Key Vault
export OP_SERVICE_ACCOUNT_TOKEN=$(az keyvault secret show \
  --vault-name keyvault-thcmfmoo5oeow \
  --name ONEPASSWORD-SERVICE-ACCOUNT-TOKEN \
  --query value -o tsv)

# Read a secret
op read "op://CLI/DEVCONTAINER-SP-CLIENT-SECRET/password"
```

### Using op run with Environment Files

```bash
# Create .env file with 1Password references
cat > .env << 'ENVEOF'
DEVCONTAINER_SP_CLIENT_SECRET=op://CLI/DEVCONTAINER-SP-CLIENT-SECRET/password
ENVEOF

# Run commands with secrets injected
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /tmp/op-service-account-token.txt)
op run --env-file=.env -- env | grep DEVCONTAINER
```

### Using in Scripts

```bash
#!/bin/bash

# Load 1Password token
export OP_SERVICE_ACCOUNT_TOKEN=$(az keyvault secret show \
  --vault-name keyvault-thcmfmoo5oeow \
  --name ONEPASSWORD-SERVICE-ACCOUNT-TOKEN \
  --query value -o tsv)

# Get secret
SECRET=$(op read "op://CLI/DEVCONTAINER-SP-CLIENT-SECRET/password")

# Use secret
echo "Secret starts with: ${SECRET:0:10}..."
```

## Adding New Secrets

### Via CLI

```bash
# Sign in with personal account
eval $(op signin)

# Create item in CLI vault (accessible by service account)
op item create \
  --category=password \
  --title="MY-NEW-SECRET" \
  --vault="CLI" \
  password="my-secret-value"

# Or create via template
op item template get Password | \
  op item create --vault=CLI --title="MY-NEW-SECRET" -
```

### Via Web Interface

1. Sign in to https://my.1password.com
2. Navigate to the **CLI** vault
3. Click **New Item**
4. Select type and fill in details
5. Save

## Token Renewal

The service account token expires in 90 days. To renew:

```bash
# Sign in with personal account
eval $(op signin)

# Create new service account
op service-account create devcontainer-sa-$(date +%Y%m%d) \
  --vault 'CLI:read_items,write_items' \
  --expires-in 90d \
  --raw > /tmp/new-token.txt

# Update Azure Key Vault
az keyvault secret set \
  --vault-name keyvault-thcmfmoo5oeow \
  --name "ONEPASSWORD-SERVICE-ACCOUNT-TOKEN" \
  --value "$(cat /tmp/new-token.txt)"

# Test new token
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /tmp/new-token.txt)
op read "op://CLI/DEVCONTAINER-SP-CLIENT-SECRET/password"
```

## Security Best Practices

1. **Never commit tokens to git** - Always use environment variables or Azure Key Vault
2. **Rotate tokens regularly** - Set calendar reminder for 90-day renewal
3. **Use service accounts for automation** - Personal accounts for manual operations
4. **Principle of least privilege** - Only grant access to required vaults
5. **Audit access** - Review 1Password activity logs periodically

## Troubleshooting

### "Signin credentials are not compatible"

This error occurs with older service account tokens. Create a new service account using the renewal steps above.

### "You are not currently signed in"

For interactive operations, sign in with your personal account:
```bash
eval $(op signin)
```

For automation, ensure `OP_SERVICE_ACCOUNT_TOKEN` is set:
```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(az keyvault secret show ...)
```

### "Cannot access Employee vault"

Service accounts can only access shared vaults (like CLI). Move secrets to the CLI vault or use your personal account for Employee vault access.

## References

- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [Service Accounts Guide](https://developer.1password.com/docs/service-accounts/)
- [Secret References](https://developer.1password.com/docs/cli/secret-references/)
