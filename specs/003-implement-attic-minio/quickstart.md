# Quickstart: Attic + MinIO Nix Binary Cache

**Feature**: 003-implement-attic-minio
**Audience**: Platform Engineers
**Time**: 15-20 minutes
**Prerequisites**: Kind cluster running, kubectl configured, Attic CLI installed on Hetzner host

## Overview

This guide walks through deploying MinIO and Attic to your Kubernetes cluster, initializing a cache namespace, pushing packages from your Hetzner host, and configuring NixOS VMs to consume the cache. By the end, you'll achieve 8x faster VM rebuild times (from 20-25 minutes to under 3 minutes).

## Architecture Summary

```
Hetzner Host (/nix/store)
    ↓ attic push (authenticated)
Attic Server (nix-cache namespace)
    ↓ S3 API (PutObject, GetObject)
MinIO Storage (100Gi PVC)
    ↑ HTTP (GET narinfo, NAR download)
NixOS VirtualMachines
```

**Key Components**:
- **MinIO**: S3-compatible object storage for NAR chunks (100Gi capacity)
- **Attic**: Nix binary cache server with content-addressed deduplication
- **Cache Namespace**: Logical grouping ("nixos") with dedicated signing key
- **NAR Files**: Compressed Nix archives stored as 16KB-256KB chunks in MinIO

## Prerequisites

### On Hetzner Host

1. **Attic CLI installed**:
   ```bash
   nix-env -iA nixpkgs.attic
   # Or add to system configuration:
   # environment.systemPackages = [ pkgs.attic ];
   ```

2. **kubectl configured** to access Kind cluster:
   ```bash
   kubectl get nodes
   # Should show Kind cluster nodes
   ```

3. **Sufficient disk space**:
   ```bash
   df -h /
   # Ensure at least 120GB available (100Gi MinIO PVC + overhead)
   ```

### On Kind Cluster

1. **CDK8s installed** (for synthesis):
   ```bash
   cd ~/stacks/cdk8s
   npm install
   ```

2. **ArgoCD running**:
   ```bash
   kubectl get pods -n argocd
   # Should show argocd-server, argocd-application-controller, etc.
   ```

## Step 1: Synthesize and Deploy MinIO

### 1.1 Synthesize Manifests

```bash
cd ~/stacks/cdk8s
npx ts-node main-v2.ts
```

**Expected Output**:
```
Synthesizing package: minio
  Writing manifests to dist/minio/manifests/
  - 0000-namespace.yaml (Namespace: nix-cache)
  - 0001-persistentvolumeclaim.yaml (PVC: minio-storage, 100Gi)
  - 0002-secret.yaml (Secret: minio-credentials)
  - 0003-deployment.yaml (Deployment: minio, 1 replica)
  - 0004-service.yaml (Service: minio, ports 9000/9001)
  Writing ArgoCD Application to dist/minio.yaml
```

### 1.2 Deploy via IdpBuilder

```bash
cd ~/stacks
source deployment/scripts/cluster-menu.sh
cluster-update  # Deploys all packages including MinIO
```

**Alternative** (deploy MinIO only):
```bash
idpbuilder create --package cdk8s/dist/minio
```

### 1.3 Verify Deployment

```bash
# Wait for MinIO pod to be ready
kubectl wait --for=condition=ready pod -n nix-cache -l app=minio --timeout=120s

# Check pod status
kubectl get pods -n nix-cache
# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# minio-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# Check PVC is bound
kubectl get pvc -n nix-cache
# Expected output:
# NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# minio-storage    Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   100Gi      RWO            standard       2m

# Check service
kubectl get svc -n nix-cache minio
# Expected output:
# NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
# minio   ClusterIP   10.96.xxx.xxx   <none>        9000/TCP,9001/TCP   2m
```

### 1.4 Test MinIO Connectivity (Optional)

```bash
# Port-forward to MinIO console
kubectl port-forward -n nix-cache svc/minio 9001:9001 &

# Get MinIO credentials
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD=$(kubectl get secret -n nix-cache minio-credentials -o jsonpath='{.data.secret-key}' | base64 -d)

echo "MinIO Console: http://localhost:9001"
echo "Username: $MINIO_ROOT_USER"
echo "Password: $MINIO_ROOT_PASSWORD"

# Open browser to http://localhost:9001 and login
# You should see an empty MinIO instance with no buckets yet
```

## Step 2: Synthesize and Deploy Attic

### 2.1 Verify MinIO is Ready

