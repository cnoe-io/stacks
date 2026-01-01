# Feature Flags Applications
# Flipt management UI and Flagd sidecar
# Mirrors: cdk8s/charts/apps/feature-flags-*.ts
{ config, lib, ... }:
let
  inherit (config.cluster) ingressHost name;
  namespace = "feature-flags";
  clusterSuffix = if name != "" then "-${name}" else "";
in
{
  # Feature Flags Namespace
  applications.feature-flags-namespace = {
    inherit namespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-80";
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
          "app.kubernetes.io/component" = "feature-flags";
          "app.kubernetes.io/part-of" = "platform";
        };
      };
    };
  };

  # Feature Flags Secrets
  applications.feature-flags-secrets = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-78";
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
      # flipt-oidc - uses keycloak ClusterSecretStore for OIDC client secret
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: flipt-oidc
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: flipt
            app.kubernetes.io/component: secrets
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: 1m
          secretStoreRef:
            kind: ClusterSecretStore
            name: keycloak
          target:
            name: flipt-oidc
            creationPolicy: Owner
            template:
              type: Opaque
              data:
                FLIPT_AUTHENTICATION_METHODS_OIDC_PROVIDERS_KEYCLOAK_CLIENT_SECRET: "{{ .FLIPT_CLIENT_SECRET }}"
          data:
            - secretKey: FLIPT_CLIENT_SECRET
              remoteRef:
                key: keycloak-clients
                property: FLIPT_CLIENT_SECRET
      ''
      # flipt-git-credentials - uses gitea ClusterSecretStore for Git access
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: flipt-git-credentials
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: flipt
            app.kubernetes.io/component: secrets
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: gitea
          target:
            name: flipt-git-credentials
            creationPolicy: Owner
            template:
              type: Opaque
              data:
                FLIPT_STORAGE_GIT_AUTHENTICATION_BASIC_USERNAME: "{{ .username }}"
                FLIPT_STORAGE_GIT_AUTHENTICATION_BASIC_PASSWORD: "{{ .password }}"
          data:
            - secretKey: username
              remoteRef:
                key: gitea-credential
                property: username
            - secretKey: password
              remoteRef:
                key: gitea-credential
                property: password
      ''
      # flipt-db-credentials - uses Azure Key Vault for stable secrets
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: flipt-db-credentials
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: flipt
            app.kubernetes.io/component: secrets
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: flipt-db-credentials
            creationPolicy: Owner
            template:
              type: Opaque
          data:
            - secretKey: FLIPT_DB_URL
              remoteRef:
                key: FLIPT-DB-URL
      ''
      # idpbuilder-cert - copy CA cert from default namespace
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: idpbuilder-cert
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: idpbuilder
            app.kubernetes.io/component: ca-cert
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: 24h
          secretStoreRef:
            kind: ClusterSecretStore
            name: default-namespace
          target:
            name: idpbuilder-cert
            creationPolicy: Owner
            template:
              type: Opaque
          data:
            - secretKey: ca.crt
              remoteRef:
                key: idpbuilder-cert
                property: ca.crt
      ''
    ];
  };

  # Flagd - OpenFeature-compliant flag evaluation sidecar
  applications.flagd = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-76";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      deployments.flagd = {
        metadata = {
          inherit namespace;
          labels.app = "flagd";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "flagd";

          template = {
            metadata.labels.app = "flagd";

            spec = {
              containers = [{
                name = "flagd";
                image = "ghcr.io/open-feature/flagd:v0.11.0";
                args = [
                  "start"
                  "--uri"
                  "http://flipt.${namespace}.svc.cluster.local:8080/internal/v1/evaluation/snapshot/namespace/default"
                ];
                ports = [
                  { containerPort = 8013; name = "grpc"; }
                  { containerPort = 8014; name = "http"; }
                ];
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
      };

      services.flagd = {
        metadata = {
          inherit namespace;
          labels.app = "flagd";
        };
        spec = {
          ports = [
            { name = "grpc"; port = 8013; targetPort = "grpc"; }
            { name = "http"; port = 8014; targetPort = "http"; }
          ];
          selector.app = "flagd";
        };
      };
    };
  };

  # Flipt - Feature Flag Management UI
  applications.flipt = {
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
    };

    resources = {
      configMaps.flipt-config = {
        metadata.namespace = namespace;
        data = {
          "default.yml" = ''
            server:
              protocol: http
              host: 0.0.0.0
              http_port: 8080
              grpc_port: 9000

            log:
              level: info

            db:
              url: file:/var/lib/flipt/flipt.db

            authentication:
              required: false
              methods:
                token:
                  enabled: true
                  cleanup:
                    interval: 1h
          '';
        };
      };

      statefulSets.flipt = {
        metadata = {
          inherit namespace;
          labels.app = "flipt";
        };
        spec = {
          replicas = 1;
          serviceName = "flipt";
          selector.matchLabels.app = "flipt";

          template = {
            metadata.labels.app = "flipt";

            spec = {
              containers = [{
                name = "flipt";
                image = "flipt/flipt:v1.52.0";
                ports = [
                  { containerPort = 8080; name = "http"; }
                  { containerPort = 9000; name = "grpc"; }
                ];
                env = [
                  { name = "FLIPT_CONFIG_PATH"; value = "/etc/flipt/config"; }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    memory = "256Mi";
                  };
                };
                volumeMounts = [
                  { name = "config"; mountPath = "/etc/flipt/config"; }
                  { name = "data"; mountPath = "/var/lib/flipt"; }
                ];
              }];

              volumes = [{
                name = "config";
                configMap.name = "flipt-config";
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "1Gi";
            };
          }];
        };
      };

      services.flipt = {
        metadata = {
          inherit namespace;
          labels.app = "flipt";
        };
        spec = {
          ports = [
            { name = "http"; port = 8080; targetPort = "http"; }
            { name = "grpc"; port = 9000; targetPort = "grpc"; }
          ];
          selector.app = "flipt";
        };
      };

      ingresses.flipt = {
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
              path = "/flipt(/|$)(.*)";
              pathType = "ImplementationSpecific";
              backend.service = {
                name = "flipt";
                port.name = "http";
              };
            }];
          }];
        };
      };
    };
  };
}
