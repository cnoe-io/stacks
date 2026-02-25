#!/usr/bin/env bash
# Cluster management functions for stacks project
# Source this file or run directly to access cluster-* functions

# Automatically detect repository root (works in Codespaces, local, CI)
if [ -z "$STACKS_DIR" ]; then
  # Try git root first (most reliable)
  if STACKS_DIR=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$STACKS_DIR" ]; then
    export STACKS_DIR
  # Fallback: derive from script location
  elif [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    export STACKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  # Last resort: common paths
  elif [ -d "/workspaces/stacks" ]; then
    export STACKS_DIR="/workspaces/stacks"
  elif [ -d "/workspace/stacks" ]; then
    export STACKS_DIR="/workspace/stacks"
  elif [ -d "$HOME/stacks" ]; then
    export STACKS_DIR="$HOME/stacks"
  else
    echo "❌ Could not detect STACKS_DIR. Please set it manually: export STACKS_DIR=/path/to/stacks"
    return 1 2>/dev/null || exit 1
  fi
fi

# Source helpers
ARGOCD_AUTH_SCRIPT="$STACKS_DIR/deployment/scripts/argocd-auth.sh"
if [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
  source "$ARGOCD_AUTH_SCRIPT"
fi

NIXOS_KUBEVIRT_SCRIPT="$STACKS_DIR/deployment/scripts/nixos-kubevirt.sh"
if [ -f "$NIXOS_KUBEVIRT_SCRIPT" ]; then
  source "$NIXOS_KUBEVIRT_SCRIPT"
fi

DB_MIGRATIONS_SCRIPT="$STACKS_DIR/deployment/scripts/db-migrations.sh"
if [ -f "$DB_MIGRATIONS_SCRIPT" ]; then
  source "$DB_MIGRATIONS_SCRIPT"
fi

load-1password-token() {
  if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    if command -v az &>/dev/null && az account show &>/dev/null 2>&1; then
      local token=$(az keyvault secret show \
        --vault-name "${AZURE_KEYVAULT_NAME:-keyvault-thcmfmoo5oeow}" \
        --name "ONEPASSWORD-SERVICE-ACCOUNT-TOKEN" \
        --query value -o tsv 2>/dev/null)

      if [ -n "$token" ]; then
        export OP_SERVICE_ACCOUNT_TOKEN="$token"
        return 0
      fi
    fi
    if [ -f "/tmp/op-service-account-token.txt" ]; then
      export OP_SERVICE_ACCOUNT_TOKEN=$(cat /tmp/op-service-account-token.txt)
      return 0
    fi
  fi
  return 1
}

sync-manual-apps() {
  if ! command -v argocd &>/dev/null; then
    echo "⚠️  argocd CLI not found - skipping manual app sync"
    return 0
  fi
  if [ -z "$ARGOCD_AUTH_TOKEN" ]; then
    echo "⚠️  ARGOCD_AUTH_TOKEN not set - skipping manual app sync"
    return 0
  fi

  echo "🔄 Syncing applications without auto-sync..."
  local timeout=180
  local interval=5
  local elapsed=0

  echo "   Waiting for keycloak dependencies (up to ${timeout}s)..."
  while [ $elapsed -lt $timeout ]; do
    local keycloak_health=$(kubectl get application keycloak -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
    local secret_exists=$(kubectl get secret keycloak-clients -n keycloak --no-headers 2>/dev/null | wc -l)

    if [ "$keycloak_health" = "Healthy" ] && [ "$secret_exists" -gt 0 ]; then
      break
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  local manual_apps=$(kubectl get applications -n argocd -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.syncPolicy.automated == null and .status.sync.status == "OutOfSync") | .metadata.name' 2>/dev/null)

  if [ -z "$manual_apps" ]; then
    return 0
  fi

  for app in $manual_apps; do
    echo "   Syncing: $app"
    argocd app sync "argocd/$app" --insecure --async --timeout 300 2>/dev/null || echo "   ⚠️  Failed to sync: $app"
  done
}

KNOWN_HOSTS=(thinkpad ryzen hetzner)

detect_hostname() {
  local detected_host="${CLUSTER_HOST:-$(hostname)}"
  local is_known=false
  for known in "${KNOWN_HOSTS[@]}"; do
    if [[ "$detected_host" == "$known" ]]; then
      is_known=true
      break
    fi
  done
  if [ "$is_known" = false ]; then
    echo "❌ Unknown host: $detected_host" >&2
    return 1
  fi
  echo "$detected_host"
}

detect_host_context() {
  local hostname
  hostname="$(detect_hostname 2>/dev/null)"
  if [ -n "$hostname" ]; then
    local expected_ctx="kind-${hostname}"
    if kubectl config get-contexts -o name 2>/dev/null | grep -q "^${expected_ctx}$"; then
      echo "$expected_ctx"
      return 0
    fi
  fi
  local ctx
  ctx=$(kubectl config get-contexts -o name 2>/dev/null | grep '^kind-' | tail -1)
  if [ -z "$ctx" ]; then
    ctx=$(kubectl config current-context 2>/dev/null || echo "")
  fi
  echo "$ctx"
}

detect_cluster_name() {
  local hostname
  hostname="$(detect_hostname)" || return 1
  echo "$hostname"
}

check-azure-auth() {
  if [ "${SKIP_AZURE_AUTH:-}" = "true" ]; then
    return 0
  fi
  local token_expiry=$(az account get-access-token --query "expiresOn" -o tsv 2>/dev/null || echo "")
  if [ -z "$token_expiry" ]; then
    echo "❌ Azure authentication required"
    return 1
  fi
  return 0
}

generate-kind-config() {
  local TEMPLATE_FILE="$STACKS_DIR/deployment/config/kind-config.yaml.template"
  local OUTPUT_FILE="$STACKS_DIR/deployment/config/kind-config.yaml"

  if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "⚠️  kind-config.yaml.template not found, using existing kind-config.yaml"
    return 0
  fi

  echo "📝 Generating kind-config.yaml from template..."
  mkdir -p "$STACKS_DIR/deployment/config/containerd"
  
  local REGISTRY_AUTH_SCRIPT="$STACKS_DIR/deployment/scripts/setup-registry-auth.sh"
  if [ -f "$REGISTRY_AUTH_SCRIPT" ]; then
    "$REGISTRY_AUTH_SCRIPT"
  fi

  sed "s|\${STACKS_DIR}|$STACKS_DIR|g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"
}

fix-kind-hosts() {
  local CLUSTER_NAME="${1:-$(detect_hostname)}"
  echo "🔧 Fixing /etc/hosts on KIND nodes for gitea.cnoe.localtest.me..."

  local INGRESS_IP
  INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

  if [ -z "$INGRESS_IP" ]; then
    echo "⚠️  Could not get ingress-nginx ClusterIP, skipping hosts fix"
    return 0
  fi

  local nodes
  nodes=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${CLUSTER_NAME}-(control|worker)" || true)

  for node in $nodes; do
    docker exec "$node" sh -c "grep -q 'gitea.cnoe.localtest.me' /etc/hosts || echo '$INGRESS_IP gitea.cnoe.localtest.me' >> /etc/hosts" 2>/dev/null
  done
}

ensure-kargo-repos() {
  local CLUSTER_NAME="${1:-$(detect_hostname 2>/dev/null)}"
  if [ -z "$CLUSTER_NAME" ]; then
    return 0
  fi

  echo "🔧 Ensuring Kargo repositories exist for host: $CLUSTER_NAME"
  local GITEA_PASSWORD
  GITEA_PASSWORD=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [ -z "$GITEA_PASSWORD" ]; then
    return 0
  fi

  local GITEA_URL="https://gitea.cnoe.localtest.me:8443"
  local GITEA_USER="giteaadmin"
  local KARGO_REPOS=("gitops-${CLUSTER_NAME}-backstage-manifests")

  for repo in "${KARGO_REPOS[@]}"; do
    local repo_exists
    repo_exists=$(curl -k -s -o /dev/null -w "%{http_code}" -u "$GITEA_USER:$GITEA_PASSWORD" "$GITEA_URL/api/v1/repos/$GITEA_USER/$repo")
    if [ "$repo_exists" != "200" ]; then
      echo "   📦 Creating repository: $repo"
      curl -k -s -X POST "$GITEA_URL/api/v1/user/repos" -H "Content-Type: application/json" -u "$GITEA_USER:$GITEA_PASSWORD" -d "{\"name\": \"$repo\", \"private\": false, \"auto_init\": true}" > /dev/null || true
    fi
  done
}

seed-workflow-builder-gitea-repo() {
  local LOCAL_REPO="${WORKFLOW_BUILDER_LOCAL_REPO:-$HOME/repos/PittampalliOrg/workflow-builder/main}"
  local SOURCE_REF="${WORKFLOW_BUILDER_SEED_REF:-HEAD}"
  local GITEA_URL="${WORKFLOW_BUILDER_GITEA_URL:-https://gitea.cnoe.localtest.me:8443}"
  local GITEA_USER="${WORKFLOW_BUILDER_GITEA_USER:-giteaadmin}"
  local GITEA_OWNER="${WORKFLOW_BUILDER_GITEA_OWNER:-giteaadmin}"
  local GITEA_REPO="${WORKFLOW_BUILDER_GITEA_REPO:-workflow-builder}"

  if ! command -v git >/dev/null 2>&1; then return 0; fi
  if [ ! -d "$LOCAL_REPO" ] || ! git -C "$LOCAL_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then return 0; fi

  local GITEA_PASSWORD
  GITEA_PASSWORD=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
  if [ -z "$GITEA_PASSWORD" ]; then return 0; fi

  local ENCODED_PASSWORD="$GITEA_PASSWORD"
  if command -v jq >/dev/null 2>&1; then ENCODED_PASSWORD=$(printf '%s' "$GITEA_PASSWORD" | jq -sRr @uri); fi
  local REMOTE_URL="https://${GITEA_USER}:${ENCODED_PASSWORD}@gitea.cnoe.localtest.me:8443/${GITEA_OWNER}/${GITEA_REPO}.git"

  echo "⬆️  Seeding ${GITEA_OWNER}/${GITEA_REPO} from local ${LOCAL_REPO}..."
  curl -k -s -X POST "${GITEA_URL}/api/v1/user/repos" -H "Content-Type: application/json" -u "${GITEA_USER}:${GITEA_PASSWORD}" -d "{\"name\": \"${GITEA_REPO}\", \"private\": false, \"auto_init\": true, \"default_branch\": \"main\"}" >/dev/null || true
  GIT_SSL_NO_VERIFY=true git -C "$LOCAL_REPO" push --force "$REMOTE_URL" "${SOURCE_REF}:refs/heads/main" >/dev/null 2>&1 || true
}

seed-stacks-gitea-repo() {
  local LOCAL_REPO="${STACKS_DIR}"
  local SOURCE_REF="${STACKS_SEED_REF:-HEAD}"
  local GITEA_URL="${STACKS_GITEA_URL:-https://gitea.cnoe.localtest.me:8443}"
  local GITEA_USER="${STACKS_GITEA_USER:-giteaadmin}"
  local GITEA_OWNER="${STACKS_GITEA_OWNER:-giteaadmin}"
  local GITEA_REPO="${STACKS_GITEA_REPO:-stacks}"

  if ! command -v git >/dev/null 2>&1; then return 0; fi
  if [ ! -d "$LOCAL_REPO" ] || ! git -C "$LOCAL_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then return 0; fi

  local GITEA_PASSWORD
  GITEA_PASSWORD=$(kubectl get secret gitea-credential -n gitea -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
  if [ -z "$GITEA_PASSWORD" ]; then return 0; fi

  local ENCODED_PASSWORD="$GITEA_PASSWORD"
  if command -v jq >/dev/null 2>&1; then ENCODED_PASSWORD=$(printf '%s' "$GITEA_PASSWORD" | jq -sRr @uri); fi
  local REMOTE_URL="https://${GITEA_USER}:${ENCODED_PASSWORD}@gitea.cnoe.localtest.me:8443/${GITEA_OWNER}/${GITEA_REPO}.git"

  echo "⬆️  Seeding ${GITEA_OWNER}/${GITEA_REPO} from local ${LOCAL_REPO}..."
  curl -k -s -X POST "${GITEA_URL}/api/v1/user/repos" -H "Content-Type: application/json" -u "${GITEA_USER}:${GITEA_PASSWORD}" -d "{\"name\": \"${GITEA_REPO}\", \"private\": false, \"auto_init\": true, \"default_branch\": \"main\"}" >/dev/null || true
  GIT_SSL_NO_VERIFY=true git -C "$LOCAL_REPO" push --force "$REMOTE_URL" "${SOURCE_REF}:refs/heads/main" >/dev/null 2>&1 || true
}

cluster-deploy() {
  if [ "${SKIP_AZURE_CHECK:-}" != "true" ]; then
    echo "🔐 Checking Azure authentication..."
    check-azure-auth || return 1
  fi

  local DEPLOY_DIR="$STACKS_DIR/deployment"
  local ORIG_DIR="$(pwd)"

  [ -f "$STACKS_DIR/.env-files/kind.env" ] && { set -a; source "$STACKS_DIR/.env-files/kind.env"; set +a; }

  export CLUSTER_HOST="$(detect_hostname)" || return 1
  echo "🏷️  Detected host: ${CLUSTER_HOST}"

  if command -v op &>/dev/null; then load-1password-token; fi

  generate-kind-config

  local KUSTOMIZE_ENV="kind"
  if [ -d "$STACKS_DIR/packages/overlays/kind-${CLUSTER_HOST}" ]; then
    KUSTOMIZE_ENV="kind-${CLUSTER_HOST}"
  fi
  sed "s|\${KUSTOMIZE_ENV}|$KUSTOMIZE_ENV|g" "$DEPLOY_DIR/config/argocd-bootstrap.yaml.template" > "$DEPLOY_DIR/config/argocd-bootstrap.yaml"

  echo "🚀 Creating cluster with kind..."
  kind create cluster --name "$CLUSTER_HOST" --config "$DEPLOY_DIR/config/kind-config.yaml"

  "$STACKS_DIR/deployment/scripts/bootstrap-local-infra.sh"

  fix-kind-hosts "${CLUSTER_HOST}"
  ensure-kargo-repos "${CLUSTER_HOST}"
  seed-workflow-builder-gitea-repo
  seed-stacks-gitea-repo

  echo "📦 Installing ArgoCD..."
  "$STACKS_DIR/scripts/01-install-argocd.sh"

  echo "⚡ Applying ArgoCD Performance overrides..."
  kubectl apply -f "$DEPLOY_DIR/overrides/argocd-performance.yaml"

  echo "🚀 Applying Root Application..."
  kubectl apply -f "$DEPLOY_DIR/config/argocd-bootstrap.yaml"

  local JWKS_SCRIPT="$STACKS_DIR/ref-implementation/azure-workload-identity/sync-jwks-to-azure.sh"
  if [ -f "$JWKS_SCRIPT" ]; then
    echo "🔄 Syncing JWKS to Azure for External Secrets..."
    "$JWKS_SCRIPT"
  fi

  if [ "${SKIP_ARGOCD_INIT:-}" != "true" ] && command -v argocd &>/dev/null && [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
    sleep 2
    argocd-auth-init
    sync-manual-apps
  fi

  if [ "${SKIP_TAILSCALE_TOKEN:-}" != "true" ] && [ -f "$STACKS_DIR/deployment/scripts/tailscale/tailscale-kubeconfig.sh" ]; then
    echo "🔑 Generating Tailscale remote access token in background..."
    nohup "$STACKS_DIR/deployment/scripts/tailscale/tailscale-kubeconfig.sh" generate > /tmp/tailscale-token-generation.log 2>&1 &
  fi

  cd "$ORIG_DIR"
  return 0
}

cluster-build() {
  echo "✅ Kustomize builds are now handled natively by ArgoCD via GitOps."
}

cluster-synth() {
  cluster-build
}

cluster-recreate() {
  local CLUSTER_NAME="$(detect_cluster_name)"
  echo "🗑️  Deleting cluster: ${CLUSTER_NAME}..."
  kind delete cluster --name "${CLUSTER_NAME}"
  unset ARGOCD_AUTH_TOKEN
  SKIP_AZURE_CHECK=true cluster-deploy "$@"
}

cluster-update() {
  echo "🔄 Syncing local repository to Gitea for ArgoCD update..."
  seed-stacks-gitea-repo
  echo "✅ Repository synced. ArgoCD will automatically detect changes and apply them."
}

cluster-update-gum() {
  cluster-update
}

cluster-status() {
  local HOST_CONTEXT="$(detect_host_context)"
  echo "🔍 CLUSTER STATUS"
  if kubectl --context "$HOST_CONTEXT" cluster-info &>/dev/null; then
    echo "✅ Cluster is running"
    kubectl get nodes
    if command -v argocd &>/dev/null && [ -f "$ARGOCD_AUTH_SCRIPT" ]; then
      argocd-status 2>/dev/null || kubectl get applications -n argocd 2>/dev/null
    else
      kubectl get applications -n argocd 2>/dev/null
    fi
  else
    echo "❌ No cluster found"
  fi
}

cluster-reconcile-mcp-services() {
  local namespace="${1:-workflow-builder}"
  kubectl create job --from="cronjob/activepieces-mcp-reconciler" "activepieces-mcp-reconcile-manual-$(date +%s)" -n "$namespace" >/dev/null || true
  echo "✅ Triggered Activepieces MCP reconciliation"
}

cluster-reconcile-workflow-builder-db() {
  if [ -f "$DB_MIGRATIONS_SCRIPT" ]; then run-workflow-builder-atlas-migrations; fi
}

cluster-mcp-services-status() {
  echo "🧩 ACTIVEPIECES MCP SERVICE STATUS"
}

cluster-menu() {
  if ! command -v gum &>/dev/null; then return 1; fi
  while true; do
    local choice=$(gum choose "Deploy Cluster" "Update Cluster" "Recreate Cluster" "Show Status" "Exit")
    case "$choice" in
      "Deploy Cluster") cluster-deploy ;;
      "Update Cluster") cluster-update ;;
      "Recreate Cluster") cluster-recreate ;;
      "Show Status") cluster-status ;;
      "Exit") break ;;
    esac
  done
}

alias clb="cluster-build"
alias cls="cluster-synth"
alias cld="cluster-deploy"
alias clu="cluster-update"
alias cluw="cluster-update"
alias clug="cluster-update-gum"
alias clr="cluster-recreate"
alias clst="cluster-status"
alias clm="cluster-menu"

TAILSCALE_KUBECONFIG_SCRIPT="$STACKS_DIR/deployment/scripts/tailscale/tailscale-kubeconfig.sh"
if [ -f "$TAILSCALE_KUBECONFIG_SCRIPT" ]; then
  alias ts-kubeconfig="$TAILSCALE_KUBECONFIG_SCRIPT"
  alias ts-kubeconfig-gen="$TAILSCALE_KUBECONFIG_SCRIPT generate"
fi

DEVENV_UP_SCRIPT="$STACKS_DIR/deployment/scripts/devenv-up.sh"
if [ -f "$DEVENV_UP_SCRIPT" ]; then
  alias dev-watch="$DEVENV_UP_SCRIPT"
  alias dev-watch-only="$DEVENV_UP_SCRIPT --watch"
fi