```bash
# Ensure MinIO is healthy before deploying Attic (sync wave dependency)
kubectl get pods -n nix-cache -l app=minio
# Pod must be Running and 1/1 Ready
```

### 2.2 Deploy Attic

```bash
# Synthesis already done in Step 1.1 (main-v2.ts synthesizes all packages)
# Deploy via cluster-update (respects sync waves: MinIO -100, Attic -90)
source deployment/scripts/cluster-menu.sh
cluster-update

# Alternative (deploy Attic only, assumes MinIO already deployed)
idpbuilder create --package cdk8s/dist/attic
```

### 2.3 Verify Deployment

```bash
# Wait for Attic pod to be ready
kubectl wait --for=condition=ready pod -n nix-cache -l app=attic --timeout=120s

# Check pod status
kubectl get pods -n nix-cache
# Expected output:
# NAME                     READY   STATUS    RESTARTS   AGE
# attic-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
# minio-xxxxxxxxxx-xxxxx   1/1     Running   0          3m

# Check service
kubectl get svc -n nix-cache attic
# Expected output:
# NAME    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# attic   ClusterIP   10.96.xxx.xxx   <none>        8080/TCP   1m

# Check logs for successful MinIO connection
kubectl logs -n nix-cache deploy/attic --tail=20
# Should see: "Connected to S3 backend: http://minio.nix-cache.svc.cluster.local:9000"
# Should NOT see connection errors or crash loops
```

## Step 3: Initialize Attic Cache

### 3.1 Generate Admin Token

```bash
# Generate JWT token with full permissions (valid for 10 years)
ADMIN_TOKEN=$(kubectl exec -n nix-cache deploy/attic -- \
  atticd-atticadm make-token \
    --sub "admin" \
    --validity "10y" \
    --pull "*" \
    --push "*" \
    --create-cache "*" \
    --configure-cache "*" \
    --destroy-cache "*")

echo "Admin Token: $ADMIN_TOKEN"
# IMPORTANT: Save this token securely (1Password, Bitwarden, etc.)
# You'll need it for cache operations from Hetzner host
```

### 3.2 Configure Attic CLI on Hetzner Host

```bash
# Port-forward Attic service to Hetzner host
kubectl port-forward -n nix-cache svc/attic 8080:8080 &

# Login to Attic (saves credentials to ~/.config/attic/config.toml)
attic login local http://localhost:8080 "$ADMIN_TOKEN"
# Expected output: "✓ Logged in to local"
```

**Alternative** (via Tailscale, no port-forward needed):
```bash
# If cluster is accessible via Tailscale:
attic login local http://<tailscale-ip>:8080 "$ADMIN_TOKEN"
```

### 3.3 Create Cache Namespace

```bash
# Create "nixos" cache (generates unique signing key pair)
attic cache create nixos
# Expected output:
# ✓ Created cache "nixos"

# Retrieve cache information and public key
attic cache info nixos
# Expected output:
# Cache: nixos
# Public key: nixos:ABC123DEF456GHI789JKL012MNO345PQR678STU901VWX234YZ=
# Created: 2025-10-11T12:00:00Z
# Packages: 0
# Total size: 0 B
```

### 3.4 Save Cache Public Key

```bash
# Extract public key for VM configuration
CACHE_PUBLIC_KEY=$(attic cache info nixos | grep "Public key:" | awk '{print $3}')
echo "Cache Public Key: $CACHE_PUBLIC_KEY"

# IMPORTANT: Save this public key - you'll add it to VM configuration
# Example: nixos:ABC123DEF456GHI789JKL012MNO345PQR678STU901VWX234YZ=
```

## Step 4: Populate Cache from Hetzner Host

### 4.1 Push System Closure

```bash
# Push current system closure (includes all dependencies)
attic push nixos /run/current-system

# Expected output:
# → Pushing 150 packages to nixos
# → Uploading NARs... (this may take 5-10 minutes for first push)
# → Signing narinfos...
# ✓ Pushed 150 packages (20 GB uncompressed, 6 GB after deduplication)
```

**Performance Expectations**:
- First push: 5-10 minutes for full system closure (~20GB uncompressed)
- Subsequent pushes: 1-2 minutes (only new packages uploaded, deduplication skips existing chunks)
- Upload speed: 50-200 MB/s depending on network

### 4.2 Verify Cache Contents

```bash
# Check cache statistics
attic cache info nixos
# Expected output:
# Cache: nixos
# Public key: nixos:ABC123...
# Created: 2025-10-11T12:00:00Z
# Packages: 150
# Total size: 6.2 GB  (after deduplication)

# List specific packages (optional)
nix-store -qR /run/current-system | head -10
# These store paths should now be in Attic cache
```

