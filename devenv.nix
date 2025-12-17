{ pkgs, ... }:

{
  # Development packages for hub-and-spoke GitOps infrastructure
  packages = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.curl
    pkgs.git
    pkgs.jq
    pkgs.yq-go
    pkgs.nodejs_20
    pkgs.skopeo
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.argocd
  ];

  # Custom scripts for development workflows
  scripts = {
    # CDK8s synthesis for KIND clusters
    "synth-kind".exec = ''
      cd cdk8s
      CLUSTER_TYPE=kind npm run synth
    '';

    # CDK8s synthesis for Talos clusters (hub)
    "synth-talos".exec = ''
      cd cdk8s
      CLUSTER_TYPE=talos npm run synth
    '';

    # TypeScript compilation check
    "compile".exec = ''
      cd cdk8s
      npm run compile
    '';

    # Refresh hub Kargo warehouse (triggers freight detection)
    "refresh-hub-kargo-warehouse".exec = ''
      WAREHOUSE_NAME=''${1:-hub-backstage-gitea}
      kubectl --kubeconfig=~/.kube/hub-config annotate warehouse "$WAREHOUSE_NAME" \
        -n kargo-pipelines refresh=$(date +%s) --overwrite
      echo "Refreshed warehouse: $WAREHOUSE_NAME"
    '';

    # Show hub Kargo status
    "hub-kargo-status".exec = ''
      echo "=== Hub Kargo Warehouses ==="
      kubectl --kubeconfig=~/.kube/hub-config get warehouses -n kargo-pipelines
      echo ""
      echo "=== Hub Kargo Stages ==="
      kubectl --kubeconfig=~/.kube/hub-config get stages -n kargo-pipelines
      echo ""
      echo "=== Recent Freight ==="
      kubectl --kubeconfig=~/.kube/hub-config get freight -n kargo-pipelines --sort-by=.metadata.creationTimestamp | tail -10
    '';

    # Show hub ArgoCD applications targeting spokes
    "hub-argocd-apps".exec = ''
      echo "=== Hub ArgoCD Applications ==="
      kubectl --kubeconfig=~/.kube/hub-config get applications -n argocd -o wide
    '';

    # Sync all hub ArgoCD applications
    "hub-argocd-sync-all".exec = ''
      argocd --server argocd-hub.tail286401.ts.net --grpc-web app sync --all
    '';
  };

  # Shell initialization message
  enterShell = ''
    echo "=================================================================="
    echo "  Hub-and-Spoke GitOps Development Environment"
    echo "=================================================================="
    echo ""
    echo "CDK8s Commands:"
    echo "  devenv shell synth-kind          # Synthesize manifests for KIND"
    echo "  devenv shell synth-talos         # Synthesize manifests for Talos (hub)"
    echo "  devenv shell compile             # TypeScript compilation check"
    echo ""
    echo "Hub Kargo Commands:"
    echo "  devenv shell hub-kargo-status    # Show hub Kargo resources"
    echo "  devenv shell refresh-hub-kargo-warehouse [name]  # Trigger warehouse refresh"
    echo ""
    echo "Hub ArgoCD Commands:"
    echo "  devenv shell hub-argocd-apps     # List hub ArgoCD applications"
    echo "  devenv shell hub-argocd-sync-all # Sync all hub ArgoCD apps"
    echo ""
    echo "Inner Loop Development:"
    echo "  See scripts/publish-local-dev.sh for pushing images to KIND Gitea"
    echo "  Hub Kargo will automatically detect and promote to local-dev stage"
    echo ""
  '';

  # Environment variables
  env = {
    # Default to KIND for local development
    CLUSTER_TYPE = "kind";
    # Tailnet name for service URLs
    TAILNET_NAME = "tail286401";
  };
}
