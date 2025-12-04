"""Implementer agent for executing tasks with TDD approach."""

from __future__ import annotations

import logging
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter

from src.agents.base import BaseAgent
from src.common.config import Config
from src.common.models import (
    Artifact,
    ArtifactType,
    WorkflowPhase,
    WorkflowStatus,
)
from src.prompts.implementer import IMPLEMENTER_SYSTEM_PROMPT

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Implementer"])


class ImplementerAgent(BaseAgent):
    """Implements tasks using TDD approach.

    The Implementer:
    - Reads tasks from tasks.md
    - Executes tasks in dependency order
    - Writes tests before implementation
    - Reports completion status
    """

    def __init__(self, config: Optional[Config] = None) -> None:
        """Initialize the Implementer agent.

        Args:
            config: Optional configuration override
        """
        super().__init__(
            name="implementer",
            role="Task Implementer",
            goal="Execute tasks with TDD approach, writing tests before code",
            instructions=[
                "Read and understand task requirements",
                "Identify task dependencies",
                "Write failing tests first",
                "Implement minimum code to pass tests",
                "Refactor for quality",
                "Report completion status",
            ],
            config=config,
        )

    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process an implementation task (T018).

        Args:
            workflow_id: The workflow ID
            task: Task description from orchestrator
            context: Context including artifacts, task info, and langfuse_trace_id

        Returns:
            Result dict with implementation status
        """
        logger.info(f"Implementer processing task for workflow {workflow_id}")

        # Extract trace context from message (T018)
        # This allows LLM calls to be correlated under the parent workflow trace
        trace_id = self.extract_trace_context_from_message(context)
        if not trace_id:
            # Fallback: create new trace if not propagated from orchestrator
            await self.initialize_trace_for_workflow(workflow_id)
        else:
            self._workflow_id = workflow_id

        try:
            # Get artifacts from context
            artifacts = context.get("artifacts", [])

            # Find tasks.md artifact
            tasks_content = None
            spec_content = None
            plan_content = None

            for artifact in artifacts:
                if isinstance(artifact, dict):
                    artifact_type = artifact.get("type")
                    content = artifact.get("content", "")
                else:
                    artifact_type = getattr(artifact, "type", None)
                    content = getattr(artifact, "content", "")

                if artifact_type == ArtifactType.TASKS or artifact_type == "tasks":
                    tasks_content = content
                elif artifact_type == ArtifactType.SPEC or artifact_type == "spec":
                    spec_content = content
                elif artifact_type == ArtifactType.PLAN or artifact_type == "plan":
                    plan_content = content

            if not tasks_content:
                return {
                    "success": False,
                    "error": "No tasks.md artifact found",
                }

            # Parse tasks from tasks.md
            tasks = self._parse_tasks(tasks_content)

            if not tasks:
                return {
                    "success": False,
                    "error": "No tasks found in tasks.md",
                }

            # Execute tasks in order
            completed_tasks = []
            for task_item in tasks:
                result = await self._execute_task(
                    workflow_id=workflow_id,
                    task_item=task_item,
                    spec_content=spec_content,
                    plan_content=plan_content,
                )
                completed_tasks.append(result)

                if not result.get("success", False):
                    logger.warning(f"Task {task_item.get('id')} failed: {result.get('error')}")

            # Generate implementation report
            report = self._generate_implementation_report(completed_tasks)

            # Store as artifact
            artifact = Artifact(
                workflow_id=workflow_id,
                type=ArtifactType.IMPLEMENTATION,
                path="implementation-report.md",
                created_by=self.name,
            )

            # Update workflow with artifact
            workflow = await self.get_workflow_state(workflow_id)
            if workflow:
                workflow.artifacts.append(artifact)
                workflow.status = WorkflowStatus.COMPLETED
                await self.save_workflow_state(workflow)

            # Publish status update
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.COMPLETED,
                phase=WorkflowPhase.IMPLEMENTATION,
                progress_percent=100,
            )

            # Notify orchestrator of completion
            await self.route_to_agent(
                target_agent="orchestrator",
                workflow_id=workflow_id,
                task="phase_complete",
                context={
                    "completed_phase": WorkflowPhase.IMPLEMENTATION.value,
                    "result": {
                        "tasks_completed": len([t for t in completed_tasks if t.get("success")]),
                        "tasks_failed": len([t for t in completed_tasks if not t.get("success")]),
                        "report": report,
                    },
                },
            )

            return {
                "success": True,
                "tasks_completed": len([t for t in completed_tasks if t.get("success")]),
                "tasks_failed": len([t for t in completed_tasks if not t.get("success")]),
            }

        except Exception as e:
            logger.error(f"Implementation failed: {e}")
            return {"success": False, "error": str(e)}

    def _parse_tasks(self, tasks_content: str) -> list[dict[str, Any]]:
        """Parse tasks from tasks.md content.

        Args:
            tasks_content: Content of tasks.md

        Returns:
            List of task dictionaries
        """
        tasks = []
        current_task = None
        current_section = None

        for line in tasks_content.split("\n"):
            line = line.strip()

            # Task header: ### T001: Task Title
            if line.startswith("### T") and ":" in line:
                if current_task:
                    tasks.append(current_task)

                parts = line[4:].split(":", 1)
                task_id = parts[0].strip()
                task_title = parts[1].strip() if len(parts) > 1 else ""

                current_task = {
                    "id": task_id,
                    "title": task_title,
                    "description": "",
                    "acceptance_criteria": [],
                    "dependencies": [],
                }
                current_section = None

            elif current_task:
                # Section headers
                if line.startswith("**Description:**"):
                    current_section = "description"
                elif line.startswith("**Acceptance Criteria:**"):
                    current_section = "acceptance_criteria"
                elif line.startswith("**Dependencies:**"):
                    current_section = "dependencies"
                elif line.startswith("**"):
                    current_section = None
                # Content
                elif current_section == "description" and line:
                    current_task["description"] += line + " "
                elif current_section == "acceptance_criteria" and line.startswith("- "):
                    current_task["acceptance_criteria"].append(line[2:])
                elif current_section == "dependencies" and line.startswith("- "):
                    current_task["dependencies"].append(line[2:])

        if current_task:
            tasks.append(current_task)

        return tasks

    async def _execute_task(
        self,
        workflow_id: UUID,
        task_item: dict[str, Any],
        spec_content: Optional[str],
        plan_content: Optional[str],
    ) -> dict[str, Any]:
        """Execute a single task.

        Args:
            workflow_id: The workflow ID
            task_item: Task dictionary
            spec_content: Content of spec.md
            plan_content: Content of plan.md

        Returns:
            Result dict with execution status
        """
        task_id = task_item.get("id", "unknown")
        logger.info(f"Executing task: {task_id}")

        try:
            # For now, simulate task execution
            # In a real implementation, this would:
            # 1. Generate test code using LLM
            # 2. Generate implementation code
            # 3. Run tests
            # 4. Report results

            # Placeholder for LLM-based implementation
            return {
                "success": True,
                "task_id": task_id,
                "status": "completed",
                "notes": "Task executed successfully (placeholder)",
            }

        except Exception as e:
            logger.error(f"Task {task_id} execution failed: {e}")
            return {
                "success": False,
                "task_id": task_id,
                "error": str(e),
            }

    def _generate_implementation_report(
        self,
        completed_tasks: list[dict[str, Any]],
    ) -> str:
        """Generate implementation report.

        Args:
            completed_tasks: List of completed task results

        Returns:
            Markdown report content
        """
        successful = [t for t in completed_tasks if t.get("success")]
        failed = [t for t in completed_tasks if not t.get("success")]

        report = """# Implementation Report

