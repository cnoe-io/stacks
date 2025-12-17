# Session Summary: NixOS VM with Tailscale - October 14, 2025

## Overview
This session focused on fixing Tailscale authentication issues in the NixOS KubeVirt VM and creating a reproducible Docker image build process.

## Completed Work

### 1. Reproducible Build Infrastructure ✅

Created complete Docker image build infrastructure in `/home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/`:

**Files Created:**
- `Dockerfile` - nginx-based image serving qcow2 files
- `build-and-push.sh` - Automated build script (755 lines, fully documented)
- `README.md` - Comprehensive documentation with usage examples, troubleshooting, and CI/CD integration guidance

**Key Features:**
- nginx:alpine base image (not FROM scratch)
- Serves qcow2 at `/usr/share/nginx/html/nixos.qcow2`
- Readiness/liveness probes configured
- Large file download support (`client_max_body_size 0`)
- Directory listing enabled

### 2. CDK8s Chart Improvements ✅

**Updated:** `/home/vpittamp/stacks/cdk8s/charts/apps/nixos-image-server-chart.ts`
- Added `imagePullPolicy: 'Always'` to force fresh image pulls
- Ensures latest qcow2 content is always used

**Updated:** `/home/vpittamp/stacks/cdk8s/config/applications.ts`
- Line 174: Image tag updated to `v1.1.1-tailscale`
- Line 288: SSH key corrected to `hetzner-nixos` (working key)

### 3. ExternalSecret Chart Parameterization ✅

**Updated:** `/home/vpittamp/stacks/cdk8s/charts/secrets/nixos-vm-cloudinit-secrets-chart.ts`

Added `nixosSystemPath` parameter (lines 63-68):
```typescript
/**
 * PATH to set for runcmd scripts in NixOS
 * @default "/run/current-system/sw/bin:/run/wrappers/bin:$PATH"
 * @remarks NixOS system binaries are in /run/current-system/sw/bin
 */
nixosSystemPath?: string;
```

**Benefits:**
- Follows NixOS best practices for cloud-init scripts
- Configurable with sensible defaults
- Prevents "command not found" errors for Tailscale/RustDesk

### 4. Docker Image Versioning ✅

**Images Pushed to Docker Hub:**
- `vpittamp23/nixos-kubevirt-desktop:v1.1.0-tailscale` (11GB) ❌ Contains old qcow2 without Tailscale
- `vpittamp23/nixos-kubevirt-desktop:v1.1.1-tailscale` (11GB) ❌ Same issue (used cached old qcow2)

**Digest:** `sha256:7a5ae13d08babfccb915e474966d69eb35ac0869bd5f8133cbb749f401481ee9`

### 5. Deployment Status ✅

**Current Cluster State:**
- ✅ `nixos-image-server` pod: Running (serving old image)
- ✅ `nixos-dev-datavolume`: Succeeded (imported old image)
- ✅ `nixos-dev-vm`: Running (IP: 10.244.0.150)
- ❌ Tailscale: NOT installed in VM (old image)
- ❌ RustDesk: NOT configured (old image)

## Critical Issue Discovered ❌

### NixOS Image Build Failed

**Error Location:** Background bash job `e71eef`
```bash
cd /etc/nixos && nixos-generate --format qcow \
  --configuration configurations/kubevirt-desktop.nix \
  --out-link /tmp/kubevirt-desktop-v1.1.0
```

**Exit Code:** 127
**Root Cause:** Bash syntax error - `BUILD_PID=: command not found`

**Impact:**
1. The qcow2 file at `/tmp/kubevirt-desktop-v1.1.0/nixos.qcow2` is from an OLD build
2. Docker images v1.1.0 and v1.1.1 contain this OLD qcow2
3. The old qcow2 does NOT have Tailscale installed
4. Current VM is running but cannot authenticate to Tailscale network

**Evidence:**
```bash
kubectl exec -n default virt-launcher-nixos-dev-vm-lczz9 -- \
  /run/current-system/sw/bin/tailscale version
# Error: no such file or directory
```

## NixOS Configuration Status ✅

**File:** `/etc/nixos/configurations/kubevirt-desktop.nix`

