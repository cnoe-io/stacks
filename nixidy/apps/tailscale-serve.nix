# Tailscale Serve Applications
# Additional Tailscale Serve services for exposing internal services
# Mirrors: cdk8s/charts/platform/tailscale-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) name;
  clusterSuffix = if name != "" then "-${name}" else "";
  tailnet = "tail286401";
  isKind = environmentType == "kind";
  # Tailscale service host for stable URLs (e.g., gitea-thinkpad, argocd-thinkpad)
  # Uses serviceHost config if set, falls back to cluster name
  serviceHost = let
    host = config.tailscale.serviceHost;
  in if host != "" then host else name;
  serviceSuffix = if serviceHost != "" then "-${serviceHost}" else "";
in
{
  # Langfuse Tailscale Serve - Access: https://langfuse-<cluster>.tail286401.ts.net
  applications.langfuse-tailscale-serve = {
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
      persistentVolumeClaims."langfuse${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."langfuse${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "langfuse-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "langfuse-tailscale-serve";

          template = {
            metadata.labels.app = "langfuse-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "langfuse${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "langfuse${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "langfuse-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.langfuse-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "langfuse${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://langfuse.observability.svc.cluster.local:3000";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Gitea Tailscale Serve - Access: https://gitea-<cluster>.tail286401.ts.net
  applications.gitea-tailscale-serve = {
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
      persistentVolumeClaims."gitea${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."gitea${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "gitea-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "gitea-tailscale-serve";

          template = {
            metadata.labels.app = "gitea-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "gitea${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "gitea${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "gitea-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.gitea-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "gitea${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://my-gitea-http.gitea.svc.cluster.local:3000";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # kagent Tailscale Serve - Access: https://kagent-<cluster>.tail286401.ts.net
  applications.kagent-tailscale-serve = {
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
      persistentVolumeClaims."kagent${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."kagent${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "kagent-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "kagent-tailscale-serve";

          template = {
            metadata.labels.app = "kagent-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "kagent${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "kagent${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "kagent-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.kagent-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "kagent${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://kagent-ui.kagent.svc.cluster.local:8080";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Kargo Tailscale Serve (KIND only) - Access: https://kargo-<cluster>.tail286401.ts.net
  applications.kargo-tailscale-serve = lib.mkIf isKind {
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
      persistentVolumeClaims."kargo${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."kargo${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "kargo-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "kargo-tailscale-serve";

          template = {
            metadata.labels.app = "kargo-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "kargo${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "kargo${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "kargo-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.kargo-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "kargo${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://kargo-api.kargo.svc.cluster.local:80";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Keycloak Tailscale Serve - Access: https://keycloak-<cluster>.tail286401.ts.net
  applications.keycloak-tailscale-serve = {
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
      persistentVolumeClaims."keycloak${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."keycloak${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "keycloak-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "keycloak-tailscale-serve";

          template = {
            metadata.labels.app = "keycloak-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "keycloak${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "keycloak${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "keycloak-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.keycloak-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "keycloak${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://keycloak.keycloak.svc.cluster.local:8080";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # NOTE: k8s-api-tailscale-serve is defined in tailscale-operator.nix

  # Grafana Tailscale Serve - Access: https://grafana-<cluster>.tail286401.ts.net
  applications.grafana-tailscale-serve = {
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
      persistentVolumeClaims."grafana${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."grafana${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "grafana-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "grafana-tailscale-serve";

          template = {
            metadata.labels.app = "grafana-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "grafana${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "grafana${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "grafana-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.grafana-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "grafana${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://grafana.observability.svc.cluster.local:3000";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # OTEL Collector Tailscale Serve - Access: https://otel-<cluster>.tail286401.ts.net
  applications.otel-collector-tailscale-serve = {
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
      persistentVolumeClaims."otel${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."otel${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "otel-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "otel-tailscale-serve";

          template = {
            metadata.labels.app = "otel-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "otel${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "otel${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "otel-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.otel-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "4317" = {};  # gRPC OTLP
              "4318" = {};  # HTTP OTLP
            };
          };
        };
      };
    };
  };

  # Mimir Tailscale Serve - Access: https://mimir-<cluster>.tail286401.ts.net
  applications.mimir-tailscale-serve = {
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
      persistentVolumeClaims."mimir${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."mimir${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "mimir-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "mimir-tailscale-serve";

          template = {
            metadata.labels.app = "mimir-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "mimir${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "mimir${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "mimir-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.mimir-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "mimir${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://mimir.observability.svc.cluster.local:9009";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Loki Tailscale Serve - Access: https://loki-<cluster>.tail286401.ts.net
  applications.loki-tailscale-serve = {
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
      persistentVolumeClaims."loki${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."loki${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "loki-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "loki-tailscale-serve";

          template = {
            metadata.labels.app = "loki-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "loki${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "loki${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "loki-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.loki-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "loki${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://loki.observability.svc.cluster.local:3100";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Flipt Tailscale Serve - Access: https://flipt-<cluster>.tail286401.ts.net
  applications.flipt-tailscale-serve = {
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
      persistentVolumeClaims."flipt${clusterSuffix}-tailscale-state" = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments."flipt${clusterSuffix}-tailscale-serve" = {
        metadata = {
          namespace = "tailscale";
          labels.app = "flipt-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "flipt-tailscale-serve";

          template = {
            metadata.labels.app = "flipt-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.86.5";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "flipt${clusterSuffix}"; }
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
                  persistentVolumeClaim.claimName = "flipt${clusterSuffix}-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "flipt-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.flipt-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "flipt${clusterSuffix}.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "http://flipt.feature-flags.svc.cluster.local:8080";
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
