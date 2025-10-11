# Feature Specification: Attic + MinIO Nix Binary Cache

**Feature Branch**: `003-implement-attic-minio`
**Created**: 2025-10-11
**Status**: Implemented ✅
**Completed**: 2025-10-11
**Input**: User description: "Implement Attic + MinIO Nix binary cache for KubeVirt VMs"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy MinIO Object Storage (Priority: P1)

As a platform engineer, I want to deploy MinIO as an S3-compatible object storage service in my Kind cluster so that I have a foundation for storing Nix binary cache artifacts locally with minimal latency.

**Why this priority**: MinIO is the storage backend for Attic and must be operational before any cache operations can occur. Without MinIO, Attic cannot store or retrieve Nix packages.

**Independent Test**: Can be fully tested by deploying the MinIO service, accessing its web console, creating a test bucket, and uploading/downloading a test file to verify S3-compatible operations work.

**Acceptance Scenarios**:

1. **Given** I have a Kind cluster with ArgoCD installed, **When** I deploy the MinIO CDK8s chart, **Then** the MinIO pod starts successfully and the API is accessible on port 9000
2. **Given** MinIO is deployed, **When** I access the MinIO console on port 9001, **Then** I can log in with admin credentials and see the management interface
3. **Given** MinIO is running, **When** I create a bucket named "attic-cache" via the MinIO API, **Then** the bucket is created and listed in the MinIO console
4. **Given** a MinIO bucket exists, **When** I upload a test object via S3 API, **Then** the object is stored and can be retrieved successfully

---

### User Story 2 - Deploy Attic Binary Cache Server (Priority: P2)

As a platform engineer, I want to deploy Attic cache server connected to MinIO so that I have a Nix binary cache service that can store and serve Nix packages with deduplication and multi-tenant capabilities.

**Why this priority**: Attic is the cache server that NixOS VMs will interact with. It must be deployed and configured before VMs can benefit from cached packages.

**Independent Test**: Can be fully tested by deploying Attic, initializing it with an admin token, creating a cache namespace, and verifying Attic can communicate with MinIO for storage operations.

**Acceptance Scenarios**:

1. **Given** MinIO is deployed and the attic-cache bucket exists, **When** I deploy the Attic CDK8s chart, **Then** the Attic pod starts and connects to MinIO successfully
2. **Given** Attic is running, **When** I generate an admin token via atticd-atticadm, **Then** I receive a valid JWT token with full permissions
3. **Given** I have an admin token, **When** I create a cache named "nixos" via Attic API, **Then** the cache is created and assigned a unique signing key
4. **Given** a cache exists, **When** I query the cache info endpoint, **Then** Attic returns the cache public key and configuration details

---

### User Story 3 - Populate Cache from Hetzner Host (Priority: P3)

As a platform engineer, I want to push Nix packages from my Hetzner host's /nix/store to the Attic cache so that subsequent VM builds can retrieve packages locally instead of downloading from cache.nixos.org.

**Why this priority**: Populating the cache with commonly used packages enables faster VM builds. This is the operational step that unlocks the performance benefits of the local cache.

**Independent Test**: Can be fully tested by pushing a small Nix package (e.g., hello) from the Hetzner host to Attic, then verifying the package appears in the cache and can be retrieved via HTTP.

**Acceptance Scenarios**:

1. **Given** Attic is deployed and I have access to the cache, **When** I run `attic push nixos /nix/store/xxx-hello` from the Hetzner host, **Then** the package NAR is uploaded to MinIO via Attic
2. **Given** a package has been pushed to Attic, **When** I query the cache for that package's store path, **Then** Attic responds with a valid NAR URL
3. **Given** my Hetzner host has a system closure, **When** I push the entire closure via `attic push nixos /run/current-system`, **Then** all transitive dependencies are uploaded to the cache
4. **Given** packages are cached, **When** I check MinIO bucket contents, **Then** I see chunked NAR data and metadata stored efficiently

---

### User Story 4 - Configure NixOS VMs to Use Attic Cache (Priority: P4)

As a platform engineer, I want to configure my NixOS VMs to use the in-cluster Attic cache as their primary substituter so that VM builds download packages from the local cache instead of the internet, reducing build times significantly.

**Why this priority**: This is the final integration step that delivers the user-facing performance improvement. VMs configured with Attic as a substituter will experience 8x faster rebuild times.

