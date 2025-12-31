# Tailscale Operator - VPN and Service Mesh
# Provides Tailscale integration for secure remote access and service exposure.
# Deploys the official Tailscale Kubernetes Operator via Helm.
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
{ config, lib, ... }:
let
  namespace = "tailscale";
  # Operator hostname varies by cluster
  clusterId = config.cluster.name or "kind";
  operatorHostname = "${clusterId}-operator";
in
{
  config = {
    # Tailscale CRDs - install first
    applications.tailscale-crds = {
      inherit namespace;
      createNamespace = true;

      annotations = {
        "argocd.argoproj.io/sync-wave" = "-120";  # Very early, CRDs first
      };

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = false;  # Don't prune CRDs
          selfHeal = true;
        };
        syncOptions = {
          createNamespace = true;
          serverSideApply = true;
          replace = true;
        };
      };

      yamls = [
        ''
          # Tailscale CRDs are managed by the Helm chart or fetched from:
          # https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_connectors.yaml
          # https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_proxygroups.yaml
          # https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_dnsconfigs.yaml
          # https://raw.githubusercontent.com/tailscale/tailscale/main/cmd/k8s-operator/deploy/crds/tailscale.com_proxyclasses.yaml
        ''
      ];
    };

    # Tailscale Operator Secrets - OAuth credentials
    applications.tailscale-operator-secrets = {
      inherit namespace;
      createNamespace = false;

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

      yamls = lib.mkIf (config.environmentType == "talos") [
        ''
          apiVersion: external-secrets.io/v1beta1
          kind: ExternalSecret
          metadata:
            name: operator-oauth
            namespace: ${namespace}
          spec:
            refreshInterval: 1h
            secretStoreRef:
              kind: ClusterSecretStore
              name: azure-keyvault-store
            target:
              name: operator-oauth
              creationPolicy: Owner
            data:
              - secretKey: client_id
                remoteRef:
                  key: tailscale-oauth-client-id
              - secretKey: client_secret
                remoteRef:
                  key: tailscale-oauth-client-secret
        ''
      ];
    };

    # Tailscale Operator via Helm
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

      # Helm chart for Tailscale Operator
      # Note: nixidy uses helm.releases with nixhelm or yamls for inline manifests
      # Since Tailscale is not in nixhelm, we use yamls with rendered values
      yamls = [
        ''
          # Placeholder: Tailscale Operator would be deployed via Helm
          # In production, use nixhelm or ArgoCD Helm source
          # Chart: tailscale-operator from https://pkgs.tailscale.com/helmcharts
          # Version: 1.82.0
        ''
      ];

      # For Helm charts not in nixhelm, consider:
      # 1. Adding chart to nixidy.chartsDir
      # 2. Using ArgoCD Application with Helm source directly
      # 3. Pre-rendering Helm templates
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
