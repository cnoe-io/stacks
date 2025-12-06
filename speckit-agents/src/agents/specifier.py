"""Specifier agent using Claude Agent SDK.

Transforms natural language feature descriptions into structured spec.md documents.
This is the first agent in the workflow pipeline (MVP).
"""

from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter, FastAPI, Request

from src.agents.base import BaseClaudeAgent
from src.common.claude_config import SPECIFIER_CONFIG
from src.common.config import Settings, get_settings
from src.common.health import router as health_router
from src.common.models import (
    ArtifactType,
    WorkflowPhase,
    WorkflowStatus,
)
from src.prompts.specifier import SPECIFIER_SYSTEM_PROMPT, format_spec_prompt
from src.tools.dapr_tools import dapr_mcp_server

# Claude SDK imports (optional - graceful degradation if not available)
try:
    from claude_code_sdk import query as claude_query, ClaudeCodeOptions, ClaudeSDKError
    CLAUDE_SDK_AVAILABLE = True
except ImportError:
    CLAUDE_SDK_AVAILABLE = False
    claude_query = None
    ClaudeCodeOptions = None
    ClaudeSDKError = Exception

logger = logging.getLogger(__name__)


class ClaudeSpecifierAgent(BaseClaudeAgent):
    """Claude SDK agent that generates spec.md from feature descriptions.

    The Specifier transforms vague feature requests into structured specifications
    with user stories, acceptance criteria, and clear scope definitions.
    """

    def __init__(self, settings: Optional[Settings] = None) -> None:
        """Initialize the Claude Specifier agent."""
        super().__init__(
            agent_config=SPECIFIER_CONFIG,
            settings=settings,
        )
        # Register Dapr MCP server
        self.register_mcp_server("dapr", dapr_mcp_server)

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
            context: Additional context (may contain hints, langfuse_trace_id)

        Returns:
            Result dict with spec.md content and artifact info
        """
        logger.info(f"Specifier processing task for workflow {workflow_id}")

        # Extract trace context from message
        self.extract_trace_from_context(context)
        self.set_trace_context(workflow_id, self._trace_id)

        # Update workflow status
        await self.publish_status_update(
            workflow_id=workflow_id,
            status=WorkflowStatus.SPECIFYING,
            phase=WorkflowPhase.SPECIFICATION,
            progress_percent=10,
        )

        try:
            # Generate the specification using Claude SDK
            spec_content = await self._generate_spec_with_claude(task, context, workflow_id)

            # Save artifact to filesystem
            artifact_path = await self._save_spec_artifact(workflow_id, spec_content)

            # Register artifact in workflow state
            artifact = await self.register_artifact(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.SPEC,
                path=str(artifact_path),
                content=spec_content,
            )

            # Update workflow status
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.SPECIFYING,
                phase=WorkflowPhase.SPECIFICATION,
                progress_percent=25,
            )

            # Publish phase completion to orchestrator
            await self.publish_phase_complete(
                workflow_id=workflow_id,
                phase=WorkflowPhase.SPECIFICATION,
                result={"artifact": artifact.model_dump(), "spec_path": str(artifact_path)},
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

    async def _generate_spec_with_claude(
        self,
        feature_description: str,
        context: dict[str, Any],
        workflow_id: UUID,
    ) -> str:
        """Generate spec.md content using Claude SDK.

        This method uses the claude-code-sdk to generate specifications.
        The SDK handles all LLM interactions, tool use, and context management.

        Args:
            feature_description: Natural language feature description
            context: Additional context for generation
            workflow_id: Workflow ID for artifact path

        Returns:
            Generated spec.md content
        """
        # Format the prompt
        prompt = format_spec_prompt(feature_description)

        # Add any context hints
        if context.get("hints"):
            prompt += f"\n\n## Additional Context\n{context['hints']}"

        # Check if Claude SDK is available
        if not CLAUDE_SDK_AVAILABLE:
            logger.warning("Claude SDK not available, using fallback spec generation")
            return self._generate_structured_spec(feature_description)

        # Check for API key
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            logger.warning("ANTHROPIC_API_KEY not set, using fallback spec generation")
            return self._generate_structured_spec(feature_description)

        # Build Claude SDK options
        options = self.get_claude_options(override_max_turns=3)

        # Working directory for the spec
        artifacts_path = self.get_artifacts_path(workflow_id)
        artifacts_path.mkdir(parents=True, exist_ok=True)

        logger.info(f"Generating spec with Claude SDK for workflow {workflow_id}")
        logger.info(f"Model: {options.get('model', 'default')}")

        try:
            # Build the full prompt with system context
            full_prompt = f"{SPECIFIER_SYSTEM_PROMPT}\n\n---\n\n{prompt}"

            # Collect the spec content from Claude's response
            spec_content = ""

            # Build ClaudeCodeOptions for the query
            sdk_options = ClaudeCodeOptions(
                model=options.get("model", "claude-opus-4-5-20251101"),
                max_turns=options.get("max_turns", 3),
                cwd=str(artifacts_path),
                permission_mode="bypassPermissions",  # Allow autonomous execution
            )

            # Execute using Claude SDK query function
            async for message in claude_query(
                prompt=full_prompt,
                options=sdk_options,
            ):
                # Collect text responses
                if hasattr(message, "content"):
                    content_str = str(message.content)
                    # Look for markdown content that looks like a spec
                    if "# Feature Specification" in content_str or "## Overview" in content_str:
                        spec_content = content_str

            # If we got spec content from Claude, return it
            if spec_content and len(spec_content) > 100:
                logger.info(f"Generated spec via Claude SDK ({len(spec_content)} chars)")
                return spec_content

            # Fallback if Claude didn't return usable content
            logger.warning("Claude SDK returned no usable spec content, using fallback")
            return self._generate_structured_spec(feature_description)

        except ClaudeSDKError as e:
            logger.error(f"Claude SDK error: {e}")
            return self._generate_structured_spec(feature_description)
        except Exception as e:
            logger.error(f"Error generating spec with Claude SDK: {e}")
            return self._generate_structured_spec(feature_description)

    def _generate_structured_spec(self, feature_description: str) -> str:
        """Generate a structured spec.md document.

        This is a fallback/template method. In production, the Claude SDK
        will generate much richer specifications.

        Args:
            feature_description: The feature description

        Returns:
            Structured spec.md content
        """
        from datetime import datetime

        # Parse feature description for key elements
        lines = feature_description.strip().split("\n")
        title = lines[0] if lines else "Feature Implementation"

        return f"""# Feature Specification: {title}

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
- Integration with existing systems

