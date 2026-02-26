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
# Images reference gitea.cnoe.localtest.me (standard HTTPS port 443).
# NGINX ingress runs with hostNetwork on the control-plane node, so we
# redirect containerd to the control-plane's Docker network IP to avoid
# DNS resolving to ::1/127.0.0.1 (which only works on the control-plane).
setup_gitea() {
  # Detect control-plane IP for KIND cluster
  local cp_ip=""
  if command -v docker &>/dev/null; then
    # Find the KIND control-plane container IP
    local cluster_name="${KIND_CLUSTER_NAME:-}"
    if [ -z "$cluster_name" ]; then
      # Try to detect from running containers
      cluster_name=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -o '^[^-]*' | grep -v '^$' | sort -u | head -1)
    fi
    if [ -n "$cluster_name" ]; then
      cp_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${cluster_name}-control-plane" 2>/dev/null || true)
    fi
  fi

  if [ -z "$cp_ip" ]; then
    log "gitea: WARNING - could not detect control-plane IP, using localhost (may fail on worker nodes)"
    cp_ip="127.0.0.1"
  fi

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
  log "gitea: configured (redirect to control-plane ${cp_ip}:443, TLS skip)"

  # Also keep legacy config for gitea.cnoe.localtest.me:8443 (used by push-devcontainers.sh)
  local dir8443="$CONTAINERD_DIR/gitea.cnoe.localtest.me:8443"
  mkdir -p "$dir8443"
  cat > "$dir8443/hosts.toml" << EOF
server = "https://gitea.cnoe.localtest.me:8443"

[host."https://${cp_ip}:443"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
  [host."https://${cp_ip}:443".header]
    Host = ["gitea.cnoe.localtest.me"]
EOF
  log "gitea:8443: configured (redirect to control-plane ${cp_ip}:443, TLS skip)"
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
