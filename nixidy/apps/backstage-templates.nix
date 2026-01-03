# Backstage Templates - Scaffolder Templates and Organization Entities
#
# This generates an ArgoCD Application for Backstage templates.
# The actual template files (with skeleton directories) are stored in
# nixidy/templates/backstage/ and copied by nixidy-to-idpbuilder.sh
#
# The script:
# 1. Removes nixidy-generated manifests/ directory
# 2. Copies nixidy/templates/backstage/ to dist/backstage-templates/entities/
# 3. Updates this ArgoCD Application to use cnoe://backstage-templates/entities
# 4. Adds directory.exclude for catalog-info.yaml (Backstage catalog file, not K8s resource)
#
# Templates included:
# - basic: Simple Kubernetes Deployment
# - argo-workflows: Argo Workflow with Spark Job
# - app-with-bucket: Go App with AWS S3 resources
# - ray-serve: Ray Service on Kubernetes
#
# KIND only - for local development with idpBuilder
{ config, lib, ... }:
let
  isKind = config.environmentType == "kind";
  namespace = "backstage";
in
{
  config = lib.mkIf isKind {
    applications.backstage-templates = {
      inherit namespace;
      createNamespace = false;  # backstage namespace created by backstage.nix

      annotations = {
        "argocd.argoproj.io/sync-wave" = "100";  # After backstage is deployed
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = false;
        };
      };

      # Empty resources - actual templates are file-based in nixidy/templates/backstage/
      # The nixidy-to-idpbuilder.sh script handles copying the template directory tree
      # and updating the ArgoCD Application source to use entities/ instead of manifests/
      resources = {};
    };
  };
}
