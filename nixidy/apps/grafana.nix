# Grafana - Observability Dashboards
# Provides visualization and dashboards for metrics, logs, and traces.
#
# Mirrors: cdk8s/charts/infra/lgtm-grafana-chart.ts
{ config, lib, ... }:
let
  namespace = "observability";
in
{
  config = {
    # Observability namespace
    applications.observability-namespace = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "40";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
        };
      };

      resources = {
        namespaces.observability = {
          metadata = {
            name = namespace;
            labels = {
              "app.kubernetes.io/name" = "observability";
              "app.kubernetes.io/part-of" = "platform";
            };
          };
        };
      };
    };

    # Grafana application
    applications.grafana = {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "60";
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

      # Placeholder for Grafana deployment
      # Chart: grafana from https://grafana.github.io/helm-charts
      yamls = [
        ''
          # Grafana visualization platform
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Key values:
          # - persistence.enabled = true
          # - datasources for Loki, Tempo, Mimir
          # - dashboardProviders for pre-built dashboards
        ''
      ];
    };
  };
}
