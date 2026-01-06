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
  # Gateway API CRDs (standard Kubernetes Gateway API) - MUST be installed before kgateway
  # These are the core gateway.networking.k8s.io CRDs required by kgateway controller
  applications.gateway-api-crds = {
    namespace = kgatewayNamespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-130";  # Before kgateway-crds
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

    # Install standard Gateway API CRDs from official source (raw GitHub manifests)
    yamls = [
      ''
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: gateway-api-crds-helm
          namespace: argocd
          annotations:
            argocd.argoproj.io/sync-wave: "-130"
        spec:
          project: default
          destination:
            server: https://kubernetes.default.svc
            namespace: ${kgatewayNamespace}
          source:
            repoURL: https://github.com/kubernetes-sigs/gateway-api
            path: config/crd/standard
            targetRevision: v1.2.0
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

  # kgateway CRDs - via ArgoCD OCI Helm Application
  # NOTE: Namespace owned by gateway-api-crds app (sync-wave -130)
  applications.kgateway-crds = {
    namespace = kgatewayNamespace;
    createNamespace = false;  # gateway-api-crds owns the namespace

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
        serverSideApply = true;
        applyOutOfSyncOnly = true;  # Skip unchanged resources
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
  # NOTE: Namespace owned by argo-workflows app (sync-wave 50)
  # This app deploys earlier to set up RBAC before workflows deploy
  applications.dagger-infra = {
    namespace = "argo";
    createNamespace = false;  # argo-workflows owns the namespace

    annotations = {
      "argocd.argoproj.io/sync-wave" = "45";  # Just before argo-workflows (50)
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
        applyOutOfSyncOnly = true;  # Skip unchanged resources
      };
    };

    resources = {
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
