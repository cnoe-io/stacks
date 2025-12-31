# Application registry
# Imports all application definitions
# Applications use lib.mkIf to conditionally include based on config.environmentType
# Environment types: kind, talos, hub
{ config, lib, ... }:
{
  imports = [
    # Phase 3: Core pilot applications (all environments)
    ./namespace.nix
    ./backstage.nix
    ./keycloak.nix
    ./postgres.nix
    ./redis.nix

    # Phase 5: Environment-specific applications
    # KIND only (local development)
    ./idpbuilder-gitea.nix

    # Talos only (production with Azure)
    ./eso-workload-identity.nix

    # Phase 8: Core Infrastructure (Batch 1)
    ./argocd.nix            # ArgoCD configuration (disabled by default)
    ./ingress-nginx.nix     # Ingress NGINX (Talos only)
    ./cert-manager.nix      # Cert-Manager with Let's Encrypt (Talos only)
    ./external-secrets.nix  # External Secrets Operator (both environments)
    ./tailscale-operator.nix # Tailscale Operator (both environments)

    # Phase 9: Observability (Batch 2)
    ./langfuse.nix          # LLM Observability
    ./grafana.nix           # Dashboards (includes observability-namespace)
    ./loki.nix              # Log aggregation
    ./tempo.nix             # Distributed tracing
    ./prometheus.nix        # Metrics collection

    # Phase 10: AI/ML Stack (Batch 3)
    ./kagent.nix            # AI Agent Platform
    ./kmcp.nix              # MCP Servers
    ./neo4j.nix             # Graph Database
    ./ollama.nix            # Local LLM Server

    # Phase 11: Kargo & Pipelines (Batch 4)
    ./kargo.nix             # Progressive Delivery
    ./kargo-pipelines.nix   # Kargo Projects and Stages
    ./argo-workflows.nix    # Workflow Engine

    # Phase 12: Additional Applications

    # Security & Secrets
    ./secrets.nix           # ClusterSecretStore, bootstrap-secrets, cert-manager-secrets, cloudflare-issuer
    ./keycloak-config.nix   # Keycloak secrets, clients, and config

    # Tailscale Services
    ./tailscale.nix         # CRDs, secrets, subnet-router, Tailscale Serve services

    # Headlamp Dashboard
    ./headlamp.nix          # Kubernetes dashboard with OIDC

    # Extended Observability
    ./observability.nix     # Jaeger, LGTM stack (Mimir, OTEL Collector), observability-namespace, observability-secrets

    # Dapr Agents
    ./dapr.nix              # Dapr CRDs, runtime, Redis, components, SpecKit RBAC

    # Nix Binary Cache
    ./nix-cache.nix         # MinIO, Attic for Nix binary cache

    # Feature Flags
    ./feature-flags.nix     # Flagd, Flipt for feature flag management

    # Gateway & Infrastructure
    ./gateway.nix           # Gateway API CRDs, kgateway, Dagger infra

    # =========================================================================
    # Full Migration: Remaining CDK8s Applications
    # =========================================================================

    # CAIPE/AI Platform (KIND only)
    ./caipe.nix             # Multi-agent AI platform with RAG, GraphRAG, agents

    # Tailscale Serve Services
    ./tailscale-serve.nix   # Additional Tailscale Serve apps (langfuse, gitea, kagent, etc.)

    # Hub-and-Spoke Architecture (Talos/Hub)
    ./hub-spoke.nix         # Hub cluster infra, spoke registration, hub Kargo

    # Backstage Variants
    ./backstage-variants.nix # Local dev, staging, hub-managed Backstage

    # Kargo Extras
    ./kargo-extras.nix      # Pipeline credentials, CA certs, webhooks, Backstage pipeline

    # Langfuse Dependencies
    ./langfuse-deps.nix     # PostgreSQL, ClickHouse, Redis, MinIO for Langfuse

    # KubeVirt and NixOS VMs
    ./kubevirt.nix          # KubeVirt operator, CDI, NixOS Sway VM
  ];
}
