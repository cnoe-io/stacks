# Headlamp Kubernetes Dashboard
# Mirrors: cdk8s/charts/apps/headlamp-chart.ts
{ config, lib, ... }:
let
  inherit (config.cluster) ingressHost;
  namespace = "headlamp";
  appName = "headlamp";
in
{
  # Headlamp Keycloak Secrets
  applications.headlamp-keycloak-secrets = {
    inherit namespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "45";
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
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: headlamp-oidc-credentials
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: headlamp-oidc-credentials
            creationPolicy: Owner
          data:
            - secretKey: clientId
              remoteRef:
                key: HEADLAMP-CLIENT-ID
            - secretKey: clientSecret
              remoteRef:
                key: HEADLAMP-CLIENT-SECRET
      ''
    ];
  };

  # Headlamp Dashboard
  applications.headlamp = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "60";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = false;
        serverSideApply = true;
      };
    };

    resources = {
      # ServiceAccount
      serviceAccounts.${appName} = {
        metadata.namespace = namespace;
      };

      # ClusterRoleBinding for admin access
      clusterRoleBindings."${appName}-admin" = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "cluster-admin";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = appName;
          inherit namespace;
        }];
      };

      # Headlamp Service
      services.${appName} = {
        metadata.namespace = namespace;
        spec = {
          ports = [{
            name = "http";
            port = 80;
            targetPort = "http";
          }];
          selector.app = appName;
        };
      };

      # Headlamp Deployment
      deployments.${appName} = {
        metadata = {
          inherit namespace;
          labels.app = appName;
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = appName;

          template = {
            metadata.labels.app = appName;

            spec = {
              serviceAccountName = appName;
              containers = [{
                name = appName;
                image = "ghcr.io/headlamp-k8s/headlamp:v0.25.0";
                ports = [{
                  containerPort = 4466;
                  name = "http";
                }];
                args = [
                  "-in-cluster"
                  "-plugins-dir=/headlamp/plugins"
                ];
                env = [
                  { name = "HEADLAMP_CONFIG_OIDC_CLIENT_ID"; valueFrom.secretKeyRef = { name = "headlamp-oidc-credentials"; key = "clientId"; }; }
                  { name = "HEADLAMP_CONFIG_OIDC_CLIENT_SECRET"; valueFrom.secretKeyRef = { name = "headlamp-oidc-credentials"; key = "clientSecret"; }; }
                  { name = "HEADLAMP_CONFIG_OIDC_IDP_ISSUER_URL"; value = "https://${ingressHost}/keycloak/realms/cnoe"; }
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
                volumeMounts = [{
                  name = "plugins";
                  mountPath = "/headlamp/plugins";
                }];
              }];

              initContainers = [{
                name = "download-plugins";
                image = "curlimages/curl:8.5.0";
                command = [ "sh" "-c" ];
                args = [
                  "curl -L https://github.com/magohl/external-secrets-operator-headlamp-plugin/releases/download/0.1.0-beta7/external-secrets-operator-headlamp-plugin-0.1.0-beta7.tar.gz | tar -xz -C /headlamp/plugins"
                ];
                volumeMounts = [{
                  name = "plugins";
                  mountPath = "/headlamp/plugins";
                }];
              }];

              volumes = [{
                name = "plugins";
                emptyDir = {};
              }];
            };
          };
        };
      };

      # Headlamp Ingress
      ingresses.${appName} = {
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
              path = "/headlamp(/|$)(.*)";
              pathType = "ImplementationSpecific";
              backend.service = {
                name = appName;
                port.name = "http";
              };
            }];
          }];
        };
      };
    };
  };
}
