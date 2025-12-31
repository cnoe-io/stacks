# KMCP - MCP Servers for Kubernetes
# Provides MCP (Model Context Protocol) servers for AI agents.
#
# Mirrors: cdk8s/charts/infra/kmcp-chart.ts
{ config, lib, ... }:
let
  namespace = "kagent";
in
{
  config = {
    applications.kmcp = {
      inherit namespace;
      createNamespace = false;  # Created by kagent.nix

      annotations = {
        "argocd.argoproj.io/sync-wave" = "80";  # After kagent
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          serverSideApply = true;
        };
      };

      # Placeholder for KMCP deployment
      yamls = [
        ''
          # KMCP MCP servers
          # Provides context servers for AI agents:
          # - Kubernetes context
          # - GitHub context
          # - ArgoCD context
          # - Backstage context
        ''
      ];
    };
  };
}
