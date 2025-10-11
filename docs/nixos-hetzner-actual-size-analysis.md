# NixOS Hetzner Actual Size Analysis

## Current System Statistics

**Total System Size:**
- System closure: **25.5 GiB** (`/run/current-system`)
- Home-manager path: **12.5 GiB** (user packages)
- Nix store total: **70 GB**
- Disk usage: **159 GB used** of 224 GB (75% full)

## Largest Space Consumers (Actual Measurements)

### 1. **Graphics & Mesa Drivers** (~972 MiB each)
```
/nix/store/...-mesa-25.2.4                    971.7 MiB
/nix/store/...-graphics-drivers                971.7 MiB
```
**Why it's large:** Full Mesa 3D graphics library with all drivers
**Needed for:** Desktop rendering, OpenGL/Vulkan support
**Can remove?** Not if you need desktop/RDP graphics

### 2. **PyTorch (Python ML Library)** (784.7 MiB)
```
/nix/store/...-python3.13-torch-2.8.0         784.7 MiB
```
**Why it's here:** Machine learning library (likely pulled by speech-to-text or AI tools)
**Can remove?** YES - disable speech-to-text or find which package requires it

### 3. **Chromium Browser** (814.1 MiB)
```
/nix/store/...-chromium-unwrapped-141.0       814.1 MiB
```
**Why it's large:** Full browser engine
**Can remove?** YES - if using Firefox only or headless

### 4. **Firefox Browser** (753.7 MiB)
```
/nix/store/...-firefox-unwrapped-143.0.4      753.7 MiB
```
**Why it's large:** Full browser engine
**Can remove?** YES - if using Chromium only (but you have both!)

### 5. **VSCode** (762.1 MiB)
```
/nix/store/...-vscode-1.104.3                 762.1 MiB
```
**Why it's large:** Full IDE with Electron
**Can remove?** Depends on workflow - could use neovim instead

### 6. **GitKraken** (547-554 MiB)
```
/nix/store/...-gitkraken-11.4.0               547M-554M
```
**Why it's large:** Electron-based Git GUI
**Can remove?** YES - use lazygit, VSCode git, or CLI instead

### 7. **Azure CLI** (222 MiB with dependencies)
```
/nix/store/...-python3.12-azure-cli-2.65.0    222M
```
**Why it's large:** Python CLI with many Azure SDK dependencies
**Can remove?** YES - if not using Azure cloud

### 8. **FFmpeg** (965.5 MiB + 966.3 MiB = ~1.9 GB)
```
/nix/store/...-ffmpeg-7.1.1-lib               965.5 MiB
/nix/store/...-ffmpeg-7.1.1-bin               966.3 MiB
```
**Why it's large:** Full video/audio codec library
**Needed for:** Browser video, desktop recording, media playback
**Can remove?** Not recommended if using desktop

### 9. **Papirus Icon Theme** (962.1 MiB)
```
/nix/store/...-papirus-icon-theme-20250501    962.1 MiB
```
**Why it's large:** Comprehensive icon set with many sizes/variants
**Can remove?** YES - use default KDE icons or smaller theme

### 10. **GTK4 + LibAdwaita** (~930 MiB)
```
/nix/store/...-gtk4-4.18.6                    912.7 MiB
/nix/store/...-libadwaita-1.7.6               921.9 MiB
```
**Why it's here:** GNOME toolkit (for GTK apps)
**Can remove?** Depends on which apps need it

### 11. **GStreamer Bad Plugins** (884.0 MiB)
```
/nix/store/...-gst-plugins-bad-1.26.5         884.0 MiB
```
**Why it's large:** Extended multimedia codecs
**Needed for:** Browser media, desktop apps
**Can remove?** Only if not using media playback

### 12. **Qt6 Development Headers** (768-769 MiB)
```
/nix/store/...-qtbase-6.9.2-dev               768.0 MiB
/nix/store/...-qtsvg-6.9.2-dev                769.3 MiB
```
**Why it's here:** Development headers for Qt
**Can remove?** YES - only needed for compiling Qt apps

### 13. **KDE Framework Libraries** (~50+ packages, 600-1000 MiB each)
```
/nix/store/...-kio-6.18.0                     1003.0 MiB
/nix/store/...-kparts-6.18.0                  1008.9 MiB
/nix/store/...-kwallet-6.18.0                 972.4 MiB
/nix/store/...-knotifyconfig-6.18.0           1003.3 MiB
... (many more KDE packages)
```
**Why it's large:** Full KDE Plasma 6 framework
**Can remove?** Only by switching desktop environments

## Quick Win Recommendations (Largest Impact)

### Remove Duplicate Browsers (-1.5 GB)
You have **both Chromium AND Firefox**. Pick one:

