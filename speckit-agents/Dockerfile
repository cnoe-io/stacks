# Multi-stage Dockerfile for SpecKit agents
# Uses AGENT_NAME environment variable to select which agent to run

# ============================================================================
# Stage 1: Builder
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
# Stage 2: Runtime
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
ENV AGENT_NAME="orchestrator" \
    AGENT_PORT="8000" \
    TEAM_NAME="speckit" \
    PUBSUB_NAME="messagepubsub" \
    WORKFLOW_STATE_STORE="workflowstatestore" \
    REGISTRY_STATE_STORE="agentregistrystore" \
    MEMORY_STORE="memorystore" \
    CONVERSATION_COMPONENT="anthropic" \
    DAPR_HTTP_PORT="3500" \
    DAPR_GRPC_PORT="50001" \
    ARTIFACTS_PATH="/artifacts" \
    PYTHONPATH="/app"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${AGENT_PORT}/healthz')" || exit 1

# Expose agent port
EXPOSE 8000

# Run the application
CMD ["python", "-m", "src.main"]
