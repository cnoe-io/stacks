# Gateway Applications
# Gateway API CRDs, kgateway, and related infrastructure
# Mirrors: cdk8s/charts/platform/gateway-*.ts, kgateway-*.ts
#
# NOTE: kgateway uses OCI registry (cr.kgateway.dev) which nixidy doesn't support.
# We use ArgoCD Application with OCI Helm source - ArgoCD handles OCI natively.
# See: https://nixidy.dev/user_guide/helm_charts/
{ config, lib, ... }:
let
  inherit (config) environmentType;
  kgatewayNamespace = "kgateway-system";
in
{
  # kgateway CRDs - via ArgoCD OCI Helm Application
  applications.kgateway-crds = {
    namespace = kgatewayNamespace;
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

    # Use ArgoCD Application with OCI Helm source (nixidy doesn't support OCI)
    yamls = [
      ''
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: kgateway-crds-helm
          namespace: argocd
          annotations:
            argocd.argoproj.io/sync-wave: "-125"
        spec:
          project: default
          destination:
            server: https://kubernetes.default.svc
            namespace: ${kgatewayNamespace}
          source:
            repoURL: cr.kgateway.dev/kgateway-dev/charts
            chart: kgateway-crds
            targetRevision: v2.1.2
          syncPolicy:
            automated:
              prune: false
              selfHeal: true
            syncOptions:
              - CreateNamespace=true
              - ServerSideApply=true
      ''
    ];
  };

  # kgateway with agentgateway - via ArgoCD OCI Helm Application
  applications.kgateway = {
    namespace = kgatewayNamespace;
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
        serverSideApply = true;
      };
    };

    # Use ArgoCD Application with OCI Helm source
    yamls = [
      ''
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: kgateway-helm
          namespace: argocd
          annotations:
            argocd.argoproj.io/sync-wave: "-120"
        spec:
          project: default
          destination:
            server: https://kubernetes.default.svc
            namespace: ${kgatewayNamespace}
          source:
            repoURL: cr.kgateway.dev/kgateway-dev/charts
            chart: kgateway
            targetRevision: v2.1.2
            helm:
              valuesObject:
                gateway:
                  enabled: true
                  replicas: 1
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
            syncOptions:
              - ServerSideApply=true
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
