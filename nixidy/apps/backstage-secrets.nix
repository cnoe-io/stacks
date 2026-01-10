# Backstage Secrets
# External Secrets for sensitive data across all Backstage stage namespaces
# ConfigMap (app-config.yaml) is now managed by Kargo via backstage-config repository
#
# Previous version: cdk8s/charts/secrets/backstage-secrets-chart.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost ingressPort name;
  inherit (config.gitea) serviceName internalPort defaultOwner;
  giteaNamespace = config.gitea.namespace;
  isKind = environmentType == "kind";
  clusterSuffix = if name != "" then "-${name}" else "";
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";

  # All namespaces where Backstage may be deployed
  allNamespaces = [ "backstage" "backstage-dev" "backstage-staging" ];

  # Service URLs (used in ExternalSecret templates)
  keycloakMetadataUrl = "https://keycloak.${ingressHost}${portSuffix}/realms/cnoe/.well-known/openid-configuration";

  # Helper to generate ExternalSecrets for a given namespace
  mkSecretsApp = ns:
    let
      postgresHost = "postgresql.${ns}.svc.cluster.local";
    in {
      "backstage-secrets-${ns}" = {
        namespace = ns;
        createNamespace = false;

        annotations = {
          "argocd.argoproj.io/sync-wave" = "-35";
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
          # ============================================================
          # ExternalSecret: Sensitive data only (no ConfigMap)
          # ConfigMap is managed by Kargo via backstage-config repository
          # ============================================================
          ''
            apiVersion: external-secrets.io/v1
            kind: ExternalSecret
            metadata:
              name: backstage-secrets
              namespace: ${ns}
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
                    # Database credentials
                    POSTGRES_HOST: "${postgresHost}"
                    POSTGRES_PORT: "5432"
                    POSTGRES_DB: "backstage"
                    POSTGRES_USER: "backstage"
                    POSTGRES_PASSWORD: "{{.POSTGRES_PASSWORD}}"
                    # Session secret
                    BACKSTAGE_SESSION_SECRET: "{{.SESSION_SECRET}}"
                    # OIDC/Auth credentials
                    KEYCLOAK_NAME_METADATA: "${keycloakMetadataUrl}"
                    KEYCLOAK_CLIENT_SECRET: "{{.BACKSTAGE_CLIENT_SECRET}}"
                    ARGOCD_AUTH_TOKEN: "argocd.token={{.ARGOCD_SESSION_TOKEN}}"
                    # GitHub App credentials for integrations and catalog discovery
                    GITHUB_APP_ID: "{{.GITHUB_APP_ID}}"
                    GITHUB_CLIENT_ID: "{{.GITHUB_CLIENT_ID}}"
                    GITHUB_CLIENT_SECRET: "{{.GITHUB_CLIENT_SECRET}}"
                    GITHUB_PRIVATE_KEY: "{{.GITHUB_PRIVATE_KEY}}"
                    GITHUB_WEBHOOK_SECRET: "{{.GITHUB_WEBHOOK_SECRET}}"
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
                # GitHub App credentials for integrations and catalog discovery
                - secretKey: GITHUB_APP_ID
                  sourceRef:
                    storeRef:
                      name: azure-keyvault-store
                      kind: ClusterSecretStore
                  remoteRef:
                    key: BACKSTAGE-GITHUB-APP
                    property: app-id
                - secretKey: GITHUB_CLIENT_ID
                  sourceRef:
                    storeRef:
                      name: azure-keyvault-store
                      kind: ClusterSecretStore
                  remoteRef:
                    key: BACKSTAGE-GITHUB-APP
                    property: client-id
                - secretKey: GITHUB_CLIENT_SECRET
                  sourceRef:
                    storeRef:
                      name: azure-keyvault-store
                      kind: ClusterSecretStore
                  remoteRef:
                    key: BACKSTAGE-GITHUB-APP
                    property: client-secret
                - secretKey: GITHUB_PRIVATE_KEY
                  sourceRef:
                    storeRef:
                      name: azure-keyvault-store
                      kind: ClusterSecretStore
                  remoteRef:
                    key: BACKSTAGE-GITHUB-APP
                    property: private-key
                - secretKey: GITHUB_WEBHOOK_SECRET
                  sourceRef:
                    storeRef:
                      name: azure-keyvault-store
                      kind: ClusterSecretStore
                  remoteRef:
                    key: BACKSTAGE-GITHUB-APP
                    property: webhook-secret
          ''

          # ghcr-dockercfg - for pulling images from GHCR
          ''
            apiVersion: external-secrets.io/v1
            kind: ExternalSecret
            metadata:
              name: ghcr-dockercfg-external
              namespace: ${ns}
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
              namespace: ${ns}
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
              namespace: ${ns}
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
              namespace: ${ns}
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
in
{
  config = lib.mkIf isKind {
    # Generate secrets applications for all namespaces
    applications = lib.foldl' (acc: ns: acc // (mkSecretsApp ns)) {} allNamespaces;
  };
}
