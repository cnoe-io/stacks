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
        --exts nix,env,yaml \
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

    # Gitea webhook listener - streams push notifications with desktop notifications
    # KIND on Linux can't reach host, so we deploy a receiver pod and stream its logs
    "gitea-listen".exec = ''
      STACKS_DIR="''${STACKS_DIR:-$DEVENV_ROOT}"
      exec "$STACKS_DIR/scripts/gitea-webhook-notify.sh"
    '';

    # Register webhooks with all Gitea repos (one-time setup)
    "gitea-webhook-setup".exec = ''
      STACKS_DIR="''${STACKS_DIR:-$DEVENV_ROOT}"
      source "$STACKS_DIR/.env-files/kind.env" 2>/dev/null || true
      exec "$STACKS_DIR/scripts/gitea-webhook-setup-devenv.sh"
    '';
  };

  # Background processes for `devenv up`
  processes = {
    # Nixidy file watcher - auto-rebuilds and deploys on file changes
    nixidy-watch = {
      exec = ''
        STACKS_DIR="''${STACKS_DIR:-$DEVENV_ROOT}"
        # Use script -q to create a pseudo-TTY, enabling watchexec to forward child output
        # The -c option runs the command, -q suppresses script's own messages
        exec script -q -c "watchexec \
          --debounce ''${NIXIDY_WATCH_DEBOUNCE:-2000}ms \
          --exts nix,env,yaml \
          --watch $STACKS_DIR/nixidy \
          --watch $STACKS_DIR/.env-files \
          --ignore 'result*' \
          --ignore dist \
          --ignore .direnv \
          --ignore '*.lock' \
          -- $STACKS_DIR/scripts/nixidy-watch-handler.sh" /dev/null
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

    # Gitea webhook listener - streams push notifications with desktop notifications
    # KIND on Linux can't reach host, so we deploy a receiver pod and stream its logs
    gitea-webhook = {
      exec = ''
        STACKS_DIR="''${STACKS_DIR:-$DEVENV_ROOT}"
        exec "$STACKS_DIR/scripts/gitea-webhook-notify.sh"
      '';
      process-compose = {
        availability = {
          restart = "on_failure";
          max_restarts = 5;
          backoff_seconds = 3;
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
    echo "Gitea Change Notifications:"
    echo "  gitea-listen                     # Start webhook listener (foreground)"
    echo "  gitea-webhook-setup              # Register webhooks with all repos (one-time)"
    echo "  (devenv up starts listener automatically on port 9999)"
    echo ""
    echo "Configuration:"
    echo "  NIXIDY_WATCH_DEBOUNCE=2000       # Debounce delay in ms"
    echo "  NIXIDY_WATCH_POLL=1000           # Poll interval in ms (for Claude Code edits)"
    echo "  NIXIDY_WATCH_SYNC_ARGOCD=true    # Auto-sync ArgoCD after deploy"
    echo "  NIXIDY_WATCH_SHOW_DIFF=false     # Show detailed manifest diffs"
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
    NIXIDY_WATCH_POLL = "1000";          # Poll interval in ms (needed for Claude Code edits)
    NIXIDY_WATCH_SYNC_ARGOCD = "true";   # Auto-sync ArgoCD after deploy
    NIXIDY_WATCH_SHOW_DIFF = "false";    # Show detailed diff of changed manifests
    # Gitea webhook listener configuration
    GITEA_WEBHOOK_PORT = "9999";         # Port for webhook listener
    GITEA_URL = "https://gitea.cnoe.localtest.me:8443";  # Gitea server URL
  };
}
