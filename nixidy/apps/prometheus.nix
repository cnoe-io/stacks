# Prometheus/Mimir - Metrics Collection
# Provides metrics collection and long-term storage.
#
# Mirrors: cdk8s/charts/infra/lgtm-mimir-chart.ts
{ config, lib, ... }:
let
  namespace = "observability";
in
{
  config = {
    applications.prometheus = {
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

      # Placeholder ConfigMap until Prometheus is configured
      resources = {
        configMaps.prometheus-placeholder = {
          metadata = {
            namespace = namespace;
            labels = {
              "app.kubernetes.io/name" = "prometheus";
              "app.kubernetes.io/part-of" = "observability";
            };
          };
          data = {
            status = "placeholder";
            note = "Prometheus metrics. Using Mimir for long-term storage. See lgtm-mimir in observability.nix";
          };
        };
      };
    };
  };
}
