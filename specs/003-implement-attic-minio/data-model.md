# Data Model: Attic + MinIO Nix Binary Cache

**Feature**: 003-implement-attic-minio
**Phase**: 1 (Design)
**Date**: 2025-10-11

## Overview

This document defines the entity relationships and data flow for the Attic + MinIO Nix binary cache system. The model describes how Nix packages flow from the Hetzner host through Attic into MinIO storage, and how NixOS VMs retrieve cached packages via the Attic HTTP API.

## Entity Definitions

### MinIO (S3-Compatible Object Storage)

**Purpose**: Durable storage backend for Attic, stores chunked NAR files and metadata

**Attributes**:
- `endpoint`: Service endpoint URL (http://minio.nix-cache.svc.cluster.local:9000)
- `accessKey`: S3 access key ID (stored in minio-credentials Secret)
- `secretKey`: S3 secret access key (stored in minio-credentials Secret)
- `region`: S3 region (us-east-1, ignored by MinIO)
- `bucket`: S3 bucket name ("attic-cache")
- `storageCapacity`: PVC size (100Gi)
- `storageUsed`: Current disk usage (observed via MinIO console)

**Kubernetes Resources**:
- Namespace: `nix-cache`
- Deployment: `minio` (1 replica)
- Service: `minio` (ClusterIP, ports 9000/9001)
- PVC: `minio-storage` (100Gi, ReadWriteOnce)
- Secret: `minio-credentials` (access-key, secret-key)

**State Transitions**:
- `Pending` → `Running`: Pod scheduled, image pulled, container started
- `Running` → `Ready`: Health check passes (TCP 9000 accessible)
- `Ready` → `Failed`: Disk full, container crash, node failure

### Attic Server (Nix Binary Cache)

**Purpose**: HTTP server managing cache namespaces, signing keys, and NAR retrieval from MinIO

**Attributes**:
- `endpoint`: Service endpoint URL (http://attic.nix-cache.svc.cluster.local:8080)
- `storageBackend`: MinIO S3 configuration (endpoint, bucket, credentials)
- `database`: SQLite database path (/var/lib/atticd/server.db)
- `chunkingConfig`: NAR chunking parameters (nar-size-threshold, min/avg/max-size)
- `compressionConfig`: Compression settings (zstd, level 8)

**Kubernetes Resources**:
- Namespace: `nix-cache`
- Deployment: `attic` (1 replica)
- Service: `attic` (ClusterIP, port 8080)
- ConfigMap: `attic-config` (server.toml configuration file)
- Secret: Uses `minio-credentials` for S3 backend authentication
- Volume: `emptyDir` for SQLite database (ephemeral, metadata only)

**State Transitions**:
- `Pending` → `Running`: Pod scheduled, MinIO connection established
- `Running` → `Ready`: HTTP server listening on port 8080
- `Ready` → `Failed`: MinIO unreachable, SQLite corruption, container crash

**Operations**:
- `CreateCache(name)`: Create new cache namespace with unique signing key pair
- `PushPackage(cache, storePath)`: Upload NAR from external host to MinIO via Attic
- `QueryPackage(cache, storeHash)`: Check if package exists in cache (returns narinfo)
- `DownloadNAR(cache, narHash)`: Stream NAR from MinIO to client
- `GetCacheInfo(cache)`: Retrieve cache public key and metadata

### Attic Cache (Namespace)

**Purpose**: Logical grouping of packages with dedicated signing key, references NARs in MinIO

**Attributes**:
- `name`: Cache identifier (e.g., "nixos")
- `publicKey`: Ed25519 public key for signature verification
- `privateKey`: Ed25519 private key for signing NARs (stored in Attic DB)
- `packagesCount`: Number of unique store paths in cache
- `totalSize`: Total storage used (after deduplication)
- `createdAt`: Timestamp when cache was created

**Relationships**:
- `1:N` with NARs - One cache references many NARs (NAR can be shared across caches via global deduplication)
- `1:1` with MinIO bucket - All caches store NARs in single "attic-cache" bucket (deduplication key)

**State Transitions**:
- `Created`: Cache namespace exists, signing key generated
- `Active`: Accepting package pushes and serving downloads
- `Archived`: Read-only mode (future feature, not MVP)
- `Deleted`: Cache namespace removed, NAR references deleted (NARs remain in MinIO until garbage collection)

### NAR (Nix ARchive)

**Purpose**: Normalized archive format containing Nix package contents, stored in MinIO with content-addressed deduplication

**Attributes**:
- `storeHash`: Nix store path hash (e.g., "abc123def456...")
- `storePath`: Full Nix store path (/nix/store/abc123def456...-package-name-version)
- `narHash`: Content hash of NAR file (sha256)
- `narSize`: Uncompressed NAR size (bytes)
- `compression`: Compression format (zstd)
- `compressionLevel`: Compression level (8)
- `chunks`: Array of chunk hashes (content-addressed splitting)
- `references`: List of runtime dependencies (other store paths)
- `signature`: Ed25519 signature by cache private key

**Storage in MinIO**:
- **Chunked NARs**: Stored as objects with keys like `nar/<chunk-hash>.nar.zst`
- **Narinfo metadata**: Stored in Attic SQLite DB, not MinIO (cache: storeHash → narHash, references, signature)

**Content-Addressed Chunking**:
- **Algorithm**: FastCDC (Fast Content-Defined Chunking)
- **Parameters**:
  - `nar-size-threshold`: 64KB (NARs smaller than this are stored unchunked)
  - `min-size`: 16KB (minimum chunk size)
  - `avg-size`: 64KB (target average chunk size)
  - `max-size`: 256KB (maximum chunk size)
- **Benefit**: Identical chunks across different NARs are deduplicated (single copy in MinIO)

**State Transitions**:
- `Uploading`: NAR being pushed from Hetzner host, chunks written to MinIO
- `Stored`: All chunks written to MinIO, narinfo indexed in Attic DB
- `Cached`: At least one cache references this NAR
- `Orphaned`: No caches reference NAR (eligible for garbage collection, future feature)

### Cache Signing Key

**Purpose**: Cryptographic key pair for signing and verifying NAR authenticity

**Attributes**:
- `algorithm`: Ed25519 (public-key signature scheme)
- `publicKey`: Base64-encoded public key (distributed to NixOS VMs)
- `privateKey`: Base64-encoded private key (stored in Attic SQLite DB, never exposed)
- `createdAt`: Timestamp when key pair was generated

**Usage**:
- **Signing (Attic)**: When NAR is pushed, Attic signs narinfo with cache private key
- **Verification (Nix Daemon)**: VM's Nix daemon verifies signature using cache public key from `trusted-public-keys`

**Key Distribution**:
- **Public key**: Retrieved via `attic cache info nixos` command, added to VM configuration
- **Private key**: Never leaves Attic pod, stored in SQLite DB (/var/lib/atticd/server.db)

### Admin Token (JWT Bearer Token)

**Purpose**: Authentication token for Attic API operations (create cache, push packages, configure)

**Attributes**:
- `sub`: Subject (e.g., "admin")
- `validity`: Token expiration (e.g., "10y")
- `permissions`: Scopes (pull, push, create-cache, configure-cache, destroy-cache)
- `token`: JWT string (used in Authorization: Bearer <token> header)

**Lifecycle**:
- **Generation**: `atticd-atticadm make-token` command in Attic pod
- **Storage**: Stored by operator, not in Kubernetes (sensitive, short-term use for cache init)
- **Usage**: `attic login local <url> <token>` configures Attic CLI for cache operations

## Entity Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                      Hetzner Host                           │
│  - /nix/store (system closure)                              │
│  - Attic CLI (authenticated with admin token)               │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ attic push nixos /run/current-system
                  ↓
┌─────────────────────────────────────────────────────────────┐
│                   Attic Server (Pod)                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Cache "nixos"                                        │  │
│  │  - publicKey: nixos:ABC123...                         │  │
│  │  - privateKey: (stored in SQLite)                     │  │
│  │  - packagesCount: 150                                 │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  SQLite Database (/var/lib/atticd/server.db)         │  │
│  │  - narinfo index: storeHash → narHash, references    │  │
│  │  - cache metadata: name, keys, timestamps            │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ S3 API: PutObject (chunked NARs)
                  ↓
┌─────────────────────────────────────────────────────────────┐
│              MinIO (S3 Storage Backend)                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Bucket: attic-cache                                  │  │
│  │  - nar/<chunk-hash-1>.nar.zst   (16KB)               │  │
│  │  - nar/<chunk-hash-2>.nar.zst   (64KB)               │  │
│  │  - nar/<chunk-hash-3>.nar.zst   (256KB)              │  │
│  │  - ... (thousands of deduplicated chunks)            │  │
│  └───────────────────────────────────────────────────────┘  │
│  Storage: 100Gi PVC (minio-storage)                         │
└─────────────────┬───────────────────────────────────────────┘
                  ↑
                  │ HTTP: GET /nixos/<storehash>.narinfo
                  │       GET /nixos/nar/<narhash>.nar.zst
                  │
┌─────────────────┴───────────────────────────────────────────┐
│              NixOS VirtualMachine (VM)                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Nix Daemon                                           │  │
│  │  substituters:                                        │  │
│  │    - http://attic.nix-cache.svc.cluster.local:8080/  │  │
│  │      nixos                                            │  │
│  │    - https://cache.nixos.org (fallback)              │  │
│  │  trusted-public-keys:                                 │  │
│  │    - nixos:ABC123... (Attic cache public key)        │  │
│  │    - cache.nixos.org-1:... (official cache)          │  │
│  └───────────────────────────────────────────────────────┘  │
│  /nix/store (local package database)                        │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### Flow 1: Push Package to Cache (Hetzner → Attic → MinIO)

1. **Operator initiates push**: `attic push nixos /nix/store/abc123...`
2. **Attic CLI authenticates**: Sends JWT bearer token in Authorization header
3. **Attic reads package**: NAR serialized from /nix/store on Hetzner host
4. **Content-addressed chunking**: Attic splits NAR into 16KB-256KB chunks using FastCDC
5. **Check for existing chunks**: Query MinIO for chunk hashes (deduplication check)
6. **Upload missing chunks**: PutObject API calls to MinIO bucket "attic-cache"
7. **Store metadata**: Insert narinfo into Attic SQLite DB (storeHash, narHash, references, signature)
8. **Sign narinfo**: Attic signs metadata with cache private key (Ed25519)
9. **Response**: Attic confirms successful push with NAR hash and signature

### Flow 2: Download Package from Cache (VM → Attic → MinIO)

1. **Nix daemon queries cache**: `GET http://attic../nixos/abc123....narinfo`
2. **Attic looks up narinfo**: Query SQLite DB for storeHash index
3. **Cache hit**: Attic responds with narinfo (NAR URL, size, hash, signature)
4. **Nix verifies signature**: Check signature using cache public key from trusted-public-keys
5. **Nix requests NAR**: `GET http://attic../nixos/nar/<narhash>.nar.zst`
6. **Attic streams NAR**: Reconstructs NAR from chunks in MinIO (GetObject API)
7. **Attic compresses**: Apply zstd compression (level 8) during streaming
8. **Nix decompresses**: Decompress zstd NAR and verify hash
9. **Nix installs package**: Extract NAR contents to /nix/store

### Flow 3: Cache Miss and Fallback (VM → Attic → cache.nixos.org)

1. **Nix daemon queries Attic**: `GET http://attic../nixos/abc123....narinfo`
2. **Attic looks up narinfo**: Query SQLite DB for storeHash index
3. **Cache miss**: No entry found, Attic responds with 404 Not Found
4. **Nix falls back**: Query next substituter (cache.nixos.org)
5. **Download from upstream**: Nix retrieves package from cache.nixos.org (20-50 MB/s)
6. **Nix installs package**: Extract NAR contents to /nix/store (not pushed back to Attic automatically)

**Note**: Cache population is manual via `attic push` command. Automatic push-on-miss is not implemented in MVP.

## Validation Rules

### MinIO
- PVC size MUST be at least 100Gi (storage capacity for 5-10 system closures)
- Bucket name MUST match Attic configuration (attic-cache)
- S3 credentials MUST be stored in Kubernetes Secret (access-key, secret-key)
- Resource limits MUST be set (512Mi-2Gi memory, 250m-1000m CPU)

### Attic
- MUST connect to MinIO on startup (fail fast if S3 backend unreachable)
- SQLite database MUST be writable (emptyDir volume with sufficient space)
- Chunking parameters MUST be configured (nar-size-threshold, min/avg/max-size)
- Compression MUST be enabled (zstd level 8)
- Resource limits MUST be set (256Mi-1Gi memory, 100m-500m CPU)

### Cache
- Cache name MUST be unique per Attic instance
- Public key MUST be distributed to VMs (trusted-public-keys configuration)
- Private key MUST never be exposed outside Attic pod

### NAR
- NAR hash MUST be verified by Nix daemon before installation
- Signature MUST be valid (signed by cache private key matching trusted public key)
- References MUST be resolvable (dependent packages available in cache or upstream)

## Performance Considerations

- **Global deduplication**: Identical chunks across NARs stored once (30% storage savings)
- **Content-addressed chunking**: 64KB average chunk size balances deduplication vs metadata overhead
- **In-cluster latency**: 1-10ms (Attic → MinIO) vs 50-200ms (VM → cache.nixos.org)
- **Download speed**: 100-500 MB/s (in-cluster) vs 10-50 MB/s (internet)
- **Cache hit rate**: Target 80%+ after initial cache population
- **Concurrent downloads**: Support 3-5 VMs downloading simultaneously without contention

## Security Model

- **Attic admin token**: Required for cache creation and package uploads (stored securely by operator)
- **Cache signing key**: Private key never leaves Attic pod, stored in SQLite DB
- **Public key distribution**: Safe to distribute (only used for signature verification)
- **MinIO credentials**: Stored in Kubernetes Secret, mounted as environment variables
- **Network isolation**: Attic/MinIO communicate via ClusterIP Services (no external exposure)
- **VM authentication**: No authentication required for downloads (public cache model)

## Future Enhancements (Not MVP)

- **Garbage collection**: Automatically delete orphaned NARs (no cache references)
- **Multi-tenancy**: Separate cache namespaces per environment (dev, staging, prod)
- **Automatic population**: Push packages to Attic on cache miss (passive caching)
- **Prometheus metrics**: Expose cache hit rate, download speed, storage usage
- **PostgreSQL backend**: Replace SQLite for multi-replica Attic deployment
- **External ingress**: Expose Attic to CI/CD pipelines outside cluster
