# Nix Binary Cache Strategies for Kubernetes

## Executive Summary

Based on your architecture (Kind cluster on Hetzner, KubeVirt VMs, NixOS configurations), here are the best Nix binary cache strategies ranked by effectiveness:

| Solution | Speed Gain | Cost | Complexity | Recommendation |
|----------|------------|------|------------|----------------|
| **MinIO + Attic in-cluster** | ⭐⭐⭐⭐⭐ | Free | Medium | **BEST** |
| **Harmonia on Hetzner host** | ⭐⭐⭐⭐ | Free | Low | **Easy Start** |
| **Cachix (paid)** | ⭐⭐⭐⭐⭐ | $$$  | Very Low | **Fastest Setup** |
| **Native S3 (AWS/R2)** | ⭐⭐⭐⭐ | $ | Low | Good |
| **nix-serve-ng in cluster** | ⭐⭐⭐ | Free | Low | Basic |

## Architecture Overview

**Your Current Setup:**
```
┌─────────────────────────────────────────┐
│         Hetzner Host (NixOS)            │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Kind Cluster                     │ │
│  │                                   │ │
│  │  ┌─────────────┐  ┌────────────┐ │ │
│  │  │ KubeVirt VM │  │ KubeVirt VM│ │ │
│  │  │  (NixOS)    │  │  (NixOS)   │ │ │
│  │  │             │  │            │ │ │
│  │  │ Downloads   │  │ Downloads  │ │ │
│  │  │ 700MB from  │  │ 700MB from │ │ │
│  │  │ cache.nixos │  │ cache.nixos│ │ │
│  │  └─────────────┘  └────────────┘ │ │
│  └───────────────────────────────────┘ │
│            ↓ Internet ↓                │
└─────────────────────────────────────────┘
              ↓
    cache.nixos.org (slow, external)
```

**Optimized Architecture (Recommended):**
```
┌─────────────────────────────────────────┐
│         Hetzner Host (NixOS)            │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Kind Cluster                     │ │
│  │                                   │ │
│  │  ┌─────────────┐                 │ │
│  │  │   MinIO     │ ← S3 Storage    │ │
│  │  │   (PVC)     │   (Local Disk)  │ │
│  │  └──────┬──────┘                 │ │
│  │         ↓                         │ │
│  │  ┌─────────────┐                 │ │
│  │  │   Attic     │ ← Cache Server  │ │
│  │  │  (Binary    │   (In-cluster)  │ │
│  │  │   Cache)    │                 │ │
│  │  └──────┬──────┘                 │ │
│  │         ↓                         │ │
│  │  ┌─────────────┐  ┌────────────┐ │ │
│  │  │ KubeVirt VM │  │ KubeVirt VM│ │ │
│  │  │  (NixOS)    │  │  (NixOS)   │ │ │
│  │  │             │  │            │ │ │
│  │  │ Downloads   │  │ Downloads  │ │ │
│  │  │ from Attic  │  │ from Attic │ │ │
│  │  │ (fast!)     │  │ (fast!)    │ │ │
│  │  └─────────────┘  └────────────┘ │ │
│  └───────────────────────────────────┘ │
└─────────────────────────────────────────┘
     First build still downloads from
     cache.nixos.org to populate cache
```

## Solution 1: Attic + MinIO (RECOMMENDED) ⭐⭐⭐⭐⭐

### Overview
- **Attic:** Modern, multi-tenant Nix binary cache written in Rust
- **MinIO:** S3-compatible object storage running in Kubernetes
- **Architecture:** Fully in-cluster, minimal latency

### Why This is Best for You

1. **In-cluster networking** - VMs → Attic = ~10ms latency (vs 50-200ms to internet)
2. **S3-compatible** - Uses standard protocols, easy migration
3. **Multi-tenant** - Can create separate caches per project/team
4. **Global deduplication** - One NAR stored once, referenced by multiple caches
5. **Managed signing** - Automatic signing without exposing keys
6. **Open source** - Free, no vendor lock-in
7. **Kubernetes-native** - Scales with your cluster

### Setup Steps

