# Sync wave constants for ArgoCD resource ordering
# SIMPLIFIED: Reduced from 35 waves to 10 for faster parallel syncing
# Resources within the same wave sync in parallel
{
  # === INFRASTRUCTURE LAYER (negative waves) ===

  # CRDs and operators - must be first
  crds = "-100";          # Gateway API, Tailscale, Kargo, ESO CRDs
  operators = "-100";     # CRD-installing operators

  # Namespaces and RBAC - foundational
  namespaces = "-80";     # All namespace creation
  rbac = "-80";           # ClusterRoles, ServiceAccounts

  # Secrets infrastructure - before apps that need secrets
  secretStores = "-60";   # ESO, ClusterSecretStores, Workload Identity
  secrets = "-60";        # ExternalSecrets, generated secrets

  # Stateful dependencies - databases, caches
  databases = "-40";      # PostgreSQL, Minio, Clickhouse
  caches = "-40";         # Redis, Milvus, Neo4j

  # Core infrastructure services
  infrastructure = "-20"; # Keycloak, Gitea, cert-manager issuers

  # === APPLICATION LAYER (zero and positive waves) ===

  # Main deployments - default wave
  deployments = "0";      # Application deployments

  # Post-deployment jobs
  jobs = "20";            # Config jobs, sync jobs

  # Applications that depend on core services
  applications = "40";    # Backstage, Argo Workflows, Grafana

  # External access - last
  ingress = "60";         # Ingress resources
  tailscaleServe = "60";  # Tailscale Serve proxies

  # === LEGACY ALIASES (for backward compatibility) ===
  workloadIdentity = "-60";  # Same as secretStores
  clusterIssuers = "-20";    # Same as infrastructure
  configMaps = "-20";        # Same as infrastructure
  tests = "20";              # Same as jobs
}
