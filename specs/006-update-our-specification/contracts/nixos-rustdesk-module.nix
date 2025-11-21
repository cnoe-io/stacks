# NixOS RustDesk Module Contract
# Feature: 006-update-our-specification
# Purpose: Define the NixOS module API for RustDesk service configuration in base image

{ config, lib, pkgs, ... }:

with lib;

{
  options.services.rustdesk = {
    enable = mkEnableOption "RustDesk remote desktop service";

    enableSystemService = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable RustDesk as a system service (multi-user.target) rather than a user service.
        Required for headless mode (no user login required).
      '';
    };

    enableDirectIpAccess = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable direct IP access mode on port 21116.
        Allows P2P connections without relay server.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "nixos";
      description = ''
        User account to run RustDesk service as.
        Use "root" for headless mode, "nixos" for desktop mode.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.rustdesk-flutter;
      description = ''
        RustDesk package to use.
        Options: pkgs.rustdesk, pkgs.rustdesk-flutter (recommended).
      '';
    };

    headlessMode = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable headless mode (no GUI dependencies).
        Automatically sets allow-linux-headless option.
      '';
    };

    firewallPorts = mkOption {
      type = types.listOf types.port;
      default = [ 21116 ];
      description = ''
        TCP ports to open in firewall for RustDesk.
        Default: [21116] for direct connection mode.
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = { LIBGL_ALWAYS_SOFTWARE = "1"; };
      description = ''
        Additional environment variables for the RustDesk service.
        Use LIBGL_ALWAYS_SOFTWARE=1 to avoid OpenGL errors in headless mode.
      '';
    };
  };

  config = mkIf config.services.rustdesk.enable {
    # Ensure package is installed
    environment.systemPackages = [ config.services.rustdesk.package ];

    # Open firewall ports
    networking.firewall.allowedTCPPorts = config.services.rustdesk.firewallPorts;

    # Create systemd service
    systemd.services.rustdesk = mkIf config.services.rustdesk.enableSystemService {
      description = "RustDesk Remote Desktop Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = config.services.rustdesk.user;
        ExecStartPre = mkIf config.services.rustdesk.headlessMode ''
          ${config.services.rustdesk.package}/bin/rustdesk --option allow-linux-headless Y
        '';
        ExecStart = "${config.services.rustdesk.package}/bin/rustdesk --service";
        Restart = "on-failure";
        RestartSec = "5s";
      };

      environment = config.services.rustdesk.extraEnvironment;
    };

    # Headless mode configuration (write to RustDesk config directory)
    systemd.tmpfiles.rules = mkIf (config.services.rustdesk.headlessMode && config.services.rustdesk.enableSystemService) [
      "d /root/.config/rustdesk 0755 root root -"
    ];
  };
}

# USAGE EXAMPLE (in base image flake.nix or configuration.nix):
#
# {
#   imports = [ ./modules/services/rustdesk.nix ];
#
#   services.rustdesk = {
#     enable = true;
#     enableSystemService = true;
#     enableDirectIpAccess = true;
#     user = "root";
#     package = pkgs.rustdesk-flutter;
#     headlessMode = true;
#     extraEnvironment = {
#       LIBGL_ALWAYS_SOFTWARE = "1";
#     };
#   };
# }

# VALIDATION:
# - After building image: nix-build -A config.system.build.toplevel
# - Check service exists: systemctl cat rustdesk (in VM)
# - Verify headless mode: cat /root/.config/rustdesk/RustDesk2.toml | grep allow-linux-headless
# - Test port listening: ss -tlnp | grep 21116 (in VM)