#### 1. Deploy MinIO to Kubernetes

```yaml
# minio-deployment.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-storage
  namespace: nix-cache
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Gi  # Adjust based on needs
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: nix-cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - :9001
        env:
        - name: MINIO_ROOT_USER
          value: admin
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: password
        ports:
        - containerPort: 9000  # API
        - containerPort: 9001  # Console
        volumeMounts:
        - name: storage
          mountPath: /data
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
          limits:
            memory: 2Gi
            cpu: 1000m
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: minio-storage
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: nix-cache
spec:
  type: ClusterIP
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
  selector:
    app: minio
```

#### 2. Deploy Attic

```yaml
# attic-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: attic-config
  namespace: nix-cache
data:
  server.toml: |
    listen = "[::]:8080"

    [database]
    url = "sqlite:///var/lib/atticd/server.db"

    [storage]
    type = "s3"
    region = "us-east-1"  # MinIO doesn't care
    bucket = "attic-cache"
    endpoint = "http://minio:9000"

    [chunking]
    nar-size-threshold = 65536
    min-size = 16384
    avg-size = 65536
    max-size = 262144

    [compression]
    type = "zstd"
    level = 8
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: attic
  namespace: nix-cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: attic
  template:
    metadata:
      labels:
        app: attic
    spec:
      containers:
      - name: attic
        image: ghcr.io/zhaofengli/attic:latest
        command: ["/bin/atticd"]
        args:
        - "-f"
        - "/etc/atticd/server.toml"
        env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: access-key
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secret-key
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: config
          mountPath: /etc/atticd
        - name: data
          mountPath: /var/lib/atticd
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 1Gi
            cpu: 500m
      volumes:
      - name: config
        configMap:
          name: attic-config
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: attic
  namespace: nix-cache
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: attic
```

#### 3. Initialize Attic Cache

```bash
# Create admin token
kubectl exec -n nix-cache deploy/attic -- \
  atticd-atticadm make-token \
    --sub "admin" \
    --validity "10y" \
    --pull "*" \
    --push "*" \
    --create-cache "*" \
    --configure-cache "*" \
    --destroy-cache "*"

# Save token as ATTIC_TOKEN=...

# Create MinIO bucket
kubectl run -n nix-cache mc-client --rm -it --image=minio/mc -- \
  mc alias set minio http://minio:9000 admin <password>
kubectl run -n nix-cache mc-client --rm -it --image=minio/mc -- \
  mc mb minio/attic-cache

# Configure Attic
kubectl port-forward -n nix-cache svc/attic 8080:8080 &
attic login local http://localhost:8080 $ATTIC_TOKEN
attic cache create nixos
```

#### 4. Configure VMs to Use Attic

```nix
# In VM's configuration.nix or via cloud-init
nix.settings = {
  substituters = [
    "http://attic.nix-cache.svc.cluster.local:8080/nixos"
    "https://cache.nixos.org"
  ];
  trusted-public-keys = [
    # Get key from: attic cache info nixos
    "nixos:YOUR_CACHE_PUBLIC_KEY"
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
};
```

#### 5. Populate Cache from Hetzner Host

```bash
# On Hetzner host, upload your system closure
attic push nixos /run/current-system

# Or push specific packages
attic push nixos $(nix build --no-link --print-out-paths github:vpittamp/nixos-config#nixosConfigurations.hetzner.config.system.build.toplevel)
```

### Performance Expectations

| Metric | Before (cache.nixos.org) | After (Attic) | Improvement |
|--------|-------------------------|---------------|-------------|
| Download speed | 10-50 MB/s | 100-500 MB/s | **10x** |
| Latency | 50-200ms | 1-10ms | **20x** |
| First build | 20-25 min | 20-25 min | Same |
| Second build | 20-25 min | **2-3 min** | **8x faster** |
| VM-to-VM copy | No sharing | Instant | **∞x** |

### Cost Analysis

- **MinIO storage:** 100 GB PVC = $0 (local disk on Hetzner)
- **Attic compute:** ~256 MB RAM + 100m CPU = minimal
- **Network:** In-cluster = free
- **Total:** **$0/month** (just disk space)

