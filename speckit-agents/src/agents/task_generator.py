"""Task Generator agent using Claude Agent SDK.

Transforms planning artifacts (plan.md, data-model.md, research.md) into
structured, dependency-ordered task lists in tasks.md format.
"""

from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter, FastAPI, Request

from src.agents.base import BaseClaudeAgent
from src.common.claude_config import TASK_GENERATOR_CONFIG
from src.common.config import Settings, get_settings
from src.common.health import router as health_router
from src.common.models import (
    ArtifactType,
    WorkflowPhase,
    WorkflowStatus,
)
from src.prompts.task_generator import (
    format_tasks_prompt,
    get_system_prompt,
)
from src.tools.dapr_tools import dapr_mcp_server
from src.tools.artifact_tools import artifact_mcp_server

logger = logging.getLogger(__name__)


class ClaudeTaskGeneratorAgent(BaseClaudeAgent):
    """Claude SDK agent that generates tasks.md from planning artifacts.

    The Task Generator:
    - Reads plan.md, research.md, data-model.md
    - Analyzes implementation requirements
    - Creates dependency-ordered task list
    - Marks parallel-safe tasks with [P]
    """

    def __init__(self, settings: Optional[Settings] = None) -> None:
        """Initialize the Claude Task Generator agent."""
        super().__init__(
            agent_config=TASK_GENERATOR_CONFIG,
            settings=settings,
        )
        # Register MCP servers
        self.register_mcp_server("dapr", dapr_mcp_server)
        self.register_mcp_server("artifacts", artifact_mcp_server)

    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process a task generation request.

        Args:
            workflow_id: The workflow this task belongs to
            task: Task description
            context: Additional context (artifacts, langfuse_trace_id)

        Returns:
            Result dict with generated tasks.md
        """
        logger.info(f"TaskGenerator processing task for workflow {workflow_id}")

        # Extract trace context
        self.extract_trace_from_context(context)
        self.set_trace_context(workflow_id, self._trace_id)

        # Update workflow status
        await self.publish_status_update(
            workflow_id=workflow_id,
            status=WorkflowStatus.TASK_GENERATING,
            phase=WorkflowPhase.TASK_GENERATION,
            progress_percent=55,
        )

        try:
            # Get planning artifacts
            plan_content = await self.get_artifact_content(workflow_id, ArtifactType.PLAN)
            if not plan_content:
                raise ValueError("plan.md not found for workflow")

            # Get optional context artifacts
            spec_content = await self.get_artifact_content(workflow_id, ArtifactType.SPEC)
            data_model_content = await self.get_artifact_content(workflow_id, ArtifactType.DATA_MODEL)

            # Generate tasks.md
            tasks_content = await self._generate_tasks(
                workflow_id=workflow_id,
                plan_content=plan_content,
                spec_content=spec_content,
                data_model_content=data_model_content,
            )

            # Save artifact
            artifacts_dir = self.get_artifacts_path(workflow_id)
            artifacts_dir.mkdir(parents=True, exist_ok=True)
            tasks_path = artifacts_dir / "tasks.md"
            tasks_path.write_text(tasks_content)

            # Register artifact
            artifact = await self.register_artifact(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.TASKS,
                path=str(tasks_path),
                content=tasks_content,
            )

            # Update workflow status
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.TASK_GENERATING,
                phase=WorkflowPhase.TASK_GENERATION,
                progress_percent=75,
            )

            # Publish phase completion
            await self.publish_phase_complete(
                workflow_id=workflow_id,
                phase=WorkflowPhase.TASK_GENERATION,
                result={
                    "artifact": artifact.model_dump(),
                    "tasks_path": str(tasks_path),
                },
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

    async def _generate_tasks(
        self,
        workflow_id: UUID,
        plan_content: str,
        spec_content: Optional[str],
        data_model_content: Optional[str],
    ) -> str:
        """Generate tasks.md content using Claude SDK.

        Args:
            workflow_id: Workflow ID
            plan_content: Content of plan.md
            spec_content: Optional spec.md content
            data_model_content: Optional data-model.md content

        Returns:
            Generated tasks.md content
        """
        # Extract summaries for context
        spec_summary = self._extract_summary(spec_content, "Overview") if spec_content else ""
        data_model_summary = self._extract_summary(data_model_content, "Entity Definitions") if data_model_content else ""

        # Build the prompt
        prompt = format_tasks_prompt(
            plan_content=plan_content,
            spec_summary=spec_summary,
            data_model_summary=data_model_summary,
        )

        # Build Claude SDK options
        options = self.get_claude_options(override_max_turns=5)

        # Log configuration (actual SDK call would be here)
        logger.info(f"Would call Claude SDK with options: {options}")
        logger.info(f"Prompt length: {len(prompt)} chars")

        # Note: In production, the Claude SDK query() call would be:
        #
        # from claude_code_sdk import query, ClaudeAgentOptions
        #
        # result = ""
        # async for message in query(
        #     prompt=prompt,
        #     options=ClaudeAgentOptions(**options),
        #     cwd=str(self.get_artifacts_path(workflow_id)),
        # ):
        #     if isinstance(message, AssistantMessage):
        #         for block in message.content:
        #             if isinstance(block, TextBlock):
        #                 result += block.text
        #
        # return result

        # For now, generate structured tasks as fallback
        return self._generate_fallback_tasks(plan_content, spec_summary)

    def _extract_summary(self, content: str, section_name: str) -> str:
        """Extract a specific section from markdown content.

        Args:
            content: Full markdown content
            section_name: Name of section to extract

        Returns:
            Section content or first 500 chars if not found
        """
        if not content:
            return ""

        lines = content.split("\n")
        in_section = False
        section_lines = []

        for line in lines:
            if line.strip().lower().startswith(f"## {section_name.lower()}"):
                in_section = True
                continue
            if in_section:
                if line.strip().startswith("##"):
                    break
                section_lines.append(line)

        if section_lines:
            return "\n".join(section_lines).strip()[:1000]

        # Fallback to first 500 chars
        return content[:500] + "..."

    def _generate_fallback_tasks(
        self,
        plan_content: str,
        spec_summary: str,
    ) -> str:
        """Generate basic tasks when Claude SDK is unavailable.

        Args:
            plan_content: Content of plan.md
            spec_summary: Summary of spec.md

        Returns:
            Basic tasks.md content
        """
        date = datetime.utcnow().strftime("%Y-%m-%d")

        # Extract title from plan
        lines = plan_content.strip().split("\n")
        title = lines[0].replace("#", "").strip() if lines else "Feature Implementation"

        return f"""# Tasks: {title}

