#!/bin/bash
# validate-hub-recovery.sh - Validate hub cluster recovery
#
# This script verifies that a hub cluster has been successfully restored
# and all spokes have reconnected. Run after hub recovery procedure.
#
# Usage:
#   ./validate-hub-recovery.sh
#
# Environment Variables:
#   KUBECONFIG      - Path to hub cluster kubeconfig (default: ~/.kube/hub-config)
#
# Exit Codes:
#   0 - All validations passed
#   1 - One or more validations failed

set -euo pipefail

# Configuration
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/hub-config}"
SPOKE_NAMES=("hetzner" "thinkpad" "ryzen" "talos")

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# ============================================================================
# Helper Functions
# ============================================================================

log_check() { echo -e "${BLUE}[CHECK]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARNINGS++)); }

check_command() {
  local name="$1"
  local cmd="$2"

  log_check "$name"
  if eval "$cmd" &>/dev/null; then
    log_pass "$name"
    return 0
  else
    log_fail "$name"
    return 1
  fi
}

check_command_output() {
  local name="$1"
  local cmd="$2"
  local expected="$3"

  log_check "$name"
  local output
  output=$(eval "$cmd" 2>/dev/null || echo "")

  if [[ "$output" == *"$expected"* ]]; then
    log_pass "$name"
    return 0
  else
    log_fail "$name (expected '$expected', got '$output')"
    return 1
  fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_hub_cluster() {
  echo ""
  echo "============================================"
  echo "Hub Cluster Validation"
  echo "============================================"

  # Check kubeconfig
  check_command "Kubeconfig accessible" \
    "kubectl --kubeconfig=$KUBECONFIG cluster-info" || true

  # Check nodes
  check_command "Hub node Ready" \
    "kubectl --kubeconfig=$KUBECONFIG get nodes | grep -q 'Ready'" || true

  # Check system pods
  check_command "CoreDNS running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running | grep -q 'Running'" || true

  check_command "Cilium running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n kube-system -l app.kubernetes.io/name=cilium-agent --field-selector=status.phase=Running | grep -q 'Running'" || true
}

validate_argocd() {
  echo ""
  echo "============================================"
  echo "ArgoCD Validation"
  echo "============================================"

  # Check ArgoCD namespace
  check_command "ArgoCD namespace exists" \
    "kubectl --kubeconfig=$KUBECONFIG get namespace argocd" || true

  # Check ArgoCD server
  check_command "ArgoCD server running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n argocd -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running | grep -q 'Running'" || true

  # Check ArgoCD controller
  check_command "ArgoCD controller running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller --field-selector=status.phase=Running | grep -q 'Running'" || true

  # Check ArgoCD repo server
  check_command "ArgoCD repo-server running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server --field-selector=status.phase=Running | grep -q 'Running'" || true
}

validate_tailscale() {
  echo ""
  echo "============================================"
  echo "Tailscale Validation"
  echo "============================================"

  # Check Tailscale namespace
  check_command "Tailscale namespace exists" \
    "kubectl --kubeconfig=$KUBECONFIG get namespace tailscale" || true

  # Check Tailscale operator
  check_command "Tailscale operator running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n tailscale -l app.kubernetes.io/name=tailscale-operator --field-selector=status.phase=Running | grep -q 'Running'" || true

  # Check Tailscale serve pod
  check_command "ArgoCD Tailscale serve running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n tailscale -l app=argocd-tailscale-serve --field-selector=status.phase=Running | grep -q 'Running'" || true
}

validate_eso() {
  echo ""
  echo "============================================"
  echo "External Secrets Operator Validation"
  echo "============================================"

  # Check ESO namespace
  check_command "External Secrets namespace exists" \
    "kubectl --kubeconfig=$KUBECONFIG get namespace external-secrets" || true

  # Check ESO operator
  check_command "ESO operator running" \
    "kubectl --kubeconfig=$KUBECONFIG get pods -n external-secrets -l app.kubernetes.io/name=external-secrets --field-selector=status.phase=Running | grep -q 'Running'" || true

  # Check ClusterSecretStore
  check_command "ClusterSecretStore ready" \
    "kubectl --kubeconfig=$KUBECONFIG get clustersecretstore azure-keyvault-store -o jsonpath='{.status.conditions[0].status}' | grep -q 'True'" || true
}

validate_spoke_connections() {
  echo ""
  echo "============================================"
  echo "Spoke Cluster Connections"
  echo "============================================"

  for spoke in "${SPOKE_NAMES[@]}"; do
    # Check cluster secret exists
    check_command "Spoke secret for $spoke exists" \
      "kubectl --kubeconfig=$KUBECONFIG get secret -n argocd cluster-$spoke" || true
  done

  # Check ArgoCD cluster list (if argocd CLI available)
  if command -v argocd &>/dev/null; then
    log_check "ArgoCD cluster list"
    local cluster_list
    cluster_list=$(argocd cluster list --insecure 2>/dev/null || echo "")

    local connected_count=0
    for spoke in "${SPOKE_NAMES[@]}"; do
      if echo "$cluster_list" | grep -q "$spoke.*Connected"; then
        ((connected_count++))
      fi
    done

    if [[ $connected_count -eq ${#SPOKE_NAMES[@]} ]]; then
      log_pass "All ${#SPOKE_NAMES[@]} spokes connected in ArgoCD"
    else
      log_warn "Only $connected_count/${#SPOKE_NAMES[@]} spokes connected"
    fi
  else
    log_warn "argocd CLI not available - skipping cluster list check"
  fi
}

validate_kargo() {
  echo ""
  echo "============================================"
  echo "Kargo Validation"
  echo "============================================"

  # Check Kargo namespace
  check_command "Kargo pipelines namespace exists" \
    "kubectl --kubeconfig=$KUBECONFIG get namespace kargo-pipelines" || true

  # Check Kargo project (if CRD exists)
  if kubectl --kubeconfig=$KUBECONFIG get crd projects.kargo.akuity.io &>/dev/null; then
    check_command "Kargo project exists" \
      "kubectl --kubeconfig=$KUBECONFIG get projects -n kargo-pipelines" || true

    check_command "Kargo warehouses exist" \
      "kubectl --kubeconfig=$KUBECONFIG get warehouses -n kargo-pipelines" || true
  else
    log_warn "Kargo CRDs not installed - skipping Kargo validation"
  fi
}

validate_applications() {
  echo ""
  echo "============================================"
  echo "Application Sync Status"
  echo "============================================"

  if command -v argocd &>/dev/null; then
    log_check "ArgoCD application sync status"
    local app_list
    app_list=$(argocd app list --insecure -o name 2>/dev/null || echo "")

    if [[ -z "$app_list" ]]; then
      log_warn "No applications found"
    else
      local total=0
      local synced=0
      local healthy=0

      while read -r app; do
        ((total++))
        local status
        status=$(argocd app get "$app" --insecure -o json 2>/dev/null | jq -r '.status.sync.status // "Unknown"')
        local health
        health=$(argocd app get "$app" --insecure -o json 2>/dev/null | jq -r '.status.health.status // "Unknown"')

        if [[ "$status" == "Synced" ]]; then
          ((synced++))
        fi
        if [[ "$health" == "Healthy" ]]; then
          ((healthy++))
        fi
      done <<< "$app_list"

      if [[ $synced -eq $total ]] && [[ $healthy -eq $total ]]; then
        log_pass "All $total applications Synced and Healthy"
      else
        log_warn "$synced/$total synced, $healthy/$total healthy"
      fi
    fi
  else
    log_warn "argocd CLI not available - skipping application sync check"
  fi
}

print_summary() {
  echo ""
  echo "============================================"
  echo "Validation Summary"
  echo "============================================"
  echo -e "Passed:   ${GREEN}$PASSED${NC}"
  echo -e "Failed:   ${RED}$FAILED${NC}"
  echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
  echo ""

  if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}Hub recovery validation PASSED${NC}"
    return 0
  else
    echo -e "${RED}Hub recovery validation FAILED${NC}"
    echo "Review failed checks and troubleshoot before proceeding."
    return 1
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════════╗"
  echo "║       Hub Cluster Recovery Validation                               ║"
  echo "╚════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Using kubeconfig: $KUBECONFIG"
  echo ""

  # Export kubeconfig for kubectl commands
  export KUBECONFIG

  validate_hub_cluster
  validate_argocd
  validate_tailscale
  validate_eso
  validate_spoke_connections
  validate_kargo
  validate_applications
  print_summary
}

main "$@"
