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

      # Placeholder for Tempo deployment
      # Chart: tempo from https://grafana.github.io/helm-charts
      yamls = [
        ''
          # Tempo distributed tracing
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Key values:
          # - persistence.enabled = true
          # - tempo.storage.trace.backend = "local" or "s3"
          # - tempo.receivers (otlp, jaeger, zipkin)
        ''
      ];
    };
  };
}
