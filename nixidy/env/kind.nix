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

  # Derive Keycloak URL from ingress host and port (domain-based routing)
  keycloak.url = lib.mkDefault "https://keycloak.${config.cluster.ingressHost}:${toString config.cluster.ingressPort}";
}
