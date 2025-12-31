# Hub cluster environment configuration
# Hub cluster manages spoke clusters via Tailscale
{ config, lib, ... }:
{
  # Set environment identifier
  nixidy.target.branch = config.git.branch;

  # Hub uses GitHub URLs
  nixidy.target.repository = config.git.repoUrl;

  # Output path for generated manifests
  nixidy.target.rootPath = "./dist";

  # Set environment to hub
  environment = lib.mkDefault "hub";

  # Environment type for application filtering
  environmentType = "hub";

  # Hub-specific cluster settings
  cluster = {
    name = lib.mkDefault "hub";
    ingressHost = lib.mkDefault "hub.ai401kchat.com";
    ingressPort = lib.mkDefault 443;
    tls = {
      enabled = lib.mkDefault true;
      clusterIssuer = lib.mkDefault "letsencrypt-prod";
    };
  };

  # Derive Keycloak URL from ingress host if not set
  keycloak.url = lib.mkDefault "https://${config.cluster.ingressHost}/keycloak";

  # Note: Hub cluster typically runs ArgoCD that manages spoke clusters
  # Spoke clusters are managed via Tailscale VPN connections
}
