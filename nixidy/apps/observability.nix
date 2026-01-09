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
        apiVersion: external-secrets.io/v1
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
            - secretKey: POSTGRES_USER
              remoteRef:
                key: LANGFUSE-POSTGRES-USER
            - secretKey: POSTGRES_PASSWORD
              remoteRef:
                key: LANGFUSE-POSTGRES-PASSWORD
      ''
      ''
        apiVersion: external-secrets.io/v1
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
            - secretKey: ENCRYPTION_KEY
              remoteRef:
                key: LANGFUSE-ENCRYPTION-KEY
      ''
      # Langfuse API credentials for OTEL collector integration
      # Syncs from Azure Key Vault: LANGFUSE-API-AUTH
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: langfuse-api
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: langfuse-api
            creationPolicy: Owner
          data:
            - secretKey: LANGFUSE_AUTH
              remoteRef:
                key: LANGFUSE-API-AUTH
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

            spec = {
              containers = [{
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

              volumes = [{
                name = "data";
                emptyDir = {};
              }];
            };
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

      # Mimir Ingress - receives metrics from external sources (e.g., Grafana Alloy on NixOS hosts)
      ingresses.mimir = {
        metadata = {
          inherit namespace;
          annotations = {
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
            # Allow large payloads for batch metric ingestion
            "nginx.ingress.kubernetes.io/proxy-body-size" = "10m";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = "mimir.${ingressHost}";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "mimir";
                port.name = "http";
              };
            }];
          }];
          tls = [{
            hosts = [ "mimir.${ingressHost}" ];
          }];
        };
      };

      configMaps.mimir-config = {
        metadata.namespace = namespace;
        data = {
          "mimir.yaml" = ''
            multitenancy_enabled: false

            server:
              http_listen_port: 9009
              log_level: warn

            # Single-node ring configuration (required for monolithic mode)
            common:
              storage:
                backend: filesystem
                filesystem:
                  dir: /data

            ingester:
              ring:
                instance_addr: 127.0.0.1
                kvstore:
                  store: inmemory
                replication_factor: 1

            store_gateway:
              sharding_ring:
                instance_addr: 127.0.0.1
                kvstore:
                  store: inmemory
                replication_factor: 1

            compactor:
              sharding_ring:
                instance_addr: 127.0.0.1
                kvstore:
                  store: inmemory

            distributor:
              ring:
                instance_addr: 127.0.0.1
                kvstore:
                  store: inmemory

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

            ruler:
              ring:
                instance_addr: 127.0.0.1
                kvstore:
                  store: inmemory

            limits:
              # Disable rate limiting for single-node homelab use
              ingestion_rate: 100000
              ingestion_burst_size: 200000
              max_global_series_per_user: 0
              max_global_series_per_metric: 0
              max_label_names_per_series: 30
              max_label_value_length: 2048
          '';
        };
      };
    };
  };

  # LGTM Loki - Logs Backend
  applications.lgtm-loki = {
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
      persistentVolumeClaims.loki-data = {
        metadata = {
          inherit namespace;
          labels.app = "loki";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "20Gi";
        };
      };

      deployments.loki = {
        metadata = {
          inherit namespace;
          labels.app = "loki";
        };
        spec = {
          replicas = 1;
          strategy.type = "Recreate";  # Required for single-node with PVC
          selector.matchLabels.app = "loki";

          template = {
            metadata.labels.app = "loki";

            spec = {
              securityContext = {
                fsGroup = 10001;
                runAsUser = 10001;
                runAsNonRoot = true;
              };
              containers = [{
                name = "loki";
                image = "grafana/loki:3.3.0";
                args = [
                  "-config.file=/etc/loki/config.yaml"
                  "-target=all"
                ];
                ports = [
                  { containerPort = 3100; name = "http"; }
                  { containerPort = 9096; name = "grpc"; }
                ];
                volumeMounts = [
                  { name = "config"; mountPath = "/etc/loki"; }
                  { name = "data"; mountPath = "/data/loki"; }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/ready";
                    port = 3100;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/ready";
                    port = 3100;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                };
              }];

              volumes = [
                { name = "config"; configMap.name = "loki-config"; }
                { name = "data"; persistentVolumeClaim.claimName = "loki-data"; }
              ];
            };
          };
        };
      };

      services.loki = {
        metadata = {
          inherit namespace;
          labels.app = "loki";
        };
        spec = {
          ports = [
            { name = "http"; port = 3100; targetPort = "http"; }
            { name = "grpc"; port = 9096; targetPort = "grpc"; }
          ];
          selector.app = "loki";
        };
      };

      # Loki Ingress - receives logs from external sources (e.g., Grafana Alloy on NixOS hosts)
      ingresses.loki = {
        metadata = {
          inherit namespace;
          annotations = {
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
            # Allow large payloads for batch log ingestion
            "nginx.ingress.kubernetes.io/proxy-body-size" = "10m";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = "loki.${ingressHost}";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "loki";
                port.name = "http";
              };
            }];
          }];
          tls = [{
            hosts = [ "loki.${ingressHost}" ];
          }];
        };
      };

      configMaps.loki-config = {
        metadata.namespace = namespace;
        data = {
          "config.yaml" = ''
            auth_enabled: false
            server:
              http_listen_port: 3100
              grpc_listen_port: 9096
              log_level: warn
            common:
              path_prefix: /data/loki
              storage:
                filesystem:
                  chunks_directory: /data/loki/chunks
                  rules_directory: /data/loki/rules
              replication_factor: 1
              ring:
                instance_addr: 127.0.0.1
                kvstore:
                  store: inmemory
            schema_config:
              configs:
                - from: "2024-01-01"
                  store: tsdb
                  object_store: filesystem
                  schema: v13
                  index:
                    prefix: index_
                    period: 24h
            ingester:
              chunk_encoding: snappy
              wal:
                dir: /data/loki/wal
            querier:
              max_concurrent: 4
            limits_config:
              retention_period: 720h
              allow_structured_metadata: true
              volume_enabled: true
            compactor:
              working_directory: /data/loki/compactor
              retention_enabled: true
              delete_request_store: filesystem
          '';
        };
      };
    };
  };

  # LGTM Tempo - Traces Backend
  applications.lgtm-tempo = {
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
      persistentVolumeClaims.tempo-data = {
        metadata = {
          inherit namespace;
          labels.app = "tempo";
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "20Gi";
        };
      };

      deployments.tempo = {
        metadata = {
          inherit namespace;
          labels.app = "tempo";
        };
        spec = {
          replicas = 1;
          strategy.type = "Recreate";  # Required for single-node with PVC
          selector.matchLabels.app = "tempo";

          template = {
            metadata.labels.app = "tempo";

            spec = {
              securityContext = {
                fsGroup = 10001;
                runAsUser = 10001;
                runAsNonRoot = true;
              };
              containers = [{
                name = "tempo";
                image = "grafana/tempo:2.6.1";
                args = [
                  "-config.file=/etc/tempo/config.yaml"
                  "-target=all"
                ];
                ports = [
                  { containerPort = 3200; name = "http"; }
                  { containerPort = 4317; name = "otlp-grpc"; }
                  { containerPort = 4318; name = "otlp-http"; }
                  { containerPort = 9095; name = "grpc"; }
                ];
                volumeMounts = [
                  { name = "config"; mountPath = "/etc/tempo"; }
                  { name = "data"; mountPath = "/data/tempo"; }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "1Gi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/ready";
                    port = 3200;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/ready";
                    port = 3200;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                };
              }];

              volumes = [
                { name = "config"; configMap.name = "tempo-config"; }
                { name = "data"; persistentVolumeClaim.claimName = "tempo-data"; }
              ];
            };
          };
        };
      };

      services.tempo = {
        metadata = {
          inherit namespace;
          labels.app = "tempo";
        };
        spec = {
          ports = [
            { name = "http"; port = 3200; targetPort = "http"; }
            { name = "otlp-grpc"; port = 4317; targetPort = "otlp-grpc"; }
            { name = "otlp-http"; port = 4318; targetPort = "otlp-http"; }
            { name = "grpc"; port = 9095; targetPort = "grpc"; }
          ];
          selector.app = "tempo";
        };
      };

      configMaps.tempo-config = {
        metadata.namespace = namespace;
        data = {
          "config.yaml" = ''
            server:
              http_listen_port: 3200
              grpc_listen_port: 9095
              log_level: warn
            distributor:
              receivers:
                otlp:
                  protocols:
                    grpc:
                      endpoint: 0.0.0.0:4317
                    http:
                      endpoint: 0.0.0.0:4318
            ingester:
              trace_idle_period: 10s
              max_block_bytes: 1000000
              max_block_duration: 5m
            compactor:
              compaction:
                block_retention: 720h
            storage:
              trace:
                backend: local
                local:
                  path: /data/tempo/traces
                wal:
                  path: /data/tempo/wal
            querier:
              frontend_worker:
                frontend_address: 127.0.0.1:9095
            metrics_generator:
              registry:
                external_labels:
                  source: tempo
              storage:
                path: /data/tempo/generator/wal
                remote_write:
                  - url: http://mimir.observability.svc.cluster.local:9009/api/v1/push
                    send_exemplars: true
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
                image = "otel/opentelemetry-collector-contrib:0.114.0";
                command = [ "/otelcol-contrib" "--config=/conf/config.yaml" ];
                ports = [
                  { containerPort = 4317; name = "otlp-grpc"; }
                  { containerPort = 4318; name = "otlp-http"; }
                  { containerPort = 8888; name = "metrics"; }
                  { containerPort = 13133; name = "health"; }
                ];
                env = [
                  {
                    name = "LANGFUSE_AUTH";
                    valueFrom.secretKeyRef = {
                      name = "langfuse-api";
                      key = "LANGFUSE_AUTH";
                      optional = true;
                    };
                  }
                ];
                volumeMounts = [{
                  name = "config";
                  mountPath = "/conf";
                }];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                readinessProbe = {
                  httpGet = {
                    path = "/";
                    port = 13133;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 13133;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                };
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

      # OTEL Collector Ingress - receives traces/logs/metrics from external sources (e.g., NixOS hosts)
      ingresses.otel-collector = {
        metadata = {
          inherit namespace;
          annotations = {
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
            # Allow large payloads for batch telemetry
            "nginx.ingress.kubernetes.io/proxy-body-size" = "10m";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = "otel-collector.${ingressHost}";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "otel-collector";
                port.name = "otlp-http";
              };
            }];
          }];
          tls = [{
            hosts = [ "otel-collector.${ingressHost}" ];
          }];
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
              memory_limiter:
                check_interval: 1s
                limit_mib: 512
                spike_limit_mib: 128
              batch:
                timeout: 5s
                send_batch_size: 1000
                send_batch_max_size: 1500
              resource:
                attributes:
                  - key: service.instance.id
                    from_attribute: host.name
                    action: insert
                  - key: deployment.environment
                    value: homelab
                    action: insert

            exporters:
              prometheusremotewrite:
                endpoint: http://mimir.observability.svc.cluster.local:9009/api/v1/push
                resource_to_telemetry_conversion:
                  enabled: true
                external_labels:
                  cluster: homelab
                  source: otel-collector
              loki:
                endpoint: http://loki.observability.svc.cluster.local:3100/loki/api/v1/push
                default_labels_enabled:
                  exporter: false
                  job: true
                  instance: true
                  level: true
              otlp/tempo:
                endpoint: tempo.observability.svc.cluster.local:4317
                tls:
                  insecure: true
              otlphttp/langfuse:
                endpoint: http://langfuse.observability.svc.cluster.local:3000/api/public/otel
                headers:
                  Authorization: "''${env:LANGFUSE_AUTH}"

            extensions:
              health_check:
                endpoint: 0.0.0.0:13133
              pprof:
                endpoint: 0.0.0.0:1777
              zpages:
                endpoint: 0.0.0.0:55679

            service:
              extensions: [health_check, pprof, zpages]
              pipelines:
                metrics:
                  receivers: [otlp]
                  processors: [memory_limiter, batch, resource]
                  exporters: [prometheusremotewrite]
                logs:
                  receivers: [otlp]
                  processors: [memory_limiter, batch, resource]
                  exporters: [loki]
                traces:
                  receivers: [otlp]
                  processors: [memory_limiter, batch, resource]
                  exporters: [otlp/tempo, otlphttp/langfuse]
              telemetry:
                logs:
                  level: warn
                metrics:
                  address: 0.0.0.0:8888
                  level: basic
          '';
        };
      };
    };
  };
}
