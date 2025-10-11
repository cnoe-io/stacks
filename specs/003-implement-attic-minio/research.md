# Research: Attic + MinIO Nix Binary Cache

**Feature**: 003-implement-attic-minio
**Phase**: 0 (Research)
**Date**: 2025-10-11

## Executive Summary

This document consolidates research findings for implementing an in-cluster Nix binary cache using MinIO (S3-compatible storage) and Attic (Nix cache server). The solution addresses the problem of slow NixOS VM rebuild times (20-25 minutes) by caching Nix packages locally, achieving 8x performance improvement (under 3 minutes). Research covers MinIO/Attic architecture, CDK8s chart patterns, sync wave ordering, and operational workflows.

## Research Tasks

### 1. MinIO Architecture and S3 API Surface

**Decision**: Use MinIO as S3-compatible object storage backend for Attic

**Rationale**:
- **Native S3 compatibility**: Attic requires S3-compatible storage (AWS S3, Cloudflare R2, MinIO)
- **Self-hosted**: Runs in-cluster with no external dependencies or costs
- **Performance**: In-cluster network latency (1-10ms vs 50-200ms for cloud S3)
- **Maturity**: Production-ready, CNCF project, widely deployed
- **Resource efficiency**: Lightweight (512Mi-2Gi RAM), suitable for Kind cluster

**S3 API Surface Used by Attic**:
- `PutObject`: Store chunked NAR files and metadata
- `GetObject`: Retrieve NAR files for package downloads
- `HeadObject`: Check object existence and metadata
- `ListObjectsV2`: List bucket contents (for debugging/monitoring)
- `DeleteObject`: Remove old/unused NARs (garbage collection, not MVP)

**Alternatives Considered**:
- **AWS S3**: Requires internet dependency, egress costs ($0.09/GB), increased latency
- **Cloudflare R2**: Free egress but internet dependency, not suitable for air-gapped dev
- **Hostpath storage**: No deduplication, no API abstraction, limited to single node

### 2. Attic Architecture and Nix Cache Protocol

**Decision**: Use Attic as the Nix binary cache server with content-addressed storage and global deduplication

**Rationale**:
- **Modern design**: Written in Rust, designed for Kubernetes, better than legacy nix-serve
- **Global deduplication**: Single NAR stored once, referenced by multiple caches (30% storage savings)
- **Content-addressed chunking**: Efficient NAR splitting (16KB-256KB chunks) for network efficiency
- **Multi-tenancy**: Supports multiple cache namespaces (e.g., per-environment caching if needed)
- **Managed signing**: Automatic signing key generation per cache, no manual key management
- **Compression**: Built-in zstd compression (level 8) reduces storage and network usage

**Nix Cache Protocol (Narinfo)**:
1. Nix daemon queries: `GET /nixos/<storehash>.narinfo`
2. Attic responds with metadata: NAR URL, file size, hash, signature
3. Nix daemon downloads: `GET /nixos/nar/<nar-hash>.nar.zst`
4. Attic serves NAR from MinIO S3 bucket
5. Nix verifies signature using cache public key

**Alternatives Considered**:
- **nix-serve**: Simple but lacks compression, deduplication, multi-tenancy
- **Harmonia**: Good performance but serves host /nix/store directly (security concern)
- **Cachix**: Managed service but costs $20-50/month, requires internet, vendor lock-in

### 3. CDK8s Chart Patterns for Storage and Stateful Services

**Decision**: Use low-level `imports/k8s` API for precise control over Deployment, PVC, ConfigMap resources

**Rationale**:
- **Exact YAML control**: MinIO/Attic require specific volume mounts, environment variables, security contexts
- **Constitution compliance**: Principle I mandates TypeScript CDK8s over YAML templating
- **Reusable patterns**: Leverage existing patterns from KubeVirt deployment (spec 002)
- **Type safety**: TypeScript compilation catches configuration errors before synthesis

