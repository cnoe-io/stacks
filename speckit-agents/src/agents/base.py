"""Base agent class using Claude Agent SDK with Dapr integration.

Provides:
- Dapr client for state/pub/sub operations
- Claude SDK options factory
- Artifact management
- Workflow state management
- Langfuse observability integration
- OpenTelemetry/Jaeger distributed tracing
- Tool invocation recording
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
from abc import ABC, abstractmethod
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Any, Generator, Optional
from uuid import UUID

from dapr.clients import DaprClient

from src.common.config import Settings, get_settings
from src.common.claude_config import AgentConfig, build_claude_options
from src.common.models import (
    Artifact,
    ArtifactType,
    Workflow,
    WorkflowMessage,
    WorkflowPhase,
    WorkflowStatus,
)
from src.services.tracing import (
    TracingService,
    get_tracing_service,
    inject_trace_context,
    extract_trace_context,
)
from src.services.tool_recorder import ToolRecorder, get_tool_recorder

logger = logging.getLogger(__name__)

# Langfuse client (lazy loaded, graceful degradation)
_langfuse_client = None
_langfuse_init_attempted = False


def get_langfuse_client():
    """Get or create Langfuse client with graceful degradation.

    Returns:
        Langfuse client or None if not available
    """
    global _langfuse_client, _langfuse_init_attempted

    if _langfuse_init_attempted:
        return _langfuse_client

    _langfuse_init_attempted = True
    settings = get_settings()

    if not settings.langfuse_enabled:
        logger.info("Langfuse disabled by configuration")
        return None

    try:
        from langfuse import Langfuse

        _langfuse_client = Langfuse(
            host=settings.langfuse_host,
            public_key=settings.langfuse_public_key,
            secret_key=settings.langfuse_secret_key,
        )
        logger.info(f"Langfuse initialized: {settings.langfuse_host}")
        return _langfuse_client

    except ImportError:
        logger.warning("Langfuse package not installed, observability disabled")
        return None
    except Exception as e:
        logger.warning(f"Failed to initialize Langfuse: {e}")
        return None


class BaseClaudeAgent(ABC):
    """Base class for Claude SDK powered agents with Dapr integration.

    Provides:
    - Dapr client for state/pub/sub operations
    - Claude SDK options factory
    - Artifact management
    - Workflow state management
    - Langfuse trace context propagation
    - OpenTelemetry/Jaeger tracing with W3C propagation
    - Tool invocation recording to Langfuse
    """

    def __init__(
        self,
        agent_config: AgentConfig,
        settings: Optional[Settings] = None,
    ) -> None:
        """Initialize Claude agent with Dapr configuration.

        Args:
            agent_config: Claude SDK agent configuration
            settings: Optional settings override (defaults to env config)
        """
        self.settings = settings or get_settings()
        self.agent_config = agent_config
        self.name = agent_config.name

        # Dapr client (lazy initialized)
        self._dapr_client: Optional[DaprClient] = None

        # Langfuse trace management
        self._trace_id: Optional[str] = None
        self._workflow_id: Optional[UUID] = None

        # MCP servers (to be registered by subclasses)
        self._mcp_servers: dict[str, Any] = {}

        # OpenTelemetry tracing (lazy initialized)
        self._tracing: Optional[TracingService] = None
        self._current_span: Optional[Any] = None

        # Tool recording for Langfuse
        self._tool_recorder: Optional[ToolRecorder] = None

    @property
    def dapr_client(self) -> DaprClient:
        """Get or create Dapr client."""
        if self._dapr_client is None:
            self._dapr_client = DaprClient()
        return self._dapr_client

    @property
    def tracing(self) -> TracingService:
        """Get or create the tracing service."""
        if self._tracing is None:
            self._tracing = get_tracing_service()
        return self._tracing

    @property
    def tool_recorder(self) -> ToolRecorder:
        """Get or create the tool recorder."""
        if self._tool_recorder is None:
            self._tool_recorder = get_tool_recorder()
            # Link tool recorder to current Langfuse trace if available
            if hasattr(self, "_langfuse_trace") and self._langfuse_trace:
                self._tool_recorder.set_langfuse_trace(self._langfuse_trace)
        return self._tool_recorder

    # =========================================================================
    # OpenTelemetry Tracing
    # =========================================================================

    def start_workflow_span(
        self,
        workflow_id: UUID,
        operation: str = "process_task",
    ) -> Optional[Any]:
        """Start an OpenTelemetry span for workflow processing.

        Args:
            workflow_id: Workflow UUID
            operation: Operation name

        Returns:
            Span object or None if tracing disabled
        """
        span = self.tracing.start_workflow_span(
            workflow_id=str(workflow_id),
            agent_name=self.name,
            operation=operation,
            langfuse_trace_id=self._trace_id,
        )
        self._current_span = span
        return span

    def end_workflow_span(
        self,
        success: bool = True,
        error: Optional[str] = None,
    ) -> None:
        """End the current workflow span.

        Args:
            success: Whether processing succeeded
            error: Optional error message
        """
        if self._current_span:
            self.tracing.end_span(self._current_span, success=success, error=error)
            self._current_span = None

    def add_span_attributes(self, attributes: dict[str, Any]) -> None:
        """Add attributes to the current span.

        Args:
            attributes: Key-value attributes to add
        """
        if self._current_span:
            self.tracing.set_span_attributes(self._current_span, attributes)

    def get_trace_propagation_headers(self) -> dict[str, str]:
        """Get W3C trace context headers for propagation.

        Returns:
            Dict with traceparent/tracestate headers
        """
        carrier: dict[str, str] = {}
        return inject_trace_context(carrier)

    def extract_trace_from_headers(self, headers: dict[str, str]) -> None:
        """Extract and set trace context from propagation headers.

        Args:
            headers: Dict with traceparent/tracestate headers
        """
        extract_trace_context(headers)

    def register_mcp_server(self, name: str, server: Any) -> None:
        """Register an MCP server for use with Claude SDK.

        Args:
            name: Server name (e.g., "dapr", "tests")
            server: MCP server instance
        """
        self._mcp_servers[name] = server
        logger.debug(f"Registered MCP server: {name}")

    def get_claude_options(
        self,
        additional_tools: list[str] | None = None,
        override_model: str | None = None,
        override_max_turns: int | None = None,
    ) -> dict[str, Any]:
        """Build Claude SDK options with registered MCP servers.

        Args:
            additional_tools: Extra tools to add
            override_model: Override default model
            override_max_turns: Override default max_turns

        Returns:
            Dictionary suitable for ClaudeAgentOptions
        """
        options = build_claude_options(
            self.agent_config,
            additional_tools=additional_tools,
            override_model=override_model,
            override_max_turns=override_max_turns,
        )

        # Add registered MCP servers
        if self._mcp_servers:
            options["mcp_servers"] = self._mcp_servers

        return options

    # =========================================================================
    # Dapr State Operations
    # =========================================================================

    async def save_workflow_state(self, workflow: Workflow) -> None:
        """Save workflow state to Dapr state store."""
        workflow.updated_at = datetime.utcnow()
        key = f"workflow:{workflow.id}"
        value = workflow.model_dump_json()

        try:
            await asyncio.to_thread(
                self.dapr_client.save_state,
                store_name=self.settings.workflow_state_store,
                key=key,
                value=value,
            )
            logger.debug(f"Saved workflow state: {workflow.id}")
        except Exception as e:
            logger.error(f"Failed to save workflow state: {e}")
            raise

    async def get_workflow_state(self, workflow_id: UUID) -> Optional[Workflow]:
        """Get workflow state from Dapr state store."""
        key = f"workflow:{workflow_id}"

        try:
            state = await asyncio.to_thread(
                self.dapr_client.get_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            if state.data:
                return Workflow.model_validate_json(state.data)
        except Exception as e:
            logger.error(f"Failed to get workflow state: {e}")

        return None

    # =========================================================================
    # Dapr Pub/Sub Operations
    # =========================================================================

    async def publish_phase_complete(
        self,
        workflow_id: UUID,
        phase: WorkflowPhase,
        result: dict[str, Any] | None = None,
    ) -> None:
        """Publish phase completion event to orchestrator."""
        topic = f"{self.settings.team_name}.orchestrator.requests"

        message = WorkflowMessage(
            source=self.name,
            workflow_id=workflow_id,
            task=f"phase_complete:{phase.value}",
            context={
                "completed_phase": phase.value,
                "result": result or {},
                "langfuse_trace_id": self._trace_id,
            },
        )

        try:
            await asyncio.to_thread(
                self.dapr_client.publish_event,
                pubsub_name=self.settings.pubsub_name,
                topic_name=topic,
                data=message.model_dump_json(),
                data_content_type="application/json",
            )
            logger.info(f"Published phase completion: {phase.value} for workflow {workflow_id}")
        except Exception as e:
            logger.error(f"Failed to publish phase completion: {e}")
            raise

    async def publish_status_update(
        self,
        workflow_id: UUID,
        status: WorkflowStatus,
        phase: WorkflowPhase,
        progress_percent: int = 0,
        error: Optional[str] = None,
    ) -> None:
        """Publish workflow status update to broadcast topic."""
        message = {
            "workflow_id": str(workflow_id),
            "status": status.value,
            "phase": phase.value,
            "agent": self.name,
            "progress_percent": progress_percent,
            "error": error,
            "timestamp": datetime.utcnow().isoformat(),
        }

        try:
            await asyncio.to_thread(
                self.dapr_client.publish_event,
                pubsub_name=self.settings.pubsub_name,
                topic_name=self.settings.workflow_status_topic,
                data=json.dumps(message),
                data_content_type="application/json",
            )
            logger.debug(f"Published status update for workflow {workflow_id}")
        except Exception as e:
            logger.error(f"Failed to publish status update: {e}")

    # =========================================================================
    # Artifact Management (Dapr State Store)
    # =========================================================================

    def get_artifacts_path(self, workflow_id: UUID) -> Path:
        """Get the artifacts directory path for a workflow (for local fallback)."""
        return Path(self.settings.artifacts_path) / str(workflow_id)

    def _artifact_state_key(self, workflow_id: UUID, artifact_type: ArtifactType) -> str:
        """Generate Dapr state key for an artifact.

        Format: artifact:{workflow_id}:{artifact_type}
        """
        return f"artifact:{workflow_id}:{artifact_type.value}"

    async def save_artifact_content(
        self,
        workflow_id: UUID,
        artifact_type: ArtifactType,
        content: str,
    ) -> None:
        """Save artifact content to Dapr state store.

        Args:
            workflow_id: Workflow ID
            artifact_type: Type of artifact
            content: Artifact content to save
        """
        key = self._artifact_state_key(workflow_id, artifact_type)

        try:
            await asyncio.to_thread(
                self.dapr_client.save_state,
                store_name=self.settings.workflow_state_store,
                key=key,
                value=content,
            )
            logger.info(f"Saved artifact to Dapr state: {key}")
        except Exception as e:
            logger.error(f"Failed to save artifact to Dapr state: {e}")
            raise

    async def register_artifact(
        self,
        workflow_id: UUID,
        artifact_type: ArtifactType,
        path: str,
        content: str,
    ) -> Artifact:
        """Register a generated artifact and store content in Dapr state.

        Args:
            workflow_id: Workflow ID
            artifact_type: Type of artifact
            path: Relative path (for reference, not used for storage)
            content: Artifact content to save

        Returns:
            Created Artifact object
        """
        content_hash = hashlib.sha256(content.encode()).hexdigest()

        artifact = Artifact(
            workflow_id=workflow_id,
            type=artifact_type,
            path=path,
            content_hash=content_hash,
            created_by=self.name,
        )

        # Save artifact content to Dapr state store
        await self.save_artifact_content(workflow_id, artifact_type, content)

        # Update workflow state with new artifact metadata
        workflow = await self.get_workflow_state(workflow_id)
        if workflow:
            # Remove existing artifact of same type if present
            workflow.artifacts = [a for a in workflow.artifacts if a.type != artifact_type]
            workflow.artifacts.append(artifact)
            await self.save_workflow_state(workflow)

        logger.info(f"Registered artifact: {artifact_type.value} (stored in Dapr state)")
        return artifact

    async def get_artifact_content(
        self,
        workflow_id: UUID,
        artifact_type: ArtifactType,
    ) -> Optional[str]:
        """Read artifact content from Dapr state store.

        Args:
            workflow_id: Workflow ID
            artifact_type: Type of artifact to read

        Returns:
            Artifact content or None if not found
        """
        key = self._artifact_state_key(workflow_id, artifact_type)

        try:
            state = await asyncio.to_thread(
                self.dapr_client.get_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            if state.data:
                content = state.data.decode() if isinstance(state.data, bytes) else state.data
                logger.debug(f"Retrieved artifact from Dapr state: {key}")
                return content
            else:
                logger.warning(f"Artifact not found in Dapr state: {key}")
                return None
        except Exception as e:
            logger.error(f"Failed to read artifact from Dapr state: {e}")
            return None

    # =========================================================================
    # Langfuse Trace Management
    # =========================================================================

    def set_trace_context(
        self,
        workflow_id: UUID,
        trace_id: Optional[str] = None,
    ) -> None:
        """Set trace context for observability.

        Args:
            workflow_id: Workflow ID (used as session ID)
            trace_id: Optional existing trace ID to continue
        """
        self._workflow_id = workflow_id
        self._trace_id = trace_id
        logger.debug(f"Set trace context: workflow={workflow_id}, trace={trace_id}")

    def extract_trace_from_context(self, context: dict[str, Any]) -> Optional[str]:
        """Extract Langfuse trace ID from message context.

        Args:
            context: Message context dict

        Returns:
            Trace ID if present
        """
        trace_id = context.get("langfuse_trace_id")
        if trace_id:
            self._trace_id = trace_id
            logger.debug(f"Extracted trace_id from context: {trace_id}")
        return trace_id

    def create_trace(
        self,
        name: Optional[str] = None,
        metadata: Optional[dict[str, Any]] = None,
    ) -> Optional[Any]:
        """Create a new Langfuse trace for this agent's execution.

        Args:
            name: Trace name (defaults to agent name)
            metadata: Additional metadata to attach

        Returns:
            Langfuse trace object or None if unavailable
        """
        langfuse = get_langfuse_client()
        if not langfuse:
            return None

        try:
            trace_metadata = {
                "agent": self.name,
                "workflow_id": str(self._workflow_id) if self._workflow_id else None,
                **(metadata or {}),
            }

            trace = langfuse.trace(
                name=name or f"agent:{self.name}",
                session_id=str(self._workflow_id) if self._workflow_id else None,
                metadata=trace_metadata,
            )

            # Store trace ID for propagation
            self._trace_id = trace.id
            self._langfuse_trace = trace

            logger.debug(f"Created Langfuse trace: {trace.id}")
            return trace

        except Exception as e:
            logger.warning(f"Failed to create Langfuse trace: {e}")
            return None

    def create_generation_span(
        self,
        name: str,
        input_text: str,
        model: Optional[str] = None,
        metadata: Optional[dict[str, Any]] = None,
    ) -> Optional[Any]:
        """Create a generation span for an LLM call.

        Args:
            name: Span name
            input_text: Input prompt text
            model: Model name
            metadata: Additional metadata

        Returns:
            Langfuse generation object or None
        """
        if not hasattr(self, "_langfuse_trace") or not self._langfuse_trace:
            return None

        try:
            generation = self._langfuse_trace.generation(
                name=name,
                model=model or self.agent_config.model,
                input=input_text[:1000],  # Truncate for storage
                metadata={
                    "agent": self.name,
                    "max_turns": self.agent_config.max_turns,
                    **(metadata or {}),
                },
            )
            return generation

        except Exception as e:
            logger.warning(f"Failed to create generation span: {e}")
            return None

    def end_generation_span(
        self,
        generation: Any,
        output_text: str,
        usage: Optional[dict] = None,
    ) -> None:
        """End a generation span with output.

        Args:
            generation: Generation object from create_generation_span
            output_text: Output text from LLM
            usage: Token usage dict
        """
        if not generation:
            return

        try:
            generation.end(
                output=output_text[:1000],  # Truncate
                usage=usage,
            )
        except Exception as e:
            logger.warning(f"Failed to end generation span: {e}")

    def log_error_to_trace(
        self,
        error: str,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        """Log an error to the current trace.

        Args:
            error: Error message
            context: Additional context
        """
        if not hasattr(self, "_langfuse_trace") or not self._langfuse_trace:
            return

        try:
            self._langfuse_trace.event(
                name="error",
                level="ERROR",
                metadata={
                    "agent": self.name,
                    "error": error,
                    **(context or {}),
                },
            )
        except Exception as e:
            logger.warning(f"Failed to log error to trace: {e}")

    def flush_traces(self) -> None:
        """Flush any pending traces to Langfuse."""
        langfuse = get_langfuse_client()
        if langfuse:
            try:
                langfuse.flush()
            except Exception as e:
                logger.warning(f"Failed to flush traces: {e}")

    # =========================================================================
    # Abstract Methods
    # =========================================================================

    @abstractmethod
    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process a task assigned to this agent.

        Args:
            workflow_id: The workflow this task belongs to
            task: Task description or instruction
            context: Additional context (artifacts, state, etc.)

        Returns:
            Result dict with output artifacts and status
        """
        pass

    # =========================================================================
    # Lifecycle
    # =========================================================================

    async def shutdown(self) -> None:
        """Graceful shutdown of agent resources."""
        # Flush any pending traces
        self.flush_traces()

        if self._dapr_client:
            try:
                self._dapr_client.close()
            except Exception as e:
                logger.error(f"Error closing Dapr client: {e}")
            self._dapr_client = None
