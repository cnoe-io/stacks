# Backstage Infrastructure
# Manages namespaces and RBAC for Backstage deployments
# Application manifests (Deployment, Service, etc.) are managed by Kargo via backstage-config repo
#
# Previous version: cdk8s/charts/apps/backstage-chart.ts
{ config, lib, ... }:
let
  # Namespace names for each stage
  baseNamespace = "backstage";
  devNamespace = "backstage-dev";
  stagingNamespace = "backstage-staging";
  appName = "backstage";

  # All namespaces where Backstage may be deployed
  allNamespaces = [ baseNamespace devNamespace stagingNamespace ];

  # Helper to create RBAC for a specific namespace
  mkRbacBinding = ns: {
    "${ns}-argo-workflows" = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "${baseNamespace}-argo-workflows";
      };
      subjects = [{
        kind = "ServiceAccount";
        name = appName;
        namespace = ns;
      }];
    };
    "${ns}-read-all" = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "${baseNamespace}-read-all";
      };
      subjects = [{
        kind = "ServiceAccount";
        name = appName;
        namespace = ns;
      }];
    };
  };
in
{
  # =========================================================================
  # Backstage Base Namespace - Legacy/primary deployment
  # =========================================================================
  applications.backstage-namespace = {
    namespace = baseNamespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-40";
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
      namespaces.${baseNamespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "portal";
          "app.kubernetes.io/part-of" = "developer-platform";
        };
      };
    };
  };

  # =========================================================================
  # Backstage Dev Namespace - Kargo dev stage deployment
  # =========================================================================
  applications.backstage-dev-namespace = {
    namespace = devNamespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-40";
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
      namespaces.${devNamespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "portal";
          "app.kubernetes.io/part-of" = "developer-platform";
          "environment" = "dev";
          "kargo.akuity.io/stage" = "backstage-dev";
        };
      };
    };
  };

  # =========================================================================
  # Backstage Staging Namespace - Kargo staging stage deployment
  # =========================================================================
  applications.backstage-staging-namespace = {
    namespace = stagingNamespace;
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-40";
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
      namespaces.${stagingNamespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "portal";
          "app.kubernetes.io/part-of" = "developer-platform";
          "environment" = "staging";
          "kargo.akuity.io/stage" = "backstage-staging";
        };
      };
    };
  };

  # =========================================================================
  # Backstage Infrastructure (RBAC) - Shared across all stages
  # =========================================================================
  applications.backstage-infra = {
    namespace = baseNamespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-30";
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
      # ClusterRole for Argo Workflows (shared)
      clusterRoles."${baseNamespace}-argo-workflows" = {
        rules = [{
          apiGroups = [ "argoproj.io" ];
          resources = [ "workflows" ];
          verbs = [ "create" ];
        }];
      };

      # ClusterRole for read-all (shared)
      clusterRoles."${baseNamespace}-read-all" = {
        rules = [{
          apiGroups = [ "*" ];
          resources = [ "*" ];
          verbs = [ "get" "list" "watch" ];
        }];
      };

      # ClusterRoleBindings for all stage namespaces
      clusterRoleBindings = lib.foldl' (acc: ns: acc // (mkRbacBinding ns)) {} allNamespaces;
    };
  };

  # =========================================================================
  # NOTE: Application resources (Deployment, Service, Ingress, StatefulSet,
  # ServiceAccount, ConfigMap) are now managed by Kargo via the
  # backstage-config repository using Kustomize overlays.
  #
  # See: https://github.com/PittampalliOrg/backstage-config
  #
  # Kargo Stages:
  # - backstage-dev: Auto-promoted, deploys to backstage-dev namespace
  # - backstage-staging: Manual promotion, deploys to backstage-staging namespace
  # =========================================================================
}
