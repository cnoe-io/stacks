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
    pkgs.kustomize
    pkgs.argocd
    pkgs.watchexec  # File watcher for auto-rebuild on manifest changes
    # Open SWE / LangGraph development
    pkgs.python311
    pkgs.python311Packages.pip
    pkgs.python311Packages.virtualenv
  ];

  # Custom scripts for development workflows
  scripts = {
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

    # Build kustomize packages for the current host
    "kustomize-build".exec = ''
      if [ -n "$CLUSTER_HOST" ]; then
        CLUSTER_NAME="$CLUSTER_HOST"
      else
        CLUSTER_NAME="$(hostname -s 2>/dev/null || hostname)"
      fi
      cd "$DEVENV_ROOT/packages"
      make build-kustomize-kind-$CLUSTER_NAME
    '';

    # Apply manifests to cluster (one-shot, exits when done)
    "apply-manifests".exec = ''
      source "$DEVENV_ROOT/deployment/scripts/cluster-menu.sh"
      cluster-update
    '';

    # Watch source manifests and rebuild on change (manual alternative to devenv up)
    "watch-kustomize".exec = ''
      if [ -n "$CLUSTER_HOST" ]; then
        CLUSTER_NAME="$CLUSTER_HOST"
      else
        CLUSTER_NAME="$(hostname -s 2>/dev/null || hostname)"
      fi
      echo "👁️  Watching packages/ for changes (Ctrl+C to stop)..."
      watchexec \
        --debounce 2000ms \
        --exts yaml,yml,json,sh \
        --watch "$DEVENV_ROOT/packages/base" \
        --watch "$DEVENV_ROOT/packages/components" \
        --watch "$DEVENV_ROOT/packages/overlays" \
        --watch "$DEVENV_ROOT/packages/scripts" \
        --watch "$DEVENV_ROOT/deployment/scripts" \
        --ignore "dist" \
        -- sh -c "echo '🔄 Change detected...'; cd '$DEVENV_ROOT/packages' && make build-kustomize-kind-$CLUSTER_NAME"
    '';

    # Open SWE status check
    "open-swe-status".exec = ''
      echo "=== Open SWE Status ==="
      echo ""
      echo "Agent Sandbox:"
      kubectl get sandboxes,sandboxtemplates,sandboxwarmpools -n agent-sandbox 2>/dev/null || echo "  Not deployed yet"
      echo ""
      echo "Open SWE Pods:"
      kubectl get pods -n open-swe 2>/dev/null || echo "  Not deployed yet"
      echo ""
      echo "External Secrets:"
      kubectl get externalsecrets -n open-swe 2>/dev/null || echo "  Not deployed yet"
    '';

    # Open SWE logs
    "open-swe-logs".exec = ''
      kubectl logs -n open-swe -l app.kubernetes.io/name=langgraph-cloud-api-server -f --tail=100
    '';

    # Image preloading from Docker cache to KIND + Gitea
    "preload-images".exec = ''
      if [ -n "$CLUSTER_HOST" ]; then
        CLUSTER_NAME="$CLUSTER_HOST"
      else
        CLUSTER_NAME="$(hostname -s 2>/dev/null || hostname)"
      fi
      "$DEVENV_ROOT/deployment/scripts/preload-images.sh" "$CLUSTER_NAME"
    '';
  };

  # NOTE: `devenv up` (processes) is NOT used - devenv-tasks generates a wrapper
  # that re-exports all inherited env vars including BASH_FUNC_*%% from fzf/sesh,
  # which causes "not a valid identifier" errors that cannot be fixed from within
  # the process script. Use `dev-watch` (standalone script) instead.

  # Shell initialization message
  enterShell = ''
    echo "=================================================================="
    echo "  Kustomize GitOps Development Environment"
    echo "=================================================================="
    echo ""
    echo "Manifest Development:"
    echo "  dev-watch                        # Watch + rebuild + apply (standalone)"
    echo "  dev-watch-only                   # Watch only (skip initial build+apply)"
    echo "  watch-kustomize                  # Watch + rebuild only (no apply)"
    echo "  kustomize-build                  # Build kustomize packages (one-shot)"
    echo "  apply-manifests                  # Apply manifests (one-shot)"
    echo ""
    echo "Hub Kargo Commands:"
    echo "  hub-kargo-status                 # Show hub Kargo resources"
    echo "  refresh-hub-kargo-warehouse [name]  # Trigger warehouse refresh"
    echo ""
    echo "Hub ArgoCD Commands:"
    echo "  hub-argocd-apps                  # List hub ArgoCD applications"
    echo "  hub-argocd-sync-all              # Sync all hub ArgoCD apps"
    echo ""
    echo "Open SWE Commands:"
    echo "  open-swe-status                  # Show Open SWE deployment status"
    echo "  open-swe-logs                    # Tail Open SWE API server logs"
    echo ""
    echo "Image Management:"
    echo "  preload-images                   # Load Docker cache images to KIND + Gitea"
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
