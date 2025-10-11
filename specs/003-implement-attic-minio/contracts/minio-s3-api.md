# Contract: MinIO S3 API Surface

**Feature**: 003-implement-attic-minio
**Component**: MinIO Object Storage
**Protocol**: AWS S3 API (v4 signature)
**Date**: 2025-10-11

## Overview

This contract defines the S3 API surface used by Attic to interact with MinIO for storing and retrieving Nix package data (chunked NARs and metadata). MinIO implements a subset of the AWS S3 API, providing object storage semantics (PutObject, GetObject, etc.) over HTTP.

## Base Endpoint

```
http://minio.nix-cache.svc.cluster.local:9000
```

**Authentication**: AWS Signature Version 4 (access key + secret key from `minio-credentials` Secret)

## API Operations

### 1. PutObject - Store NAR Chunk

**Purpose**: Upload a NAR chunk to MinIO storage (called by Attic during package push)

**Request**:
```http
PUT /attic-cache/nar/<chunk-hash>.nar.zst HTTP/1.1
Host: minio.nix-cache.svc.cluster.local:9000
Authorization: AWS4-HMAC-SHA256 Credential=...
Content-Type: application/octet-stream
Content-Length: 65536
x-amz-content-sha256: <sha256-of-body>

<binary NAR chunk data>
```

**Parameters**:
- `Bucket`: attic-cache (fixed bucket name)
- `Key`: nar/<chunk-hash>.nar.zst (content-addressed key)
- `Body`: Binary NAR chunk data (compressed with zstd)

**Response (Success)**:
```http
HTTP/1.1 200 OK
ETag: "abc123def456..."
x-amz-request-id: abc123...
x-amz-id-2: def456...

(empty body)
```

**Response (Error - Bucket Not Found)**:
```http
HTTP/1.1 404 Not Found
Content-Type: application/xml

<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>NoSuchBucket</Code>
  <Message>The specified bucket does not exist.</Message>
  <BucketName>attic-cache</BucketName>
  <RequestId>abc123...</RequestId>
</Error>
```

**Response (Error - Disk Full)**:
```http
HTTP/1.1 507 Insufficient Storage
Content-Type: application/xml

<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>XMinioStorageFull</Code>
  <Message>Storage backend has reached its minimum free disk threshold.</Message>
</Error>
```

**Contract Guarantees**:
- Object is stored durably (PVC backed by local disk)
- ETag returned matches object content hash
- Idempotent: Repeated PUTs with same key/content succeed (overwrite)
- Atomic: Object either fully written or not visible

### 2. GetObject - Retrieve NAR Chunk

**Purpose**: Download a NAR chunk from MinIO storage (called by Attic during package download to VM)

**Request**:
```http
GET /attic-cache/nar/<chunk-hash>.nar.zst HTTP/1.1
Host: minio.nix-cache.svc.cluster.local:9000
Authorization: AWS4-HMAC-SHA256 Credential=...
```

**Parameters**:
- `Bucket`: attic-cache
- `Key`: nar/<chunk-hash>.nar.zst

**Response (Success)**:
```http
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 65536
ETag: "abc123def456..."
Last-Modified: Fri, 11 Oct 2025 12:00:00 GMT
x-amz-request-id: abc123...

<binary NAR chunk data>
```

**Response (Error - Object Not Found)**:
```http
HTTP/1.1 404 Not Found
Content-Type: application/xml

<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>NoSuchKey</Code>
  <Message>The specified key does not exist.</Message>
  <Key>nar/<chunk-hash>.nar.zst</Key>
  <RequestId>abc123...</RequestId>
</Error>
```

**Contract Guarantees**:
- Object content matches ETag (integrity)
- Read-after-write consistency (object visible immediately after PutObject)
- Partial content supported via Range header (not used by Attic MVP)

### 3. HeadObject - Check Object Existence

**Purpose**: Verify if NAR chunk exists without downloading content (used for deduplication checks)

**Request**:
```http
HEAD /attic-cache/nar/<chunk-hash>.nar.zst HTTP/1.1
Host: minio.nix-cache.svc.cluster.local:9000
Authorization: AWS4-HMAC-SHA256 Credential=...
```

**Parameters**:
- `Bucket`: attic-cache
- `Key`: nar/<chunk-hash>.nar.zst

**Response (Success - Object Exists)**:
```http
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Length: 65536
ETag: "abc123def456..."
Last-Modified: Fri, 11 Oct 2025 12:00:00 GMT

(no body)
```

**Response (Object Not Found)**:
```http
HTTP/1.1 404 Not Found

(no body)
```

**Contract Guarantees**:
- Response headers identical to GetObject (except no body)
- Fast operation (metadata-only, no disk read)
- Used by Attic to skip uploading duplicate chunks

### 4. ListObjectsV2 - List Bucket Contents

