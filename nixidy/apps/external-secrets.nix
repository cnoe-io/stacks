# External Secrets Operator - Secret Management
# Provides external secret management for both KIND and Talos clusters.
# KIND uses idpBuilder's built-in Gitea secret stores.
# Both KIND and Talos use Azure Key Vault via Workload Identity.
#
# CONSOLIDATED: This app now owns the namespace, ServiceAccount, and ClusterSecretStore
# (previously split across external-secrets and eso-workload-identity apps)
#
# Uses nixhelm for Helm chart management following nixidy best practices.
# See: https://nixidy.dev/user_guide/helm_charts/
#
# Mirrors: cdk8s/config/applications.ts external-secrets entries
{ config, lib, charts, ... }:
let
  isKind = config.environmentType == "kind";
  isTalos = config.environmentType == "talos";
  enableAzureWorkloadIdentity = isTalos || isKind;
  namespace = "external-secrets";
in
{
  # External Secrets Operator - Helm deployment via nixhelm
  config = {
    applications.external-secrets = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-100";  # Early, before secrets
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
          applyOutOfSyncOnly = true;  # Skip unchanged resources for faster syncs
        };
      };

      # Use nixhelm for pre-rendered Helm chart (nixidy best practice)
      # Chart is rendered at build time, not at ArgoCD sync time
      helm.releases.external-secrets = {
        chart = charts.external-secrets.external-secrets;
        values = {
          installCRDs = true;
          webhook = {
            create = true;
          };
          certController = {
            create = true;
          };
          serviceAccount = {
            create = true;
            name = "external-secrets";
            # Azure Workload Identity annotations for Key Vault access
            labels = {
              "azure.workload.identity/use" = "true";
            };
            annotations = {
              "azure.workload.identity/client-id" = config.azure.clientId;
              "azure.workload.identity/tenant-id" = config.azure.tenantId;
            };
          };
          # Resource limits from ref-implementation
          resources = {
            requests = {
              cpu = "100m";
              memory = "128Mi";
            };
            limits = {
              cpu = "500m";
              memory = "512Mi";
            };
          };
          # Additional settings from ref-implementation
          logLevel = "info";
          leaderElect = true;
        };
      };

      # ClusterSecretStore for Azure Key Vault (consolidated from eso-workload-identity)
      # This provides access to Azure Key Vault for all ExternalSecrets
      yamls = lib.mkIf enableAzureWorkloadIdentity [
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

    # NOTE: bootstrap-secrets is defined in secrets.nix
  };
}
