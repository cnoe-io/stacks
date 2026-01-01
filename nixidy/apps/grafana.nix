# Grafana - Observability Dashboards
# Provides visualization and dashboards for metrics, logs, and traces.
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# Mirrors: cdk8s/charts/infra/lgtm-grafana-chart.ts
{ config, lib, charts, ... }:
let
  inherit (config.cluster) ingressHost;
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
          ingress = {
            enabled = true;
            ingressClassName = "nginx";
            hosts = [ "grafana.${ingressHost}" ];
            annotations = {
              "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
            };
            tls = [{
              hosts = [ "grafana.${ingressHost}" ];
            }];
          };
          datasources = {
            "datasources.yaml" = {
              apiVersion = 1;
              datasources = [
                # Mimir - Metrics Backend (default)
                {
                  name = "Mimir";
                  type = "prometheus";
                  access = "proxy";
                  url = "http://mimir:9009/prometheus";
                  isDefault = true;
                  uid = "mimir";
                  jsonData = {
                    httpMethod = "POST";
                    prometheusType = "Mimir";
                    prometheusVersion = "2.14.0";
                    timeInterval = "15s";
                    # Metrics → Traces: Click exemplars to jump to trace
                    exemplarTraceIdDestinations = [
                      {
                        name = "trace_id";
                        datasourceUid = "tempo";
                        urlDisplayLabel = "View trace in Tempo";
                      }
                    ];
                  };
                }
                # Loki - Logs Backend with derived fields for trace correlation
                {
                  name = "Loki";
                  type = "loki";
                  url = "http://loki:3100";
                  access = "proxy";
                  uid = "loki";
                  isDefault = false;
                  jsonData = {
                    maxLines = 1000;
                    # Logs → Traces: Extract trace_id from logs
                    derivedFields = [
                      {
                        datasourceUid = "tempo";
                        matcherRegex = "(?:trace_id|traceId|TraceId|traceid)[=:]\\s*\"?([a-fA-F0-9]{32})\"?";
                        matcherType = "regex";
                        name = "TraceID";
                        url = "\${__value.raw}";
                      }
                    ];
                  };
                }
                # Tempo - Traces Backend with full correlation
                {
                  name = "Tempo";
                  type = "tempo";
                  url = "http://tempo:3200";
                  access = "proxy";
                  uid = "tempo";
                  isDefault = false;
                  jsonData = {
                    httpMethod = "GET";
                    serviceMap = {
                      datasourceUid = "mimir";
                    };
                    nodeGraph = {
                      enabled = true;
                    };
                    search = {
                      hide = false;
                    };
                    lokiSearch = {
                      datasourceUid = "loki";
                    };
                    # Traces → Logs: Click span to see related logs
                    tracesToLogs = {
                      datasourceUid = "loki";
                      spanStartTimeShift = "-1h";
                      spanEndTimeShift = "1h";
                      filterByTraceID = true;
                      filterBySpanID = true;
                      mapTagNamesEnabled = true;
                      mappedTags = [
                        { key = "service.name"; value = "service_name"; }
                        { key = "host.name"; value = "host"; }
                      ];
                    };
                    # Traces → Metrics: Click span to see related metrics
                    tracesToMetrics = {
                      datasourceUid = "mimir";
                      spanStartTimeShift = "-1h";
                      spanEndTimeShift = "1h";
                      tags = [
                        { key = "service.name"; value = "service"; }
                        { key = "host.name"; value = "instance"; }
                      ];
                      queries = [
                        {
                          name = "Request rate";
                          query = "sum(rate(traces_spanmetrics_calls_total{\$__tags}[5m]))";
                        }
                        {
                          name = "Duration (p95)";
                          query = "histogram_quantile(0.95, sum(rate(traces_spanmetrics_latency_bucket{\$__tags}[5m])) by (le))";
                        }
                      ];
                    };
                  };
                }
              ];
            };
          };
        };
      };
    };
  };
}
