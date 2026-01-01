# Tailscale Operator - VPN and Service Mesh
# Provides Tailscale integration for secure remote access and service exposure.
# Deploys the official Tailscale Kubernetes Operator via nixhelm.
# Uses nixhelm for Helm chart management following nixidy best practices.
#
# Features:
# - Manages Tailscale resources (ProxyGroup, Connector, DNSConfig)
# - Provides ingressClassName: tailscale for exposing services
# - Centralizes certificate management (avoiding Let's Encrypt rate limits)
# - Handles state persistence automatically
#
# Prerequisites:
# - OAuth credentials synced to 'operator-oauth' secret
# - Tailscale ACL policy with tag:k8s-operator configured
#
# Mirrors: cdk8s/charts/infra/tailscale-operator-chart.ts
{ config, lib, charts, ... }:
let
  namespace = "tailscale";
  # Operator hostname varies by cluster
  clusterId = config.cluster.name or "kind";
  operatorHostname = "${clusterId}-operator";
in
{
  config = {
    # Tailscale Operator Secrets - OAuth credentials
    applications.tailscale-operator-secrets = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-105";  # After namespace, before operator
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
        retry = {
          limit = 5;
          backoff = {
            duration = "5s";
            factor = 2;
            maxDuration = "3m";
          };
        };
      };

      # ExternalSecret for operator-oauth - available for all environments with Azure Key Vault
      yamls = [
        ''
          apiVersion: external-secrets.io/v1
          kind: ExternalSecret
          metadata:
            name: operator-oauth
            namespace: ${namespace}
            labels:
              app.kubernetes.io/name: tailscale-operator
              app.kubernetes.io/component: secrets
              app.kubernetes.io/part-of: tailscale
          spec:
            refreshInterval: 24h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: operator-oauth
              creationPolicy: Owner
            data:
              - secretKey: client_id
                remoteRef:
                  key: TAILSCALE-OAUTH-CLIENT-ID
              - secretKey: client_secret
                remoteRef:
                  key: TAILSCALE-OAUTH-CLIENT-SECRET
        ''
      ];
    };

    # Tailscale Operator via nixhelm
    # CRDs are included with the Helm chart
    applications.tailscale-operator = {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-100";  # After secrets
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          serverSideApply = true;
        };
      };

      # Use nixhelm for pre-rendered Helm chart
      helm.releases.tailscale-operator = {
        chart = charts.tailscale.tailscale-operator;
        values = {
          operatorConfig = {
            hostname = operatorHostname;
          };
          oauth = {
            clientId = "";  # From operator-oauth secret
            clientSecret = "";  # From operator-oauth secret
          };
          # Reference existing secret for OAuth credentials
          apiServerProxyConfig = {
            mode = "true";
          };
        };
      };
    };

    # K8s API Tailscale Serve - Expose API server via Tailscale
    applications.k8s-api-tailscale-serve = {
      inherit namespace;
      createNamespace = false;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "10";  # After operator is ready
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
        syncOptions = {
          serverSideApply = true;
        };
      };

      yamls = [
        ''
          apiVersion: tailscale.com/v1alpha1
          kind: Connector
          metadata:
            name: k8s-api-connector
            namespace: ${namespace}
          spec:
            hostname: ${clusterId}-api
            tags:
              - tag:k8s-api
            subnetRouter:
              advertiseRoutes:
                - 10.43.0.0/16  # Service CIDR
                - 10.42.0.0/16  # Pod CIDR
        ''
      ];
    };
  };
}
