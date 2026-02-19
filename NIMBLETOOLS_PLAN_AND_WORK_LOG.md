# NimbleTools Runtime Plan And Work Log

## Objective
Enable NimbleTools runtime infrastructure in-cluster and align with ArgoCD/idpbuilder/kustomize workflows so MCP servers can be built, deployed, and consumed from Kubernetes.

## Plan
1. Install and declare Nimble core/runtime components in GitOps manifests.
2. Add/adjust build and deployment automation for MCP server artifacts.
3. Update cluster operations scripts for bootstrap, migrations, and dev workflows.
4. Add manifests for managed MCP apps/services and registry integration.

## Work Reflected In This Repo
### GitOps / manifests
- Added Nimble core app manifest:
  - `packages/base/apps/nimbletools-core.yaml`
- Added active-development app manifests:
  - `packages/components/active-development/apps/mpak-registry.yaml`
  - `packages/components/active-development/apps/nimble-activepieces-mcps.yaml`
- Added Nimble activepieces MCP manifest set:
  - `packages/components/active-development/manifests/nimble-activepieces-mcps/`

### Build pipeline updates
- Added build definitions:
  - `packages/components/active-development/manifests/workflow-builder-builds/Build-mpak-registry.yaml`
  - `packages/components/active-development/manifests/workflow-builder-builds/Build-piece-mcp-server.yaml`
- Updated trigger template and related kustomizations:
  - `packages/components/active-development/manifests/workflow-builder-builds/TriggerTemplate-workflow-builder-fn-builds.yaml`
  - related `kustomization.yaml` files

### Cluster operations / scripts
- Updated cluster menu script:
  - `deployment/scripts/cluster-menu.sh`
- Added DB migration helper script:
  - `deployment/scripts/db-migrations.sh`

### Kustomize wiring and RBAC adjustments
- Updated base and component kustomizations:
  - `packages/base/kustomization.yaml`
  - `packages/components/active-development/kustomization.yaml`
  - `packages/components/active-development/manifests/durable-agent/kustomization.yaml`
  - others as modified
- Updated RBAC for MCP provisioning:
  - `packages/components/active-development/manifests/workflow-builder/Role-piece-mcp-provisioner.yaml`

### Documentation
- Added runtime guidance doc:
  - `docs/nimbletools-runtime.md`

## Notes
- This log summarizes implemented infrastructure changes currently present in this repo’s working tree.
- Workflow-builder application-layer MCP connection management is implemented in the separate `workflow-builder/main` repo.
