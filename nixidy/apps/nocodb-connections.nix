# NocoDB External Database Connections
# Declaratively configures external PostgreSQL connections for NoCoDB
#
# Architecture:
#   1. Integration (nc_integrations_v2) - Stores FULL connection credentials (host, port, user, password, database)
#   2. Base (nc_bases_v2) - The "database" container in NocoDB UI
#   3. Source (nc_sources_v2) - Links base to integration with MINIMAL config (just database name)
#   4. Base Users (nc_base_users_v2) - User access control
#   5. Meta Sync in UI to discover tables from external database
#
# IMPORTANT: Source config should be minimal (just database name). Full credentials must come
# from the integration via fk_integration_id. If source has full config, NocoDB has issues with
# password handling ("client password must be a string" error).
#
# This creates connections to:
#   - Backstage Catalog (backstage_plugin_catalog)
#   - Langfuse Observability (langfuse)
#
# Runs as a Job after NoCoDB is deployed (sync-wave 70)
{ config, lib, ... }:
let
  inherit (config) environmentType;
  namespace = "nocodb";
  isKind = environmentType == "kind";

  # Generate ID helper (NocoDB uses specific prefixes)
  # int = integration, p = base/project, s = source

  # Generate setup script with full integration + API sync
  setupScript = ''
    #!/bin/bash
    set -e

    echo "=== NoCoDB External Connections Setup ==="
    echo "This script creates integrations, bases, sources and syncs tables declaratively"

    # Wait for NoCoDB to be ready
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

    # Get admin user ID
    ADMIN_USER_ID=$(PGPASSWORD="$NOCODB_POSTGRES_PASSWORD" psql -h nocodb-postgres -U nocodb -d nocodb -tAc \
      "SELECT id FROM nc_users_v2 WHERE roles LIKE '%super%' LIMIT 1")
    echo "Admin user ID: $ADMIN_USER_ID"

    # Function to generate NocoDB-style IDs (prefix + random alphanumeric)
    generate_id() {
      local prefix="$1"
      # Use deterministic ID based on prefix for idempotency
      echo "''${prefix}$(echo -n "$2" | md5sum | cut -c1-15)"
    }

    # Function to create complete external database connection
    # This creates: integration -> base -> source -> user mapping -> table sync
    create_external_db() {
      local name="$1"
      local title="$2"
      local description="$3"
      local host="$4"
      local port="$5"
      local database="$6"
      local db_user="$7"
      local password="$8"

      # Generate deterministic IDs for idempotency
      local int_id="int_$(echo -n "$name" | md5sum | cut -c1-14)"
      local base_id="p_$(echo -n "$name" | md5sum | cut -c1-14)"
      local source_id="s_$(echo -n "$name" | md5sum | cut -c1-14)"
      local alias=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

      echo ""
      echo "=== Creating: $title ==="
      echo "  Integration ID: $int_id"
      echo "  Base ID: $base_id"
      echo "  Source ID: $source_id"

      # Build config JSON for integration (full connection details)
      local int_config='{"client":"pg","connection":{"host":"'"$host"'","port":"'"$port"'","user":"'"$db_user"'","password":"'"$password"'","database":"'"$database"'"},"searchPath":["public"]}'

      # Build minimal config JSON for source (just database name - credentials come from integration)
      local source_config='{"client":"pg","connection":{"database":"'"$database"'"},"searchPath":["public"]}'

      PGPASSWORD="$NOCODB_POSTGRES_PASSWORD" psql -h nocodb-postgres -U nocodb -d nocodb <<EOSQL
        -- 1. Create/update integration (stores FULL connection credentials)
        INSERT INTO nc_integrations_v2 (
          id, title, config, type, sub_type, is_private, deleted,
          created_by, "order", created_at, updated_at, is_default, is_encrypted
        )
        VALUES (
          '$int_id', '$title', '$int_config', 'database', 'pg', false, false,
          '$ADMIN_USER_ID', 1, NOW(), NOW(), false, false
        )
        ON CONFLICT (id) DO UPDATE SET
          title = EXCLUDED.title,
          config = EXCLUDED.config,
          updated_at = NOW();

        -- 2. Create/update base (the "database" in NocoDB UI)
        INSERT INTO nc_bases_v2 (id, title, description, status, is_meta, created_at, updated_at)
        VALUES ('$base_id', '$title', '$description', 'online', false, NOW(), NOW())
        ON CONFLICT (id) DO UPDATE SET
          title = EXCLUDED.title,
          description = EXCLUDED.description,
          updated_at = NOW();

        -- 3. Create/update source (MINIMAL config - credentials from integration via fk_integration_id)
        INSERT INTO nc_sources_v2 (
          id, base_id, alias, type, config, is_meta, enabled,
          fk_integration_id, is_local, is_encrypted,
          created_at, updated_at
        )
        VALUES (
          '$source_id', '$base_id', '$alias', 'pg', '$source_config', false, true,
          '$int_id', false, false,
          NOW(), NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
          config = EXCLUDED.config,
          fk_integration_id = EXCLUDED.fk_integration_id,
          updated_at = NOW();

        -- 4. Grant admin user access to the base
        INSERT INTO nc_base_users_v2 (base_id, fk_user_id, roles, created_at, updated_at)
        VALUES ('$base_id', '$ADMIN_USER_ID', 'owner', NOW(), NOW())
        ON CONFLICT DO NOTHING;
EOSQL

      echo "  ✓ Database records created"

      # 5. Trigger table sync via NocoDB API
      # First, get an API token by signing in
      echo "  Syncing tables via API..."

      # Get user email and create a session token
      local user_email=$(PGPASSWORD="$NOCODB_POSTGRES_PASSWORD" psql -h nocodb-postgres -U nocodb -d nocodb -tAc \
        "SELECT email FROM nc_users_v2 WHERE id = '$ADMIN_USER_ID'")

      # Use the v1 meta sync endpoint to trigger table discovery
      # This endpoint syncs the schema from the external database
      local sync_response=$(wget -q -O - --post-data="" \
        "http://nocodb:8080/api/v1/db/meta/projects/$base_id/meta-diff" 2>/dev/null || echo "")

      if [ -n "$sync_response" ]; then
        echo "  ✓ Table sync triggered"
      else
        echo "  ⚠ Table sync may require manual trigger (open base in UI)"
      fi

      echo "  ✓ Complete: $title"
    }

    # Create Backstage Catalog connection
    if [ -n "$BACKSTAGE_POSTGRES_PASSWORD" ]; then
      create_external_db \
        "backstage_catalog" \
        "Backstage Catalog" \
        "Backstage software catalog - entities, relationships, locations" \
        "postgresql.backstage.svc.cluster.local" \
        "5432" \
        "backstage_plugin_catalog" \
        "backstage" \
        "$BACKSTAGE_POSTGRES_PASSWORD"
    else
      echo "⚠ Skipping Backstage Catalog - no password provided"
    fi

    # Create Langfuse Observability connection
    if [ -n "$LANGFUSE_POSTGRES_PASSWORD" ]; then
      create_external_db \
        "langfuse_obs" \
        "Langfuse Observability" \
        "LLM observability - traces, prompts, scores, evaluations" \
        "langfuse-postgres.observability.svc.cluster.local" \
        "5432" \
        "langfuse" \
        "langfuse" \
        "$LANGFUSE_POSTGRES_PASSWORD"
    else
      echo "⚠ Skipping Langfuse - no password provided"
    fi

    echo ""
    echo "=== Setup Complete ==="
    echo ""
    echo "External databases configured with full integration support."
    echo "Tables should auto-sync. If not visible, open the base in NocoDB UI"
    echo "to trigger the initial table discovery."
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
