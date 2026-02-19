#!/usr/bin/env bash
# Database migration helpers for stacks cluster workflows.
# - Prefers Atlas where available (workflow-builder).
# - Falls back to Prisma SQL bootstrap only where Atlas is not available (mpak-registry).

# Detect stacks root when run standalone.
if [ -z "${STACKS_DIR:-}" ]; then
  if STACKS_DIR=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$STACKS_DIR" ]; then
    export STACKS_DIR
  elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    export STACKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
fi

_dbm_log() {
  printf '%s\n' "$*"
}

_dbm_wait_for_pod() {
  local namespace="$1"
  local pod_name="$2"
  local timeout_seconds="${3:-300}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if kubectl get pod "$pod_name" -n "$namespace" >/dev/null 2>&1; then
      if kubectl wait --for=condition=Ready "pod/$pod_name" -n "$namespace" --timeout=10s >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

_dbm_wait_for_secret() {
  local namespace="$1"
  local secret_name="$2"
  local timeout_seconds="${3:-180}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

_dbm_wait_for_job_complete() {
  local namespace="$1"
  local job_name="$2"
  local timeout_seconds="${3:-600}"

  if kubectl wait --for=condition=complete "job/$job_name" -n "$namespace" --timeout="${timeout_seconds}s" >/dev/null 2>&1; then
    return 0
  fi

  _dbm_log "❌ Job ${namespace}/${job_name} failed or timed out"
  kubectl get job "$job_name" -n "$namespace" -o wide || true
  local job_pod
  job_pod="$(kubectl get pod -n "$namespace" -l "job-name=$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -n "$job_pod" ]; then
    _dbm_log "Logs from ${namespace}/${job_pod}:"
    kubectl logs "$job_pod" -n "$namespace" --all-containers --tail=200 || true
  fi
  return 1
}

_dbm_secret_value() {
  local namespace="$1"
  local secret_name="$2"
  local key="$3"

  kubectl get secret "$secret_name" -n "$namespace" -o "jsonpath={.data.${key}}" 2>/dev/null | base64 -d 2>/dev/null || true
}

_dbm_find_pod() {
  local namespace="$1"
  shift
  local selector pod_name

  for selector in "$@"; do
    pod_name="$(kubectl get pod -n "$namespace" -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [ -n "$pod_name" ]; then
      printf '%s\n' "$pod_name"
      return 0
    fi
  done

  return 1
}

run-workflow-builder-atlas-migrations() {
  local manifest="$STACKS_DIR/packages/components/active-development/manifests/workflow-builder/Job-db-migrate.yaml"
  if [ ! -f "$manifest" ]; then
    _dbm_log "❌ Missing manifest: $manifest"
    return 1
  fi

  _dbm_log "🧭 Reconciling workflow-builder schema via Atlas job..."

  if ! kubectl get namespace workflow-builder >/dev/null 2>&1; then
    _dbm_log "ℹ️  Namespace workflow-builder not found; skipping workflow-builder migrations"
    return 0
  fi

  if ! _dbm_wait_for_pod workflow-builder postgresql-0 600; then
    _dbm_log "❌ workflow-builder/postgresql-0 is not ready"
    return 1
  fi

  if ! _dbm_wait_for_secret workflow-builder workflow-builder-secrets 300; then
    _dbm_log "❌ workflow-builder-secrets not found"
    return 1
  fi

  kubectl delete job db-migrate -n workflow-builder --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl apply -f "$manifest" >/dev/null

  _dbm_wait_for_job_complete workflow-builder db-migrate 900
}

run-workflow-builder-db-seed() {
  local manifest="$STACKS_DIR/packages/components/active-development/manifests/workflow-builder/Job-db-seed.yaml"
  if [ ! -f "$manifest" ]; then
    _dbm_log "❌ Missing manifest: $manifest"
    return 1
  fi

  _dbm_log "🌱 Running workflow-builder DB seed job..."

  if ! kubectl get namespace workflow-builder >/dev/null 2>&1; then
    _dbm_log "ℹ️  Namespace workflow-builder not found; skipping workflow-builder seed"
    return 0
  fi

  if ! _dbm_wait_for_pod workflow-builder postgresql-0 600; then
    _dbm_log "❌ workflow-builder/postgresql-0 is not ready"
    return 1
  fi

  if ! _dbm_wait_for_secret workflow-builder workflow-builder-secrets 300; then
    _dbm_log "❌ workflow-builder-secrets not found"
    return 1
  fi

  kubectl delete job db-seed -n workflow-builder --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl apply -f "$manifest" >/dev/null

  _dbm_wait_for_job_complete workflow-builder db-seed 600
}

bootstrap-mpak-registry-db() {
  _dbm_log "🧭 Reconciling mpak-registry database bootstrap..."

  if ! kubectl get namespace nimbletools-system >/dev/null 2>&1; then
    _dbm_log "ℹ️  Namespace nimbletools-system not found; skipping mpak bootstrap"
    return 0
  fi

  if ! kubectl get namespace workflow-builder >/dev/null 2>&1; then
    _dbm_log "ℹ️  Namespace workflow-builder not found; skipping mpak bootstrap"
    return 0
  fi

  if ! kubectl get deployment mpak-registry -n nimbletools-system >/dev/null 2>&1; then
    _dbm_log "ℹ️  Deployment nimbletools-system/mpak-registry not found; skipping mpak bootstrap"
    return 0
  fi

  if ! _dbm_wait_for_pod workflow-builder postgresql-0 600; then
    _dbm_log "❌ workflow-builder/postgresql-0 is not ready"
    return 1
  fi

  local database_url
  database_url="$(_dbm_secret_value nimbletools-system mpak database-url)"
  if [ -z "$database_url" ]; then
    database_url="$(_dbm_secret_value nimbletools-system mpak DATABASE_URL)"
  fi
  if [ -z "$database_url" ]; then
    _dbm_log "ℹ️  Secret nimbletools-system/mpak missing database URL key; skipping mpak bootstrap"
    return 0
  fi

  local base_url query db_name admin_url
  base_url="${database_url%%\?*}"
  if [ "$base_url" = "$database_url" ]; then
    query=""
  else
    query="${database_url#"$base_url"}"
  fi
  db_name="${base_url##*/}"
  if [ -z "$db_name" ]; then
    _dbm_log "❌ Could not parse database name from mpak database URL"
    return 1
  fi
  admin_url="${base_url%/*}/postgres${query}"

  local db_exists
  db_exists="$(
    kubectl exec -n workflow-builder postgresql-0 -- \
      psql "$admin_url" -tAc "select 1 from pg_database where datname='${db_name}'" 2>/dev/null | tr -d '[:space:]'
  )"
  if [ "$db_exists" != "1" ]; then
    _dbm_log "📦 Creating database ${db_name}..."
    kubectl exec -n workflow-builder postgresql-0 -- \
      psql "$admin_url" -v ON_ERROR_STOP=1 -v "db_name=${db_name}" -c "select format('create database %I', :'db_name') \\gexec" >/dev/null
  fi

  local has_packages
  has_packages="$(
    kubectl exec -n workflow-builder postgresql-0 -- \
      psql "$database_url" -tAc "select coalesce(to_regclass('public.packages')::text,'')" 2>/dev/null | tr -d '[:space:]'
  )"
  if [ "$has_packages" = "packages" ]; then
    _dbm_log "✅ mpak-registry tables already initialized"
    return 0
  fi

  local mpak_pod
  mpak_pod="$(_dbm_find_pod nimbletools-system app.kubernetes.io/component=registry app.kubernetes.io/name=mpak)"
  if [ -z "$mpak_pod" ]; then
    _dbm_log "❌ Could not find mpak-registry pod to source Prisma migrations"
    return 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"

  kubectl cp "nimbletools-system/${mpak_pod}:/app/apps/registry/prisma/migrations" "$tmpdir" >/dev/null

  local migration_root="$tmpdir/migrations"
  if [ ! -d "$migration_root" ]; then
    _dbm_log "❌ Failed to copy Prisma migrations from mpak-registry"
    rm -rf "$tmpdir"
    return 1
  fi

  local migration_files=()
  mapfile -t migration_files < <(find "$migration_root" -maxdepth 2 -type f -name 'migration.sql' | sort)
  if [ "${#migration_files[@]}" -eq 0 ]; then
    _dbm_log "❌ No Prisma migration files found in mpak-registry image"
    rm -rf "$tmpdir"
    return 1
  fi

  _dbm_log "📚 Applying ${#migration_files[@]} mpak Prisma migration files..."
  local file
  for file in "${migration_files[@]}"; do
    _dbm_log "   -> $(basename "$(dirname "$file")")"
    kubectl exec -i -n workflow-builder postgresql-0 -- \
      psql "$database_url" -v ON_ERROR_STOP=1 >/dev/null < "$file"
  done

  has_packages="$(
    kubectl exec -n workflow-builder postgresql-0 -- \
      psql "$database_url" -tAc "select coalesce(to_regclass('public.packages')::text,'')" 2>/dev/null | tr -d '[:space:]'
  )"
  if [ "$has_packages" != "packages" ]; then
    _dbm_log "❌ mpak bootstrap did not create public.packages"
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  _dbm_log "✅ mpak-registry database bootstrap complete"
}

cluster-reconcile-databases() {
  local with_seed="false"
  if [ "${1:-}" = "--with-seed" ]; then
    with_seed="true"
  fi

  if [ "${SKIP_DB_RECONCILE:-}" = "true" ]; then
    _dbm_log "⏭️  Skipping DB reconciliation (SKIP_DB_RECONCILE=true)"
    return 0
  fi

  run-workflow-builder-atlas-migrations

  if [ "$with_seed" = "true" ] && [ "${SKIP_DB_SEED:-}" != "true" ]; then
    run-workflow-builder-db-seed
  fi

  bootstrap-mpak-registry-db
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-all}" in
    workflow-builder)
      run-workflow-builder-atlas-migrations
      ;;
    workflow-builder-seed)
      run-workflow-builder-db-seed
      ;;
    mpak)
      bootstrap-mpak-registry-db
      ;;
    all)
      cluster-reconcile-databases "${2:-}"
      ;;
    *)
      echo "Usage: $0 [workflow-builder|workflow-builder-seed|mpak|all [--with-seed]]"
      exit 1
      ;;
  esac
fi
