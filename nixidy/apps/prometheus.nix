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

      # Placeholder for Prometheus/Mimir deployment
      # Chart: mimir-distributed from https://grafana.github.io/helm-charts
      # or kube-prometheus-stack from prometheus-community
      yamls = [
        ''
          # Prometheus/Mimir metrics collection
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Options:
          # - Mimir for long-term storage and multi-tenancy
          # - kube-prometheus-stack for full monitoring stack
          #
          # Key values:
          # - persistence.enabled = true
          # - alertmanager.enabled = true
          # - serviceMonitors for application metrics
        ''
      ];
    };
  };
}
