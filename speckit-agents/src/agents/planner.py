"""Planner agent for generating plan.md, research.md, and data-model.md."""

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
from src.prompts.planner import (
    format_plan_prompt,
    get_system_prompt,
    parse_plan_response,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Planner"])


class PlannerAgent(BaseAgent):
    """Agent that generates planning artifacts from specifications.

    The Planner takes spec.md and produces:
    - plan.md: Implementation approach and architecture
    - research.md: Technology decisions and rationale
    - data-model.md: Entity definitions and relationships
    """

    def __init__(self, config: Optional[Config] = None) -> None:
        """Initialize the Planner agent.

        Args:
            config: Optional configuration override
        """
        super().__init__(
            name="planner",
            role="Implementation Planner",
            goal="Transform specifications into comprehensive implementation plans with architecture, research, and data models",
            instructions=[
                "Analyze spec.md to understand all requirements",
                "Design a high-level architecture that addresses all user stories",
                "Research and justify technology choices",
                "Define clear data models with relationships",
                "Create an implementation roadmap in dependency order",
                "Identify risks and propose mitigations",
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
        """Process a planning task (T018).

        Args:
            workflow_id: The workflow this task belongs to
            task: Task description
            context: Context with spec.md content, previous artifacts, and langfuse_trace_id

        Returns:
            Result dict with generated artifacts
        """
        logger.info(f"Planner processing task for workflow {workflow_id}")

        # Extract trace context from message (T018)
        # This allows LLM calls to be correlated under the parent workflow trace
        trace_id = self.extract_trace_context_from_message(context)
        if not trace_id:
            # Fallback: create new trace if not propagated from orchestrator
            await self.initialize_trace_for_workflow(workflow_id)
        else:
            self._workflow_id = workflow_id

        # Update workflow status
        await self.publish_status_update(
            workflow_id=workflow_id,
            status=WorkflowStatus.PLANNING,
            phase=WorkflowPhase.PLANNING,
            progress_percent=30,
        )

        try:
            # Get spec.md content
            spec_content = await self._get_spec_content(workflow_id, context)
            if not spec_content:
                raise ValueError("spec.md not found for workflow")

            # Generate planning artifacts
            artifacts = await self._generate_plan_artifacts(workflow_id, spec_content)

            # Update workflow with artifacts
            workflow = await self.get_workflow_state(workflow_id)
            if workflow:
                workflow.artifacts.extend(artifacts)
                workflow.status = WorkflowStatus.PLANNING
                workflow.current_phase = WorkflowPhase.PLANNING
                await self.save_workflow_state(workflow)

            # Publish success status
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.PLANNING,
                phase=WorkflowPhase.PLANNING,
                progress_percent=50,
            )

            logger.info(f"Planner completed task for workflow {workflow_id}")

            return {
                "success": True,
                "artifacts": [a.model_dump() for a in artifacts],
                "next_agent": "task-generator",
            }

        except Exception as e:
            logger.error(f"Planner failed for workflow {workflow_id}: {e}")
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.FAILED,
                phase=WorkflowPhase.PLANNING,
                error=str(e),
            )
            return {
                "success": False,
                "error": str(e),
            }

    async def _get_spec_content(
        self,
        workflow_id: UUID,
        context: dict[str, Any],
    ) -> Optional[str]:
        """Get spec.md content from storage or context.

        Args:
            workflow_id: The workflow ID
            context: Context that may contain spec content

        Returns:
            Spec.md content or None
        """
        # Try to read from storage first
        content = await self._storage.read_by_type(workflow_id, ArtifactType.SPEC)
        if content:
            return content

        # Fall back to context
        return context.get("spec_content")

    async def _generate_plan_artifacts(
        self,
        workflow_id: UUID,
        spec_content: str,
    ) -> list[Artifact]:
        """Generate all planning artifacts using LLM with Langfuse tracing (T011).

        Args:
            workflow_id: The workflow ID
            spec_content: Content of spec.md

        Returns:
            List of created Artifact records
        """
        start_time = time.time()

        # Format the prompt
        prompt = format_plan_prompt(spec_content)

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
                        "max_tokens": 8000,
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

            # Log to Langfuse (T011) - graceful degradation if trace_id not set (T015)
            if self._trace_id:
                create_generation(
                    trace_id=self._trace_id,
                    name="generate_plan",
                    model=model,
                    input_messages=messages,
                    output=content,
                    usage=usage,
                    metadata={
                        "agent": self.name,
                        "latency_ms": int((time.time() - start_time) * 1000),
                    },
                )

            # Parse into separate artifacts
            artifact_contents = parse_plan_response(content)

        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            # Log error to Langfuse (T014)
            if self._trace_id:
                create_generation(
                    trace_id=self._trace_id,
                    name="generate_plan",
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
            # Fallback to basic templates
            artifact_contents = self._generate_fallback_artifacts(spec_content)

        # Save all artifacts
        artifacts = []

        # Plan.md
        if "plan.md" in artifact_contents:
            artifact = await self._storage.save(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.PLAN,
                content=artifact_contents["plan.md"],
                created_by=self.name,
            )
            artifacts.append(artifact)

        # Research.md
        if "research.md" in artifact_contents:
            artifact = await self._storage.save(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.RESEARCH,
                content=artifact_contents["research.md"],
                created_by=self.name,
            )
            artifacts.append(artifact)

        # Data-model.md
        if "data-model.md" in artifact_contents:
            artifact = await self._storage.save(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.DATA_MODEL,
                content=artifact_contents["data-model.md"],
                created_by=self.name,
            )
            artifacts.append(artifact)

        return artifacts

    def _generate_fallback_artifacts(
        self,
        spec_content: str,
    ) -> dict[str, str]:
        """Generate basic artifacts when LLM is unavailable.

        Args:
            spec_content: The spec.md content

        Returns:
            Dict of artifact names to content
        """
        date = datetime.utcnow().strftime("%Y-%m-%d")

        plan = f"""# Implementation Plan

**Version**: 1.0
**Created**: {date}
**Based On**: spec.md v1.0

## Architecture Overview

Based on the provided specification, this plan outlines the implementation approach.

## Technology Stack

- Python 3.11+
- FastAPI for HTTP endpoints
- Pydantic for data validation

## Implementation Approach

1. Set up project structure
2. Implement core models
3. Build API endpoints
4. Add integration tests
5. Deploy and validate

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Scope creep | Strict adherence to spec |
| Technical debt | Regular refactoring |
"""

        research = f"""# Research

**Version**: 1.0
**Created**: {date}

## Executive Summary

This document captures technology decisions for the feature implementation.

## Technology Decisions

### Language: Python 3.11+
- Strong typing with type hints
- Async/await for concurrent operations
- Mature ecosystem

### Framework: FastAPI
- High performance
- Automatic OpenAPI documentation
- Native async support

## Recommendations

- Follow existing code patterns
- Prioritize testability
- Document architectural decisions
"""

        data_model = f"""# Data Model

**Version**: 1.0
**Created**: {date}

## Overview

Entity definitions for the feature implementation.

## Entity Definitions

Entities will be defined based on the specification requirements.

## Relationships

Relationships will be documented as entities are defined.

## Validation Rules

- All required fields must be present
- IDs must be valid UUIDs
- Timestamps must be ISO 8601 format
"""

        return {
            "plan.md": plan,
            "research.md": research,
            "data-model.md": data_model,
        }


# Create singleton instance
_agent: Optional[PlannerAgent] = None


def get_agent() -> PlannerAgent:
    """Get or create the Planner agent instance."""
    global _agent
    if _agent is None:
        _agent = PlannerAgent()
    return _agent
