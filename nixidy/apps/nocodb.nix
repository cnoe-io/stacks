# NocoDB - Open Source Airtable Alternative
# No-code database platform with spreadsheet-like interface
# Includes dedicated PostgreSQL instance
#
# Dependencies: nocodb-secrets.nix (ExternalSecrets from Azure Key Vault)
# Access: https://nocodb.cnoe.localtest.me:8443
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost ingressPort;
  namespace = "nocodb";
  isKind = environmentType == "kind";
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";
  publicUrl = "https://nocodb.${ingressHost}${portSuffix}";
in
{
  config = lib.mkIf isKind {
    # PostgreSQL Database for NocoDB
    applications.nocodb-postgres = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-50";
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          serverSideApply = true;
          createNamespace = true;
        };
      };

      resources = {
        # PostgreSQL StatefulSet
        statefulSets.nocodb-postgres = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-postgres";
          };
          spec = {
            serviceName = "nocodb-postgres";
            replicas = 1;
            selector.matchLabels.app = "nocodb-postgres";

            template = {
              metadata.labels.app = "nocodb-postgres";

              spec = {
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 999;
                  runAsGroup = 999;
                  fsGroup = 999;
                };
                containers = [{
                  name = "postgres";
                  image = "postgres:15-alpine";
                  ports = [{ containerPort = 5432; name = "postgres"; }];
                  env = [
                    { name = "POSTGRES_DB"; value = "nocodb"; }
                    { name = "POSTGRES_USER"; value = "nocodb"; }
                    {
                      name = "POSTGRES_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "nocodb-credentials";
                        key = "POSTGRES_PASSWORD";
                      };
                    }
                    { name = "PGDATA"; value = "/var/lib/postgresql/data/pgdata"; }
                  ];
                  volumeMounts = [{
                    name = "data";
                    mountPath = "/var/lib/postgresql/data";
                  }];
                  resources = {
                    requests = { cpu = "100m"; memory = "256Mi"; };
                    limits = { cpu = "500m"; memory = "512Mi"; };
                  };
                  readinessProbe = {
                    exec.command = [ "pg_isready" "-U" "nocodb" "-d" "nocodb" ];
                    initialDelaySeconds = 10;
                    periodSeconds = 5;
                  };
                  livenessProbe = {
                    exec.command = [ "pg_isready" "-U" "nocodb" "-d" "nocodb" ];
                    initialDelaySeconds = 30;
                    periodSeconds = 10;
                  };
                }];
              };
            };

            volumeClaimTemplates = [{
              metadata.name = "data";
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources.requests.storage = "5Gi";
              };
            }];
          };
        };

        # PostgreSQL Service
        services.nocodb-postgres = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-postgres";
          };
          spec = {
            ports = [{ name = "postgres"; port = 5432; targetPort = "postgres"; }];
            selector.app = "nocodb-postgres";
            clusterIP = "None";  # Headless for StatefulSet
          };
        };
      };
    };

    # NocoDB Application
    applications.nocodb = {
      inherit namespace;
      createNamespace = false;  # Created by nocodb-postgres

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
          serverSideApply = true;
        };
      };

      resources = {
        # NocoDB Deployment
        deployments.nocodb = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb";
          };
          spec = {
            replicas = 1;
            selector.matchLabels.app = "nocodb";

            template = {
              metadata.labels.app = "nocodb";

              spec = {
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 1000;
                  runAsGroup = 1000;
                  fsGroup = 1000;
                };
                containers = [{
                  name = "nocodb";
                  image = "nocodb/nocodb:latest";
                  ports = [{ containerPort = 8080; name = "http"; }];
                  env = [
                    # Database connection - NocoDB expects NC_DB format
                    {
                      name = "POSTGRES_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "nocodb-credentials";
                        key = "POSTGRES_PASSWORD";
                      };
                    }
                    { name = "NC_DB"; value = "pg://nocodb-postgres:5432?u=nocodb&p=$(POSTGRES_PASSWORD)&d=nocodb"; }
                    # JWT Secret for authentication
                    {
                      name = "NC_AUTH_JWT_SECRET";
                      valueFrom.secretKeyRef = {
                        name = "nocodb-credentials";
                        key = "NC_AUTH_JWT_SECRET";
                      };
                    }
                    # Public URL
                    { name = "NC_PUBLIC_URL"; value = publicUrl; }
                    # Disable telemetry
                    { name = "NC_DISABLE_TELE"; value = "true"; }
                  ];
                  resources = {
                    requests = { cpu = "500m"; memory = "512Mi"; };
                    limits = { cpu = "1000m"; memory = "1Gi"; };
                  };
                  readinessProbe = {
                    httpGet = { path = "/api/v1/health"; port = 8080; };
                    initialDelaySeconds = 30;
                    periodSeconds = 10;
                  };
                  livenessProbe = {
                    httpGet = { path = "/api/v1/health"; port = 8080; };
                    initialDelaySeconds = 60;
                    periodSeconds = 30;
                  };
                }];
              };
            };
          };
        };

        # NocoDB Service
        services.nocodb = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb";
          };
          spec = {
            ports = [{ name = "http"; port = 8080; targetPort = "http"; }];
            selector.app = "nocodb";
          };
        };

        # NocoDB Ingress
        ingresses.nocodb = {
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
              host = "nocodb.${ingressHost}";
              http.paths = [{
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "nocodb";
                  port.name = "http";
                };
              }];
            }];
            tls = [{
              hosts = [ "nocodb.${ingressHost}" ];
            }];
          };
        };
      };
    };
  };
}
