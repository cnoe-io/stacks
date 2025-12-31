# Simple namespace application - demonstrates basic nixidy resource generation
{ config, lib, ... }:
let
  syncWaves = import ../lib/sync-waves.nix;
in
{
  # Example: namespace-only application for demonstration
  applications.example-namespace = {
    namespace = "example";
    createNamespace = true;

    # Sync wave annotations on the ArgoCD Application
    annotations = {
      "argocd.argoproj.io/sync-wave" = syncWaves.namespaces;
    };

    # Sync policy
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
        serverSideApply = true;
      };
    };

    resources = {
      # Namespace with labels
      namespaces.example = {
        metadata = {
          labels = {
            "app.kubernetes.io/managed-by" = "nixidy";
            "app.kubernetes.io/component" = "namespace";
            "app.kubernetes.io/part-of" = "infrastructure";
            "app.kubernetes.io/name" = "example-namespace";
          };
        };
      };
    };
  };
}