### 4.3 Test Cache Query (Optional)

```bash
# Pick a store path from your system
STORE_PATH="/nix/store/abc123def456-package-name-1.0"
STORE_HASH=$(basename "$STORE_PATH" | cut -d'-' -f1)

# Query narinfo from Attic
curl -v http://localhost:8080/nixos/${STORE_HASH}.narinfo

# Expected response: HTTP/1.1 200 OK
# Body should contain:
# StorePath: /nix/store/abc123def456-package-name-1.0
# URL: nar/def456abc123...uvw321.nar.zst
# Compression: zstd
# FileHash: sha256:def456abc123...
# NarHash: sha256:abc123def456...
# Sig: nixos:ABC123...signature...
```

## Step 5: Configure NixOS VMs to Use Attic Cache

### 5.1 Update VM NixOS Configuration

Add the following to your NixOS VM configuration (e.g., `nixos-config/base-vm-config.nix`):

```nix
{ config, pkgs, ... }:

{
  nix.settings = {
    # Attic cache as primary substituter (falls back to cache.nixos.org if miss)
    substituters = [
      "http://attic.nix-cache.svc.cluster.local:8080/nixos"
      "https://cache.nixos.org"
    ];

    # Trust Attic cache public key for signature verification
    trusted-public-keys = [
      "nixos:ABC123DEF456GHI789JKL012MNO345PQR678STU901VWX234YZ="  # REPLACE with your cache public key
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    # Optional: Prioritize Attic cache over cache.nixos.org
    # Lower priority value = higher preference (default is 40)
    # trusted-substituters = [ "http://attic.nix-cache.svc.cluster.local:8080/nixos" ];
  };
}
```

**IMPORTANT**: Replace `nixos:ABC123...` with your actual cache public key from Step 3.4.

### 5.2 Rebuild VM Configuration

If using the KubeVirt implementation from spec 002, update your VM DataVolume:

```bash
# Update the nixos-config ConfigMap or cloud-init data with the new substituters
# Then recreate the VM DataVolume (immutable, requires recreation)

# Example: Update cloud-init user-data in DataVolume spec
kubectl edit datavolumetemplates -n dev-vcluster nixos-vm-dv

# Or regenerate via CDK8s chart and redeploy
cd ~/stacks/cdk8s
# (Update VM chart to include new nix.settings)
npx ts-node main-v2.ts
cluster-update
```

**Alternative** (live VM reconfiguration):
```bash
# SSH into running VM
ssh root@<vm-ip>

# Edit /etc/nixos/configuration.nix to add substituters
nano /etc/nixos/configuration.nix
# (Add nix.settings block from Step 5.1)

# Rebuild system
nixos-rebuild switch

# Verify substituters
nix show-config | grep substituters
# Expected output:
# substituters = http://attic.nix-cache.svc.cluster.local:8080/nixos https://cache.nixos.org
```

### 5.3 Verify Cache Connectivity from VM

```bash
# SSH into VM
ssh root@<vm-ip>

# Test narinfo query (should succeed)
curl -I http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info
# Expected: HTTP/1.1 200 OK

# Test package query
nix-store --store http://attic.nix-cache.svc.cluster.local:8080/nixos \
  -q --valid-paths | head -5
# Expected: List of store paths cached in Attic

# Check cache priority
nix show-config | grep priority
# Attic cache should have priority 40 (higher than cache.nixos.org at 50)
```

## Step 6: Test Performance Improvement

### 6.1 Baseline Measurement (Before Attic)

```bash
# Remove Attic substituter temporarily to measure baseline
ssh root@<vm-ip>
nix-collect-garbage -d  # Clear local cache
nixos-rebuild switch --option substituters "https://cache.nixos.org"

# Measure time:
# Expected: 20-25 minutes (downloading from cache.nixos.org)
```

### 6.2 Attic-Accelerated Rebuild

```bash
# Restore Attic substituter
ssh root@<vm-ip>
nix-collect-garbage -d  # Clear local cache again

# Rebuild with Attic cache
time nixos-rebuild switch

# Measure time:
# Expected: Under 3 minutes (80%+ cache hit rate from Attic)
# Download speed: 100-500 MB/s (in-cluster network)
```

### 6.3 Verify Cache Hit Rate

