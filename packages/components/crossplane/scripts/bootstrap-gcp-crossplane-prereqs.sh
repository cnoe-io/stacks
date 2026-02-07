#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") \
    --project-id <gcp-project-id> \
    --crossplane-service-account <service-account-email>

Run this as a project owner/editor account (not the Crossplane service account key)
to grant minimum roles needed by Crossplane's GCP provider.
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
}

PROJECT_ID=""
CROSSPLANE_SA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --crossplane-service-account)
      CROSSPLANE_SA="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ID" || -z "$CROSSPLANE_SA" ]]; then
  usage
  exit 1
fi

require_cmd gcloud

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1)"
echo "active gcloud account: ${ACTIVE_ACCOUNT:-<none>}"

echo "enabling required APIs in project: $PROJECT_ID"
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  calendar-json.googleapis.com \
  --project "$PROJECT_ID"

echo "granting IAM roles to $CROSSPLANE_SA"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$CROSSPLANE_SA" \
  --role "roles/serviceusage.serviceUsageAdmin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$CROSSPLANE_SA" \
  --role "roles/viewer"

echo "done"
