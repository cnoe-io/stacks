# Keycloak Identity Provider
# Mirrors: cdk8s/charts/infra/keycloak-chart.ts
{ config, lib, ... }:
let
  namespace = "keycloak";
  appName = "keycloak";
  postgresAppName = "postgresql";

  # Environment-specific settings from cluster config
  ingressHost = config.cluster.ingressHost;
  ingressPort = config.cluster.ingressPort;
  isTalos = config.cluster.tls.enabled;

  # Default values
  keycloakImage = "quay.io/keycloak/keycloak:22.0.3";
  postgresImage = "docker.io/library/postgres:15.3-alpine3.18";
  postgresStorageSize = "500Mi";
  httpRelativePath = "/keycloak";

  # Build hostname admin URL
  hostnameAdmin = if ingressPort == 443 then ingressHost else "${ingressHost}:${toString ingressPort}";
in
{
  applications.keycloak = {
    inherit namespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;  # Note: 'enable' not 'enabled'
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
        serverSideApply = true;
      };
    };

    resources = {
      # Namespace
      namespaces.${namespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "identity";
          "app.kubernetes.io/part-of" = "infrastructure";
        };
      };

      # Keycloak Service
      services.${appName} = {
        metadata = {
          inherit namespace;
          labels.app = appName;
        };
        spec = {
          type = "ClusterIP";
          ports = [{
            name = "http";
            port = 8080;
            targetPort = 8080;
          }];
          selector.app = appName;
        };
      };

      # PostgreSQL Headless Service
      services.${postgresAppName} = {
        metadata = {
          inherit namespace;
          labels.app = postgresAppName;
        };
        spec = {
          clusterIP = "None";
          ports = [{
            name = "postgres";
            port = 5432;
          }];
          selector.app = postgresAppName;
        };
      };

      # Keycloak ConfigMap
      configMaps.keycloak-config = {
        metadata.namespace = namespace;
        data."keycloak.conf" = ''
          # Database
          # The database vendor.
          db=postgres

          # The username of the database user.
          db-url=jdbc:postgresql://postgresql.${namespace}.svc.cluster.local:5432/postgres

          # The proxy address forwarding mode if the server is behind a reverse proxy.
          proxy=edge

          # hostname configuration
          hostname=${ingressHost}
          hostname-port=${toString ingressPort}
          http-relative-path=${httpRelativePath}

          # the admin url requires its own configuration to reflect correct url
          hostname-admin=${hostnameAdmin}

          hostname-debug=true

          # this should only be allowed in development. NEVER in production.
          hostname-strict=false
          hostname-strict-backchannel=false
        '';
      };

      # PostgreSQL StatefulSet
      statefulSets.${postgresAppName} = {
        metadata = {
          inherit namespace;
          labels.app = postgresAppName;
          annotations."argocd.argoproj.io/sync-wave" = "0";
        };
        spec = {
          replicas = 1;
          serviceName = "service-${postgresAppName}";
          selector.matchLabels.app = postgresAppName;

          template = {
            metadata.labels.app = postgresAppName;

            spec.containers = [{
              name = "postgres";
              image = postgresImage;
              ports = [{
                containerPort = 5432;
                name = "postgresdb";
              }];
              envFrom = [{
                secretRef.name = "keycloak-config";
              }];
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "300Mi";
                };
                limits = {
                  memory = "500Mi";
                };
              };
              volumeMounts = [{
                name = "data";
                mountPath = "/var/lib/postgresql/data";
              }];
            }];
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = postgresStorageSize;
            };
          }];
        };
      };

      # Keycloak Deployment
      deployments.${appName} = {
        metadata = {
          inherit namespace;
          labels.app = appName;
          annotations."argocd.argoproj.io/sync-wave" = "10";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = appName;

          template = {
            metadata.labels.app = appName;

            spec = {
              initContainers = [{
                name = "realm-import-envsubst";
                image = "docker.io/library/alpine:3.19";
                command = [ "/bin/sh" "-c" ];
                args = [
                  ''
                    apk add --no-cache gettext && \
                    envsubst < /realm-template/cnoe-realm.json > /realm-import/cnoe-realm.json && \
                    echo "Realm import file processed successfully"
                  ''
                ];
                envFrom = [
                  { secretRef = { name = "keycloak-client-secrets"; optional = true; }; }
                  { secretRef.name = "keycloak-config"; }
                ];
                volumeMounts = [
                  { name = "realm-import-template"; mountPath = "/realm-template"; readOnly = true; }
                  { name = "realm-import"; mountPath = "/realm-import"; }
                ];
              }];

              containers = [{
                name = appName;
                image = keycloakImage;
                args = [ "start-dev" "--import-realm" ];
                env = [
                  { name = "KEYCLOAK_ADMIN"; value = "cnoe-admin"; }
                  { name = "KEYCLOAK_LOGLEVEL"; value = "ALL"; }
                  { name = "QUARKUS_TRANSACTION_MANAGER_ENABLE_RECOVERY"; value = "true"; }
                ];
                envFrom = [
                  { secretRef.name = "keycloak-config"; }
                  { secretRef = { name = "keycloak-client-secrets"; optional = true; }; }
                ];
                ports = [{
                  containerPort = 8080;
                  name = "http";
                }];
                readinessProbe = {
                  httpGet = {
                    path = "${httpRelativePath}/realms/master";
                    port = 8080;
                  };
                };
                volumeMounts = [
                  { name = "keycloak-config"; mountPath = "/opt/keycloak/conf"; readOnly = true; }
                  { name = "realm-import"; mountPath = "/opt/keycloak/data/import"; readOnly = true; }
                ];
              }];

              volumes = [
                { name = "keycloak-config"; configMap.name = "keycloak-config"; }
                { name = "realm-import-template"; configMap.name = "keycloak-realm-import"; }
                { name = "realm-import"; emptyDir = {}; }
              ];
            };
          };
        };
      };

      # Keycloak Ingress
      ingresses.keycloak-ingress = {
        metadata = {
          inherit namespace;
          annotations = {
            "argocd.argoproj.io/sync-wave" = "100";
          } // lib.optionalAttrs isTalos {
            "cert-manager.io/cluster-issuer" = config.cluster.tls.clusterIssuer;
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = ingressHost;
            http.paths = [{
              path = httpRelativePath;
              pathType = "ImplementationSpecific";
              backend.service = {
                name = appName;
                port.name = "http";
              };
            }];
          }];
        } // lib.optionalAttrs isTalos {
          tls = [{
            hosts = [ ingressHost ];
            secretName = "keycloak-tls";
          }];
        };
      };
    };
  };
}
