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
# Uses a placeholder IP that gets patched after KIND cluster creation.
# See patch_gitea_registry_ip() for the post-create fixup.
setup_gitea() {
  local cp_ip="${GITEA_CONTROL_PLANE_IP:-PLACEHOLDER_CP_IP}"

  # Config for gitea.cnoe.localtest.me (no port - how Deployments reference images)
  local dir="$CONTAINERD_DIR/gitea.cnoe.localtest.me"
  mkdir -p "$dir"
  cat > "$dir/hosts.toml" << EOF
server = "https://gitea.cnoe.localtest.me"

[host."https://${cp_ip}:443"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
  [host."https://${cp_ip}:443".header]
    Host = ["gitea.cnoe.localtest.me"]
EOF
  log "gitea: configured (control-plane IP: ${cp_ip}, TLS skip)"
}

# Patch the Gitea registry config with the actual control-plane IP.
# Called AFTER KIND cluster creation when the real IP is known.
# Updates the host-side config files (bind-mounted read-only into nodes).
# containerd reads hosts.toml fresh on each pull, so no restart needed.
patch_gitea_registry_ip() {
  local cluster_name="${1:?Usage: patch_gitea_registry_ip <cluster-name>}"
  local cp_ip
  cp_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${cluster_name}-control-plane" 2>/dev/null || true)

  if [ -z "$cp_ip" ]; then
    log "ERROR: Could not detect control-plane IP for cluster ${cluster_name}"
    return 1
  fi

  log "Patching Gitea registry config with control-plane IP: ${cp_ip}"

  # Update the host-side config files (mounted read-only into KIND nodes)
  for hosts_file in "$CONTAINERD_DIR/gitea.cnoe.localtest.me/hosts.toml"; do
    if [ -f "$hosts_file" ]; then
      sed -i "s|PLACEHOLDER_CP_IP|${cp_ip}|g" "$hosts_file"
      sed -i -E "s|https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:443|https://${cp_ip}:443|g" "$hosts_file"
    fi
  done

  # Verify
  local node
  node=$(kind get nodes --name "$cluster_name" 2>/dev/null | head -1)
  if [ -n "$node" ]; then
    log "Verified on ${node}:"
    docker exec "$node" cat /etc/containerd/certs.d/gitea.cnoe.localtest.me/hosts.toml 2>/dev/null | head -5
  fi

  log "Gitea registry config patched successfully (${cp_ip}:443)"
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
