#!/usr/bin/env bash
set -euo pipefail

# check-service-host-approvals.sh
#
# Reports which Kubernetes Tailscale Serve pods are currently approved as Service hosts
# (i.e., have the "service-host" capability for their configured svc:* entries).
#
# Why this exists:
# - ACL autoApprovers.services does NOT create Services in the admin console.
# - If a Service (e.g., "grafana-ryzen") hasn't been created in the Tailscale admin console
#   (Admin → Services), then pods serving "svc:grafana-ryzen" will not be approved and
#   "grafana-ryzen.<tailnet>.ts.net" will not resolve.
#
# Usage:
#   ./check-service-host-approvals.sh [namespace]
#
# Examples:
#   ./check-service-host-approvals.sh tailscale

NAMESPACE="${1:-tailscale}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 2
fi

pods_json="$(kubectl -n "${NAMESPACE}" get pods -o json)"
mapfile -t pods < <(echo "${pods_json}" | jq -r '.items[] | select(.metadata.name | test("tailscale-serve")) | .metadata.name' | sort -u)

if [[ ${#pods[@]} -eq 0 ]]; then
  echo "No pods matching /tailscale-serve/ found in namespace: ${NAMESPACE}"
  exit 0
fi

echo "Namespace: ${NAMESPACE}"
echo ""
printf "%-60s %-10s %-28s %s\n" "POD" "APPROVED" "SERVICE" "URL"
printf "%-60s %-10s %-28s %s\n" "$(printf '%0.s-' {1..60})" "$(printf '%0.s-' {1..10})" "$(printf '%0.s-' {1..28})" "$(printf '%0.s-' {1..35})"

missing=()

kubectl_exec_ts() {
  local pod="$1"
  shift
  # Most of our serve pods use container name "tailscale-serve"; fall back to default.
  kubectl -n "${NAMESPACE}" exec "${pod}" -c tailscale-serve -- "$@" 2>/dev/null \
    || kubectl -n "${NAMESPACE}" exec "${pod}" -- "$@"
}

for pod in "${pods[@]}"; do
  status_json="$(kubectl_exec_ts "${pod}" tailscale --socket=/run/tailscale/tailscaled.sock status --json)"
  serve_json="$(kubectl_exec_ts "${pod}" tailscale --socket=/run/tailscale/tailscaled.sock serve status --json)"

  dns_suffix="$(echo "${status_json}" | jq -r '.MagicDNSSuffix')"
  # List of svc:* this pod is configured to serve (even if not approved yet)
  mapfile -t served < <(echo "${serve_json}" | jq -r '(.Services // {}) | keys[]' | sort -u)
  # List of svc:* for which this node is currently approved as a host
  approved_list="$(
    echo "${status_json}" \
      | jq -r '(.Self.CapMap["service-host"] // []) | map(keys[]) | .[]?' \
      | sort -u
  )"

  if [[ ${#served[@]} -eq 0 ]]; then
    printf "%-60s %-10s %-28s %s\n" "${pod}" "?" "<no svc:*>" "-"
    continue
  fi

  for svc in "${served[@]}"; do
    svc_name="${svc#svc:}"
    svc_url="https://${svc_name}.${dns_suffix}"
    if echo "${approved_list}" | grep -Fxq "${svc}"; then
      printf "%-60s %-10s %-28s %s\n" "${pod}" "yes" "${svc}" "${svc_url}"
    else
      printf "%-60s %-10s %-28s %s\n" "${pod}" "no" "${svc}" "${svc_url}"
      missing+=("${svc_name}")
    fi
  done
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo ""
  echo "OK: all discovered svc:* entries are approved as Service hosts."
  exit 0
fi

echo ""
echo "Missing approvals (likely missing Tailscale Services definitions):"
printf '  - %s\n' "${missing[@]}" | sort -u
echo ""
echo "Next:"
echo "  1) Create each Service in the Tailscale admin console → Services"
echo "  2) Wait ~30-60s for auto-approval via ACL autoApprovers.services"
