# Kargo - Progressive Delivery
# Provides GitOps-based progressive delivery for Kubernetes.
#
# Mirrors: cdk8s/config/applications.ts kargo entries
{ config, lib, ... }:
let
  namespace = "kargo";
in
{
  config = {
    # Kargo Secrets
    applications.kargo-secrets = lib.mkIf (config.environmentType == "talos") {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "60";
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
          limit = 5;
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
            name: kargo-admin-credentials
            namespace: ${namespace}
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: kargo-admin-credentials
              creationPolicy: Owner
            data:
              - secretKey: ADMIN_ACCOUNT_PASSWORD
                remoteRef:
                  key: kargo-admin-password
        ''
      ];
    };

    # Kargo application
    applications.kargo = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "65";
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

      # Placeholder for Kargo deployment
      # Chart: kargo from oci://ghcr.io/akuity/kargo-charts
      yamls = [
        ''
          # Kargo progressive delivery
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Key values:
          # - controller.resources
          # - api.resources
          # - api.adminAccount.enabled = true
        ''
      ];
    };
  };
}
