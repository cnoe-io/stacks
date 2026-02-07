#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") \
    --vault-name <azure-key-vault-name> \
    --gcp-creds <path-to-gcp-service-account.json> \
    --google-oauth <path-to-google-oauth-client-secret.json> \
    [--aws-creds <path-to-aws-provider-creds>] \
    [--azuread-creds <path-to-azuread-credentials.json>] \
    [--skip-k8s-refresh]

This script writes credential material to Azure Key Vault using canonical
secret names expected by ExternalSecrets.

Note: AzureAD Crossplane provider now uses Azure Workload Identity by default,
so AZUREAD-CROSSPLANE-CREDS is optional (legacy fallback only).
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
}

VAULT_NAME=""
AZUREAD_CREDS=""
GCP_CREDS=""
GOOGLE_OAUTH=""
AWS_CREDS=""
SKIP_K8S_REFRESH="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault-name)
      VAULT_NAME="$2"
      shift 2
      ;;
    --azuread-creds)
      AZUREAD_CREDS="$2"
      shift 2
      ;;
    --gcp-creds)
      GCP_CREDS="$2"
      shift 2
      ;;
    --google-oauth)
      GOOGLE_OAUTH="$2"
      shift 2
      ;;
    --aws-creds)
      AWS_CREDS="$2"
      shift 2
      ;;
    --skip-k8s-refresh)
      SKIP_K8S_REFRESH="true"
      shift
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

if [[ -z "$VAULT_NAME" || -z "$GCP_CREDS" || -z "$GOOGLE_OAUTH" ]]; then
  usage
  exit 1
fi

require_cmd az
require_cmd jq

for f in "$GCP_CREDS" "$GOOGLE_OAUTH"; do
  if [[ ! -f "$f" ]]; then
    echo "file not found: $f" >&2
    exit 1
  fi
done

jq -e '.type == "service_account" and .project_id and .client_email and .private_key' "$GCP_CREDS" >/dev/null
jq -e '.web.client_id and .web.client_secret and .web.redirect_uris' "$GOOGLE_OAUTH" >/dev/null

if [[ -n "$AZUREAD_CREDS" ]]; then
  if [[ ! -f "$AZUREAD_CREDS" ]]; then
    echo "file not found: $AZUREAD_CREDS" >&2
    exit 1
  fi
  jq -e '.clientId and .clientSecret and .tenantId' "$AZUREAD_CREDS" >/dev/null
fi

if [[ -n "$AWS_CREDS" && ! -f "$AWS_CREDS" ]]; then
  echo "file not found: $AWS_CREDS" >&2
  exit 1
fi

if [[ -n "$AZUREAD_CREDS" ]]; then
  echo "writing AZUREAD-CROSSPLANE-CREDS (legacy)"
  az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name AZUREAD-CROSSPLANE-CREDS \
    --value "$(cat "$AZUREAD_CREDS")" \
    --only-show-errors \
    --output none
fi

echo "writing GCP-CROSSPLANE-CREDS"
az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name GCP-CROSSPLANE-CREDS \
  --value "$(cat "$GCP_CREDS")" \
  --only-show-errors \
  --output none

echo "writing WORKFLOW-BUILDER-GOOGLE-OAUTH-JSON"
az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name WORKFLOW-BUILDER-GOOGLE-OAUTH-JSON \
  --value "$(cat "$GOOGLE_OAUTH")" \
  --only-show-errors \
  --output none

if [[ -n "$AWS_CREDS" ]]; then
  echo "writing AWS-CROSSPLANE-CREDS"
  az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name AWS-CROSSPLANE-CREDS \
    --value "$(cat "$AWS_CREDS")" \
    --only-show-errors \
    --output none
fi

if [[ "$SKIP_K8S_REFRESH" == "false" ]] && command -v kubectl >/dev/null 2>&1; then
  TS="$(date +%s)"
  echo "refreshing ExternalSecret sync in crossplane-system"
  kubectl -n crossplane-system annotate externalsecret gcp-crossplane-creds force-sync="$TS" --overwrite >/dev/null || true
  kubectl -n crossplane-system annotate externalsecret aws-crossplane-creds force-sync="$TS" --overwrite >/dev/null || true
  if kubectl -n crossplane-system get externalsecret azuread-crossplane-creds >/dev/null 2>&1; then
    kubectl -n crossplane-system annotate externalsecret azuread-crossplane-creds force-sync="$TS" --overwrite >/dev/null || true
  fi
fi

echo "done"
