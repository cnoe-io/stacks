# Shared environment configuration for all cluster types
# Mirrors: cdk8s/lib/source-url.ts, cdk8s/config/applications.ts
{ config, lib, ... }:
{
  # App-of-Apps configuration for ArgoCD
  nixidy.appOfApps = {
    name = "apps";
    namespace = "argocd";
    destination.server = "https://kubernetes.default.svc";
  };

  # Default destination for all applications
  nixidy.defaults.destination.server = "https://kubernetes.default.svc";

  # Default sync policy settings
  # Note: syncOptions must be set per-application, not at defaults level
  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = true;
  };

  # Import custom modules
  imports = [
    ../modules/application.nix
    ../modules/cluster-config.nix
  ];
}
