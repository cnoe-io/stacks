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

      # Placeholder ConfigMap until Loki Helm chart is configured
      resources = {
        configMaps.loki-placeholder = {
          metadata = {
            namespace = namespace;
            labels = {
              "app.kubernetes.io/name" = "loki";
              "app.kubernetes.io/part-of" = "observability";
            };
          };
          data = {
            status = "placeholder";
            note = "Loki will be deployed via Helm chart. See cdk8s/charts/infra/lgtm-loki-chart.ts";
          };
        };
      };
    };
  };
}
