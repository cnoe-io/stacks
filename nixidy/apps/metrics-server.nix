# Metrics Server - Kubernetes Resource Metrics API
# Provides resource metrics (CPU/memory) for HPA/VPA and kubectl top.
# Required for KIND/minikube clusters with insecure TLS.
# Source: ref-implementation/metric-server.yaml
# KIND only - idpBuilder local development
#
# Uses local chart definition in charts/kubernetes-sigs/metrics-server/
# since this chart is not available in nixhelm
{ config, lib, charts, ... }:
let
  isKind = config.environmentType == "kind";
  namespace = "kube-system";
in
{
  config = lib.mkIf isKind {
    applications.metrics-server = {
      inherit namespace;
      createNamespace = false;  # kube-system already exists

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-100";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = false;
          serverSideApply = true;
        };
      };

      # Use metrics-server chart from nixhelm (kubernetes-sigs repo)
      helm.releases.metrics-server = {
        chart = charts.kubernetes-sigs.metrics-server;
        values = {
          # Required for KIND/minikube - kubelet TLS cert not trusted
          args = [ "--kubelet-insecure-tls" ];
        };
      };
    };
  };
}
