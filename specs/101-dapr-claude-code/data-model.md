# Data Model: Claude Agent SDK Integration with Dapr

**Feature Branch**: `101-dapr-claude-code`
**Created**: 2025-12-05

## Entity Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Workflow                                          │
│  (persisted in Dapr state store: workflowstatestore)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  id: UUID                                                                   │
│  feature_description: str                                                   │
│  status: WorkflowStatus                                                     │
│  current_phase: WorkflowPhase                                               │
│  current_agent: str                                                         │
│  artifacts: List[Artifact]                                                  │
│  trace_id: str (Langfuse)                                                   │
│  created_at: datetime                                                       │
│  updated_at: datetime                                                       │
│  completed_at: datetime?                                                    │
│  error: str?                                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                │
                │ 1:N
                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Artifact                                          │
│  (stored as files, metadata in Workflow)                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  workflow_id: UUID                                                          │
│  type: ArtifactType (SPEC, PLAN, RESEARCH, DATA_MODEL, TASKS)              │
│  path: str                                                                  │
│  content_hash: str (SHA256)                                                 │
│  created_by: str (agent name)                                               │
│  created_at: datetime                                                       │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        WorkflowMessage                                      │
│  (transient - Dapr pub/sub)                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  source: str (sending agent)                                                │
│  workflow_id: UUID                                                          │
│  task: str (description/instruction)                                        │
│  context: Dict[str, Any]                                                    │
│    - langfuse_trace_id: str?                                                │
│    - artifacts: List[Artifact]?                                             │
│    - phase: str?                                                            │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        AgentConfig                                          │
│  (in-memory configuration per agent)                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  name: str                                                                  │
│  role: str                                                                  │
│  system_prompt: str                                                         │
│  max_turns: int                                                             │
│  model: str (claude-sonnet-4-20250514)                                      │
│  allowed_tools: List[str]                                                   │
│  mcp_servers: Dict[str, MCPServer]?                                         │
│  subagents: Dict[str, SubagentConfig]?                                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        SubagentConfig                                       │
│  (for planner's parallel workers)                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  description: str                                                           │
│  prompt: str (system prompt for subagent)                                   │
│  tools: List[str]                                                           │
│  model: str (haiku, sonnet, opus)                                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Entity Definitions

### Workflow

Primary entity tracking a feature development workflow from start to completion.

```python
from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum
from typing import Optional, List, Dict, Any
from uuid import UUID, uuid4

class WorkflowStatus(str, Enum):
    """Workflow lifecycle states"""
    PENDING = "pending"
    SPECIFYING = "specifying"
    PLANNING = "planning"
    TASK_GENERATING = "task_generating"
    IMPLEMENTING = "implementing"
    COMPLETED = "completed"
    FAILED = "failed"

class WorkflowPhase(str, Enum):
    """Workflow execution phases"""
    SPECIFICATION = "specification"
    PLANNING = "planning"
    TASK_GENERATION = "task_generation"
    IMPLEMENTATION = "implementation"

class Workflow(BaseModel):
    """Workflow state persisted in Dapr state store"""
    id: UUID = Field(default_factory=uuid4)
    feature_description: str
    status: WorkflowStatus = WorkflowStatus.PENDING
    current_phase: WorkflowPhase = WorkflowPhase.SPECIFICATION
    current_agent: Optional[str] = None
    artifacts: List["Artifact"] = Field(default_factory=list)
    trace_id: Optional[str] = None  # Langfuse trace ID
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    completed_at: Optional[datetime] = None
    error: Optional[str] = None

    def progress_percent(self) -> int:
        """Calculate workflow progress percentage"""
        phase_progress = {
            WorkflowPhase.SPECIFICATION: 25,
            WorkflowPhase.PLANNING: 50,
            WorkflowPhase.TASK_GENERATION: 75,
            WorkflowPhase.IMPLEMENTATION: 100,
        }
        if self.status == WorkflowStatus.COMPLETED:
            return 100
        if self.status == WorkflowStatus.FAILED:
            return phase_progress.get(self.current_phase, 0)
        return phase_progress.get(self.current_phase, 0) - 10

    class Config:
        use_enum_values = True
```

### Artifact

Represents generated documents in the workflow.

```python
class ArtifactType(str, Enum):
    """Types of artifacts generated by agents"""
    SPEC = "spec"
    PLAN = "plan"
    RESEARCH = "research"
    DATA_MODEL = "data_model"
    TASKS = "tasks"
    CONTRACT = "contract"
    CODE = "code"
    TEST = "test"

class Artifact(BaseModel):
    """Artifact metadata (content stored as files)"""
    workflow_id: UUID
    type: ArtifactType
    path: str  # Relative path from artifacts root
    content_hash: str  # SHA256 of content
    created_by: str  # Agent name
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        use_enum_values = True
```

### WorkflowMessage

Message format for Dapr pub/sub inter-agent communication.

```python
class WorkflowMessage(BaseModel):
    """Message passed between agents via Dapr pub/sub"""
    source: str  # Sending agent name
    workflow_id: UUID
    task: str  # Task description or instruction
    context: Dict[str, Any] = Field(default_factory=dict)
    # Common context fields:
    # - langfuse_trace_id: str (for observability propagation)
    # - artifacts: List[Artifact] (from previous phases)
    # - phase: str (current workflow phase)
    # - previous_result: dict (output from previous agent)
```

### AgentConfig

Configuration for Claude Agent SDK per agent type.

```python
from dataclasses import dataclass, field
from typing import Dict, List, Optional

@dataclass
class SubagentConfig:
    """Configuration for a parallel subagent"""
    description: str
    prompt: str
    tools: List[str]
    model: str = "sonnet"

@dataclass
class AgentConfig:
    """Configuration for a SpecKit agent"""
    name: str
    role: str
    system_prompt: str
    max_turns: int = 5
    model: str = "claude-sonnet-4-20250514"
    allowed_tools: List[str] = field(default_factory=list)
    mcp_servers: Dict[str, Any] = field(default_factory=dict)  # MCP server instances
    subagents: Dict[str, SubagentConfig] = field(default_factory=dict)
```

## Agent Configurations

### Specifier Agent

```python
SPECIFIER_CONFIG = AgentConfig(
    name="specifier",
    role="Specification Writer",
    system_prompt="""You are a specification writer. Transform feature descriptions into structured spec.md documents.

Output format: Markdown specification with sections:
- User Scenarios & Testing (user stories with acceptance criteria)
- Requirements (functional requirements)
- Success Criteria (measurable outcomes)

Use the Write tool to save the specification to {workflow_id}/spec.md""",
    max_turns=3,
    model="claude-sonnet-4-20250514",
    allowed_tools=["Read", "Write", "mcp__dapr__get_workflow_state"],
)
```

### Planner Agent

```python
PLANNER_CONFIG = AgentConfig(
    name="planner",
    role="Implementation Planner",
    system_prompt="""You are a planning orchestrator. Based on the specification, generate:
1. research.md - Technology research and decisions
2. data-model.md - Entity definitions and relationships
3. plan.md - Implementation approach and file structure

Delegate specialized work to subagents for parallel execution.""",
    max_turns=10,
    model="claude-sonnet-4-20250514",
    allowed_tools=["Read", "Write", "Glob", "mcp__dapr__get_artifact"],
    subagents={
        "research-agent": SubagentConfig(
            description="Research technology choices and best practices",
            prompt="You are a technology researcher. Analyze requirements and recommend technologies.",
            tools=["WebSearch", "Read"],
            model="haiku"
        ),
        "data-modeler": SubagentConfig(
            description="Design data models and entity relationships",
            prompt="You are a data modeling expert. Define entities, fields, and relationships.",
            tools=["Read", "Write"],
            model="sonnet"
        ),
        "architecture-agent": SubagentConfig(
            description="Design system architecture and implementation approach",
            prompt="You are a software architect. Create implementation plans with file structure.",
            tools=["Read", "Write", "Glob"],
            model="sonnet"
        )
    }
)
```

### Task Generator Agent

```python
TASK_GENERATOR_CONFIG = AgentConfig(
    name="task-generator",
    role="Task Breakdown Specialist",
    system_prompt="""You are a task breakdown specialist. Convert implementation plans into ordered tasks.

Output: tasks.md with phases:
- Setup: Environment and configuration
- Tests: Test files (TDD - tests before implementation)
- Core: Core implementation files
- Integration: Integration and wiring
- Polish: Documentation and cleanup

Mark parallel-safe tasks with [P]. Include file paths for each task.""",
    max_turns=5,
    model="claude-sonnet-4-20250514",
    allowed_tools=["Read", "Write", "mcp__dapr__get_artifact"],
)
```

### Implementer Agent

```python
IMPLEMENTER_CONFIG = AgentConfig(
    name="implementer",
    role="Task Implementer",
    system_prompt="""You are a TDD implementation agent. For each task in tasks.md:
1. Write tests first (use mcp__tests__run_tests to verify they fail)
2. Implement the code to make tests pass
3. Run tests to verify success
4. Refactor if needed
5. Mark task complete in tasks.md

Use Edit for precise file modifications. Use Bash for commands.""",
    max_turns=50,  # Many iterations for TDD workflow
    model="claude-sonnet-4-20250514",
    allowed_tools=[
        "Read", "Write", "Edit", "Bash", "Glob", "Grep",
        "mcp__dapr__get_artifact",
        "mcp__dapr__save_workflow_state",
        "mcp__tests__run_tests"
    ],
)
```

## Storage Patterns

### Dapr State Store Keys

| Key Pattern | Value | Store |
|-------------|-------|-------|
| `workflow:{uuid}` | Workflow JSON | workflowstatestore |
| `registry:{team}:{agent}` | Agent registration | agentregistrystore |
| `memory:{agent}:{session}` | Conversation history | memorystore |

### Artifact File Paths

```
/artifacts/
└── {workflow_id}/
    ├── spec.md          # ArtifactType.SPEC
    ├── research.md      # ArtifactType.RESEARCH
    ├── data-model.md    # ArtifactType.DATA_MODEL
    ├── plan.md          # ArtifactType.PLAN
    ├── tasks.md         # ArtifactType.TASKS
    └── contracts/       # ArtifactType.CONTRACT
        └── *.yaml
```

## State Transitions

```
                    ┌─────────────────┐
                    │     PENDING     │
                    └────────┬────────┘
                             │ start_workflow
                             ▼
                    ┌─────────────────┐
         ┌─────────│   SPECIFYING    │─────────┐
         │ fail    └────────┬────────┘ success │
         │                  │                  │
         │                  ▼                  │
         │         ┌─────────────────┐         │
         │ ┌───────│    PLANNING     │───────┐ │
         │ │ fail  └────────┬────────┘success│ │
         │ │                │                │ │
         │ │                ▼                │ │
         │ │       ┌─────────────────┐       │ │
         │ │ ┌─────│TASK_GENERATING  │─────┐ │ │
         │ │ │fail └────────┬────────┘succ │ │ │
         │ │ │              │              │ │ │
         │ │ │              ▼              │ │ │
         │ │ │     ┌─────────────────┐     │ │ │
         │ │ │ ┌───│  IMPLEMENTING   │───┐ │ │ │
         │ │ │ │   └────────┬────────┘   │ │ │ │
         │ │ │ │            │            │ │ │ │
         ▼ ▼ ▼ ▼            ▼            ▼ ▼ ▼ ▼
    ┌──────────┐      ┌──────────┐
    │  FAILED  │      │ COMPLETED│
    └──────────┘      └──────────┘
```

## Validation Rules

### Workflow

- `feature_description`: Required, non-empty string
- `status`: Must be valid WorkflowStatus enum
- `current_phase`: Must be valid WorkflowPhase enum
- `artifacts`: List of valid Artifact objects with unique types per workflow

### Artifact

- `path`: Must be relative path, no `..` traversal
- `content_hash`: Valid SHA256 hex string (64 chars)
- `created_by`: Must match known agent name

### WorkflowMessage

- `workflow_id`: Must reference existing workflow
- `source`: Must be valid agent name
- `context.langfuse_trace_id`: Optional but recommended for observability
