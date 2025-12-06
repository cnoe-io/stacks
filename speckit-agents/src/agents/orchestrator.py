"""Orchestrator for managing SpecKit workflows.

The Orchestrator is a pure Dapr router - it does NOT use Claude SDK.
It manages workflow lifecycle using only Dapr pub/sub and state management.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from dapr.clients import DaprClient
from fastapi import APIRouter, FastAPI, HTTPException, Request

from src.common.config import Settings, get_settings
from src.common.health import router as health_router
from src.common.models import (
    Workflow,
    WorkflowMessage,
    WorkflowPhase,
    WorkflowRequest,
    WorkflowResponse,
    WorkflowStatus,
    WorkflowStatusResponse,
)

logger = logging.getLogger(__name__)


class DaprOrchestrator:
    """Pure Dapr orchestrator - no Claude SDK, no LLM calls.

    The Orchestrator:
    - Receives feature requests via /run endpoint
    - Creates workflow state in Dapr state store
    - Routes tasks to specialized agents via Dapr pub/sub
    - Tracks workflow progress
    - Handles phase completion events
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
    ) -> None:
        """Route a task to another agent via Dapr pub/sub.

        Args:
            target_agent: Name of the target agent
            workflow_id: Workflow ID
            task: Task description
            context: Additional context
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

        try:
            await asyncio.to_thread(
                self.dapr_client.publish_event,
                pubsub_name=self.settings.pubsub_name,
                topic_name=topic,
                data=message.model_dump_json(),
                data_content_type="application/json",
            )
            logger.info(f"Routed task to {target_agent} for workflow {workflow_id}")
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
        )

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
        title="SpecKit Orchestrator",
        version="2.0.0",
        description="Pure Dapr workflow orchestrator (no LLM)",
    )

    # Add health endpoints
    app.include_router(health_router)

    # Create orchestrator router
    router = APIRouter(tags=["Orchestrator"])

    @router.post("/run", response_model=WorkflowResponse)
    async def run_workflow(request: WorkflowRequest) -> WorkflowResponse:
        """Start a new SpecKit workflow.

        Accepts a feature description and initiates the multi-agent
        workflow pipeline (specify → plan → tasks → implement).
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

    @router.get("/status/{workflow_id}", response_model=WorkflowStatusResponse)
    async def get_workflow_status(workflow_id: UUID) -> WorkflowStatusResponse:
        """Get the status of a workflow."""
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
