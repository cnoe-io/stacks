#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${IDPB_NAMESPACE:-idpbuilder-localdev}
ARGO_NAMESPACE=${ARGO_NAMESPACE:-argocd}

log() {
  printf '\033[0;32m%s\033[0m\n' "$1"
}
warn() {
  printf '\033[1;33m%s\033[0m\n' "$1"
}

if ! command -v kubectl >/dev/null 2>&1; then
  warn "kubectl not found; skipping core-dns package cleanup"
  exit 0
fi

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  warn "Namespace $NAMESPACE not available; nothing to clean"
  exit 0
fi

log "Removing legacy core-dns override package (if present)..."

kubectl delete custompackage core-dns-rewrite-core-dns-rewrite \
  -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || warn "Unable to delete CustomPackage"

kubectl delete gitrepository core-dns-rewrite-manifests \
  -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || warn "Unable to delete GitRepository"

if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  kubectl delete application core-dns-rewrite -n "$ARGO_NAMESPACE" --ignore-not-found \
    >/dev/null 2>&1 || warn "Unable to delete ArgoCD Application"
fi

log "CoreDNS override resources cleaned"