```bash
# Check Nix daemon logs on VM
journalctl -u nix-daemon.service --since "5 minutes ago" | grep substituter
# Expected output:
# copying path '/nix/store/abc123...' from 'http://attic.nix-cache.svc.cluster.local:8080/nixos'...
# copying path '/nix/store/def456...' from 'http://attic.nix-cache.svc.cluster.local:8080/nixos'...
# (Should see mostly Attic URLs, minimal cache.nixos.org fallbacks)
```

**Success Criteria**:
- ✅ VM rebuild time: Under 3 minutes (vs 20-25 minutes baseline)
- ✅ Cache hit rate: 80%+ packages downloaded from Attic
- ✅ Download speed: 100-500 MB/s average
- ✅ No signature verification errors (trusted-public-keys configured correctly)

## Troubleshooting

### MinIO Pod CrashLoopBackOff

**Symptom**: `kubectl get pods -n nix-cache` shows MinIO pod restarting
**Cause**: Insufficient disk space or PVC provisioning failure
**Fix**:
```bash
# Check PVC status
kubectl get pvc -n nix-cache minio-storage
# If Pending: Check available disk space on Kind node

# Check MinIO logs
kubectl logs -n nix-cache deploy/minio --tail=50
# Look for disk errors or permission issues

# If disk full: Resize PVC or clean up Kind cluster
docker exec -it <kind-node-name> df -h /
```

### Attic Pod CrashLoopBackOff

**Symptom**: Attic pod fails to start, logs show S3 connection errors
**Cause**: MinIO not ready or network connectivity issue
**Fix**:
```bash
# Verify MinIO is Running and Ready
kubectl get pods -n nix-cache -l app=minio
# Must show 1/1 Ready before Attic can start

# Check Attic logs
kubectl logs -n nix-cache deploy/attic --tail=50
# Look for: "Failed to connect to S3 backend" or DNS resolution errors

# Test MinIO DNS resolution from Attic pod
kubectl exec -n nix-cache deploy/attic -- nslookup minio.nix-cache.svc.cluster.local
# Should resolve to MinIO ClusterIP

# If DNS fails: Check CoreDNS pods in kube-system namespace
```

### Cache Push Fails: 401 Unauthorized

**Symptom**: `attic push` fails with "Invalid or missing authentication token"
**Cause**: Admin token expired or not configured
**Fix**:
```bash
# Regenerate admin token (Step 3.1)
ADMIN_TOKEN=$(kubectl exec -n nix-cache deploy/attic -- \
  atticd-atticadm make-token --sub "admin" --validity "10y" \
  --pull "*" --push "*" --create-cache "*")

# Re-login to Attic
attic login local http://localhost:8080 "$ADMIN_TOKEN"

# Verify login
attic cache list
# Should show "nixos" cache
```

### VM Cannot Reach Attic Cache

**Symptom**: VM rebuild downloads all packages from cache.nixos.org, ignoring Attic
**Cause**: DNS resolution failure or incorrect substituter URL
**Fix**:
```bash
# SSH into VM
ssh root@<vm-ip>

# Test Attic connectivity
curl -v http://attic.nix-cache.svc.cluster.local:8080/nixos/nix-cache-info
# Expected: HTTP/1.1 200 OK

# If connection refused: Check Service exists
kubectl get svc -n nix-cache attic
# Must show ClusterIP and port 8080

# If DNS fails: VM may not have cluster DNS configured
# Check /etc/resolv.conf in VM:
cat /etc/resolv.conf
# Should contain: nameserver 10.96.0.10 (cluster DNS)

# If missing: Add to cloud-init network config (see spec 002 for details)
```

### Signature Verification Errors

**Symptom**: VM logs show "signature verification failed for narinfo"
**Cause**: Incorrect cache public key in trusted-public-keys
**Fix**:
```bash
# Retrieve correct public key from Attic
attic cache info nixos | grep "Public key:"
# Copy the full key: nixos:ABC123...

# Update VM configuration (Step 5.1) with correct key
# Rebuild VM or live-edit /etc/nixos/configuration.nix
ssh root@<vm-ip>
nixos-rebuild switch

# Verify trusted keys
nix show-config | grep trusted-public-keys
# Must include Attic cache public key
```

### Cache Hit Rate Lower Than Expected

**Symptom**: VM still downloads many packages from cache.nixos.org (not Attic)
**Cause**: Cache not fully populated with required packages
**Fix**:
```bash
# Push additional closures from Hetzner host
attic push nixos /nix/store/abc123-package-name-1.0  # Specific package
attic push nixos $(nix-build '<nixpkgs>' -A firefox)  # Build and push Firefox

# Push all installed packages
nix-store -qR /run/current-system | xargs attic push nixos

# Verify cache now contains more packages
attic cache info nixos
# Check Packages count increased
```

