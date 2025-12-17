# NixOS Rebuild Performance Analysis

## Current Build Status

**Build Command:** `sudo nixos-rebuild switch --flake github:vpittamp/nixos-config#hetzner`

**Current Stage:** Downloading/copying source archives (nixpkgs)
- Status: `[2 copied (181.2 MiB), 76.8 MiB DL] copying nixpkgs-24.11 archive`
- Build started: ~15:49 (current time check needed)
- Still running as of check

**Progress Indicators:**
```
[1/1/2 copied (181.2/181.2 MiB), 31.5 MiB DL] - Initial fetch
[2 copied (181.2 MiB), 76.8 MiB DL] - Copying nixpkgs archive
```

## Build Speed Assessment

### Speed: **SLOW** 🐌

**Why it's slow:**

1. **Network bottleneck** - Downloading from cache.nixos.org and GitHub
   - Fetching flake inputs: ~181 MiB
   - Downloading pre-built packages: 76.8 MiB so far (likely 700+ MiB total based on previous runs)

2. **VM I/O limitations**
   - KubeVirt VM with emulated storage
   - Nix store writes are synchronous and metadata-heavy
   - Copy operations slower than bare metal

3. **Previous build showed:**
   ```
   [6/19/53 built, 1/12/13 copied (491.7/722.5 MiB), 480.3/707.8 MiB DL]
   [6/19/53 built, 1/12/13 copied (540.6/722.5 MiB), 526.6/707.8 MiB DL]
   [3/28/54 built, 1/12/13 copied (680.9/722.5 MiB), 667.0/707.8 MiB DL]
   ```
   - Total download: ~708 MiB
   - Total copy: ~722 MiB
   - Building: 53-54 packages
   - **Time taken: ~15-20 minutes** (based on previous attempt)

### Is it progressing? **YES** ✓

The build IS progressing, just slowly:
- Successfully fetched flake
- Currently copying nixpkgs archive
- Next: Download ~700 MB of pre-built packages
- Then: Build ~50 packages locally
- Finally: Switch to new configuration

### Estimated Time to Completion

Based on previous build patterns:

| Phase | Progress | Est. Time Remaining |
|-------|----------|---------------------|
| Fetch flake | ✅ Done | 0 min |
| Copy nixpkgs archive | 🔄 In Progress (42%) | 2-3 min |
| Download packages | ⏳ Pending | 8-12 min |
| Build packages | ⏳ Pending | 5-8 min |
| Activation | ⏳ Pending | 1-2 min |
| **TOTAL** | **~20%** | **16-25 minutes** |

**Current estimate: 16-25 minutes total** from when it started at 15:49.

## Why This Configuration Takes So Long

### 1. Large Closure Size (25.5 GB)
The full `hetzner` configuration includes:
- KDE Plasma 6 desktop (~3-4 GB)
- Two browsers: Chromium + Firefox (~1.6 GB)
- Development tools + language servers (~1.5 GB)
- Audio/video: FFmpeg, PulseAudio, codecs (~2 GB)
- ML libraries: PyTorch for speech-to-text (~800 MB)

### 2. First-Time Build vs Rebuild
- **First build on VM:** Downloads everything from cache
- **Subsequent rebuilds:** Much faster if packages already in store
- **After config changes:** Only new/changed packages downloaded

### 3. Network-Bound Operations
```
708 MiB download at typical VM network speed (~10-30 MB/s) = 23-70 seconds
But with nixpkgs overhead (metadata, hash checking) = 8-12 minutes
```

### 4. Build Operations
Some packages need local compilation:
- 53 packages built (not in cache)
- Each takes 10 seconds - 2 minutes
- Total: ~5-8 minutes

## How to Speed Up Future Builds

### Strategy 1: Use Local Binary Cache (FASTEST) ⚡
**Speed improvement: 80-90% faster**

Set up a local binary cache on Hetzner host or NFS:

```nix
# In VM configuration
nix.settings = {
  substituters = [
    "http://192.168.1.x:5000"  # Local cache server
    "https://cache.nixos.org"
  ];
};
```

Benefits:
- First VM build still slow
- Subsequent VMs or rebuilds: 2-3 minutes instead of 20
- All packages served from local network

### Strategy 2: Pre-Build Minimal Base Image 🎯
**Speed improvement: 70% faster**

Create a pre-built disk image with base system:

```bash
# On Hetzner host, build minimal system
nix build github:vpittamp/nixos-config#nixosConfigurations.hetzner-minimal.config.system.build.toplevel

# Convert to VM image
# Use as base for KubeVirt VMs
```

Benefits:
- Base packages (~15 GB) already in VM
- Only user customizations need installation
- Rebuild time: 3-5 minutes

