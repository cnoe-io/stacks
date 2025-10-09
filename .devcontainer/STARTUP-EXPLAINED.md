# DevContainer Startup Process

## Overview
The devcontainer has been updated to mimic the startup automation from `devspace.yaml` to ensure Nix and home-manager are properly installed and configured.

## Startup Flow

### 1. **Check for Nix Installation** 
- Checks if `/nix/store` directory exists and is populated
- Checks if Nix daemon profile script exists at `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`
- If either check fails, proceeds to install Nix

### 2. **Install Nix (First Run Only)**
- Downloads official Nix installer from `https://nixos.org/nix/install`
- Runs multi-user installation with daemon mode: `sudo bash /tmp/install-nix.sh --daemon --yes`
- This creates:
  - `/nix/store` - Nix package store
  - `/nix/var/nix/profiles/default` - System-wide Nix profile
  - Nix daemon service configuration

### 3. **Start Nix Daemon**
- Checks if `nix-daemon` process is running using `pgrep`
- If not running, starts it in the background
- Logs output to `/tmp/nix-daemon.log`
- Waits 2 seconds for daemon to initialize

### 4. **Source Nix Environment**
- Sources the Nix profile script to add Nix to PATH
- Priority order:
  1. System-wide daemon profile: `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`
  2. User profile: `~/.nix-profile/etc/profile.d/nix.sh`
- Exports environment variables:
  - `NIX_CONFIG="experimental-features = nix-command flakes"` - Enables flakes
  - Updates `PATH` to include Nix binaries

### 5. **Initialize Home-Manager (First Run Only)**
- Checks for marker file `~/.home-manager-initialized`
- If not found:
  - Removes conflicting shell config files (`.bashrc`, `.profile`, `.bash_profile`)
  - Runs: `nix run home-manager -- switch --flake github:vpittamp/nixos-config#code --impure`
  - Creates marker file on success
  - Continues even if home-manager fails (non-blocking)

### 6. **Complete Startup**
- Shows success message
- Container is ready with fully configured Nix environment

## Key Differences from Previous Version

| Aspect | Previous | New (DevSpace-Style) |
|--------|----------|---------------------|
| **Nix Installation** | Assumed pre-installed | Installs if missing |
| **Daemon Management** | Assumed running | Starts if not running |
| **Error Handling** | Failed silently | Clear status messages |
| **First Run** | Could fail | Fully automated |
| **Persistence** | No state tracking | Uses marker files |

## Marker Files

- `~/.home-manager-initialized` - Created after successful home-manager setup
- Prevents re-running expensive initialization on subsequent container starts
- Delete this file to force re-initialization

## Troubleshooting

### Check Nix Installation
```bash
ls -la /nix/store
which nix
nix --version
```

### Check Daemon Status
```bash
pgrep -x nix-daemon
cat /tmp/nix-daemon.log
```

### Check Home-Manager Status
```bash
ls -la ~/.home-manager-initialized
home-manager generations
```

### Force Re-initialization
```bash
rm ~/.home-manager-initialized
# Rebuild devcontainer or run postStartCommand manually
```

## Manual Test
You can test the startup script manually:
```bash
bash /tmp/devcontainer-startup-explained.sh
```

## Comparison with DevSpace

The devcontainer now follows the same pattern as the `devspace.yaml` terminal command:
1. ✅ Install Nix if missing
2. ✅ Start Nix daemon
3. ✅ Source Nix environment 
4. ✅ Run home-manager initialization
5. ✅ Track state with marker files
6. ✅ Provide clear progress messages

This ensures consistent behavior whether using DevSpace or DevContainer.