```nix
# In modules/desktop/kde-plasma.nix:178
# Either:
environment.systemPackages = with pkgs; [
  chromium  # Keep this
  # firefox  # Remove this
];

# Or in home-modules/tools/chromium.nix, disable:
# modules.tools.chromium.enable = false;
```

**Savings: ~750-800 MB**

### Remove GitKraken (-550 MB)
Use lazygit (already installed) or VSCode's git integration:

```nix
# In user/packages.nix:106-108
gitTools = with pkgs; [
  git-lfs git-crypt delta diff-so-fancy lazygit
  # Remove gitkraken line
] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
  # gitkraken  # REMOVE THIS
];
```

**Savings: ~550 MB**

### Remove Azure CLI if Not Using Azure (-220 MB)
```nix
# In user/packages.nix:120-122
cloudTools = [
  # azure-cli-bin  # Comment out if not using Azure
];
```

**Savings: ~220 MB**

### Disable Speech-to-Text if Not Using (-850 MB with PyTorch)
```nix
# In configurations/hetzner.nix:240-246
services.speech-to-text = {
  enable = false;  # Change to false
  # ... rest disabled
};
```

**Savings: ~850 MB (includes PyTorch dependency)**

### Use Smaller Icon Theme (-900 MB)
```nix
# In home-modules/profiles/base-home.nix:81
# Remove papirus-icon-theme, use KDE default
home.packages = packageConfig.getProfile.user; # Remove + [ pkgs.papirus-icon-theme ]
```

**Savings: ~960 MB**

### Remove Qt Development Headers (-1.5 GB)
These are only needed for compiling Qt apps, not running them.

```bash
# Check what's pulling in -dev packages
nix-store --query --referrers /nix/store/...-qtbase-6.9.2-dev
```

If nothing critical, you can garbage collect after removing the referrer.

**Potential Savings: ~1.5 GB**

## Total Potential Savings Summary

| Action | Savings | Difficulty |
|--------|---------|-----------|
| Remove duplicate browser (Firefox or Chromium) | ~800 MB | Easy |
| Remove GitKraken | ~550 MB | Easy |
| Remove Azure CLI | ~220 MB | Easy |
| Disable speech-to-text | ~850 MB | Easy |
| Use smaller icon theme | ~960 MB | Easy |
| Remove Qt dev headers | ~1.5 GB | Medium |
| **Total Quick Wins** | **~4.9 GB** | **Easy** |

## Medium-Impact Changes

### Switch from PulseAudio to PipeWire (-50-100 MB)
Currently using PulseAudio Full for RDP audio. If not using RDP audio:

```nix
# In configurations/hetzner.nix:254-269
services.pulseaudio.enable = lib.mkForce false;
services.pipewire.enable = lib.mkForce true;
```

### Remove Unused Language Servers (-200-300 MB)
If not using certain languages:

```nix
# In user/packages.nix:61-82
languageServers = with pkgs; [
  # Keep only what you use
  # Remove: gopls, rust-analyzer if not using Go/Rust
];
```

## Major Changes (If Desktop Not Needed)

### Switch to Lightweight Desktop (-2 GB)
Replace KDE Plasma with XFCE:

```nix
# Instead of: ../modules/desktop/kde-plasma.nix
# Use: services.xserver.desktopManager.xfce.enable = true;
```

**Savings: ~2-3 GB**

### Go Headless (SSH + tmux only) (-4 GB)
Remove all desktop modules, keep SSH access:

```nix
# Remove all desktop imports from hetzner.nix
# Keep only: SSH, tmux, terminal tools
```

**Savings: ~4-5 GB**

## Garbage Collection Commands

After making changes, clean up old generations:

```bash
# Remove old system generations (keep last 3)
sudo nix-collect-garbage --delete-older-than 3d

# Optimize store (deduplicate)
sudo nix-store --optimize

# Check space after cleanup
du -sh /nix/store
df -h /
```

## Current Disk Usage Breakdown

```
Total disk: 224 GB
Used: 159 GB (75%)
Available: 54 GB

Breakdown:
- Nix store: 70 GB
- Other system files: ~89 GB (likely old generations, logs, temp files)
```

## Recommendation: Create Minimal VM Config

Create a new `configurations/hetzner-vm-minimal.nix`:

```nix
{
  imports = [
    ./base.nix
    ../modules/services/development.nix
    ../modules/desktop/remote-access.nix  # Keep RDP
    ../modules/desktop/xrdp-with-sound.nix
  ];

  # Lightweight XFCE instead of KDE
  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.displayManager.lightdm.enable = true;

  # Minimal package set
  environment.systemPackages = with pkgs; [
    vim git tmux htop kubectl firefox
  ];

  # Disable unnecessary services
  services.speech-to-text.enable = false;
}
```

This would reduce system size from **25.5 GB to ~15-18 GB**.