### Pros
✅ Fastest for in-cluster VMs
✅ Open source, fully self-hosted
✅ Multi-tenant capabilities
✅ Global deduplication saves storage
✅ S3-compatible (easy migration)
✅ Scales horizontally
✅ Built-in monitoring (Prometheus metrics)

### Cons
❌ Requires Kubernetes knowledge
❌ Need to manage MinIO + Attic
❌ First build still slow (populating cache)
❌ No external access without ingress

## Solution 2: Harmonia on Hetzner Host (EASIEST) ⭐⭐⭐⭐

### Overview
- **Harmonia:** Rust-based binary cache serving /nix/store
- **Deployment:** Directly on Hetzner host (not in Kubernetes)
- **Architecture:** VMs access host's /nix/store via HTTP

### Why This is Easier

1. **No Kubernetes complexity** - Just enable NixOS module
2. **Leverages host's store** - No duplicate storage
3. **Fast setup** - 5 minutes to deploy
4. **Good performance** - Written in Rust, zstd compression

### Setup Steps

#### 1. Enable Harmonia on Hetzner Host

```nix
# In Hetzner host configuration.nix
services.harmonia = {
  enable = true;
  signKeyPath = "/var/lib/secrets/harmonia.secret";
  settings = {
    bind = "[::]:5000";  # Listen on all interfaces
    priority = 30;  # Lower than cache.nixos.org
  };
};

# Open firewall
networking.firewall.allowedTCPPorts = [ 5000 ];
```

#### 2. Generate Signing Key

```bash
# On Hetzner host
sudo mkdir -p /var/lib/secrets
sudo nix-store --generate-binary-cache-key \
  hetzner-cache \
  /var/lib/secrets/harmonia.secret \
  /var/lib/secrets/harmonia.pub

# Get public key
cat /var/lib/secrets/harmonia.pub
```

#### 3. Configure VMs

```nix
# In VM configuration
nix.settings = {
  substituters = [
    "http://10.244.0.1:5000"  # Hetzner host IP from VM perspective
    "https://cache.nixos.org"
  ];
  trusted-public-keys = [
    "hetzner-cache:YOUR_PUBLIC_KEY_HERE"
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
};
```

### Performance Expectations

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Download speed | 10-50 MB/s | 50-200 MB/s | **5x** |
| Latency | 50-200ms | 5-20ms | **10x** |
| Rebuild time | 20-25 min | **5-8 min** | **3x faster** |

### Pros
✅ Simplest setup (5 minutes)
✅ No duplicate storage
✅ Leverages existing Hetzner store
✅ Written in Rust (fast, reliable)
✅ Built-in Prometheus metrics
✅ Automatic zstd compression

### Cons
❌ Single point of failure (host)
❌ VMs share host's packages (security consideration)
❌ Host must have packages built first
❌ Network limited to Hetzner host bandwidth

## Solution 3: Cachix (Managed Service) ⭐⭐⭐⭐⭐

### Overview
- **Paid service:** $20-$50/month for private cache
- **Fastest setup:** 2 minutes
- **Best performance:** Global CDN

### Setup

```bash
# Install cachix
nix-env -iA nixpkgs.cachix

# Authenticate
cachix authtoken <YOUR_TOKEN>

# Create cache
cachix create vpittamp-nixos

# Push from Hetzner host
cachix push vpittamp-nixos /run/current-system

# Configure VMs (auto-configured by cachix)
cachix use vpittamp-nixos
```

### Pros
✅ 2-minute setup
✅ Global CDN (fast everywhere)
✅ Managed (no maintenance)
✅ Automatic garbage collection
✅ Web UI for management
✅ GitHub Actions integration
✅ Free for open source

### Cons
❌ Costs $20-50/month for private
❌ Vendor lock-in
❌ Data leaves your infrastructure
❌ Internet dependency

## Solution 4: Native S3 Cache (AWS S3 / Cloudflare R2) ⭐⭐⭐⭐

