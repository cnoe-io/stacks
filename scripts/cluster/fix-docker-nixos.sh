#!/usr/bin/env bash

# Fix Docker environment for NixOS when WSL variables are incorrectly set

echo "Checking Docker configuration..."

# Check if DOCKER_HOST is set to WSL path
if [[ -n "${DOCKER_HOST:-}" ]] && [[ "${DOCKER_HOST}" == *"wsl"* ]]; then
    echo "Found WSL Docker host setting: ${DOCKER_HOST}"
    
    # Check if native Docker socket exists
    if [[ -S /var/run/docker.sock ]]; then
        echo "Native Docker socket found at /var/run/docker.sock"
        echo ""
        echo "To fix this permanently, add to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo "  # Fix Docker for NixOS (remove WSL Docker host)"
        echo "  unset DOCKER_HOST"
        echo ""
        echo "Or for this session only, run:"
        echo "  unset DOCKER_HOST"
        echo ""
        
        # Test Docker
        echo "Testing Docker connection..."
        unset DOCKER_HOST
        if docker ps &>/dev/null; then
            echo "✓ Docker is working correctly after unsetting DOCKER_HOST"
        else
            echo "✗ Docker still not working. Check systemctl status docker"
        fi
    else
        echo "Native Docker socket not found. Is Docker installed and running?"
        echo "Check: systemctl status docker"
    fi
else
    echo "DOCKER_HOST is not set to WSL path"
    
    # Test Docker connection
    if docker ps &>/dev/null; then
        echo "✓ Docker is working correctly"
    else
        echo "✗ Docker is not working. Check:"
        echo "  - systemctl status docker"
        echo "  - Is your user in the docker group? (groups | grep docker)"
        echo "  - Docker socket permissions: ls -la /var/run/docker.sock"
    fi
fi

echo ""
echo "Current Docker environment:"
echo "  DOCKER_HOST=${DOCKER_HOST:-<not set>}"
echo "  Docker socket: $(ls -la /var/run/docker.sock 2>/dev/null || echo 'not found')"
echo "  Docker version: $(docker --version 2>/dev/null || echo 'not available')"