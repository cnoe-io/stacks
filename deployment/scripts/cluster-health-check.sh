#!/usr/bin/env bash
# Cluster Health Check and Summary Script
# Provides timing, benchmarks, and visibility into cluster state
set -euo pipefail

STACKS_DIR="${STACKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Benchmark thresholds
NODES_READY_THRESHOLD=100      # % of nodes that must be Ready
APPS_HEALTHY_THRESHOLD=90      # % of apps that must be Healthy
EXTERNALSECRETS_THRESHOLD=80   # % of ExternalSecrets that must be synced
CORE_APPS=("argocd" "gitea" "nginx" "external-secrets")

# Timing file for tracking phases
TIMING_FILE="/tmp/cluster-recreate-timing.json"

#=============================================================================
# Timing Functions
#=============================================================================

start_timing() {
  local phase="$1"
  local now=$(date +%s)

  if [ ! -f "$TIMING_FILE" ]; then
    echo '{"phases":{}, "start_time": '"$now"'}' > "$TIMING_FILE"
  fi

  # Update phase start time
  local tmp=$(mktemp)
  jq --arg phase "$phase" --argjson now "$now" \
    '.phases[$phase] = {"start": $now, "end": null}' "$TIMING_FILE" > "$tmp"
  mv "$tmp" "$TIMING_FILE"
}

end_timing() {
  local phase="$1"
  local now=$(date +%s)

  if [ -f "$TIMING_FILE" ]; then
    local tmp=$(mktemp)
    jq --arg phase "$phase" --argjson now "$now" \
      '.phases[$phase].end = $now' "$TIMING_FILE" > "$tmp"
    mv "$tmp" "$TIMING_FILE"
  fi
}

reset_timing() {
  rm -f "$TIMING_FILE"
  local now=$(date +%s)
  echo '{"phases":{}, "start_time": '"$now"'}' > "$TIMING_FILE"
}

#=============================================================================
# Health Check Functions
#=============================================================================

check_nodes() {
  local total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  local ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")

  if [ "$total" -eq 0 ]; then
    echo "0|0|0"
    return
  fi

  local pct=$((ready * 100 / total))
  echo "$ready|$total|$pct"
}

check_apps() {
  local total=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
  local healthy=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$3=="Healthy"' | wc -l)
  local synced=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$2=="Synced"' | wc -l)
  local degraded=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$3=="Degraded"' | wc -l)
  local progressing=$(kubectl get applications -n argocd --no-headers 2>/dev/null | awk '$3=="Progressing"' | wc -l)

  if [ "$total" -eq 0 ]; then
    echo "0|0|0|0|0|0|0"
    return
  fi

  local health_pct=$((healthy * 100 / total))
  local sync_pct=$((synced * 100 / total))
  echo "$healthy|$total|$health_pct|$synced|$sync_pct|$degraded|$progressing"
}

check_core_apps() {
  local ready=0
  local total=${#CORE_APPS[@]}

  for app in "${CORE_APPS[@]}"; do
    local status=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep "^${app} " | awk '{print $3}')
    if [ "$status" = "Healthy" ]; then
      ready=$((ready + 1))
    fi
  done

  echo "$ready|$total"
}

check_external_secrets() {
  local total=$(kubectl get externalsecrets -A --no-headers 2>/dev/null | wc -l)
  local synced=$(kubectl get externalsecrets -A --no-headers 2>/dev/null | grep -c "SecretSynced" || echo "0")
  local errors=$(kubectl get externalsecrets -A --no-headers 2>/dev/null | grep -c "SecretSyncedError" || echo "0")

  if [ "$total" -eq 0 ]; then
    echo "0|0|0|0"
    return
  fi

  local pct=$((synced * 100 / total))
  echo "$synced|$total|$pct|$errors"
}

