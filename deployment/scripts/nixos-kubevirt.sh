#!/usr/bin/env bash
#
# nixos-kubevirt.sh - NixOS KubeVirt image build and management functions
#
# This module provides functions for building and managing NixOS KubeVirt images.
# Source this file from cluster-menu.sh or use standalone.
#
# Functions:
#   build-nixos-image    - Build NixOS KubeVirt image and load into Kind
#   nixos-vm-status      - Show status of NixOS VM and related resources
#   nixos-vm-ssh         - SSH into the running NixOS VM
#   nixos-vm-rebuild     - Trigger nixos-rebuild inside the VM
#
# Aliases (when sourced):
#   clnix         - build-nixos-image
#   clnix-force   - build-nixos-image --force
#   clnix-github  - build-nixos-image --github
#   clnix-status  - nixos-vm-status
#   clnix-ssh     - nixos-vm-ssh
#

# ============================================================================
# Configuration
# ============================================================================

# Determine script directory if sourced
NIXOS_KUBEVIRT_SCRIPT_DIR="${NIXOS_KUBEVIRT_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
NIXOS_KUBEVIRT_STACKS_DIR="${STACKS_DIR:-$(cd "$NIXOS_KUBEVIRT_SCRIPT_DIR/../.." && pwd)}"

# Default configuration
NIXOS_VM_NAME="${NIXOS_VM_NAME:-nixos-sway-vm}"
NIXOS_VM_NAMESPACE="${NIXOS_VM_NAMESPACE:-default}"

# ============================================================================
# Helper Functions
# ============================================================================

_nixos_log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
_nixos_log_success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
_nixos_log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
_nixos_log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

# Detect cluster name (reuse from cluster-menu.sh if available)
_nixos_detect_cluster() {
  if type detect_hostname &>/dev/null 2>&1; then
    detect_hostname
  else
    hostname
  fi
}

# ============================================================================
# Main Functions
# ============================================================================

build-nixos-image() {
  # Build NixOS KubeVirt image and load into Kind
  # Wraps deployment/scripts/build-nixos-kubevirt-image.sh with cluster context
  #
  # Usage:
  #   build-nixos-image [OPTIONS]
  #
  # Options:
  #   --force    Force rebuild even if image exists
  #   --local    Use local nixos-config worktree (default)
  #   --github   Use github:vpittamp/nixos-config
  #   --help     Show help

  local BUILD_SCRIPT="$NIXOS_KUBEVIRT_STACKS_DIR/deployment/scripts/build-nixos-kubevirt-image.sh"

  if [ ! -f "$BUILD_SCRIPT" ]; then
    _nixos_log_error "Build script not found: $BUILD_SCRIPT"
    return 1
  fi

  # Auto-detect cluster name
  local CLUSTER_NAME
  CLUSTER_NAME="$(_nixos_detect_cluster)" || {
    _nixos_log_error "Failed to detect cluster name"
    return 1
  }

  _nixos_log_info "Building NixOS KubeVirt image for cluster: $CLUSTER_NAME"

  # Run build script with detected cluster
  KIND_CLUSTER="$CLUSTER_NAME" "$BUILD_SCRIPT" "$@"
  local result=$?

  if [ $result -eq 0 ]; then
    echo ""
    _nixos_log_success "Image ready!"
    echo ""
    echo "Next steps:"
    echo "  1. Run: cluster-update (or clu)"
    echo "  2. Check VM status: nixos-vm-status (or clnix-status)"
    echo "  3. SSH into VM: nixos-vm-ssh (or clnix-ssh)"
  fi

  return $result
}

nixos-vm-status() {
  # Show status of NixOS VM and related resources
  #
  # Usage:
  #   nixos-vm-status [VM_NAME] [NAMESPACE]

  local vm_name="${1:-$NIXOS_VM_NAME}"
  local namespace="${2:-$NIXOS_VM_NAMESPACE}"

  echo ""
  echo "=========================================="
  echo "  NixOS KubeVirt VM Status"
  echo "=========================================="
  echo ""

  # Check image server
  _nixos_log_info "Image Server:"
  kubectl get pod -n "$namespace" -l app=nixos-image-server --no-headers 2>/dev/null || \
    echo "  (not found)"
  echo ""

  # Check DataVolume
  _nixos_log_info "DataVolume:"
  kubectl get datavolume -n "$namespace" --no-headers 2>/dev/null || \
    echo "  (not found)"
  echo ""

  # Check VM
  _nixos_log_info "VirtualMachine:"
  kubectl get vm "$vm_name" -n "$namespace" --no-headers 2>/dev/null || \
    echo "  (not found)"
  echo ""

  # Check VMI (running instance)
  _nixos_log_info "VirtualMachineInstance (running):"
  kubectl get vmi "$vm_name" -n "$namespace" --no-headers 2>/dev/null || \
    echo "  (not running)"
  echo ""

  # Check services
  _nixos_log_info "Services:"
  kubectl get svc -n "$namespace" -l "kubevirt.io/vm=$vm_name" --no-headers 2>/dev/null || \
    kubectl get svc -n "$namespace" | grep -i nixos || \
    echo "  (not found)"
  echo ""

  # Show connection info if VM is running
  if kubectl get vmi "$vm_name" -n "$namespace" &>/dev/null; then
    _nixos_log_success "VM is running!"
    echo ""
    echo "Connect via:"

    # Check for NodePort service
    local ssh_port
    ssh_port=$(kubectl get svc "${vm_name}-ssh-vnc" -n "$namespace" -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}' 2>/dev/null)
    if [ -n "$ssh_port" ]; then
      echo "  SSH: ssh -p $ssh_port vpittamp@localhost"
    fi

    local vnc_port
    vnc_port=$(kubectl get svc "${vm_name}-ssh-vnc" -n "$namespace" -o jsonpath='{.spec.ports[?(@.name=="vnc")].nodePort}' 2>/dev/null)
    if [ -n "$vnc_port" ]; then
      echo "  VNC: Connect to localhost:$vnc_port"
    fi

    echo "  Console: virtctl console $vm_name -n $namespace"
  fi
}

