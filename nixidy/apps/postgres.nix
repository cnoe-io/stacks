# PostgreSQL application - External service pointing to Neon cloud
# Mirrors: cdk8s/charts/apps/postgres-chart.ts
{ config, lib, ... }:
let
  namespace = "nextjs";
in
{
  applications.postgres = {
    inherit namespace;
    createNamespace = true;

    # Sync wave for database layer
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
      };
    };

    resources = {
      # Headless service pointing to Neon cloud PostgreSQL
      # Allows apps to use postgres-service.nextjs.svc.cluster.local
      services.postgres-service = {
        metadata = {
          inherit namespace;
          annotations = {
            description = "Headless service for Neon cloud PostgreSQL compatibility";
            "argocd.argoproj.io/sync-wave" = "50";
          };
          labels = {
            "app.kubernetes.io/component" = "database";
            "app.kubernetes.io/part-of" = "data-layer";
            "app.kubernetes.io/name" = "postgres";
          };
        };
        spec = {
          type = "ExternalName";
          externalName = "ep-wispy-math-a8k8xapb-pooler.eastus2.azure.neon.tech";
          ports = [{
            name = "pg";
            port = 5432;
            targetPort = 5432;
          }];
        };
      };

      # ConfigMap with database connection info for debugging
      configMaps.postgres-connection-info = {
        metadata = {
          inherit namespace;
        };
        data = {
          "connection-type" = "neon-cloud";
          "pooling" = "enabled";
          "ssl-mode" = "require";
          "info" = "Database is hosted on Neon cloud. Connection string is stored in neon-database-credentials secret.";
          "migration-note" = "Run database migrations using your application migration tools (Prisma, Drizzle, etc.)";
        };
      };
    };
  };
}
