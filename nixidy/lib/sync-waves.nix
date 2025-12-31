# Sync wave constants for ArgoCD resource ordering
# Matches the current cdk8s sync wave patterns
{
  # CRDs and fundamental resources (earliest)
  crds = "-120";
  operators = "-110";
  namespaces = "-110";

  # RBAC and security
  rbac = "-90";
  workloadIdentity = "-90";
  secretStores = "-88";

  # Secrets and configuration
  secrets = "-85";
  clusterIssuers = "-80";
  configMaps = "-70";

  # Dependencies
  databases = "-50";
  caches = "-40";

  # Core infrastructure
  infrastructure = "-30";

  # Deployments (default)
  deployments = "0";

  # Post-deployment
  jobs = "10";
  tests = "20";

  # Applications
  applications = "50";

  # Ingress and external access (last)
  ingress = "100";
  tailscaleServe = "110";
}
