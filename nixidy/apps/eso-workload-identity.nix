# External Secrets Workload Identity
# This app configures Azure Workload Identity for External Secrets Operator
# Needed for any environment using Azure Key Vault (talos, kind clusters with Azure access)
# Mirrors: cdk8s/charts/secrets/external-secrets-workload-identity-chart.ts
{ config, lib, ... }:
let
  # Include for talos and kind environments (thinkpad, ryzen use Azure Workload Identity)
  isTalos = config.environmentType == "talos";
  isKind = config.environmentType == "kind";
  enableAzureWorkloadIdentity = isTalos || isKind;
  namespace = "external-secrets";
in
{
  # Conditionally include this application based on environment type
  config = lib.mkIf enableAzureWorkloadIdentity {
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
          apiVersion: external-secrets.io/v1
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
