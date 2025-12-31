# Hub-and-Spoke Architecture Applications
# Hub cluster for centralized management, spoke clusters for workloads
# Mirrors: cdk8s/charts/platform/hub-*.ts, spoke-*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType azure;
  inherit (config.cluster) name;
  isTalos = environmentType == "talos";
  isHub = environmentType == "hub";
  tailnet = "tail286401";

  # Spoke cluster names for registration
  spokeClusterNames = ["hetzner" "thinkpad" "ryzen" "talos"];
in
{
  # =========================================================================
  # Hub Cluster Infrastructure
  # These apps deploy to the dedicated hub cluster for centralized management
  # =========================================================================

  # Hub Cluster: ESO Workload Identity Patch
  applications.hub-eso-workload-identity = lib.mkIf (isTalos || isHub) {
    namespace = "external-secrets";
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
      syncOptions = {
        serverSideApply = true;
      };
    };

    # Note: targetCluster = 'hub' would be set in ArgoCD Application
    # For now, this deploys to the current cluster

    yamls = [
      ''
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: external-secrets
          namespace: external-secrets
          labels:
            azure.workload.identity/use: "true"
          annotations:
            azure.workload.identity/client-id: "${azure.clientId}"
            azure.workload.identity/tenant-id: "${azure.tenantId}"
      ''
    ];
  };

  # Hub Cluster: ClusterSecretStore
  applications.hub-cluster-secret-store = lib.mkIf (isTalos || isHub) {
    namespace = "external-secrets";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-88";
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

    yamls = [
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ClusterSecretStore
        metadata:
          name: azure-keyvault-store
        spec:
          provider:
            azurekv:
              authType: WorkloadIdentity
              vaultUrl: https://${azure.keyVaultName}.vault.azure.net
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
      ''
    ];
  };

  # Hub Cluster: Tailscale CRDs
  applications.hub-tailscale-crds = lib.mkIf (isTalos || isHub) {
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

    yamls = [
      ''
        # Tailscale CRDs - Deployed via Helm chart in ArgoCD
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: hub-tailscale-crds-placeholder
          namespace: tailscale
        data:
          note: "CRDs deployed via Helm chart"
      ''
    ];
  };

  # Hub Cluster: Tailscale Operator Secrets
  applications.hub-tailscale-operator-secrets = lib.mkIf (isTalos || isHub) {
    namespace = "tailscale";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-85";
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
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: operator-oauth
          namespace: tailscale
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: operator-oauth
            creationPolicy: Owner
          data:
            - secretKey: client_id
              remoteRef:
                key: TAILSCALE-OAUTH-CLIENT-ID
            - secretKey: client_secret
              remoteRef:
                key: TAILSCALE-OAUTH-CLIENT-SECRET
      ''
    ];
  };

  # Hub Cluster: Tailscale Operator
  applications.hub-tailscale-operator = lib.mkIf (isTalos || isHub) {
    namespace = "tailscale";
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
      syncOptions = {
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        # Tailscale Operator - Deployed via Helm chart
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: hub-tailscale-operator-config
          namespace: tailscale
        data:
          operatorHostname: "hub-operator"
          defaultTags: "tag:k8s-operator"
          enableApiServerProxy: "true"
      ''
    ];
  };

  # Hub Cluster: Tailscale Secrets
  applications.hub-tailscale-secrets = lib.mkIf (isTalos || isHub) {
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
        apiVersion: external-secrets.io/v1beta1
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

  # Hub Cluster: ArgoCD Tailscale Serve
  applications.hub-argocd-tailscale-serve = lib.mkIf (isTalos || isHub) {
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
      persistentVolumeClaims.argocd-hub-tailscale-state = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments.argocd-hub-tailscale-serve = {
        metadata = {
          namespace = "tailscale";
          labels.app = "argocd-hub-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "argocd-hub-tailscale-serve";

          template = {
            metadata.labels.app = "argocd-hub-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.82.0";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "argocd-hub"; }
                  { name = "TS_SERVE_CONFIG"; value = "/config/serve.json"; }
                  { name = "TS_STATE_DIR"; value = "/var/lib/tailscale"; }
                ];
                volumeMounts = [
                  { name = "state"; mountPath = "/var/lib/tailscale"; }
                  { name = "config"; mountPath = "/config"; }
                ];
              }];

              volumes = [
                {
                  name = "state";
                  persistentVolumeClaim.claimName = "argocd-hub-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "argocd-hub-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.argocd-hub-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "argocd-hub.${tailnet}.ts.net:443" = {
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

  # Hub Cluster: K8s API Tailscale Serve
  applications.hub-k8s-api-tailscale-serve = lib.mkIf (isTalos || isHub) {
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
      persistentVolumeClaims.k8s-api-hub-tailscale-state = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      serviceAccounts.k8s-api-hub-tailscale = {
        metadata.namespace = "tailscale";
      };

      secrets.hub-k8s-remote-access-token = {
        metadata = {
          namespace = "tailscale";
          annotations = {
            "kubernetes.io/service-account.name" = "k8s-api-hub-tailscale";
          };
        };
        type = "kubernetes.io/service-account-token";
      };

      clusterRoleBindings.k8s-api-hub-tailscale-admin = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "cluster-admin";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "k8s-api-hub-tailscale";
          namespace = "tailscale";
        }];
      };

      deployments.k8s-api-hub-tailscale-serve = {
        metadata = {
          namespace = "tailscale";
          labels.app = "k8s-api-hub-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "k8s-api-hub-tailscale-serve";

          template = {
            metadata.labels.app = "k8s-api-hub-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.82.0";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "k8s-api-hub"; }
                  { name = "TS_SERVE_CONFIG"; value = "/config/serve.json"; }
                  { name = "TS_STATE_DIR"; value = "/var/lib/tailscale"; }
                ];
                volumeMounts = [
                  { name = "state"; mountPath = "/var/lib/tailscale"; }
                  { name = "config"; mountPath = "/config"; }
                ];
              }];

              volumes = [
                {
                  name = "state";
                  persistentVolumeClaim.claimName = "k8s-api-hub-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "k8s-api-hub-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.k8s-api-hub-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "k8s-api-hub.${tailnet}.ts.net:443" = {
                Handlers = {
                  "/" = {
                    Proxy = "https://kubernetes.default.svc.cluster.local:443";
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # =========================================================================
  # Spoke Cluster Registration
  # ExternalSecrets sync spoke credentials from Azure Key Vault
  # Cluster secrets register spokes in ArgoCD
  # =========================================================================

  # Spoke Credentials - Hetzner
  applications.spoke-credentials-hetzner = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-82";
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
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: spoke-creds-hetzner
          namespace: argocd
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: spoke-creds-hetzner
            creationPolicy: Owner
          data:
            - secretKey: server
              remoteRef:
                key: ARGOCD-CLUSTER-HETZNER-SERVER
            - secretKey: caData
              remoteRef:
                key: ARGOCD-CLUSTER-HETZNER-CA
            - secretKey: bearerToken
              remoteRef:
                key: ARGOCD-CLUSTER-HETZNER-TOKEN
      ''
    ];
  };

  # Spoke Credentials - Thinkpad
  applications.spoke-credentials-thinkpad = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-82";
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
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: spoke-creds-thinkpad
          namespace: argocd
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: spoke-creds-thinkpad
            creationPolicy: Owner
          data:
            - secretKey: server
              remoteRef:
                key: ARGOCD-CLUSTER-THINKPAD-SERVER
            - secretKey: caData
              remoteRef:
                key: ARGOCD-CLUSTER-THINKPAD-CA
            - secretKey: bearerToken
              remoteRef:
                key: ARGOCD-CLUSTER-THINKPAD-TOKEN
      ''
    ];
  };

  # Spoke Credentials - Ryzen
  applications.spoke-credentials-ryzen = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-82";
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
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: spoke-creds-ryzen
          namespace: argocd
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: spoke-creds-ryzen
            creationPolicy: Owner
          data:
            - secretKey: server
              remoteRef:
                key: ARGOCD-CLUSTER-RYZEN-SERVER
            - secretKey: caData
              remoteRef:
                key: ARGOCD-CLUSTER-RYZEN-CA
            - secretKey: bearerToken
              remoteRef:
                key: ARGOCD-CLUSTER-RYZEN-TOKEN
      ''
    ];
  };

  # Spoke Credentials - Talos
  applications.spoke-credentials-talos = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-82";
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
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: spoke-creds-talos
          namespace: argocd
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: spoke-creds-talos
            creationPolicy: Owner
          data:
            - secretKey: server
              remoteRef:
                key: ARGOCD-CLUSTER-TALOS-SERVER
            - secretKey: caData
              remoteRef:
                key: ARGOCD-CLUSTER-TALOS-CA
            - secretKey: bearerToken
              remoteRef:
                key: ARGOCD-CLUSTER-TALOS-TOKEN
      ''
    ];
  };

  # Spoke Cluster Secret - Hetzner
  applications.spoke-cluster-hetzner = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

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
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: v1
        kind: Secret
        metadata:
          name: cluster-hetzner
          namespace: argocd
          labels:
            argocd.argoproj.io/secret-type: cluster
            cluster-host: hetzner
        type: Opaque
        stringData:
          name: hetzner
          server: "$(kubectl get secret spoke-creds-hetzner -n argocd -o jsonpath='{.data.server}' | base64 -d)"
          config: |
            {
              "bearerToken": "$(kubectl get secret spoke-creds-hetzner -n argocd -o jsonpath='{.data.bearerToken}' | base64 -d)",
              "tlsClientConfig": {
                "insecure": false,
                "caData": "$(kubectl get secret spoke-creds-hetzner -n argocd -o jsonpath='{.data.caData}')"
              }
            }
      ''
    ];
  };

  # Spoke Cluster Secret - Thinkpad
  applications.spoke-cluster-thinkpad = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

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
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: v1
        kind: Secret
        metadata:
          name: cluster-thinkpad
          namespace: argocd
          labels:
            argocd.argoproj.io/secret-type: cluster
            cluster-host: thinkpad
        type: Opaque
        stringData:
          name: thinkpad
          server: "$(kubectl get secret spoke-creds-thinkpad -n argocd -o jsonpath='{.data.server}' | base64 -d)"
          config: |
            {
              "bearerToken": "$(kubectl get secret spoke-creds-thinkpad -n argocd -o jsonpath='{.data.bearerToken}' | base64 -d)",
              "tlsClientConfig": {
                "insecure": false,
                "caData": "$(kubectl get secret spoke-creds-thinkpad -n argocd -o jsonpath='{.data.caData}')"
              }
            }
      ''
    ];
  };

  # Spoke Cluster Secret - Ryzen
  applications.spoke-cluster-ryzen = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

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
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: v1
        kind: Secret
        metadata:
          name: cluster-ryzen
          namespace: argocd
          labels:
            argocd.argoproj.io/secret-type: cluster
            cluster-host: ryzen
        type: Opaque
        stringData:
          name: ryzen
          server: "$(kubectl get secret spoke-creds-ryzen -n argocd -o jsonpath='{.data.server}' | base64 -d)"
          config: |
            {
              "bearerToken": "$(kubectl get secret spoke-creds-ryzen -n argocd -o jsonpath='{.data.bearerToken}' | base64 -d)",
              "tlsClientConfig": {
                "insecure": false,
                "caData": "$(kubectl get secret spoke-creds-ryzen -n argocd -o jsonpath='{.data.caData}')"
              }
            }
      ''
    ];
  };

  # Spoke Cluster Secret - Talos
  applications.spoke-cluster-talos = lib.mkIf (isTalos || isHub) {
    namespace = "argocd";
    createNamespace = false;

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
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        apiVersion: v1
        kind: Secret
        metadata:
          name: cluster-talos
          namespace: argocd
          labels:
            argocd.argoproj.io/secret-type: cluster
            cluster-host: talos
        type: Opaque
        stringData:
          name: talos
          server: "$(kubectl get secret spoke-creds-talos -n argocd -o jsonpath='{.data.server}' | base64 -d)"
          config: |
            {
              "bearerToken": "$(kubectl get secret spoke-creds-talos -n argocd -o jsonpath='{.data.bearerToken}' | base64 -d)",
              "tlsClientConfig": {
                "insecure": false,
                "caData": "$(kubectl get secret spoke-creds-talos -n argocd -o jsonpath='{.data.caData}')"
              }
            }
      ''
    ];
  };

  # =========================================================================
  # Hub Kargo Configuration
  # Kargo pipelines for hub-managed applications
  # =========================================================================

  # Hub Kargo Secrets
  applications.hub-kargo-secrets = lib.mkIf (isTalos || isHub) {
    namespace = "kargo";
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
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: kargo-oidc-credentials
          namespace: kargo
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: kargo-oidc-credentials
            creationPolicy: Owner
          data:
            - secretKey: oidc.dex.clientId
              remoteRef:
                key: KARGO-DEX-CLIENT-ID
            - secretKey: oidc.dex.clientSecret
              remoteRef:
                key: KARGO-DEX-CLIENT-SECRET
      ''
    ];
  };

  # Hub Kargo Pipelines Project
  applications.hub-kargo-pipelines-project = lib.mkIf (isTalos || isHub) {
    namespace = "kargo-pipelines";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "80";
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

    yamls = [
      ''
        apiVersion: kargo.akuity.io/v1alpha1
        kind: Project
        metadata:
          name: kargo-pipelines
        spec:
          promotionPolicies:
            - stage: hub-backstage-local-dev
              autoPromotionEnabled: true
            - stage: hub-backstage-dev
              autoPromotionEnabled: true
            - stage: hub-backstage-staging
              autoPromotionEnabled: false
      ''
    ];
  };

  # Hub Kargo Tailscale Serve
  applications.hub-kargo-tailscale-serve = lib.mkIf (isTalos || isHub) {
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
      persistentVolumeClaims.kargo-hub-tailscale-state = {
        metadata.namespace = "tailscale";
        spec = {
          accessModes = ["ReadWriteOnce"];
          resources.requests.storage = "1Gi";
        };
      };

      deployments.kargo-hub-tailscale-serve = {
        metadata = {
          namespace = "tailscale";
          labels.app = "kargo-hub-tailscale-serve";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "kargo-hub-tailscale-serve";

          template = {
            metadata.labels.app = "kargo-hub-tailscale-serve";

            spec = {
              containers = [{
                name = "tailscale";
                image = "tailscale/tailscale:v1.82.0";
                securityContext.capabilities.add = ["NET_ADMIN"];
                env = [
                  {
                    name = "TS_AUTHKEY";
                    valueFrom.secretKeyRef = {
                      name = "tailscale-auth-key";
                      key = "authKey";
                    };
                  }
                  { name = "TS_HOSTNAME"; value = "kargo-hub"; }
                  { name = "TS_SERVE_CONFIG"; value = "/config/serve.json"; }
                  { name = "TS_STATE_DIR"; value = "/var/lib/tailscale"; }
                ];
                volumeMounts = [
                  { name = "state"; mountPath = "/var/lib/tailscale"; }
                  { name = "config"; mountPath = "/config"; }
                ];
              }];

              volumes = [
                {
                  name = "state";
                  persistentVolumeClaim.claimName = "kargo-hub-tailscale-state";
                }
                {
                  name = "config";
                  configMap.name = "kargo-hub-tailscale-serve-config";
                }
              ];
            };
          };
        };
      };

      configMaps.kargo-hub-tailscale-serve-config = {
        metadata.namespace = "tailscale";
        data = {
          "serve.json" = builtins.toJSON {
            TCP = {
              "443" = {
                HTTPS = true;
              };
            };
            Web = {
              "kargo-hub.${tailnet}.ts.net:443" = {
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
}
