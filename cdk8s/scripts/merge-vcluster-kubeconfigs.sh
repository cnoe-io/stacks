#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET_SCRIPT="${PROJECT_ROOT}/ref-implementation/setup-vcluster-kubeconfigs.sh"

if [ ! -x "$TARGET_SCRIPT" ]; then
  echo "Error: ${TARGET_SCRIPT} is missing or not executable" >&2
  exit 1
fi

exec "$TARGET_SCRIPT" "$@"
