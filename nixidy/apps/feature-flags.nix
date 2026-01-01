# Feature Flags Applications
# Flipt management UI and Flagd sidecar
# Mirrors: cdk8s/charts/infra/flipt-chart.ts
# Uses domain-based routing for all services
{ config, lib, ... }:
let
  inherit (config.cluster) ingressHost ingressPort name;
  namespace = "feature-flags";
  clusterSuffix = if name != "" then "-${name}" else "";
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";
  fliptHost = "flipt.${ingressHost}";
  giteaInternalHost = "my-gitea-http.gitea.svc.cluster.local:3000";
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
        metadata = {
          namespace = namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
        data = {
          # Flipt v2 configuration
          # https://docs.flipt.io/configuration/overview
          "flipt.yml" = ''
            log:
              level: debug
              encoding: json

            server:
              protocol: http
              http_port: 8080
              grpc_port: 9000

            # Declarative Git storage (v2 format)
            # https://docs.flipt.io/configuration/storage
            storage:
              default:
                remote: "http://${giteaInternalHost}/giteaAdmin/feature-flags.git"
                ref: "main"
                poll_interval: "30s"
                insecure_skip_tls: true
                backend:
                  type: memory

            # Authentication configuration
            authentication:
              required: true
              session:
                domain: "${fliptHost}"
                secure: true
              methods:
                token:
                  enabled: false
                oidc:
                  enabled: true
                  cleanup:
                    interval: "10m"
                    grace_period: "30m"
                  providers:
                    keycloak:
                      # Domain-based routing for Keycloak
                      issuer_url: "https://keycloak.${ingressHost}${portSuffix}/realms/cnoe"
                      client_id: "flipt"
                      # client_secret provided via FLIPT_AUTHENTICATION_METHODS_OIDC_PROVIDERS_KEYCLOAK_CLIENT_SECRET env var
                      redirect_address: "https://${fliptHost}${portSuffix}"
                      scopes:
                        - openid
                        - profile
                        - email
                        - groups

            # Audit logging
            audit:
              sinks:
                log:
                  enabled: true

            # Telemetry
            telemetry:
              enabled: true
          '';
        };
      };

      # PVC for Flipt data (local cache)
      persistentVolumeClaims.flipt-data = {
        metadata = {
          namespace = namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
          };
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
        };
      };

      # Deployment (not StatefulSet) to match cdk8s
      deployments.flipt = {
        metadata = {
          inherit namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "flipt";

          template = {
            metadata.labels = {
              "app" = "flipt";
              "app.kubernetes.io/name" = "flipt";
              "app.kubernetes.io/component" = "management-ui";
              "app.kubernetes.io/part-of" = "feature-flags";
            };

            spec = {
              # Security context
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1000;
                runAsGroup = 1000;
                fsGroup = 1000;
              };

              containers = [{
                name = "flipt";
                image = "ghcr.io/flipt-io/flipt:v2.4.0";
                # Flipt v2 requires 'server' subcommand
                command = [ "/flipt" ];
                args = [ "server" "--config" "/etc/flipt/flipt.yml" ];
                ports = [
                  { containerPort = 8080; name = "http"; protocol = "TCP"; }
                  { containerPort = 9000; name = "grpc"; protocol = "TCP"; }
                ];
                # Mount secrets via envFrom
                envFrom = [
                  { secretRef.name = "flipt-oidc"; }
                  { secretRef.name = "flipt-git-credentials"; }
                ];
                env = [
                  { name = "FLIPT_LOG_LEVEL"; value = "debug"; }
                  # Use idpbuilder CA for TLS verification
                  { name = "GIT_SSL_CAINFO"; value = "/etc/ssl/certs/idpbuilder-ca.crt"; }
                  { name = "SSL_CERT_FILE"; value = "/etc/ssl/certs/idpbuilder-ca.crt"; }
                ];
                volumeMounts = [
                  { name = "config"; mountPath = "/etc/flipt"; readOnly = true; }
                  { name = "data"; mountPath = "/var/opt/flipt"; }
                  { name = "idpbuilder-ca"; mountPath = "/etc/ssl/certs/idpbuilder-ca.crt"; subPath = "ca.crt"; readOnly = true; }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "256Mi";
                  };
                };
                # Security context for container
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                # Health probes
                livenessProbe = {
                  httpGet = { path = "/health"; port = 8080; };
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = { path = "/health"; port = 8080; };
                  initialDelaySeconds = 5;
                  periodSeconds = 5;
                  failureThreshold = 3;
                };
              }];

              volumes = [
                { name = "config"; configMap.name = "flipt-config"; }
                { name = "data"; persistentVolumeClaim.claimName = "flipt-data"; }
                { name = "idpbuilder-ca"; secret.secretName = "idpbuilder-cert"; }
              ];
            };
          };
        };
      };

      services.flipt = {
        metadata = {
          inherit namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
        spec = {
          type = "ClusterIP";
          ports = [
            { name = "http"; port = 8080; targetPort = 8080; protocol = "TCP"; }
            { name = "grpc"; port = 9000; targetPort = 9000; protocol = "TCP"; }
          ];
          selector.app = "flipt";
        };
      };

      ingresses.flipt = {
        metadata = {
          inherit namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
          annotations = {
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = fliptHost;
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "flipt";
                port.number = 8080;
              };
            }];
          }];
          tls = [{
            hosts = [ fliptHost ];
          }];
        };
      };
    };
  };
}
