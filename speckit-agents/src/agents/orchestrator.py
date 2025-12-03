"""Orchestrator agent for managing SpecKit workflows."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter, HTTPException

from src.agents.base import BaseAgent
from src.common.config import Config
from src.common.models import (
    ErrorResponse,
    Workflow,
    WorkflowPhase,
    WorkflowRequest,
    WorkflowResponse,
    WorkflowStatus,
    WorkflowStatusResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Orchestrator"])


class OrchestratorAgent(BaseAgent):
    """Central orchestrator for SpecKit multi-agent workflows.

    The Orchestrator:
    - Receives feature requests via /run endpoint
    - Creates workflow state
    - Routes tasks to specialized agents
    - Tracks workflow progress
    """

    def __init__(self, config: Optional[Config] = None) -> None:
        """Initialize the Orchestrator agent.

        Args:
            config: Optional configuration override
        """
        super().__init__(
            name="orchestrator",
            role="Workflow Coordinator",
            goal="Coordinate the SpecKit multi-agent workflow from feature request to implementation",
            instructions=[
                "Accept feature requests and create workflow instances",
                "Route tasks to appropriate specialized agents",
                "Track workflow state and progress",
                "Handle errors and provide status updates",
                "Ensure orderly progression through workflow phases",
            ],
            config=config,
        )

        # Phase to agent mapping
        self._phase_agents = {
            WorkflowPhase.SPECIFICATION: "specifier",
            WorkflowPhase.PLANNING: "planner",
            WorkflowPhase.TASK_GENERATION: "task-generator",
            WorkflowPhase.IMPLEMENTATION: "implementer",
        }

    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process orchestration tasks (phase transitions, completions).

        Args:
            workflow_id: The workflow ID
            task: Task description (e.g., "phase_complete", "transition")
            context: Context with phase info and results

        Returns:
            Result dict with next steps
        """
        logger.info(f"Orchestrator processing: {task} for workflow {workflow_id}")

        if task == "phase_complete":
            return await self._handle_phase_completion(workflow_id, context)
        elif task == "start_workflow":
            return await self._start_workflow(workflow_id, context)
        else:
            logger.warning(f"Unknown orchestrator task: {task}")
            return {"success": False, "error": f"Unknown task: {task}"}

    async def _start_workflow(
        self,
        workflow_id: UUID,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Start a new workflow by routing to the first agent.

        Args:
            workflow_id: The workflow ID
            context: Context with feature_description

        Returns:
            Result indicating workflow started
        """
        feature_description = context.get("feature_description", "")

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

    async def _handle_phase_completion(
        self,
        workflow_id: UUID,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Handle completion of a workflow phase.

        Args:
            workflow_id: The workflow ID
            context: Context with completed phase and results

        Returns:
            Result with next phase info
        """
        completed_phase = context.get("completed_phase")
        result = context.get("result", {})

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
        """Get the next phase after a completed phase.

        Args:
            completed_phase: The phase that just completed

        Returns:
            Next WorkflowPhase or None if workflow is complete
        """
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

    async def create_workflow(
        self,
        feature_description: str,
    ) -> Workflow:
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


# Create singleton instance
_agent: Optional[OrchestratorAgent] = None


def get_agent() -> OrchestratorAgent:
    """Get or create the Orchestrator agent instance."""
    global _agent
    if _agent is None:
        _agent = OrchestratorAgent()
    return _agent


# FastAPI endpoints


@router.post("/run", response_model=WorkflowResponse)
async def run_workflow(request: WorkflowRequest) -> WorkflowResponse:
    """Start a new SpecKit workflow.

    Accepts a feature description and initiates the multi-agent
    workflow pipeline (specify → plan → tasks → implement).

    Args:
        request: WorkflowRequest with feature description

    Returns:
        WorkflowResponse with workflow ID and status URL
    """
    agent = get_agent()

    try:
        # Create workflow
        workflow = await agent.create_workflow(request.task)

        # Publish initial status
        await agent.publish_status_update(
            workflow_id=workflow.id,
            status=WorkflowStatus.PENDING,
            phase=WorkflowPhase.SPECIFICATION,
            progress_percent=0,
        )

        # Start the workflow
        await agent.process_task(
            workflow_id=workflow.id,
            task="start_workflow",
            context={"feature_description": request.task},
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
    """Get the status of a workflow.

    Args:
        workflow_id: The workflow ID to query

    Returns:
        WorkflowStatusResponse with current status and progress
    """
    agent = get_agent()

    workflow = await agent.get_workflow_state(workflow_id)
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
