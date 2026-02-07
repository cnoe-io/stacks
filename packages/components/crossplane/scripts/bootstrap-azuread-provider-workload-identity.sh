#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--app-id <existing-app-id>] [--display-name <name>] \
    [--tenant-id <tenant-id>] [--issuer <issuer-url>] \
    [--namespace <k8s-namespace>] [--service-account <sa-name>] \
    [--credential-name <fic-name>]

Creates or reuses an Entra app registration for Crossplane AzureAD provider,
ensures service principal + Cloud Application Administrator role assignment,
and ensures federated credential mapping for the provider ServiceAccount.

Defaults:
  --display-name crossplane-provider-kind-localdev
  --namespace crossplane-system
  --service-account provider-azuread-wi
  --credential-name crossplane-system-provider-azuread-wi
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
}

APP_ID=""
DISPLAY_NAME="crossplane-provider-kind-localdev"
TENANT_ID=""
ISSUER=""
NAMESPACE="crossplane-system"
SERVICE_ACCOUNT="provider-azuread-wi"
CRED_NAME="crossplane-system-provider-azuread-wi"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id)
      APP_ID="$2"
      shift 2
      ;;
    --display-name)
      DISPLAY_NAME="$2"
      shift 2
      ;;
    --tenant-id)
      TENANT_ID="$2"
      shift 2
      ;;
    --issuer)
      ISSUER="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --service-account)
      SERVICE_ACCOUNT="$2"
      shift 2
      ;;
    --credential-name)
      CRED_NAME="$2"
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

require_cmd az
require_cmd jq
require_cmd kubectl

if [[ -z "$TENANT_ID" ]]; then
  TENANT_ID="$(az account show --query tenantId -o tsv)"
fi
if [[ -z "$ISSUER" ]]; then
  ISSUER="$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer')"
fi

SUBJECT="system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
AUD="api://AzureADTokenExchange"

if [[ -z "$APP_ID" ]]; then
  APP_JSON="$(az ad app create --display-name "$DISPLAY_NAME" --sign-in-audience AzureADMyOrg -o json)"
  APP_ID="$(echo "$APP_JSON" | jq -r '.appId')"
  APP_OBJ_ID="$(echo "$APP_JSON" | jq -r '.id')"
else
  APP_OBJ_ID="$(az rest --method GET --url "https://graph.microsoft.com/v1.0/applications?\$filter=appId%20eq%20'$APP_ID'&\$select=id" --query 'value[0].id' -o tsv)"
  if [[ -z "$APP_OBJ_ID" ]]; then
    echo "unable to resolve app object ID for appId=$APP_ID" >&2
    exit 1
  fi
fi

SP_OBJ_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv 2>/dev/null || az ad sp show --id "$APP_ID" --query id -o tsv)"

ROLE_ID="$(az rest --method GET --url 'https://graph.microsoft.com/v1.0/directoryRoles?$select=id,displayName' -o json | jq -r '.value[] | select(.displayName=="Cloud Application Administrator") | .id' | head -n1)"
if [[ -n "$ROLE_ID" ]]; then
  ROLE_BODY="$(jq -nc --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$SP_OBJ_ID" '{"@odata.id":$id}')"
  az rest --method POST --url "https://graph.microsoft.com/v1.0/directoryRoles/$ROLE_ID/members/\$ref" --headers 'Content-Type=application/json' --body "$ROLE_BODY" >/dev/null 2>&1 || true
fi

EXISTING="$(az rest --method GET --url "https://graph.microsoft.com/v1.0/applications/$APP_OBJ_ID/federatedIdentityCredentials" -o json)"
FIC_ID="$(echo "$EXISTING" | jq -r --arg n "$CRED_NAME" '.value[]? | select(.name==$n) | .id' | head -n1)"
FIC_BODY="$(jq -nc --arg name "$CRED_NAME" --arg issuer "$ISSUER" --arg subject "$SUBJECT" --arg aud "$AUD" '{name:$name,issuer:$issuer,subject:$subject,audiences:[$aud],description:"Crossplane provider-azuread workload identity"}')"

if [[ -n "$FIC_ID" ]]; then
  az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$APP_OBJ_ID/federatedIdentityCredentials/$FIC_ID" --headers 'Content-Type=application/json' --body "$FIC_BODY" -o none
else
  az rest --method POST --url "https://graph.microsoft.com/v1.0/applications/$APP_OBJ_ID/federatedIdentityCredentials" --headers 'Content-Type=application/json' --body "$FIC_BODY" -o none
fi

cat <<OUT
APP_ID=$APP_ID
APP_OBJECT_ID=$APP_OBJ_ID
SERVICE_PRINCIPAL_OBJECT_ID=$SP_OBJ_ID
TENANT_ID=$TENANT_ID
ISSUER=$ISSUER
SUBJECT=$SUBJECT
OUT