**Independent Test**: Can be fully tested by creating a NixOS VM with Attic configured as a substituter, performing a nixos-rebuild, and measuring download times compared to a VM using only cache.nixos.org.

**Acceptance Scenarios**:

1. **Given** Attic cache is populated with packages, **When** I configure a NixOS VM with `substituters = ["http://attic.nix-cache.svc.cluster.local:8080/nixos"]`, **Then** the VM's Nix daemon recognizes Attic as a valid substituter
2. **Given** a VM is configured to use Attic, **When** I rebuild the VM configuration, **Then** Nix queries Attic for packages before falling back to cache.nixos.org
3. **Given** a package exists in the Attic cache, **When** the VM requests that package during a build, **Then** the package is downloaded from Attic at in-cluster network speeds (100-500 MB/s)
4. **Given** a package is not in the Attic cache, **When** the VM requests that package, **Then** Nix falls back to cache.nixos.org and downloads from the internet without errors
5. **Given** Attic cache is configured as the primary substituter, **When** I rebuild a VM that previously took 20 minutes, **Then** the rebuild completes in under 3 minutes (8x faster)

---

### Edge Cases

- What happens when MinIO runs out of disk space (PVC full)?
- How does the system handle Attic pod restarts during an active package upload?
- What occurs when a NixOS VM attempts to use Attic before it's fully initialized?
- How is cache consistency maintained when multiple VMs push the same package simultaneously?
- What happens to cached packages when the MinIO PVC is accidentally deleted?
- How does Attic handle corrupted NAR data in MinIO storage?
- What occurs when Attic cache signing key is lost or rotated?
- How are authorization failures handled when VMs use an invalid or expired cache token?
- What happens when Attic service is temporarily unavailable during VM builds?
- How does the system handle MinIO credential rotation without disrupting active cache operations?

## Requirements *(mandatory)*

### Functional Requirements

#### MinIO Deployment

- **FR-001**: System MUST deploy MinIO to the nix-cache namespace using CDK8s-generated manifests
- **FR-002**: System MUST create a PersistentVolumeClaim of 100Gi for MinIO data storage
- **FR-003**: System MUST configure MinIO with root user credentials stored in a Kubernetes Secret
- **FR-004**: System MUST expose MinIO API on port 9000 and console on port 9001 via ClusterIP Service
- **FR-005**: System MUST configure MinIO resource limits (512Mi-2Gi memory, 250m-1000m CPU)
- **FR-006**: System MUST create an "attic-cache" bucket in MinIO for Attic storage backend

#### Attic Deployment

- **FR-007**: System MUST deploy Attic server to the nix-cache namespace using CDK8s-generated manifests
- **FR-008**: System MUST configure Attic to use MinIO as S3 storage backend with endpoint "http://minio:9000"
- **FR-009**: System MUST configure Attic with SQLite database for metadata storage
- **FR-010**: System MUST configure Attic chunking parameters (nar-size-threshold: 64KB, min-size: 16KB, avg-size: 64KB, max-size: 256KB)
- **FR-011**: System MUST configure Attic compression with zstd level 8
- **FR-012**: System MUST expose Attic API on port 8080 via ClusterIP Service
- **FR-013**: System MUST configure Attic resource limits (256Mi-1Gi memory, 100m-500m CPU)
- **FR-014**: System MUST provide mechanism to generate Attic admin token with full cache permissions

#### Cache Management

- **FR-015**: System MUST support creating named caches (e.g., "nixos") via Attic API
- **FR-016**: System MUST generate unique signing key pairs for each cache
- **FR-017**: System MUST expose cache public keys for NixOS VM configuration
- **FR-018**: System MUST support pushing Nix store paths to Attic from external hosts (Hetzner)
- **FR-019**: System MUST support pushing entire system closures with transitive dependencies
- **FR-020**: System MUST deduplicate identical NARs across multiple caches (global deduplication)

#### NixOS VM Integration

- **FR-021**: System MUST provide NixOS configuration snippet for VMs to use Attic as substituter
- **FR-022**: NixOS VMs MUST be able to query Attic for package availability via HTTP
- **FR-023**: NixOS VMs MUST download packages from Attic when available in cache
- **FR-024**: NixOS VMs MUST fall back to cache.nixos.org when packages are not in Attic cache
- **FR-025**: System MUST provide cache public key for NixOS trusted-public-keys configuration
- **FR-026**: NixOS VMs MUST access Attic via cluster-internal DNS (attic.nix-cache.svc.cluster.local:8080)