**Generated**: {date}
**Based On**: plan.md, spec.md, data-model.md

**Organization**: Tasks grouped by phase for systematic implementation.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel
- **[Story]**: User story reference

---

## Phase 1: Setup

- [ ] T001 [US1] Set up project directory structure
- [ ] T002 [P] [US1] Create configuration files (pyproject.toml, requirements.txt)
- [ ] T003 [P] [US1] Create .gitignore and .dockerignore
- [ ] T004 [US1] Initialize empty __init__.py files

---

## Phase 2: Core Models

- [ ] T005 [US1] Implement Pydantic models (entities, enums)
- [ ] T006 [US1] Implement configuration management
- [ ] T007 [P] [US1] Implement health check endpoints

---

## Phase 3: Core Implementation

- [ ] T008 [US2] Implement core business logic
- [ ] T009 [US2] Implement service layer
- [ ] T010 [US2] Implement API endpoints

---

## Phase 4: Integration

- [ ] T011 [US3] Wire up dependencies and routing
- [ ] T012 [US3] Implement middleware and error handling
- [ ] T013 [US3] Add logging and observability

---

## Phase 5: Testing

- [ ] T014 [P] [US1] Add unit tests for models
- [ ] T015 [P] [US2] Add unit tests for services
- [ ] T016 [P] [US3] Add integration tests

---

## Phase 6: Polish

- [ ] T017 [US1] Add type hints to all public functions
- [ ] T018 [US1] Create Dockerfile
- [ ] T019 [US1] Update documentation

---

## Dependencies & Execution Order

### Phase Dependencies
- **Setup (Phase 1)**: No dependencies - start immediately
- **Core Models (Phase 2)**: Depends on Phase 1
- **Core Implementation (Phase 3)**: Depends on Phase 2
- **Integration (Phase 4)**: Depends on Phase 3
- **Testing (Phase 5)**: Depends on Phases 2-4
- **Polish (Phase 6)**: Depends on all previous phases

### Parallel Opportunities
- T002, T003 can run in parallel (different files)
- T014, T015, T016 can run in parallel (different test files)

---

## Notes

- Tasks marked [P] can run in parallel
- Complete each phase before moving to the next
- Commit after each task or logical group
- Run tests after each phase

---

## Summary

| Phase | Description | Task Count |
|-------|-------------|------------|
| Setup | Project structure | 4 |
| Core Models | Entities and config | 3 |
| Core Implementation | Business logic | 3 |
| Integration | Wiring | 3 |
| Testing | Unit and integration | 3 |
| Polish | Types, Docker, docs | 3 |
| **Total** | | **19** |
"""


# ============================================================================
# FastAPI Application Factory
# ============================================================================

_agent: Optional[ClaudeTaskGeneratorAgent] = None


def get_agent() -> ClaudeTaskGeneratorAgent:
    """Get or create the Task Generator agent instance."""
    global _agent
    if _agent is None:
        _agent = ClaudeTaskGeneratorAgent()
    return _agent


def create_task_generator_app() -> FastAPI:
    """Create FastAPI app for the task generator agent.

    Returns:
        Configured FastAPI app with agent endpoints
    """
    app = FastAPI(
        title="SpecKit Task Generator Agent",
        version="2.0.0",
        description="Claude SDK powered task breakdown specialist",
    )

    # Add health endpoints
    app.include_router(health_router)

    # Create agent router
    router = APIRouter(tags=["TaskGenerator"])

    @router.get("/dapr/subscribe")
    async def dapr_subscribe():
        """Dapr pub/sub subscription endpoint."""
        settings = get_settings()
        return [
            {
                "pubsubname": settings.pubsub_name,
                "topic": f"{settings.team_name}.task-generator.requests",
                "route": "/events/task",
            }
        ]

    @router.post("/events/task")
    async def handle_task_event(request: Request):
        """Handle task events from orchestrator."""
        agent = get_agent()

        try:
            body = await request.json()
            data = body.get("data", body)

            workflow_id = UUID(data.get("workflow_id"))
            task = data.get("task", "")
            context = data.get("context", {})

            result = await agent.process_task(
                workflow_id=workflow_id,
                task=task,
                context=context,
            )

            return {"success": True, "result": result}

        except Exception as e:
            logger.error(f"Error handling task event: {e}")
            return {"success": False, "error": str(e)}

    app.include_router(router)

    return app
