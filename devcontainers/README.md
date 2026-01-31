# Shared DevSpace Containers

Shared devcontainer images for Kubernetes-native development. Instead of maintaining separate Dockerfile.devspace files in each project, use these centralized images.

## Available Images

| Image | Base | Use Case | Size |
|-------|------|----------|------|
| `nodejs-22-devspace` | node:22-bookworm | Pure Next.js/Node.js apps | ~1GB |
| `python-312-devspace` | python:3.12-bookworm | Pure Python/FastAPI apps | ~1.2GB |
| `nodejs-python-devspace` | node:22 + python3.12 | **Agent apps needing both** | ~1.5GB |

## Quick Start

### Build and Push All Images

```bash
cd stacks/main/devcontainers
bash build-push.sh all
```

### Build Individual Images

```bash
bash build-push.sh nodejs   # Node.js only
bash build-push.sh python   # Python only
bash build-push.sh hybrid   # Node.js + Python (for agent apps)
```

## Hybrid Container (Node.js + Python)

The `nodejs-python-devspace` image is designed for **agent-based applications** that:

1. Run a Node.js/Next.js primary application
2. Use Claude Code or similar AI tools that may generate Python code
3. Need to execute Python scripts at runtime

### What's Included

- **Node.js 22** - Primary runtime for Next.js/Node.js apps
- **Python 3.12** - Full Python installation with pip
- **Claude CLI** - For AI-powered development
- **Pre-installed Python packages**:
  - `numpy`, `pandas` - Data manipulation
  - `requests`, `httpx` - HTTP clients
  - `pydantic` - Data validation
  - `ipython` - Interactive Python
  - `pytest` - Testing

### Usage in DevSpace

```yaml
# For agent apps that need Python execution
devImage: ${GITEA_HOST}/${GITEA_USER}/nodejs-python-devspace:latest
```

### Example: AI Chatbot with Python Execution

```yaml
version: v2beta1
name: ai-chatbot

vars:
  APP_NAME: ai-chatbot

dev:
  app:
    # Use hybrid container for agent capabilities
    devImage: ${GITEA_HOST}/${GITEA_USER}/nodejs-python-devspace:latest

    command:
      - /bin/sh
      - -c
      - |
        echo "=== Agent Development Container ==="
        echo "Node.js: $(node --version)"
        echo "Python:  $(python --version)"
        echo "Claude:  $(claude --version 2>/dev/null || echo 'not installed')"

        # Your startup script...
        exec pnpm dev
```

## Container Comparison

| Feature | nodejs-22 | python-312 | nodejs-python |
|---------|-----------|------------|---------------|
| Node.js 22 | ✅ | ❌ | ✅ |
| Python 3.12 | ❌ | ✅ | ✅ |
| pnpm | ✅ | ❌ | ✅ |
| pip | ❌ | ✅ | ✅ |
| Claude CLI | ❌ | ✅ | ✅ |
| numpy/pandas | ❌ | ❌ | ✅ |
| Default user | root | devuser (1000) | root |
| Primary use | Next.js apps | FastAPI apps | Agent apps |

## Choosing the Right Container

```
Is your app primarily Node.js/Next.js?
├── Yes → Does it need to execute Python code?
│         ├── Yes → nodejs-python-devspace (hybrid)
│         └── No  → nodejs-22-devspace
└── No (Python/FastAPI) → python-312-devspace
```

## Migration Guide

To switch an app to use a shared container:

1. **Update devspace.yaml**:
   ```yaml
   # Before (per-app image):
   devImage: ${GITEA_HOST}/${GITEA_USER}/${APP_NAME}-devspace:latest

   # After (shared image):
   devImage: ${GITEA_HOST}/${GITEA_USER}/nodejs-python-devspace:latest
   ```

2. **Remove per-app Dockerfile.devspace** (optional):
   ```bash
   rm Dockerfile.devspace  # No longer needed
   ```

## Customization

If you need additional packages:

### Option 1: Install at container startup (temporary)

```yaml
command:
  - /bin/sh
  - -c
  - |
    # Install additional Python packages
    pip install --break-system-packages scikit-learn matplotlib

    # Continue with your app
    exec pnpm dev
```

### Option 2: Add to shared Dockerfile (permanent)

If multiple apps need the same package, add it to the appropriate Dockerfile and rebuild.

## Kargo Integration

All containers work with Kargo-promoted images. The DevSpace templates provide variables that show which production image is being replaced:

| Variable | Description |
|----------|-------------|
| `CURRENT_IMAGE_TAG` | Tag of the deployed production image |
| `CURRENT_PRODUCTION_IMAGE` | Full image reference being replaced |

These are queried from the cluster at DevSpace startup:

```yaml
command:
  - /bin/sh
  - -c
  - |
    echo "=== DevSpace Development Container ==="
    echo "Replacing production image: ${CURRENT_PRODUCTION_IMAGE}"
    echo "Using shared devcontainer: nodejs-python-devspace"
    echo ""
    # Your startup script...
    exec pnpm dev
```

This visibility helps developers understand which Kargo-promoted version they're developing against.

## DevSpace Templates Integration

These containers are designed to work with the shared DevSpace templates in `../devspace-templates/`:

```yaml
# Example devspace.yaml using shared container + templates
imports:
  - path: ../../stacks/main/devspace-templates/base.yaml
  - path: ../../stacks/main/devspace-templates/snippets/nextjs.yaml

vars:
  APP_NAME: ai-chatbot

dev:
  app:
    devImage: ${GITEA_HOST}/${GITEA_USER}/nodejs-python-devspace:latest
    # ... rest of config
```

See `../devspace-templates/README.md` for template documentation.
