# Secrets Management Applications
# Bootstrap secrets and related secrets infrastructure
# NOTE: ClusterSecretStore is defined in eso-workload-identity.nix
# Mirrors: cdk8s/charts/secrets/*.ts
{ config, lib, ... }:
let
  inherit (config) environmentType azure;
  isTalos = environmentType == "talos";
  isKind = environmentType == "kind";
  # Enable Azure secrets for both talos and kind (thinkpad, ryzen)
  enableAzureSecrets = isTalos || isKind;
in
{
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
        apiVersion: external-secrets.io/v1
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
        apiVersion: external-secrets.io/v1
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
