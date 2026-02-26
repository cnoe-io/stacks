#!/usr/bin/env bash
# setup-registry-auth.sh - Generate containerd registry auth configs
# Called by cluster-menu.sh during generate-kind-config
#
# This script creates hosts.toml files for container registries with authentication
# to avoid rate limits and enable faster image pulls.
#
# Supported registries:
#   - docker.io (Docker Hub) - uses 1Password credentials
#   - ghcr.io (GitHub Container Registry) - uses gh CLI token
#   - gitea.cnoe.localtest.me - local Gitea registry (no auth needed for pull)

set -euo pipefail

STACKS_DIR="${STACKS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CONTAINERD_DIR="$STACKS_DIR/deployment/config/containerd"
LOG_PREFIX="[registry-auth]"

log() { echo "$LOG_PREFIX $1"; }

# Setup Docker Hub auth from 1Password
setup_dockerhub() {
  local dir="$CONTAINERD_DIR/docker.io"
  local hosts_file="$dir/hosts.toml"

  if [ -f "$hosts_file" ]; then
    log "docker.io: already configured"
    return 0
  fi

  mkdir -p "$dir"

  # Try to get credentials from 1Password
  local user password auth
  if command -v op &>/dev/null; then
    user=$(op item get "DOCKER_PERSONAL_ACCESS_TOKEN" --vault CLI --fields label=username --reveal 2>/dev/null || true)
    password=$(op item get "DOCKER_PERSONAL_ACCESS_TOKEN" --vault CLI --fields label=password --reveal 2>/dev/null || true)
  fi

  if [ -n "$user" ] && [ -n "$password" ]; then
    auth=$(echo -n "${user}:${password}" | base64 -w0)
    cat > "$hosts_file" << EOF
server = "https://registry-1.docker.io"

[host."https://registry-1.docker.io"]
  capabilities = ["pull", "resolve"]
  [host."https://registry-1.docker.io".header]
    Authorization = ["Basic ${auth}"]
EOF
    log "docker.io: configured with 1Password credentials"
  else
    log "docker.io: skipped (no 1Password credentials found)"
  fi
}

# Setup GitHub Container Registry auth from gh CLI
setup_ghcr() {
  local dir="$CONTAINERD_DIR/ghcr.io"
  local hosts_file="$dir/hosts.toml"

  mkdir -p "$dir"

  # Get token from gh CLI
  local token user auth
  if command -v gh &>/dev/null; then
    token=$(gh auth token 2>/dev/null || true)
    user=$(gh api user --jq '.login' 2>/dev/null || echo "user")
  fi

  if [ -n "$token" ]; then
    auth=$(echo -n "${user}:${token}" | base64 -w0)
    cat > "$hosts_file" << EOF
server = "https://ghcr.io"

[host."https://ghcr.io"]
  capabilities = ["pull", "resolve"]
  [host."https://ghcr.io".header]
    Authorization = ["Basic ${auth}"]
EOF
    log "ghcr.io: configured with gh CLI token (user: $user)"
  else
    log "ghcr.io: skipped (gh CLI not authenticated)"
  fi
}

# Setup local Gitea registry
# Uses domain-based routing with skip_verify for self-signed certs.
# The /etc/hosts entry on Kind nodes maps gitea.cnoe.localtest.me to the
# control-plane IP (where ingress-nginx runs with hostPort 443).
# This is required because Gitea's OCI registry Bearer token auth uses ROOT_URL
# in the www-authenticate header, and localtest.me resolves to ::1 by default.
# See: https://github.com/go-gitea/gitea/issues/29591
setup_gitea() {
  # Config for gitea.cnoe.localtest.me (no port - how Deployments reference images)
  local dir="$CONTAINERD_DIR/gitea.cnoe.localtest.me"
  mkdir -p "$dir"
  cat > "$dir/hosts.toml" << EOF
server = "https://gitea.cnoe.localtest.me"

[host."https://gitea.cnoe.localtest.me"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF
  log "gitea: configured (domain-based routing with TLS skip)"
}

# Patch /etc/hosts on Kind nodes so gitea.cnoe.localtest.me resolves to the
# control-plane IP instead of ::1 (default for localtest.me).
# This is required for Gitea OCI registry Bearer token auth to work from kubelet.
# Called AFTER KIND cluster creation when the real IP is known.
patch_gitea_registry_ip() {
  local cluster_name="${1:?Usage: patch_gitea_registry_ip <cluster-name>}"
  local cp_ip
  cp_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${cluster_name}-control-plane" 2>/dev/null || true)

  if [ -z "$cp_ip" ]; then
    log "ERROR: Could not detect control-plane IP for cluster ${cluster_name}"
    return 1
  fi

  log "Patching /etc/hosts on Kind nodes with control-plane IP: ${cp_ip}"

  # Add /etc/hosts entry on all nodes so gitea.cnoe.localtest.me resolves correctly.
  # localtest.me resolves to 127.0.0.1/::1 by default, which doesn't work inside Kind
  # because ingress-nginx runs on the control-plane node's docker IP.
  local node
  for node in $(kind get nodes --name "$cluster_name" 2>/dev/null); do
    # Remove any existing gitea entry, then add the correct one
    docker exec "$node" sh -c "sed -i '/gitea.cnoe.localtest.me/d' /etc/hosts; echo '${cp_ip} gitea.cnoe.localtest.me' >> /etc/hosts"
    log "  ${node}: /etc/hosts updated (${cp_ip} gitea.cnoe.localtest.me)"
  done

  # Also update hosts.toml if it was bind-mounted read-only and has the old IP format
  for hosts_file in "$CONTAINERD_DIR/gitea.cnoe.localtest.me/hosts.toml"; do
    if [ -f "$hosts_file" ] && grep -q "PLACEHOLDER_CP_IP" "$hosts_file"; then
      sed -i "s|PLACEHOLDER_CP_IP|${cp_ip}|g" "$hosts_file"
    fi
  done

  # Remount certs.d as rw if needed (Kind mounts it ro from host)
  for node in $(kind get nodes --name "$cluster_name" 2>/dev/null); do
    docker exec "$node" mount -o remount,rw /etc/containerd/certs.d 2>/dev/null || true
  done

  # Verify
  node=$(kind get nodes --name "$cluster_name" 2>/dev/null | head -1)
  if [ -n "$node" ]; then
    log "Verified on ${node}:"
    docker exec "$node" cat /etc/containerd/certs.d/gitea.cnoe.localtest.me/hosts.toml 2>/dev/null | head -5
    docker exec "$node" getent hosts gitea.cnoe.localtest.me 2>/dev/null
  fi

  log "Gitea registry config patched successfully (${cp_ip})"
}

main() {
  log "Setting up container registry authentication..."
  mkdir -p "$CONTAINERD_DIR"

  setup_dockerhub
  setup_ghcr
  setup_gitea

  log "Registry auth setup complete"
  ls -la "$CONTAINERD_DIR"
}

main "$@"
