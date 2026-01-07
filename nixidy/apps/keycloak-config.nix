# Keycloak Configuration Applications
# Keycloak secrets, clients, and config jobs
# Mirrors: cdk8s/charts/secrets/keycloak-secrets-chart.ts, apps/keycloak-clients-chart.ts, keycloak-config-chart.ts
{ config, lib, ... }:
let
  inherit (config) environmentType;
  inherit (config.cluster) ingressHost ingressPort;
  namespace = "keycloak";
  giteaNamespace = "gitea";
  defaultNamespace = "default";
  # Dynamic port suffix for URLs (empty for 443, :port otherwise)
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";
in
{
  # Keycloak Secrets - Creates Password generator, keycloak-config secret, and ClusterSecretStores
  # NOTE: Namespace owned by keycloak app (sync-wave -50)
  applications.keycloak-secrets = {
    inherit namespace;
    createNamespace = false;  # keycloak app owns the namespace

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-50";
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
      retry = {
        limit = 10;
        backoff = {
          duration = "5s";
          factor = 2;
          maxDuration = "3m";
        };
      };
    };

    # RBAC for keycloak namespace ClusterSecretStore
    resources = {
      serviceAccounts.eso-store-keycloak = {
        metadata.namespace = namespace;
      };

      roles.eso-store-keycloak = {
        metadata.namespace = namespace;
        rules = [
          {
            apiGroups = [ "" ];
            resources = [ "secrets" ];
            verbs = [ "get" "list" "watch" ];
          }
          {
            apiGroups = [ "authorization.k8s.io" ];
            resources = [ "selfsubjectrulesreviews" ];
            verbs = [ "create" ];
          }
        ];
      };

      roleBindings.eso-store-keycloak = {
        metadata.namespace = namespace;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "Role";
          name = "eso-store-keycloak";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "eso-store-keycloak";
          namespace = namespace;
        }];
      };
    };

    yamls = [
      # Password Generator for Keycloak credentials
      ''
        apiVersion: generators.external-secrets.io/v1alpha1
        kind: Password
        metadata:
          name: keycloak
          namespace: ${namespace}
        spec:
          length: 36
          digits: 5
          symbols: 5
          symbolCharacters: "/-+"
          noUpper: false
          allowRepeat: true
      ''
      # ExternalSecret: keycloak-config - uses Password generator
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: keycloak-config
          namespace: ${namespace}
        spec:
          refreshInterval: "0"
          target:
            name: keycloak-config
            template:
              metadata:
                labels:
                  cnoe.io/cli-secret: "true"
                  cnoe.io/package-name: keycloak
              engineVersion: v2
              data:
                KEYCLOAK_ADMIN_PASSWORD: "{{.KEYCLOAK_ADMIN_PASSWORD}}"
                KC_DB_USERNAME: keycloak
                KC_DB_PASSWORD: "{{.KC_DB_PASSWORD}}"
                POSTGRES_DB: keycloak
                POSTGRES_USER: keycloak
                POSTGRES_PASSWORD: "{{.KC_DB_PASSWORD}}"
                USER_PASSWORD: "{{.USER_PASSWORD}}"
          dataFrom:
            - sourceRef:
                generatorRef:
                  apiVersion: generators.external-secrets.io/v1alpha1
                  kind: Password
                  name: keycloak
              rewrite:
                - transform:
                    template: KEYCLOAK_ADMIN_PASSWORD
            - sourceRef:
                generatorRef:
                  apiVersion: generators.external-secrets.io/v1alpha1
                  kind: Password
                  name: keycloak
              rewrite:
                - transform:
                    template: KC_DB_PASSWORD
            - sourceRef:
                generatorRef:
                  apiVersion: generators.external-secrets.io/v1alpha1
                  kind: Password
                  name: keycloak
              rewrite:
                - transform:
                    template: USER_PASSWORD
      ''
      # ClusterSecretStore: keycloak (Kubernetes provider)
      ''
        apiVersion: external-secrets.io/v1
        kind: ClusterSecretStore
        metadata:
          name: keycloak
        spec:
          provider:
            kubernetes:
              remoteNamespace: ${namespace}
              server:
                caProvider:
                  type: ConfigMap
                  name: kube-root-ca.crt
                  namespace: ${namespace}
                  key: ca.crt
              auth:
                serviceAccount:
                  name: eso-store-keycloak
                  namespace: ${namespace}
      ''
    ];
  };

  # NOTE: gitea-secretstore, default-secretstore, and argocd-secretstore
  # are defined in secretstores.nix to avoid duplication

  # Keycloak Config Job - Creates realm, users, OIDC clients, and keycloak-clients secret
  # Mirrors: cdk8s/charts/platform/keycloak-config-chart.ts
  applications.keycloak-config = {
    inherit namespace;
    createNamespace = false;

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
        createNamespace = false;
        serverSideApply = true;
      };
    };

    resources = {
      # Keycloak realm config - used by Keycloak's realm import feature
      configMaps.keycloak-realm-config = {
        metadata = {
          inherit namespace;
          labels = {
            "app.kubernetes.io/component" = "configuration";
            "app.kubernetes.io/part-of" = "keycloak";
          };
        };
        data = {
          "cnoe-realm.json" = builtins.toJSON {
            realm = "cnoe";
            enabled = true;
            registrationAllowed = false;
            loginWithEmailAllowed = true;
            duplicateEmailsAllowed = false;
          };
        };
      };

      # ServiceAccount for keycloak-config job
      serviceAccounts.keycloak-config = {
        metadata.namespace = namespace;
      };

      # Role in keycloak namespace for creating secrets
      roles.keycloak-config-secrets = {
        metadata.namespace = namespace;
        rules = [{
          apiGroups = [ "" ];
          resources = [ "secrets" ];
          verbs = [ "get" "create" "update" "patch" ];
        }];
      };

      # RoleBinding in keycloak namespace
      roleBindings.keycloak-config-secrets = {
        metadata.namespace = namespace;
        subjects = [{
          kind = "ServiceAccount";
          name = "keycloak-config";
          namespace = namespace;
        }];
        roleRef = {
          kind = "Role";
          name = "keycloak-config-secrets";
          apiGroup = "rbac.authorization.k8s.io";
        };
      };

      # ConfigMap with OIDC client payloads
      configMaps.config-job = {
        metadata.namespace = namespace;
        data = {
          "client-scope-groups-payload.json" = builtins.toJSON {
            name = "groups";
            description = "groups a user belongs to";
            attributes = {
              "consent.screen.text" = "Access to groups a user belongs to.";
              "display.on.consent.screen" = "true";
              "include.in.token.scope" = "true";
              "gui.order" = "";
            };
            type = "default";
            protocol = "openid-connect";
          };
          "group-admin-payload.json" = builtins.toJSON { name = "admin"; };
          "group-base-user-payload.json" = builtins.toJSON { name = "base-user"; };
          "group-mapper-payload.json" = builtins.toJSON {
            protocol = "openid-connect";
            protocolMapper = "oidc-group-membership-mapper";
            name = "groups";
            config = {
              "claim.name" = "groups";
              "full.path" = "false";
              "id.token.claim" = "true";
              "access.token.claim" = "true";
              "userinfo.token.claim" = "true";
            };
          };
          "realm-payload.json" = builtins.toJSON { realm = "cnoe"; enabled = true; };
          "user-password.json" = builtins.toJSON {
            temporary = false;
            type = "password";
            value = "\${USER1_PASSWORD}";
          };
          "user-user1.json" = builtins.toJSON {
            username = "user1";
            email = "";
            firstName = "user";
            lastName = "one";
            requiredActions = [];
            emailVerified = false;
            groups = [ "/admin" ];
            enabled = true;
          };
          "user-user2.json" = builtins.toJSON {
            username = "user2";
            email = "";
            firstName = "user";
            lastName = "two";
            requiredActions = [];
            emailVerified = false;
            groups = [ "/base-user" ];
            enabled = true;
          };
          "argo-client-payload.json" = builtins.toJSON {
            protocol = "openid-connect";
            clientId = "argo-workflows";
            name = "Argo Workflows Client";
            description = "Used for Argo Workflows SSO";
            publicClient = false;
            authorizationServicesEnabled = false;
            serviceAccountsEnabled = false;
            implicitFlowEnabled = false;
            directAccessGrantsEnabled = true;
            standardFlowEnabled = true;
            frontchannelLogout = true;
            attributes = {
              saml_idp_initiated_sso_url_name = "";
              "oauth2.device.authorization.grant.enabled" = false;
              "oidc.ciba.grant.enabled" = false;
            };
            alwaysDisplayInConsole = false;
            rootUrl = "";
            baseUrl = "";
            redirectUris = [
              "https://${ingressHost}:8443/argo-workflows/oauth2/callback"
              "https://${ingressHost}/argo-workflows/oauth2/callback"
            ];
            webOrigins = [ "/*" ];
          };
          "backstage-client-payload.json" = builtins.toJSON {
            protocol = "openid-connect";
            clientId = "backstage";
            name = "Backstage Client";
            description = "Used for Backstage SSO";
            publicClient = false;
            authorizationServicesEnabled = false;
            serviceAccountsEnabled = false;
            implicitFlowEnabled = false;
            directAccessGrantsEnabled = true;
            standardFlowEnabled = true;
            frontchannelLogout = true;
            attributes = {
              saml_idp_initiated_sso_url_name = "";
              "oauth2.device.authorization.grant.enabled" = false;
              "oidc.ciba.grant.enabled" = false;
            };
            alwaysDisplayInConsole = false;
            rootUrl = "";
            baseUrl = "";
            redirectUris = [
              # Domain-based routing (primary)
              "https://backstage.${ingressHost}${portSuffix}/api/auth/keycloak-oidc/handler/frame"
              "https://backstage.${ingressHost}/api/auth/keycloak-oidc/handler/frame"
              # Local HMR development (frontend on localhost:3000, backend in K8s)
              "https://localhost:3000/api/auth/keycloak-oidc/handler/frame"
            ];
            webOrigins = [
              "https://backstage.${ingressHost}${portSuffix}"
              "https://backstage.${ingressHost}"
              # Local HMR development
              "https://localhost:3000"
            ];
          };
          "flipt-client-payload.json" = builtins.toJSON {
            protocol = "openid-connect";
            clientId = "flipt";
            name = "Flipt Feature Flag Management";
            description = "Used for Flipt Feature Flag UI SSO";
            publicClient = false;
            authorizationServicesEnabled = false;
            serviceAccountsEnabled = false;
            implicitFlowEnabled = false;
            directAccessGrantsEnabled = true;
            standardFlowEnabled = true;
            frontchannelLogout = true;
            attributes = {
              saml_idp_initiated_sso_url_name = "";
              "oauth2.device.authorization.grant.enabled" = false;
              "oidc.ciba.grant.enabled" = false;
            };
            alwaysDisplayInConsole = false;
            rootUrl = "";
            baseUrl = "";
            redirectUris = [
              # Domain-based routing (primary)
              "https://flipt.${ingressHost}${portSuffix}/auth/v1/method/oidc/keycloak/callback"
              "https://flipt.${ingressHost}/auth/v1/method/oidc/keycloak/callback"
              # Internal cluster for backchannel
              "http://flipt.feature-flags.svc.cluster.local:8080/auth/v1/method/oidc/keycloak/callback"
            ];
            webOrigins = [ "/*" ];
          };
          "headlamp-client-payload.json" = builtins.toJSON {
            protocol = "openid-connect";
            clientId = "headlamp";
            name = "Headlamp Kubernetes Dashboard";
            description = "Used for Headlamp Dashboard SSO";
            publicClient = false;
            authorizationServicesEnabled = false;
            serviceAccountsEnabled = false;
            implicitFlowEnabled = false;
            directAccessGrantsEnabled = true;
            standardFlowEnabled = true;
            frontchannelLogout = true;
            attributes = {
              saml_idp_initiated_sso_url_name = "";
              "oauth2.device.authorization.grant.enabled" = false;
              "oidc.ciba.grant.enabled" = false;
            };
            alwaysDisplayInConsole = false;
            rootUrl = "";
            baseUrl = "";
            redirectUris = [
              # Domain-based routing (primary)
              "https://headlamp.${ingressHost}${portSuffix}/oidc-callback"
              "https://headlamp.${ingressHost}/oidc-callback"
              # Local development
              "http://localhost:4466/oidc-callback"
              "http://localhost:8000/*"
            ];
            webOrigins = [ "/*" ];
          };
        };
      };
    };

    # Role and RoleBinding in argocd namespace (for reading ArgoCD admin secret)
    yamls = [
      ''
        apiVersion: rbac.authorization.k8s.io/v1
        kind: Role
        metadata:
          name: keycloak-config-argocd
          namespace: argocd
        rules:
          - apiGroups: [""]
            resources: ["secrets"]
            verbs: ["get"]
      ''
      ''
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        metadata:
          name: keycloak-config-argocd
          namespace: argocd
        subjects:
          - kind: ServiceAccount
            name: keycloak-config
            namespace: ${namespace}
        roleRef:
          kind: Role
          name: keycloak-config-argocd
          apiGroup: rbac.authorization.k8s.io
      ''
      # PostSync Job - Creates realm, users, OIDC clients, and keycloak-clients secret
      ''
        apiVersion: batch/v1
        kind: Job
        metadata:
          name: config
          namespace: ${namespace}
          annotations:
            argocd.argoproj.io/hook: PostSync
            argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded
        spec:
          activeDeadlineSeconds: 900
          backoffLimit: 10
          template:
            metadata:
              generateName: config
            spec:
              serviceAccountName: keycloak-config
              restartPolicy: Never
              volumes:
                - name: keycloak-config
                  secret:
                    secretName: keycloak-config
                - name: config-payloads
                  configMap:
                    name: config-job
              containers:
                - name: kubectl
                  image: docker.io/library/ubuntu:22.04
                  volumeMounts:
                    - name: keycloak-config
                      readOnly: true
                      mountPath: /var/secrets/
                    - name: config-payloads
                      readOnly: true
                      mountPath: /var/config/
                  command: ["/bin/bash", "-c"]
                  args:
                    - |
                      #!/bin/bash
                      set -ex -o pipefail

                      apt -qq update && apt -qq install curl jq -y

                      ADMIN_PASSWORD=$(cat /var/secrets/KEYCLOAK_ADMIN_PASSWORD)
                      USER1_PASSWORD=$(cat /var/secrets/USER_PASSWORD)

                      # Domain-based routing: no path prefix needed
                      KEYCLOAK_URL=http://keycloak.keycloak.svc.cluster.local:8080

                      KEYCLOAK_TOKEN=$(curl -sS  --fail-with-body -X POST -H "Content-Type: application/x-www-form-urlencoded" \
                        --data-urlencode "username=cnoe-admin" \
                        --data-urlencode "password=''${ADMIN_PASSWORD}" \
                        --data-urlencode "grant_type=password" \
                        --data-urlencode "client_id=admin-cli" \
                        ''${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token | jq -e -r '.access_token')

                      set +e

                      # Check if realm exists
                      curl --fail-with-body -H "Authorization: bearer ''${KEYCLOAK_TOKEN}"  "''${KEYCLOAK_URL}/admin/realms/cnoe"  &> /dev/null
                      REALM_EXISTS=$?
                      set -e

                      # Always need kubectl for secret creation
                      curl -sS -LO "https://dl.k8s.io/release/v1.28.3//bin/linux/amd64/kubectl"
                      chmod +x kubectl

                      patch_client_config() {
                        local client_name="$1"
                        local payload_file="$2"

                        if [ ! -f "$payload_file" ]; then
                          echo "payload file not found: $payload_file"
                          return 1
                        fi

                        local desired_redirects desired_weborigins
                        desired_redirects=$(jq -c '.redirectUris' "$payload_file")
                        desired_weborigins=$(jq -c '.webOrigins' "$payload_file")

                        local existing_client_id
                        existing_client_id=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -r --arg name "$client_name" '.[] | select(.clientId == $name) | .id' | head -1)

                        if [ -z "$existing_client_id" ] || [ "$existing_client_id" = "null" ]; then
                          echo "client ''\${client_name}' not found; creating"
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X POST --data @"$payload_file" \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/clients
                          existing_client_id=$(curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -r --arg name "$client_name" '.[] | select(.clientId == $name) | .id' | head -1)
                        fi

                        echo "ensuring redirectUris and webOrigins for client ''\${client_name}' (''\${existing_client_id}')"
                        local existing_json updated_json
                        existing_json=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${existing_client_id})
                        updated_json=$(echo "$existing_json" | jq --argjson redirects "$desired_redirects" --argjson origins "$desired_weborigins" '.redirectUris = $redirects | .webOrigins = $origins')

                        curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X PUT --data "$updated_json" \
                          ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${existing_client_id} >/dev/null

                        # Ensure groups scope is added to client (idempotent - no error if already exists)
                        echo "ensuring groups scope for client ''\${client_name}'"
                        local groups_scope_id
                        groups_scope_id=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -r '.[] | select(.name == "groups") | .id')
                        if [ -n "$groups_scope_id" ] && [ "$groups_scope_id" != "null" ]; then
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X PUT ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${existing_client_id}/default-client-scopes/''${groups_scope_id} 2>/dev/null || true
                        fi
                      }

                      # Helper function to ensure groups scope exists
                      ensure_groups_scope() {
                        echo "ensuring groups scope exists..."
                        local groups_scope_id
                        groups_scope_id=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -r '.[] | select(.name == "groups") | .id')

                        if [ -z "$groups_scope_id" ] || [ "$groups_scope_id" = "null" ]; then
                          echo "creating groups scope..."
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X POST --data @/var/config/client-scope-groups-payload.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes

                          groups_scope_id=$(curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -r '.[] | select(.name == "groups") | .id')

                          echo "adding group mapper to groups scope..."
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X POST --data @/var/config/group-mapper-payload.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes/''${groups_scope_id}/protocol-mappers/models
                        fi
                        echo "groups scope id: $groups_scope_id"
                      }

                      # Helper function to ensure groups exist
                      ensure_groups() {
                        echo "ensuring groups exist..."
                        local admin_group_id base_user_group_id

                        admin_group_id=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/groups | jq -r '.[] | select(.name == "admin") | .id')

                        if [ -z "$admin_group_id" ] || [ "$admin_group_id" = "null" ]; then
                          echo "creating admin group..."
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X POST --data @/var/config/group-admin-payload.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/groups
                        fi

                        base_user_group_id=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/groups | jq -r '.[] | select(.name == "base-user") | .id')

                        if [ -z "$base_user_group_id" ] || [ "$base_user_group_id" = "null" ]; then
                          echo "creating base-user group..."
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X POST --data @/var/config/group-base-user-payload.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/groups
                        fi
                      }

                      # Helper function to ensure users exist
                      ensure_users() {
                        echo "ensuring users exist..."

                        # Check/create user1
                        local user1_id
                        user1_id=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          "''${KEYCLOAK_URL}/admin/realms/cnoe/users?username=user1" | jq -r '.[0].id // empty')

                        if [ -z "$user1_id" ]; then
                          echo "creating user1..."
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X POST --data @/var/config/user-user1.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/users

                          user1_id=$(curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            "''${KEYCLOAK_URL}/admin/realms/cnoe/users?username=user1" | jq -r '.[0].id')

                          echo "setting user1 password..."
                          jq -r --arg pass ''${USER1_PASSWORD} '.value = $pass' /var/config/user-password.json > /tmp/user-password-to-be-applied.json
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X PUT --data @/tmp/user-password-to-be-applied.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/users/''${user1_id}/reset-password

                          echo "adding user1 to admin group..."
                          local admin_group_id
                          admin_group_id=$(curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/groups | jq -r '.[] | select(.name == "admin") | .id')
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X PUT ''${KEYCLOAK_URL}/admin/realms/cnoe/users/''${user1_id}/groups/''${admin_group_id}
                        fi

                        # Check/create user2
                        local user2_id
                        user2_id=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          "''${KEYCLOAK_URL}/admin/realms/cnoe/users?username=user2" | jq -r '.[0].id // empty')

                        if [ -z "$user2_id" ]; then
                          echo "creating user2..."
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X POST --data @/var/config/user-user2.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/users

                          user2_id=$(curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            "''${KEYCLOAK_URL}/admin/realms/cnoe/users?username=user2" | jq -r '.[0].id')

                          echo "setting user2 password..."
                          jq -r --arg pass ''${USER1_PASSWORD} '.value = $pass' /var/config/user-password.json > /tmp/user-password-to-be-applied.json
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X PUT --data @/tmp/user-password-to-be-applied.json \
                            ''${KEYCLOAK_URL}/admin/realms/cnoe/users/''${user2_id}/reset-password

                          echo "adding user2 to base-user group..."
                          local base_user_group_id
                          base_user_group_id=$(curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/groups | jq -r '.[] | select(.name == "base-user") | .id')
                          curl -sS -H "Content-Type: application/json" \
                            -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                            -X PUT ''${KEYCLOAK_URL}/admin/realms/cnoe/users/''${user2_id}/groups/''${base_user_group_id}
                        fi
                      }

                      # If realm exists, check if keycloak-clients secret exists
                      if [ $REALM_EXISTS -eq 0 ]; then
                        # Realm exists: ensure all resources are present (idempotent)
                        ensure_groups_scope
                        ensure_groups
                        ensure_users

                        # Ensure redirect URIs and web origins match the desired payloads
                        patch_client_config "argo-workflows" "/var/config/argo-client-payload.json"
                        patch_client_config "backstage" "/var/config/backstage-client-payload.json"
                        patch_client_config "flipt" "/var/config/flipt-client-payload.json"
                        patch_client_config "headlamp" "/var/config/headlamp-client-payload.json"

                        # Check if secret already exists
                        if ./kubectl -n keycloak get secret keycloak-clients &>/dev/null; then
                          echo "Realm and secret already exist; all resources reconciled"
                          exit 0
                        fi
                        echo "Realm exists but secret missing, recreating secret..."

                        # Get existing client secrets from Keycloak
                        KEYCLOAK_TOKEN=$(curl -sS  --fail-with-body -X POST -H "Content-Type: application/x-www-form-urlencoded" \
                          --data-urlencode "username=cnoe-admin" \
                          --data-urlencode "password=''${ADMIN_PASSWORD}" \
                          --data-urlencode "grant_type=password" \
                          --data-urlencode "client_id=admin-cli" \
                          ''${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token | jq -e -r '.access_token')

                        # Get Argo Workflows client secret
                        CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "argo-workflows") | .id')
                        ARGO_WORKFLOWS_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                        # Get Backstage client secret
                        CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "backstage") | .id')
                        BACKSTAGE_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                        # Get Flipt client secret
                        CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "flipt") | .id')
                        FLIPT_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                        # Get Headlamp client secret
                        CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "headlamp") | .id')
                        HEADLAMP_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                          -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                        # Get ArgoCD session token
                        ARGOCD_PASSWORD=$(./kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode }}')
                        ARGOCD_SESSION_TOKEN=$(curl -k -sS http://argocd-server.argocd.svc.cluster.local:443/api/v1/session -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"''${ARGOCD_PASSWORD}\"}" | jq -r .token)

                        # Create the secret
                        echo "
                      apiVersion: v1
                      kind: Secret
                      metadata:
                        name: keycloak-clients
                        namespace: keycloak
                      type: Opaque
                      stringData:
                        ARGO_WORKFLOWS_CLIENT_SECRET: ''${ARGO_WORKFLOWS_CLIENT_SECRET}
                        ARGO_WORKFLOWS_CLIENT_ID: argo-workflows
                        ARGOCD_SESSION_TOKEN: ''${ARGOCD_SESSION_TOKEN}
                        BACKSTAGE_CLIENT_SECRET: ''${BACKSTAGE_CLIENT_SECRET}
                        BACKSTAGE_CLIENT_ID: backstage
                        FLIPT_CLIENT_SECRET: ''${FLIPT_CLIENT_SECRET}
                        FLIPT_CLIENT_ID: flipt
                        HEADLAMP_CLIENT_SECRET: ''${HEADLAMP_CLIENT_SECRET}
                        HEADLAMP_CLIENT_ID: headlamp
                      " > /tmp/secret.yaml

                        ./kubectl apply -f /tmp/secret.yaml
                        exit 0
                      fi

                      echo "creating cnoe realm and groups"

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/realm-payload.json \
                        ''${KEYCLOAK_URL}/admin/realms

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/client-scope-groups-payload.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/group-admin-payload.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/groups

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/group-base-user-payload.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/groups

                      # Create scope mapper
                      echo 'adding group claim to tokens'
                      CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" -X GET  ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/group-mapper-payload.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes/''${CLIENT_SCOPE_GROUPS_ID}/protocol-mappers/models

                      echo "creating test users"
                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/user-user1.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/users

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/user-user2.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/users

                      USER1ID=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" "''${KEYCLOAK_URL}/admin/realms/cnoe/users?lastName=one" | jq -r '.[0].id')
                      USER2ID=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" "''${KEYCLOAK_URL}/admin/realms/cnoe/users?lastName=two" | jq -r '.[0].id')

                      echo "setting user passwords"
                      jq -r --arg pass ''${USER1_PASSWORD}  '.value = $pass' /var/config/user-password.json > /tmp/user-password-to-be-applied.json

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X PUT --data @/tmp/user-password-to-be-applied.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/users/''${USER1ID}/reset-password

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X PUT --data @/tmp/user-password-to-be-applied.json \
                        ''${KEYCLOAK_URL}/admin/realms/cnoe/users/''${USER2ID}/reset-password

                      echo "creating Argo Workflows client"
                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                          -X POST --data @/var/config/argo-client-payload.json \
                          ''${KEYCLOAK_URL}/admin/realms/cnoe/clients

                      CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "argo-workflows") | .id')
                      CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET  ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')

                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X PUT  ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID}/default-client-scopes/''${CLIENT_SCOPE_GROUPS_ID}

                      ARGO_WORKFLOWS_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                      -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                      -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                      echo "creating Backstage client"
                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/backstage-client-payload.json \
                          ''${KEYCLOAK_URL}/admin/realms/cnoe/clients

                      CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "backstage") | .id')

                      CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" -X GET  ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')
                      curl -sS -H "Content-Type: application/json" -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" -X PUT  ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID}/default-client-scopes/''${CLIENT_SCOPE_GROUPS_ID}

                      BACKSTAGE_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                      echo "creating Flipt client"
                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/flipt-client-payload.json \
                          ''${KEYCLOAK_URL}/admin/realms/cnoe/clients

                      CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "flipt") | .id')

                      CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" -X GET  ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')
                      curl -sS -H "Content-Type: application/json" -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" -X PUT  ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID}/default-client-scopes/''${CLIENT_SCOPE_GROUPS_ID}

                      FLIPT_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                      echo "creating Headlamp client"
                      curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X POST --data @/var/config/headlamp-client-payload.json \
                          ''${KEYCLOAK_URL}/admin/realms/cnoe/clients

                      CLIENT_ID=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients | jq -e -r  '.[] | select(.clientId == "headlamp") | .id')

                      CLIENT_SCOPE_GROUPS_ID=$(curl -sS -H "Content-Type: application/json" -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" -X GET  ''${KEYCLOAK_URL}/admin/realms/cnoe/client-scopes | jq -e -r  '.[] | select(.name == "groups") | .id')
                      curl -sS -H "Content-Type: application/json" -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" -X PUT  ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID}/default-client-scopes/''${CLIENT_SCOPE_GROUPS_ID}

                      HEADLAMP_CLIENT_SECRET=$(curl -sS -H "Content-Type: application/json" \
                        -H "Authorization: bearer ''${KEYCLOAK_TOKEN}" \
                        -X GET ''${KEYCLOAK_URL}/admin/realms/cnoe/clients/''${CLIENT_ID} | jq -e -r '.secret')

                      ARGOCD_PASSWORD=$(./kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode }}')

                      ARGOCD_SESSION_TOKEN=$(curl -k -sS http://argocd-server.argocd.svc.cluster.local:443/api/v1/session -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"''${ARGOCD_PASSWORD}\"}" | jq -r .token)

                      echo "
                      apiVersion: v1
                      kind: Secret
                      metadata:
                        name: keycloak-clients
                        namespace: keycloak
                      type: Opaque
                      stringData:
                        ARGO_WORKFLOWS_CLIENT_SECRET: ''${ARGO_WORKFLOWS_CLIENT_SECRET}
                        ARGO_WORKFLOWS_CLIENT_ID: argo-workflows
                        ARGOCD_SESSION_TOKEN: ''${ARGOCD_SESSION_TOKEN}
                        BACKSTAGE_CLIENT_SECRET: ''${BACKSTAGE_CLIENT_SECRET}
                        BACKSTAGE_CLIENT_ID: backstage
                        FLIPT_CLIENT_SECRET: ''${FLIPT_CLIENT_SECRET}
                        FLIPT_CLIENT_ID: flipt
                        HEADLAMP_CLIENT_SECRET: ''${HEADLAMP_CLIENT_SECRET}
                        HEADLAMP_CLIENT_ID: headlamp
                      " > /tmp/secret.yaml

                      ./kubectl apply -f /tmp/secret.yaml
      ''
    ];
  };
}
