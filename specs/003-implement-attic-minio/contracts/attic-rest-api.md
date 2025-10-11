# Contract: Attic REST API

**Feature**: 003-implement-attic-minio
**Component**: Attic Binary Cache Server
**Protocol**: HTTP REST API (Nix cache protocol + Attic management extensions)
**Date**: 2025-10-11

## Overview

This contract defines the HTTP REST API exposed by Attic for Nix package caching operations and cache management. The API consists of two parts: (1) Nix Cache Protocol endpoints for NixOS VMs to query/download packages, (2) Attic Management API for creating caches and pushing packages.

## Base Endpoint

```
http://attic.nix-cache.svc.cluster.local:8080
```

**Authentication** (Management API only): JWT Bearer token in `Authorization` header

## Part 1: Nix Cache Protocol (Public, Unauthenticated)

These endpoints implement the standard Nix binary cache protocol, used by Nix daemons on NixOS VMs to query and download packages.

### 1.1 GET /\<cache\>/nix-cache-info - Cache Metadata

**Purpose**: Advertise cache capabilities and public key (queried by Nix daemon on first contact)

**Request**:
```http
GET /nixos/nix-cache-info HTTP/1.1
Host: attic.nix-cache.svc.cluster.local:8080
```

**Response (Success)**:
```http
HTTP/1.1 200 OK
Content-Type: text/plain

StoreDir: /nix/store
WantMassQuery: 1
Priority: 40
PublicKey: nixos:ABC123DEF456...
```

**Response Fields**:
- `StoreDir`: Nix store path (always /nix/store)
- `WantMassQuery`: Cache supports bulk narinfo queries (1 = yes)
- `Priority`: Cache priority (40 = higher priority than cache.nixos.org at 50)
- `PublicKey`: Ed25519 public key for signature verification (format: `<cache-name>:<base64-key>`)

**Contract Guarantees**:
- Response is cacheable by Nix daemon (HTTP caching headers)
- Public key matches cache signing key (used to verify narinfo signatures)

### 1.2 GET /\<cache\>/\<storehash\>.narinfo - Package Metadata

**Purpose**: Query if package exists in cache and get download URL (primary lookup endpoint for Nix daemon)

**Request**:
```http
GET /nixos/abc123def456...xyz789.narinfo HTTP/1.1
Host: attic.nix-cache.svc.cluster.local:8080
```

**Parameters**:
- `cache`: Cache namespace (e.g., "nixos")
- `storehash`: Nix store path hash (e.g., "abc123def456...xyz789")

**Response (Success - Cache Hit)**:
```http
HTTP/1.1 200 OK
Content-Type: text/plain

StorePath: /nix/store/abc123def456...xyz789-package-name-1.0
URL: nar/def456abc123...uvw321.nar.zst
Compression: zstd
FileHash: sha256:def456abc123...uvw321
FileSize: 1048576
NarHash: sha256:abc123def456...xyz789
NarSize: 2097152
References: ghi789jkl012...mno345 pqr678stu901...vwx234
Deriver: abc123def456...xyz789-package-name-1.0.drv
Sig: nixos:ABC123...signature...XYZ789
```

**Response Fields**:
- `StorePath`: Full Nix store path
- `URL`: Relative URL to NAR file (base: cache URL)
- `Compression`: Compression format (zstd)
- `FileHash`: Hash of compressed NAR file
- `FileSize`: Size of compressed NAR (bytes)
- `NarHash`: Hash of uncompressed NAR (verifies integrity)
- `NarSize`: Size of uncompressed NAR (bytes)
- `References`: Space-separated list of runtime dependency hashes
- `Deriver`: Store path hash of derivation that built this package
- `Sig`: Ed25519 signature of narinfo (format: `<cache-name>:<base64-sig>`)

**Response (Cache Miss)**:
```http
HTTP/1.1 404 Not Found
Content-Type: text/plain

Package not found in cache
```

**Contract Guarantees**:
- Signature verifies with cache public key (from nix-cache-info)
- NarHash matches actual NAR content (Nix daemon verifies after download)
- URL is relative to cache base URL (Nix prepends base URL)
- Response is cacheable (HTTP caching headers)

### 1.3 GET /\<cache\>/nar/\<narhash\>.nar.zst - Download Package

**Purpose**: Download compressed NAR file for package installation (called after successful narinfo lookup)

**Request**:
```http
GET /nixos/nar/def456abc123...uvw321.nar.zst HTTP/1.1
Host: attic.nix-cache.svc.cluster.local:8080
```