nixos-vm-ssh() {
  # SSH into the running NixOS VM
  #
  # Usage:
  #   nixos-vm-ssh [VM_NAME] [NAMESPACE] [SSH_USER]

  local vm_name="${1:-$NIXOS_VM_NAME}"
  local namespace="${2:-$NIXOS_VM_NAMESPACE}"
  local ssh_user="${3:-vpittamp}"

  # Check if VM is running
  if ! kubectl get vmi "$vm_name" -n "$namespace" &>/dev/null; then
    _nixos_log_error "VM '$vm_name' is not running in namespace '$namespace'"
    echo "Run 'nixos-vm-status' to check VM status"
    return 1
  fi

  # Get SSH NodePort
  local ssh_port
  ssh_port=$(kubectl get svc "${vm_name}-ssh-vnc" -n "$namespace" -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}' 2>/dev/null)

  if [ -z "$ssh_port" ]; then
    _nixos_log_error "SSH service not found for VM '$vm_name'"
    echo "Using virtctl for console access instead..."
    virtctl console "$vm_name" -n "$namespace"
    return $?
  fi

  _nixos_log_info "Connecting to $vm_name via SSH (port $ssh_port)..."
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$ssh_port" "${ssh_user}@localhost"
}

nixos-vm-rebuild() {
  # Trigger nixos-rebuild inside the VM via SSH
  #
  # Usage:
  #   nixos-vm-rebuild [FLAKE_REF] [VM_NAME] [NAMESPACE]
  #
  # Examples:
  #   nixos-vm-rebuild                                    # Use default hetzner config
  #   nixos-vm-rebuild "github:vpittamp/nixos-config#hetzner-sway"  # Specific flake target

  local flake_ref="${1:-github:vpittamp/nixos-config#hetzner}"
  local vm_name="${2:-$NIXOS_VM_NAME}"
  local namespace="${3:-$NIXOS_VM_NAMESPACE}"
  local ssh_user="${4:-vpittamp}"

  # Get SSH port
  local ssh_port
  ssh_port=$(kubectl get svc "${vm_name}-ssh-vnc" -n "$namespace" -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}' 2>/dev/null)

  if [ -z "$ssh_port" ]; then
    _nixos_log_error "SSH service not found for VM '$vm_name'"
    return 1
  fi

  _nixos_log_info "Triggering nixos-rebuild on $vm_name..."
  _nixos_log_info "Flake: $flake_ref"
  echo ""

  # Run nixos-rebuild via SSH
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$ssh_port" "${ssh_user}@localhost" \
    "sudo nixos-rebuild switch --flake '$flake_ref'"

  local result=$?

  if [ $result -eq 0 ]; then
    _nixos_log_success "nixos-rebuild completed successfully!"
    echo ""
    echo "To rollback: nixos-vm-rebuild 'github:vpittamp/nixos-config#hetzner' --rollback"
  else
    _nixos_log_error "nixos-rebuild failed with exit code $result"
    echo ""
    echo "To rollback: ssh -p $ssh_port $ssh_user@localhost 'sudo nixos-rebuild switch --rollback'"
  fi

  return $result
}

# ============================================================================
# Aliases (defined when sourced)
# ============================================================================

alias clnix="build-nixos-image"
alias clnix-force="build-nixos-image --force"
alias clnix-github="build-nixos-image --github"
alias clnix-status="nixos-vm-status"
alias clnix-ssh="nixos-vm-ssh"
alias clnix-rebuild="nixos-vm-rebuild"

# ============================================================================
# Export functions for subshells
# ============================================================================

export -f build-nixos-image nixos-vm-status nixos-vm-ssh nixos-vm-rebuild 2>/dev/null || true