**CDK8s Chart Structure** (based on existing codebase patterns):
```typescript
import { Chart, ChartProps } from 'cdk8s';
import { Construct } from 'constructs';
import * as k8s from '../../imports/k8s';
import { addSyncWaveAnnotation } from '../../lib/argocd-sync-builders';

export interface MinioChartProps extends ChartProps {
  namespace: string;
  storageSize: string; // e.g., "100Gi"
  resources?: {
    requests?: { memory: string; cpu: string; };
    limits?: { memory: string; cpu: string; };
  };
}

export class MinioChart extends Chart {
  constructor(scope: Construct, id: string, props: MinioChartProps) {
    super(scope, id, props);

    // Namespace
    const ns = new k8s.KubeNamespace(this, 'namespace', {
      metadata: { name: props.namespace }
    });
    addSyncWaveAnnotation(ns, '-110');

    // PVC for data storage
    const pvc = new k8s.KubePersistentVolumeClaim(this, 'pvc', {
      metadata: { name: 'minio-storage', namespace: props.namespace },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: { requests: { storage: props.storageSize } }
      }
    });
    addSyncWaveAnnotation(pvc, '-100');

    // Secret for credentials
    const secret = new k8s.KubeSecret(this, 'credentials', {
      metadata: { name: 'minio-credentials', namespace: props.namespace },
      type: 'Opaque',
      stringData: {
        'access-key': 'admin',
        'secret-key': generatePassword() // Helper function
      }
    });
    addSyncWaveAnnotation(secret, '-100');

    // Deployment
    const deployment = new k8s.KubeDeployment(this, 'deployment', {
      metadata: { name: 'minio', namespace: props.namespace },
      spec: {
        replicas: 1,
        selector: { matchLabels: { app: 'minio' } },
        template: {
          metadata: { labels: { app: 'minio' } },
          spec: {
            containers: [{
              name: 'minio',
              image: 'quay.io/minio/minio:latest',
              args: ['server', '/data', '--console-address', ':9001'],
              env: [
                { name: 'MINIO_ROOT_USER', value: 'admin' },
                { name: 'MINIO_ROOT_PASSWORD', valueFrom: {
                  secretKeyRef: { name: 'minio-credentials', key: 'secret-key' }
                }}
              ],
              ports: [
                { containerPort: 9000, name: 'api' },
                { containerPort: 9001, name: 'console' }
              ],
              volumeMounts: [{
                name: 'storage',
                mountPath: '/data'
              }],
              resources: props.resources
            }],
            volumes: [{
              name: 'storage',
              persistentVolumeClaim: { claimName: 'minio-storage' }
            }]
          }
        }
      }
    });
    addSyncWaveAnnotation(deployment, '-100');

    // Service
    const service = new k8s.KubeService(this, 'service', {
      metadata: { name: 'minio', namespace: props.namespace },
      spec: {
        type: 'ClusterIP',
        selector: { app: 'minio' },
        ports: [
          { name: 'api', port: 9000, targetPort: k8s.IntOrString.fromNumber(9000) },
          { name: 'console', port: 9001, targetPort: k8s.IntOrString.fromNumber(9001) }
        ]
      }
    });
    addSyncWaveAnnotation(service, '-100');
  }
}
```

**Pattern Learnings from KubeVirt Deployment** (spec 002):
- Use `ApiObject` for CRDs with complex schemas (not applicable here, native K8s resources)
- Separate operator deployment from custom resource creation (not applicable, no operators)
- Use sync waves to enforce ordering: Namespace (-110) → PVC/Secret (-100) → Deployment (-100) → Service (-100)
- Use helper functions for repetitive annotations (`addSyncWaveAnnotation`)

### 4. Sync Wave Ordering and Dependency Management

**Decision**: MinIO sync wave -100, Attic sync wave -90, enforce via ArgoCD Application annotations

**Rationale**:
- **Critical dependency**: Attic CANNOT start without MinIO S3 backend available
- **Failure mode**: If Attic starts before MinIO, connection errors cause crash loop
- **ArgoCD behavior**: Resources with lower sync waves deploy and reach "Healthy" before higher waves start
- **Constitution compliance**: Principle II requires sync wave ordering for dependencies

**Sync Wave Strategy**:
```
-110: Namespaces (nix-cache namespace)
-100: MinIO (PVC, Deployment, Service) - Storage backend must be ready first
 -90: Attic (ConfigMap, Deployment, Service) - Starts after MinIO is healthy
   0: (Reserved for future resources, e.g., monitoring)
```

**ArgoCD Application Manifest Pattern**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: minio
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-100"
spec:
  source:
    repoURL: cnoe://minio/manifests
    targetRevision: HEAD
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: nix-cache
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Dependency Validation**:
- ArgoCD waits for MinIO pod to be "Running" and pass readiness checks before deploying Attic
- If MinIO fails to deploy, Attic deployment is blocked (prevents cascade failures)
- Use `argocd app wait minio --health` to verify MinIO before syncing Attic

### 5. Operational Workflows: Cache Initialization and Population

**Decision**: Provide Bash helper scripts for cache initialization and package pushing from Hetzner host

**Rationale**:
- **One-time setup**: Creating cache namespaces and retrieving signing keys is not declarative (Attic API-driven)
- **External host integration**: Hetzner host needs to push packages to Attic (cannot be fully automated via GitOps)
- **Operational flexibility**: Scripts allow for manual testing, debugging, and disaster recovery
- **Constitution compliance**: Principle II allows imperative scripts for "initial cluster bootstrapping" (cache init is analogous)

