# Spark Operator - Apache Spark on Kubernetes
# Manages SparkApplication and ScheduledSparkApplication CRDs.
# Enables running Spark jobs on Kubernetes via declarative manifests.
# Source: ref-implementation/spark-operator.yaml
# KIND only - for local development with Backstage templates
#
# Uses local chart definition in charts/kubeflow/spark-operator/
# since this chart is not available in nixhelm
{ config, lib, charts, ... }:
let
  isKind = config.environmentType == "kind";
  namespace = "spark-operator";
in
{
  config = lib.mkIf isKind {
    applications.spark-operator = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "50";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
        };
      };

      # Use spark-operator chart from nixhelm
      helm.releases.spark-operator = {
        chart = charts.spark-operator.spark-operator;
        values = {
          # Default values sufficient for local development
        };
      };
    };
  };
}
