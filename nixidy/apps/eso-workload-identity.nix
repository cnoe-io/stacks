# External Secrets Workload Identity - Talos only
# This app configures Azure Workload Identity for External Secrets Operator
# Only needed in Talos (production) where we use Azure Key Vault
# Mirrors: cdk8s/charts/secrets/external-secrets-workload-identity-chart.ts
{ config, lib, ... }:
let
  # Only include for talos environment
  isTalos = config.environmentType == "talos";
  namespace = "external-secrets";
in
{
  # Conditionally include this application based on environment type
  config = lib.mkIf isTalos {
    applications.eso-workload-identity = {
      inherit namespace;
      createNamespace = true;

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
          createNamespace = true;
          serverSideApply = true;
        };
      };

      resources = {
        # ServiceAccount with Azure Workload Identity annotations
        serviceAccounts.external-secrets = {
          metadata = {
            inherit namespace;
            labels = {
              "azure.workload.identity/use" = "true";
            };
            annotations = {
              "azure.workload.identity/client-id" = config.azure.clientId;
              "azure.workload.identity/tenant-id" = config.azure.tenantId;
            };
          };
        };
      };

      # ClusterSecretStore requires Custom Resource - use yamls for now
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
                vaultUrl: https://${config.azure.keyVaultName}.vault.azure.net
                serviceAccountRef:
                  name: external-secrets
                  namespace: ${namespace}
        ''
      ];
    };
  };
}
