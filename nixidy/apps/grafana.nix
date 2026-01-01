# Grafana - Observability Dashboards
# Provides visualization and dashboards for metrics, logs, and traces.
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# Mirrors: cdk8s/charts/infra/lgtm-grafana-chart.ts
{ config, lib, charts, ... }:
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

      # Use nixhelm for pre-rendered Helm chart
      helm.releases.grafana = {
        chart = charts.grafana.grafana;
        values = {
          persistence = {
            enabled = true;
            size = "10Gi";
          };
          adminPassword = "admin";  # Override via secret in production
          service = {
            type = "ClusterIP";
          };
          datasources = {
            "datasources.yaml" = {
              apiVersion = 1;
              datasources = [
                {
                  name = "Loki";
                  type = "loki";
                  url = "http://loki:3100";
                  access = "proxy";
                  isDefault = false;
                }
                {
                  name = "Tempo";
                  type = "tempo";
                  url = "http://tempo:3200";
                  access = "proxy";
                  isDefault = false;
                }
              ];
            };
          };
        };
      };
    };
  };
}
