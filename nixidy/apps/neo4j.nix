# Neo4j - Graph Database
# Provides graph database for knowledge graphs and AI applications.
#
# Mirrors: cdk8s applications using Neo4j
{ config, lib, ... }:
let
  namespace = "neo4j";
in
{
  config = {
    applications.neo4j = {
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

      # Placeholder for Neo4j deployment
      # Chart: neo4j from https://helm.neo4j.com/neo4j
      yamls = [
        ''
          # Neo4j graph database
          # For production deployment, use one of:
          # 1. nixhelm with helm.releases
          # 2. ArgoCD Application with Helm source
          # 3. Pre-rendered manifests
          #
          # Key values:
          # - neo4j.edition = "community" or "enterprise"
          # - persistence.enabled = true
          # - neo4j.passwordSecretRef for authentication
        ''
      ];
    };
  };
}
