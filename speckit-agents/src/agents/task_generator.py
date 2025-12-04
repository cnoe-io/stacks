"""Task Generator agent for creating tasks.md from planning artifacts."""

from __future__ import annotations

import logging
import time
from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter

from src.agents.base import BaseAgent
from src.common.artifacts import get_artifact_storage
from src.common.config import Config
from src.common.models import (
    Artifact,
    ArtifactType,
    WorkflowPhase,
    WorkflowStatus,
)
from src.common.observability import create_generation
from src.prompts.task_generator import (
    format_tasks_prompt,
    get_system_prompt,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["TaskGenerator"])


class TaskGeneratorAgent(BaseAgent):
    """Agent that generates tasks.md from planning artifacts.

    The Task Generator converts plan.md into a structured, dependency-ordered
    task list that developers can execute to implement the feature.
    """

    def __init__(self, config: Optional[Config] = None) -> None:
        """Initialize the Task Generator agent.

        Args:
            config: Optional configuration override
        """
        super().__init__(
            name="task-generator",
            role="Task Breakdown Specialist",
            goal="Convert implementation plans into actionable, dependency-ordered task lists",
            instructions=[
                "Analyze plan.md to identify all required work items",
                "Order tasks by dependencies so they can be executed sequentially",
                "Mark parallel-safe tasks with [P] indicator",
                "Tag tasks with user story references for traceability",
                "Include specific file paths for each task",
                "Group tasks into logical phases (Setup, Core, Tests, etc.)",
            ],
            config=config,
        )
        self._system_prompt = get_system_prompt()
        self._storage = get_artifact_storage()

    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process a task generation request (T018).

        Args:
            workflow_id: The workflow this task belongs to
            task: Task description
            context: Context with plan artifacts and langfuse_trace_id

        Returns:
            Result dict with generated tasks.md
        """
        logger.info(f"TaskGenerator processing task for workflow {workflow_id}")

        # Extract trace context from message (T018)
        # This allows LLM calls to be correlated under the parent workflow trace
        # Also sets session_id for Langfuse trace grouping by workflow
        trace_id = self.extract_trace_context_from_message(context, workflow_id)
        if not trace_id:
            # Fallback: create new trace if not propagated from orchestrator
            await self.initialize_trace_for_workflow(workflow_id)

        # Update workflow status
        await self.publish_status_update(
            workflow_id=workflow_id,
            status=WorkflowStatus.TASK_GENERATING,
            phase=WorkflowPhase.TASK_GENERATION,
            progress_percent=55,
        )

        try:
            # Get plan.md content
            plan_content = await self._get_plan_content(workflow_id, context)
            if not plan_content:
                raise ValueError("plan.md not found for workflow")

            # Get spec summary for context
            spec_content = await self._storage.read_by_type(
                workflow_id, ArtifactType.SPEC
            )
            spec_summary = self._extract_spec_summary(spec_content) if spec_content else ""

            # Generate tasks.md
            tasks_content = await self._generate_tasks(
                workflow_id, plan_content, spec_summary
            )

            # Save artifact
            artifact = await self._storage.save(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.TASKS,
                content=tasks_content,
                created_by=self.name,
            )

            # Update workflow with artifact
            workflow = await self.get_workflow_state(workflow_id)
            if workflow:
                workflow.artifacts.append(artifact)
                workflow.status = WorkflowStatus.TASK_GENERATING
                workflow.current_phase = WorkflowPhase.TASK_GENERATION
                await self.save_workflow_state(workflow)

            # Publish success status
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.TASK_GENERATING,
                phase=WorkflowPhase.TASK_GENERATION,
                progress_percent=75,
            )

            logger.info(f"TaskGenerator completed task for workflow {workflow_id}")

            return {
                "success": True,
                "artifact": artifact.model_dump(),
                "tasks_content": tasks_content,
                "next_agent": "implementer",
            }

        except Exception as e:
            logger.error(f"TaskGenerator failed for workflow {workflow_id}: {e}")
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.FAILED,
                phase=WorkflowPhase.TASK_GENERATION,
                error=str(e),
            )
            return {
                "success": False,
                "error": str(e),
            }

    async def _get_plan_content(
        self,
        workflow_id: UUID,
        context: dict[str, Any],
    ) -> Optional[str]:
        """Get plan.md content from storage or context.

        Args:
            workflow_id: The workflow ID
            context: Context that may contain plan content

        Returns:
            Plan.md content or None
        """
        # Try to read from storage first
        content = await self._storage.read_by_type(workflow_id, ArtifactType.PLAN)
        if content:
            return content

        # Fall back to context
        return context.get("plan_content")

    def _extract_spec_summary(self, spec_content: str) -> str:
        """Extract a summary from spec.md for context.

        Args:
            spec_content: Full spec.md content

        Returns:
            Summary string
        """
        # Extract Overview section if present
        lines = spec_content.split("\n")
        in_overview = False
        overview_lines = []

        for line in lines:
            if line.strip().lower().startswith("## overview"):
                in_overview = True
                continue
            if in_overview:
                if line.strip().startswith("##"):
                    break
                overview_lines.append(line)

        if overview_lines:
            return "\n".join(overview_lines).strip()

        # Fallback: first 500 chars
        return spec_content[:500] + "..."

    async def _generate_tasks(
        self,
        workflow_id: UUID,
        plan_content: str,
        spec_summary: str,
    ) -> str:
        """Generate tasks.md content using LLM with Langfuse tracing (T012).

        Args:
            workflow_id: The workflow ID
            plan_content: Content of plan.md
            spec_summary: Summary from spec.md

        Returns:
            Generated tasks.md content
        """
        start_time = time.time()

        # Format the prompt
        prompt = format_tasks_prompt(plan_content, spec_summary)

        # Build messages for LLM call
        messages = [
            {"role": "system", "content": self._system_prompt},
            {"role": "user", "content": prompt},
        ]
        model = "claude-sonnet-4-20250514"

        # Call Dapr conversation API
        try:
            response = self.dapr_client.invoke_method(
                app_id=self.config.conversation_component,
                method_name="converse",
                data={
                    "messages": messages,
                    "metadata": {
                        "model": model,
                        "max_tokens": 6000,
                    },
                },
                http_verb="POST",
            )

            # Extract content from response
            if hasattr(response, "json"):
                result = response.json()
            else:
                result = response

            content = result.get("content", "")
            if isinstance(content, list) and content:
                content = content[0].get("text", "")

            # Extract usage if available
            usage = result.get("usage")

            # Log to Langfuse (T012) - graceful degradation if trace_id not set (T015)
            if self._trace_id:
                create_generation(
                    trace_id=self._trace_id,
                    name="generate_tasks",
                    model=model,
                    input_messages=messages,
                    output=content,
                    usage=usage,
                    metadata={
                        "agent": self.name,
                        "latency_ms": int((time.time() - start_time) * 1000),
                    },
                )

            return content

        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            # Log error to Langfuse (T014)
            if self._trace_id:
                create_generation(
                    trace_id=self._trace_id,
                    name="generate_tasks",
                    model=model,
                    input_messages=messages,
                    output=None,
                    metadata={
                        "agent": self.name,
                        "error": str(e),
                        "error_type": type(e).__name__,
                        "latency_ms": int((time.time() - start_time) * 1000),
                    },
                )
            # Fallback to basic template
            return self._generate_fallback_tasks(plan_content)

    def _generate_fallback_tasks(self, plan_content: str) -> str:
        """Generate basic tasks when LLM is unavailable.

        Args:
            plan_content: The plan.md content

        Returns:
            Basic tasks.md template
        """
        date = datetime.utcnow().strftime("%Y-%m-%d")

        return f"""# Tasks: Feature Implementation

