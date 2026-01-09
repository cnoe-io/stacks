# Backstage Secrets and Configuration
# External Secrets for sensitive data, ConfigMap for non-sensitive config
# Mirrors: cdk8s/charts/secrets/backstage-secrets-chart.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost ingressPort name;
  inherit (config.gitea) serviceName internalPort defaultOwner;
  giteaNamespace = config.gitea.namespace;
  namespace = "backstage";
  isKind = environmentType == "kind";
  clusterSuffix = if name != "" then "-${name}" else "";
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";

  # Service URLs (non-sensitive configuration)
  backstageUrl = "https://backstage.${ingressHost}${portSuffix}";
  argocdUrl = "https://argocd.${ingressHost}${portSuffix}";
  argoWorkflowsUrl = "https://${ingressHost}${portSuffix}/argo-workflows";
  giteaUrl = "https://gitea.${ingressHost}${portSuffix}";
  giteaInternalUrl = "http://${serviceName}.${giteaNamespace}.svc.cluster.local:${toString internalPort}";
  keycloakMetadataUrl = "https://keycloak.${ingressHost}${portSuffix}/realms/cnoe/.well-known/openid-configuration";
  kargoUrl = "https://kargo.${ingressHost}${portSuffix}";
  # Catalog URL follows idpBuilder naming: cnoe://<package>/<path> -> idpbuilder-<cluster>-<package>-<path>
  # Since we use cnoe://backstage-templates/entities, the Gitea repo is backstage-templates-entities
  # Uses /raw/branch/main/ for raw content (not /src/branch/main/ which returns HTML)
  catalogUrl = "https://gitea.${ingressHost}${portSuffix}/${defaultOwner}/idpbuilder${clusterSuffix}-backstage-templates-entities/raw/branch/main/catalog-info.yaml";

  # Internal service URLs
  postgresHost = "postgresql.${namespace}.svc.cluster.local";
  agentForgeUrl = "http://supervisor.ai-platform-engineering.svc.cluster.local:8000";
  # Flipt provides OpenFeature-compliant gRPC API on port 9000
  fliptHost = "flipt.feature-flags.svc.cluster.local";
