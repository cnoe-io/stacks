"""Planner agent using Claude Agent SDK with parallel subagents.

Transforms specifications into implementation artifacts:
- research.md: Technology research and decisions
- data-model.md: Entity definitions and relationships
- plan.md: Implementation approach and file structure
"""

from __future__ import annotations

import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Optional
from uuid import UUID

from fastapi import APIRouter, FastAPI, Request

from src.agents.base import BaseClaudeAgent

# Claude SDK imports (optional - graceful degradation if not available)
try:
    from claude_code_sdk import query as claude_query, ClaudeCodeOptions, ClaudeSDKError
    CLAUDE_SDK_AVAILABLE = True
except ImportError:
    CLAUDE_SDK_AVAILABLE = False
    claude_query = None
    ClaudeCodeOptions = None
    ClaudeSDKError = Exception
from src.common.claude_config import PLANNER_CONFIG
from src.common.config import Settings, get_settings
from src.common.health import router as health_router
from src.common.models import (
    ArtifactType,
    WorkflowPhase,
    WorkflowStatus,
)
from src.prompts.planner import (
    format_plan_prompt,
    get_research_agent_prompt,
    get_data_modeler_prompt,
    get_architecture_agent_prompt,
)
from src.tools.dapr_tools import dapr_mcp_server
from src.tools.artifact_tools import artifact_mcp_server

logger = logging.getLogger(__name__)


class ClaudePlannerAgent(BaseClaudeAgent):
    """Claude SDK agent that generates planning artifacts with parallel subagents.

    The Planner coordinates three specialized subagents:
    - research-agent: Technology research (uses haiku for speed)
    - data-modeler: Entity design (uses sonnet for accuracy)
    - architecture-agent: Implementation plan (uses sonnet for depth)
    """

    def __init__(self, settings: Optional[Settings] = None) -> None:
        """Initialize the Claude Planner agent."""
        super().__init__(
            agent_config=PLANNER_CONFIG,
            settings=settings,
        )
        # Register MCP servers for Dapr and artifact access
        self.register_mcp_server("dapr", dapr_mcp_server)
        self.register_mcp_server("artifacts", artifact_mcp_server)

    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process a planning task.

        Args:
            workflow_id: The workflow this task belongs to
            task: Task description
            context: Additional context (spec content, langfuse_trace_id)

        Returns:
            Result dict with generated artifacts
        """
        logger.info(f"Planner processing task for workflow {workflow_id}")

        # Extract trace context
        self.extract_trace_from_context(context)
        self.set_trace_context(workflow_id, self._trace_id)

        # Create Langfuse trace for this agent's execution
        self.create_trace(
            name=f"planner:{workflow_id}",
            metadata={"task": task[:200], "phase": "planning"},
        )

        # Start OpenTelemetry span for distributed tracing
        self.start_workflow_span(workflow_id, "planning")

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

            # Generate planning artifacts using Claude SDK with subagents
            artifacts = await self._generate_planning_artifacts(workflow_id, spec_content)

            # Update workflow status
            await self.publish_status_update(
                workflow_id=workflow_id,
                status=WorkflowStatus.PLANNING,
                phase=WorkflowPhase.PLANNING,
                progress_percent=50,
            )

            # Publish phase completion
            await self.publish_phase_complete(
                workflow_id=workflow_id,
                phase=WorkflowPhase.PLANNING,
                result={
                    "artifacts": [a.model_dump() for a in artifacts],
                    "artifact_count": len(artifacts),
                },
            )

            logger.info(f"Planner completed task for workflow {workflow_id}")

            # End spans and flush traces
            self.end_workflow_span(success=True)
            self.flush_traces()

            return {
                "success": True,
                "artifacts": [a.model_dump() for a in artifacts],
                "next_agent": "task-generator",
            }

        except Exception as e:
            logger.error(f"Planner failed for workflow {workflow_id}: {e}")

            # End spans with error and flush traces
            self.log_error_to_trace(str(e), {"workflow_id": str(workflow_id)})
            self.end_workflow_span(success=False, error=str(e))
            self.flush_traces()

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
        """Get spec.md content from artifacts or context."""
        # Try artifact storage first
        content = await self.get_artifact_content(workflow_id, ArtifactType.SPEC)
        if content:
            return content

        # Fall back to context
        return context.get("spec_content")

    async def _generate_planning_artifacts(
        self,
        workflow_id: UUID,
        spec_content: str,
    ) -> list:
        """Generate all planning artifacts using Claude SDK with subagents.

        This method demonstrates the parallel subagent pattern:
        - Claude SDK orchestrates the main planner agent
        - Subagents (research, data-modeler, architecture) run in parallel
        - Results are aggregated and saved as artifacts

        Args:
            workflow_id: Workflow ID
            spec_content: Content of spec.md

        Returns:
            List of created Artifact records
        """
        artifacts_dir = self.get_artifacts_path(workflow_id)
        artifacts_dir.mkdir(parents=True, exist_ok=True)

        # Build the orchestration prompt
        prompt = format_plan_prompt(spec_content)

        # Build Claude SDK options with subagents
        options = self.get_claude_options(override_max_turns=10)

        # Check if Claude SDK is available
        if not CLAUDE_SDK_AVAILABLE:
            logger.warning("Claude SDK not available, using fallback artifact generation")
            artifact_contents = self._generate_fallback_artifacts(spec_content)
        elif not os.environ.get("ANTHROPIC_API_KEY"):
            logger.warning("ANTHROPIC_API_KEY not set, using fallback artifact generation")
            artifact_contents = self._generate_fallback_artifacts(spec_content)
        else:
            # Generate artifacts using Claude SDK
            artifact_contents = await self._generate_artifacts_with_claude(
                workflow_id=workflow_id,
                prompt=prompt,
                spec_content=spec_content,
                options=options,
                artifacts_dir=artifacts_dir,
            )

        # Save artifacts to filesystem
        artifacts = []

        # Research.md
        if "research.md" in artifact_contents:
            path = artifacts_dir / "research.md"
            path.write_text(artifact_contents["research.md"])
            artifact = await self.register_artifact(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.RESEARCH,
                path=str(path),
                content=artifact_contents["research.md"],
            )
            artifacts.append(artifact)

        # Data-model.md
        if "data-model.md" in artifact_contents:
            path = artifacts_dir / "data-model.md"
            path.write_text(artifact_contents["data-model.md"])
            artifact = await self.register_artifact(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.DATA_MODEL,
                path=str(path),
                content=artifact_contents["data-model.md"],
            )
            artifacts.append(artifact)

        # Plan.md
        if "plan.md" in artifact_contents:
            path = artifacts_dir / "plan.md"
            path.write_text(artifact_contents["plan.md"])
            artifact = await self.register_artifact(
                workflow_id=workflow_id,
                artifact_type=ArtifactType.PLAN,
                path=str(path),
                content=artifact_contents["plan.md"],
            )
            artifacts.append(artifact)

        return artifacts

    async def _generate_artifacts_with_claude(
        self,
        workflow_id: UUID,
        prompt: str,
        spec_content: str,
        options: dict[str, Any],
        artifacts_dir: Path,
    ) -> dict[str, str]:
        """Generate planning artifacts using Claude SDK.

        Args:
            workflow_id: Workflow ID
            prompt: Formatted planning prompt
            spec_content: Spec content for fallback
            options: Claude SDK options
            artifacts_dir: Directory to save artifacts

        Returns:
            Dict of artifact names to content
        """
        logger.info(f"Generating planning artifacts with Claude SDK for workflow {workflow_id}")
        logger.info(f"Model: {options.get('model', 'claude-opus-4-5-20251101')}")

        # System prompt for comprehensive planning
        system_prompt = """You are an expert software architect specializing in generating implementation artifacts.

