# Backstage Secrets
# External Secrets for main Backstage namespace
# Mirrors: cdk8s/charts/secrets/backstage-secrets-chart.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost ingressPort name;
  namespace = "backstage";
  isKind = environmentType == "kind";
  clusterSuffix = if name != "" then "-${name}" else "";
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";
in
{
  config = lib.mkIf isKind {
    # Backstage Secrets App
    applications.backstage-secrets = {
      inherit namespace;
      createNamespace = false;  # Created by backstage.nix

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-70";  # Before backstage deployment
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
        retry = {
          limit = 10;
          backoff = {
            duration = "5s";
            factor = 2;
            maxDuration = "3m";
          };
        };
      };

      yamls = [
        # backstage-env-vars - uses keycloak ClusterSecretStore for OIDC + Azure for stable passwords
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: backstage-oidc
            namespace: ${namespace}
          spec:
            refreshInterval: 1m
            secretStoreRef:
              kind: ClusterSecretStore
              name: keycloak
            target:
              name: backstage-env-vars
              template:
                engineVersion: v2
                data:
                  BACKSTAGE_FRONTEND_URL: "https://backstage.${ingressHost}${portSuffix}"
                  POSTGRES_HOST: "postgresql.${namespace}.svc.cluster.local"
                  POSTGRES_PORT: "5432"
                  POSTGRES_DB: backstage
                  POSTGRES_USER: backstage
                  POSTGRES_PASSWORD: "{{.POSTGRES_PASSWORD}}"
                  BACKSTAGE_SESSION_SECRET: "{{.SESSION_SECRET}}"
                  ARGO_WORKFLOWS_URL: "https://${ingressHost}${portSuffix}/argo-workflows"
                  ARGO_CD_URL: "https://argocd.${ingressHost}${portSuffix}"
                  ARGOCD_AUTH_TOKEN: "argocd.token={{.ARGOCD_SESSION_TOKEN}}"
                  KEYCLOAK_NAME_METADATA: "https://keycloak.${ingressHost}${portSuffix}/realms/cnoe/.well-known/openid-configuration"
                  KEYCLOAK_CLIENT_SECRET: "{{.BACKSTAGE_CLIENT_SECRET}}"
                  GITEA_URL: "https://gitea.${ingressHost}${portSuffix}"
                  GITEA_URL_NO_PORT: "https://gitea.${ingressHost}"
                  GITEA_HOST: "gitea.${ingressHost}${portSuffix}"
                  GITEA_HOST_NO_PORT: "gitea.${ingressHost}"
                  CATALOG_URL: "https://gitea.${ingressHost}${portSuffix}/giteaAdmin/idpbuilder${clusterSuffix}-backstage-templates-entities/src/branch/main/catalog-info.yaml"
                  KARGO_URL: "https://kargo.${ingressHost}${portSuffix}"
                  AGENT_FORGE_URL: "http://k8s-agent.kagent:8080"
            data:
              # OIDC tokens from keycloak ClusterSecretStore
              - secretKey: ARGOCD_SESSION_TOKEN
                remoteRef:
                  key: keycloak-clients
                  property: ARGOCD_SESSION_TOKEN
              - secretKey: BACKSTAGE_CLIENT_SECRET
                remoteRef:
                  key: keycloak-clients
                  property: BACKSTAGE_CLIENT_SECRET
              # Stable passwords from Azure Key Vault
              - secretKey: POSTGRES_PASSWORD
                sourceRef:
                  storeRef:
                    name: azure-keyvault-store
                    kind: ClusterSecretStore
                remoteRef:
                  key: BACKSTAGE-POSTGRES-PASSWORD
              - secretKey: SESSION_SECRET
                sourceRef:
                  storeRef:
                    name: azure-keyvault-store
                    kind: ClusterSecretStore
                remoteRef:
                  key: BACKSTAGE-SESSION-SECRET
        ''
        # ghcr-dockercfg - for pulling images from GHCR
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: ghcr-dockercfg-external
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: ghcr-dockercfg
              app.kubernetes.io/part-of: backstage
            annotations:
              argocd.argoproj.io/sync-wave: "-10"
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: ghcr-dockercfg
              creationPolicy: Owner
              template:
                type: kubernetes.io/dockerconfigjson
                data:
                  .dockerconfigjson: |
                    {
                      "auths": {
                        "ghcr.io": {
                          "username": "pittampalliorg",
                          "password": "{{ .pat }}",
                          "auth": "{{ printf "%s:%s" "pittampalliorg" .pat | b64enc }}"
                        }
                      }
                    }
            data:
              - secretKey: pat
                remoteRef:
                  key: GITHUB-PAT
        ''
        # gitea-dockercfg - uses gitea ClusterSecretStore (Kubernetes provider)
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: gitea-dockercfg-external
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: gitea-dockercfg
              app.kubernetes.io/part-of: backstage
            annotations:
              argocd.argoproj.io/sync-wave: "-10"
          spec:
            refreshInterval: "0"
            secretStoreRef:
              kind: ClusterSecretStore
              name: gitea
            target:
              name: gitea-dockercfg
              creationPolicy: Owner
              template:
                type: kubernetes.io/dockerconfigjson
                data:
                  .dockerconfigjson: |
                    {
                      "auths": {
                        "gitea.${ingressHost}:8443": {
                          "username": "{{ .username }}",
                          "password": "{{ .password }}",
                          "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
                        },
                        "gitea${clusterSuffix}.tail286401.ts.net": {
                          "username": "{{ .username }}",
                          "password": "{{ .password }}",
                          "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
                        }
                      }
                    }
            data:
              - secretKey: username
                remoteRef:
                  key: gitea-credential
                  property: username
              - secretKey: password
                remoteRef:
                  key: gitea-credential
                  property: password
        ''
        # gitea-credentials - for Backstage to access Gitea API
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: gitea-credentials
            namespace: ${namespace}
          spec:
            refreshInterval: "0"
            secretStoreRef:
              kind: ClusterSecretStore
              name: gitea
            target:
              name: gitea-credentials
            data:
              - secretKey: GITEA_USERNAME
                remoteRef:
                  key: gitea-credential
                  property: username
              - secretKey: GITEA_PASSWORD
                remoteRef:
                  key: gitea-credential
                  property: password
        ''
        # argocd-credentials - for Backstage to access ArgoCD
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: argocd-credentials
            namespace: ${namespace}
          spec:
            refreshInterval: "0"
            secretStoreRef:
              kind: ClusterSecretStore
              name: argocd
            target:
              name: argocd-credentials
            data:
              - secretKey: ARGOCD_ADMIN_PASSWORD
                remoteRef:
                  key: argocd-initial-admin-secret
                  property: password
        ''
      ];
    };
  };
}
