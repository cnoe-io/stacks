# Persistent TLS Certificates and Attic Signing Keys

This feature stores TLS certificates and Attic signing keys in Azure Key Vault, eliminating the need to re-trust certificates or rebuild NixOS after cluster recreation.

## Problem Solved

When idpbuilder recreates the KIND cluster:
- **Before**: New self-signed cert generated, browsers need re-trust, NixOS rebuild required
- **After**: Same certificate persists across cluster recreations, zero manual intervention

## Prerequisites

- Azure CLI authenticated: `az login`
- Access to Azure Key Vault: `keyvault-thcmfmoo5oeow` (or set `AZURE_KEYVAULT_NAME`)
- External Secrets Operator deployed in cluster

## Quick Start

### One-Time Setup (New Deployment)

Generate and upload persistent certificates to Azure Key Vault:

```bash
./deployment/scripts/persistent-secrets/setup-persistent-certs.sh
```

This creates:
| Secret | Purpose |
|--------|---------|
| `IDPBUILDER-TLS-CRT` | TLS certificate (base64 PEM) |
| `IDPBUILDER-TLS-KEY` | TLS private key (base64 PEM) |
| `IDPBUILDER-CA-CRT` | CA certificate (base64 PEM) |
| `ATTIC-SIGNING-PRIVATE-KEY` | Ed25519 signing key (base64) |
| `ATTIC-SIGNING-PUBLIC-KEY` | Public key (`backstage:BASE64` format) |

After setup, update your NixOS configuration with the public key:
```bash
# The script outputs the public key to add to extra-trusted-public-keys
# Example: backstage:ABC123...
```

### Migrate Existing Cluster

Extract current certificates from a running cluster and upload to AKV:

```bash
./deployment/scripts/persistent-secrets/migrate-existing-cluster.sh
```

Use `--dry-run` to preview what would be uploaded.

### Deploy/Recreate Cluster

The standard deploy command automatically uses persistent certificates if available:

```bash
source deployment/scripts/cluster-menu.sh
cluster-recreate  # Uses persistent certs from AKV
```

Or for a fresh deploy:
```bash
cluster-deploy
```

## How It Works

### TLS Certificate Flow

1. `generate-nginx-override.sh` fetches cert from AKV at deploy time
2. Generates combined YAML with Secret + Deployment
3. idpbuilder applies this via `-c nginx:` customization
4. nginx-ingress uses `persistent-tls-cert` instead of auto-generated cert

### Attic Signing Key Flow

1. ExternalSecret `attic-signing-keypair` syncs from AKV (sync wave -95)
2. Attic StatefulSet mounts the keypair at `/etc/attic-keys/` (sync wave -90)
3. Cache creation uses persistent keypair if available, falls back to generate

## Files

| File | Purpose |
|------|---------|
| `deployment/scripts/persistent-secrets/setup-persistent-certs.sh` | One-time certificate generation |
| `deployment/scripts/persistent-secrets/generate-nginx-override.sh` | Dynamic nginx override with embedded TLS |
| `deployment/scripts/persistent-secrets/migrate-existing-cluster.sh` | Extract certs from running cluster |
| `nixidy/apps/nix-cache.nix` | ExternalSecret for Attic signing keypair |

## Verification

Check if persistent certificates are configured:

```bash
# Verify AKV secrets exist
az keyvault secret list --vault-name keyvault-thcmfmoo5oeow -o table | grep -E "(IDPBUILDER|ATTIC)"

# Verify nginx is using persistent cert
kubectl get secret persistent-tls-cert -n ingress-nginx

# Verify Attic signing keypair
kubectl get externalsecret attic-signing-keypair -n nix-cache
kubectl get secret attic-signing-keypair -n nix-cache
```

## Troubleshooting

### Certificate not being used

Check that nginx-ingress deployment has `--default-ssl-certificate=ingress-nginx/persistent-tls-cert`:

```bash
kubectl get deployment ingress-nginx-controller -n ingress-nginx -o yaml | grep default-ssl
```

### Attic keypair not syncing

Check ExternalSecret status:

```bash
kubectl describe externalsecret attic-signing-keypair -n nix-cache
```

Common issues:
- ClusterSecretStore `azure-keyvault-store` not ready
- Secrets not in Azure Key Vault (run `setup-persistent-certs.sh`)

### Fallback behavior

Without persistent certificates in AKV:
- TLS: idpbuilder generates new self-signed cert (old behavior)
- Attic: Generates new keypair on startup (requires NixOS rebuild)

## Performance Impact

Using persistent certificates **saves ~5 minutes** on cluster recreation:
- Eliminated: `sync-attic-pubkey.sh` wait (300s timeout + 10s)
- Eliminated: Certificate extraction wait (60s)
- Added: AKV fetch (~4s, parallelized)
