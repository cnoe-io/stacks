# Multi-stage Dockerfile for SpecKit Agents
#
# Architecture:
# - Claude Agent SDK handles all LLM-powered agent execution
# - Dapr handles distributed systems (pub/sub, state store)
# - Orchestrator is pure Dapr routing (no LLM calls)
#
# Usage:
#   docker build -t speckit-agents .
#   docker run -e AGENT_NAME=specifier -e ANTHROPIC_API_KEY=xxx speckit-agents

# ============================================================================
# Stage 1: Builder - Install dependencies
# ============================================================================
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install dependencies into a virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ============================================================================
# Stage 2: Runtime - Minimal production image
# ============================================================================
FROM python:3.11-slim as runtime

WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application code
COPY src/ ./src/

# Create artifacts directory
RUN mkdir -p /artifacts && chmod 755 /artifacts

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app /artifacts
USER appuser

# Environment variables with defaults
ENV PYTHONPATH="/app" \
    PYTHONUNBUFFERED="1" \
    PYTHONDONTWRITEBYTECODE="1" \
    # Agent identity
    AGENT_NAME="orchestrator" \
    AGENT_PORT="8000" \
    TEAM_NAME="speckit" \
    # Dapr component names
    PUBSUB_NAME="messagepubsub" \
    WORKFLOW_STATE_STORE="workflowstatestore" \
    REGISTRY_STATE_STORE="agentregistrystore" \
    MEMORY_STORE="memorystore" \
    # Dapr sidecar ports
    DAPR_HTTP_PORT="3500" \
    DAPR_GRPC_PORT="50001" \
    # Artifact storage
    ARTIFACTS_PATH="/artifacts" \
    # Claude SDK configuration
    # Note: ANTHROPIC_API_KEY must be provided at runtime
    CLAUDE_MODEL="claude-sonnet-4-20250514" \
    CLAUDE_MAX_TURNS="10" \
    # Langfuse observability (disabled by default)
    LANGFUSE_ENABLED="false"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${AGENT_PORT}/healthz')" || exit 1

# Expose agent port (can be overridden per-agent)
EXPOSE 8000

# Run the application
# AGENT_NAME env var determines which agent to run:
# - orchestrator: Pure Dapr routing (no LLM)
# - specifier: Claude SDK agent for spec generation
# - planner: Claude SDK agent with parallel subagents
# - task-generator: Claude SDK agent for task breakdown
# - implementer: Claude SDK agent for TDD execution
CMD ["python", "-m", "src.main"]

# ============================================================================
# Stage 3: Development - Includes dev dependencies
# ============================================================================
FROM runtime as development

USER root

# Install dev dependencies
RUN pip install --no-cache-dir \
    pytest>=8.0.0 \
    pytest-asyncio>=0.23.0 \
    pytest-cov>=4.0.0 \
    ruff>=0.3.0 \
    mypy>=1.8.0

# Create test directory
RUN mkdir -p /app/tests && chown -R appuser:appuser /app/tests

USER appuser

# Override command for interactive development
CMD ["python", "-m", "src.main"]
