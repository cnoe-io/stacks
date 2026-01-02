# Argo Workflows - Workflow Engine
# Provides workflow orchestration for CI/CD and batch processing.
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# Includes ref-implementation features:
# - SSO integration with Keycloak OIDC
# - Path-based ingress routing (/argo-workflows)
# - Admin ServiceAccount with cluster-admin for RBAC
# - ExternalSecret for Keycloak client credentials
#
# Mirrors: cdk8s Argo Workflows configurations + ref-implementation
{ config, lib, charts, ... }:
let
  namespace = "argo";
  isKind = config.environmentType == "kind";
  ingressHost = config.cluster.ingressHost;
  ingressPort = config.cluster.ingressPort;
  keycloakUrl = config.keycloak.url;
  keycloakRealm = config.keycloak.realm;
in
{
  config = {
    applications.argo-workflows = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "50";
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

      # Use nixhelm for pre-rendered Helm chart
      helm.releases.argo-workflows = {
        chart = charts.argoproj.argo-workflows;
        values = {
          controller = {
            workflowNamespaces = [ namespace ];
          };
          server = {
            serviceType = "ClusterIP";
            # SSO + client auth modes for KIND (from ref-implementation)
            extraArgs = lib.mkIf isKind [
              "--auth-mode=client"
              "--auth-mode=sso"
              "--secure=false"
              "--loglevel=info"
              "--log-format=text"
            ];
            # BASE_HREF for path-based routing
            extraEnv = lib.mkIf isKind [
              { name = "BASE_HREF"; value = "/argo-workflows/"; }
            ];
          };
          workflow = {
            serviceAccount = {
              create = true;
            };
          };
        };
      };

      # Additional resources for KIND environment (from ref-implementation)
      resources = lib.mkIf isKind {
        # Ingress for path-based routing
        ingresses.argo-workflows-ingress = {
          metadata = {
            inherit namespace;
            annotations = {
              "nginx.ingress.kubernetes.io/use-regex" = "true";
              "nginx.ingress.kubernetes.io/rewrite-target" = "/$2";
            };
          };
          spec = {
            ingressClassName = "nginx";
            rules = [
              {
                host = "localhost";
                http.paths = [{
                  path = "/argo-workflows(/|$)(.*)";
                  pathType = "ImplementationSpecific";
                  backend.service = {
                    name = "argo-server";
                    port.name = "web";
                  };
                }];
              }
              {
                host = ingressHost;
                http.paths = [{
                  path = "/argo-workflows(/|$)(.*)";
                  pathType = "ImplementationSpecific";
                  backend.service = {
                    name = "argo-server";
                    port.name = "web";
                  };
                }];
              }
            ];
          };
        };

        # Admin ServiceAccount for RBAC-enabled workflows
        serviceAccounts.admin = {
          metadata = {
            inherit namespace;
            annotations = {
              "workflows.argoproj.io/rbac-rule" = "'admin' in groups";
              "workflows.argoproj.io/rbac-rule-precedence" = "10";
            };
          };
        };

        # ClusterRoleBinding for admin SA
        clusterRoleBindings.argo-admin = {
          metadata.name = "argo-admin";
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "cluster-admin";
          };
          subjects = [{
            kind = "ServiceAccount";
            name = "admin";
            inherit namespace;
          }];
        };
      };

      # YAML resources for CRDs and complex configs (KIND only)
      yamls = lib.mkIf isKind [
        # ConfigMap for SSO configuration
        ''
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: workflow-controller-configmap
            namespace: ${namespace}
          data:
            config: |
              sso:
                insecureSkipVerify: true
                issuer: ${keycloakUrl}/realms/${keycloakRealm}
                clientId:
                  name: keycloak-oidc
                  key: client-id
                clientSecret:
                  name: keycloak-oidc
                  key: secret-key
                redirectUrl: https://${ingressHost}:${toString ingressPort}/argo-workflows/oauth2/callback
                rbac:
                  enabled: true
                scopes:
                  - openid
                  - profile
                  - email
                  - groups
              nodeEvents:
                enabled: false
        ''

        # ExternalSecret for Keycloak OIDC credentials
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: keycloak-oidc
            namespace: ${namespace}
          spec:
            secretStoreRef:
              name: keycloak
              kind: ClusterSecretStore
            target:
              name: keycloak-oidc
            data:
              - secretKey: client-id
                remoteRef:
                  key: keycloak-clients
                  property: ARGO_WORKFLOWS_CLIENT_ID
              - secretKey: secret-key
                remoteRef:
                  key: keycloak-clients
                  property: ARGO_WORKFLOWS_CLIENT_SECRET
        ''

        # Service account token secret for admin
        ''
          apiVersion: v1
          kind: Secret
          metadata:
            name: admin.service-account-token
            namespace: ${namespace}
            annotations:
              kubernetes.io/service-account.name: admin
          type: kubernetes.io/service-account-token
        ''
      ];
    };
  };
}
