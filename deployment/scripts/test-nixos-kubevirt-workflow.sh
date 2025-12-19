#!/usr/bin/env bash
#
# test-nixos-kubevirt-workflow.sh - Validate NixOS KubeVirt CI/CD workflow
#
# This script tests the end-to-end workflow:
# 1. Image build validation (nix build + docker image)
# 2. VM boot validation
# 3. SSH connectivity test
# 4. nixos-rebuild with Attic cache
# 5. Generation count validation
#
# Usage:
#   ./test-nixos-kubevirt-workflow.sh [OPTIONS]
#
# Options:
#   --skip-build        Skip image build step
#   --skip-deploy       Skip deployment step
#   --skip-rebuild      Skip nixos-rebuild test
#   --flake-ref URL     Flake reference for nixos-rebuild test
#   --timeout SECONDS   VM boot timeout (default: 300)
#   -v, --verbose       Verbose output
#   -h, --help          Show this help
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_DIR="${STACKS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Test configuration
VM_NAME="${NIXOS_VM_NAME:-nixos-sway-vm}"
VM_NAMESPACE="${NIXOS_VM_NAMESPACE:-default}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"  # 5 minutes
SSH_TIMEOUT="${SSH_TIMEOUT:-60}"
FLAKE_REF="${FLAKE_REF:-github:vpittamp/nixos-config#hetzner}"

# Options
SKIP_BUILD=false
SKIP_DEPLOY=false
SKIP_REBUILD=false
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $*" >&2; }

log_test() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}  TEST: $*${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""
}

verbose() {
  if [ "$VERBOSE" = true ]; then
    echo -e "${YELLOW}[DEBUG]${NC} $*"
  fi
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-build)
        SKIP_BUILD=true
        shift
        ;;
      --skip-deploy)
        SKIP_DEPLOY=true
        shift
        ;;
      --skip-rebuild)
        SKIP_REBUILD=true
        shift
        ;;
      --flake-ref)
        FLAKE_REF="$2"
        shift 2
        ;;
      --timeout)
        BOOT_TIMEOUT="$2"
        shift 2
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Validate NixOS KubeVirt CI/CD workflow end-to-end.

Options:
  --skip-build        Skip image build step
  --skip-deploy       Skip deployment step
  --skip-rebuild      Skip nixos-rebuild test
  --flake-ref URL     Flake reference for nixos-rebuild test
                      (default: github:vpittamp/nixos-config#hetzner)
  --timeout SECONDS   VM boot timeout (default: 300)
  -v, --verbose       Verbose output
  -h, --help          Show this help

Environment:
  NIXOS_VM_NAME       VM name (default: nixos-sway-vm)
  NIXOS_VM_NAMESPACE  VM namespace (default: default)
  BOOT_TIMEOUT        VM boot timeout (default: 300)
  SSH_TIMEOUT         SSH connection timeout (default: 60)
EOF
}

# ============================================================================
# Test Functions
# ============================================================================

test_prerequisites() {
  log_test "Prerequisites Check"

  local failed=0

  # Check required commands
  for cmd in kubectl kind docker nix; do
    if command -v "$cmd" &>/dev/null; then
      log_success "$cmd installed"
    else
      log_error "$cmd not found"
      failed=1
    fi
  done

  # Check Kind cluster
  local cluster_name
  cluster_name="$(hostname)"
  if kind get clusters 2>/dev/null | grep -q "^${cluster_name}$"; then
    log_success "Kind cluster '$cluster_name' exists"
  else
    log_error "Kind cluster '$cluster_name' not found"
    failed=1
  fi

  # Check KubeVirt
  if kubectl get deploy -n kubevirt virt-operator &>/dev/null; then
    log_success "KubeVirt installed"
  else
    log_error "KubeVirt not installed"
    failed=1
  fi

  # Check CDI
  if kubectl get deploy -n cdi cdi-operator &>/dev/null; then
    log_success "CDI installed"
  else
    log_error "CDI not installed"
    failed=1
  fi

  return $failed
}

test_image_build() {
  log_test "Image Build"

  if [ "$SKIP_BUILD" = true ]; then
    log_warn "Skipping image build (--skip-build)"
    return 0
  fi

  local build_script="$STACKS_DIR/deployment/scripts/build-nixos-kubevirt-image.sh"

  if [ ! -f "$build_script" ]; then
    log_error "Build script not found: $build_script"
    return 1
  fi

  log_info "Building NixOS KubeVirt image..."
  if "$build_script" --force; then
    log_success "Image built successfully"
  else
    log_error "Image build failed"
    return 1
  fi

  # Verify image exists in Kind
  local cluster_name
  cluster_name="$(hostname)"
  local kind_node="${cluster_name}-control-plane"

  if docker exec "$kind_node" crictl images 2>/dev/null | grep -q "nixos-kubevirt-minimal"; then
    log_success "Image loaded in Kind cluster"
  else
    log_error "Image not found in Kind cluster"
    return 1
  fi

  return 0
}

