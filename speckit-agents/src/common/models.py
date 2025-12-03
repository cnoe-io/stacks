"""Pydantic models for SpecKit workflow entities."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


# =============================================================================
# Workflow Models (T010)
# =============================================================================


class WorkflowStatus(str, Enum):
    """Workflow execution status."""

    PENDING = "pending"
    SPECIFYING = "specifying"
    PLANNING = "planning"
    TASK_GENERATING = "task_generating"
    IMPLEMENTING = "implementing"
    COMPLETED = "completed"
    FAILED = "failed"


class WorkflowPhase(str, Enum):
    """Workflow phase for agent routing."""

    SPECIFICATION = "specification"
    PLANNING = "planning"
    TASK_GENERATION = "task_generation"
    IMPLEMENTATION = "implementation"


class Workflow(BaseModel):
    """Represents a feature development workflow."""

    id: UUID = Field(default_factory=uuid4, description="Unique workflow identifier")
    feature_description: str = Field(..., description="Original feature request")
    status: WorkflowStatus = Field(default=WorkflowStatus.PENDING)
    current_phase: WorkflowPhase = Field(default=WorkflowPhase.SPECIFICATION)
    current_agent: Optional[str] = Field(default=None, description="Currently processing agent")
    artifacts: list["Artifact"] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    completed_at: Optional[datetime] = Field(default=None)
    error: Optional[str] = Field(default=None, description="Error message if failed")

    def progress_percent(self) -> int:
        """Calculate workflow progress percentage."""
        phase_weights = {
            WorkflowPhase.SPECIFICATION: 25,
            WorkflowPhase.PLANNING: 50,
            WorkflowPhase.TASK_GENERATION: 75,
            WorkflowPhase.IMPLEMENTATION: 100,
        }
        if self.status == WorkflowStatus.COMPLETED:
            return 100
        if self.status == WorkflowStatus.FAILED:
            return phase_weights.get(self.current_phase, 0)
        # In progress - return phase start percentage
        phase_starts = {
            WorkflowPhase.SPECIFICATION: 0,
            WorkflowPhase.PLANNING: 25,
            WorkflowPhase.TASK_GENERATION: 50,
            WorkflowPhase.IMPLEMENTATION: 75,
        }
        return phase_starts.get(self.current_phase, 0)


# =============================================================================
# Agent Models (T011)
# =============================================================================


class AgentStatus(str, Enum):
    """Agent availability status."""

    AVAILABLE = "available"
    BUSY = "busy"
    OFFLINE = "offline"


class Agent(BaseModel):
    """Represents an agent in the SpecKit team."""

    name: str = Field(..., description="Agent identifier")
    role: str = Field(..., description="Agent role description")
    topic: str = Field(..., description="Pub/sub topic for requests")
    capabilities: list[str] = Field(default_factory=list)
    status: AgentStatus = Field(default=AgentStatus.AVAILABLE)
    last_heartbeat: datetime = Field(default_factory=datetime.utcnow)


class ArtifactType(str, Enum):
    """Type of generated artifact."""

    SPEC = "spec"
    PLAN = "plan"
    RESEARCH = "research"
    DATA_MODEL = "data_model"
    TASKS = "tasks"
    CONTRACT = "contract"
    SOURCE = "source"
    TEST = "test"


class Artifact(BaseModel):
    """Generated document from a workflow phase."""

    id: UUID = Field(default_factory=uuid4)
    workflow_id: UUID = Field(..., description="Parent workflow ID")
    type: ArtifactType = Field(..., description="Artifact type")
    path: str = Field(..., description="File path relative to artifacts root")
    content_hash: Optional[str] = Field(default=None, description="SHA-256 hash")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    created_by: str = Field(..., description="Agent that created this artifact")
    version: int = Field(default=1)


# =============================================================================
# Task Models (T012)
# =============================================================================


class TaskPhase(str, Enum):
    """Task phase category."""

    SETUP = "setup"
    TESTS = "tests"
    CORE = "core"
    INTEGRATION = "integration"
    POLISH = "polish"


class TaskStatus(str, Enum):
    """Task execution status."""

    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


class Task(BaseModel):
    """Individual work item from tasks.md."""

    id: str = Field(..., description="Task identifier (e.g., T001)")
    workflow_id: UUID = Field(..., description="Parent workflow ID")
    phase: TaskPhase = Field(..., description="Task phase category")
    description: str = Field(..., description="Task description")
    status: TaskStatus = Field(default=TaskStatus.PENDING)
    dependencies: list[str] = Field(default_factory=list, description="Dependency task IDs")
    file_paths: list[str] = Field(default_factory=list, description="Files to create/modify")
    is_parallel: bool = Field(default=False, description="Can run in parallel")
    user_story: Optional[str] = Field(default=None, description="User story label (e.g., US1)")
    started_at: Optional[datetime] = Field(default=None)
    completed_at: Optional[datetime] = Field(default=None)
    error: Optional[str] = Field(default=None)


class WorkflowMessage(BaseModel):
    """Message published to agent topics."""

    id: UUID = Field(default_factory=uuid4, description="Message identifier")
    type: str = Field(default="TriggerAction", description="CloudEvent type")
    source: str = Field(..., description="Originating agent or client")
    workflow_id: UUID = Field(..., description="Associated workflow ID")
    task: str = Field(..., description="Task description or instruction")
    context: dict[str, Any] = Field(default_factory=dict, description="Additional context")
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# =============================================================================
# Response Models
# =============================================================================


class HealthResponse(BaseModel):
    """Health check response."""

    status: str = "healthy"
    agent: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class ReadinessResponse(BaseModel):
    """Readiness check response."""

    ready: bool
    agent: str
    dapr_connected: bool = False
    components_ready: list[str] = Field(default_factory=list)


class WorkflowRequest(BaseModel):
    """Request to start a new workflow."""

    task: str = Field(..., min_length=10, max_length=10000, description="Feature description")


class WorkflowResponse(BaseModel):
    """Response after starting a workflow."""

    instance_id: UUID
    status: WorkflowStatus
    status_url: Optional[str] = None


class WorkflowStatusResponse(BaseModel):
    """Detailed workflow status response."""

    id: UUID
    status: WorkflowStatus
    current_phase: WorkflowPhase
    current_agent: Optional[str] = None
    progress_percent: int = 0
    artifacts: list[Artifact] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
    error: Optional[str] = None


class ErrorResponse(BaseModel):
    """Error response."""

    error: str
    message: str
    details: Optional[dict[str, Any]] = None