**Generated**: {date}
**Based On**: plan.md

**Organization**: Tasks grouped by phase for systematic implementation.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel
- **[Story]**: User story reference

---

## Phase 1: Setup

- [ ] T001 [US1] Set up project structure
- [ ] T002 [P] [US1] Create configuration files
- [ ] T003 [P] [US1] Add dependencies

---

## Phase 2: Core Implementation

- [ ] T004 [US1] Implement core models
- [ ] T005 [US1] Implement business logic
- [ ] T006 [US2] Add API endpoints

---

## Phase 3: Testing

- [ ] T007 [P] [US1] Add unit tests for models
- [ ] T008 [P] [US2] Add API integration tests

---

## Phase 4: Polish

- [ ] T009 [US1] Add error handling
- [ ] T010 [US1] Add documentation

---

## Dependencies

- T004 depends on T001-T003
- T005 depends on T004
- T006 depends on T005
- T007-T008 depend on T004-T006
- T009-T010 depend on T007-T008

---

## Notes

- Tasks marked [P] can run in parallel
- Complete each phase before moving to the next
- Commit after each task or logical group

---

## Summary

| Phase | Description | Task Count |
|-------|-------------|------------|
| Setup | Project structure | 3 |
| Core | Implementation | 3 |
| Testing | Unit and integration | 2 |
| Polish | Error handling, docs | 2 |
| **Total** | | **10** |
"""


# Create singleton instance
_agent: Optional[TaskGeneratorAgent] = None


def get_agent() -> TaskGeneratorAgent:
    """Get or create the Task Generator agent instance."""
    global _agent
    if _agent is None:
        _agent = TaskGeneratorAgent()
    return _agent
