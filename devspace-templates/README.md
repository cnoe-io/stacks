# DevSpace Templates

Shared DevSpace configuration templates for standardizing Kubernetes-native development across projects.

## Quick Start

Import the base configuration and appropriate framework snippet in your `devspace.yaml`:

```yaml
version: v2beta1
name: my-app

imports:
  - path: ../../stacks/main/devspace-templates/base.yaml
  - path: ../../stacks/main/devspace-templates/snippets/nextjs.yaml  # or fastapi.yaml

vars:
  APP_NAME: my-app
  LOCAL_PORT: "3000"
  CONTAINER_PORT: "3000"

dev:
  app:
    # Complete dev configuration here (see examples)
```

## Architecture

The templates provide **shared variables only**. Each project defines its own complete `dev` configuration using those variables. This approach:

- Keeps configurations explicit and visible in each project
- Allows full customization per project
- Avoids complex merge conflicts
- Provides sensible defaults through imported variables

## Directory Structure

```
devspace-templates/
├── README.md           # This file
├── base.yaml           # Common variables (registry, resources, observability)
├── snippets/
│   ├── nextjs.yaml     # Next.js-specific variables (pnpm version, migrations)
│   └── fastapi.yaml    # FastAPI-specific variables (uvicorn config, Python UID)
└── examples/
    ├── nextjs-minimal.yaml   # Complete Next.js example
    └── fastapi-minimal.yaml  # Complete FastAPI example
```

## Shared Devcontainers

Instead of maintaining per-app devcontainers, use centralized shared images from `devcontainers/`:

| Image | Base | Use Case |
|-------|------|----------|
| `nodejs-22-devspace` | node:22-bookworm | Next.js/Node.js apps |
| `python-312-devspace` | python:3.12-bookworm | Python/FastAPI apps |
| `nodejs-python-devspace` | node:22 + python3.12 | Agent apps needing both |

Build and push shared devcontainers:
```bash
cd stacks/main/devcontainers
bash build-push.sh all    # Build all images
bash build-push.sh hybrid # Build Node.js+Python only
```

See `devcontainers/README.md` for detailed container specifications.

## Variables Reference

### Base Variables (base.yaml)

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | (required) | Application name (namespace, container, labels) |
| `LOCAL_PORT` | `3000` | Local port for forwarding |
| `CONTAINER_PORT` | `3000` | Container port |
| `GITEA_HOST` | `gitea.cnoe.localtest.me:8443` | Registry host |
| `GITEA_USER` | `giteaadmin` | Registry user |
| `SSH_PORT` | `2222` | SSH tunnel port (informational only - use integer in config) |
| `CPU_REQUEST` | `500m` | CPU request |
| `CPU_LIMIT` | `4` | CPU limit |
| `MEMORY_REQUEST` | `2Gi` | Memory request |
| `MEMORY_LIMIT` | `8Gi` | Memory limit |
| `OTEL_SERVICE_NAME` | `${APP_NAME}-dev` | OpenTelemetry service name |
| `OTEL_ENVIRONMENT` | `development` | OpenTelemetry environment |

### Kargo Integration Variables (base.yaml)

| Variable | Description |
|----------|-------------|
| `CURRENT_IMAGE_TAG` | Tag of currently deployed production image (queried from cluster) |
| `CURRENT_PRODUCTION_IMAGE` | Full image reference being replaced by DevSpace |

These variables query the cluster at DevSpace startup to show which Kargo-promoted image is being replaced:

```yaml
command:
  - /bin/sh
  - -c
  - |
    echo "Replacing production image: ${CURRENT_PRODUCTION_IMAGE}"
    echo "Using devcontainer: nodejs-22-devspace"
    exec pnpm dev
```

### Next.js Variables (snippets/nextjs.yaml)

| Variable | Default | Description |
|----------|---------|-------------|
| `PNPM_VERSION` | `9.12.3` | pnpm version |
| `RUN_MIGRATIONS` | `false` | Enable database migrations |
| `MIGRATION_COMMAND` | (empty) | Migration command |
| `INSTALL_CLAUDE_CLI` | `false` | Install Claude CLI |

### FastAPI Variables (snippets/fastapi.yaml)

| Variable | Default | Description |
|----------|---------|-------------|
| `UVICORN_HOST` | `0.0.0.0` | Uvicorn bind host |
| `UVICORN_PORT` | `8080` | Uvicorn bind port |
| `UVICORN_APP` | `main:app` | Uvicorn app module |
| `PYTHON_UID` | `1000` | Non-root user UID |
| `PYTHON_GID` | `1000` | Non-root user GID |

## Port Allocation

When running multiple DevSpace instances simultaneously:

| App | Local Port | SSH Port | Container Port |
|-----|------------|----------|----------------|
| ai-chatbot | 3000 | 2222 | 3000 |
| workflow-builder | 3002 | 2223 | 3000 |
| planner-agent | 8080 | 2224 | 8080 |

**Note:** SSH `localPort` must be an integer in the config, not a variable reference.

## Key Differences by Framework

### Next.js Apps

- Run as root (UID 0) for npm/pnpm permissions
- Use `-devspace` suffixed dev images
- Enable `persistPaths` for node_modules
- `startContainer: true` - wait for sync before starting

### FastAPI Apps

- Run as non-root user (UID 1000) for Claude CLI security
- Use production images directly
- Disable `restartHelper.inject` for permission issues
- `startContainer: false` - start immediately, sync in background

## Usage Examples

See `examples/` directory for complete, working configurations:

- `nextjs-minimal.yaml` - Minimal Next.js app
- `fastapi-minimal.yaml` - Minimal FastAPI app

## Migration Guide

To migrate an existing devspace.yaml:

1. Add imports section pointing to base.yaml and appropriate snippet
2. Move hardcoded values to vars section
3. Replace hardcoded strings with `${VARIABLE}` references
4. Update paths based on project location relative to stacks/main

## How Imports Work

From [DevSpace documentation](https://www.devspace.sh/docs/configuration/imports/):

- Imports merge specified config files into the main config
- The main `devspace.yaml` takes precedence over imported files
- Importable sections: `vars`, `dev`, `deployments`, `images`, etc.
- Local path imports work relative to the importing file

## Validation

```bash
# Verify config parses correctly (shows merged output)
devspace print

# List all variables and their values
devspace list vars

# Test with debug output
devspace dev --debug
```

## Integration with devenv.nix

These templates work with existing devenv.nix orchestration:

- `devenv up` continues to manage OTEL port-forwards and processes
- DevSpace handles container replacement and file sync
- Existing Dockerfile.devspace files remain unchanged

## Troubleshooting

### "cannot unmarshal string into int"

SSH `localPort` must be an integer, not a variable. Use `localPort: 2222` instead of `localPort: ${SSH_PORT}`.

### Import path not found

Check the relative path from your project to `stacks/main/devspace-templates/`. Common patterns:

- From `ai/main/`: `../../stacks/main/devspace-templates/`
- From `workflow-builder/main/`: `../../stacks/main/devspace-templates/`
- From git worktrees: May need adjustment based on worktree location

### Variables not interpolating

Ensure variables are defined before use. Import order matters:
1. base.yaml (defines defaults)
2. snippet.yaml (defines framework defaults)
3. Your vars section (overrides)

## Related Documentation

- `../devcontainers/README.md` - Shared devcontainer images
- `../docs/devspace-kargo-workflow.md` - Complete DevSpace + Kargo workflow
- `../CLAUDE.md` - Main repository documentation
