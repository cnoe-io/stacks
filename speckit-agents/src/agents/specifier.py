"""Specifier agent for generating spec.md from feature descriptions."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter

from src.agents.base import BaseAgent
from src.common.config import Config
from src.common.models import (
    Artifact,
    ArtifactType,
    Workflow,
    WorkflowPhase,
    WorkflowStatus,
)
from src.prompts.specifier import format_spec_prompt, get_system_prompt

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Specifier"])


class SpecifierAgent(BaseAgent):
    """Agent that generates spec.md from natural language feature descriptions.

    The Specifier transforms vague feature requests into structured specifications
    with user stories, acceptance criteria, and clear scope definitions.
    """

    def __init__(self, config: Optional[Config] = None) -> None:
        """Initialize the Specifier agent.

        Args:
            config: Optional configuration override
        """
        super().__init__(
            name="specifier",
            role="Specification Writer",
            goal="Transform natural language feature descriptions into comprehensive, actionable spec.md documents",
            instructions=[
                "Analyze feature descriptions to extract core requirements",
                "Generate user stories with clear acceptance criteria",
                "Define explicit scope boundaries (in/out of scope)",
                "Document assumptions and technical constraints",
                "Ensure all requirements are testable and measurable",
                "Follow the spec.md template format exactly",
            ],
            config=config,
        )
        self._system_prompt = get_system_prompt()

    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process a specification generation task.

        Args:
            workflow_id: The workflow this task belongs to
            task: The feature description to specify
            context: Additional context (may contain hints, constraints)

        Returns:
            Result dict with spec.md content and artifact info
        """
        logger.info(f"Specifier processing task for workflow {workflow_id}")

        # Update workflow status
        await self.publish_status_update(
            workflow_id=workflow_id,
            status=WorkflowStatus.SPECIFYING,
            phase=WorkflowPhase.SPECIFICATION,
            progress_percent=10,
        )

        try:
            # Generate the specification
            spec_content = await self._generate_spec(task, context)

            # Save artifact
            artifact = await self._save_spec_artifact(workflow_id, spec_content)

            # Update workflow with artifact
            workflow = await self.get_workflow_state(workflow_id)
            if workflow:
                workflow.artifacts.append(artifact)
                workflow.status = WorkflowStatus.SPECIFYING
                workflow.current_phase = WorkflowPhase.SPECIFICATION
                await self.save_workflow_state(workflow)

            # Publish success status
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.SPECIFYING,
                phase=WorkflowPhase.SPECIFICATION,
                progress_percent=25,
            )

            logger.info(f"Specifier completed task for workflow {workflow_id}")

            return {
                "success": True,
                "artifact": artifact.model_dump(),
                "spec_content": spec_content,
                "next_agent": "planner",
            }

        except Exception as e:
            logger.error(f"Specifier failed for workflow {workflow_id}: {e}")
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.FAILED,
                phase=WorkflowPhase.SPECIFICATION,
                error=str(e),
            )
            return {
                "success": False,
                "error": str(e),
            }

    async def _generate_spec(
        self,
        feature_description: str,
        context: dict[str, Any],
    ) -> str:
        """Generate spec.md content using LLM.

        Args:
            feature_description: Natural language feature description
            context: Additional context for generation

        Returns:
            Generated spec.md content
        """
        # Format the prompt
        prompt = format_spec_prompt(feature_description)

        # Add any context hints
        if context.get("hints"):
            prompt += f"\n\n## Additional Context\n{context['hints']}"

        # Call Dapr conversation API
        # Note: This uses the Dapr conversation building block
        try:
            response = self.dapr_client.invoke_method(
                app_id=self.config.conversation_component,
                method_name="converse",
                data={
                    "messages": [
                        {"role": "system", "content": self._system_prompt},
                        {"role": "user", "content": prompt},
                    ],
                    "metadata": {
                        "model": "claude-sonnet-4-20250514",
                        "max_tokens": 4000,
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

            return content

        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            # Fallback: Generate a basic template
            return self._generate_fallback_spec(feature_description)

    def _generate_fallback_spec(self, feature_description: str) -> str:
        """Generate a basic spec template when LLM is unavailable.

        Args:
            feature_description: The original feature description

        Returns:
            Basic spec.md template
        """
        return f"""# Feature Specification

**Version**: 1.0
**Created**: {datetime.utcnow().strftime('%Y-%m-%d')}
**Status**: Draft

## Overview

{feature_description}

## User Stories

### US1: Core Feature Implementation

**As a** developer
**I want to** implement the described feature
**So that** users can benefit from the new functionality

**Acceptance Criteria**:
- Feature is implemented as described
- Tests cover the new functionality
- Documentation is updated

**Priority**: P1

## Scope

### In Scope
- Core feature implementation
- Basic testing

### Out of Scope
- Advanced features (future iteration)

## Assumptions
- Standard development environment available
- Dependencies are accessible

## Technical Constraints
- Must follow existing code patterns
- Must maintain backward compatibility

## Non-Functional Requirements
- Performance: Response time under 500ms
- Reliability: 99.9% uptime

## Success Metrics
- Feature is functional
- All tests pass
- No regressions introduced

## Dependencies
- None identified

## Risks
- Scope creep if requirements not clarified
"""

    async def _save_spec_artifact(
        self,
        workflow_id: UUID,
        content: str,
    ) -> Artifact:
        """Save spec.md content as an artifact.

        Args:
            workflow_id: The workflow ID
            content: Spec.md content to save

        Returns:
            Created Artifact record
        """
        import hashlib
        import os

        # Create artifact path
        artifact_path = f"{workflow_id}/spec.md"
        full_path = os.path.join(self.config.artifacts_path, artifact_path)

        # Ensure directory exists
        os.makedirs(os.path.dirname(full_path), exist_ok=True)

        # Write content
        with open(full_path, "w") as f:
            f.write(content)

        # Create artifact record
        content_hash = hashlib.sha256(content.encode()).hexdigest()

        artifact = Artifact(
            workflow_id=workflow_id,
            type=ArtifactType.SPEC,
            path=artifact_path,
            content_hash=content_hash,
            created_by=self.name,
        )

        logger.info(f"Saved spec.md artifact: {artifact_path}")

        return artifact


# Create singleton instance for the router
_agent: Optional[SpecifierAgent] = None


def get_agent() -> SpecifierAgent:
    """Get or create the Specifier agent instance."""
    global _agent
    if _agent is None:
        _agent = SpecifierAgent()
    return _agent
