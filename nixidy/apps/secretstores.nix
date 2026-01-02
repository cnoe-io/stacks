# Cluster Secret Stores
# Creates ClusterSecretStores for gitea, argocd, and default namespaces
# These enable ExternalSecrets to fetch secrets from Kubernetes secrets in those namespaces
# Includes retry logic to handle ESO webhook not being ready on fresh cluster creation
{ config, lib, ... }:
let
  isKind = config.environmentType == "kind";

  # Helper to create a secretstore with RBAC
  mkSecretStore = { name, namespace, saName ? "eso-store", resourceNames ? null }:
    let
      secretRules = if resourceNames != null then [{
        apiGroups = [ "" ];
        resources = [ "secrets" ];
        resourceNames = resourceNames;
        verbs = [ "get" "list" "watch" ];
      }] else [{
        apiGroups = [ "" ];
        resources = [ "secrets" ];
        verbs = [ "get" "list" "watch" ];
      }];
    in {
      # ServiceAccount
      serviceAccounts.${saName} = {
        metadata.namespace = namespace;
      };

      # Role for secret access
      roles.${saName} = {
        metadata.namespace = namespace;
        rules = secretRules ++ [{
          apiGroups = [ "authorization.k8s.io" ];
          resources = [ "selfsubjectrulesreviews" ];
          verbs = [ "create" ];
        }];
      };

      # RoleBinding
      roleBindings.${saName} = {
        metadata.namespace = namespace;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          inherit name;
        };
        subjects = [{
          kind = "ServiceAccount";
          inherit namespace;
          name = saName;
        }];
      };
    };

  # Common sync policy with retry for webhook readiness
  syncPolicyWithRetry = {
    autoSync = {
      enable = true;
      prune = true;
      selfHeal = true;
    };
    syncOptions = {
      serverSideApply = true;
    };
    # Retry on webhook not ready errors
    retry = {
      limit = 10;
      backoff = {
        duration = "10s";
        factor = 2;
        maxDuration = "5m";
      };
    };
  };
in
{
  # Gitea SecretStore - for KIND environments
  applications.gitea-secretstore = lib.mkIf isKind {
    namespace = "gitea";
    createNamespace = true;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = syncPolicyWithRetry;

    resources = mkSecretStore {
      name = "eso-store";
      namespace = "gitea";
    };

    yamls = [
      ''
        apiVersion: external-secrets.io/v1
        kind: ClusterSecretStore
        metadata:
          name: gitea
        spec:
          provider:
            kubernetes:
              auth:
                serviceAccount:
                  name: eso-store
                  namespace: gitea
              remoteNamespace: gitea
              server:
                caProvider:
                  key: ca.crt
                  name: kube-root-ca.crt
                  namespace: gitea
                  type: ConfigMap
      ''
    ];
  };

  # ArgoCD SecretStore - for KIND environments
  applications.argocd-secretstore = lib.mkIf isKind {
    namespace = "argocd";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = syncPolicyWithRetry;

    resources = mkSecretStore {
      name = "eso-store";
      namespace = "argocd";
    };

    yamls = [
      ''
        apiVersion: external-secrets.io/v1
        kind: ClusterSecretStore
        metadata:
          name: argocd
        spec:
          provider:
            kubernetes:
              auth:
                serviceAccount:
                  name: eso-store
                  namespace: argocd
              remoteNamespace: argocd
              server:
                caProvider:
                  key: ca.crt
                  name: kube-root-ca.crt
                  namespace: argocd
                  type: ConfigMap
      ''
    ];
  };

  # Default Namespace SecretStore - for KIND environments
  applications.default-secretstore = lib.mkIf isKind {
    namespace = "default";
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
    };

    syncPolicy = syncPolicyWithRetry;

    resources = mkSecretStore {
      name = "eso-store-default";
      namespace = "default";
      saName = "eso-store-default";
      resourceNames = [ "idpbuilder-cert" ];
    };

    yamls = [
      ''
        apiVersion: external-secrets.io/v1
        kind: ClusterSecretStore
        metadata:
          name: default-namespace
        spec:
          provider:
            kubernetes:
              auth:
                serviceAccount:
                  name: eso-store-default
                  namespace: default
              remoteNamespace: default
              server:
                caProvider:
                  key: ca.crt
                  name: kube-root-ca.crt
                  namespace: default
                  type: ConfigMap
      ''
    ];
  };
}
