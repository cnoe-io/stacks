#!/usr/bin/env bash
set -euo pipefail

# Rebuild local kubeconfigs for vclusters when running on native Linux.
# Prioritises straightforward context names (dev, staging) and merges them
# into the standard kubeconfig without WSL-specific tweaks.

# Stages to configure
VCLUSTER_STAGES=("dev" "staging")

# Preferred host-cluster context(s) to fall back to after merging
if [ -n "${HOST_CONTEXT_OVERRIDE:-}" ]; then
  HOST_CONTEXT_CANDIDATES=(${HOST_CONTEXT_OVERRIDE})
else
  HOST_CONTEXT_CANDIDATES=()
fi
HOST_CONTEXT_CANDIDATES+=("kind-local" "kind-localdev" "kind-kind")
HOST_CONTEXT=""

# Base domain/port for the ingress endpoints that front the vcluster apiservers
VCLUSTER_BASE_DOMAIN=${VCLUSTER_BASE_DOMAIN:-cnoe.localtest.me}
VCLUSTER_TLS_PORT=${VCLUSTER_TLS_PORT:-8443}

# Main kubeconfig location (respects KUBECONFIG if set)
MAIN_KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

# Utilities
log() { printf '\033[0;32m%s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$1"; }
error() { printf '\033[0;31m%s\033[0m\n' "$1"; }

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command: $1"
    exit 1
  fi
}

ensure_host_cluster() {
  local current=$(kubectl config current-context 2>/dev/null || echo "")
  if [ -n "$current" ]; then
    for candidate in "${HOST_CONTEXT_CANDIDATES[@]}"; do
      if [ "$current" = "$candidate" ] && kubectl --context "$candidate" cluster-info >/dev/null 2>&1; then
        HOST_CONTEXT="$candidate"
        return
      fi
    done
  fi

  for candidate in "${HOST_CONTEXT_CANDIDATES[@]}"; do
    [ -n "$candidate" ] || continue
    if kubectl --context "$candidate" cluster-info >/dev/null 2>&1; then
      HOST_CONTEXT="$candidate"
      KUBECONFIG="$MAIN_KUBECONFIG" kubectl config use-context "$candidate" >/dev/null 2>&1 || true
      return
    fi
  done

  error "Cannot reach the host cluster. Is Kind running?"
  exit 1
}

wait_for_vcluster_pod() {
  local env=$1
  local namespace="${env}-vcluster"
  local pod="vcluster-${env}-helm-0"

  for _ in {1..60}; do
    if kubectl --context "$HOST_CONTEXT" get pod "$pod" -n "$namespace" >/dev/null 2>&1; then
      local phase
      phase=$(kubectl --context "$HOST_CONTEXT" get pod "$pod" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
      if [[ "$phase" == "Running" ]]; then
        return 0
      fi
    fi
    sleep 2
  done

  return 1
}

build_ingress_server() {
  local env=$1
  printf 'https://%s-vcluster.%s:%s' "$env" "$VCLUSTER_BASE_DOMAIN" "$VCLUSTER_TLS_PORT"
}

apply_vcluster_context() {
  local env=$1
  local cluster_name="vcluster-${env}"
  local user_name="vcluster-${env}"
  local namespace="${env}-vcluster"
  local secret_name="vc-vcluster-${env}-helm"
  local server

  server=$(build_ingress_server "$env")

  local ca client key
  ca=$(kubectl --context "$HOST_CONTEXT" get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.certificate-authority}' 2>/dev/null || echo "")
  client=$(kubectl --context "$HOST_CONTEXT" get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.client-certificate}' 2>/dev/null || echo "")
  key=$(kubectl --context "$HOST_CONTEXT" get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.client-key}' 2>/dev/null || echo "")

  if [[ -z "$ca" || -z "$client" || -z "$key" ]]; then
    error "Required certificates missing in secret ${secret_name} (env: ${env})"
    return 1
  fi

  local ca_file="${TEMP_DIR}/${env}-ca.crt"
  local cert_file="${TEMP_DIR}/${env}-client.crt"
  local key_file="${TEMP_DIR}/${env}-client.key"

  echo "$ca" | base64 -d > "$ca_file"
  echo "$client" | base64 -d > "$cert_file"
  echo "$key" | base64 -d > "$key_file"

  KUBECONFIG="$MAIN_KUBECONFIG" kubectl config delete-context "$env" >/dev/null 2>&1 || true
  KUBECONFIG="$MAIN_KUBECONFIG" kubectl config delete-cluster "$cluster_name" >/dev/null 2>&1 || true
  KUBECONFIG="$MAIN_KUBECONFIG" kubectl config delete-user "$user_name" >/dev/null 2>&1 || true

  KUBECONFIG="$MAIN_KUBECONFIG" kubectl config set-cluster "$cluster_name" \
    --server="$server" \
    --certificate-authority="$ca_file" \
    --embed-certs=true >/dev/null

  KUBECONFIG="$MAIN_KUBECONFIG" kubectl config set-credentials "$user_name" \
    --client-certificate="$cert_file" \
    --client-key="$key_file" \
    --embed-certs=true >/dev/null

  KUBECONFIG="$MAIN_KUBECONFIG" kubectl config set-context "$env" \
    --cluster="$cluster_name" \
    --user="$user_name" \
    --namespace=default >/dev/null

  log "✓ Configured context '${env}'"
}

verify_contexts() {
  local contexts=($@)
  for env in "${contexts[@]}"; do
    printf 'Validating context %s... ' "$env"
    if kubectl --context "$env" get ns >/dev/null 2>&1; then
      printf '\033[0;32mok\033[0m\n'
    else
      printf '\033[1;33mwarning (unable to connect)\033[0m\n'
    fi
  done
}

set_default_context() {
  local configured=($@)
  local candidates=("${HOST_CONTEXT_CANDIDATES[@]}" "${configured[@]}")

  for candidate in "${candidates[@]}"; do
    [ -n "$candidate" ] || continue
    if KUBECONFIG="$MAIN_KUBECONFIG" kubectl config get-contexts "$candidate" >/dev/null 2>&1; then
      if KUBECONFIG="$MAIN_KUBECONFIG" kubectl config use-context "$candidate" >/dev/null 2>&1; then
        log "Default context set to ${candidate}"
        return
      fi
    fi
  done

  warn "Unable to set default kube context automatically"
}

main() {
  require kubectl

  ensure_host_cluster
  mkdir -p "$(dirname "$MAIN_KUBECONFIG")"
  touch "$MAIN_KUBECONFIG"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup="${MAIN_KUBECONFIG}.bak.${timestamp}"
  cp "$MAIN_KUBECONFIG" "$backup"
  log "Backup of existing kubeconfig: ${backup}"

  # Remove stale current-context before re-applying entries
  KUBECONFIG="$MAIN_KUBECONFIG" kubectl config unset current-context >/dev/null 2>&1 || true

  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TEMP_DIR"' EXIT

  local configured=()

  for env in "${VCLUSTER_STAGES[@]}"; do
    log "Configuring ${env} vcluster"
    if ! wait_for_vcluster_pod "$env"; then
      warn "${env} vcluster is not ready; skipping"
      continue
    fi

    if apply_vcluster_context "$env"; then
      configured+=("$env")
    else
      warn "Skipped ${env} due to missing credentials"
    fi
  done

  if [[ ${#configured[@]} -eq 0 ]]; then
    warn "No vcluster kubeconfigs were generated"
    exit 0
  fi

  verify_contexts "${configured[@]}"
  set_default_context "${configured[@]}"

  echo
  log "Contexts available: ${configured[*]}"
}

main "$@"
