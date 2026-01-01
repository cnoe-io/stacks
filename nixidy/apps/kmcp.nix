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

      # Placeholder ConfigMap until KMCP is configured
      resources = {
        configMaps.kmcp-placeholder = {
          metadata = {
            namespace = namespace;
            labels = {
              "app.kubernetes.io/name" = "kmcp";
              "app.kubernetes.io/part-of" = "kagent";
            };
          };
          data = {
            status = "placeholder";
            note = "KMCP MCP servers for AI agents. See cdk8s/charts/infra/kmcp-chart.ts";
          };
        };
      };
    };
  };
}
