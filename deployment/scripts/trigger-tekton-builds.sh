#!/usr/bin/env bash
# trigger-tekton-builds.sh - Trigger all Tekton pipeline runs for initial image builds
#
# Called after cluster creation to build all images that are stored in the
# local Gitea registry. Without these builds, pods referencing
# gitea.cnoe.localtest.me/giteaadmin/<image> will fail with ImagePullBackOff.
#
# Usage:
#   ./trigger-tekton-builds.sh           # Wait for pipelines, then trigger all
#   ./trigger-tekton-builds.sh --no-wait # Trigger immediately (assumes pipelines exist)

set -euo pipefail

LOG_PREFIX="[tekton-builds]"
log() { echo "$LOG_PREFIX $1"; }

WAIT_FOR_PIPELINES=true
if [[ "${1:-}" == "--no-wait" ]]; then
  WAIT_FOR_PIPELINES=false
fi

# Wait for Tekton pipelines and triggers to be ready
wait_for_pipelines() {
  log "Waiting for Tekton pipelines to be deployed..."

  local max_retries=60  # 5 minutes
  local retry=0

  while [ $retry -lt $max_retries ]; do
    local stacks_count wb_count
    stacks_count=$(kubectl get pipelines -n stacks-builds --no-headers 2>/dev/null | wc -l)
    wb_count=$(kubectl get pipelines -n workflow-builder --no-headers 2>/dev/null | wc -l)

    if [ "$stacks_count" -ge 3 ] && [ "$wb_count" -ge 9 ]; then
      log "Pipelines ready: stacks-builds=$stacks_count, workflow-builder=$wb_count"
      return 0
    fi

    retry=$((retry + 1))
    sleep 5
  done

  log "WARNING: Timed out waiting for pipelines (stacks=$stacks_count, wb=$wb_count)"
  return 1
}

# Get latest commit SHA from a Gitea repo
get_gitea_sha() {
  local repo="$1"
  kubectl run -q --rm -i --restart=Never "gitea-sha-${repo}-$$" \
    --image=curlimages/curl -- \
    curl -sk -u giteaadmin:developer \
    "http://gitea-http.gitea.svc.cluster.local:3000/api/v1/repos/giteaadmin/${repo}/commits?limit=1" \
    2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['sha'])" 2>/dev/null
}

# Trigger stacks-builds pipelines (devcontainer images)
trigger_stacks_builds() {
  local sha="$1"
  log "Triggering stacks-builds with SHA: ${sha:0:12}..."

  local pipelines=("devcontainer-nodejs-build" "devcontainer-python-build" "devcontainer-hybrid-build")

  for pipeline in "${pipelines[@]}"; do
    kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ${pipeline}-run-
  namespace: stacks-builds
  labels:
    app.kubernetes.io/name: stacks-builds
    app.kubernetes.io/managed-by: trigger-tekton-builds
spec:
  pipelineRef:
    name: ${pipeline}
  taskRunTemplate:
    serviceAccountName: image-build-bot
  params:
    - name: git_sha
      value: "${sha}"
  workspaces:
    - name: registry-auth
      secret:
        secretName: gitea-registry-creds
EOF
    log "  Started: $pipeline"
  done
}

# Trigger workflow-builder pipelines (all app images)
trigger_workflow_builder_builds() {
  local sha="$1"
  log "Triggering workflow-builder builds with SHA: ${sha:0:12}..."

  local pipelines=(
    "workflow-builder-image-build"
    "function-router-image-build"
    "mcp-gateway-image-build"
    "workflow-orchestrator-image-build"
    "durable-agent-image-build"
    # agentuity-coder-image-build: skipped, no Gitea repo exists
    "fn-system-image-build"
    "node-sandbox-image-build"
    "workflow-mcp-server-image-build"
  )

  for pipeline in "${pipelines[@]}"; do
    # Extract image name from pipeline name (remove -image-build suffix)
    local image_name="${pipeline%-image-build}"
    kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ${image_name}-build-
  namespace: workflow-builder
  labels:
    app.kubernetes.io/name: workflow-builder-image-builds
    app.kubernetes.io/managed-by: trigger-tekton-builds
    workflow-builder.cnoe.io/image: ${image_name}
spec:
  pipelineRef:
    name: ${pipeline}
  taskRunTemplate:
    serviceAccountName: workflow-builder-build-trigger
  params:
    - name: git_sha
      value: "${sha}"
EOF
    log "  Started: $pipeline"
  done
}

main() {
  log "Triggering initial Tekton image builds..."

  if [ "$WAIT_FOR_PIPELINES" = true ]; then
    wait_for_pipelines || true
  fi

  # Wait for registry credentials to be synced
  local max_retries=30
  local retry=0
  while [ $retry -lt $max_retries ]; do
    if kubectl get secret gitea-registry-creds -n stacks-builds &>/dev/null && \
       kubectl get secret gitea-registry-creds -n workflow-builder &>/dev/null; then
      break
    fi
    retry=$((retry + 1))
    sleep 5
  done

  # Get latest SHAs from Gitea repos
  local stacks_sha wb_sha
  stacks_sha=$(get_gitea_sha "stacks" || echo "main")
  wb_sha=$(get_gitea_sha "workflow-builder" || echo "main")

  log "Stacks SHA: ${stacks_sha:0:12}"
  log "Workflow-builder SHA: ${wb_sha:0:12}"

  trigger_stacks_builds "$stacks_sha"
  trigger_workflow_builder_builds "$wb_sha"

  log "All pipeline runs triggered (12 total). Monitor with:"
  log "  kubectl get pipelineruns -A"
}

main "$@"
