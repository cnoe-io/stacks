# Gateway Applications
# Gateway API CRDs, kgateway, and related infrastructure
# Mirrors: cdk8s/charts/platform/gateway-*.ts, kgateway-*.ts
#
# NOTE: Helm charts are deployed via ArgoCD Applications with Helm source type
# nixidy generates the ArgoCD Application manifests pointing to Helm repos
{ config, lib, ... }:
let
  inherit (config) environmentType;
in
{
  # Gateway API CRDs - placeholder for Helm deployment
  applications.gateway-api-crds = {
    namespace = "default";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-130";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = false;  # Never auto-delete CRDs
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
      };
    };

    yamls = [
      ''
        # Gateway API CRDs - Deployed via ArgoCD Application with Helm source
        # Chart: gateway-api from https://kubernetes-sigs.github.io/gateway-api/charts
        # Version: 1.4.0
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: gateway-api-crds-placeholder
          namespace: default
        data:
          note: "CRDs deployed via Helm chart in ArgoCD"
      ''
    ];
  };

  # kgateway CRDs - placeholder for Helm deployment
  applications.kgateway-crds = {
    namespace = "kgateway-system";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-125";
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
        # kgateway CRDs - Deployed via ArgoCD Application with Helm source
        # Chart: kgateway-crds from https://charts.kgateway.dev
        # Version: 2.1.1
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: kgateway-crds-placeholder
          namespace: kgateway-system
        data:
          note: "CRDs deployed via Helm chart in ArgoCD"
      ''
    ];
  };

  # kgateway with agentgateway - placeholder for Helm deployment
  applications.kgateway = {
    namespace = "kgateway-system";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-120";
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

    yamls = [
      ''
        # kgateway - Deployed via ArgoCD Application with Helm source
        # Chart: kgateway from https://charts.kgateway.dev
        # Version: 2.1.1
        # Values:
        #   gateway.enabled: true
        #   gateway.replicas: 1
        #   agentGateway.enabled: true
        #   ai.enabled: true
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: kgateway-placeholder
          namespace: kgateway-system
        data:
          note: "Deployed via Helm chart in ArgoCD"
      ''
    ];
  };

  # Dagger Infrastructure for Argo Workflows
  applications.dagger-infra = {
    namespace = "argo";
    createNamespace = true;

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
        createNamespace = true;
      };
    };

    resources = {
      namespaces.argo = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "workflows";
          "app.kubernetes.io/part-of" = "platform";
        };
      };

      # ServiceAccount for Dagger workflows
      serviceAccounts.dagger-workflow = {
        metadata.namespace = "argo";
      };

      # Role for Dagger workflow operations
      roles.dagger-workflow-role = {
        metadata.namespace = "argo";
        rules = [
          {
            apiGroups = [ "" ];
            resources = [ "pods" "pods/log" "pods/exec" ];
            verbs = [ "get" "list" "watch" "create" "delete" ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "secrets" "configmaps" ];
            verbs = [ "get" "list" ];
          }
          {
            apiGroups = [ "batch" ];
            resources = [ "jobs" ];
            verbs = [ "get" "list" "watch" "create" "delete" ];
          }
        ];
      };

      roleBindings.dagger-workflow-rolebinding = {
        metadata.namespace = "argo";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "dagger-workflow-role";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "dagger-workflow";
          namespace = "argo";
        }];
      };
    };
  };
}
