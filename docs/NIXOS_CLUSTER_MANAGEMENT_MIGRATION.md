# NixOS Cluster Management Migration Guide

## Overview

Cluster management functions have been migrated from `/etc/nixos/home-modules/tools/cluster-management.nix` to the version-controlled `stacks` repository.

## Benefits of Migration

✅ **Version Control**: All cluster management logic tracked in Git
✅ **Portability**: Works on any system without NixOS configuration
✅ **No Sudo Required**: Update functions without system rebuilds
✅ **Easier Collaboration**: Changes visible in pull requests
✅ **Faster Iteration**: Modify and test without `nixos-rebuild`

## Migration Steps

### 1. Source New Functions

Add to your `~/.bashrc`:

```bash
# Cluster management functions
source ~/stacks/.bashrc-cluster
```

Then reload:

```bash
source ~/.bashrc
```

### 2. Test New Functions

Verify functions work:

```bash
# Test synthesis
cls

# Test status
clst

# Test interactive menu (if gum is installed)
clm
```

### 3. Remove NixOS Configuration

Once verified, remove the old configuration from `/etc/nixos`:

**File to remove or modify:**
- `/etc/nixos/home-modules/tools/cluster-management.nix`

**In your NixOS configuration**, remove or comment out:

```nix
# In /etc/nixos/home-manager.nix or similar:
# imports = [
#   ./home-modules/tools/cluster-management.nix  # REMOVE THIS LINE
# ];
```

### 4. Rebuild NixOS

Apply the changes:

```bash
sudo nixos-rebuild switch
```

### 5. Verify Cleanup

Start a new shell session and verify:

```bash
# Should still work (sourced from ~/.bashrc)
which cluster-deploy

# Should point to the function, not a path
type cluster-deploy
```

## Function Mapping

All functions remain the same:

| Old (NixOS) | New (stacks) | Still Works |
|-------------|--------------|-------------|
| `cluster-synth` | `cluster-synth` | ✅ |
| `cluster-deploy` | `cluster-deploy` | ✅ |
| `cluster-update` | `cluster-update` | ✅ |
| `cluster-update-gum` | `cluster-update-gum` | ✅ |
| `cluster-recreate` | `cluster-recreate` | ✅ |
| `cluster-status` | `cluster-status` | ✅ |
| `cluster-menu` | `cluster-menu` | ✅ |
| `cls` | `cls` | ✅ |
| `cld` | `cld` | ✅ |
| `clu` | `clu` | ✅ |
| `clug` | `clug` | ✅ |
| `clr` | `clr` | ✅ |
| `clst` | `clst` | ✅ |
| `clm` | `clm` | ✅ |

## Differences from NixOS Version

### Improved

1. **Gum is optional**: Functions gracefully fall back to basic prompts if gum is not installed
2. **Better path handling**: Updated to reference `azure-workload-identity/` subdirectory
3. **Version controlled**: All changes tracked in Git

### Removed

- Direct nix package references (e.g., `${pkgs.gum}/bin/gum`) - now uses `gum` from PATH
- Nix string interpolation syntax - pure bash now

## Rollback

If you need to rollback:

1. Re-enable in `/etc/nixos`:
   ```nix
   imports = [
     ./home-modules/tools/cluster-management.nix
   ];
   ```

2. Remove from `~/.bashrc`:
   ```bash
   # Remove or comment out:
   # source ~/stacks/.bashrc-cluster
   ```

3. Rebuild NixOS:
   ```bash
   sudo nixos-rebuild switch
   ```

## Keeping Both (Temporary)

During migration, you can keep both:

1. Keep NixOS config active
2. Source stacks version in `~/.bashrc` (it will override)
3. Test thoroughly
4. Remove NixOS version when confident

## Troubleshooting

**Functions not found after sourcing:**
```bash
# Check if file exists
ls -la ~/stacks/cluster-menu.sh

# Check if sourcing succeeded
source ~/stacks/cluster-menu.sh
echo $?  # Should be 0
```

**gum not found:**
```bash
# Install gum (optional)
nix-env -iA nixpkgs.gum

# Or use without gum - functions work with basic prompts
clu  # Works without gum
```

**Path issues:**
```bash
# Verify STACKS_DIR
echo $STACKS_DIR

# Override if needed
export STACKS_DIR=$HOME/stacks
source ~/stacks/cluster-menu.sh
```

## Support

For issues or questions, check:
- `CLUSTER_UPDATE_GUIDE.md` - Detailed usage guide
- `cluster-menu.sh` - Source code with inline documentation
- Run `./cluster-menu.sh` without sourcing for help text
