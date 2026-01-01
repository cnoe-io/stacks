# Tailscale Applications
# CRDs, secrets, subnet router, and Tailscale Serve services
# Mirrors: cdk8s/charts/platform/tailscale-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) name;
  isTalos = environmentType == "talos";
  clusterSuffix = if name != "" then "-${name}" else "";
  tailnet = "tail286401";
in
{
  # Tailscale CRDs - placeholder for Helm-based deployment
  # NOTE: Use ArgoCD Application with Helm source for production
  applications.tailscale-crds = {
    namespace = "tailscale";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-120";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = false;  # Never auto-delete CRDs
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
        serverSideApply = true;
      };
    };

    # CRDs deployed via ArgoCD Helm source, not inline
    yamls = [
      ''
        # Tailscale CRDs - Deployed via ArgoCD Application with Helm source
        # Chart: tailscale-operator from https://pkgs.tailscale.com/helmcharts
        # Version: 1.82.0
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: tailscale-crds-placeholder
          namespace: tailscale
        data:
          note: "CRDs deployed via Helm chart in ArgoCD"
      ''
    ];
  };

  # Tailscale RBAC - Required for pods to manage state secrets
  applications.tailscale-rbac = {
    namespace = "tailscale";
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
      roles.tailscale-state = {
        metadata.namespace = "tailscale";
        rules = [
          {
            apiGroups = [""];
            resources = ["secrets"];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
          {
            apiGroups = [""];
            resources = ["events"];
            verbs = ["get" "create" "patch"];
          }
        ];
      };

      roleBindings.tailscale-state = {
        metadata.namespace = "tailscale";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "tailscale-state";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "default";
            namespace = "tailscale";
          }
          {
            kind = "ServiceAccount";
            name = "tailscale-subnet-router";
            namespace = "tailscale";
          }
        ];
      };
    };
  };

  # Tailscale Secrets - Auth key from Azure Key Vault
  applications.tailscale-secrets = {
    namespace = "tailscale";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-70";
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
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: tailscale-auth-key
          namespace: tailscale
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: tailscale-auth-key
            creationPolicy: Owner
          data:
            - secretKey: authKey
              remoteRef:
                key: TAILSCALE-AUTH-KEY
      ''
    ];
  };

  # Tailscale Subnet Router - exposes cluster networks to tailnet
  applications.tailscale-subnet-router = {
    namespace = "tailscale";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      serviceAccounts.tailscale-subnet-router = {
        metadata.namespace = "tailscale";
      };

      deployments.tailscale-subnet-router = {
        metadata = {
          namespace = "tailscale";
          labels.app = "tailscale-subnet-router";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "tailscale-subnet-router";

          template = {
            metadata.labels.app = "tailscale-subnet-router";

            spec = {
              serviceAccountName = "tailscale-subnet-router";
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.82.0";
                securityContext = {
                  capabilities.add = [ "NET_ADMIN" ];
                };
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "subnet-router${clusterSuffix}"; }
                  { name = "TS_ROUTES"; value = "10.244.0.0/16,10.96.0.0/16"; }
                  { name = "TS_USERSPACE"; value = "true"; }
                  { name = "TS_STATE_DIR"; value = "/var/lib/tailscale"; }
                  # Reset state on restart to avoid conflicts with existing Tailscale node
                  { name = "TS_EXTRA_ARGS"; value = "--reset"; }
                ];
                volumeMounts = [{
                  name = "state";
                  mountPath = "/var/lib/tailscale";
                }];
              }];

              volumes = [{
                name = "state";
                emptyDir = {};
              }];
            };
          };
        };
      };
    };
  };

  # ArgoCD Tailscale Serve - Access: https://argocd-<cluster>.tail286401.ts.net
  applications.argocd-tailscale-serve = {
    namespace = "tailscale";
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
    };

    resources = {
      persistentVolumeClaims."argocd${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."argocd${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "argocd-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "argocd-tailscale-serve";

          template = {
            metadata.labels.app = "argocd-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.82.0";
                securityContext.capabilities.add = [ "NET_ADMIN" ];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "argocd${clusterSuffix}"; }
                  { name = "TS_SERVE_CONFIG"; value = "/config/serve.json"; }
                  { name = "TS_STATE_DIR"; value = "/var/lib/tailscale"; }
                  # Reset state on restart to avoid conflicts with existing Tailscale node
                  { name = "TS_EXTRA_ARGS"; value = "--reset"; }
                ];
                volumeMounts = [
                  { name = "state"; mountPath = "/var/lib/tailscale"; }
                  { name = "config"; mountPath = "/config"; }
                ];
              }];

              volumes = [
                {
                  name = "state";
                  persistentVolumeClaim.claimName = "argocd${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "argocd-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.argocd-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "argocd${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "https://argocd-server.argocd.svc.cluster.local:443";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Backstage Tailscale Serve - Access: https://backstage-<cluster>.tail286401.ts.net
  applications.backstage-tailscale-serve = {
    namespace = "tailscale";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-55";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      persistentVolumeClaims."backstage${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."backstage${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "backstage-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "backstage-tailscale-serve";

          template = {
            metadata.labels.app = "backstage-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.82.0";
                securityContext.capabilities.add = [ "NET_ADMIN" ];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "backstage${clusterSuffix}"; }
                  { name = "TS_SERVE_CONFIG"; value = "/config/serve.json"; }
                  { name = "TS_STATE_DIR"; value = "/var/lib/tailscale"; }
                  # Reset state on restart to avoid conflicts with existing Tailscale node
                  { name = "TS_EXTRA_ARGS"; value = "--reset"; }
                ];
                volumeMounts = [
                  { name = "state"; mountPath = "/var/lib/tailscale"; }
                  { name = "config"; mountPath = "/config"; }
                ];
              }];

              volumes = [
                {
                  name = "state";
                  persistentVolumeClaim.claimName = "backstage${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "backstage-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.backstage-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "backstage${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://backstage.backstage.svc.cluster.local:7007";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
