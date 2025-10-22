#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OVERRIDE_ALL=false
ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --override-all)
      OVERRIDE_ALL=true
      shift
      ;;
    --envFile)
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--override-all] [--envFile <path>]"
      echo ""
      echo "Options:"
      echo "  --override-all       Force prompts for existing secrets in agent setup"
      echo "  --envFile <path>     Path to env file to source for values"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Build argument lists safely
llm_args=()
agent_args=()

if [[ -n "$ENV_FILE" ]]; then
  llm_args+=(--envFile "$ENV_FILE")
  agent_args+=(--envFile "$ENV_FILE")
fi

if [[ "$OVERRIDE_ALL" == "true" ]]; then
  agent_args+=(--override-all)
fi

echo "🧩 Running setup-llm-credentials.sh..."
bash "$script_dir/setup-llm-credentials.sh" "${llm_args[@]}"

echo ""
echo "🧩 Running setup-agent-secrets.sh..."
bash "$script_dir/setup-agent-secrets.sh" "${agent_args[@]}"

echo "⏳ Waiting 2 seconds before refreshing secrets..."
sleep 2

echo "🔄 Running refresh-secrets.sh..."
bash "$script_dir/refresh-secrets.sh"

echo "✅ All done."
