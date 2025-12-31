# Loki - Log Aggregation
# Provides log aggregation and querying for observability.
#
# Mirrors: cdk8s/charts/infra/lgtm-loki-chart.ts
{ config, lib, ... }:
let
  namespace = "observability";
in
{
  config = {
    applications.loki = {
      inherit namespace;
      createNamespace = false;  # Created by grafana.nix

      annotations = {
        "argocd.argoproj.io/sync-wave" = "45";  # Before Grafana
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

      # Placeholder for Loki deployment
      # Chart: loki from https://grafana.github.io/helm-charts
      yamls = [
        ''
          # Loki log aggregation
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Key values:
          # - loki.storage.type = "filesystem" or "s3"
          # - persistence.enabled = true
          # - loki.schemaConfig for chunk storage
        ''
      ];
    };
  };
}
