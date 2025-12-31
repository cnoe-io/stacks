# Application module options schema
# Defines the structure for application definitions in nixidy
{ lib, config, ... }:
let
  syncWaves = import ../lib/sync-waves.nix;
in
{
  options.applicationOptions = lib.mkOption {
    type = lib.types.submodule {
      options = {
        # Cluster targeting (replaces clusterType from cdk8s)
        clusterTypes = lib.mkOption {
          type = lib.types.listOf (lib.types.enum [ "kind" "talos" ]);
          default = [ "kind" "talos" ];
          description = "Which cluster types this app is deployed to";
        };

        clusterNames = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "Optional: Only deploy to specific cluster names";
        };

        # ArgoCD multi-source support
        sources = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf (lib.types.submodule {
            options = {
              repoURL = lib.mkOption { type = lib.types.str; };
              path = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              targetRevision = lib.mkOption { type = lib.types.str; default = "main"; };
              chart = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              helm = lib.mkOption { type = lib.types.nullOr lib.types.attrs; default = null; };
              ref = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
            };
          }));
          default = null;
          description = "Multi-source configuration for ArgoCD";
        };

        # Hub-and-spoke deployment target
        targetCluster = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum [ "hub" "hetzner" "thinkpad" "ryzen" "talos" ]);
          default = null;
          description = "Target cluster for hub-and-spoke deployment";
        };

        # Ignore differences for ArgoCD
        ignoreDifferences = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              group = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              kind = lib.mkOption { type = lib.types.str; };
              name = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              namespace = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
              jsonPointers = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
              jqPathExpressions = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
            };
          });
          default = [];
          description = "ArgoCD ignoreDifferences configuration";
        };
      };
    };
    default = {};
    description = "Extended application options beyond nixidy defaults";
  };

  # Helper function for sync wave annotations
  options.lib.syncWaves = lib.mkOption {
    type = lib.types.attrs;
    default = syncWaves;
    description = "Sync wave constants for ArgoCD ordering";
    readOnly = true;
  };
}
