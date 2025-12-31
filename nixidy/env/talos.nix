# Talos production environment configuration
# Mirrors: cdk8s environment handling for CLUSTER_TYPE=talos
{ config, lib, ... }:
{
  # Set environment identifier
  nixidy.target.branch = config.git.branch;

  # Talos uses GitHub URLs
  nixidy.target.repository = config.git.repoUrl;

  # Output path for generated manifests
  nixidy.target.rootPath = "./dist";

  # Set environment to talos if not explicitly set
  environment = lib.mkDefault "talos";

  # Environment type for application filtering
  environmentType = "talos";

  # Talos-specific cluster settings (custom options from variables.nix)
  cluster = {
    ingressHost = lib.mkDefault "ai401kchat.com";
    ingressPort = lib.mkDefault 443;
    tls = {
      enabled = lib.mkDefault true;
      clusterIssuer = lib.mkDefault "letsencrypt-prod";
    };
  };

  # Derive Keycloak URL from ingress host if not set
  keycloak.url = lib.mkDefault "https://${config.cluster.ingressHost}/keycloak";

  # Note: Environment variable validation is done via documentation and runtime checks
  # Required Talos environment variables:
  #   - AZURE_CLIENT_ID: Azure AD Application Client ID for Workload Identity
  #   - AZURE_TENANT_ID: Azure AD Tenant ID
  #   - GIT_REPO_URL: Git repository URL for ArgoCD sources (defaults to PittampalliOrg/stacks)
  #   - GIT_BRANCH: Git branch (defaults to main)
}