## Summary
- **Total Tasks:** {total}
- **Completed:** {completed}
- **Failed:** {failed}

## Completed Tasks
{completed_list}

## Failed Tasks
{failed_list}

## Next Steps
{next_steps}
""".format(
            total=len(completed_tasks),
            completed=len(successful),
            failed=len(failed),
            completed_list="\n".join(
                f"- {t.get('task_id')}: {t.get('notes', 'Completed')}"
                for t in successful
            ) or "- None",
            failed_list="\n".join(
                f"- {t.get('task_id')}: {t.get('error', 'Unknown error')}"
                for t in failed
            ) or "- None",
            next_steps="Review implementation and run integration tests."
            if not failed
            else "Address failed tasks before proceeding.",
        )

        return report


# Create singleton instance
_agent: Optional[ImplementerAgent] = None


def get_agent() -> ImplementerAgent:
    """Get or create the Implementer agent instance."""
    global _agent
    if _agent is None:
        _agent = ImplementerAgent()
    return _agent


# FastAPI endpoints

@router.post("/execute")
async def execute_task(task_id: str, workflow_id: UUID) -> dict[str, Any]:
    """Execute a specific task.

    Args:
        task_id: The task ID to execute
        workflow_id: The workflow ID

    Returns:
        Execution result
    """
    agent = get_agent()

    # Get workflow state
    workflow = await agent.get_workflow_state(workflow_id)
    if not workflow:
        return {"success": False, "error": "Workflow not found"}

    # Find and execute the task
    return await agent._execute_task(
        workflow_id=workflow_id,
        task_item={"id": task_id},
        spec_content=None,
        plan_content=None,
    )
