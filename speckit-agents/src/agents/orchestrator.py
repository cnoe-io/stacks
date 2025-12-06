"""Orchestrator for managing SpecKit workflows.

The Orchestrator is a pure Dapr router - it does NOT use Claude SDK.
It manages workflow lifecycle using only Dapr pub/sub and state management.
"""

from __future__ import annotations

import asyncio
import json
import logging
import random
from datetime import datetime, timedelta
from typing import Any, Callable, Optional, TypeVar
from uuid import UUID

from dapr.clients import DaprClient
from fastapi import APIRouter, FastAPI, HTTPException, Request

from src.common.config import Settings, get_settings
from src.common.health import router as health_router
from src.common.models import (
    TraceIds,
    Workflow,
    WorkflowMessage,
    WorkflowPhase,
    WorkflowRequest,
    WorkflowResponse,
    WorkflowStatus,
    WorkflowStatusResponse,
)

T = TypeVar("T")

logger = logging.getLogger(__name__)


class RetryConfig:
    """Configuration for retry with exponential backoff."""

    def __init__(
        self,
        max_retries: int = 3,
        base_delay: float = 1.0,
        max_delay: float = 60.0,
        exponential_base: float = 2.0,
        jitter: float = 0.1,
    ):
        """Initialize retry configuration.

        Args:
            max_retries: Maximum number of retry attempts
            base_delay: Initial delay in seconds
            max_delay: Maximum delay in seconds (caps exponential growth)
            exponential_base: Base for exponential backoff
            jitter: Random jitter factor (0.1 = ±10%)
        """
        self.max_retries = max_retries
        self.base_delay = base_delay
        self.max_delay = max_delay
        self.exponential_base = exponential_base
        self.jitter = jitter

    def get_delay(self, attempt: int) -> float:
        """Calculate delay for a given attempt with jitter.

        Args:
            attempt: Current attempt number (0-indexed)

        Returns:
            Delay in seconds with jitter applied
        """
        # Exponential backoff: base_delay * exponential_base ^ attempt
        delay = self.base_delay * (self.exponential_base ** attempt)

        # Cap at max_delay
        delay = min(delay, self.max_delay)

        # Apply jitter (±jitter%)
        jitter_range = delay * self.jitter
        delay += random.uniform(-jitter_range, jitter_range)

        return max(0, delay)


class PhaseTimeoutConfig:
    """Phase-specific timeout configuration."""

    # Default timeouts per phase in seconds
    PHASE_TIMEOUTS = {
        WorkflowPhase.SPECIFICATION: 300,  # 5 minutes
        WorkflowPhase.PLANNING: 600,  # 10 minutes
        WorkflowPhase.TASK_GENERATION: 300,  # 5 minutes
        WorkflowPhase.IMPLEMENTATION: 1800,  # 30 minutes
    }

    @classmethod
    def get_timeout(cls, phase: WorkflowPhase) -> int:
        """Get timeout in seconds for a phase."""
        return cls.PHASE_TIMEOUTS.get(phase, 600)  # Default 10 minutes