### Strategy 3: Use Container Images for Nix Store 📦
**Speed improvement: 50-60% faster**

Pre-populate Nix store using OCI image:

```bash
# Build store paths as container layer
nix build github:vpittamp/nixos-config#nixosConfigurations.hetzner.config.system.build.toplevel
docker save -o nixos-store.tar

# Mount as DataVolume in VM
# Copy to /nix/store before first rebuild
```

Benefits:
- Nix store pre-seeded with common packages
- Network downloads reduced by 80%
- Rebuild time: 5-8 minutes

### Strategy 4: Reduce Configuration Size 📉
**Speed improvement: 40-60% faster**

Use minimal configuration (from previous analysis):

```nix
# Create hetzner-vm-minimal.nix
- Remove KDE → XFCE (saves 3 GB)
- Remove duplicate browser (saves 800 MB)
- Remove GitKraken (saves 550 MB)
- Disable speech-to-text (saves 850 MB)
- Minimal packages only

# Result: ~15 GB instead of 25.5 GB
# Download: ~400 MB instead of 700 MB
# Build time: 8-12 minutes instead of 20-25
```

### Strategy 5: Enable Parallel Downloads 🚀
**Speed improvement: 20-30% faster**

```nix
nix.settings = {
  max-jobs = 4;  # Parallel builds
  cores = 2;     # Cores per job
  download-speed = 0;  # Unlimited
  http-connections = 5;  # Parallel downloads
};
```

### Strategy 6: Use Faster Substituter ⚡
**Speed improvement: 10-20% faster**

```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"  # Additional cache
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:..."
    "nix-community.cachix.org-1:..."
  ];
};
```

### Strategy 7: Optimize VM Resources 💪
**Speed improvement: 15-25% faster**

Increase VM resources:
- CPU: 4 → 6-8 cores
- Memory: 8 GB → 12-16 GB
- Storage: virtio-scsi → virtio-blk (faster I/O)

```yaml
# In nixos-vm-chart.ts
resources:
  requests:
    cpu: "6"
    memory: 12Gi
```

## Recommended Approach for Your Use Case

**Best Option: Pre-Built Minimal Base Image + Local Cache**

1. **Create minimal base image** (~10 GB)
   - XFCE or no desktop
   - Essential dev tools only
   - SSH + tmux
   - Build time: 10-15 minutes (one time)

2. **Set up local binary cache** (optional but recommended)
   - Use Hetzner host as cache server
   - Push base image paths to cache
   - All VMs pull from local network

3. **User customization via home-manager**
   - Desktop preferences
   - Additional tools
   - Personal configs
   - Fast rebuild: 2-3 minutes

**Result:**
- Initial VM boot: 2-3 minutes (pre-built image)
- First customization: 5-8 minutes (home-manager)
- Subsequent rebuilds: 1-2 minutes (only changed paths)

## Comparison: Current vs Optimized

| Metric | Current | Optimized | Improvement |
|--------|---------|-----------|-------------|
| System size | 25.5 GB | 15 GB | -41% |
| Download size | 708 MB | 200-300 MB | -58% |
| Build time (first) | 20-25 min | 8-12 min | -52% |
| Build time (rebuild) | 15-20 min | 2-3 min | -85% |
| Disk usage | 159 GB | 100-120 GB | -25% |

## Immediate Actions You Can Take

### Now (No Config Changes):
1. **Be patient** - Current build will finish in ~15-20 minutes
2. **Don't interrupt** - Let it complete fully
3. **Monitor**: `tmux capture-pane -t %1 -p | tail -5` every few minutes

### After This Build:
1. **Test system** - Verify everything works
2. **Create snapshot** - Backup working state
3. **Plan reduction** - Decide which packages to remove

### Next Build:
1. **Implement quick wins** from size analysis:
   - Remove duplicate browser
   - Remove GitKraken
   - Disable speech-to-text
   - **Result: Next build ~12-15 minutes** (smaller download)

2. **Create minimal config** for future VMs:
   - Use `hetzner-vm-minimal` configuration
   - **Result: 8-12 minute builds**

### Long-term:
1. **Set up binary cache** on Hetzner host
2. **Pre-build base images** for common use cases
3. **Use home-manager** for user customizations

## Current Build Timeline (Estimated)

```
15:49 - Build started
15:50 - Fetching flake (done)
15:51 - Copying nixpkgs archive (current, ~40% done)
15:53 - Starting package downloads (0/700 MB)
16:02 - Package downloads complete
16:03 - Building local packages (0/53)
16:10 - Build complete, activating
16:12 - Activation complete ✅

Estimated completion: ~16:12 (23 minutes total)
```

Check again at 16:00 to see download progress.