**Parameters**:
- `cache`: Cache namespace (e.g., "nixos")
- `narhash`: Content hash of NAR file (from narinfo URL field)

**Response (Success)**:
```http
HTTP/1.1 200 OK
Content-Type: application/zstd
Content-Length: 1048576
ETag: "def456abc123...uvw321"

<binary zstd-compressed NAR data>
```

**Response (Not Found)**:
```http
HTTP/1.1 404 Not Found
Content-Type: text/plain

NAR file not found
```

**Contract Guarantees**:
- Content matches FileHash from narinfo (Nix daemon verifies)
- Decompressed content matches NarHash from narinfo (Nix daemon verifies)
- Streaming response (no full-file buffering in Attic)
- Supports HTTP/1.1 Keep-Alive (multiple NARs downloaded over single connection)

**Data Flow**:
1. Attic queries SQLite DB for NAR chunk hashes
2. Attic fetches chunks from MinIO S3 bucket (GetObject API)
3. Attic reconstructs NAR from chunks (in-memory or streaming)
4. Attic applies zstd compression (level 8) during streaming
5. Attic streams compressed NAR to client

## Part 2: Attic Management API (Authenticated)

These endpoints are Attic-specific extensions for cache creation, package pushing, and configuration. **Authentication required**: JWT Bearer token with appropriate scopes.

### 2.1 POST /_api/v1/login - Authenticate (Not Used in MVP)

**Purpose**: Exchange username/password for JWT token (not used, tokens generated via `atticd-atticadm`)

**Request**:
```http
POST /_api/v1/login HTTP/1.1
Host: attic.nix-cache.svc.cluster.local:8080
Content-Type: application/json

{
  "username": "admin",
  "password": "secret"
}
```

**Response (Success)**:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**MVP Alternative**: Tokens generated via `atticd-atticadm make-token` command in Attic pod.

### 2.2 POST /_api/v1/caches - Create Cache

**Purpose**: Create new cache namespace with unique signing key pair

**Request**:
```http
POST /_api/v1/caches HTTP/1.1
Host: attic.nix-cache.svc.cluster.local:8080
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{
  "name": "nixos"
}
```

**Response (Success)**:
```http
HTTP/1.1 201 Created
Content-Type: application/json

{
  "name": "nixos",
  "public_key": "nixos:ABC123DEF456...",
  "created_at": "2025-10-11T12:00:00Z"
}
```

**Response (Cache Already Exists)**:
```http
HTTP/1.1 409 Conflict
Content-Type: application/json

{
  "error": "Cache 'nixos' already exists"
}
```

**Response (Unauthorized)**:
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "error": "Invalid or missing authentication token"
}
```

**Contract Guarantees**:
- Signing key pair generated securely (Ed25519, 256-bit entropy)
- Private key stored in Attic SQLite DB (never exposed via API)
- Public key returned in response (safe to distribute)
- Cache name is unique per Attic instance

### 2.3 GET /_api/v1/caches/\<cache\> - Get Cache Info

**Purpose**: Retrieve cache metadata and public key

**Request**:
```http
GET /_api/v1/caches/nixos HTTP/1.1
Host: attic.nix-cache.svc.cluster.local:8080
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Response (Success)**:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "name": "nixos",
  "public_key": "nixos:ABC123DEF456...",
  "created_at": "2025-10-11T12:00:00Z",
  "packages_count": 150,
  "total_size": 21474836480
}
```

**Response (Cache Not Found)**:
```http
HTTP/1.1 404 Not Found
Content-Type: application/json

{
  "error": "Cache 'nixos' not found"
}
```

**Contract Guarantees**:
- `packages_count`: Number of unique store paths in cache
- `total_size`: Total storage used after deduplication (bytes)

### 2.4 PUT /_api/v1/caches/\<cache\>/objects - Push Package

**Purpose**: Upload Nix package NAR to cache (called by Attic CLI during `attic push`)

**Request**:
```http
PUT /_api/v1/caches/nixos/objects HTTP/1.1
Host: attic.nix-cache.svc.cluster.local:8080
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/octet-stream
Content-Length: 2097152
X-Attic-NAR-Hash: abc123def456...xyz789
X-Attic-NAR-Size: 2097152
X-Attic-References: ghi789jkl012...mno345 pqr678stu901...vwx234

<binary NAR data>
```

**Response (Success)**:
```http
HTTP/1.1 201 Created
Content-Type: application/json