test_deployment() {
  log_test "VM Deployment"

  if [ "$SKIP_DEPLOY" = true ]; then
    log_warn "Skipping deployment (--skip-deploy)"
    return 0
  fi

  # Check if cluster-update is available
  if type cluster-update &>/dev/null 2>&1; then
    log_info "Running cluster-update..."
    cluster-update || true
  else
    log_warn "cluster-update not available, using kubectl apply"
    cd "$STACKS_DIR/cdk8s" && npm run synth && cd ..
    kubectl apply -f cdk8s/dist/nixos-image-server/manifests/
    kubectl apply -f cdk8s/dist/nixos-sway-datavolume/manifests/
    kubectl apply -f cdk8s/dist/nixos-sway-vm/manifests/
  fi

  # Wait for image server
  log_info "Waiting for image server pod..."
  kubectl wait --for=condition=ready pod -l app=nixos-image-server -n "$VM_NAMESPACE" --timeout=120s || {
    log_error "Image server pod not ready"
    kubectl get pod -l app=nixos-image-server -n "$VM_NAMESPACE"
    return 1
  }
  log_success "Image server ready"

  # Wait for DataVolume
  log_info "Waiting for DataVolume import (this may take a few minutes)..."
  local dv_name="nixos-sway-datavolume"
  local dv_timeout=$((BOOT_TIMEOUT / 2))

  for i in $(seq 1 "$dv_timeout"); do
    local phase
    phase=$(kubectl get datavolume "$dv_name" -n "$VM_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    if [ "$phase" = "Succeeded" ]; then
      log_success "DataVolume import succeeded"
      break
    elif [ "$phase" = "Failed" ]; then
      log_error "DataVolume import failed"
      kubectl describe datavolume "$dv_name" -n "$VM_NAMESPACE"
      return 1
    fi

    verbose "DataVolume phase: $phase ($i/$dv_timeout)"
    sleep 1
  done

  return 0
}

test_vm_boot() {
  log_test "VM Boot"

  log_info "Waiting for VM to boot (timeout: ${BOOT_TIMEOUT}s)..."

  local start_time
  start_time=$(date +%s)

  while true; do
    local elapsed
    elapsed=$(($(date +%s) - start_time))

    if [ "$elapsed" -ge "$BOOT_TIMEOUT" ]; then
      log_error "VM boot timeout after ${BOOT_TIMEOUT}s"
      kubectl get vm,vmi -n "$VM_NAMESPACE"
      kubectl describe vmi "$VM_NAME" -n "$VM_NAMESPACE" || true
      return 1
    fi

    # Check VMI status
    local vmi_phase
    vmi_phase=$(kubectl get vmi "$VM_NAME" -n "$VM_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotCreated")

    if [ "$vmi_phase" = "Running" ]; then
      log_success "VM is running (took ${elapsed}s)"
      break
    fi

    verbose "VMI phase: $vmi_phase (${elapsed}s elapsed)"
    sleep 5
  done

  # Get VM info
  log_info "VM details:"
  kubectl get vmi "$VM_NAME" -n "$VM_NAMESPACE" -o wide

  return 0
}

test_ssh_connectivity() {
  log_test "SSH Connectivity"

  # Get SSH NodePort
  local ssh_port
  ssh_port=$(kubectl get svc "${VM_NAME}-ssh-vnc" -n "$VM_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}' 2>/dev/null)

  if [ -z "$ssh_port" ]; then
    log_error "SSH service not found"
    return 1
  fi

  log_info "SSH port: $ssh_port"
  log_info "Waiting for SSH to become available (timeout: ${SSH_TIMEOUT}s)..."

  local start_time
  start_time=$(date +%s)

  while true; do
    local elapsed
    elapsed=$(($(date +%s) - start_time))

    if [ "$elapsed" -ge "$SSH_TIMEOUT" ]; then
      log_error "SSH timeout after ${SSH_TIMEOUT}s"
      return 1
    fi

    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 -o BatchMode=yes \
           -p "$ssh_port" vpittamp@localhost "echo SSH_OK" 2>/dev/null | grep -q "SSH_OK"; then
      log_success "SSH connection successful (took ${elapsed}s)"
      break
    fi

    verbose "SSH not ready (${elapsed}s elapsed)"
    sleep 5
  done

  # Get system info
  log_info "NixOS system info:"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -p "$ssh_port" vpittamp@localhost "nixos-version && uname -a"

  return 0
}

test_nixos_rebuild() {
  log_test "nixos-rebuild"

  if [ "$SKIP_REBUILD" = true ]; then
    log_warn "Skipping nixos-rebuild (--skip-rebuild)"
    return 0
  fi

  local ssh_port
  ssh_port=$(kubectl get svc "${VM_NAME}-ssh-vnc" -n "$VM_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}' 2>/dev/null)

  if [ -z "$ssh_port" ]; then
    log_error "SSH service not found"
    return 1
  fi

  # Get current generation before rebuild
  local gen_before
  gen_before=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -p "$ssh_port" vpittamp@localhost \
               "readlink /nix/var/nix/profiles/system | sed 's/.*-\\([0-9]*\\)-link/\\1/'" 2>/dev/null || echo "1")

  log_info "Current generation: $gen_before"
  log_info "Running nixos-rebuild with flake: $FLAKE_REF"
  log_info "This may take several minutes (depending on Attic cache hit rate)..."

  local start_time
  start_time=$(date +%s)

  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o ServerAliveInterval=30 -o ServerAliveCountMax=10 \
         -p "$ssh_port" vpittamp@localhost \
         "sudo nixos-rebuild switch --flake '$FLAKE_REF'"; then

    local elapsed
    elapsed=$(($(date +%s) - start_time))
    log_success "nixos-rebuild completed in ${elapsed}s"

    # Get new generation
    local gen_after
    gen_after=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -p "$ssh_port" vpittamp@localhost \
                "readlink /nix/var/nix/profiles/system | sed 's/.*-\\([0-9]*\\)-link/\\1/'" 2>/dev/null || echo "$gen_before")

    log_info "New generation: $gen_after"

    if [ "$gen_after" -gt "$gen_before" ]; then
      log_success "Generation incremented: $gen_before -> $gen_after"
    else
      log_warn "Generation did not increment (possibly already up-to-date)"
    fi

    return 0
  else
    log_error "nixos-rebuild failed"
    return 1
  fi
}

test_generations() {
  log_test "NixOS Generations"

  local ssh_port
  ssh_port=$(kubectl get svc "${VM_NAME}-ssh-vnc" -n "$VM_NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}' 2>/dev/null)

  if [ -z "$ssh_port" ]; then
    log_error "SSH service not found"
    return 1
  fi

  log_info "Listing NixOS generations:"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -p "$ssh_port" vpittamp@localhost \
      "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system"

  local gen_count
  gen_count=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -p "$ssh_port" vpittamp@localhost \
              "ls -1 /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l" 2>/dev/null || echo "0")

  if [ "$gen_count" -ge 1 ]; then
    log_success "Found $gen_count generation(s)"
    return 0
  else
    log_warn "No generations found (this is unusual)"
    return 0
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  parse_args "$@"

  echo ""
  echo "=========================================="
  echo "  NixOS KubeVirt Workflow Test"
  echo "=========================================="
  echo ""
  echo "Configuration:"
  echo "  VM Name:      $VM_NAME"
  echo "  Namespace:    $VM_NAMESPACE"
  echo "  Boot Timeout: ${BOOT_TIMEOUT}s"
  echo "  Flake Ref:    $FLAKE_REF"
  echo ""

  local failed=0
  local tests_run=0
  local tests_passed=0

  # Run tests
  for test_func in \
    test_prerequisites \
    test_image_build \
    test_deployment \
    test_vm_boot \
    test_ssh_connectivity \
    test_nixos_rebuild \
    test_generations; do

    tests_run=$((tests_run + 1))

    if $test_func; then
      tests_passed=$((tests_passed + 1))
    else
      failed=1
    fi
  done

  # Summary
  echo ""
  echo "=========================================="
  echo "  Test Summary"
  echo "=========================================="
  echo ""
  echo "  Tests Run:    $tests_run"
  echo "  Tests Passed: $tests_passed"
  echo "  Tests Failed: $((tests_run - tests_passed))"
  echo ""

  if [ "$failed" -eq 0 ]; then
    log_success "All tests passed!"
    return 0
  else
    log_error "Some tests failed"
    return 1
  fi
}

main "$@"
