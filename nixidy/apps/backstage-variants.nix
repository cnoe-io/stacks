# Backstage Variant Applications
# Local dev, staging, and hub-managed Backstage instances
# Mirrors: cdk8s/charts/apps/backstage-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost name;
  isKind = environmentType == "kind";
  isTalos = environmentType == "talos";
  isHub = environmentType == "hub";
  clusterSuffix = if name != "" then "-${name}" else "";
in
{
  # =========================================================================
  # KIND-specific Backstage Variants
  # =========================================================================

  # Backstage Local Dev Secrets
  applications.backstage-local-dev-secrets = lib.mkIf isKind {
    namespace = "backstage-local-dev";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-75";
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
          name: backstage-secrets
          namespace: backstage-local-dev
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: backstage-secrets
            creationPolicy: Owner
          data:
            - secretKey: POSTGRES_PASSWORD
              remoteRef:
                key: BACKSTAGE-POSTGRES-PASSWORD
            - secretKey: GITHUB_TOKEN
              remoteRef:
                key: GITHUB-PAT
            - secretKey: AUTH_GITHUB_CLIENT_ID
              remoteRef:
                key: AUTH-GITHUB-CLIENT-ID
            - secretKey: AUTH_GITHUB_CLIENT_SECRET
              remoteRef:
                key: AUTH-GITHUB-CLIENT-SECRET
      ''
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: gitea-dockercfg
          namespace: backstage-local-dev
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: gitea-dockercfg
            creationPolicy: Owner
            template:
              type: kubernetes.io/dockerconfigjson
              data:
                .dockerconfigjson: '{{ .dockerconfigjson }}'
          data:
            - secretKey: dockerconfigjson
              remoteRef:
                key: GITEA-DOCKERCFG
      ''
    ];
  };

  # Backstage Local Dev
  applications.backstage-local-dev = lib.mkIf isKind {
    namespace = "backstage-local-dev";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "85";
      "kargo.akuity.io/authorized-stage" = "kargo-pipelines:backstage-local-dev";
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
    };

    resources = {
      # PostgreSQL for local dev
      statefulSets.postgresql = {
        metadata = {
          namespace = "backstage-local-dev";
          labels.app = "postgresql";
        };
        spec = {
          replicas = 1;
          serviceName = "postgresql";
          selector.matchLabels.app = "postgresql";

          template = {
            metadata.labels.app = "postgresql";

            spec = {
              containers = [{
                name = "postgresql";
                image = "postgres:15-alpine";
                ports = [{ containerPort = 5432; name = "postgres"; }];
                env = [
                  { name = "POSTGRES_DB"; value = "backstage"; }
                  { name = "POSTGRES_USER"; value = "backstage"; }
                  { name = "POSTGRES_PASSWORD"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "POSTGRES_PASSWORD"; }; }
                ];
                volumeMounts = [{
                  name = "data";
                  mountPath = "/var/lib/postgresql/data";
                }];
              }];
            };
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "5Gi";
            };
          }];
        };
      };

      services.postgresql = {
        metadata = {
          namespace = "backstage-local-dev";
          labels.app = "postgresql";
        };
        spec = {
          ports = [{ name = "postgres"; port = 5432; targetPort = "postgres"; }];
          selector.app = "postgresql";
        };
      };

      # Backstage Deployment
      deployments.backstage = {
        metadata = {
          namespace = "backstage-local-dev";
          labels.app = "backstage";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "backstage";

          template = {
            metadata.labels.app = "backstage";

            spec = {
              imagePullSecrets = [{ name = "gitea-dockercfg"; }];
              containers = [{
                name = "backstage";
                image = "gitea.cnoe.localtest.me:8443/giteaadmin/backstage-cnoe:latest";
                ports = [{ containerPort = 7007; name = "http"; }];
                env = [
                  { name = "POSTGRES_HOST"; value = "postgresql.backstage-local-dev.svc.cluster.local"; }
                  { name = "POSTGRES_PORT"; value = "5432"; }
                  { name = "POSTGRES_USER"; value = "backstage"; }
                  { name = "POSTGRES_PASSWORD"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "POSTGRES_PASSWORD"; }; }
                  { name = "GITHUB_TOKEN"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "GITHUB_TOKEN"; }; }
                  { name = "AUTH_GITHUB_CLIENT_ID"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "AUTH_GITHUB_CLIENT_ID"; }; }
                  { name = "AUTH_GITHUB_CLIENT_SECRET"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "AUTH_GITHUB_CLIENT_SECRET"; }; }
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
              }];
            };
          };
        };
      };

      services.backstage = {
        metadata = {
          namespace = "backstage-local-dev";
          labels.app = "backstage";
        };
        spec = {
          ports = [{ name = "http"; port = 7007; targetPort = "http"; }];
          selector.app = "backstage";
        };
      };

      ingresses.backstage = {
        metadata = {
          namespace = "backstage-local-dev";
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = "backstage-local-dev.cnoe.localtest.me";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "backstage";
                port.name = "http";
              };
            }];
          }];
        };
      };
    };
  };

  # Backstage Staging
  applications.backstage-staging = lib.mkIf isKind {
    namespace = "backstage-staging";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "90";
      "kargo.akuity.io/authorized-stage" = "kargo-pipelines:backstage-staging";
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
      namespaces.backstage-staging = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
        };
      };

      # PostgreSQL for staging
      statefulSets.postgresql = {
        metadata = {
          namespace = "backstage-staging";
          labels.app = "postgresql";
        };
        spec = {
          replicas = 1;
          serviceName = "postgresql";
          selector.matchLabels.app = "postgresql";

          template = {
            metadata.labels.app = "postgresql";

            spec.containers = [{
              name = "postgresql";
              image = "postgres:15-alpine";
              ports = [{ containerPort = 5432; name = "postgres"; }];
              env = [
                { name = "POSTGRES_DB"; value = "backstage"; }
                { name = "POSTGRES_USER"; value = "backstage"; }
                { name = "POSTGRES_PASSWORD"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "POSTGRES_PASSWORD"; }; }
              ];
              volumeMounts = [{
                name = "data";
                mountPath = "/var/lib/postgresql/data";
              }];
            }];
          };

          volumeClaimTemplates = [{
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              resources.requests.storage = "10Gi";
            };
          }];
        };
      };

      services.postgresql = {
        metadata = {
          namespace = "backstage-staging";
          labels.app = "postgresql";
        };
        spec = {
          ports = [{ name = "postgres"; port = 5432; targetPort = "postgres"; }];
          selector.app = "postgresql";
        };
      };

      # Backstage Deployment
      deployments.backstage = {
        metadata = {
          namespace = "backstage-staging";
          labels.app = "backstage";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "backstage";

          template = {
            metadata.labels.app = "backstage";

            spec.containers = [{
              name = "backstage";
              image = "ghcr.io/pittampalliorg/backstage-cnoe:latest";
              ports = [{ containerPort = 7007; name = "http"; }];
              env = [
                { name = "POSTGRES_HOST"; value = "postgresql.backstage-staging.svc.cluster.local"; }
                { name = "POSTGRES_PORT"; value = "5432"; }
                { name = "POSTGRES_USER"; value = "backstage"; }
                { name = "POSTGRES_PASSWORD"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "POSTGRES_PASSWORD"; }; }
                { name = "GITHUB_TOKEN"; valueFrom.secretKeyRef = { name = "backstage-secrets"; key = "GITHUB_TOKEN"; }; }
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
            }];
          };
        };
      };

      services.backstage = {
        metadata = {
          namespace = "backstage-staging";
          labels.app = "backstage";
        };
        spec = {
          ports = [{ name = "http"; port = 7007; targetPort = "http"; }];
          selector.app = "backstage";
        };
      };
    };
  };

  # Backstage Token Sync (ArgoCD token for Backstage)
  applications.backstage-token-sync = lib.mkIf isKind {
    namespace = "argocd";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "50";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    yamls = [
      ''
        apiVersion: batch/v1
        kind: CronJob
        metadata:
          name: backstage-argocd-token-sync
          namespace: argocd
        spec:
          schedule: "0 */6 * * *"
          jobTemplate:
            spec:
              template:
                spec:
                  serviceAccountName: argocd-server
                  containers:
                    - name: token-sync
                      image: quay.io/argoproj/argocd:v2.14.11
                      env:
                        - name: HOME
                          value: /tmp
                        - name: ARGOCD_SERVER
                          value: argocd-server.argocd.svc.cluster.local
                      command:
                        - /bin/sh
                        - -c
                        - |
                          argocd login $ARGOCD_SERVER --core
                          TOKEN=$(argocd account generate-token --account backstage)
                          echo "Backstage token generated successfully"
                  restartPolicy: OnFailure
      ''
    ];
  };

  # =========================================================================
  # Hub-Managed Backstage Variants (Talos/Hub)
  # These are managed by hub ArgoCD and deploy to spoke clusters
  # =========================================================================

  # Hub-Managed Backstage Local Dev (deploys to thinkpad spoke)
  applications.hub-backstage-local-dev = lib.mkIf (isTalos || isHub) {
    namespace = "backstage-local-dev";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "85";
      "kargo.akuity.io/authorized-stage" = "kargo-pipelines:hub-backstage-local-dev";
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
      namespaces.backstage-local-dev = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "kargo.akuity.io/loop" = "inner";
        };
      };

      deployments.backstage = {
        metadata = {
          namespace = "backstage-local-dev";
          labels = {
            app = "backstage";
            "kargo.akuity.io/managed-by" = "hub-kargo";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "backstage";

          template = {
            metadata.labels.app = "backstage";

            spec = {
              imagePullSecrets = [{ name = "gitea-dockercfg"; }];
              containers = [{
                name = "backstage";
                image = "gitea.cnoe.localtest.me:8443/giteaadmin/backstage-cnoe:latest";
                ports = [{ containerPort = 7007; name = "http"; }];
                resources = {
                  requests = {
                    cpu = "200m";
                    memory = "512Mi";
                  };
                  limits = {
                    memory = "1Gi";
                  };
                };
              }];
            };
          };
        };
      };

      services.backstage = {
        metadata = {
          namespace = "backstage-local-dev";
          labels.app = "backstage";
        };
        spec = {
          ports = [{ name = "http"; port = 7007; targetPort = "http"; }];
          selector.app = "backstage";
        };
      };

      ingresses.backstage = {
        metadata.namespace = "backstage-local-dev";
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = "backstage-local-dev.cnoe.localtest.me";
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "backstage";
                port.name = "http";
              };
            }];
          }];
        };
      };
    };
  };

  # Hub-Managed Backstage Dev (deploys to thinkpad spoke)
  applications.hub-backstage-dev = lib.mkIf (isTalos || isHub) {
    namespace = "backstage-dev";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "85";
      "kargo.akuity.io/authorized-stage" = "kargo-pipelines:hub-backstage-dev";
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
      namespaces.backstage-dev = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "kargo.akuity.io/loop" = "outer";
        };
      };

      deployments.backstage = {
        metadata = {
          namespace = "backstage-dev";
          labels = {
            app = "backstage";
            "kargo.akuity.io/managed-by" = "hub-kargo";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "backstage";

          template = {
            metadata.labels.app = "backstage";

            spec.containers = [{
              name = "backstage";
              image = "ghcr.io/pittampalliorg/backstage-cnoe:latest";
              ports = [{ containerPort = 7007; name = "http"; }];
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "512Mi";
                };
                limits = {
                  memory = "1Gi";
                };
              };
            }];
          };
        };
      };

      services.backstage = {
        metadata = {
          namespace = "backstage-dev";
          labels.app = "backstage";
        };
        spec = {
          ports = [{ name = "http"; port = 7007; targetPort = "http"; }];
          selector.app = "backstage";
        };
      };
    };
  };

  # Hub-Managed Backstage Staging (deploys to ryzen spoke)
  applications.hub-backstage-staging = lib.mkIf (isTalos || isHub) {
    namespace = "backstage-staging";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "90";
      "kargo.akuity.io/authorized-stage" = "kargo-pipelines:hub-backstage-staging";
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
      namespaces.backstage-staging = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "kargo.akuity.io/loop" = "outer";
        };
      };

      deployments.backstage = {
        metadata = {
          namespace = "backstage-staging";
          labels = {
            app = "backstage";
            "kargo.akuity.io/managed-by" = "hub-kargo";
          };
        };
        spec = {
          replicas = 2;  # Higher replicas for staging
          selector.matchLabels.app = "backstage";

          template = {
            metadata.labels.app = "backstage";

            spec.containers = [{
              name = "backstage";
              image = "ghcr.io/pittampalliorg/backstage-cnoe:latest";
              ports = [{ containerPort = 7007; name = "http"; }];
              resources = {
                requests = {
                  cpu = "300m";
                  memory = "768Mi";
                };
                limits = {
                  memory = "1536Mi";
                };
              };
            }];
          };
        };
      };

      services.backstage = {
        metadata = {
          namespace = "backstage-staging";
          labels.app = "backstage";
        };
        spec = {
          ports = [{ name = "http"; port = 7007; targetPort = "http"; }];
          selector.app = "backstage";
        };
      };
    };
  };
}