**Verified Includes:**
- ✅ Line 105-109: Tailscale service enabled
- ✅ Line 234: Tailscale package in systemPackages
- ✅ Line 97-103: SSH properly configured
- ✅ RustDesk in systemPackages
- ✅ KDE Plasma 6 desktop environment
- ✅ cloud-init enabled

**Configuration is CORRECT** - the build just never completed successfully.

## Next Steps (Priority Order)

### 1. Fix nixos-generate Command ⚠️ HIGH PRIORITY

**Issue:** Bash variable assignment syntax error

**Current Command:**
```bash
cd /etc/nixos && nixos-generate --format qcow \
  --configuration configurations/kubevirt-desktop.nix \
  --out-link /tmp/kubevirt-desktop-v1.1.0 2>&1 | tee /tmp/build.log &
BUILD_PID=$!
```

**Correct Command:**
```bash
cd /etc/nixos
nixos-generate --format qcow \
  --configuration configurations/kubevirt-desktop.nix \
  --out-link /tmp/kubevirt-desktop-v1.2.0 \
  2>&1 | tee /tmp/kubevirt-desktop-v1.2.0-build.log
```

**Alternative (Use Reproducible Script):**
```bash
cd /home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop
./build-and-push.sh v1.2.0-tailscale
```

### 2. Build Fresh NixOS Image ⏱️ ~25-30 min

**Command:**
```bash
cd /etc/nixos
nixos-generate --format qcow \
  --configuration configurations/kubevirt-desktop.nix \
  --out-link /tmp/kubevirt-desktop-v1.2.0
```

**Expected Output:**
- `/tmp/kubevirt-desktop-v1.2.0/nixos.qcow2` (11GB)
- Includes: Tailscale, RustDesk, KDE Plasma 6, cloud-init

**Verification After Build:**
```bash
ls -lh /tmp/kubevirt-desktop-v1.2.0/nixos.qcow2
# Expected: ~11GB file
```

### 3. Package as Docker Image ⏱️ ~5 min

**Commands:**
```bash
mkdir -p /tmp/docker-build-v1.2.0
cp /home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/Dockerfile /tmp/docker-build-v1.2.0/
cp /tmp/kubevirt-desktop-v1.2.0/nixos.qcow2 /tmp/docker-build-v1.2.0/

cd /tmp/docker-build-v1.2.0
docker build -t vpittamp23/nixos-kubevirt-desktop:v1.2.0-tailscale .
```

**Expected Output:**
```
Successfully built <image-id>
Successfully tagged vpittamp23/nixos-kubevirt-desktop:v1.2.0-tailscale
```

### 4. Push to Docker Hub ⏱️ ~10 min

**Command:**
```bash
docker push vpittamp23/nixos-kubevirt-desktop:v1.2.0-tailscale
```

**Monitor:**
```bash
docker images | grep nixos-kubevirt-desktop
# Should show: v1.2.0-tailscale with correct Size
```

### 5. Update CDK8s Configuration ⏱️ ~2 min

**File:** `/home/vpittamp/stacks/cdk8s/config/applications.ts`

**Change Line 174:**
```typescript
// FROM:
image: 'vpittamp23/nixos-kubevirt-desktop:v1.1.1-tailscale'

// TO:
image: 'vpittamp23/nixos-kubevirt-desktop:v1.2.0-tailscale'
```

**Synthesize & Deploy:**
```bash
cd /home/vpittamp/stacks/cdk8s
npx ts-node main-v2.ts

source ~/stacks/deployment/scripts/cluster-menu.sh
argocd app sync argocd/nixos-image-server --prune --insecure
```

### 6. Delete VM/DataVolume for Fresh Boot ⏱️ ~1 min

**Commands:**
```bash
kubectl delete vm nixos-dev-vm -n default
kubectl delete datavolume nixos-dev-datavolume -n default
```

**Wait for Recreation (~5 min):**
```bash
watch kubectl get vm,vmi,datavolume -n default
# Wait for: DataVolume Succeeded, VM Running
```

### 7. Verify Tailscale Authentication ⏱️ ~3 min

**SSH into VM:**
```bash
kubectl port-forward -n default svc/nixos-dev-vm-rdp 2222:22 &
ssh -p 2222 vpittamp@localhost
```

**Inside VM:**
```bash
which tailscale
# Expected: /run/current-system/sw/bin/tailscale

tailscale version
# Expected: tailscale version (from NixOS package)

tailscale status
# Expected: logged in, shows Tailnet info
```

