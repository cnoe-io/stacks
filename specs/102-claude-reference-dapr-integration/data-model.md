# Data Model: Claude SDK + Dapr Multi-Agent Integration

**Feature**: 102-claude-reference-dapr-integration
**Date**: 2025-12-06
**Status**: Complete

## Overview

This document defines the data models used across the multi-agent system, including workflow state, messages, artifacts, and observability entities.

---

## 1. Core Domain Models

### 1.1 Workflow

The primary entity representing a feature development request.

```python
from enum import Enum
from datetime import datetime
from typing import Optional, List, Dict
from pydantic import BaseModel, Field
from uuid import UUID, uuid4

class WorkflowStatus(str, Enum):
    """Workflow lifecycle states."""
    PENDING = "pending"           # Created, waiting for processing
    QUEUED = "queued"             # Waiting in agent queue
    IN_PROGRESS = "in_progress"   # Currently being processed
    COMPLETED = "completed"       # Successfully finished
    FAILED = "failed"             # Terminal failure after retries
    CANCELLED = "cancelled"       # User-cancelled

class PhaseType(str, Enum):
    """Workflow phases in order."""
    SPECIFICATION = "specification"
    PLANNING = "planning"
    TASK_GENERATION = "task_generation"
    IMPLEMENTATION = "implementation"

class PhaseStatus(str, Enum):
    """Individual phase states."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"

class Phase(BaseModel):
    """Represents a single workflow phase."""
    type: PhaseType
    status: PhaseStatus = PhaseStatus.PENDING
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    retry_count: int = 0
    max_retries: int = 3
    timeout_seconds: int  # Phase-specific timeout
    error_message: Optional[str] = None
    artifact_refs: List[str] = Field(default_factory=list)

    @property
    def duration_seconds(self) -> Optional[float]:
        if self.started_at and self.completed_at:
            return (self.completed_at - self.started_at).total_seconds()
        return None

class TraceIds(BaseModel):
    """Cross-system trace identifiers."""
    langfuse_trace_id: Optional[str] = None
    langfuse_session_id: Optional[str] = None  # Same as workflow_id
    jaeger_trace_id: Optional[str] = None
    jaeger_span_id: Optional[str] = None

class Workflow(BaseModel):
    """Main workflow entity."""
    id: UUID = Field(default_factory=uuid4)
    description: str
    status: WorkflowStatus = WorkflowStatus.PENDING
    current_phase: Optional[PhaseType] = None
    phases: Dict[PhaseType, Phase] = Field(default_factory=dict)
    artifacts: Dict[str, "Artifact"] = Field(default_factory=dict)
    trace_ids: TraceIds = Field(default_factory=TraceIds)
    queue_position: Optional[int] = None  # If queued
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    def initialize_phases(self):
        """Initialize all phases with default timeouts."""
        phase_timeouts = {
            PhaseType.SPECIFICATION: 300,      # 5 minutes
            PhaseType.PLANNING: 600,           # 10 minutes
            PhaseType.TASK_GENERATION: 300,    # 5 minutes
            PhaseType.IMPLEMENTATION: 1800,    # 30 minutes
        }
        for phase_type, timeout in phase_timeouts.items():
            self.phases[phase_type] = Phase(
                type=phase_type,
                timeout_seconds=timeout,
            )

    def advance_phase(self) -> Optional[PhaseType]:
        """Move to next phase. Returns None if workflow complete."""
        phase_order = list(PhaseType)
        if self.current_phase is None:
            self.current_phase = phase_order[0]
            return self.current_phase

        current_idx = phase_order.index(self.current_phase)
        if current_idx + 1 < len(phase_order):
            self.current_phase = phase_order[current_idx + 1]
            return self.current_phase
        return None
```

### 1.2 Artifact

Generated documents from workflow phases.

```python
from enum import Enum
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field

class ArtifactType(str, Enum):
    """Types of generated artifacts."""
    SPEC = "spec"           # spec.md
    PLAN = "plan"           # plan.md
    RESEARCH = "research"   # research.md
    DATA_MODEL = "data_model"  # data-model.md
    CONTRACTS = "contracts"    # contracts/
    QUICKSTART = "quickstart"  # quickstart.md
    TASKS = "tasks"         # tasks.md
    SOURCE_CODE = "source_code"  # Implementation files

class Artifact(BaseModel):
    """Generated artifact from workflow phase."""
    id: str = Field(default_factory=lambda: str(uuid4()))
    type: ArtifactType
    name: str  # Filename or identifier
    content_hash: str  # SHA256 of content
    storage_ref: str  # Path or storage key
    size_bytes: int
    generating_agent: str
    generated_at: datetime = Field(default_factory=datetime.utcnow)
    metadata: Dict[str, str] = Field(default_factory=dict)
```

