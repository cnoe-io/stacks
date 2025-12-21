#!/usr/bin/env bash
set -euo pipefail

POLICY_FILE="${1:-policy.hujson}"
APPS_FILE="${2:-cdk8s/config/applications.ts}"
ENVRC_FILE="${3:-.envrc}"

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "ERROR: policy file not found: $POLICY_FILE" >&2
  exit 2
fi

if [[ ! -f "$APPS_FILE" ]]; then
  echo "ERROR: applications config not found: $APPS_FILE" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 2
fi

# NOTE: This script expects policy.hujson to be valid JSON (no comments/trailing commas).
jq . "$POLICY_FILE" >/dev/null

hosts=()
if [[ -f "$ENVRC_FILE" ]]; then
  while IFS= read -r host; do
    [[ -n "$host" ]] && hosts+=("$host")
  done < <(
    awk '
      $0 ~ /^case "\\$CLUSTER_HOST" in/ { in_case=1; next }
      in_case && $0 ~ /^[[:space:]]*[a-zA-Z0-9_-]+\\)/ {
        line=$0
        gsub(/^[[:space:]]*/, "", line)
        sub(/\\).*/, "", line)
        if (line != "*") print line
      }
      in_case && $0 ~ /^esac/ { exit }
    ' "$ENVRC_FILE"
  )
fi

if [[ ${#hosts[@]} -eq 0 ]]; then
  hosts=(thinkpad ryzen hetzner)
fi

mapfile -t base_names < <(
  grep -oE "serviceName: getTailscaleServiceName\\('[^']+'\\)" "$APPS_FILE" \
    | sed -E "s/.*getTailscaleServiceName\\('([^']+)'\\).*/\\1/" \
    | sort -u
)

mapfile -t fixed_names < <(
  grep -oE "serviceName: '[^']+'" "$APPS_FILE" \
    | sed -E "s/serviceName: '([^']+)'/\\1/" \
    | sort -u
)

mapfile -t vm_names < <(
  grep -oE "tailscaleHostname: '[^']+'" "$APPS_FILE" \
    | sed -E "s/tailscaleHostname: '([^']+)'/\\1/" \
    | sort -u
)

declare -A required_services=()

for name in "${fixed_names[@]}"; do
  required_services["$name"]=1
done

for name in "${vm_names[@]}"; do
  required_services["$name"]=1
done

for base in "${base_names[@]}"; do
  required_services["$base"]=1
  for host in "${hosts[@]}"; do
    required_services["${base}-${host}"]=1
  done
done

# Defensive: if a fixed-name service ever appears in the host-aware list (e.g., from comments),
# do not require host-suffixed variants for it.
for fixed in "${fixed_names[@]}"; do
  for host in "${hosts[@]}"; do
    unset 'required_services["'"${fixed}-${host}"'"]'
  done
done

missing=()

require_jq_key() {
  local jq_expr="$1"
  if ! jq -e "$jq_expr" "$POLICY_FILE" >/dev/null 2>&1; then
    missing+=("$2")
  fi
}

require_jq_key '.tagOwners["tag:k8s-operator"]' 'tagOwners:tag:k8s-operator'
require_jq_key '.tagOwners["tag:k8s-services"]' 'tagOwners:tag:k8s-services'
require_jq_key '.tagOwners["tag:vm"]' 'tagOwners:tag:vm'

while IFS= read -r svc; do
  [[ -z "$svc" ]] && continue
  require_jq_key ".autoApprovers.services[\"svc:${svc}\"]" "autoApprovers.services:svc:${svc}"
done < <(printf '%s\n' "${!required_services[@]}" | sort)

if [[ ${#missing[@]} -ne 0 ]]; then
  echo "ERROR: $POLICY_FILE is missing required entries:" >&2
  printf '  - %s\n' "${missing[@]}" | sort >&2
  exit 1
fi

echo "OK: $POLICY_FILE covers $(printf '%s\n' "${!required_services[@]}" | wc -l | tr -d ' ') services + required tags."
