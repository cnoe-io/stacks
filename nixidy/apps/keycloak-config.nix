# Keycloak Configuration Applications
# Keycloak secrets, clients, and config jobs
# Mirrors: cdk8s/charts/apps/keycloak-secrets-chart.ts, keycloak-clients-chart.ts, keycloak-config-chart.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost;
  namespace = "keycloak";
in
{
  # Keycloak Secrets - Creates ClusterSecretStores and password generators
  applications.keycloak-secrets = {
    inherit namespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
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
      # Keycloak admin password ExternalSecret
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: keycloak-admin-credentials
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: keycloak-admin-credentials
            creationPolicy: Owner
          data:
            - secretKey: password
              remoteRef:
                key: KEYCLOAK-ADMIN-PASSWORD
      ''
      # PostgreSQL credentials for Keycloak
      ''
        apiVersion: external-secrets.io/v1beta1
        kind: ExternalSecret
        metadata:
          name: keycloak-postgres-credentials
          namespace: ${namespace}
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: keycloak-postgres-credentials
            creationPolicy: Owner
          data:
            - secretKey: password
              remoteRef:
                key: KEYCLOAK-POSTGRES-PASSWORD
      ''
    ];
  };

  # Keycloak Clients - OIDC client configuration
  applications.keycloak-clients = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-47";
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
      # ConfigMap with OIDC client configuration
      configMaps.keycloak-clients-config = {
        metadata = {
          inherit namespace;
        };
        data = {
          "backstage-client.json" = builtins.toJSON {
            clientId = "backstage";
            enabled = true;
            protocol = "openid-connect";
            publicClient = false;
            redirectUris = [
              "https://${ingressHost}/backstage/*"
              "https://${ingressHost}/*"
            ];
            webOrigins = [ "+" ];
            standardFlowEnabled = true;
          };
        };
      };
    };
  };

  # Keycloak Config Job - Creates realm, users, and OIDC clients
  applications.keycloak-config = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-40";
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
      # Config Job will be managed by Keycloak realm import
      configMaps.keycloak-realm-config = {
        metadata = {
          inherit namespace;
          labels = {
            "app.kubernetes.io/component" = "configuration";
            "app.kubernetes.io/part-of" = "keycloak";
          };
        };
        data = {
          "cnoe-realm.json" = builtins.toJSON {
            realm = "cnoe";
            enabled = true;
            registrationAllowed = false;
            loginWithEmailAllowed = true;
            duplicateEmailsAllowed = false;
          };
        };
      };
    };
  };
}