class DaprOrchestrator:
    """Pure Dapr orchestrator - no Claude SDK, no LLM calls.

    The Orchestrator:
    - Receives feature requests via /run endpoint
    - Creates workflow state in Dapr state store
    - Routes tasks to specialized agents via Dapr pub/sub
    - Tracks workflow progress
    - Handles phase completion events
    - Implements retry logic with exponential backoff
    - Enforces phase-specific timeouts
    """

    def __init__(self, settings: Optional[Settings] = None) -> None:
        """Initialize the Dapr Orchestrator.

        Args:
            settings: Optional settings override
        """
        self.settings = settings or get_settings()
        self.name = "orchestrator"

        # Dapr client (lazy initialized)
        self._dapr_client: Optional[DaprClient] = None

        # Langfuse trace ID for this workflow session
        self._trace_id: Optional[str] = None

        # Retry configuration
        self._retry_config = RetryConfig()

        # Active phase tracking for timeout enforcement
        self._phase_start_times: dict[UUID, datetime] = {}

        # Phase to agent mapping
        self._phase_agents = {
            WorkflowPhase.SPECIFICATION: "specifier",
            WorkflowPhase.PLANNING: "planner",
            WorkflowPhase.TASK_GENERATION: "task-generator",
            WorkflowPhase.IMPLEMENTATION: "implementer",
        }

    @property
    def dapr_client(self) -> DaprClient:
        """Get or create Dapr client."""
        if self._dapr_client is None:
            self._dapr_client = DaprClient()
        return self._dapr_client

    # =========================================================================
    # Retry Logic with Exponential Backoff
    # =========================================================================

    async def retry_with_backoff(
        self,
        operation: Callable[[], T],
        operation_name: str,
        workflow_id: Optional[UUID] = None,
        retryable_exceptions: tuple = (Exception,),
    ) -> T:
        """Execute an operation with retry and exponential backoff.

        Args:
            operation: Async callable to execute
            operation_name: Human-readable name for logging
            workflow_id: Optional workflow ID for logging
            retryable_exceptions: Tuple of exceptions that should trigger retry

        Returns:
            Result of the operation

        Raises:
            Last exception if all retries exhausted
        """
        last_exception: Optional[Exception] = None

        for attempt in range(self._retry_config.max_retries + 1):
            try:
                return await operation()
            except retryable_exceptions as e:
                last_exception = e

                if attempt < self._retry_config.max_retries:
                    delay = self._retry_config.get_delay(attempt)
                    logger.warning(
                        f"Retry {attempt + 1}/{self._retry_config.max_retries} "
                        f"for {operation_name}"
                        f"{f' (workflow {workflow_id})' if workflow_id else ''}: "
                        f"{e}. Waiting {delay:.2f}s"
                    )
                    await asyncio.sleep(delay)
                else:
                    logger.error(
                        f"All {self._retry_config.max_retries} retries exhausted "
                        f"for {operation_name}"
                        f"{f' (workflow {workflow_id})' if workflow_id else ''}: {e}"
                    )

        # All retries exhausted
        raise last_exception  # type: ignore

    # =========================================================================
    # Phase Timeout Enforcement
    # =========================================================================

    def start_phase_timer(self, workflow_id: UUID, phase: WorkflowPhase) -> None:
        """Start timeout timer for a phase.

        Args:
            workflow_id: Workflow ID
            phase: Phase being started
        """
        self._phase_start_times[workflow_id] = datetime.utcnow()
        timeout = PhaseTimeoutConfig.get_timeout(phase)
        logger.debug(
            f"Started phase timer for workflow {workflow_id}, "
            f"phase {phase.value}, timeout {timeout}s"
        )

    def check_phase_timeout(
        self,
        workflow_id: UUID,
        phase: WorkflowPhase,
    ) -> tuple[bool, Optional[int]]:
        """Check if phase has exceeded its timeout.

        Args:
            workflow_id: Workflow ID
            phase: Current phase

        Returns:
            Tuple of (is_timed_out, remaining_seconds)
        """
        start_time = self._phase_start_times.get(workflow_id)
        if not start_time:
            return False, None

        timeout = PhaseTimeoutConfig.get_timeout(phase)
        elapsed = (datetime.utcnow() - start_time).total_seconds()
        remaining = int(timeout - elapsed)

        if elapsed > timeout:
            logger.warning(
                f"Phase {phase.value} timed out for workflow {workflow_id}: "
                f"elapsed {elapsed:.1f}s > timeout {timeout}s"
            )
            return True, 0

        return False, remaining

    def clear_phase_timer(self, workflow_id: UUID) -> None:
        """Clear phase timer after completion.

        Args:
            workflow_id: Workflow ID
        """
        self._phase_start_times.pop(workflow_id, None)

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

    async def route_to_agent(
        self,
        target_agent: str,
        workflow_id: UUID,
        task: str,
        context: Optional[dict[str, Any]] = None,
        with_retry: bool = True,
    ) -> None:
        """Route a task to another agent via Dapr pub/sub.

        Args:
            target_agent: Name of the target agent
            workflow_id: Workflow ID
            task: Task description
            context: Additional context
            with_retry: Whether to use retry with exponential backoff
        """
        topic = f"{self.settings.team_name}.{target_agent}.requests"

        # Include trace ID in context for observability propagation
        enriched_context = context.copy() if context else {}
        if self._trace_id:
            enriched_context["langfuse_trace_id"] = self._trace_id

        message = WorkflowMessage(
            source=self.name,
            workflow_id=workflow_id,
            task=task,
            context=enriched_context,
        )

        async def _publish():
            await asyncio.to_thread(
                self.dapr_client.publish_event,
                pubsub_name=self.settings.pubsub_name,
                topic_name=topic,
                data=message.model_dump_json(),
                data_content_type="application/json",
            )
            logger.info(f"Routed task to {target_agent} for workflow {workflow_id}")

        if with_retry:
            await self.retry_with_backoff(
                operation=_publish,
                operation_name=f"route to {target_agent}",
                workflow_id=workflow_id,
            )
        else:
            try:
                await _publish()
            except Exception as e:
                logger.error(f"Failed to route to {target_agent}: {e}")
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
    # Workflow Management
    # =========================================================================

    async def create_workflow(self, feature_description: str) -> Workflow:
        """Create a new workflow instance.

        Args:
            feature_description: The feature to implement

        Returns:
            Created Workflow instance
        """
        workflow = Workflow(
            feature_description=feature_description,
            status=WorkflowStatus.PENDING,
            current_phase=WorkflowPhase.SPECIFICATION,
            current_agent=self.name,
            # Initialize trace_ids with session_id (workflow_id will be available)
            trace_ids=TraceIds(
                langfuse_session_id=None,  # Set after workflow creation
            ),
        )

        # Set session ID to workflow ID after creation
        workflow.trace_ids.langfuse_session_id = str(workflow.id)

        await self.save_workflow_state(workflow)
        logger.info(f"Created workflow: {workflow.id}")

        return workflow

    async def start_workflow(
        self,
        workflow_id: UUID,
        feature_description: str,
    ) -> dict[str, Any]:
        """Start a new workflow by routing to the first agent.

        Args:
            workflow_id: The workflow ID
            feature_description: Feature description to process

        Returns:
            Result indicating workflow started
        """
        # Start phase timer for specification
        self.start_phase_timer(workflow_id, WorkflowPhase.SPECIFICATION)

        # Route to specifier as the first agent
        await self.route_to_agent(
            target_agent="specifier",
            workflow_id=workflow_id,
            task=feature_description,
            context={"source": "orchestrator", "phase": "specification"},
        )

        return {
            "success": True,
            "message": "Workflow started, routed to specifier",
            "current_agent": "specifier",
        }

    async def handle_phase_completion(
        self,
        workflow_id: UUID,
        completed_phase: str,
        result: dict[str, Any],
        trace_id: Optional[str] = None,
    ) -> dict[str, Any]:
        """Handle completion of a workflow phase.

        Args:
            workflow_id: The workflow ID
            completed_phase: The phase that just completed
            result: Result data from the completed phase
            trace_id: Optional trace ID to propagate

        Returns:
            Result with next phase info
        """
        # Preserve trace ID for propagation
        if trace_id:
            self._trace_id = trace_id

        workflow = await self.get_workflow_state(workflow_id)
        if not workflow:
            return {"success": False, "error": "Workflow not found"}

        # Store trace ID in workflow for correlation lookup
        if trace_id and workflow.trace_ids:
            if not workflow.trace_ids.langfuse_trace_id:
                workflow.trace_ids.langfuse_trace_id = trace_id
                await self.save_workflow_state(workflow)

        # Clear phase timer for completed phase
        self.clear_phase_timer(workflow_id)

        # Determine next phase
        next_phase = self._get_next_phase(completed_phase)

        if next_phase is None:
            # Workflow complete
            workflow.status = WorkflowStatus.COMPLETED
            workflow.completed_at = datetime.utcnow()
            await self.save_workflow_state(workflow)

            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.COMPLETED,
                phase=WorkflowPhase.IMPLEMENTATION,
                progress_percent=100,
            )

            return {
                "success": True,
                "message": "Workflow completed",
                "status": "completed",
            }

        # Route to next agent
        next_agent = self._phase_agents.get(next_phase)
        if not next_agent:
            return {"success": False, "error": f"No agent for phase: {next_phase}"}

        # Update workflow state
        workflow.current_phase = next_phase
        workflow.current_agent = next_agent
        await self.save_workflow_state(workflow)

        # Start phase timer for new phase
        self.start_phase_timer(workflow_id, next_phase)

        # Get artifacts from previous phase for context
        artifacts = [a.model_dump() for a in workflow.artifacts]

        # Route to next agent
        await self.route_to_agent(
            target_agent=next_agent,
            workflow_id=workflow_id,
            task=f"Execute {next_phase.value} phase",
            context={
                "source": "orchestrator",
                "phase": next_phase.value,
                "artifacts": artifacts,
                "previous_result": result,
            },
        )

        return {
            "success": True,
            "message": f"Routed to {next_agent}",
            "current_phase": next_phase.value,
            "current_agent": next_agent,
        }

    def _get_next_phase(self, completed_phase: str) -> Optional[WorkflowPhase]:
        """Get the next phase after a completed phase."""
        phase_order = [
            WorkflowPhase.SPECIFICATION,
            WorkflowPhase.PLANNING,
            WorkflowPhase.TASK_GENERATION,
            WorkflowPhase.IMPLEMENTATION,
        ]

        try:
            current = WorkflowPhase(completed_phase)
            current_idx = phase_order.index(current)
            if current_idx + 1 < len(phase_order):
                return phase_order[current_idx + 1]
        except (ValueError, IndexError):
            pass

        return None

    def shutdown(self) -> None:
        """Graceful shutdown."""
        if self._dapr_client:
            try:
                self._dapr_client.close()
            except Exception as e:
                logger.error(f"Error closing Dapr client: {e}")
            self._dapr_client = None


