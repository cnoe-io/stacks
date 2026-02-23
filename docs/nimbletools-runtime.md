# NimbleTools Runtime (GitOps)

This stack installs NimbleTools Core with ArgoCD via:

- `packages/base/apps/nimbletools-core.yaml`
- `packages/base/kustomization.yaml`
- `packages/components/active-development/apps/nimble-activepieces-mcps.yaml`

## What Gets Installed

- NimbleTools control plane API
- NimbleTools MCP operator
- NimbleTools RBAC controller
- `mcpservices.mcp.nimbletools.dev` CRD
- Activepieces MCP reconciler CronJob (DB-driven MCPService lifecycle)

Namespace: `nimbletools-system`

## Deployment Flow

Use the standard stack flow (not the upstream install script):

```bash
source ~/stacks/deployment/scripts/cluster-menu.sh
clu
```

Then verify:

```bash
kubectl get pods -n nimbletools-system
kubectl get crd mcpservices.mcp.nimbletools.dev
kubectl get applications.argoproj.io -n argocd nimbletools-core
kubectl get applications.argoproj.io -n argocd nimble-activepieces-mcps
```

## Endpoints

- In-cluster API: `http://nimbletools-core-control-plane.nimbletools-system.svc.cluster.local:8080`
- Ingress API: `https://api.cnoe.localtest.me:8443`
- Ingress MCP host: `https://mcp.cnoe.localtest.me:8443`

## Custom Registry Pattern (Inside Kubernetes)

NimbleTools supports both OCI images and MCPB bundles in server definitions.

### 1) OCI Package From Local Gitea Registry

Use `registryBaseUrl` with the idpbuilder registry host:

```json
{
  "name": "ai.gitea/echo",
  "version": "1.0.0",
  "description": "Echo server from local Gitea OCI registry",
  "packages": [
    {
      "registryType": "oci",
      "registryBaseUrl": "gitea.cnoe.localtest.me:8443",
      "identifier": "giteaadmin/mcp-echo",
      "version": "latest",
      "transport": { "type": "streamable-http" }
    }
  ],
  "_meta": {
    "ai.nimbletools.mcp/v1": {
      "deployment": { "protocol": "http", "port": 8000, "mcpPath": "/mcp" },
      "container": { "healthCheck": { "path": "/health", "port": 8000 } }
    }
  }
}
```

### 2) MCPB Bundle URL Hosted In-Cluster

For `mcpb`, NimbleTools expects the package `identifier` to be the full `.mcpb` URL:

```json
{
  "name": "ai.gitea/echo-bundle",
  "version": "1.0.0",
  "description": "Echo MCPB bundle from in-cluster Gitea",
  "packages": [
    {
      "registryType": "mcpb",
      "identifier": "http://my-gitea-http.gitea.svc.cluster.local:3000/giteaAdmin/mcp-echo/releases/download/v1.0.0/mcp-echo-v1.0.0-linux-amd64.mcpb",
      "version": "1.0.0",
      "transport": { "type": "streamable-http" }
    }
  ],
  "_meta": {
    "ai.nimbletools.mcp/v1": {
      "runtime": "python:3.14",
      "deployment": { "protocol": "http", "port": 8000, "mcpPath": "/mcp" }
    }
  }
}
```

## Activepieces MCP Reconciler (On-Demand + TTL)

`nimble-activepieces-mcps` deploys a CronJob that:

1. Reads active pieces from `app_connection` in workflow-builder Postgres
2. Merges with a pinned hot set (`github,google-calendar,openai` by default)
3. Reconciles Nimble `MCPService` objects in `workflow-builder`
4. Publishes `activepieces-mcp-catalog` (`servers.json`)
5. Deletes stale, reconciler-managed MCPServices after TTL

Manifests:

- `packages/components/active-development/manifests/nimble-activepieces-mcps/CronJob-activepieces-mcp-reconciler.yaml`
- `packages/components/active-development/manifests/nimble-activepieces-mcps/ConfigMap-activepieces-mcp-reconciler-script.yaml`

Runtime-created resource:

- `ConfigMap/workflow-builder/activepieces-mcp-catalog` (created/updated by the reconciler)

Run manually:

```bash
source ~/stacks/deployment/scripts/cluster-menu.sh
clmcp
clmcpst
```

## Consuming Servers From Tools Inside Kubernetes

For in-cluster consumers, use the service DNS created per deployed `MCPService`:

- Service name: `<mcpservice-name>-service`
- Namespace: `workflow-builder`
- MCP endpoint: `http://<mcpservice-name>-service.workflow-builder.svc.cluster.local:3100/mcp`

The reconciler catalog (`activepieces-mcp-catalog`) stores these endpoints in `servers.json`.

This avoids loopback DNS issues with `*.localtest.me` inside pods.