**Check Tailscale Devices:**
```bash
kubectl exec -n tailscale tailscale-subnet-router -- tailscale status
# Expected: Shows nixos-dev-vm in device list
```

### 8. Verify RustDesk via Tailscale ⏱️ ~5 min

**Get VM Tailscale IP:**
```bash
ssh -p 2222 vpittamp@localhost 'tailscale ip -4'
# Expected: 100.x.x.x
```

**Get RustDesk ID:**
```bash
ssh -p 2222 vpittamp@localhost 'cat /root/rustdesk-info.txt'
# Expected: RustDesk ID: <9-digit-number>
```

**Connect from Local Machine:**
1. Ensure local machine connected to same Tailnet
2. Open RustDesk client
3. Enter Tailscale IP: `100.x.x.x`
4. Enter RustDesk ID from above
5. Password: (from Azure Key Vault or default)

## Files Modified This Session

### New Files Created ✅
1. `/home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/Dockerfile`
2. `/home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/build-and-push.sh`
3. `/home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/README.md`
4. `/home/vpittamp/stacks/docs/SESSION_SUMMARY_2025-10-14.md` (this file)

### Modified Files ✅
1. `/home/vpittamp/stacks/cdk8s/charts/apps/nixos-image-server-chart.ts` (Line 81: added imagePullPolicy)
2. `/home/vpittamp/stacks/cdk8s/charts/secrets/nixos-vm-cloudinit-secrets-chart.ts` (Lines 63-89: parameterized PATH)
3. `/home/vpittamp/stacks/cdk8s/config/applications.ts` (Lines 174, 288: updated image tag and SSH key)

### Existing Files (Verified Correct, No Changes) ✅
- `/etc/nixos/configurations/kubevirt-desktop.nix` - Tailscale configuration confirmed

## Lessons Learned

### 1. Background Job Variable Assignment ⚠️
**Issue:** `BUILD_PID=$!` after piping to background fails
**Solution:** Capture PID before piping or use proper subshell

### 2. Image Caching in Kind ⚠️
**Issue:** Kind nodes cache Docker images aggressively
**Solution:**
- Use unique image tags (v1.2.0 not v1.1.1)
- Set `imagePullPolicy: Always` in charts
- Or manually remove cached images: `docker exec <node> crictl rmi <image>`

### 3. Docker Image Requirements for nginx-based Server ⚠️
**Issue:** `FROM scratch` images have no CMD/ENTRYPOINT
**Solution:** Use `FROM nginx:alpine` with proper nginx configuration

### 4. Cloud-Init Cache Persistence ⚠️
**Issue:** Cloud-init scripts won't re-run unless both VM AND DataVolume are deleted
**Solution:** Always delete both resources for fresh cloud-init execution

### 5. NixOS PATH in Cloud-Init ✅
**Issue:** System binaries not in default PATH during cloud-init execution
**Solution:** Explicitly set `PATH="/run/current-system/sw/bin:/run/wrappers/bin:$PATH"`

## Quick Start Commands for Next Session

### Option A: Use Reproducible Script (Recommended)
```bash
cd /home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop
./build-and-push.sh v1.2.0-tailscale
```