# ============================================================================
# FastAPI Application Factory
# ============================================================================

# Singleton orchestrator instance
_orchestrator: Optional[DaprOrchestrator] = None


def get_orchestrator() -> DaprOrchestrator:
    """Get or create the orchestrator instance."""
    global _orchestrator
    if _orchestrator is None:
        _orchestrator = DaprOrchestrator()
    return _orchestrator


def create_orchestrator_app() -> FastAPI:
    """Create FastAPI app for the orchestrator.

    Returns:
        Configured FastAPI app with workflow endpoints
    """
    app = FastAPI(
        title="SpecKit Orchestrator API",
        version="2.0.0",
        description="""
## SpecKit Multi-Agent Workflow Orchestrator

Pure Dapr-based workflow orchestrator for managing feature implementation pipelines.

### Features

- **Workflow Management**: Create and track feature implementation workflows
- **Multi-Agent Coordination**: Routes work through specialized agents (Specifier → Planner → TaskGenerator → Implementer)
- **Retry Logic**: Exponential backoff for transient failures
- **Phase Timeouts**: Configurable per-phase timeout enforcement
- **Observability**: Full integration with Langfuse and Jaeger tracing

### Workflow Phases

1. **Specification**: Generates feature specifications from descriptions
2. **Planning**: Creates architecture and implementation plans
3. **Task Generation**: Breaks plans into actionable tasks
4. **Implementation**: Executes tasks to produce artifacts

### Observability

All workflow executions are traced in both Langfuse (LLM observability) and Jaeger (distributed tracing).
Use the `trace_ids` field in status responses to correlate across systems.
""",
        openapi_tags=[
            {
                "name": "Workflows",
                "description": "Create and monitor feature implementation workflows",
            },
            {
                "name": "Events",
                "description": "Dapr pub/sub event handlers",
            },
            {
                "name": "Health",
                "description": "Service health and readiness checks",
            },
        ],
        contact={
            "name": "SpecKit Team",
            "url": "https://github.com/PittampalliOrg/stacks",
        },
        license_info={
            "name": "MIT",
            "url": "https://opensource.org/licenses/MIT",
        },
    )

    # Add health endpoints
    app.include_router(health_router)

    # Create orchestrator router
    router = APIRouter(tags=["Workflows"])

    @router.post(
        "/run",
        response_model=WorkflowResponse,
        summary="Start a new workflow",
        response_description="Workflow initiation response with instance ID and status URL",
    )
    async def run_workflow(request: WorkflowRequest) -> WorkflowResponse:
        """Start a new SpecKit feature implementation workflow.

        This endpoint initiates a multi-agent workflow pipeline:
        1. **Specification Phase**: Generates detailed feature specification
        2. **Planning Phase**: Creates architecture and implementation plan
        3. **Task Generation Phase**: Breaks plan into actionable tasks
        4. **Implementation Phase**: Executes tasks to produce code artifacts

        The workflow is processed asynchronously. Use the returned `status_url`
        to poll for progress and results.

        **Example Request:**
        ```json
        {
            "task": "Add a REST API endpoint for user authentication"
        }
        ```

        **Example Response:**
        ```json
        {
            "instance_id": "550e8400-e29b-41d4-a716-446655440000",
            "status": "specifying",
            "status_url": "/status/550e8400-e29b-41d4-a716-446655440000"
        }
        ```
        """
        orchestrator = get_orchestrator()

        try:
            # Create workflow
            workflow = await orchestrator.create_workflow(request.task)

            # Publish initial status
            await orchestrator.publish_status_update(
                workflow_id=workflow.id,
                status=WorkflowStatus.PENDING,
                phase=WorkflowPhase.SPECIFICATION,
                progress_percent=0,
            )

            # Start the workflow
            await orchestrator.start_workflow(
                workflow_id=workflow.id,
                feature_description=request.task,
            )

            return WorkflowResponse(
                instance_id=workflow.id,
                status=WorkflowStatus.SPECIFYING,
                status_url=f"/status/{workflow.id}",
            )

        except Exception as e:
            logger.error(f"Failed to start workflow: {e}")
            raise HTTPException(status_code=500, detail=str(e))

    @router.get(
        "/status/{workflow_id}",
        response_model=WorkflowStatusResponse,
        summary="Get workflow status",
        response_description="Current workflow status including phase, progress, and trace IDs",
    )
    async def get_workflow_status(workflow_id: UUID) -> WorkflowStatusResponse:
        """Get the current status of a workflow.

        Returns comprehensive status information including:
        - **Current Phase**: Which phase (specification/planning/tasks/implementation) is active
        - **Progress**: Percentage completion
        - **Artifacts**: Generated documents/code from completed phases
        - **Trace IDs**: Cross-system observability correlation

        **Trace ID Usage:**
        - `langfuse_trace_id`: Search in Langfuse for LLM conversation details
        - `langfuse_session_id`: Session grouping in Langfuse (equals workflow_id)
        - `jaeger_trace_id`: Search in Jaeger for distributed trace details

        **Example Response:**
        ```json
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "status": "planning",
            "current_phase": "planning",
            "current_agent": "planner",
            "progress_percent": 35,
            "artifacts": [...],
            "trace_ids": {
                "langfuse_trace_id": "trace-abc123",
                "langfuse_session_id": "550e8400-e29b-41d4-a716-446655440000"
            }
        }
        ```
        """
        orchestrator = get_orchestrator()

        workflow = await orchestrator.get_workflow_state(workflow_id)
        if not workflow:
            raise HTTPException(status_code=404, detail="Workflow not found")

        return WorkflowStatusResponse(
            id=workflow.id,
            status=workflow.status,
            current_phase=workflow.current_phase,
            current_agent=workflow.current_agent,
            progress_percent=workflow.progress_percent(),
            artifacts=workflow.artifacts,
            trace_ids=workflow.trace_ids,
            created_at=workflow.created_at,
            updated_at=workflow.updated_at,
            error=workflow.error,
        )

    @router.get("/dapr/subscribe")
    async def dapr_subscribe():
        """Dapr pub/sub subscription endpoint.

        Returns list of topics this service subscribes to.
        """
        settings = get_settings()
        return [
            {
                "pubsubname": settings.pubsub_name,
                "topic": f"{settings.team_name}.orchestrator.requests",
                "route": "/events/phase-complete",
            }
        ]

    @router.post("/events/phase-complete")
    async def handle_phase_complete_event(request: Request):
        """Handle phase completion events from worker agents."""
        orchestrator = get_orchestrator()

        try:
            body = await request.json()
            data = body.get("data", body)

            # Parse the workflow message
            workflow_id = UUID(data.get("workflow_id"))
            task = data.get("task", "")
            context = data.get("context", {})

            # Check if this is a phase completion
            if task.startswith("phase_complete:"):
                completed_phase = task.replace("phase_complete:", "")
                result = context.get("result", {})
                trace_id = context.get("langfuse_trace_id")

                await orchestrator.handle_phase_completion(
                    workflow_id=workflow_id,
                    completed_phase=completed_phase,
                    result=result,
                    trace_id=trace_id,
                )

            return {"success": True}

        except Exception as e:
            logger.error(f"Error handling phase completion: {e}")
            return {"success": False, "error": str(e)}

    app.include_router(router)

    return app