---

## 2. Message Models

### 2.1 Dapr Pub/Sub Messages

```python
from enum import Enum
from datetime import datetime
from typing import Optional, Dict, Any
from pydantic import BaseModel, Field
from uuid import UUID

class MessageType(str, Enum):
    """Types of inter-agent messages."""
    TRIGGER_ACTION = "TriggerAction"      # Start workflow/phase
    PHASE_COMPLETE = "PhaseComplete"       # Phase finished
    PHASE_FAILED = "PhaseFailed"          # Phase failed
    ARTIFACT_READY = "ArtifactReady"      # New artifact available
    BROADCAST = "Broadcast"               # Team-wide message

class AgentMessage(BaseModel):
    """Base message envelope for Dapr pub/sub."""
    id: str = Field(default_factory=lambda: str(uuid4()))
    type: MessageType
    workflow_id: UUID
    source_agent: str
    target_agent: Optional[str] = None  # None for broadcasts
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    trace_context: Dict[str, str] = Field(default_factory=dict)  # W3C traceparent
    payload: Dict[str, Any] = Field(default_factory=dict)

class TriggerActionPayload(BaseModel):
    """Payload for starting a workflow or phase."""
    task: str  # Description or instruction
    phase: Optional[PhaseType] = None
    context: Dict[str, Any] = Field(default_factory=dict)

class PhaseCompletePayload(BaseModel):
    """Payload for phase completion."""
    phase: PhaseType
    artifacts: List[str]  # Artifact IDs
    duration_seconds: float
    token_usage: Dict[str, int] = Field(default_factory=dict)

class PhaseFailedPayload(BaseModel):
    """Payload for phase failure."""
    phase: PhaseType
    error: str
    retry_count: int
    is_retryable: bool = True
```

### 2.2 API Request/Response Models

```python
from pydantic import BaseModel, Field
from typing import Optional, List, Dict
from uuid import UUID
from datetime import datetime

class WorkflowCreateRequest(BaseModel):
    """POST /run request body."""
    description: str = Field(..., min_length=10, max_length=10000)
    metadata: Dict[str, str] = Field(default_factory=dict)

class WorkflowCreateResponse(BaseModel):
    """POST /run response body."""
    workflow_id: UUID
    status: WorkflowStatus
    status_url: str
    created_at: datetime

class WorkflowStatusResponse(BaseModel):
    """GET /workflows/{id}/status response body."""
    workflow_id: UUID
    status: WorkflowStatus
    current_phase: Optional[PhaseType]
    queue_position: Optional[int]  # If status is QUEUED
    phases: Dict[str, PhaseStatusSummary]
    artifacts: List[ArtifactSummary]
    trace_ids: TraceIds
    created_at: datetime
    updated_at: datetime

class PhaseStatusSummary(BaseModel):
    """Summary of phase status for API response."""
    status: PhaseStatus
    retry_count: int
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    duration_seconds: Optional[float]

class ArtifactSummary(BaseModel):
    """Summary of artifact for API response."""
    id: str
    type: ArtifactType
    name: str
    size_bytes: int
    generated_at: datetime
```

---

## 3. Agent Configuration Models

### 3.1 Agent Profile

```python
from typing import List, Optional
from pydantic import BaseModel

class AgentToolConfig(BaseModel):
    """Tool configuration for an agent."""
    name: str
    allowed: bool = True
    timeout_seconds: int = 30

class AgentProfile(BaseModel):
    """Agent identity and behavior configuration."""
    name: str
    role: str
    goal: str
    instructions: List[str]
    style_guidelines: List[str]
    allowed_tools: List[AgentToolConfig]
    model: str = "claude-opus-4-5-20251101"

# Predefined agent profiles
ORCHESTRATOR_PROFILE = AgentProfile(
    name="Orchestrator",
    role="Workflow Coordinator",
    goal="Route workflows through phases, manage state, handle retries",
    instructions=[
        "Route incoming workflows to appropriate phase agents",
        "Track workflow state and progress",
        "Handle phase failures with retry logic (max 3 attempts)",
        "Enforce phase-specific timeouts",
        "Maintain queue for concurrent workflow limits",
    ],
    style_guidelines=[
        "Be concise and efficient",
        "Log all state transitions",
        "Preserve trace context across phase transitions",
    ],
    allowed_tools=[
        AgentToolConfig(name="Read", allowed=True),
        AgentToolConfig(name="Write", allowed=False),
    ],
)

SPECIFIER_PROFILE = AgentProfile(
    name="Specifier",
    role="Specification Writer",
    goal="Create detailed feature specifications from descriptions",
    instructions=[
        "Analyze feature description thoroughly",
        "Generate user stories with acceptance criteria",
        "Define functional requirements (FR-XXX format)",
        "Identify edge cases and error scenarios",
        "Produce spec.md following template structure",
    ],
    style_guidelines=[
        "Write for non-technical stakeholders",
        "Be comprehensive but concise",
        "Use testable, unambiguous language",
    ],
    allowed_tools=[
        AgentToolConfig(name="Read", allowed=True),
        AgentToolConfig(name="Write", allowed=True),
        AgentToolConfig(name="Glob", allowed=True),
        AgentToolConfig(name="Grep", allowed=True),
    ],
)

# Similar profiles for Planner, TaskGenerator, Implementer...
```

