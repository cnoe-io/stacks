# Data Model: SpecKit Multi-Agent Workflow System

**Branch**: `100-dapr-agent-speckit`
**Date**: 2025-12-03

## Entities

### Workflow

Represents a feature development request from submission to completion.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique workflow identifier |
| `feature_description` | string | Original natural language feature request |
| `status` | WorkflowStatus | Current workflow status |
| `current_phase` | WorkflowPhase | Active phase in the workflow |
| `current_agent` | string | Agent currently processing (null if idle) |
| `artifacts` | Artifact[] | List of generated artifacts |
| `created_at` | datetime | Workflow creation timestamp |
| `updated_at` | datetime | Last state update timestamp |
| `completed_at` | datetime | Workflow completion timestamp (null if incomplete) |
| `error` | string | Error message if failed (null otherwise) |

**State Transitions**:
```
pending → specifying → planning → task_generating → implementing → completed
                 ↓           ↓              ↓              ↓
              failed      failed         failed         failed
```

### WorkflowStatus (Enum)

| Value | Description |
|-------|-------------|
| `pending` | Workflow created, waiting to start |
| `specifying` | Specifier agent generating spec.md |
| `planning` | Planner agent creating plan artifacts |
| `task_generating` | Task generator creating tasks.md |
| `implementing` | Implementer executing tasks |
| `completed` | All phases complete |
| `failed` | Workflow encountered unrecoverable error |

### WorkflowPhase (Enum)

| Value | Description |
|-------|-------------|
| `specification` | Generate spec.md from description |
| `planning` | Generate plan.md, research.md, data-model.md |
| `task_generation` | Generate tasks.md |
| `implementation` | Execute tasks in order |

### Agent

Represents an autonomous service in the SpecKit team.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Agent identifier (e.g., "orchestrator", "specifier") |
| `role` | string | Agent's role description |
| `topic` | string | Pub/sub topic for receiving requests |
| `capabilities` | string[] | List of agent capabilities |
| `status` | AgentStatus | Current agent status |
| `last_heartbeat` | datetime | Last health check timestamp |

**Agent Registry Key**: `speckit:agent:{name}`

### AgentStatus (Enum)

| Value | Description |
|-------|-------------|
| `available` | Agent ready to receive tasks |
| `busy` | Agent currently processing a task |
| `offline` | Agent not responding to heartbeats |

### Artifact

Generated document from a workflow phase.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique artifact identifier |
| `workflow_id` | string | Parent workflow ID |
| `type` | ArtifactType | Type of artifact |
| `path` | string | File path relative to artifacts root |
| `content_hash` | string | SHA-256 hash of content |
| `created_at` | datetime | Generation timestamp |
| `created_by` | string | Agent that created this artifact |
| `version` | integer | Artifact version (incremented on updates) |

### ArtifactType (Enum)

| Value | Description |
|-------|-------------|
| `spec` | spec.md - Feature specification |
| `plan` | plan.md - Implementation plan |
| `research` | research.md - Technical research |
| `data_model` | data-model.md - Entity definitions |
| `tasks` | tasks.md - Task breakdown |
| `contract` | API contract file (OpenAPI/GraphQL) |
| `source` | Generated source code file |
| `test` | Generated test file |

### Task

Individual work item from tasks.md.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Task identifier (e.g., "SETUP-001") |
| `workflow_id` | string | Parent workflow ID |
| `phase` | TaskPhase | Task phase category |
| `description` | string | Task description |
| `status` | TaskStatus | Current task status |
| `dependencies` | string[] | IDs of tasks this depends on |
| `file_paths` | string[] | Files this task will create/modify |
| `is_parallel` | boolean | Can run in parallel with siblings |
| `started_at` | datetime | Task start timestamp |
| `completed_at` | datetime | Task completion timestamp |
| `error` | string | Error message if failed |

### TaskPhase (Enum)

| Value | Description |
|-------|-------------|
| `setup` | Project initialization, dependencies |
| `tests` | Contract and unit test creation |
| `core` | Core implementation |
| `integration` | Integration with external systems |
| `polish` | Documentation, cleanup, optimization |

### TaskStatus (Enum)

| Value | Description |
|-------|-------------|
| `pending` | Task not yet started |
| `in_progress` | Task currently executing |
| `completed` | Task finished successfully |
| `failed` | Task encountered error |
| `skipped` | Task skipped (dependency failed) |

### WorkflowMessage

Message published to agent topics.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Message identifier |
| `type` | string | CloudEvent type (e.g., "TriggerAction") |
| `source` | string | Originating agent or client |
| `workflow_id` | string | Associated workflow ID |
| `task` | string | Task description or instruction |
| `context` | object | Additional context (artifacts, state) |
| `timestamp` | datetime | Message creation time |

## Relationships

```
Workflow 1──*──* Artifact
    │
    └──*──* Task

Agent ──registers-in──> AgentRegistry (speckit team)

WorkflowMessage ──published-to──> Agent.topic
```

## State Store Keys

| Store | Key Pattern | Value |
|-------|-------------|-------|
| workflowstatestore | `{agent}:workflow:{workflow_id}` | Workflow state JSON |
| agentregistrystore | `speckit:agent:{agent_name}` | Agent registration JSON |
| memorystore | `{agent}-session:{session_id}` | Conversation history JSON |

## Validation Rules

### Workflow
- `feature_description` must be non-empty
- `status` must follow valid state transitions
- `completed_at` only set when `status == completed`

### Artifact
- `path` must be valid relative path
- `content_hash` must be valid SHA-256 hex string
- `version` must be positive integer

### Task
- `dependencies` must reference valid task IDs within same workflow
- Circular dependencies are invalid
- `is_parallel` tasks cannot depend on each other
