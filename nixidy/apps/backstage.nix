# Backstage Developer Portal
# Mirrors: cdk8s/charts/apps/backstage-chart.ts
{ config, lib, ... }:
let
  namespace = "backstage";
  appName = "backstage";
  postgresAppName = "postgresql";

  # Environment-specific settings from cluster config
  ingressHost = config.cluster.ingressHost;
  isTalos = config.cluster.tls.enabled;

  # Subdomain-based routing: backstage.cnoe.localtest.me
  backstageHost = "backstage.${ingressHost}";

  # Default values
  backstageImage = "ghcr.io/pittampalliorg/backstage:v1.1.2";
  imagePullSecretName = "ghcr-dockercfg";
  postgresImage = "docker.io/library/postgres:15.3-alpine3.18";
  postgresStorageSize = "500Mi";
in
{
  applications.backstage = {
    inherit namespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "100";
      # Allow Kargo Stage to manage this ArgoCD Application
      "kargo.akuity.io/authorized-stage" = "kargo-pipelines:backstage";
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
          "app.kubernetes.io/component" = "portal";
          "app.kubernetes.io/part-of" = "developer-platform";
        };
      };

      # ServiceAccount
      serviceAccounts.${appName} = {
        metadata.namespace = namespace;
      };

      # ClusterRole for Argo Workflows
      clusterRoles."${namespace}-argo-worfklows" = {
        rules = [{
          apiGroups = [ "argoproj.io" ];
          resources = [ "workflows" ];
          verbs = [ "create" ];
        }];
      };

      # ClusterRole for read-all
      clusterRoles."${namespace}-read-all" = {
        rules = [{
          apiGroups = [ "*" ];
          resources = [ "*" ];
          verbs = [ "get" "list" "watch" ];
        }];
      };

      # ClusterRoleBindings
      clusterRoleBindings."${namespace}-argo-worfklows" = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "${namespace}-argo-worfklows";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = appName;
          inherit namespace;
        }];
      };

      clusterRoleBindings."${namespace}-read-all" = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "${namespace}-read-all";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = appName;
          inherit namespace;
        }];
      };

      # Backstage Service
      services.${appName} = {
        metadata.namespace = namespace;
        spec = {
          ports = [{
            name = "http";
            port = 7007;
            targetPort = "http";
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

      # PostgreSQL StatefulSet
      statefulSets.${postgresAppName} = {
        metadata = {
          inherit namespace;
          labels.app = postgresAppName;
          annotations."argocd.argoproj.io/sync-wave" = "10";
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
              env = [
                {
                  name = "POSTGRES_DB";
                  valueFrom.secretKeyRef = {
                    name = "backstage-env-vars";
                    key = "POSTGRES_DB";
                  };
                }
                {
                  name = "POSTGRES_USER";
                  valueFrom.secretKeyRef = {
                    name = "backstage-env-vars";
                    key = "POSTGRES_USER";
                  };
                }
                {
                  name = "POSTGRES_PASSWORD";
                  valueFrom.secretKeyRef = {
                    name = "backstage-env-vars";
                    key = "POSTGRES_PASSWORD";
                  };
                }
              ];
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

      # Backstage Deployment
      deployments.${appName} = {
        metadata = {
          inherit namespace;
          annotations."argocd.argoproj.io/sync-wave" = "20";
        };
        spec = {
          replicas = 1;
          strategy.type = "Recreate";
          selector.matchLabels.app = appName;

          template = {
            metadata.labels.app = appName;

            spec = {
              serviceAccountName = appName;
              imagePullSecrets = [{ name = imagePullSecretName; }];
              securityContext = {
                runAsUser = 0;
                runAsGroup = 0;
                fsGroup = 0;
              };

              containers = [{
                name = appName;
                image = backstageImage;
                ports = [{
                  containerPort = 7007;
                  name = "http";
                }];
                # Load config files in order (last wins for overlapping keys)
                # Order: base config → production config → Kubernetes environment config
                args = [
                  "node"
                  "packages/backend"
                  "--config"
                  "/app/app-config.yaml"
                  "--config"
                  "/app/app-config.production.yaml"
                  "--config"
                  "/etc/backstage/app-config.yaml"
                ];
                env = [
                  { name = "LOG_LEVEL"; value = "debug"; }
                  { name = "NODE_TLS_REJECT_UNAUTHORIZED"; value = "0"; }
                  { name = "NODE_ENV"; value = "production"; }
                ];
                envFrom = [
                  { secretRef.name = "backstage-env-vars"; }
                  { secretRef.name = "gitea-credentials"; }
                  { secretRef.name = "argocd-credentials"; }
                ];
                volumeMounts = [{
                  name = "app-config";
                  mountPath = "/etc/backstage/app-config.yaml";
                  subPath = "app-config.yaml";
                  readOnly = true;
                }];
              }];

              volumes = [{
                name = "app-config";
                configMap.name = "backstage-app-config";
              }];
            };
          };
        };
      };

      # Backstage Ingress - subdomain-based routing
      ingresses.${appName} = {
        metadata = {
          inherit namespace;
          annotations = lib.optionalAttrs isTalos {
            "cert-manager.io/cluster-issuer" = config.cluster.tls.clusterIssuer;
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = backstageHost;
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = appName;
                port.name = "http";
              };
            }];
          }];
        } // lib.optionalAttrs isTalos {
          tls = [{
            hosts = [ backstageHost ];
            secretName = "${appName}-tls";
          }];
        };
      };
    };
  };
}