---

## 4. Observability Models

### 4.1 Tool Invocation Record

```python
from datetime import datetime
from typing import Optional, Any
from pydantic import BaseModel, Field

class ToolInvocation(BaseModel):
    """Record of a tool call for Langfuse."""
    tool_name: str
    input_params: Dict[str, Any]
    output_content: str  # Truncated if >10KB
    output_size_bytes: int  # Full size
    duration_ms: float
    is_error: bool = False
    error_message: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    @classmethod
    def from_tool_block(
        cls,
        name: str,
        input_params: dict,
        output: str,
        duration_ms: float,
        is_error: bool = False,
    ) -> "ToolInvocation":
        """Create from Claude SDK ToolResultBlock."""
        output_size = len(output.encode('utf-8'))
        truncated_output = output
        if output_size > 10240:
            truncated_output = f"{output[:10240]}... [truncated, {output_size} bytes total]"

        return cls(
            tool_name=name,
            input_params=input_params,
            output_content=truncated_output,
            output_size_bytes=output_size,
            duration_ms=duration_ms,
            is_error=is_error,
        )
```

### 4.2 Generation Record

```python
class LLMGeneration(BaseModel):
    """Record of LLM generation for Langfuse."""
    model: str
    input_messages: List[Dict[str, str]]
    output_text: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    duration_ms: float
    timestamp: datetime = Field(default_factory=datetime.utcnow)
```

---

## 5. State Store Schemas

### 5.1 Dapr State Keys

| Key Pattern | Model | Description |
|-------------|-------|-------------|
| `workflow:{id}` | `Workflow` | Complete workflow state |
| `queue:orchestrator` | `List[UUID]` | Orchestrator queue |
| `queue:{agent}` | `List[UUID]` | Per-agent queues |
| `{agent}:state:{workflow_id}` | `AgentState` | Agent-specific workflow state |
| `artifact:{id}` | `Artifact` | Artifact metadata |
| `artifact:{id}:content` | `bytes` | Artifact content (large files) |

### 5.2 Agent State

```python
class AgentState(BaseModel):
    """Per-agent state for a workflow."""
    workflow_id: UUID
    agent_name: str
    conversation_history: List[Dict[str, str]] = Field(default_factory=list)
    tool_calls: List[ToolInvocation] = Field(default_factory=list)
    artifacts_generated: List[str] = Field(default_factory=list)
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    error: Optional[str] = None
```

---

## 6. Entity Relationships

```
┌─────────────┐       1:N        ┌─────────────┐
│   Workflow  │─────────────────>│    Phase    │
│             │                  │             │
│  - id       │                  │  - type     │
│  - status   │                  │  - status   │
│  - phases   │                  │  - retries  │
└─────────────┘                  └─────────────┘
       │                                │
       │ 1:N                           │ 1:N
       ▼                                ▼
┌─────────────┐                  ┌─────────────┐
│  Artifact   │                  │ AgentState  │
│             │                  │             │
│  - type     │                  │  - history  │
│  - hash     │                  │  - tools    │
│  - agent    │                  │  - errors   │
└─────────────┘                  └─────────────┘
       │
       │ 1:N
       ▼
┌─────────────────┐
│  ToolInvocation │
│                 │
│  - tool_name    │
│  - duration     │
│  - is_error     │
└─────────────────┘
```

---

## 7. Validation Rules

### 7.1 Workflow Validation

- `description` must be 10-10,000 characters
- `workflow_id` must be unique (UUID collision checked)
- Phase order must be maintained (SPEC → PLAN → TASKS → IMPL)
- Retry count must not exceed 3 per phase

### 7.2 Message Validation

- `trace_context` must contain valid W3C traceparent if present
- `workflow_id` must reference existing workflow
- `source_agent` must be registered agent name

### 7.3 Artifact Validation

- `content_hash` must match SHA256 of stored content
- `storage_ref` must be valid path/key
- `type` must match generating phase expectations
