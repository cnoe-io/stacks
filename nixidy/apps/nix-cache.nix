# Nix Binary Cache Applications
# MinIO and Attic for Nix binary cache
# Mirrors: cdk8s/charts/platform/minio-chart.ts, attic-chart.ts
{ config, lib, ... }:
let
  namespace = "nix-cache";
in
{
  # Nix Cache Namespace
  applications.nix-cache-namespace = {
    inherit namespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-110";
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
      namespaces.${namespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "infrastructure";
          "app.kubernetes.io/part-of" = "nix-cache";
        };
      };
    };
  };

  # MinIO Object Storage
  applications.minio = {
    inherit namespace;
    createNamespace = false;

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
      };
    };

    resources = {
      secrets.minio-credentials = {
        metadata.namespace = namespace;
        type = "Opaque";
        stringData = {
          root-user = "admin";
          root-password = "minioadmin";  # TODO: Use ExternalSecret in production
        };
      };

      statefulSets.minio = {
        metadata = {
          inherit namespace;
          labels.app = "minio";
        };
        spec = {
          replicas = 1;
          serviceName = "minio";
          selector.matchLabels.app = "minio";

          template = {
            metadata.labels.app = "minio";

            spec = {
              containers = [{
                name = "minio";
                image = "minio/minio:RELEASE.2024-11-07T00-52-20Z";
                args = [ "server" "/data" "--console-address" ":9001" ];
                ports = [
                  { containerPort = 9000; name = "api"; }
                  { containerPort = 9001; name = "console"; }
                ];
                env = [
                  {
                    name = "MINIO_ROOT_USER";
                    valueFrom.secretKeyRef = {
                      name = "minio-credentials";
                      key = "root-user";
                    };
                  }
                  {
                    name = "MINIO_ROOT_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "minio-credentials";
                      key = "root-password";
                    };
                  }
                ];
                resources = {
                  requests = {
                    cpu = "200m";
                    memory = "512Mi";
                  };
                  limits = {
                    memory = "1Gi";
                  };
                };
                volumeMounts = [{
                  name = "data";
                  mountPath = "/data";
                }];
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "100Gi";
            };
          }];
        };
      };

      services.minio = {
        metadata = {
          inherit namespace;
          labels.app = "minio";
        };
        spec = {
          ports = [
            { name = "api"; port = 9000; targetPort = "api"; }
            { name = "console"; port = 9001; targetPort = "console"; }
          ];
          selector.app = "minio";
        };
      };
    };
  };

  # Attic Nix Binary Cache Server
  applications.attic = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-90";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      secrets.attic-server-config = {
        metadata.namespace = namespace;
        type = "Opaque";
        stringData = {
          "server.toml" = ''
            listen = "[::]:8080"
            allowed-hosts = ["*"]
            api-endpoint = "https://attic.cnoe.localtest.me:8443/"

            [database]
            url = "sqlite:///var/lib/attic/server.db?mode=rwc"

            [storage]
            type = "s3"
            region = "us-east-1"
            bucket = "attic-cache"
            endpoint = "http://minio.nix-cache.svc.cluster.local:9000"

            [storage.credentials]
            access_key_id = "admin"
            secret_access_key = "minioadmin"

            [chunking]
            nar-size-threshold = 65536
            min-size = 16384
            avg-size = 65536
            max-size = 262144

            [compression]
            type = "zstd"
          '';
        };
      };

      deployments.attic = {
        metadata = {
          inherit namespace;
          labels.app = "attic";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "attic";

          template = {
            metadata.labels.app = "attic";

            spec = {
              containers = [{
                name = "attic";
                image = "ghcr.io/zhaofengli/attic:latest";
                args = [ "-f" "/etc/attic/server.toml" ];
                ports = [{
                  containerPort = 8080;
                  name = "http";
                }];
                volumeMounts = [
                  { name = "config"; mountPath = "/etc/attic"; }
                  { name = "data"; mountPath = "/var/lib/attic"; }
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
              }];

              volumes = [
                {
                  name = "config";
                  secret.secretName = "attic-server-config";
                }
                {
                  name = "data";
                  emptyDir = {};
                }
              ];
            };
          };
        };
      };

      services.attic = {
        metadata = {
          inherit namespace;
          labels.app = "attic";
        };
        spec = {
          ports = [{
            name = "http";
            port = 8080;
            targetPort = "http";
          }];
          selector.app = "attic";
        };
      };
    };
  };
}