### MinIO Bucket Not Created

**Symptom**: Attic logs show "NoSuchBucket: attic-cache"
**Cause**: Attic does not auto-create buckets; must be done manually or via init script
**Fix**:
```bash
# Option 1: Use MinIO CLI (mc)
# Port-forward to MinIO
kubectl port-forward -n nix-cache svc/minio 9000:9000 &

# Get credentials
MINIO_ROOT_PASSWORD=$(kubectl get secret -n nix-cache minio-credentials -o jsonpath='{.data.secret-key}' | base64 -d)

# Configure mc alias
mc alias set local http://localhost:9000 admin "$MINIO_ROOT_PASSWORD"

# Create bucket
mc mb local/attic-cache
# Expected: "Bucket created successfully"

# Option 2: Use Attic init (if supported by version)
kubectl exec -n nix-cache deploy/attic -- atticd init
# May auto-create bucket on first run
```

## Maintenance Tasks

### Viewing Cache Statistics

```bash
# Summary
attic cache info nixos

# Detailed package list (requires Attic CLI with list feature)
# Note: Not all Attic versions support this
attic cache list nixos
```

### Manually Testing Package Availability

```bash
# From Hetzner host
STORE_HASH="abc123def456"  # Replace with actual hash
curl http://localhost:8080/nixos/${STORE_HASH}.narinfo

# Expected for cache hit: HTTP/1.1 200 OK with narinfo body
# Expected for cache miss: HTTP/1.1 404 Not Found
```

### Monitoring Disk Usage

```bash
# Check MinIO PVC usage
kubectl exec -n nix-cache deploy/minio -- df -h /data
# Expected output:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/xxx        100G  6.2G   94G   7% /data

# Warning: If usage exceeds 90%, consider:
# 1. Implementing garbage collection (delete unused NARs)
# 2. Increasing PVC size (requires PVC resize or recreation)
# 3. Clearing old/unused cache namespaces
```

### Backing Up Attic Database (Optional)

```bash
# Attic SQLite database contains narinfo metadata (NOT NAR files)
# Database is ephemeral (emptyDir volume) - regenerate by re-pushing packages

# If persistent backup needed:
kubectl cp nix-cache/attic-xxxxxxxxxx-xxxxx:/var/lib/atticd/server.db ./attic-backup.db

# Restore (requires pod recreation):
kubectl cp ./attic-backup.db nix-cache/attic-xxxxxxxxxx-xxxxx:/var/lib/atticd/server.db
kubectl delete pod -n nix-cache -l app=attic  # Restart pod
```

## Next Steps

After completing this quickstart, consider:

1. **Automate Cache Population**: Set up CI/CD pipeline to push packages to Attic after successful builds
2. **Multi-Environment Caching**: Create separate cache namespaces (dev, staging, prod) if needed
3. **Garbage Collection**: Implement periodic cleanup of unused NARs to reclaim disk space
4. **Monitoring**: Add Prometheus metrics for cache hit rate, download speed, storage usage
5. **High Availability**: Migrate from SQLite to PostgreSQL backend for multi-replica Attic deployment

## Success Validation Checklist

- [ ] MinIO pod Running and Ready in nix-cache namespace
- [ ] MinIO PVC bound with 100Gi capacity
- [ ] Attic pod Running and Ready in nix-cache namespace
- [ ] Attic successfully connected to MinIO S3 backend (check logs)
- [ ] "nixos" cache namespace created with unique signing key
- [ ] Cache public key saved and added to VM configuration
- [ ] System closure pushed to Attic (150+ packages)
- [ ] Cache info shows 6+ GB storage used (after deduplication)
- [ ] NixOS VM nix.settings configured with Attic substituter
- [ ] VM can query Attic nix-cache-info endpoint (HTTP 200)
- [ ] VM rebuild time reduced to under 3 minutes (vs 20-25 min baseline)
- [ ] Cache hit rate 80%+ (check nix-daemon logs)
- [ ] No signature verification errors in VM logs
- [ ] Download speed 100-500 MB/s from Attic cache

**Status**: ✅ Attic + MinIO binary cache operational

For implementation details, see:
- [research.md](./research.md) - Architecture decisions and CDK8s patterns
- [data-model.md](./data-model.md) - Entity relationships and data flows
- [contracts/minio-s3-api.md](./contracts/minio-s3-api.md) - MinIO S3 API contract
- [contracts/attic-rest-api.md](./contracts/attic-rest-api.md) - Attic HTTP API contract