### Out of Scope
- Advanced features (future iteration)
- Performance optimization (separate task)

## Assumptions
- Standard development environment available
- Dependencies are accessible
- Team has required skills

## Technical Constraints
- Must follow existing code patterns
- Must maintain backward compatibility
- Must use approved technologies

## Non-Functional Requirements
- Performance: Response time under 500ms
- Reliability: 99.9% uptime
- Security: Follow security best practices

## Success Metrics
- Feature is functional and passes all tests
- No regressions introduced
- Documentation is complete

## Dependencies
- None identified

## Risks
- Scope creep if requirements not clarified
- Integration complexity may increase timeline
"""

    async def _save_spec_artifact(
        self,
        workflow_id: UUID,
        content: str,
    ) -> Path:
        """Save spec.md content to filesystem.

        Args:
            workflow_id: The workflow ID
            content: Spec.md content to save

        Returns:
            Path to saved artifact
        """
        # Create artifact directory
        artifacts_dir = self.get_artifacts_path(workflow_id)
        artifacts_dir.mkdir(parents=True, exist_ok=True)

        # Write content
        spec_path = artifacts_dir / "spec.md"
        spec_path.write_text(content)

        logger.info(f"Saved spec.md artifact: {spec_path}")

        return spec_path


# ============================================================================
# FastAPI Application Factory
# ============================================================================

# Singleton agent instance
_agent: Optional[ClaudeSpecifierAgent] = None


def get_agent() -> ClaudeSpecifierAgent:
    """Get or create the Specifier agent instance."""
    global _agent
    if _agent is None:
        _agent = ClaudeSpecifierAgent()
    return _agent


def create_specifier_app() -> FastAPI:
    """Create FastAPI app for the specifier agent.

    Returns:
        Configured FastAPI app with agent endpoints
    """
    app = FastAPI(
        title="SpecKit Specifier Agent",
        version="2.0.0",
        description="Claude SDK powered specification writer",
    )

    # Add health endpoints
    app.include_router(health_router)

    # Create agent router
    router = APIRouter(tags=["Specifier"])

    @router.get("/dapr/subscribe")
    async def dapr_subscribe():
        """Dapr pub/sub subscription endpoint (GET required by Dapr)."""
        settings = get_settings()
        return [
            {
                "pubsubname": settings.pubsub_name,
                "topic": f"{settings.team_name}.specifier.requests",
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

            # Parse the workflow message
            workflow_id = UUID(data.get("workflow_id"))
            task = data.get("task", "")
            context = data.get("context", {})

            # Process the task
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