**Script 1: Initialize Attic Cache** (`deployment/scripts/nix-cache/init-attic-cache.sh`):
```bash
#!/usr/bin/env bash
# Initialize Attic "nixos" cache and retrieve public key for VM configuration

set -euo pipefail

ATTIC_URL="${ATTIC_URL:-http://attic.nix-cache.svc.cluster.local:8080}"
CACHE_NAME="${CACHE_NAME:-nixos}"

echo "Generating Attic admin token..."
ADMIN_TOKEN=$(kubectl exec -n nix-cache deploy/attic -- \
  atticd-atticadm make-token \
    --sub "admin" \
    --validity "10y" \
    --pull "*" \
    --push "*" \
    --create-cache "*" \
    --configure-cache "*" \
    --destroy-cache "*")

echo "Admin token: $ADMIN_TOKEN"
echo "Configuring Attic login..."
attic login local "$ATTIC_URL" "$ADMIN_TOKEN"

echo "Creating cache: $CACHE_NAME..."
attic cache create "$CACHE_NAME"

echo "Retrieving cache public key..."
CACHE_INFO=$(attic cache info "$CACHE_NAME")
echo "$CACHE_INFO"

PUBLIC_KEY=$(echo "$CACHE_INFO" | grep "Public key:" | awk '{print $3}')
echo ""
echo "✅ Cache initialization complete!"
echo "Add this to your NixOS VM configuration:"
echo ""
echo "nix.settings = {"
echo "  substituters = ["
echo "    \"$ATTIC_URL/$CACHE_NAME\""
echo "    \"https://cache.nixos.org\""
echo "  ];"
echo "  trusted-public-keys = ["
echo "    \"$CACHE_NAME:$PUBLIC_KEY\""
echo "    \"cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\""
echo "  ];"
echo "};"
```

**Script 2: Push to Cache** (`deployment/scripts/nix-cache/push-to-cache.sh`):
```bash
#!/usr/bin/env bash
# Push system closure or specific store paths to Attic cache

set -euo pipefail

CACHE_NAME="${CACHE_NAME:-nixos}"
STORE_PATH="${1:-/run/current-system}"

if [ ! -e "$STORE_PATH" ]; then
  echo "Error: Store path $STORE_PATH does not exist"
  exit 1
fi

echo "Pushing $STORE_PATH to cache $CACHE_NAME..."
attic push "$CACHE_NAME" "$STORE_PATH"

echo "✅ Push complete!"
echo "Check cache contents:"
echo "  attic cache info $CACHE_NAME"
```

**Workflow Integration**:
1. Deploy MinIO and Attic via ArgoCD: `cluster-update`
2. Wait for pods to be ready: `kubectl wait --for=condition=ready pod -n nix-cache -l app=attic`
3. Initialize cache: `./deployment/scripts/nix-cache/init-attic-cache.sh`
4. Push packages from Hetzner: `./deployment/scripts/nix-cache/push-to-cache.sh`
5. Configure VMs with cache substituter (copy output from init script)
6. Rebuild VM and measure performance improvement

## Decisions Summary

| Decision Point | Choice | Rationale |
|----------------|--------|-----------|
| **Storage Backend** | MinIO | S3-compatible, self-hosted, performant, cost-free |
| **Cache Server** | Attic | Modern, deduplication, multi-tenancy, Rust-based |
| **CDK8s API Level** | imports/k8s (low-level) | Exact YAML control, type safety, constitution compliance |
| **Sync Wave Ordering** | MinIO (-100), Attic (-90) | Enforce dependency (Attic requires MinIO backend) |
| **Cache Initialization** | Bash helper scripts | One-time operational tasks not suited for declarative GitOps |
| **Security Context** | MinIO non-root (UID 1000), Attic root (SQLite) | Balance security with operational simplicity for MVP |
| **Storage Size** | 100Gi PVC | Sufficient for 5-10 NixOS configurations with deduplication |
| **Resource Limits** | MinIO (2Gi/1CPU), Attic (1Gi/500m CPU) | Fit within Kind cluster capacity, avoid resource contention |

## Open Questions

None. All technical decisions are finalized and documented above.

## References

- [Attic Documentation](https://docs.attic.rs/)
- [MinIO Kubernetes Deployment Guide](https://min.io/docs/minio/kubernetes/upstream/operations/installation.html)
- [Nix Binary Cache Protocol](https://nixos.org/manual/nix/stable/protocols/binary-cache.html)
- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [CDK8s TypeScript API](https://cdk8s.io/docs/latest/typescript/)
- [KubeVirt Deployment Lessons Learned](../002-i-want-to/spec.md#implementation-lessons-learned-added-2025-10-11) (spec 002)
