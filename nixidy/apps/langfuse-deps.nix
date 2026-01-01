# Langfuse Dependency Applications
# PostgreSQL, ClickHouse, Redis, MinIO for Langfuse
# Mirrors: cdk8s/charts/infra/langfuse-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  namespace = "observability";
in
{
  # Langfuse PostgreSQL
  applications.langfuse-postgres = {
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
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      statefulSets.langfuse-postgres = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-postgres";
        };
        spec = {
          replicas = 1;
          serviceName = "langfuse-postgres";
          selector.matchLabels.app = "langfuse-postgres";

          template = {
            metadata.labels.app = "langfuse-postgres";

            spec = {
              containers = [{
                name = "postgres";
                image = "postgres:15-alpine";
                ports = [{ containerPort = 5432; name = "postgres"; }];
                env = [
                  { name = "POSTGRES_DB"; value = "langfuse"; }
                  { name = "POSTGRES_USER"; value = "langfuse"; }
                  { name = "POSTGRES_PASSWORD"; valueFrom.secretKeyRef = { name = "langfuse-postgres-credentials"; key = "POSTGRES_PASSWORD"; }; }
                  { name = "PGDATA"; value = "/var/lib/postgresql/data/pgdata"; }
                ];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/var/lib/postgresql/data";
                }];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    memory = "512Mi";
                  };
                };
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "10Gi";
            };
          }];
        };
      };

      services.langfuse-postgres = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-postgres";
        };
        spec = {
          ports = [{ name = "postgres"; port = 5432; targetPort = "postgres"; }];
          selector.app = "langfuse-postgres";
        };
      };
    };
  };

  # Langfuse ClickHouse
  applications.langfuse-clickhouse = {
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
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      statefulSets.langfuse-clickhouse = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-clickhouse";
        };
        spec = {
          replicas = 1;
          serviceName = "langfuse-clickhouse";
          selector.matchLabels.app = "langfuse-clickhouse";

          template = {
            metadata.labels.app = "langfuse-clickhouse";

            spec = {
              containers = [{
                name = "clickhouse";
                image = "clickhouse/clickhouse-server:24.1-alpine";
                ports = [
                  { containerPort = 8123; name = "http"; }
                  { containerPort = 9000; name = "native"; }
                ];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/var/lib/clickhouse";
                }];
                resources = {
                  requests = {
                    cpu = "200m";
                    memory = "512Mi";
                  };
                  limits = {
                    memory = "1Gi";
                  };
                };
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "20Gi";
            };
          }];
        };
      };

      services.langfuse-clickhouse = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-clickhouse";
        };
        spec = {
          ports = [
            { name = "http"; port = 8123; targetPort = "http"; }
            { name = "native"; port = 9000; targetPort = "native"; }
          ];
          selector.app = "langfuse-clickhouse";
        };
      };
    };
  };

  # Langfuse Redis
  applications.langfuse-redis = {
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
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      deployments.langfuse-redis = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-redis";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "langfuse-redis";

          template = {
            metadata.labels.app = "langfuse-redis";

            spec.containers = [{
              name = "redis";
              image = "redis:7-alpine";
              ports = [{ containerPort = 6379; name = "redis"; }];
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  memory = "128Mi";
                };
              };
            }];
          };
        };
      };

      services.langfuse-redis = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-redis";
        };
        spec = {
          ports = [{ name = "redis"; port = 6379; targetPort = "redis"; }];
          selector.app = "langfuse-redis";
        };
      };
    };
  };

  # Langfuse MinIO (S3-compatible object storage)
  applications.langfuse-minio = {
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
      syncOptions = {
        serverSideApply = true;
      };
    };

    resources = {
      statefulSets.langfuse-minio = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-minio";
        };
        spec = {
          replicas = 1;
          serviceName = "langfuse-minio";
          selector.matchLabels.app = "langfuse-minio";

          template = {
            metadata.labels.app = "langfuse-minio";

            spec = {
              containers = [{
                name = "minio";
                image = "minio/minio:RELEASE.2024-01-01T16-36-33Z";
                command = ["minio" "server" "/data" "--console-address" ":9001"];
                ports = [
                  { containerPort = 9000; name = "api"; }
                  { containerPort = 9001; name = "console"; }
                ];
                env = [
                  { name = "MINIO_ROOT_USER"; value = "minioadmin"; }
                  { name = "MINIO_ROOT_PASSWORD"; value = "minioadmin"; }
                ];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/data";
                }];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    memory = "512Mi";
                  };
                };
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "10Gi";
            };
          }];
        };
      };

      services.langfuse-minio = {
        metadata = {
          inherit namespace;
          labels.app = "langfuse-minio";
        };
        spec = {
          ports = [
            { name = "api"; port = 9000; targetPort = "api"; }
            { name = "console"; port = 9001; targetPort = "console"; }
          ];
          selector.app = "langfuse-minio";
        };
      };
    };
  };

  # LGTM Pyroscope (continuous profiling)
  applications.lgtm-pyroscope = {
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
      statefulSets.pyroscope = {
        metadata = {
          inherit namespace;
          labels.app = "pyroscope";
        };
        spec = {
          replicas = 1;
          serviceName = "pyroscope";
          selector.matchLabels.app = "pyroscope";

          template = {
            metadata.labels.app = "pyroscope";

            spec = {
              containers = [{
                name = "pyroscope";
                image = "grafana/pyroscope:1.4.0";
                ports = [{ containerPort = 4040; name = "http"; }];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/data";
                }];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    memory = "512Mi";
                  };
                };
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "10Gi";
            };
          }];
        };
      };

      services.pyroscope = {
        metadata = {
          inherit namespace;
          labels.app = "pyroscope";
        };
        spec = {
          ports = [{ name = "http"; port = 4040; targetPort = "http"; }];
          selector.app = "pyroscope";
        };
      };
    };
  };

  # LGTM Grafana - Placeholder
  # NOTE: Actual Grafana deployment is via nixhelm in grafana.nix
  # This placeholder exists for ArgoCD Application tracking only.
  # See cdk8s/charts/infra/lgtm-grafana-chart.ts for reference implementation.
  applications.lgtm-grafana = {
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
      configMaps.lgtm-grafana-placeholder = {
        metadata = {
          namespace = namespace;
          labels = {
            "app.kubernetes.io/name" = "lgtm-grafana";
            "app.kubernetes.io/part-of" = "observability";
          };
        };
        data = {
          status = "placeholder";
          note = "Grafana deployed via nixhelm in grafana.nix. See cdk8s/charts/infra/lgtm-grafana-chart.ts for dashboard configuration.";
        };
      };
    };
  };
}
