# KIND local development environment configuration
# Mirrors: cdk8s environment handling for CLUSTER_TYPE=kind
{ config, lib, ... }:
{
  # Set environment identifier
  nixidy.target.branch = "main";

  # KIND uses cnoe:// URLs for local development
  # idpBuilder will rewrite these to Gitea internal URLs
  nixidy.target.repository = "cnoe://";

  # Output path for generated manifests
  nixidy.target.rootPath = "./dist";

  # Set environment to dev for kind
  environment = lib.mkDefault "dev";

  # Environment type for application filtering
  environmentType = "kind";

  # KIND-specific cluster settings (custom options from variables.nix)
  cluster = {
    ingressHost = lib.mkDefault "cnoe.localtest.me";
    ingressPort = lib.mkDefault 8443;
    tls.enabled = lib.mkDefault false;
  };

  # ==========================================================================
  # Azure Workload Identity Configuration
  # ==========================================================================
  # These are Azure AD identifiers (not secrets) used for Workload Identity.
  # Actual secrets are stored in Azure Key Vault and accessed via ESO.
  # This is the native Nix approach - values defined directly in config.
  azure = {
    clientId = "1140d9c2-62f6-4857-94c2-7e0e6c64e562";
    tenantId = "0c4da9c5-40ea-4e7d-9c7a-e7308d4f8e38";
    subscriptionId = "fa5b32b6-1d6d-4110-bea2-8ac0e3126a38";
    keyVaultName = "keyvault-thcmfmoo5oeow";
  };

  # Tailscale configuration
  tailscale = {
    tailnet = "tail286401.ts.net";
  };

  # Derive Keycloak URL from ingress host and port (domain-based routing)
  keycloak.url = lib.mkDefault "https://keycloak.${config.cluster.ingressHost}:${toString config.cluster.ingressPort}";

  # Local charts directory for charts not in nixhelm (spark-operator)
  nixidy.chartsDir = ../charts;
}