check_webhook_job() {
  # Check if job exists and is complete
  local job_exists=$(kubectl get job argocd-webhook-setup -n argocd --no-headers 2>/dev/null | wc -l)

  if [ "$job_exists" -gt 0 ]; then
    local succeeded=$(kubectl get job argocd-webhook-setup -n argocd -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    if [ "$succeeded" = "1" ]; then
      echo "Complete|"
      return
    fi
    echo "Running|"
    return
  fi

  # Job doesn't exist - check if webhooks are configured (job ran and was deleted)
  # This happens with BeforeHookCreation delete policy
  local webhook_count=$(kubectl get secret -n gitea gitea-credential -o jsonpath='{.data.token}' 2>/dev/null | base64 -d | \
    xargs -I {} curl -sk -H "Authorization: token {}" \
    "https://gitea.cnoe.localtest.me/api/v1/repos/giteaadmin/gitops-thinkpad-backstage-manifests/hooks" 2>/dev/null | \
    jq 'length' 2>/dev/null || echo "0")

  if [ "$webhook_count" -gt 0 ]; then
    echo "Complete|configured"
  else
    echo "Pending|"
  fi
}

get_lagging_apps() {
  kubectl get applications -n argocd --no-headers 2>/dev/null | \
    awk '$3=="Degraded" || $3=="Progressing" || $3=="Missing" {print $1 ": " $3}' | head -10
}

get_failed_secrets() {
  kubectl get externalsecrets -A --no-headers 2>/dev/null | \
    grep "SecretSyncedError" | awk '{print $1 "/" $2}' | head -10
}

get_pending_pods() {
  kubectl get pods -A --no-headers 2>/dev/null | \
    grep -vE "Running|Completed|Succeeded" | \
    awk '{print $1 "/" $2 ": " $4}' | head -10
}

#=============================================================================
# Summary Output Functions
#=============================================================================

print_header() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║            CLUSTER RECREATION SUMMARY                            ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_timing_summary() {
  if [ ! -f "$TIMING_FILE" ]; then
    return
  fi

  echo -e "${BOLD}⏱️  TIMING BREAKDOWN${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local start_time=$(jq -r '.start_time' "$TIMING_FILE")
  local now=$(date +%s)
  local total_duration=$((now - start_time))

  # Print each phase
  jq -r '.phases | to_entries[] | "\(.key)|\(.value.start)|\(.value.end)"' "$TIMING_FILE" 2>/dev/null | \
  while IFS='|' read -r phase start end; do
    if [ "$end" != "null" ] && [ -n "$end" ]; then
      local duration=$((end - start))
      printf "  %-25s %3ds\n" "$phase:" "$duration"
    elif [ -n "$start" ]; then
      local duration=$((now - start))
      printf "  %-25s %3ds ${YELLOW}(in progress)${NC}\n" "$phase:" "$duration"
    fi
  done

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  printf "  ${BOLD}%-25s %3ds${NC}\n" "TOTAL:" "$total_duration"
  echo ""
}

print_benchmark_status() {
  echo -e "${BOLD}📊 BENCHMARK STATUS${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Nodes
  IFS='|' read -r ready total pct <<< "$(check_nodes)"
  if [ "$pct" -ge "$NODES_READY_THRESHOLD" ]; then
    echo -e "  ${GREEN}✓${NC} Nodes Ready:          $ready/$total (${pct}%)"
  else
    echo -e "  ${RED}✗${NC} Nodes Ready:          $ready/$total (${pct}%) ${YELLOW}[need ${NODES_READY_THRESHOLD}%]${NC}"
  fi

  # Core Apps
  IFS='|' read -r core_ready core_total <<< "$(check_core_apps)"
  if [ "$core_ready" -eq "$core_total" ]; then
    echo -e "  ${GREEN}✓${NC} Core Infrastructure:  $core_ready/$core_total"
  else
    echo -e "  ${RED}✗${NC} Core Infrastructure:  $core_ready/$core_total ${YELLOW}[need all]${NC}"
  fi

  # Apps Health
  IFS='|' read -r healthy total health_pct synced sync_pct degraded progressing <<< "$(check_apps)"
  if [ "$health_pct" -ge "$APPS_HEALTHY_THRESHOLD" ]; then
    echo -e "  ${GREEN}✓${NC} Apps Healthy:         $healthy/$total (${health_pct}%)"
  else
    echo -e "  ${RED}✗${NC} Apps Healthy:         $healthy/$total (${health_pct}%) ${YELLOW}[need ${APPS_HEALTHY_THRESHOLD}%]${NC}"
  fi
  echo -e "    Apps Synced:         $synced/$total (${sync_pct}%)"

  # ExternalSecrets
  IFS='|' read -r es_synced es_total es_pct es_errors <<< "$(check_external_secrets)"
  if [ "$es_pct" -ge "$EXTERNALSECRETS_THRESHOLD" ]; then
    echo -e "  ${GREEN}✓${NC} ExternalSecrets:      $es_synced/$es_total (${es_pct}%)"
  else
    echo -e "  ${RED}✗${NC} ExternalSecrets:      $es_synced/$es_total (${es_pct}%) ${YELLOW}[need ${EXTERNALSECRETS_THRESHOLD}%]${NC}"
  fi

  # Webhook Job
  IFS='|' read -r wh_status wh_time <<< "$(check_webhook_job)"
  if [ "$wh_status" = "Complete" ]; then
    echo -e "  ${GREEN}✓${NC} Webhook Setup:        Complete"
  else
    echo -e "  ${YELLOW}○${NC} Webhook Setup:        Pending"
  fi

  echo ""
}

print_lagging_items() {
  echo -e "${BOLD}⚠️  LAGGING ITEMS${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Degraded/Progressing Apps
  local lagging_apps=$(get_lagging_apps)
  if [ -n "$lagging_apps" ]; then
    echo -e "  ${YELLOW}Apps (Degraded/Progressing):${NC}"
    echo "$lagging_apps" | while read -r line; do
      echo "    - $line"
    done
  fi

  # Failed ExternalSecrets
  local failed_secrets=$(get_failed_secrets)
  if [ -n "$failed_secrets" ]; then
    echo -e "  ${YELLOW}ExternalSecrets (Errors):${NC}"
    echo "$failed_secrets" | while read -r line; do
      echo "    - $line"
    done
  fi

  # Pending Pods
  local pending_pods=$(get_pending_pods)
  if [ -n "$pending_pods" ]; then
    echo -e "  ${YELLOW}Pods (Not Running):${NC}"
    echo "$pending_pods" | while read -r line; do
      echo "    - $line"
    done
  fi

  if [ -z "$lagging_apps" ] && [ -z "$failed_secrets" ] && [ -z "$pending_pods" ]; then
    echo -e "  ${GREEN}None - All resources healthy!${NC}"
  fi

  echo ""
}

is_cluster_ready() {
  # Check all benchmark criteria
  IFS='|' read -r ready total pct <<< "$(check_nodes)"
  [ "$pct" -lt "$NODES_READY_THRESHOLD" ] && return 1

  IFS='|' read -r core_ready core_total <<< "$(check_core_apps)"
  [ "$core_ready" -lt "$core_total" ] && return 1

  IFS='|' read -r healthy total health_pct _ _ _ _ <<< "$(check_apps)"
  [ "$health_pct" -lt "$APPS_HEALTHY_THRESHOLD" ] && return 1

  IFS='|' read -r wh_status _ <<< "$(check_webhook_job)"
  [ "$wh_status" != "Complete" ] && return 1

  return 0
}

print_cluster_status() {
  if is_cluster_ready; then
    echo -e "${GREEN}${BOLD}✅ CLUSTER IS READY${NC}"
  else
    echo -e "${YELLOW}${BOLD}⏳ CLUSTER STILL INITIALIZING${NC}"
  fi
  echo ""
}

print_summary() {
  print_header
  print_timing_summary
  print_benchmark_status
  print_lagging_items
  print_cluster_status
}

#=============================================================================
# Wait for Cluster Ready
#=============================================================================

wait_for_ready() {
  local timeout="${1:-600}"  # Default 10 minutes
  local interval=10
  local elapsed=0

  echo -e "${CYAN}Waiting for cluster to be ready (timeout: ${timeout}s)...${NC}"

  while [ $elapsed -lt $timeout ]; do
    if is_cluster_ready; then
      return 0
    fi

    # Show progress
    IFS='|' read -r healthy total health_pct _ _ _ _ <<< "$(check_apps)"
    printf "\r  Apps: %d/%d (%d%%) - Elapsed: %ds" "$healthy" "$total" "$health_pct" "$elapsed"

    sleep $interval
    elapsed=$((elapsed + interval))
  done

  echo ""
  return 1
}

#=============================================================================
# Main
#=============================================================================

case "${1:-summary}" in
  summary|status)
    print_summary
    ;;
  wait)
    wait_for_ready "${2:-600}"
    print_summary
    ;;
  ready)
    is_cluster_ready
    exit $?
    ;;
  reset)
    reset_timing
    echo "Timing reset"
    ;;
  start)
    start_timing "${2:-unknown}"
    ;;
  end)
    end_timing "${2:-unknown}"
    ;;
  *)
    echo "Usage: $0 {summary|wait [timeout]|ready|reset|start <phase>|end <phase>}"
    exit 1
    ;;
esac
