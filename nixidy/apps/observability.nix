# Observability Stack Applications
# Namespace, secrets, Jaeger, and LGTM stack
# Mirrors: cdk8s/charts/platform/observability-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost name;
  namespace = "observability";
  clusterSuffix = if name != "" then "-${name}" else "";
in
{
  # NOTE: observability-namespace is defined in grafana.nix

  # Observability Secrets
  applications.observability-secrets = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-75";
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
      retry = {
        limit = 10;
        backoff = {
          duration = "5s";
          factor = 2;
          maxDuration = "3m";
        };
      };
    };


    yamls = [
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: langfuse-postgres-credentials
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: langfuse-postgres-credentials
            creationPolicy: Owner
          data:
            - secretKey: POSTGRES_PASSWORD
              remoteRef:
                key: LANGFUSE-POSTGRES-PASSWORD
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: langfuse-auth
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: langfuse-auth
            creationPolicy: Owner
          data:
            - secretKey: NEXTAUTH_SECRET
              remoteRef:
                key: LANGFUSE-NEXTAUTH-SECRET
            - secretKey: SALT
              remoteRef:
                key: LANGFUSE-SALT
      ''
    ];
  };

  # Jaeger Distributed Tracing
  applications.jaeger = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-65";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      # Jaeger All-in-One Deployment
      deployments.jaeger = {
        metadata = {
          inherit namespace;
          labels.app = "jaeger";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "jaeger";

          template = {
            metadata.labels.app = "jaeger";

            spec.containers = [{
              name = "jaeger";
              image = "jaegertracing/all-in-one:1.66.0";
              ports = [
                { containerPort = 5775; name = "zipkin-compact"; protocol = "UDP"; }
                { containerPort = 6831; name = "jaeger-compact"; protocol = "UDP"; }
                { containerPort = 6832; name = "jaeger-binary"; protocol = "UDP"; }
                { containerPort = 5778; name = "config-rest"; }
                { containerPort = 16686; name = "query"; }
                { containerPort = 14250; name = "grpc"; }
                { containerPort = 14268; name = "jaeger-http"; }
                { containerPort = 14269; name = "admin"; }
                { containerPort = 9411; name = "zipkin"; }
              ];
              env = [
                { name = "COLLECTOR_ZIPKIN_HOST_PORT"; value = ":9411"; }
                { name = "SPAN_STORAGE_TYPE"; value = "badger"; }
                { name = "BADGER_EPHEMERAL"; value = "false"; }
                { name = "BADGER_DIRECTORY_VALUE"; value = "/badger/data"; }
                { name = "BADGER_DIRECTORY_KEY"; value = "/badger/key"; }
                { name = "BADGER_SPAN_STORE_TTL"; value = "168h"; }
              ];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  memory = "512Mi";
                };
              };
              volumeMounts = [{
                name = "data";
                mountPath = "/badger";
              }];
            }];
          };
        };
      };

      # Jaeger Services
      services.jaeger-query = {
        metadata = {
          inherit namespace;
          labels.app = "jaeger";
        };
        spec = {
          ports = [{
            name = "query";
            port = 16686;
            targetPort = "query";
          }];
          selector.app = "jaeger";
        };
      };

      services.jaeger-collector = {
        metadata = {
          inherit namespace;
          labels.app = "jaeger";
        };
        spec = {
          ports = [
            { name = "grpc"; port = 14250; targetPort = "grpc"; }
            { name = "http"; port = 14268; targetPort = "jaeger-http"; }
            { name = "zipkin"; port = 9411; targetPort = "zipkin"; }
          ];
          selector.app = "jaeger";
        };
      };

      # Jaeger Ingress
      ingresses.jaeger = {
        metadata = {
          inherit namespace;
          annotations = {
            "nginx.ingress.kubernetes.io/use-regex" = "true";
            "nginx.ingress.kubernetes.io/rewrite-target" = "/$2";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = ingressHost;
            http.paths = [{
              path = "/jaeger(/|$)(.*)";
              pathType = "ImplementationSpecific";
              backend.service = {
                name = "jaeger-query";
                port.name = "query";
              };
            }];
          }];
        };
      };
    };
  };

  # LGTM Mimir - Metrics Backend
  applications.lgtm-mimir = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-60";
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

    resources = {
      statefulSets.mimir = {
        metadata = {
          inherit namespace;
          labels.app = "mimir";
        };
        spec = {
          replicas = 1;
          serviceName = "mimir";
          selector.matchLabels.app = "mimir";

          template = {
            metadata.labels.app = "mimir";

            spec = {
              containers = [{
                name = "mimir";
                image = "grafana/mimir:2.14.0";
                args = [
                  "-config.file=/etc/mimir/mimir.yaml"
                ];
                ports = [{
                  containerPort = 9009;
                  name = "http";
                }];
                volumeMounts = [
                  { name = "config"; mountPath = "/etc/mimir"; }
                  { name = "data"; mountPath = "/data"; }
                ];
              }];

              volumes = [{
                name = "config";
                configMap.name = "mimir-config";
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "20Gi";
            };
          }];
        };
      };

      services.mimir = {
        metadata = {
          inherit namespace;
          labels.app = "mimir";
        };
        spec = {
          ports = [{
            name = "http";
            port = 9009;
            targetPort = "http";
          }];
          selector.app = "mimir";
        };
      };

      configMaps.mimir-config = {
        metadata.namespace = namespace;
        data = {
          "mimir.yaml" = ''
            multitenancy_enabled: false
            server:
              http_listen_port: 9009
            common:
              storage:
                backend: filesystem
                filesystem:
                  dir: /data
            blocks_storage:
              backend: filesystem
              filesystem:
                dir: /data/blocks
              tsdb:
                dir: /data/tsdb
            ruler_storage:
              backend: filesystem
              filesystem:
                dir: /data/rules
          '';
        };
      };
    };
  };

  # LGTM OTEL Collector - Ingestion Gateway
  applications.lgtm-otel-collector = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-55";
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

    resources = {
      deployments.otel-collector = {
        metadata = {
          inherit namespace;
          labels.app = "otel-collector";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "otel-collector";

          template = {
            metadata.labels.app = "otel-collector";

            spec = {
              containers = [{
                name = "otel-collector";
                image = "otel/opentelemetry-collector-contrib:0.115.0";
                args = [
                  "--config=/etc/otel-collector/config.yaml"
                ];
                ports = [
                  { containerPort = 4317; name = "otlp-grpc"; }
                  { containerPort = 4318; name = "otlp-http"; }
                  { containerPort = 8888; name = "metrics"; }
                ];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/etc/otel-collector";
                }];
              }];

              volumes = [{
                name = "config";
                configMap.name = "otel-collector-config";
              }];
            };
          };
        };
      };

      services.otel-collector = {
        metadata = {
          inherit namespace;
          labels.app = "otel-collector";
        };
        spec = {
          ports = [
            { name = "otlp-grpc"; port = 4317; targetPort = "otlp-grpc"; }
            { name = "otlp-http"; port = 4318; targetPort = "otlp-http"; }
          ];
          selector.app = "otel-collector";
        };
      };

      configMaps.otel-collector-config = {
        metadata.namespace = namespace;
        data = {
          "config.yaml" = ''
            receivers:
              otlp:
                protocols:
                  grpc:
                    endpoint: 0.0.0.0:4317
                  http:
                    endpoint: 0.0.0.0:4318

            processors:
              batch:
                timeout: 10s
                send_batch_size: 1000

            exporters:
              otlphttp/mimir:
                endpoint: http://mimir.observability.svc.cluster.local:9009/api/v1/otlp
              otlphttp/loki:
                endpoint: http://loki.observability.svc.cluster.local:3100/otlp
              otlphttp/tempo:
                endpoint: http://tempo.observability.svc.cluster.local:4318
              otlphttp/langfuse:
                endpoint: http://langfuse.observability.svc.cluster.local:3000/api/public/otel

            service:
              pipelines:
                metrics:
                  receivers: [otlp]
                  processors: [batch]
                  exporters: [otlphttp/mimir]
                logs:
                  receivers: [otlp]
                  processors: [batch]
                  exporters: [otlphttp/loki]
                traces:
                  receivers: [otlp]
                  processors: [batch]
                  exporters: [otlphttp/tempo, otlphttp/langfuse]
          '';
        };
      };
    };
  };
}
