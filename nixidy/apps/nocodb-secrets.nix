# NocoDB Secrets
# External Secrets for sensitive data from Azure Key Vault
# Mirrors pattern from: backstage-secrets.nix
{ config, lib, ... }:
let
  inherit (config) environmentType;
  namespace = "nocodb";
  isKind = environmentType == "kind";
in
{
  config = lib.mkIf isKind {
    applications.nocodb-secrets = {
      inherit namespace;
      createNamespace = false;  # Created by nocodb.nix

      annotations = {
        # Sync-wave -85: Before database (-50) and application (50)
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
        # ExternalSecret: Fetch NocoDB credentials from Azure Key Vault
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: nocodb-secrets
            namespace: ${namespace}
          spec:
            refreshInterval: 1m
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: nocodb-credentials
              template:
                engineVersion: v2
                data:
                  POSTGRES_PASSWORD: "{{.POSTGRES_PASSWORD}}"
                  NC_AUTH_JWT_SECRET: "{{.NC_AUTH_JWT_SECRET}}"
            data:
              - secretKey: POSTGRES_PASSWORD
                remoteRef:
                  key: NOCODB-POSTGRES-PASSWORD
              - secretKey: NC_AUTH_JWT_SECRET
                remoteRef:
                  key: NOCODB-JWT-SECRET
        ''
      ];
    };
  };
}
