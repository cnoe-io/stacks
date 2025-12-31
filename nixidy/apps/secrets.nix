# Secrets Management Applications
# Bootstrap secrets, ClusterSecretStore, and related secrets infrastructure
# Mirrors: cdk8s/charts/secrets/*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType azure;
  isTalos = environmentType == "talos";
  isKind = environmentType == "kind";
in
{
  # ClusterSecretStore for Azure Key Vault - Talos only
  applications.cluster-secret-store = lib.mkIf isTalos {
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

    resources = {
      # ClusterSecretStore CRD - needs yamls for CRD resources
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

  # Bootstrap Secrets - External Secrets from Azure Key Vault
  applications.bootstrap-secrets = lib.mkIf isTalos {
    namespace = "argocd";
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
        createNamespace = false;
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
          name: argocd-github-credentials
          namespace: argocd
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: argocd-github-credentials
            creationPolicy: Owner
          data:
            - secretKey: password
              remoteRef:
                key: GITHUB-TOKEN
            - secretKey: username
              remoteRef:
                key: GITHUB-USERNAME
      ''
    ];
  };

  # Cert-Manager Secrets - Cloudflare API token for DNS-01 challenges
  applications.cert-manager-secrets = lib.mkIf isTalos {
    namespace = "cert-manager";
    createNamespace = true;

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
          name: cloudflare-api-token-secret
          namespace: cert-manager
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: cloudflare-api-token-secret
            creationPolicy: Owner
          data:
            - secretKey: api-token
              remoteRef:
                key: CLOUDFLARE-API-TOKEN
      ''
    ];
  };

  # Cloudflare ClusterIssuer for Let's Encrypt DNS-01 challenges
  applications.cloudflare-issuer = lib.mkIf isTalos {
    namespace = "cert-manager";
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
        apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: letsencrypt-cloudflare
        spec:
          acme:
            email: admin@ai401kchat.com
            server: https://acme-v02.api.letsencrypt.org/directory
            privateKeySecretRef:
              name: letsencrypt-cloudflare-account-key
            solvers:
              - dns01:
                  cloudflare:
                    apiTokenSecretRef:
                      name: cloudflare-api-token-secret
                      key: api-token
      ''
    ];
  };
}