### Overview
- Use Nix's built-in S3 support
- No additional software needed
- Works with AWS S3, Cloudflare R2, Backblaze B2

### Cloudflare R2 Setup (Recommended - Free egress)

```bash
# Create R2 bucket
cf r2 bucket create nixos-cache

# Push from Hetzner
nix copy \
  --to 's3://nixos-cache?profile=r2&scheme=https&endpoint=<account-id>.r2.cloudflarestorage.com' \
  /run/current-system
```

```nix
# Configure VMs
nix.settings = {
  substituters = [
    "s3://nixos-cache?profile=r2&scheme=https&endpoint=<account-id>.r2.cloudflarestorage.com"
    "https://cache.nixos.org"
  ];
};
```

### Pricing
- **Cloudflare R2:** $0.015/GB/month storage, **FREE egress**
- **AWS S3:** $0.023/GB/month + $0.09/GB egress (expensive!)
- **Backblaze B2:** $0.005/GB/month + first 3x storage free egress

### Pros
✅ No server management
✅ Built into Nix
✅ Scales infinitely
✅ R2 has free egress
✅ Global availability

### Cons
❌ Slightly higher latency than in-cluster
❌ Requires cloud account
❌ Storage costs (though minimal)
❌ Internet dependency

## Solution 5: nix-serve-ng ⭐⭐⭐

### Overview
- Drop-in replacement for nix-serve
- 1.5x-32x faster than original
- Simple HTTP server

### Setup

```nix
# On Hetzner host
services.nix-serve = {
  enable = true;
  port = 5000;
  secretKeyFile = "/var/lib/nix-serve/cache-priv-key.pem";
};
```

### Pros
✅ Simple
✅ Fast (Haskell)
✅ Drop-in replacement

### Cons
❌ Less features than Harmonia/Attic
❌ No compression
❌ No deduplication
❌ Basic serving only

## Recommended Implementation Plan

### Phase 1: Quick Win (Day 1) - Harmonia on Host
1. Enable Harmonia on Hetzner host (5 min)
2. Configure VMs to use it (5 min)
3. Test with rebuild (2 min)
4. **Result: 3x faster rebuilds immediately**

### Phase 2: Optimal Setup (Week 1) - Attic + MinIO
1. Deploy MinIO to cluster (30 min)
2. Deploy Attic (30 min)
3. Initialize cache (15 min)
4. Populate from Hetzner host (varies)
5. Update VM configs (10 min)
6. **Result: 8x faster rebuilds, full deduplication**

### Phase 3: Optimization (Month 1)
1. Set up automatic cache population
2. Create separate caches per environment
3. Configure garbage collection
4. Set up monitoring/alerts
5. **Result: Production-ready cache system**

## Monitoring & Maintenance

### Metrics to Track
- Cache hit rate
- Download speed
- Storage usage
- Build time reduction

### Prometheus Queries

```promql
# Attic/Harmonia metrics
rate(http_requests_total[5m])
http_request_duration_seconds_bucket
nix_cache_size_bytes
```

### Maintenance Tasks
- Garbage collect old generations (weekly)
- Monitor disk usage
- Update Attic/Harmonia versions
- Review access logs

## Cost Comparison

| Solution | Monthly Cost | Setup Time | Performance |
|----------|-------------|------------|-------------|
| Attic + MinIO | $0 | 1 hour | ⭐⭐⭐⭐⭐ |
| Harmonia | $0 | 10 min | ⭐⭐⭐⭐ |
| Cachix | $20-50 | 2 min | ⭐⭐⭐⭐⭐ |
| Cloudflare R2 | ~$5 | 20 min | ⭐⭐⭐⭐ |
| AWS S3 | ~$30+ | 20 min | ⭐⭐⭐⭐ |

## Conclusion

**For your architecture, I recommend:**

1. **Start with Harmonia** (today) - Get immediate 3x speedup
2. **Migrate to Attic + MinIO** (next week) - Get 8x speedup + deduplication
3. **Keep Cachix in mind** if you want zero maintenance

The combination of Attic + MinIO gives you the best performance, costs nothing, and leverages your existing Kubernetes infrastructure.
