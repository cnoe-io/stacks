# Backstage Variant Applications
# Local dev, staging, and hub-managed Backstage instances
# Mirrors: cdk8s/charts/apps/backstage-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost ingressPort name;
  isKind = environmentType == "kind";
  isTalos = environmentType == "talos";
  isHub = environmentType == "hub";
  clusterSuffix = if name != "" then "-${name}" else "";
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";
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
      # After keycloak-config (-50 to -40) which creates keycloak-clients
      "argocd.argoproj.io/sync-wave" = "-35";
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
      # backstage-env-vars - uses keycloak ClusterSecretStore for OIDC + Azure for stable passwords
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: backstage-oidc
          namespace: backstage-local-dev
        spec:
          refreshInterval: 1m
          secretStoreRef:
            kind: ClusterSecretStore
            name: keycloak
          target:
            name: backstage-env-vars
            template:
              engineVersion: v2
              data:
                BACKSTAGE_FRONTEND_URL: "https://${ingressHost}${portSuffix}/backstage"
                POSTGRES_HOST: "postgresql.backstage-local-dev.svc.cluster.local"
                POSTGRES_PORT: "5432"
                POSTGRES_DB: backstage
                POSTGRES_USER: backstage
                POSTGRES_PASSWORD: "{{.POSTGRES_PASSWORD}}"
                BACKSTAGE_SESSION_SECRET: "{{.SESSION_SECRET}}"
                ARGO_WORKFLOWS_URL: "https://${ingressHost}${portSuffix}/argo-workflows"
                ARGO_CD_URL: "https://argocd.${ingressHost}${portSuffix}"
                ARGOCD_AUTH_TOKEN: "argocd.token={{.ARGOCD_SESSION_TOKEN}}"
                KEYCLOAK_NAME_METADATA: "https://keycloak.${ingressHost}${portSuffix}/realms/cnoe/.well-known/openid-configuration"
                KEYCLOAK_CLIENT_SECRET: "{{.BACKSTAGE_CLIENT_SECRET}}"
                GITEA_URL: "https://gitea.${ingressHost}${portSuffix}"
                GITEA_HOST: "gitea.${ingressHost}${portSuffix}"
          data:
            # OIDC tokens from keycloak ClusterSecretStore
            - secretKey: ARGOCD_SESSION_TOKEN
              remoteRef:
                key: keycloak-clients
                property: ARGOCD_SESSION_TOKEN
            - secretKey: BACKSTAGE_CLIENT_SECRET
              remoteRef:
                key: keycloak-clients
                property: BACKSTAGE_CLIENT_SECRET
            # Stable passwords from Azure Key Vault
            - secretKey: POSTGRES_PASSWORD
              sourceRef:
                storeRef:
                  name: azure-keyvault-store
                  kind: ClusterSecretStore
              remoteRef:
                key: BACKSTAGE-POSTGRES-PASSWORD
            - secretKey: SESSION_SECRET
              sourceRef:
                storeRef:
                  name: azure-keyvault-store
                  kind: ClusterSecretStore
              remoteRef:
                key: BACKSTAGE-SESSION-SECRET
      ''
      # gitea-dockercfg - uses gitea ClusterSecretStore (Kubernetes provider)
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: gitea-dockercfg-external
          namespace: backstage-local-dev
          labels:
            app.kubernetes.io/name: gitea-dockercfg
            app.kubernetes.io/part-of: backstage
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: gitea
          target:
            name: gitea-dockercfg
            creationPolicy: Owner
            template:
              type: kubernetes.io/dockerconfigjson
              data:
                .dockerconfigjson: |
                  {
                    "auths": {
                      "gitea.${ingressHost}:8443": {
                        "username": "{{ .username }}",
                        "password": "{{ .password }}",
                        "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
                      }
                    }
                  }
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
      # gitea-credentials - for Backstage to access Gitea API
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: gitea-credentials
          namespace: backstage-local-dev
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: gitea
          target:
            name: gitea-credentials
          data:
            - secretKey: GITEA_USERNAME
              remoteRef:
                key: gitea-credential
                property: username
            - secretKey: GITEA_PASSWORD
              remoteRef:
                key: gitea-credential
                property: password
      ''
      # argocd-credentials - for Backstage to access ArgoCD
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: argocd-credentials
          namespace: backstage-local-dev
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: argocd
          target:
            name: argocd-credentials
          data:
            - secretKey: ARGOCD_ADMIN_PASSWORD
              remoteRef:
                key: argocd-initial-admin-secret
                property: password
      ''
      # ghcr-dockercfg - for pulling from GHCR
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: ghcr-dockercfg-external
          namespace: backstage-local-dev
          labels:
            app.kubernetes.io/name: ghcr-dockercfg
            app.kubernetes.io/part-of: backstage
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: ghcr-dockercfg
            creationPolicy: Owner
            template:
              type: kubernetes.io/dockerconfigjson
              data:
                .dockerconfigjson: |
                  {
                    "auths": {
                      "ghcr.io": {
                        "username": "pittampalliorg",
                        "password": "{{ .pat }}",
                        "auth": "{{ printf "%s:%s" "pittampalliorg" .pat | b64enc }}"
                      }
                    }
                  }
          data:
            - secretKey: pat
              remoteRef:
                key: GITHUB-PAT
      ''
    ];
  };

  # Backstage Local Dev
  applications.backstage-local-dev = lib.mkIf isKind {
    namespace = "backstage-local-dev";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "85";
      # Authorize Kargo Stage to mutate this Application for promotions
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
                  { name = "POSTGRES_PASSWORD"; valueFrom.secretKeyRef = { name = "backstage-env-vars"; key = "POSTGRES_PASSWORD"; }; }
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
              imagePullSecrets = [{ name = "ghcr-dockercfg"; }];
              containers = [{
                name = "backstage";
                image = "ghcr.io/pittampalliorg/backstage:v1.0.0";
                ports = [{ containerPort = 7007; name = "http"; }];
                envFrom = [{
                  secretRef.name = "backstage-env-vars";
                }];
                env = [
                  { name = "GITEA_USERNAME"; valueFrom.secretKeyRef = { name = "gitea-credentials"; key = "GITEA_USERNAME"; }; }
                  { name = "GITEA_PASSWORD"; valueFrom.secretKeyRef = { name = "gitea-credentials"; key = "GITEA_PASSWORD"; }; }
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

    # Note: kustomization.yaml for Kargo is generated separately
    # via the kargo-backstage-pipeline manifest repo, not here
  };

  # Backstage Staging Secrets
  applications.backstage-staging-secrets = lib.mkIf isKind {
    namespace = "backstage-staging";
    createNamespace = true;

    annotations = {
      # After keycloak-config (-50 to -40) which creates keycloak-clients
      "argocd.argoproj.io/sync-wave" = "-35";
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
      # backstage-env-vars for staging - uses Azure Key Vault (GHCR doesn't need Keycloak OIDC)
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: backstage-staging-secrets
          namespace: backstage-staging
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: backstage-env-vars
            template:
              engineVersion: v2
              data:
                BACKSTAGE_FRONTEND_URL: "https://${ingressHost}:8443/backstage-staging"
                POSTGRES_HOST: "postgresql.backstage-staging.svc.cluster.local"
                POSTGRES_PORT: "5432"
                POSTGRES_DB: backstage
                POSTGRES_USER: backstage
                POSTGRES_PASSWORD: "{{.POSTGRES_PASSWORD}}"
                GITHUB_TOKEN: "{{.GITHUB_TOKEN}}"
          data:
            - secretKey: POSTGRES_PASSWORD
              remoteRef:
                key: BACKSTAGE-POSTGRES-PASSWORD
            - secretKey: GITHUB_TOKEN
              remoteRef:
                key: GITHUB-PAT
      ''
      # ghcr-dockercfg for pulling from GHCR
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: ghcr-dockercfg-external
          namespace: backstage-staging
          labels:
            app.kubernetes.io/name: ghcr-dockercfg
            app.kubernetes.io/part-of: backstage
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: ghcr-dockercfg
            creationPolicy: Owner
            template:
              type: kubernetes.io/dockerconfigjson
              data:
                .dockerconfigjson: |
                  {
                    "auths": {
                      "ghcr.io": {
                        "username": "pittampalliorg",
                        "password": "{{ .pat }}",
                        "auth": "{{ printf "%s:%s" "pittampalliorg" .pat | b64enc }}"
                      }
                    }
                  }
          data:
            - secretKey: pat
              remoteRef:
                key: GITHUB-PAT
      ''
    ];
  };

  # Backstage Staging
  applications.backstage-staging = lib.mkIf isKind {
    namespace = "backstage-staging";
    createNamespace = false;

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
        serverSideApply = true;
      };
    };

    resources = {
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
                { name = "POSTGRES_PASSWORD"; valueFrom.secretKeyRef = { name = "backstage-env-vars"; key = "POSTGRES_PASSWORD"; }; }
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

            spec = {
              imagePullSecrets = [{ name = "ghcr-dockercfg"; }];
              containers = [{
                name = "backstage";
                image = "ghcr.io/pittampalliorg/backstage:v1.0.0";
                ports = [{ containerPort = 7007; name = "http"; }];
                envFrom = [{
                  secretRef.name = "backstage-env-vars";
                }];
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
              imagePullSecrets = [{ name = "ghcr-dockercfg"; }];
              containers = [{
                name = "backstage";
                image = "ghcr.io/pittampalliorg/backstage:v1.0.0";
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
              image = "ghcr.io/pittampalliorg/backstage:v1.0.0";
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
              image = "ghcr.io/pittampalliorg/backstage:v1.0.0";
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
