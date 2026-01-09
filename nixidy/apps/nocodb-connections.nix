# NocoDB External Database Connections
# Declaratively configures external PostgreSQL connections for NoCoDB
#
# This creates connections to:
#   - Backstage Catalog (backstage_plugin_catalog)
#   - Langfuse Observability (langfuse)
#
# Runs as a Job after NoCoDB is deployed (sync-wave 60)
{ config, lib, ... }:
let
  inherit (config) environmentType;
  namespace = "nocodb";
  isKind = environmentType == "kind";

  # External database connection definitions
  connections = [
    {
      id = "backstage-catalog";
      title = "Backstage Catalog";
      description = "Backstage software catalog entities and relationships";
      host = "postgresql.backstage.svc.cluster.local";
      port = 5432;
      database = "backstage_plugin_catalog";
      user = "backstage";
      # Password injected from secret
      passwordSecretKey = "BACKSTAGE_POSTGRES_PASSWORD";
    }
    {
      id = "langfuse";
      title = "Langfuse Observability";
      description = "LLM observability - traces, prompts, scores";
      host = "langfuse-postgres.observability.svc.cluster.local";
      port = 5432;
      database = "langfuse";
      user = "langfuse";
      passwordSecretKey = "LANGFUSE_POSTGRES_PASSWORD";
    }
  ];

  # Generate setup script
  setupScript = ''
    #!/bin/bash
    set -e

    echo "=== NoCoDB External Connections Setup ==="

    # Wait for NoCoDB to be ready (using wget since alpine doesn't have curl)
    echo "Waiting for NoCoDB to be ready..."
    until wget -q --spider http://nocodb:8080/api/v1/health 2>/dev/null; do
      echo "  NoCoDB not ready, waiting..."
      sleep 5
    done
    echo "NoCoDB is ready!"

    # Wait for NoCoDB postgres to be ready
    echo "Waiting for NoCoDB PostgreSQL..."
    until PGPASSWORD="$NOCODB_POSTGRES_PASSWORD" psql -h nocodb-postgres -U nocodb -d nocodb -c "SELECT 1" > /dev/null 2>&1; do
      echo "  PostgreSQL not ready, waiting..."
      sleep 2
    done
    echo "PostgreSQL is ready!"

    # Function to create external database connection
    create_connection() {
      local base_id="$1"
      local source_id="$2"
      local title="$3"
      local description="$4"
      local host="$5"
      local port="$6"
      local database="$7"
      local user="$8"
      local password="$9"

      echo "Creating connection: $title"

      # Check if base already exists
      existing=$(PGPASSWORD="$NOCODB_POSTGRES_PASSWORD" psql -h nocodb-postgres -U nocodb -d nocodb -tAc \
        "SELECT id FROM nc_bases_v2 WHERE id = '$base_id'" 2>/dev/null || echo "")

      if [ -n "$existing" ]; then
        echo "  Base $title already exists, skipping..."
        return 0
      fi

      # Create the base
      PGPASSWORD="$NOCODB_POSTGRES_PASSWORD" psql -h nocodb-postgres -U nocodb -d nocodb <<EOSQL
        -- Create base
        INSERT INTO nc_bases_v2 (id, title, description, status, is_meta, created_at, updated_at)
        VALUES ('$base_id', '$title', '$description', 'online', false, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;

        -- Create source (external database connection)
        INSERT INTO nc_sources_v2 (id, base_id, alias, type, config, is_meta, enabled, created_at, updated_at)
        VALUES (
          '$source_id',
          '$base_id',
          '$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')',
          'pg',
          '{"client":"pg","connection":{"host":"$host","port":$port,"user":"$user","password":"$password","database":"$database"},"searchPath":["public"]}',
          false,
          true,
          NOW(),
          NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
          config = EXCLUDED.config,
          updated_at = NOW();

        -- Link base to admin user
        INSERT INTO nc_base_users_v2 (base_id, fk_user_id, roles, created_at, updated_at)
        SELECT '$base_id', id, 'owner', NOW(), NOW()
        FROM nc_users_v2
        WHERE roles LIKE '%super%'
        ON CONFLICT DO NOTHING;
    EOSQL

      echo "  ✓ Created connection: $title"
    }

    # Create Backstage Catalog connection
    create_connection \
      "p_backstage_cat" \
      "s_backstage_cat" \
      "Backstage Catalog" \
      "Backstage software catalog entities and relationships" \
      "postgresql.backstage.svc.cluster.local" \
      "5432" \
      "backstage_plugin_catalog" \
      "backstage" \
      "$BACKSTAGE_POSTGRES_PASSWORD"

    # Create Langfuse connection
    create_connection \
      "p_langfuse_obs" \
      "s_langfuse_obs" \
      "Langfuse Observability" \
      "LLM observability - traces, prompts, scores" \
      "langfuse-postgres.observability.svc.cluster.local" \
      "5432" \
      "langfuse" \
      "langfuse" \
      "$LANGFUSE_POSTGRES_PASSWORD"

    echo ""
    echo "=== Setup Complete ==="
    echo "External database connections have been configured."
    echo "Visit NoCoDB to view the connected tables."
  '';
in
{
  config = lib.mkIf isKind {
    # ConfigMap with setup script
    applications.nocodb-connections = {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "70";  # After NoCoDB (50)
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
        # ConfigMap with setup script
        configMaps.nocodb-connections-setup = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-connections";
          };
          data = {
            "setup.sh" = setupScript;
          };
        };

        # Job to configure connections
        jobs.nocodb-connections-setup = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-connections";
            annotations = {
              "argocd.argoproj.io/hook" = "PostSync";
              "argocd.argoproj.io/hook-delete-policy" = "BeforeHookCreation";
            };
          };
          spec = {
            backoffLimit = 3;
            ttlSecondsAfterFinished = 300;

            template = {
              metadata.labels.app = "nocodb-connections";

              spec = {
                restartPolicy = "OnFailure";

                containers = [{
                  name = "setup";
                  image = "postgres:15-alpine";
                  command = [ "/bin/bash" "/scripts/setup.sh" ];
                  env = [
                    {
                      name = "NOCODB_POSTGRES_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "nocodb-credentials";
                        key = "POSTGRES_PASSWORD";
                      };
                    }
                    {
                      name = "BACKSTAGE_POSTGRES_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "nocodb-external-db-credentials";
                        key = "BACKSTAGE_POSTGRES_PASSWORD";
                      };
                    }
                    {
                      name = "LANGFUSE_POSTGRES_PASSWORD";
                      valueFrom.secretKeyRef = {
                        name = "nocodb-external-db-credentials";
                        key = "LANGFUSE_POSTGRES_PASSWORD";
                      };
                    }
                  ];
                  volumeMounts = [{
                    name = "scripts";
                    mountPath = "/scripts";
                  }];
                }];

                volumes = [{
                  name = "scripts";
                  configMap = {
                    name = "nocodb-connections-setup";
                    defaultMode = 493;  # 0755
                  };
                }];
              };
            };
          };
        };
      };
    };

    # Secret with external database credentials
    # Uses a Job to copy credentials from source namespaces
    applications.nocodb-external-secrets = {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "65";  # Before connections job (70)
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
        # ServiceAccount for cross-namespace secret access
        serviceAccounts.nocodb-secret-copier = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-connections";
          };
        };

        # ClusterRole to read secrets from other namespaces
        clusterRoles.nocodb-secret-reader = {
          metadata.labels.app = "nocodb-connections";
          rules = [{
            apiGroups = [ "" ];
            resources = [ "secrets" ];
            verbs = [ "get" "list" ];
          }];
        };

        # ClusterRoleBinding
        clusterRoleBindings.nocodb-secret-reader = {
          metadata.labels.app = "nocodb-connections";
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "nocodb-secret-reader";
          };
          subjects = [{
            kind = "ServiceAccount";
            name = "nocodb-secret-copier";
            inherit namespace;
          }];
        };

        # Role to create secrets in nocodb namespace
        roles.nocodb-secret-writer = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-connections";
          };
          rules = [{
            apiGroups = [ "" ];
            resources = [ "secrets" ];
            verbs = [ "get" "create" "update" "patch" ];
          }];
        };

        # RoleBinding
        roleBindings.nocodb-secret-writer = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-connections";
          };
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "Role";
            name = "nocodb-secret-writer";
          };
          subjects = [{
            kind = "ServiceAccount";
            name = "nocodb-secret-copier";
            inherit namespace;
          }];
        };

        # Job to copy secrets from source namespaces
        jobs.nocodb-copy-credentials = {
          metadata = {
            inherit namespace;
            labels.app = "nocodb-connections";
            annotations = {
              "argocd.argoproj.io/hook" = "Sync";
              "argocd.argoproj.io/hook-delete-policy" = "BeforeHookCreation";
            };
          };
          spec = {
            backoffLimit = 3;
            ttlSecondsAfterFinished = 300;

            template = {
              metadata.labels.app = "nocodb-connections";

              spec = {
                serviceAccountName = "nocodb-secret-copier";
                restartPolicy = "OnFailure";

                containers = [{
                  name = "copy-secrets";
                  image = "bitnami/kubectl:latest";
                  command = [ "/bin/bash" "-c" ];
                  args = [
                    ''
                      set -e
                      echo "=== Copying database credentials ==="

                      # Get Backstage PostgreSQL password from StatefulSet env
                      echo "Getting Backstage PostgreSQL password..."
                      BACKSTAGE_PW=$(kubectl exec -n backstage postgresql-0 -- sh -c 'echo $POSTGRES_PASSWORD' 2>/dev/null || echo "")

                      # Get Langfuse PostgreSQL password
                      echo "Getting Langfuse PostgreSQL password..."
                      LANGFUSE_PW=$(kubectl get secret -n observability langfuse-postgres-credentials -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d || echo "")

                      if [ -z "$BACKSTAGE_PW" ] || [ -z "$LANGFUSE_PW" ]; then
                        echo "Warning: Could not retrieve all passwords, using defaults"
                        # Fallback to known passwords for local dev
                        BACKSTAGE_PW="''${BACKSTAGE_PW:-backstage}"
                        LANGFUSE_PW="''${LANGFUSE_PW:-langfuse}"
                      fi

                      # Create/update secret in nocodb namespace
                      kubectl create secret generic nocodb-external-db-credentials \
                        --namespace=${namespace} \
                        --from-literal=BACKSTAGE_POSTGRES_PASSWORD="$BACKSTAGE_PW" \
                        --from-literal=LANGFUSE_POSTGRES_PASSWORD="$LANGFUSE_PW" \
                        --dry-run=client -o yaml | kubectl apply -f -

                      echo "✓ Credentials copied to nocodb namespace"
                    ''
                  ];
                }];
              };
            };
          };
        };
      };
    };
  };
}
