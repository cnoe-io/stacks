# Feature Flags Applications
# Flipt management UI and Flagd sidecar
# Mirrors: cdk8s/charts/infra/flipt-chart.ts
# Uses domain-based routing for all services
{ config, lib, ... }:
let
  inherit (config.cluster) ingressHost ingressPort name;
  namespace = "feature-flags";
  clusterSuffix = if name != "" then "-${name}" else "";
  portSuffix = if ingressPort == 443 then "" else ":${toString ingressPort}";
  fliptHost = "flipt.${ingressHost}";
  giteaInternalHost = "my-gitea-http.gitea.svc.cluster.local:3000";
in
{
  # Feature Flags Namespace
  applications.feature-flags-namespace = {
    inherit namespace;
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
      namespaces.${namespace} = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "nixidy";
          "app.kubernetes.io/component" = "feature-flags";
          "app.kubernetes.io/part-of" = "platform";
        };
      };
    };
  };

  # Feature Flags Secrets
  applications.feature-flags-secrets = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      # After keycloak-config (-50 to -40) which creates keycloak-clients secret
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
      # flipt-oidc - uses keycloak ClusterSecretStore for OIDC client secret
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: flipt-oidc
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: flipt
            app.kubernetes.io/component: secrets
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: 1m
          secretStoreRef:
            kind: ClusterSecretStore
            name: keycloak
          target:
            name: flipt-oidc
            creationPolicy: Owner
            template:
              type: Opaque
              data:
                FLIPT_AUTHENTICATION_METHODS_OIDC_PROVIDERS_KEYCLOAK_CLIENT_SECRET: "{{ .FLIPT_CLIENT_SECRET }}"
          data:
            - secretKey: FLIPT_CLIENT_SECRET
              remoteRef:
                key: keycloak-clients
                property: FLIPT_CLIENT_SECRET
      ''
      # flipt-git-credentials - uses gitea ClusterSecretStore for Git access
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: flipt-git-credentials
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: flipt
            app.kubernetes.io/component: secrets
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: "0"
          secretStoreRef:
            kind: ClusterSecretStore
            name: gitea
          target:
            name: flipt-git-credentials
            creationPolicy: Owner
            template:
              type: Opaque
              data:
                # Flipt env var naming: FLIPT_<section>_<key> in UPPER_SNAKE_CASE
                # storage.default.authentication.basic.username -> FLIPT_STORAGE_DEFAULT_AUTHENTICATION_BASIC_USERNAME
                FLIPT_STORAGE_DEFAULT_AUTHENTICATION_BASIC_USERNAME: "{{ .username }}"
                FLIPT_STORAGE_DEFAULT_AUTHENTICATION_BASIC_PASSWORD: "{{ .password }}"
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
      # flipt-db-credentials - uses Azure Key Vault for stable secrets
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: flipt-db-credentials
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: flipt
            app.kubernetes.io/component: secrets
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: 1h
          secretStoreRef:
            kind: ClusterSecretStore
            name: azure-keyvault-store
          target:
            name: flipt-db-credentials
            creationPolicy: Owner
            template:
              type: Opaque
          data:
            - secretKey: FLIPT_DB_URL
              remoteRef:
                key: FLIPT-DB-URL
      ''
      # idpbuilder-cert - copy CA cert from default namespace
      ''
        apiVersion: external-secrets.io/v1
        kind: ExternalSecret
        metadata:
          name: idpbuilder-cert
          namespace: ${namespace}
          labels:
            app.kubernetes.io/name: idpbuilder
            app.kubernetes.io/component: ca-cert
            app.kubernetes.io/part-of: feature-flags
        spec:
          refreshInterval: 24h
          secretStoreRef:
            kind: ClusterSecretStore
            name: default-namespace
          target:
            name: idpbuilder-cert
            creationPolicy: Owner
            template:
              type: Opaque
          data:
            - secretKey: ca.crt
              remoteRef:
                key: idpbuilder-cert
                property: ca.crt
      ''
    ];
  };

  # Feature Flags Repo Init - Create the feature-flags repo in Gitea
  applications.feature-flags-repo-init = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-77";
      "argocd.argoproj.io/hook" = "Sync";
      "argocd.argoproj.io/hook-delete-policy" = "HookSucceeded";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      # ServiceAccount for the init job
      serviceAccounts.feature-flags-repo-init = {
        metadata = {
          inherit namespace;
          labels = {
            "app.kubernetes.io/name" = "feature-flags-repo-init";
            "app.kubernetes.io/component" = "init";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
      };

      # Job to create the feature-flags repo
      jobs.feature-flags-repo-init = {
        metadata = {
          inherit namespace;
          labels = {
            "app.kubernetes.io/name" = "feature-flags-repo-init";
            "app.kubernetes.io/component" = "init";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
        spec = {
          ttlSecondsAfterFinished = 300;
          backoffLimit = 3;
          template = {
            metadata.labels = {
              "app.kubernetes.io/name" = "feature-flags-repo-init";
            };
            spec = {
              serviceAccountName = "feature-flags-repo-init";
              restartPolicy = "OnFailure";
              containers = [{
                name = "init-repo";
                image = "alpine/git:latest";
                command = [ "/bin/sh" "-c" ];
                args = [''
                  set -e

                  # Install curl and jq
                  apk add --no-cache curl jq

                  GITEA_URL="http://my-gitea-http.gitea.svc.cluster.local:3000"
                  REPO_NAME="feature-flags"

                  echo "Checking if repo exists..."
                  REPO_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
                    -u "$GITEA_USERNAME:$GITEA_PASSWORD" \
                    "$GITEA_URL/api/v1/repos/giteaAdmin/$REPO_NAME")

                  if [ "$REPO_CHECK" = "200" ]; then
                    echo "Repository already exists, checking for .flipt.yml..."
                    cd /tmp
                    git config --global user.email "admin@example.com"
                    git config --global user.name "Admin"
                    git clone "http://$GITEA_USERNAME:$GITEA_PASSWORD@my-gitea-http.gitea.svc.cluster.local:3000/giteaAdmin/$REPO_NAME.git"
                    cd "$REPO_NAME"
                    if [ -d "default" ] && [ -f "default/features.yaml" ]; then
                      echo "Feature flags already configured with correct structure, skipping"
                      exit 0
                    fi
                    echo "Repo exists but needs feature flags setup, continuing..."
                  else
                    echo "Creating repository..."
                    curl -s -X POST "$GITEA_URL/api/v1/user/repos" \
                      -u "$GITEA_USERNAME:$GITEA_PASSWORD" \
                      -H "Content-Type: application/json" \
                      -d '{
                        "name": "'"$REPO_NAME"'",
                        "description": "Feature flags configuration for Flipt",
                        "private": false,
                        "auto_init": true,
                        "default_branch": "main"
                      }'

                    echo "Waiting for repo to be ready..."
                    sleep 5

                    cd /tmp
                    git config --global user.email "admin@example.com"
                    git config --global user.name "Admin"
                    git clone "http://$GITEA_USERNAME:$GITEA_PASSWORD@my-gitea-http.gitea.svc.cluster.local:3000/giteaAdmin/$REPO_NAME.git"
                    cd "$REPO_NAME"
                  fi

                  # Remove old features.json and flags directory if they exist
                  rm -f features.json
                  rm -rf flags .flipt.yml

                  # Create namespace directories (Flipt expects <namespace>/features.yaml structure)
                  mkdir -p default development staging production

                  # Default namespace flags (for Flagd and general use)
                  cat > default/features.yaml << 'EOF'
# Default Namespace Feature Flags
version: "1.2"
namespace: default

segments:
  - key: beta-users
    name: Beta Program Users
    match_type: ANY_MATCH_TYPE
    constraints:
      - property: groups
        operator: isoneof
        value: beta-testers,early-adopters
        type: STRING_COMPARISON_TYPE

  - key: internal-users
    name: Internal Users
    match_type: ANY_MATCH_TYPE
    constraints:
      - property: email
        operator: suffix
        value: "@company.com"
        type: STRING_COMPARISON_TYPE

flags:
  - key: dark-mode-enabled
    name: Dark Mode
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    rollouts:
      - segment:
          key: beta-users
          value: true
      - threshold:
          percentage: 20
          value: true

  - key: new-dashboard-ui
    name: New Dashboard UI
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    rollouts:
      - segment:
          key: internal-users
          value: true

  - key: checkout-flow
    name: Checkout Flow Version
    type: VARIANT_FLAG_TYPE
    enabled: true
    variants:
      - key: control
        name: Original checkout
      - key: variant-a
        name: Streamlined checkout
      - key: variant-b
        name: Single page checkout
    rules:
      - segment: beta-users
        rank: 1
        distributions:
          - variant: control
            rollout: 34
          - variant: variant-a
            rollout: 33
          - variant: variant-b
            rollout: 33
EOF

                  # Development environment flags - Flipt v2 format
                  cat > development/features.yaml << 'EOF'
# Development Environment Feature Flags
version: "1.2"
namespace: development

segments:
  - key: beta-users
    name: Beta Program Users
    match_type: ANY_MATCH_TYPE
    constraints:
      - property: groups
        operator: isoneof
        value: beta-testers,early-adopters
        type: STRING_COMPARISON_TYPE

  - key: internal-users
    name: Internal Users
    match_type: ANY_MATCH_TYPE
    constraints:
      - property: email
        operator: suffix
        value: "@company.com"
        type: STRING_COMPARISON_TYPE

flags:
  - key: dark-mode-enabled
    name: Dark Mode
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    rollouts:
      - segment:
          key: beta-users
          value: true
      - threshold:
          percentage: 20
          value: true

  - key: new-dashboard-ui
    name: New Dashboard UI
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    rollouts:
      - segment:
          key: internal-users
          value: true
      - threshold:
          percentage: 0
          value: false

  - key: checkout-flow
    name: Checkout Flow Version
    type: VARIANT_FLAG_TYPE
    enabled: true
    variants:
      - key: control
        name: Original checkout
      - key: variant-a
        name: Streamlined checkout
      - key: variant-b
        name: Single page checkout
    rules:
      - segment: beta-users
        rank: 1
        distributions:
          - variant: control
            rollout: 34
          - variant: variant-a
            rollout: 33
          - variant: variant-b
            rollout: 33
EOF

                  # Staging environment flags - Flipt v2 format
                  cat > staging/features.yaml << 'EOF'
# Staging Environment Feature Flags
version: "1.2"
namespace: staging

segments:
  - key: beta-users
    name: Beta Program Users
    match_type: ANY_MATCH_TYPE
    constraints:
      - property: groups
        operator: isoneof
        value: beta-testers
        type: STRING_COMPARISON_TYPE

flags:
  - key: dark-mode-enabled
    name: Dark Mode
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    rollouts:
      - threshold:
          percentage: 50
          value: true

  - key: new-dashboard-ui
    name: New Dashboard UI
    type: BOOLEAN_FLAG_TYPE
    enabled: false

  - key: checkout-flow
    name: Checkout Flow Version
    type: VARIANT_FLAG_TYPE
    enabled: true
    variants:
      - key: control
        name: Original checkout
      - key: variant-a
        name: Streamlined checkout
    rules:
      - segment: beta-users
        rank: 1
        distributions:
          - variant: control
            rollout: 80
          - variant: variant-a
            rollout: 20
EOF

                  # Production environment flags - Flipt v2 format
                  cat > production/features.yaml << 'EOF'
# Production Environment Feature Flags
version: "1.2"
namespace: production

segments:
  - key: vip-users
    name: VIP Users
    match_type: ALL_MATCH_TYPE
    constraints:
      - property: tier
        operator: eq
        value: enterprise
        type: STRING_COMPARISON_TYPE

flags:
  - key: dark-mode-enabled
    name: Dark Mode
    type: BOOLEAN_FLAG_TYPE
    enabled: true
    rollouts:
      - threshold:
          percentage: 100
          value: true

  - key: new-dashboard-ui
    name: New Dashboard UI
    type: BOOLEAN_FLAG_TYPE
    enabled: false

  - key: checkout-flow
    name: Checkout Flow Version
    type: VARIANT_FLAG_TYPE
    enabled: true
    variants:
      - key: control
        name: Original checkout
    rules:
      - segment: vip-users
        rank: 1
        distributions:
          - variant: control
            rollout: 100
EOF

                  # Commit all changes
                  git add -A
                  git commit -m "Initialize feature flags with multi-environment setup" || true
                  git push origin main || true

                  echo "Repository initialized with full feature flags configuration"
                ''];
                env = [
                  { name = "GITEA_USERNAME"; valueFrom.secretKeyRef = { name = "flipt-git-credentials"; key = "FLIPT_STORAGE_DEFAULT_AUTHENTICATION_BASIC_USERNAME"; }; }
                  { name = "GITEA_PASSWORD"; valueFrom.secretKeyRef = { name = "flipt-git-credentials"; key = "FLIPT_STORAGE_DEFAULT_AUTHENTICATION_BASIC_PASSWORD"; }; }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    memory = "128Mi";
                  };
                };
              }];
            };
          };
        };
      };
    };
  };

  # Flagd - OpenFeature-compliant flag evaluation sidecar
  # Note: Sync wave -74 ensures Flagd deploys after Flipt (-75)
  applications.flagd = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-74";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      # ConfigMap with flag definitions in flagd format
      configMaps.flagd-flags = {
        metadata = {
          inherit namespace;
          labels.app = "flagd";
        };
        data."flags.json" = builtins.toJSON {
          flags = {
            "enable-caipe" = {
              state = "ENABLED";
              variants = {
                "on" = true;
                "off" = false;
              };
              defaultVariant = "on";
            };
            "dark-mode-enabled" = {
              state = "ENABLED";
              variants = {
                "on" = true;
                "off" = false;
              };
              defaultVariant = "off";
            };
            "new-dashboard-ui" = {
              state = "ENABLED";
              variants = {
                "on" = true;
                "off" = false;
              };
              defaultVariant = "off";
              targeting = {
                "if" = [
                  { "in" = [ { var = "groups"; } [ "admin" "beta-testers" ] ]; }
                  "on"
                  "off"
                ];
              };
            };
          };
        };
      };

      deployments.flagd = {
        metadata = {
          inherit namespace;
          labels.app = "flagd";
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "flagd";

          template = {
            metadata.labels.app = "flagd";

            spec = {
              containers = [{
                name = "flagd";
                image = "ghcr.io/open-feature/flagd:v0.11.0";
                args = [
                  "start"
                  "--port"
                  "8013"
                  "--uri"
                  "file:/etc/flagd/flags.json"
                ];
                ports = [
                  { containerPort = 8013; name = "grpc"; }
                  { containerPort = 8014; name = "http"; }
                ];
                volumeMounts = [{
                  name = "flags-config";
                  mountPath = "/etc/flagd";
                  readOnly = true;
                }];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    memory = "128Mi";
                  };
                };
              }];
              volumes = [{
                name = "flags-config";
                configMap.name = "flagd-flags";
              }];
            };
          };
        };
      };

      services.flagd = {
        metadata = {
          inherit namespace;
          labels.app = "flagd";
        };
        spec = {
          ports = [
            { name = "grpc"; port = 8013; targetPort = "grpc"; }
            { name = "http"; port = 8014; targetPort = "http"; }
          ];
          selector.app = "flagd";
        };
      };
    };
  };

  # Flipt - Feature Flag Management UI
  applications.flipt = {
    inherit namespace;
    createNamespace = false;

    annotations = {
      "argocd.argoproj.io/sync-wave" = "-75";
    };

    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    resources = {
      configMaps.flipt-config = {
        metadata = {
          namespace = namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
        data = {
          # Flipt v2 configuration
          # https://docs.flipt.io/configuration/overview
          "flipt.yml" = ''
            log:
              level: debug
              encoding: json

            server:
              protocol: http
              http_port: 8080
              grpc_port: 9000

            # Declarative Git storage (v2 format)
            # https://docs.flipt.io/configuration/storage
            # Authentication values are overridden by env vars:
            # FLIPT_STORAGE_DEFAULT_AUTHENTICATION_BASIC_USERNAME
            # FLIPT_STORAGE_DEFAULT_AUTHENTICATION_BASIC_PASSWORD
            storage:
              default:
                remote: "http://${giteaInternalHost}/giteaAdmin/feature-flags.git"
                ref: "main"
                poll_interval: "30s"
                insecure_skip_tls: true
                authentication:
                  basic:
                    # Placeholder values - overridden by env vars from flipt-git-credentials secret
                    username: "placeholder"
                    password: "placeholder"
                backend:
                  type: git

            # Authentication configuration
            authentication:
              required: true
              exclude:
                metadata: true
                evaluation: true
              session:
                domain: "${fliptHost}"
                secure: true
              methods:
                token:
                  enabled: false
                oidc:
                  enabled: true
                  cleanup:
                    interval: "10m"
                    grace_period: "30m"
                  providers:
                    keycloak:
                      # Domain-based routing for Keycloak
                      issuer_url: "https://keycloak.${ingressHost}${portSuffix}/realms/cnoe"
                      client_id: "flipt"
                      # client_secret provided via FLIPT_AUTHENTICATION_METHODS_OIDC_PROVIDERS_KEYCLOAK_CLIENT_SECRET env var
                      redirect_address: "https://${fliptHost}${portSuffix}"
                      scopes:
                        - openid
                        - profile
                        - email
                        - groups

            # Audit logging
            audit:
              sinks:
                log:
                  enabled: true

            # Telemetry
            telemetry:
              enabled: true
          '';
        };
      };

      # PVC for Flipt data (local cache)
      persistentVolumeClaims.flipt-data = {
        metadata = {
          namespace = namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
          };
        };
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
        };
      };

      # Deployment (not StatefulSet) to match cdk8s
      deployments.flipt = {
        metadata = {
          inherit namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
        spec = {
          replicas = 1;
          selector.matchLabels.app = "flipt";

          template = {
            metadata.labels = {
              "app" = "flipt";
              "app.kubernetes.io/name" = "flipt";
              "app.kubernetes.io/component" = "management-ui";
              "app.kubernetes.io/part-of" = "feature-flags";
            };

            spec = {
              # Security context
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1000;
                runAsGroup = 1000;
                fsGroup = 1000;
              };

              containers = [{
                name = "flipt";
                image = "ghcr.io/flipt-io/flipt:v2.4.0";
                # Flipt v2 requires 'server' subcommand
                command = [ "/flipt" ];
                args = [ "server" "--config" "/etc/flipt/flipt.yml" ];
                ports = [
                  { containerPort = 8080; name = "http"; protocol = "TCP"; }
                  { containerPort = 9000; name = "grpc"; protocol = "TCP"; }
                ];
                # Mount secrets via envFrom
                envFrom = [
                  { secretRef.name = "flipt-oidc"; }
                  { secretRef.name = "flipt-git-credentials"; }
                ];
                env = [
                  { name = "FLIPT_LOG_LEVEL"; value = "debug"; }
                  # Use idpbuilder CA for TLS verification
                  { name = "GIT_SSL_CAINFO"; value = "/etc/ssl/certs/idpbuilder-ca.crt"; }
                  { name = "SSL_CERT_FILE"; value = "/etc/ssl/certs/idpbuilder-ca.crt"; }
                ];
                volumeMounts = [
                  { name = "config"; mountPath = "/etc/flipt"; readOnly = true; }
                  { name = "data"; mountPath = "/var/opt/flipt"; }
                  { name = "idpbuilder-ca"; mountPath = "/etc/ssl/certs/idpbuilder-ca.crt"; subPath = "ca.crt"; readOnly = true; }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "256Mi";
                  };
                };
                # Security context for container
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                # Health probes
                livenessProbe = {
                  httpGet = { path = "/health"; port = 8080; };
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = { path = "/health"; port = 8080; };
                  initialDelaySeconds = 5;
                  periodSeconds = 5;
                  failureThreshold = 3;
                };
              }];

              volumes = [
                { name = "config"; configMap.name = "flipt-config"; }
                { name = "data"; persistentVolumeClaim.claimName = "flipt-data"; }
                { name = "idpbuilder-ca"; secret.secretName = "idpbuilder-cert"; }
              ];
            };
          };
        };
      };

      services.flipt = {
        metadata = {
          inherit namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
        };
        spec = {
          type = "ClusterIP";
          ports = [
            { name = "http"; port = 8080; targetPort = 8080; protocol = "TCP"; }
            { name = "grpc"; port = 9000; targetPort = 9000; protocol = "TCP"; }
          ];
          selector.app = "flipt";
        };
      };

      ingresses.flipt = {
        metadata = {
          inherit namespace;
          labels = {
            "app" = "flipt";
            "app.kubernetes.io/name" = "flipt";
            "app.kubernetes.io/component" = "management-ui";
            "app.kubernetes.io/part-of" = "feature-flags";
          };
          annotations = {
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP";
          };
        };
        spec = {
          ingressClassName = "nginx";
          rules = [{
            host = fliptHost;
            http.paths = [{
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "flipt";
                port.number = 8080;
              };
            }];
          }];
          tls = [{
            hosts = [ fliptHost ];
          }];
        };
      };
    };
  };
}
