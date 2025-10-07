# Scripts Directory

Modular organization of utility scripts for the stacks project.

## Structure

```
scripts/
├── certificates/          Certificate management and trust store operations
│   ├── sync-cluster-certificates.sh    Extract certs from cluster, install to system
│   ├── setup-browser-certs.sh          Import CA certs to Firefox/Chromium profiles
│   ├── setup-firefox-policies.sh       Configure Firefox enterprise policies
│   ├── cache/                          Cached certificates extracted from cluster
│   └── system/                         System-ready certificates for trust stores
│
└── cluster/               Cluster-specific operations and utilities
    ├── fix-docker-nixos.sh            Fix Docker socket permissions on NixOS
    ├── remove-core-dns-package.sh     Clean up legacy CoreDNS overrides
    ├── setup-headlamp-access.sh       Configure Headlamp service account
    └── update-argocd-token.sh         Sync ArgoCD token to 1Password
```

## Certificates Module

### Purpose
Manages IDPBuilder CA certificates across local system trust stores, Docker, and browser profiles.

### Certificate Workflow
1. **Extract** from cluster → `cache/` directory
2. **Process** and prepare → `system/` directory
3. **Install** to system trust stores (requires root)
4. **Import** to browser profiles (user-level)

### Key Scripts

**sync-cluster-certificates.sh**
- Extracts TLS certificate and CA from cluster secret (`idpbuilder-cert` in `ingress-nginx`)
- Caches to `cache/` directory with fingerprint tracking
- Prepares system certificates in `system/` directory
- Installs to system trust stores (`/usr/local/share/ca-certificates/`)
- Configures Docker trust store (`/etc/docker/certs.d/`)
- Triggers browser certificate import

**Modes:**
- Default: Extract from cluster + install to system
- `--system`: Only install (used by systemd service)
- `--force`: Re-extract even if fingerprint unchanged

**setup-browser-certs.sh**
- Imports CA certificate to Firefox and Chromium profiles
- Uses `certutil` from NSS tools
- Scans user home directory for browser profiles
- Idempotent (checks if cert already imported)

**setup-firefox-policies.sh**
- Configures Firefox enterprise policies for certificate trust
- Creates `/etc/firefox/policies/policies.json`
- Alternative to profile-level certutil approach

### Certificate Directories

**cache/**
- Runtime certificate cache extracted from cluster
- Contains: `tls.crt`, `tls.key`, `ca.crt`, `ca-bundle-with-idpbuilder.crt`
- Tracks certificate fingerprints to detect changes
- Gitignored (regenerated from cluster)

**system/**
- System-ready certificates for distribution
- Contains:
  - `idpbuilder-ca.crt` - CA certificate
  - `idpbuilder-tls.crt` - TLS certificate
  - `ca-bundle-with-idpbuilder.crt` - System CA bundle + IDPBuilder CA
- Used by systemd service and manual installations
- Gitignored (regenerated from cluster)

### Environment Variables
- `CERT_SECRET_NAME` - Kubernetes secret name (default: `idpbuilder-cert`)
- `CERT_NAMESPACE` - Namespace for secret (default: `ingress-nginx`)
- `REGISTRY_HOST` - Container registry hostname (default: `gitea.cnoe.localtest.me:8443`)
- `STACKS_DIR` - Project root directory (default: `$HOME/stacks`)
- `TARGET_USER` - User for Docker certs (default: current user)

### Usage Examples

Extract and install certificates after cluster creation:
```bash
./scripts/certificates/sync-cluster-certificates.sh
```

Force re-extraction even if unchanged:
```bash
./scripts/certificates/sync-cluster-certificates.sh --force
```

Only install (systemd service mode):
```bash
sudo ./scripts/certificates/sync-cluster-certificates.sh --system
```

Import to browser profiles:
```bash
./scripts/certificates/setup-browser-certs.sh --cert-file ./scripts/certificates/system/idpbuilder-ca.crt
```

## Cluster Module

### Purpose
Operations specific to Kind cluster management and Kubernetes utilities.

### Key Scripts

**fix-docker-nixos.sh**
- Fixes Docker socket permissions on NixOS systems
- Ensures current user can access `/var/run/docker.sock`
- Used during cluster creation on NixOS hosts

**remove-core-dns-package.sh**
- Removes legacy ArgoCD Application for CoreDNS overrides
- Cleans up from previous architecture where CoreDNS was manually managed
- Idempotent (safe to run multiple times)

**setup-headlamp-access.sh**
- Creates Headlamp service account with cluster-admin privileges
- Generates long-lived token for Headlamp UI
- Configures RBAC for dashboard access

**update-argocd-token.sh**
- Extracts ArgoCD admin token from cluster
- Stores in 1Password CLI (`op` command)
- Useful for CI/CD and automation

### Usage Examples

Fix Docker permissions (NixOS):
```bash
sudo ./scripts/cluster/fix-docker-nixos.sh
```

Clean up CoreDNS overrides:
```bash
./scripts/cluster/remove-core-dns-package.sh
```

Setup Headlamp access:
```bash
./scripts/cluster/setup-headlamp-access.sh
```

Update ArgoCD token in 1Password:
```bash
./scripts/cluster/update-argocd-token.sh
```

## Integration with Deployment

The deployment scripts (`deployment/scripts/`) automatically reference these utility scripts:

**deploy-linux-ssh.sh** calls:
- `scripts/cluster/remove-core-dns-package.sh` (cleanup)
- `scripts/certificates/sync-cluster-certificates.sh` (post-deployment)
- `scripts/certificates/setup-browser-certs.sh` (browser trust)
- `scripts/cluster/update-argocd-token.sh` (1Password sync)

**cluster-menu.sh** uses:
- `scripts/certificates/system/ca-bundle-with-idpbuilder.crt` (SSL_CERT_FILE)

## Notes

- All scripts use `set -euo pipefail` for error handling
- Scripts are idempotent (safe to run multiple times)
- Certificate scripts gracefully handle missing dependencies
- Colored output using ANSI escape codes (GREEN, YELLOW, RED)
- Root operations use `sudo` automatically when needed
- Scripts detect their location dynamically (portable)

## Troubleshooting

**Certificates not updating:**
- Check cluster secret exists: `kubectl get secret idpbuilder-cert -n ingress-nginx`
- Force re-extraction: `./scripts/certificates/sync-cluster-certificates.sh --force`

**Browser import fails:**
- Install NSS tools: `nix-env -iA nixpkgs.nss`
- Check certutil: `which certutil`

**Permission denied errors:**
- System trust store requires root: `sudo ./scripts/certificates/sync-cluster-certificates.sh --system`
- Browser import runs as user (no sudo needed)

**Docker trust issues:**
- Verify Docker config: `ls -la /etc/docker/certs.d/`
- Check user Docker config: `ls -la ~/.docker/certs.d/`

## Future Improvements

- [ ] Systemd service for automatic certificate sync
- [ ] Certificate expiration monitoring
- [ ] Prometheus metrics for certificate health
- [ ] Helm-based certificate management
- [ ] Multi-cluster certificate coordination