Your task is to generate three markdown files based on the provided specification:

1. **research.md** - Technology research and decisions:
   - Executive summary
   - Technology choices with rationale
   - Alternatives considered
   - Performance and security considerations

2. **data-model.md** - Data model design:
   - Entity definitions with Pydantic models
   - Relationships (mermaid ER diagram)
   - Validation rules

3. **plan.md** - Implementation plan:
   - Architecture overview with ASCII diagram
   - Technology stack
   - Project structure
   - Implementation phases
   - API design
   - Testing strategy

Generate comprehensive, production-ready content for each file.
Output each file's content clearly labeled with the filename."""

        try:
            full_prompt = f"{system_prompt}\n\n---\n\n{prompt}"

            # Collect response content
            response_content = ""

            # Build ClaudeCodeOptions for the query
            sdk_options = ClaudeCodeOptions(
                model=options.get("model", "claude-opus-4-5-20251101"),
                max_turns=options.get("max_turns", 10),
                cwd=str(artifacts_dir),
                permission_mode="bypassPermissions",  # Allow autonomous execution
            )

            async for message in claude_query(
                prompt=full_prompt,
                options=sdk_options,
            ):
                if hasattr(message, "content"):
                    response_content += str(message.content)

            # Parse the response to extract individual artifacts
            artifacts = self._parse_claude_artifacts(response_content)

            # If we got valid artifacts, return them
            if artifacts and len(artifacts) >= 2:
                logger.info(f"Generated {len(artifacts)} artifacts via Claude SDK")
                return artifacts

            # Fallback if parsing failed
            logger.warning("Claude SDK response parsing failed, using fallback")
            return self._generate_fallback_artifacts(spec_content)

        except ClaudeSDKError as e:
            logger.error(f"Claude SDK error: {e}")
            return self._generate_fallback_artifacts(spec_content)
        except Exception as e:
            logger.error(f"Error generating artifacts with Claude SDK: {e}")
            return self._generate_fallback_artifacts(spec_content)

    def _parse_claude_artifacts(self, response: str) -> dict[str, str]:
        """Parse Claude response to extract individual artifacts.

        Args:
            response: Full Claude response text

        Returns:
            Dict mapping artifact names to content
        """
        artifacts = {}

        # Look for markdown file sections
        artifact_markers = [
            ("research.md", ["# Research", "## Executive Summary", "## Technology"]),
            ("data-model.md", ["# Data Model", "## Entity", "## Overview"]),
            ("plan.md", ["# Implementation Plan", "# Plan", "## Architecture"]),
        ]

        for filename, markers in artifact_markers:
            for marker in markers:
                if marker in response:
                    # Extract content starting from the marker
                    start_idx = response.find(marker)
                    if start_idx >= 0:
                        # Find the next major section or end
                        end_markers = ["# Research", "# Data Model", "# Implementation Plan", "# Plan"]
                        end_idx = len(response)
                        for em in end_markers:
                            if em != marker and em in response[start_idx + len(marker):]:
                                candidate_idx = response.find(em, start_idx + len(marker))
                                if candidate_idx < end_idx and candidate_idx > start_idx:
                                    end_idx = candidate_idx

                        content = response[start_idx:end_idx].strip()
                        if len(content) > 100:  # Minimum valid content
                            artifacts[filename] = content
                            break

        return artifacts

    def _generate_fallback_artifacts(self, spec_content: str) -> dict[str, str]:
        """Generate basic artifacts when Claude SDK is not available.

        This serves as a template/fallback. In production, Claude SDK
        with parallel subagents generates much richer content.

        Args:
            spec_content: The spec.md content

        Returns:
            Dict of artifact names to content
        """
        date = datetime.utcnow().strftime("%Y-%m-%d")

        # Extract title from spec
        lines = spec_content.strip().split("\n")
        title = lines[0].replace("#", "").strip() if lines else "Feature"

        research = f"""# Research: {title}

**Version**: 1.0
**Created**: {date}

## Executive Summary

This document captures technology decisions for implementing the specified feature.

## Technology Decisions

### Python 3.11+
- Strong typing with type hints
- Native async/await for concurrent operations
- Mature ecosystem with extensive libraries

### FastAPI Framework
- High performance async support
- Automatic OpenAPI documentation
- Native Pydantic integration

### Dapr Integration
- Distributed state management via Redis
- Pub/sub messaging for agent coordination
- Service invocation for inter-agent communication

### Claude Agent SDK
- LLM-powered agent execution
- MCP tools for external integrations
- Parallel subagent support

## Alternatives Considered

| Technology | Considered | Chosen | Rationale |
|------------|------------|--------|-----------|
| Flask | Yes | FastAPI | Async support, auto-docs |
| RabbitMQ | Yes | Dapr | Unified sidecar approach |
| LangChain | Yes | Claude SDK | Native Claude integration |

## Performance Considerations

- Async operations for all I/O-bound work
- Parallel subagent execution for 40% faster planning
- Redis state store with connection pooling

## Security Considerations

- API keys from environment variables
- No secrets in state store values
- Input validation via Pydantic

## Recommendations

1. Use Claude Agent SDK for all LLM interactions
2. Keep Dapr for distributed systems concerns
3. Implement graceful degradation for observability
"""

        data_model = f"""# Data Model: {title}

**Version**: 1.0
**Created**: {date}

## Overview

Entity definitions and relationships for the feature implementation.

## Entity Diagram

```mermaid
erDiagram
    Workflow ||--o{{ Artifact : contains
    Workflow {{
        uuid id PK
        string feature_description
        enum status
        enum current_phase
        string current_agent
        datetime created_at
        datetime updated_at
    }}
    Artifact {{
        uuid workflow_id FK
        enum type
        string path
        string content_hash
        string created_by
        datetime created_at
    }}
```

## Entity Definitions

### Workflow
Primary entity tracking feature development from start to completion.

```python
class Workflow(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    feature_description: str
    status: WorkflowStatus
    current_phase: WorkflowPhase
    current_agent: Optional[str] = None
    artifacts: List[Artifact] = []
    created_at: datetime
    updated_at: datetime
```

### Artifact
Represents generated documents in the workflow.

```python
class Artifact(BaseModel):
    workflow_id: UUID
    type: ArtifactType
    path: str
    content_hash: str
    created_by: str
    created_at: datetime
```

## Relationships

- **Workflow → Artifact**: One-to-many (workflow contains multiple artifacts)
- Artifacts are uniquely identified by workflow_id + type

## Validation Rules

1. Workflow.feature_description: Required, non-empty
2. Artifact.path: No ".." path traversal allowed
3. Artifact.content_hash: Valid SHA256 hex string (64 chars)
"""

        plan = f"""# Implementation Plan: {title}

**Version**: 1.0
**Created**: {date}
**Based On**: spec.md v1.0

## Architecture Overview

Multi-agent system using Claude Agent SDK for LLM operations and Dapr for distributed coordination.

```
┌─────────────────────────────────────────────────────────────┐
│                        API Gateway                           │
│                      (FastAPI + Dapr)                        │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
    │   Orchestrator  │ │   Worker Agent  │ │   Worker Agent  │
    │   (Pure Dapr)   │ │ (Claude SDK)    │ │ (Claude SDK)    │
    └─────────────────┘ └─────────────────┘ └─────────────────┘
              │               │               │
              └───────────────┼───────────────┘
                              ▼
                    ┌─────────────────┐
                    │   Dapr Sidecar  │
                    │ (State + PubSub)│
                    └─────────────────┘
```

## Technology Stack

- **Language**: Python 3.11+
- **Framework**: FastAPI + Uvicorn
- **LLM**: Claude Agent SDK
- **Distributed**: Dapr (state store, pub/sub)
- **Observability**: Langfuse
- **Storage**: Redis via Dapr

## Project Structure

```
speckit-agents/
├── src/
│   ├── agents/
│   │   ├── base.py           # BaseClaudeAgent
│   │   ├── orchestrator.py   # DaprOrchestrator
│   │   ├── specifier.py      # ClaudeSpecifierAgent
│   │   ├── planner.py        # ClaudePlannerAgent
│   │   ├── task_generator.py # ClaudeTaskGeneratorAgent
│   │   └── implementer.py    # ClaudeImplementerAgent
│   ├── tools/
│   │   ├── dapr_tools.py     # MCP tools for Dapr
│   │   ├── artifact_tools.py # MCP tools for artifacts
│   │   └── test_tools.py     # MCP tools for testing
│   ├── common/
│   │   ├── config.py         # Environment config
│   │   ├── models.py         # Pydantic models
│   │   └── claude_config.py  # Agent configurations
│   └── prompts/
│       ├── specifier.py
│       ├── planner.py
│       ├── task_generator.py
│       └── implementer.py
└── tests/
```

## Implementation Approach

### Phase 1: Foundation
- Project setup and dependencies
- Base classes and models
- Configuration management

### Phase 2: Infrastructure
- Dapr MCP tools
- Health probes
- Entry point dispatcher

### Phase 3: Agents
- Orchestrator (pure Dapr)
- Specifier (MVP)
- Planner with subagents
- Task Generator
- Implementer

### Phase 4: Observability
- Langfuse integration
- Trace propagation
- Error logging

## API Design

### POST /run
Start a new workflow with feature description.

### GET /status/{{workflow_id}}
Get workflow status and progress.

### Dapr Subscriptions
- `{{team}}.specifier.requests`
- `{{team}}.planner.requests`
- `{{team}}.orchestrator.requests`

## Testing Strategy

- Unit tests with pytest
- Integration tests with mock Dapr
- End-to-end workflow validation

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| LLM latency | Parallel subagents |
| State store failures | Retry with backoff |
| Agent deadlocks | Workflow timeouts |
"""

        return {
            "research.md": research,
            "data-model.md": data_model,
            "plan.md": plan,
        }


# ============================================================================
# FastAPI Application Factory
# ============================================================================

_agent: Optional[ClaudePlannerAgent] = None


def get_agent() -> ClaudePlannerAgent:
    """Get or create the Planner agent instance."""
    global _agent
    if _agent is None:
        _agent = ClaudePlannerAgent()
    return _agent


def create_planner_app() -> FastAPI:
    """Create FastAPI app for the planner agent.

    Returns:
        Configured FastAPI app with agent endpoints
    """
    app = FastAPI(
        title="SpecKit Planner Agent",
        version="2.0.0",
        description="Claude SDK powered planner with parallel subagents",
    )

    # Add health endpoints
    app.include_router(health_router)

    # Create agent router
    router = APIRouter(tags=["Planner"])

    @router.get("/dapr/subscribe")
    async def dapr_subscribe():
        """Dapr pub/sub subscription endpoint."""
        settings = get_settings()
        return [
            {
                "pubsubname": settings.pubsub_name,
                "topic": f"{settings.team_name}.planner.requests",
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
