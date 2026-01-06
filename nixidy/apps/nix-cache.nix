# Nix Binary Cache Applications
# MinIO and Attic for Nix binary cache
#
# Signing Key Persistence:
# - If ATTIC-SIGNING-PRIVATE-KEY exists in Azure Key Vault, uses persistent keypair
# - Otherwise falls back to generating a new keypair (requires sync-attic-pubkey.sh)
#
# To set up persistent signing keys:
#   ./deployment/scripts/persistent-secrets/setup-persistent-certs.sh
#
{ config, lib, ... }:
let
  namespace = "nix-cache";
  # Cluster name for Tailscale hostname
  inherit (config.cluster) name;
  clusterSuffix = if name != "" then "-${name}" else "";
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

  # Attic Signing Keypair from Azure Key Vault
  # This ExternalSecret fetches the persistent signing keypair for cache artifact signing
  # Sync wave -95 ensures it's ready before Attic StatefulSet at -90
  applications.attic-signing-keypair = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-95";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {};  # Required for nixidy to generate the app

    yamls = [
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: attic-signing-keypair
          namespace: ${namespace}
        spec:
          refreshInterval: 24h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: attic-signing-keypair
            creationPolicy: Orphan
          data:
            - secretKey: private-key
              remoteRef:
                key: ATTIC-SIGNING-PRIVATE-KEY
                decodingStrategy: Base64
            - secretKey: public-key
              remoteRef:
                key: ATTIC-SIGNING-PUBLIC-KEY
      ''
    ];
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
            # Allow any host for flexible access (port-forward, ingress, tailscale, etc.)
            # Note: Attic requires exact host:port match, wildcard doesn't work reliably
            # Tailscale Service URLs: attic-thinkpad, attic-ryzen, attic-hub
            allowed-hosts = [
              "localhost", "localhost:8080",
              "127.0.0.1", "127.0.0.1:8080",
              "attic.cnoe.localtest.me", "attic.cnoe.localtest.me:8443",
              "attic.nix-cache.svc.cluster.local", "attic.nix-cache.svc.cluster.local:8080",
              "attic-thinkpad.tail286401.ts.net", "attic-thinkpad.tail286401.ts.net:443",
              "attic-ryzen.tail286401.ts.net", "attic-ryzen.tail286401.ts.net:443",
              "attic-hub.tail286401.ts.net", "attic-hub.tail286401.ts.net:443",
              "attic.tail286401.ts.net", "attic.tail286401.ts.net:443"
            ]

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

            # JWT signing configuration (required for authentication)
            # Using HMAC secret for testing - use RSA keys in production
            [jwt.signing]
            token-hs256-secret-base64 = "dGVzdC1zZWNyZXQtZm9yLWF0dGljLWJpbmFyeS1jYWNoZS1zZXJ2ZXI="

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

      # Ingress for external access to Attic binary cache
      ingresses.attic = {
        metadata = {
          inherit namespace;
          labels.app = "attic";
          annotations = {
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
            # Large body size for NAR uploads
            "nginx.ingress.kubernetes.io/proxy-body-size" = "0";
            "nginx.ingress.kubernetes.io/proxy-read-timeout" = "600";
            "nginx.ingress.kubernetes.io/proxy-send-timeout" = "600";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = "attic.cnoe.localtest.me";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "attic";
                port.number = 8080;
              };
            }];
          }];
          tls = [{
            hosts = [ "attic.cnoe.localtest.me" ];
            secretName = "attic-tls";
          }];
        };
      };
    };

    # Using yamls for full control over StatefulSet spec (initContainers, command)
    yamls = [''
        apiVersion: apps/v1
        kind: StatefulSet
        metadata:
          name: attic
          namespace: ${namespace}
          labels:
            app: attic
        spec:
          replicas: 1
          serviceName: attic
          selector:
            matchLabels:
              app: attic
          template:
            metadata:
              labels:
                app: attic
            spec:
              initContainers:
                - name: init-minio-bucket
                  image: minio/mc:latest
                  command: ["/bin/sh", "-c"]
                  args:
                    - |
                      until mc alias set minio http://minio.nix-cache.svc.cluster.local:9000 admin minioadmin 2>/dev/null; do
                        echo "Waiting for MinIO..."; sleep 2
                      done
                      mc mb minio/attic-cache --ignore-existing
              containers:
                - name: attic
                  image: ghcr.io/zhaofengli/attic:latest
                  command: ["/bin/sh", "-c"]
                  args:
                    - |
                      atticd -f /etc/attic/server.toml &
                      PID=$!
                      sleep 5

                      # Create backstage cache via API using wget (curl not available in image)
                      TOKEN=$(atticadm -f /etc/attic/server.toml make-token --sub init --validity 1m --create-cache backstage 2>/dev/null)

                      # Check if persistent signing keypair is available from Azure Key Vault
                      # The ExternalSecret creates /etc/attic-keys/private-key if ATTIC-SIGNING-PRIVATE-KEY exists in AKV
                      if [ -f /etc/attic-keys/private-key ]; then
                        echo "Using persistent signing keypair from Azure Key Vault"
                        KEYPAIR=$(cat /etc/attic-keys/private-key)
                        # Escape the keypair for JSON (handle special chars)
                        KEYPAIR_ESCAPED=$(echo "$KEYPAIR" | sed 's/"/\\"/g')
                        PAYLOAD="{\"is_public\":true,\"keypair\":\"$KEYPAIR_ESCAPED\",\"store_dir\":\"/nix/store\",\"priority\":41,\"upstream_cache_key_names\":[\"cache.nixos.org-1\"]}"
                      else
                        echo "No persistent keypair found, generating new keypair"
                        PAYLOAD='{"is_public":true,"keypair":"Generate","store_dir":"/nix/store","priority":41,"upstream_cache_key_names":["cache.nixos.org-1"]}'
                      fi

                      wget -q -O- --header="Authorization: Bearer $TOKEN" --header="Content-Type: application/json" \
                        --post-data="$PAYLOAD" \
                        http://localhost:8080/_api/v1/cache-config/backstage 2>/dev/null \
                        && echo "Created backstage cache" \
                        || echo "Cache backstage may already exist"
                      wait $PID
                  ports:
                    - containerPort: 8080
                      name: http
                  volumeMounts:
                    - name: config
                      mountPath: /etc/attic
                    - name: data
                      mountPath: /var/lib/attic
                    - name: signing-keypair
                      mountPath: /etc/attic-keys
                      readOnly: true
                  resources:
                    requests:
                      cpu: 100m
                      memory: 512Mi
                    limits:
                      memory: 2Gi
              volumes:
                - name: config
                  secret:
                    secretName: attic-server-config
                - name: signing-keypair
                  secret:
                    secretName: attic-signing-keypair
                    optional: true
          volumeClaimTemplates:
            - metadata:
                name: data
              spec:
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: 1Gi
      ''];
    };
}