**Purpose**: Enumerate objects in bucket (used for debugging, monitoring, garbage collection planning)

**Request**:
```http
GET /attic-cache?list-type=2&prefix=nar/&max-keys=1000 HTTP/1.1
Host: minio.nix-cache.svc.cluster.local:9000
Authorization: AWS4-HMAC-SHA256 Credential=...
```

**Parameters**:
- `Bucket`: attic-cache (path parameter)
- `list-type`: 2 (ListObjectsV2 API version)
- `prefix`: nar/ (filter objects by prefix)
- `max-keys`: 1000 (limit results per page)
- `continuation-token`: (pagination token from previous response)

**Response (Success)**:
```http
HTTP/1.1 200 OK
Content-Type: application/xml

<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <Name>attic-cache</Name>
  <Prefix>nar/</Prefix>
  <KeyCount>1000</KeyCount>
  <MaxKeys>1000</MaxKeys>
  <IsTruncated>true</IsTruncated>
  <NextContinuationToken>abc123...</NextContinuationToken>
  <Contents>
    <Key>nar/abc123...def456.nar.zst</Key>
    <LastModified>2025-10-11T12:00:00.000Z</LastModified>
    <ETag>"abc123..."</ETag>
    <Size>65536</Size>
    <StorageClass>STANDARD</StorageClass>
  </Contents>
  <Contents>
    <!-- more objects... -->
  </Contents>
</ListBucketResult>
```

**Contract Guarantees**:
- Paginated results (use NextContinuationToken for subsequent requests)
- Eventually consistent (newly uploaded objects may not appear immediately)
- Sorted lexicographically by Key

### 5. DeleteObject - Remove NAR Chunk (Future Feature)

**Purpose**: Delete obsolete NAR chunks during garbage collection (not implemented in MVP)

**Request**:
```http
DELETE /attic-cache/nar/<chunk-hash>.nar.zst HTTP/1.1
Host: minio.nix-cache.svc.cluster.local:9000
Authorization: AWS4-HMAC-SHA256 Credential=...
```

**Response (Success)**:
```http
HTTP/1.1 204 No Content
x-amz-request-id: abc123...
```

**Contract Guarantees**:
- Idempotent: Deleting non-existent object returns 204 (success)
- Atomic: Object either fully deleted or still exists

## Authentication

**AWS Signature Version 4** (SigV4) is used for all requests:

1. **Credentials**: Access Key (admin) + Secret Key (from minio-credentials Secret)
2. **Signing Process**:
   - Canonical request: Method + URI + Query + Headers + Payload hash
   - String to sign: Algorithm + Date + Scope + Canonical request hash
   - Signature: HMAC-SHA256 of string to sign with derived signing key
3. **Authorization Header**: `AWS4-HMAC-SHA256 Credential=admin/20251011/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=abc123...`

**SDK Handling**: Attic uses `aws-sdk-rust` crate, which automatically generates SigV4 signatures given credentials.

## Error Handling

**Common Error Responses**:
- `400 Bad Request`: Malformed request (invalid signature, missing headers)
- `403 Forbidden`: Invalid credentials or insufficient permissions
- `404 Not Found`: Bucket or object does not exist
- `500 Internal Server Error`: MinIO server error (disk failure, OOM)
- `503 Service Unavailable`: MinIO temporarily unavailable (pod restart)
- `507 Insufficient Storage`: Disk full (PVC capacity exhausted)

**Retry Strategy** (Attic client):
- Retryable errors: 500, 503, 507 (exponential backoff, max 3 retries)
- Non-retryable errors: 400, 403, 404 (fail immediately)

## Performance Characteristics

- **Throughput**: 100-500 MB/s for in-cluster uploads/downloads (network-bound)
- **Latency**: 1-10ms for HeadObject (metadata-only), 5-50ms for GetObject (small chunks)
- **Concurrent operations**: Supports 10+ simultaneous PutObject/GetObject requests
- **Storage capacity**: 100Gi PVC (approximately 5-10 system closures with deduplication)

## Constraints

- **Single-node MinIO**: No replication or high availability (acceptable for Kind cluster)
- **PVC-backed storage**: Durability depends on Kind node disk (local-path-provisioner)
- **No versioning**: Objects are immutable (no versioning enabled on bucket)
- **No lifecycle policies**: No automatic expiration or archiving (manual garbage collection)

## Testing Strategy

1. **Bucket creation verification**: `mc mb minio/attic-cache` (via MinIO CLI)
2. **Object upload test**: Upload 10MB test file, verify ETag and size
3. **Object download test**: Download same file, verify content hash matches
4. **Deduplication test**: Upload identical file twice, verify single object in bucket
5. **Disk full simulation**: Fill PVC to 99%, verify 507 Insufficient Storage error
6. **Authentication test**: Use invalid credentials, verify 403 Forbidden response
