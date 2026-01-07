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
  # =========================================================================
  # Backstage Namespace - Created early for dependent apps (secrets, dapr)
  # =========================================================================
  applications.backstage-namespace = {
    inherit namespace;
    createNamespace = true;

    annotations = {
      # Wave -40: Before backstage-secrets (-35) and backstage-dapr-components (15)
      "argocd.argoproj.io/sync-wave" = "-40";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
        serverSideApply = true;
      };
    };

    resources = {
      namespaces.${namespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "portal";
          "app.kubernetes.io/part-of" = "developer-platform";
        };
      };
    };
  };

  # =========================================================================
  # Backstage Application - Main deployment (managed by Kargo)
  # =========================================================================
  applications.backstage = {
    inherit namespace;
    createNamespace = false;  # Created by backstage-namespace at wave -40

    annotations = {
      "argocd.argoproj.io/sync-wave" = "100";
      # Allow Kargo Stage to manage this ArgoCD Application
      "kargo.akuity.io/authorized-stage" = "kargo-pipelines:backstage";
    };

    syncPolicy = {
      # Auto-sync disabled: Kargo/Gitea handles image promotion
      autoSync = {
        enable = false;
      };
      syncOptions = {
        createNamespace = false;  # Namespace already exists
        serverSideApply = true;
      };
    };

    # Allow DevSpace to scale down the deployment without ArgoCD reverting it
    ignoreDifferences = {
      ${appName} = {
        group = "apps";
        kind = "Deployment";
        name = appName;
        namespace = namespace;
        jsonPointers = [ "/spec/replicas" ];
      };
    };

    resources = {
      # NOTE: Namespace is created by backstage-namespace app at wave -40
      # This ensures namespace exists before backstage-secrets (-35) and backstage-dapr-components (15)

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
            metadata = {
              labels.app = appName;
              # Dapr sidecar annotations for configuration building block
              # See: https://docs.dapr.io/operations/resiliency/health-checks/sidecar-health/
              annotations = {
                "dapr.io/enabled" = "true";
                "dapr.io/app-id" = "backstage";
                "dapr.io/app-port" = "7007";
                "dapr.io/config" = "backstage-dapr-config";
                "dapr.io/log-as-json" = "true";
                "dapr.io/log-level" = "info";
                # Override sidecar securityContext to allow running with pod's runAsUser: 0
                # The daprd image defaults to runAsNonRoot: true which conflicts with backstage's root requirement
                "dapr.io/sidecar-securitycontext" = builtins.toJSON {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  runAsNonRoot = false;
                };
                # Dapr sidecar health probe configuration (best practices)
                # - Reasonable initial delay (30s) for container startup
                # - Faster period (10s) for quicker detection
                # - 3 failures before marking unhealthy
                "dapr.io/sidecar-liveness-probe-delay-seconds" = "30";
                "dapr.io/sidecar-liveness-probe-period-seconds" = "10";
                "dapr.io/sidecar-liveness-probe-threshold" = "3";
                "dapr.io/sidecar-readiness-probe-delay-seconds" = "5";
                "dapr.io/sidecar-readiness-probe-period-seconds" = "5";
                "dapr.io/sidecar-readiness-probe-threshold" = "3";
                # App health checks - Dapr monitors the app and stops routing traffic if unhealthy
                # See: https://docs.dapr.io/operations/resiliency/health-checks/app-health/
                "dapr.io/enable-app-health-check" = "true";
                "dapr.io/app-health-check-path" = "/.backstage/health/v1/readiness";
                "dapr.io/app-health-probe-interval" = "5";
                "dapr.io/app-health-probe-timeout" = "500";
                "dapr.io/app-health-threshold" = "3";
              };
            };

            spec = {
              serviceAccountName = appName;
              imagePullSecrets = [{ name = imagePullSecretName; }];
              # Explicit empty pod-level securityContext to allow Dapr sidecar with runAsNonRoot
              # The daprd container needs to run as non-root, so we can't have pod-level runAsUser: 0
              # Container-level securityContext handles backstage's root requirement
              securityContext = {};

              containers = [{
                name = appName;
                image = backstageImage;
                # Container-level securityContext for backstage (runs as root)
                securityContext = {
                  runAsUser = 0;
                  runAsGroup = 0;
                  allowPrivilegeEscalation = false;
                };
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
