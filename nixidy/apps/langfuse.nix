# Langfuse - LLM Observability and Tracing
# Provides observability for LLM applications with tracing, metrics, and logging.
# Full Langfuse v3 with Web and Worker deployments.
#
# Dependencies in langfuse-deps.nix: PostgreSQL, ClickHouse, Redis, MinIO
# Secrets in observability.nix: langfuse-postgres-credentials, langfuse-auth, langfuse-api
#
# Mirrors: cdk8s/charts/infra/langfuse-chart.ts
{ config, lib, ... }:
let
  inherit (config.cluster) ingressHost name;
  namespace = "observability";  # Same namespace as deps
  portSuffix = ":8443";
  nextAuthUrl = "https://langfuse.${ingressHost}${portSuffix}";
in
{
  config = {
    # Langfuse Web + Worker Deployment
    applications.langfuse-app = {
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
        # Langfuse Web Deployment
        deployments.langfuse = {
          metadata = {
            inherit namespace;
            labels.app = "langfuse";
          };
          spec = {
            replicas = 1;
            selector.matchLabels.app = "langfuse";

            template = {
              metadata.labels.app = "langfuse";

              spec = {
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 1000;
                  runAsGroup = 1000;
                  fsGroup = 1000;
                };
                containers = [{
                  name = "langfuse";
                  image = "langfuse/langfuse:3";
                  ports = [{ containerPort = 3000; name = "http"; }];
                  env = [
                    # Bind to all interfaces (required for Next.js in K8s)
                    { name = "HOSTNAME"; value = "0.0.0.0"; }
                    # Database connection
                    {
                      name = "POSTGRES_USER";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-postgres-credentials";
                        key = "POSTGRES_USER";
                      };
                    }
                    {
                      name = "POSTGRES_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-postgres-credentials";
                        key = "POSTGRES_PASSWORD";
                      };
                    }
                    { name = "DATABASE_URL"; value = "postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@langfuse-postgres:5432/langfuse"; }
                    # ClickHouse connection (single-node, no Zookeeper)
                    { name = "CLICKHOUSE_USER"; value = "default"; }
                    { name = "CLICKHOUSE_PASSWORD"; value = "clickhouse_langfuse_password"; }
                    { name = "CLICKHOUSE_URL"; value = "http://default:clickhouse_langfuse_password@langfuse-clickhouse:8123"; }
                    { name = "CLICKHOUSE_MIGRATION_URL"; value = "clickhouse://default:clickhouse_langfuse_password@langfuse-clickhouse:9000"; }
                    { name = "CLICKHOUSE_CLUSTER_ENABLED"; value = "false"; }
                    # Redis connection
                    { name = "REDIS_HOST"; value = "langfuse-redis"; }
                    { name = "REDIS_PORT"; value = "6379"; }
                    # MinIO/S3 connection
                    { name = "LANGFUSE_S3_BUCKET_NAME"; value = "langfuse"; }
                    { name = "LANGFUSE_S3_ENDPOINT"; value = "http://langfuse-minio:9000"; }
                    { name = "LANGFUSE_S3_ACCESS_KEY_ID"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_SECRET_ACCESS_KEY"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_REGION"; value = "us-east-1"; }
                    { name = "LANGFUSE_S3_FORCE_PATH_STYLE"; value = "true"; }
                    { name = "AWS_ACCESS_KEY_ID"; value = "minioadmin"; }
                    { name = "AWS_SECRET_ACCESS_KEY"; value = "minioadmin"; }
                    { name = "AWS_REGION"; value = "us-east-1"; }
                    { name = "AWS_ENDPOINT_URL_S3"; value = "http://langfuse-minio:9000"; }
                    { name = "AWS_S3_FORCE_PATH_STYLE"; value = "true"; }
                    # S3 Event Upload (v3)
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET"; value = "langfuse"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_REGION"; value = "us-east-1"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT"; value = "http://langfuse-minio:9000"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE"; value = "true"; }
                    # NextAuth
                    { name = "NEXTAUTH_URL"; value = nextAuthUrl; }
                    {
                      name = "NEXTAUTH_SECRET";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-auth";
                        key = "NEXTAUTH_SECRET";
                      };
                    }
                    {
                      name = "SALT";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-auth";
                        key = "SALT";
                      };
                    }
                    {
                      name = "ENCRYPTION_KEY";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-auth";
                        key = "ENCRYPTION_KEY";
                      };
                    }
                    # Settings
                    { name = "TELEMETRY_ENABLED"; value = "false"; }
                    { name = "AUTH_DISABLE_SIGNUP"; value = "false"; }
                    { name = "LANGFUSE_ENABLE_OTEL_INGESTION"; value = "true"; }
                    # Headless initialization - auto-creates org, project, user, and API keys
                    {
                      name = "LANGFUSE_INIT_ORG_ID";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_ORG_ID";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_ORG_NAME";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_ORG_NAME";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_PROJECT_ID";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_PROJECT_ID";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_PROJECT_NAME";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_PROJECT_NAME";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_USER_EMAIL";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_USER_EMAIL";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_USER_NAME";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_USER_NAME";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_USER_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_USER_PASSWORD";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_PROJECT_PUBLIC_KEY";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_PROJECT_PUBLIC_KEY";
                        optional = true;
                      };
                    }
                    {
                      name = "LANGFUSE_INIT_PROJECT_SECRET_KEY";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-init";
                        key = "LANGFUSE_INIT_PROJECT_SECRET_KEY";
                        optional = true;
                      };
                    }
                  ];
                  resources = {
                    requests = { cpu = "500m"; memory = "1Gi"; };
                    limits = { cpu = "2000m"; memory = "3Gi"; };
                  };
                  readinessProbe = {
                    httpGet = { path = "/api/public/health"; port = 3000; };
                    initialDelaySeconds = 60;
                    periodSeconds = 10;
                  };
                  livenessProbe = {
                    httpGet = { path = "/api/public/health"; port = 3000; };
                    initialDelaySeconds = 90;
                    periodSeconds = 30;
                  };
                }];
              };
            };
          };
        };

        # Langfuse Worker Deployment (v3 requirement)
        deployments.langfuse-worker = {
          metadata = {
            inherit namespace;
            labels.app = "langfuse-worker";
          };
          spec = {
            replicas = 1;
            selector.matchLabels.app = "langfuse-worker";

            template = {
              metadata.labels.app = "langfuse-worker";

              spec = {
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 1000;
                  runAsGroup = 1000;
                  fsGroup = 1000;
                };
                containers = [{
                  name = "langfuse-worker";
                  image = "langfuse/langfuse-worker:3";
                  env = [
                    # Database connection
                    {
                      name = "POSTGRES_USER";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-postgres-credentials";
                        key = "POSTGRES_USER";
                      };
                    }
                    {
                      name = "POSTGRES_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-postgres-credentials";
                        key = "POSTGRES_PASSWORD";
                      };
                    }
                    { name = "DATABASE_URL"; value = "postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@langfuse-postgres:5432/langfuse"; }
                    # ClickHouse connection
                    { name = "CLICKHOUSE_USER"; value = "default"; }
                    { name = "CLICKHOUSE_PASSWORD"; value = "clickhouse_langfuse_password"; }
                    { name = "CLICKHOUSE_URL"; value = "http://default:clickhouse_langfuse_password@langfuse-clickhouse:8123"; }
                    { name = "CLICKHOUSE_MIGRATION_URL"; value = "clickhouse://default:clickhouse_langfuse_password@langfuse-clickhouse:9000"; }
                    { name = "CLICKHOUSE_CLUSTER_ENABLED"; value = "false"; }
                    # Redis connection
                    { name = "REDIS_HOST"; value = "langfuse-redis"; }
                    { name = "REDIS_PORT"; value = "6379"; }
                    # MinIO/S3 connection
                    { name = "LANGFUSE_S3_BUCKET_NAME"; value = "langfuse"; }
                    { name = "LANGFUSE_S3_ENDPOINT"; value = "http://langfuse-minio:9000"; }
                    { name = "LANGFUSE_S3_ACCESS_KEY_ID"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_SECRET_ACCESS_KEY"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_REGION"; value = "us-east-1"; }
                    { name = "LANGFUSE_S3_FORCE_PATH_STYLE"; value = "true"; }
                    { name = "AWS_ACCESS_KEY_ID"; value = "minioadmin"; }
                    { name = "AWS_SECRET_ACCESS_KEY"; value = "minioadmin"; }
                    { name = "AWS_REGION"; value = "us-east-1"; }
                    { name = "AWS_ENDPOINT_URL_S3"; value = "http://langfuse-minio:9000"; }
                    { name = "AWS_S3_FORCE_PATH_STYLE"; value = "true"; }
                    # S3 Event Upload (v3)
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET"; value = "langfuse"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_REGION"; value = "us-east-1"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY"; value = "minioadmin"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT"; value = "http://langfuse-minio:9000"; }
                    { name = "LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE"; value = "true"; }
                    # Auth secrets
                    {
                      name = "NEXTAUTH_SECRET";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-auth";
                        key = "NEXTAUTH_SECRET";
                      };
                    }
                    {
                      name = "SALT";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-auth";
                        key = "SALT";
                      };
                    }
                    {
                      name = "ENCRYPTION_KEY";
                      valueFrom.secretKeyRef = {
                        name = "langfuse-auth";
                        key = "ENCRYPTION_KEY";
                      };
                    }
                    # Settings
                    { name = "TELEMETRY_ENABLED"; value = "false"; }
                  ];
                  resources = {
                    requests = { cpu = "250m"; memory = "512Mi"; };
                    limits = { cpu = "1000m"; memory = "2Gi"; };
                  };
                }];
              };
            };
          };
        };

        # Langfuse Service
        services.langfuse = {
          metadata = {
            inherit namespace;
            labels.app = "langfuse";
          };
          spec = {
            ports = [{ name = "http"; port = 3000; targetPort = "http"; }];
            selector.app = "langfuse";
          };
        };

        # Langfuse Ingress
        ingresses.langfuse = {
          metadata = {
            inherit namespace;
            annotations = {
              "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
              "nginx.ingress.kubernetes.io/proxy-body-size" = "50m";
              "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300";
            };
          };
          spec = {
            ingressClassName = "nginx";
            rules = [{
              host = "langfuse.${ingressHost}";
              http.paths = [{
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "langfuse";
                  port.name = "http";
                };
              }];
            }];
            tls = [{
              hosts = [ "langfuse.${ingressHost}" ];
            }];
          };
        };
      };
    };
  };
}
