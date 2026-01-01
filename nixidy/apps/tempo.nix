# Tempo - Distributed Tracing
# Provides distributed tracing for observability.
#
# Mirrors: cdk8s/charts/infra/lgtm-tempo-chart.ts
{ config, lib, ... }:
let
  namespace = "observability";
in
{
  config = {
    applications.tempo = {
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

      # Placeholder ConfigMap until Tempo is configured
      resources = {
        configMaps.tempo-placeholder = {
          metadata = {
            namespace = namespace;
            labels = {
              "app.kubernetes.io/name" = "tempo";
              "app.kubernetes.io/part-of" = "observability";
            };
          };
          data = {
            status = "placeholder";
            note = "Tempo distributed tracing. See cdk8s/charts/infra/lgtm-tempo-chart.ts. Jaeger is available as alternative.";
          };
        };
      };
    };
  };
}
