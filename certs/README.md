# System Certificates Directory

This directory contains certificates installed into system trust stores by `scripts/sync-cluster-certificates.sh`.

## Purpose

**System-level certificate storage** for:
- System CA bundle with IDPBuilder cert (`ca-bundle-with-idpbuilder.crt`)
- IDPBuilder CA certificate (`idpbuilder-ca.crt`)
- TLS certificate (`idpbuilder-tls.crt`)

## Relationship to certificates/

- `certificates/` - **Cache** of certificates extracted from cluster
- `certs/` - **System** certificates ready for trust store installation

The workflow:
1. Extract certs from cluster → `certificates/`
2. Process and prepare for system → `certs/`
3. Install to system trust stores (requires root)

## Usage

Certificates are automatically synced by:
```bash
scripts/sync-cluster-certificates.sh
```

Or as part of cluster deployment:
```bash
deployment/scripts/deploy-linux-ssh.sh
```

## Referenced By

- `deployment/scripts/cluster-menu.sh` - Sets SSL_CERT_FILE to ca-bundle
- `scripts/sync-cluster-certificates.sh` - Manages certificate lifecycle
- `scripts/setup-firefox-policies.sh` - Firefox certificate trust

## Gitignored

All certificate files (*.crt, *.key, *.pem) are gitignored. Only this README is tracked.

**Do not commit certificate files** - they are runtime-generated and cluster-specific.
