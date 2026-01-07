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
    pkgs.watchexec  # File watcher for nixidy development
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

    # Nixidy watch mode - watches nixidy/ and .env-files/ for changes
    "nixidy-watch".exec = ''
      STACKS_DIR="''${STACKS_DIR:-$DEVENV_ROOT}"
      echo "Starting nixidy file watcher..."
      echo "Watching: $STACKS_DIR/nixidy/, $STACKS_DIR/.env-files/"
      echo "Debounce: ''${NIXIDY_WATCH_DEBOUNCE:-2000}ms"
      echo "ArgoCD sync: ''${NIXIDY_WATCH_SYNC_ARGOCD:-true}"
      echo ""
      echo "Press Ctrl+C to stop"
      echo ""

      exec watchexec \
        --debounce "''${NIXIDY_WATCH_DEBOUNCE:-2000}ms" \
        --exts nix,env \
        --watch "$STACKS_DIR/nixidy" \
        --watch "$STACKS_DIR/.env-files" \
        --ignore "result*" \
        --ignore "dist" \
        --ignore ".direnv" \
        --ignore "*.lock" \
        -- "$STACKS_DIR/scripts/nixidy-watch-handler.sh"
    '';

    # Manual nixidy rebuild (one-shot, no watching)
    "nixidy-rebuild".exec = ''
      STACKS_DIR="''${STACKS_DIR:-$DEVENV_ROOT}"
      "$STACKS_DIR/scripts/nixidy-watch-handler.sh"
    '';
  };

  # Background processes for `devenv up`
  processes = {
    # Nixidy file watcher - auto-rebuilds and deploys on file changes
    nixidy-watch = {
      exec = ''
        STACKS_DIR="''${STACKS_DIR:-$DEVENV_ROOT}"
        watchexec \
          --debounce "''${NIXIDY_WATCH_DEBOUNCE:-2000}ms" \
          --exts nix,env \
          --watch "$STACKS_DIR/nixidy" \
          --watch "$STACKS_DIR/.env-files" \
          --ignore "result*" \
          --ignore "dist" \
          --ignore ".direnv" \
          --ignore "*.lock" \
          -- "$STACKS_DIR/scripts/nixidy-watch-handler.sh"
      '';
      # Restart policy for process-compose
      process-compose = {
        availability = {
          restart = "on_failure";
          max_restarts = 10;
          backoff_seconds = 5;
        };
      };
    };
  };

  # Shell initialization message
  enterShell = ''
    echo "=================================================================="
    echo "  Hub-and-Spoke GitOps Development Environment"
    echo "=================================================================="
    echo ""
    echo "Nixidy Watch Mode (Auto-rebuild on file changes):"
    echo "  devenv up                        # Start watcher as background process"
    echo "  nixidy-watch                     # Start watcher in foreground"
    echo "  nixidy-rebuild                   # One-shot rebuild (no watching)"
    echo ""
    echo "CDK8s Commands (Legacy):"
    echo "  synth-kind                       # Synthesize manifests for KIND"
    echo "  synth-talos                      # Synthesize manifests for Talos (hub)"
    echo "  compile                          # TypeScript compilation check"
    echo ""
    echo "Hub Kargo Commands:"
    echo "  hub-kargo-status                 # Show hub Kargo resources"
    echo "  refresh-hub-kargo-warehouse [name]  # Trigger warehouse refresh"
    echo ""
    echo "Hub ArgoCD Commands:"
    echo "  hub-argocd-apps                  # List hub ArgoCD applications"
    echo "  hub-argocd-sync-all              # Sync all hub ArgoCD apps"
    echo ""
    echo "Configuration:"
    echo "  NIXIDY_WATCH_DEBOUNCE=2000       # Debounce delay in ms"
    echo "  NIXIDY_WATCH_SYNC_ARGOCD=true    # Auto-sync ArgoCD after deploy"
    echo ""
  '';

  # Environment variables
  env = {
    # Default to KIND for local development
    CLUSTER_TYPE = "kind";
    # Tailnet name for service URLs
    TAILNET_NAME = "tail286401";
    # Nixidy watch mode configuration
    NIXIDY_WATCH_DEBOUNCE = "2000";      # Debounce delay in milliseconds
    NIXIDY_WATCH_SYNC_ARGOCD = "true";   # Auto-sync ArgoCD after deploy
  };
}