### Option B: Manual Build
```bash
# 1. Build NixOS image
cd /etc/nixos
nixos-generate --format qcow \
  --configuration configurations/kubevirt-desktop.nix \
  --out-link /tmp/kubevirt-desktop-v1.2.0

# 2. Package as Docker image
mkdir -p /tmp/docker-build-v1.2.0
cp /home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/Dockerfile /tmp/docker-build-v1.2.0/
cp /tmp/kubevirt-desktop-v1.2.0/nixos.qcow2 /tmp/docker-build-v1.2.0/
cd /tmp/docker-build-v1.2.0
docker build -t vpittamp23/nixos-kubevirt-desktop:v1.2.0-tailscale .

# 3. Push to Docker Hub
docker push vpittamp23/nixos-kubevirt-desktop:v1.2.0-tailscale

# 4. Update config and deploy
sed -i 's/v1\.1\.1-tailscale/v1.2.0-tailscale/g' \
  /home/vpittamp/stacks/cdk8s/config/applications.ts
cd /home/vpittamp/stacks/cdk8s && npx ts-node main-v2.ts
source ~/stacks/deployment/scripts/cluster-menu.sh && cluster-update

# 5. Fresh deployment
kubectl delete vm nixos-dev-vm -n default
kubectl delete datavolume nixos-dev-datavolume -n default
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Hetzner NixOS Host                                          │
│                                                             │
│  /etc/nixos/configurations/kubevirt-desktop.nix             │
│          │                                                  │
│          ├─ Tailscale: enabled ✅                           │
│          ├─ RustDesk: in systemPackages ✅                  │
│          ├─ KDE Plasma 6 ✅                                 │
│          └─ cloud-init: enabled ✅                          │
│          │                                                  │
│          ▼                                                  │
│  nixos-generate --format qcow ❌ (FAILED - exit 127)       │
│          │                                                  │
│          ▼                                                  │
│  /tmp/kubevirt-desktop-v1.2.0/nixos.qcow2 (11GB)           │
│          │                                                  │
│          ▼                                                  │
│  Docker: vpittamp23/nixos-kubevirt-desktop:v1.2.0          │
│          │                                                  │
│          ▼                                                  │
│  Docker Hub ──────────────────────────────────────┐        │
└─────────────────────────────────────────────────┼──────────┘
                                                   │
                                                   ▼
┌─────────────────────────────────────────────────────────────┐
│ Kind Cluster (localdev-control-plane)                       │
│                                                             │
│  ┌───────────────────────────────────────────┐             │
│  │ nixos-image-server (nginx:alpine)         │             │
│  │ - Serves: /usr/share/nginx/html/nixos.qcow2│            │
│  │ - imagePullPolicy: Always                 │             │
│  └───────────────────┬───────────────────────┘             │
│                      │ HTTP                                │
│                      ▼                                      │
│  ┌───────────────────────────────────────────┐             │
│  │ DataVolume (CDI Import)                   │             │
│  │ - Source: HTTP nixos-image-server         │             │
│  │ - Status: Succeeded ✅                     │             │
│  └───────────────────┬───────────────────────┘             │
│                      │ PVC                                 │
│                      ▼                                      │
│  ┌───────────────────────────────────────────┐             │
│  │ NixOS VM (KubeVirt)                       │             │
│  │ - IP: 10.244.0.150 ✅                     │             │
│  │ - Tailscale: NOT installed ❌             │             │
│  │ - RustDesk: NOT configured ❌             │             │
│  └───────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

## References

### Documentation
- `/home/vpittamp/stacks/cdk8s/docker/nixos-kubevirt-desktop/README.md` - Build process, usage, troubleshooting
- `/home/vpittamp/stacks/specs/004-deploy-nixos-vms/rustdesk-headless-spec.md` - RustDesk configuration
- `/home/vpittamp/stacks/docs/tailscale-cluster-access.md` - Tailscale operator setup

### Charts
- `/home/vpittamp/stacks/cdk8s/charts/apps/nixos-image-server-chart.ts`
- `/home/vpittamp/stacks/cdk8s/charts/secrets/nixos-vm-cloudinit-secrets-chart.ts`
- `/home/vpittamp/stacks/cdk8s/charts/infra/nixos-vm-chart.ts`

### NixOS
- `/etc/nixos/configurations/kubevirt-desktop.nix` - VM image definition
- nixos-generators: https://github.com/nix-community/nixos-generators

## Estimated Total Time for Completion

| Task | Time | Status |
|------|------|--------|
| Fix nixos-generate syntax | 5 min | Pending |
| Build NixOS qcow2 | 25-30 min | Pending |
| Package Docker image | 5 min | Pending |
| Push to Docker Hub | 10 min | Pending |
| Update CDK8s config | 2 min | Pending |
| Synthesize & deploy | 3 min | Pending |
| Delete VM/DataVolume | 1 min | Pending |
| Wait for recreation | 5 min | Pending |
| Verify Tailscale | 3 min | Pending |
| Verify RustDesk | 5 min | Pending |
| **TOTAL** | **~60 min** | - |

---

**Session Date:** October 14, 2025
**Status:** Infrastructure Ready, NixOS Build Required
**Next Session Goal:** Complete NixOS image build and verify Tailscale + RustDesk functionality