#### GitOps Integration

- **FR-027**: System MUST synthesize MinIO and Attic manifests to dist/ directory following package-based architecture
- **FR-028**: System MUST create ArgoCD Application manifests for MinIO and Attic packages
- **FR-029**: System MUST use cnoe:// URL syntax for local development deployment via idpbuilder
- **FR-030**: System MUST configure sync waves ensuring MinIO deploys before Attic (MinIO: -100, Attic: -90)
- **FR-031**: System MUST register MinIO and Attic charts in IdpBuilderChartFactory
- **FR-032**: System MUST support automated sync policy for cache infrastructure (prune, selfHeal)

### Key Entities

- **MinIO**: S3-compatible object storage service storing Nix package data (NARs, metadata) in a 100Gi PVC with API (port 9000) and console (port 9001) interfaces
- **Attic Server**: Rust-based binary cache server managing cache namespaces, deduplication, signing, and serving Nix packages via HTTP API (port 8080)
- **Attic Cache**: Named cache namespace (e.g., "nixos") with unique signing key, storing references to NAR objects in MinIO
- **NAR (Nix ARchive)**: Normalized archive format for Nix packages, chunked and compressed by Attic, stored in MinIO
- **Cache Signing Key**: Public/private key pair for verifying cache authenticity, generated per cache, public key distributed to VMs
- **Admin Token**: JWT bearer token with full Attic permissions (create, push, pull, configure, destroy caches)
- **PersistentVolumeClaim**: Kubernetes storage resource (100Gi) backing MinIO data persistence
- **nix-cache Namespace**: Kubernetes namespace containing MinIO and Attic infrastructure

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: MinIO deploys successfully within 2 minutes of ArgoCD sync and passes readiness checks
- **SC-002**: Attic server connects to MinIO and initializes within 1 minute of deployment
- **SC-003**: Platform engineer can push a 1GB system closure to Attic in under 5 minutes from Hetzner host
- **SC-004**: NixOS VM rebuild time reduces from 20-25 minutes to under 3 minutes when using Attic cache (8x improvement)
- **SC-005**: Package download speed from Attic cache reaches 100-500 MB/s for in-cluster VMs (10x faster than cache.nixos.org)
- **SC-006**: Cache hit rate exceeds 80% for subsequent VM rebuilds after initial cache population
- **SC-007**: Attic cache storage efficiency achieves 30% reduction in disk usage compared to duplicate /nix/store copies (via global deduplication)
- **SC-008**: Platform engineer can create a new cache namespace in under 30 seconds via Attic API
- **SC-009**: System handles concurrent package pushes from multiple sources without data corruption
- **SC-010**: Cache availability remains above 99% during normal operations (excluding cluster restarts)
- **SC-011**: NixOS VM builds complete successfully using Attic cache on first attempt without manual intervention

### Assumptions

1. **Kind cluster resources**: Assumes Kind cluster has sufficient disk space (minimum 120GB available) for MinIO PVC and local-path-provisioner
2. **Network connectivity**: Assumes Hetzner host can reach Kind cluster's exposed ports (e.g., via port-forward or Tailscale) for pushing packages to Attic
3. **NixOS build environment**: Assumes Attic CLI (`attic`) is installed on Hetzner host for pushing packages
4. **Storage class**: Assumes Kind cluster has a default StorageClass supporting ReadWriteOnce PVCs (typically local-path-provisioner)
5. **Cluster stability**: Assumes Kind cluster remains stable during cache population (no node restarts during large uploads)
6. **Existing KubeVirt deployment**: Assumes KubeVirt and NixOS VMs are already deployed per spec 002-i-want-to
7. **CDI not required**: Assumes Containerized Data Importer (CDI) is already deployed for KubeVirt image management, but Attic operates independently
8. **Namespace creation**: Assumes nix-cache namespace will be created as part of deployment workflow
9. **Secrets management**: Assumes MinIO credentials can be stored in Kubernetes Secrets (development) or External Secrets Operator (production)
10. **Cache retention**: Assumes 100Gi storage is sufficient for caching system closures for 5-10 NixOS configurations; no automatic garbage collection required initially
11. **Single-tenant cache**: Assumes initial deployment uses a single "nixos" cache namespace; multi-tenant capabilities are available but not required for MVP
12. **No external ingress**: Assumes Attic is accessed only from within the cluster; external access (e.g., from CI/CD) is not required for initial deployment