in
{
  config = lib.mkIf isKind {
    # Backstage Secrets App
    applications.backstage-secrets = {
      inherit namespace;
      createNamespace = false;  # Created by backstage.nix

      annotations = {
        # Sync-wave -35: After keycloak-config (-50 to -40) which creates keycloak-clients secret
        # but before backstage deployment (100)
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
        # ConfigMap: Kubernetes-specific Backstage configuration
        # Mounted at /etc/backstage/ and loaded after baked configs
        # Following Backstage best practice: config independent from image
        # ============================================================
        ''
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: backstage-app-config
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: backstage
              app.kubernetes.io/component: config
          data:
            app-config.yaml: |
              # Kubernetes environment configuration for Backstage
              # Loaded after app-config.yaml from the image (provides auth, database, integrations)

              app:
                baseUrl: ${backstageUrl}

              backend:
                baseUrl: ${backstageUrl}
                listen: ':7007'
                reading:
                  allow:
                    - host: 'gitea.${ingressHost}${portSuffix}'
                    - host: '*.${ingressHost}${portSuffix}'
                database:
                  client: pg
                  connection:
                    host: ${postgresHost}
                    port: 5432
                    user: ''${POSTGRES_USER}
                    password: ''${POSTGRES_PASSWORD}

              auth:
                environment: production
                session:
                  secret: ''${BACKSTAGE_SESSION_SECRET}
                providers:
                  guest:
                    dangerouslyAllowOutsideDevelopment: true
                  keycloak-oidc:
                    production:
                      metadataUrl: ''${KEYCLOAK_NAME_METADATA}
                      clientId: backstage
                      clientSecret: ''${KEYCLOAK_CLIENT_SECRET}
                      prompt: auto

              # Proxy endpoints
              proxy:
                endpoints:
                  '/agent-forge':
                    target: ${agentForgeUrl}
                    changeOrigin: true
                    secure: false
                    pathRewrite:
                      '^/api/proxy/agent-forge/?': '/'
                    credentials: 'dangerously-allow-unauthenticated'
                    headers:
                      X-Custom-Source: 'backstage'
                    allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
                    allowedHeaders: ['Authorization', 'Content-Type']

              # Feature Flags - Using Flipt (OpenFeature-compliant gRPC API)
              # Flagd has been deprecated in favor of Flipt-only architecture
              featureFlags:
                flipt:
                  host: ${fliptHost}
                  port: 9000
                  tls: false
                frontend:
                  baseUrl: /api/feature-flags
                  pollInterval: 30000

              # Agent Forge / CAIPE
              agentForge:
                baseUrl: /api/proxy/agent-forge
                botName: 'CAIPE'
                useOpenIDToken: false
                enableStreaming: false
                requestTimeout: 300
                headerTitle: 'CAIPE'
                headerSubtitle: 'AI Platform Engineer Assistant'
                inputPlaceholder: 'Ask CAIPE anything...'

              # Integrations (credentials from environment variables)
              # Host includes port for URL matching in catalog locations
              integrations:
                github:
                  - host: github.com
                    # GitHub App authentication (higher rate limits, better for orgs)
                    apps:
                      - appId: ''${GITHUB_APP_ID}
                        clientId: ''${GITHUB_CLIENT_ID}
                        clientSecret: ''${GITHUB_CLIENT_SECRET}
                        privateKey: ''${GITHUB_PRIVATE_KEY}
                        webhookSecret: ''${GITHUB_WEBHOOK_SECRET}
                gitea:
                  - host: gitea.${ingressHost}${portSuffix}
                    baseUrl: ${giteaUrl}
                    apiBaseUrl: ${giteaUrl}/api/v1
                    username: ''${GITEA_USERNAME}
                    password: ''${GITEA_PASSWORD}

              # Catalog configuration
              # Global rules apply to all dynamically registered locations
              catalog:
                rules:
                  - allow: [Component, System, API, Resource, Location, Template, User, Group]
                # GitHub catalog providers for autodiscovery
                # Discovers catalog-info.yaml files in repositories
                providers:
                  github:
                    # Personal account - vpittamp
                    vpittamp:
                      organization: 'vpittamp'
                      catalogPath: '/catalog-info.yaml'
                      filters:
                        branch: 'main'
                        repository: '.*'
                      schedule:
                        frequency: { minutes: 30 }
                        timeout: { minutes: 3 }
                    # Organization - PittampalliOrg
                    pittampalliorg:
                      organization: 'PittampalliOrg'
                      catalogPath: '/catalog-info.yaml'
                      filters:
                        branch: 'main'
                        repository: '.*'
                      schedule:
                        frequency: { minutes: 30 }
                        timeout: { minutes: 3 }
                locations:
                  - type: url
                    target: ${catalogUrl}
                    rules:
                      - allow: [Component, System, API, Resource, Location, Template, User, Group]
                  # Keep local examples for fallback
                  - type: file
                    target: ./examples/entities.yaml
                  - type: file
                    target: ./examples/template/template.yaml
                    rules:
                      - allow: [Template]
                  - type: file
                    target: ./examples/org.yaml
                    rules:
                      - allow: [User, Group]

              # ArgoCD integration
              # Instance name must match templates' argoInstance field
              # Uses admin credentials from argocd-credentials secret
              argocd:
                baseUrl: ${argocdUrl}
                username: admin
                password: ''${ARGOCD_ADMIN_PASSWORD}
                appLocatorMethods:
                  - type: 'config'
                    instances:
                      - name: in-cluster
                        url: ${argocdUrl}
                        username: admin
                        password: ''${ARGOCD_ADMIN_PASSWORD}

              # Kargo URL for templates
              kargo:
                baseUrl: ${kargoUrl}

              # Dapr Configuration plugin settings
              # Connects to Dapr sidecar for configuration management
              # See: https://docs.dapr.io/developing-applications/building-blocks/configuration/
              daprConfiguration:
                host: localhost  # Dapr sidecar runs as localhost in the pod
                port: 3500       # Dapr HTTP port
                storeName: configstore  # Dapr configuration component name

              # Kubernetes plugin configuration
              # Enables viewing K8s resources (pods, deployments, etc.) for catalog components
              # Uses the Backstage service account to connect to the local cluster
              kubernetes:
                serviceLocatorMethod:
                  type: 'multiTenant'
                clusterLocatorMethods:
                  - type: 'config'
                    clusters:
                      - name: local-cluster
                        url: https://kubernetes.default.svc
                        authProvider: 'serviceAccount'
                        skipTLSVerify: true
                        skipMetricsLookup: true
                customResources:
                  # ArgoCD Applications
                  - group: 'argoproj.io'
                    apiVersion: 'v1alpha1'
                    plural: 'applications'
                  # Argo Workflows
                  - group: 'argoproj.io'
                    apiVersion: 'v1alpha1'
                    plural: 'workflows'
                  # Kargo Stages
                  - group: 'kargo.akuity.io'
                    apiVersion: 'v1alpha1'
                    plural: 'stages'

              # TechDocs configuration
              # Using 'local' builder - mkdocs-techdocs-core installed in container
              # generator.runIn: 'local' uses mkdocs directly (not Docker)
              # For production, configure a publisher (awsS3, googleGcs, azureBlobStorage)
              techdocs:
                builder: 'local'
                generator:
                  runIn: 'local'
                publisher:
                  type: 'local'

              # Permission framework - disabled for development
              # Enable and configure policies for production
              permission:
                enabled: false
        ''

        # ============================================================
        # ExternalSecret: Sensitive data only
        # ============================================================
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: backstage-secrets
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
              # Using BACKSTAGE-GITHUB-APP JSON secret with JSONPath extraction
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

        # ============================================================
        # Docker registry credentials
        # ============================================================

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