{
  "nar_hash": "abc123def456...xyz789",
  "nar_size": 2097152,
  "file_hash": "def456abc123...uvw321",
  "file_size": 1048576,
  "signature": "nixos:ABC123...signature...XYZ789"
}
```

**Response (Cache Full - MinIO Disk Full)**:
```http
HTTP/1.1 507 Insufficient Storage
Content-Type: application/json

{
  "error": "S3 backend storage full"
}
```

**Contract Guarantees**:
- NAR is chunked using FastCDC (16KB-256KB chunks)
- Chunks uploaded to MinIO S3 bucket (deduplication via content-addressing)
- Narinfo indexed in Attic SQLite DB (storeHash → narHash, references, signature)
- Signature generated using cache private key (Ed25519)

**Data Flow**:
1. Attic receives NAR stream from client
2. Attic chunks NAR using FastCDC algorithm
3. Attic checks MinIO for existing chunks (HeadObject API)
4. Attic uploads missing chunks to MinIO (PutObject API)
5. Attic stores narinfo in SQLite DB
6. Attic signs narinfo with cache private key
7. Attic responds with narinfo metadata and signature

## Authentication Details

**JWT Bearer Token** format:
```json
{
  "sub": "admin",
  "exp": 1760000000,
  "iat": 1728000000,
  "scopes": ["pull:*", "push:*", "create-cache:*", "configure-cache:*", "destroy-cache:*"]
}
```

**Scopes**:
- `pull:<cache>`: Download packages from cache (or `pull:*` for all caches)
- `push:<cache>`: Upload packages to cache (or `push:*` for all caches)
- `create-cache:<name>`: Create new cache (or `create-cache:*` for any name)
- `configure-cache:<cache>`: Modify cache settings
- `destroy-cache:<cache>`: Delete cache

**Token Generation** (MVP):
```bash
kubectl exec -n nix-cache deploy/attic -- \
  atticd-atticadm make-token \
    --sub "admin" \
    --validity "10y" \
    --pull "*" \
    --push "*" \
    --create-cache "*"
```

## Error Handling

**Common Error Responses**:
- `400 Bad Request`: Malformed request (invalid JSON, missing headers)
- `401 Unauthorized`: Invalid or missing JWT token
- `403 Forbidden`: Valid token but insufficient permissions (scope mismatch)
- `404 Not Found`: Cache or package does not exist
- `409 Conflict`: Cache already exists (on cache creation)
- `500 Internal Server Error`: Attic server error (SQLite corruption, panic)
- `502 Bad Gateway`: MinIO S3 backend unreachable
- `507 Insufficient Storage`: MinIO disk full

**Retry Strategy** (Attic CLI):
- Retryable errors: 500, 502, 503 (exponential backoff, max 3 retries)
- Non-retryable errors: 400, 401, 403, 404, 409 (fail immediately)

## Performance Characteristics

- **Narinfo lookup latency**: 1-5ms (SQLite DB query)
- **NAR download throughput**: 100-500 MB/s (in-cluster network, MinIO backend)
- **Package push throughput**: 50-200 MB/s (chunking + deduplication overhead)
- **Concurrent operations**: Supports 10+ simultaneous narinfo queries, 3-5 concurrent NAR downloads
- **Chunking overhead**: ~10-20% CPU usage during push (FastCDC algorithm)
- **Deduplication savings**: 30% storage reduction (typical for multiple NixOS configurations)

## Security Model

- **Public endpoints** (nix-cache-info, narinfo, NAR download): No authentication required (public cache model)
- **Management endpoints** (create cache, push package): JWT bearer token required
- **Token storage**: Not stored in Kubernetes (sensitive, generated on-demand for cache init)
- **Signature verification**: Nix daemon verifies narinfo signature using public key (prevents tampering)
- **HTTPS in production**: TLS termination at ingress (not required for in-cluster MVP)

## Testing Strategy

1. **Cache creation test**: POST /_api/v1/caches, verify 201 Created and public key returned
2. **Cache info test**: GET /_api/v1/caches/nixos, verify metadata matches
3. **Package push test**: PUT package NAR, verify 201 Created and signature returned
4. **Narinfo query test**: GET /nixos/<storehash>.narinfo, verify narinfo fields and signature
5. **NAR download test**: GET /nixos/nar/<narhash>.nar.zst, verify content hash matches
6. **Cache miss test**: Query non-existent package, verify 404 Not Found
7. **Authentication test**: Query management endpoint without token, verify 401 Unauthorized
8. **Deduplication test**: Push identical package twice, verify chunks uploaded once (check MinIO objects)
