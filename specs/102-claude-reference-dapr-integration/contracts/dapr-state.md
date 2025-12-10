# Contract: Dapr State Store

**Feature**: 102-claude-reference-dapr-integration
**Version**: 1.0.0
**Date**: 2025-12-06

## Overview

Defines state store contracts for workflow state, agent state, and artifact storage via Dapr state management (Redis backend).

---

## State Store Components

### Component Configuration

```yaml
# Workflow state store (primary)
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: workflowstatestore
  namespace: speckit
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: redis.speckit.svc.cluster.local:6379
    - name: actorStateStore
      value: "true"
    - name: keyPrefix
      value: "speckit"

---
# Agent registry store
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: agentregistrystore
  namespace: speckit
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: redis.speckit.svc.cluster.local:6379
    - name: keyPrefix
      value: "none"

---
# Memory store (conversation history)
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: memorystore
  namespace: speckit
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: redis.speckit.svc.cluster.local:6379
    - name: keyPrefix
      value: "memory"
```

---

## Key Patterns

### Key Naming Convention

| Pattern | Store | Description |
|---------|-------|-------------|
| `workflow:{id}` | workflowstatestore | Complete workflow state |
| `queue:orchestrator` | workflowstatestore | Orchestrator work queue |
| `queue:{agent}` | workflowstatestore | Per-agent work queues |
| `{agent}:state:{workflow_id}` | workflowstatestore | Agent-specific workflow state |
| `artifact:{id}` | workflowstatestore | Artifact metadata |
| `artifact:{id}:content` | workflowstatestore | Artifact content (large) |
| `registry:speckit` | agentregistrystore | Team agent registry |
| `memory:{agent}:{session_id}` | memorystore | Conversation history |

---

## State Schemas

### Workflow State

**Key**: `workflow:{workflow_id}`

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "description": "Add user authentication with OAuth2 support",
  "status": "in_progress",
  "current_phase": "planning",
  "queue_position": null,
  "phases": {
    "specification": {
      "type": "specification",
      "status": "completed",
      "started_at": "2025-12-06T10:30:05Z",
      "completed_at": "2025-12-06T10:33:45Z",
      "retry_count": 0,
      "max_retries": 3,
      "timeout_seconds": 300,
      "error_message": null,
      "artifact_refs": ["art-001"]
    },
    "planning": {
      "type": "planning",
      "status": "in_progress",
      "started_at": "2025-12-06T10:33:50Z",
      "completed_at": null,
      "retry_count": 0,
      "max_retries": 3,
      "timeout_seconds": 600,
      "error_message": null,
      "artifact_refs": []
    },
    "task_generation": {
      "type": "task_generation",
      "status": "pending",
      "started_at": null,
      "completed_at": null,
      "retry_count": 0,
      "max_retries": 3,
      "timeout_seconds": 300,
      "error_message": null,
      "artifact_refs": []
    },
    "implementation": {
      "type": "implementation",
      "status": "pending",
      "started_at": null,
      "completed_at": null,
      "retry_count": 0,
      "max_retries": 3,
      "timeout_seconds": 1800,
      "error_message": null,
      "artifact_refs": []
    }
  },
  "artifacts": {
    "art-001": {
      "id": "art-001",
      "type": "spec",
      "name": "spec.md",
      "content_hash": "sha256:a3f2b...",
      "storage_ref": "artifact:art-001:content",
      "size_bytes": 15420,
      "generating_agent": "specifier",
      "generated_at": "2025-12-06T10:33:45Z",
      "metadata": {}
    }
  },
  "trace_ids": {
    "langfuse_trace_id": "lf-abc123",
    "langfuse_session_id": "550e8400-e29b-41d4-a716-446655440000",
    "jaeger_trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
    "jaeger_span_id": "00f067aa0ba902b7"
  },
  "metadata": {
    "priority": "high",
    "team": "platform"
  },
  "created_at": "2025-12-06T10:30:00Z",
  "updated_at": "2025-12-06T10:33:50Z"
}
```

---

### Work Queue

**Key**: `queue:orchestrator` or `queue:{agent}`

```json
{
  "items": [
    {
      "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
      "priority": 1,
      "enqueued_at": "2025-12-06T10:30:00Z"
    },
    {
      "workflow_id": "661f9511-f30c-52e5-b827-557766551111",
      "priority": 2,
      "enqueued_at": "2025-12-06T10:31:00Z"
    }
  ],
  "max_concurrent": 5,
  "processing_count": 4
}
```

---

### Agent State

**Key**: `{agent}:state:{workflow_id}`

```json
{
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "agent_name": "specifier",
  "conversation_history": [
    {
      "role": "user",
      "content": "Create a feature specification for: Add user authentication..."
    },
    {
      "role": "assistant",
      "content": "I'll create a comprehensive specification for the authentication feature..."
    }
  ],
  "tool_calls": [
    {
      "tool_name": "Read",
      "input_params": {
        "file_path": "/workspace/existing-auth/README.md"
      },
      "output_content": "# Existing Auth Module\n\nThis module provides...[truncated]",
      "output_size_bytes": 4520,
      "duration_ms": 45.2,
      "is_error": false,
      "error_message": null,
      "timestamp": "2025-12-06T10:31:15Z"
    },
    {
      "tool_name": "Write",
      "input_params": {
        "file_path": "/workspace/specs/102/spec.md",
        "content": "# Feature Specification..."
      },
      "output_content": "File written successfully",
      "output_size_bytes": 15420,
      "duration_ms": 12.8,
      "is_error": false,
      "error_message": null,
      "timestamp": "2025-12-06T10:33:42Z"
    }
  ],
  "artifacts_generated": ["art-001"],
  "started_at": "2025-12-06T10:30:05Z",
  "completed_at": "2025-12-06T10:33:45Z",
  "error": null,
  "token_usage": {
    "prompt_tokens": 15420,
    "completion_tokens": 8230,
    "total_tokens": 23650
  }
}
```

---

### Artifact Metadata

**Key**: `artifact:{id}`

```json
{
  "id": "art-001",
  "type": "spec",
  "name": "spec.md",
  "content_hash": "sha256:a3f2b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3",
  "storage_ref": "artifact:art-001:content",
  "size_bytes": 15420,
  "generating_agent": "specifier",
  "generated_at": "2025-12-06T10:33:45Z",
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "phase": "specification",
  "metadata": {
    "format": "markdown",
    "version": "1.0"
  }
}
```

---

### Artifact Content

**Key**: `artifact:{id}:content`

```
# Feature Specification: User Authentication

**Feature Branch**: `102-user-authentication`
**Created**: 2025-12-06
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - User Registration (Priority: P1)
...
```

Note: Content stored as raw string/bytes, not JSON.

---

### Agent Registry

**Key**: `registry:speckit`

```json
{
  "team_name": "speckit",
  "agents": {
    "orchestrator": {
      "name": "orchestrator",
      "topic": "speckit.orchestrator.requests",
      "capabilities": ["workflow_management", "phase_routing", "retry_logic"],
      "status": "active",
      "registered_at": "2025-12-06T10:00:00Z",
      "last_heartbeat": "2025-12-06T10:35:00Z"
    },
    "specifier": {
      "name": "specifier",
      "topic": "speckit.specifier.requests",
      "capabilities": ["spec_generation", "requirements_analysis"],
      "status": "active",
      "registered_at": "2025-12-06T10:00:05Z",
      "last_heartbeat": "2025-12-06T10:35:00Z"
    },
    "planner": {
      "name": "planner",
      "topic": "speckit.planner.requests",
      "capabilities": ["research", "architecture_design", "data_modeling"],
      "status": "active",
      "registered_at": "2025-12-06T10:00:10Z",
      "last_heartbeat": "2025-12-06T10:35:00Z"
    },
    "taskgenerator": {
      "name": "taskgenerator",
      "topic": "speckit.taskgenerator.requests",
      "capabilities": ["task_breakdown", "dependency_ordering"],
      "status": "active",
      "registered_at": "2025-12-06T10:00:15Z",
      "last_heartbeat": "2025-12-06T10:35:00Z"
    },
    "implementer": {
      "name": "implementer",
      "topic": "speckit.implementer.requests",
      "capabilities": ["code_generation", "testing", "refactoring"],
      "status": "active",
      "registered_at": "2025-12-06T10:00:20Z",
      "last_heartbeat": "2025-12-06T10:35:00Z"
    }
  },
  "updated_at": "2025-12-06T10:35:00Z"
}
```

---

### Conversation Memory

**Key**: `memory:{agent}:{session_id}`

```json
{
  "session_id": "specifier-550e8400-e29b-41d4-a716-446655440000",
  "agent_name": "specifier",
  "messages": [
    {
      "role": "system",
      "content": "You are the Specifier agent...",
      "timestamp": "2025-12-06T10:30:05Z"
    },
    {
      "role": "user",
      "content": "Create a feature specification for...",
      "timestamp": "2025-12-06T10:30:05Z"
    },
    {
      "role": "assistant",
      "content": "I'll analyze the requirements...",
      "timestamp": "2025-12-06T10:30:10Z"
    }
  ],
  "metadata": {
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "phase": "specification"
  },
  "created_at": "2025-12-06T10:30:05Z",
  "updated_at": "2025-12-06T10:33:45Z"
}
```

---

## Operations

### State Operations

#### Get State

```python
from dapr.clients import DaprClient

async def get_workflow(workflow_id: str) -> dict:
    with DaprClient() as client:
        state = client.get_state(
            store_name="workflowstatestore",
            key=f"workflow:{workflow_id}",
        )
        return json.loads(state.data) if state.data else None
```

#### Save State

```python
async def save_workflow(workflow: Workflow) -> None:
    with DaprClient() as client:
        client.save_state(
            store_name="workflowstatestore",
            key=f"workflow:{workflow.id}",
            value=workflow.model_dump_json(),
            state_metadata={
                "contentType": "application/json"
            }
        )
```

#### Transactional Update

```python
async def transition_phase(workflow_id: str, new_phase: str) -> None:
    with DaprClient() as client:
        # Get current state
        state = client.get_state(
            store_name="workflowstatestore",
            key=f"workflow:{workflow_id}",
        )
        workflow = json.loads(state.data)

        # Update phase
        workflow["current_phase"] = new_phase
        workflow["phases"][new_phase]["status"] = "in_progress"
        workflow["phases"][new_phase]["started_at"] = datetime.utcnow().isoformat()
        workflow["updated_at"] = datetime.utcnow().isoformat()

        # Save with etag for optimistic concurrency
        client.save_state(
            store_name="workflowstatestore",
            key=f"workflow:{workflow_id}",
            value=json.dumps(workflow),
            etag=state.etag,
        )
```

---

## Concurrency Control

### Optimistic Locking

Use ETags to prevent lost updates:

```python
try:
    client.save_state(
        store_name="workflowstatestore",
        key=f"workflow:{workflow_id}",
        value=updated_data,
        etag=current_etag,  # From previous get
        options=StateOptions(
            concurrency=StateConcurrency.FIRST_WRITE_WINS,
            consistency=StateConsistency.STRONG,
        )
    )
except DaprInternalError as e:
    if "etag mismatch" in str(e):
        # Retry with fresh state
        pass
```

### Queue Operations

Atomic queue operations using transactions:

```python
async def enqueue_workflow(agent: str, workflow_id: str) -> int:
    """Add workflow to queue, return position."""
    with DaprClient() as client:
        # Transaction: get queue, append, save
        queue_key = f"queue:{agent}"
        queue_state = client.get_state("workflowstatestore", queue_key)
        queue = json.loads(queue_state.data) if queue_state.data else {"items": [], "max_concurrent": 5, "processing_count": 0}

        queue["items"].append({
            "workflow_id": workflow_id,
            "priority": 1,
            "enqueued_at": datetime.utcnow().isoformat()
        })

        client.save_state(
            store_name="workflowstatestore",
            key=queue_key,
            value=json.dumps(queue),
            etag=queue_state.etag,
        )

        return len(queue["items"])
```

---

## TTL and Cleanup

### Workflow State TTL

Completed/failed workflows expire after 30 days:

```python
client.save_state(
    store_name="workflowstatestore",
    key=f"workflow:{workflow_id}",
    value=workflow_data,
    state_metadata={
        "ttlInSeconds": str(30 * 24 * 60 * 60)  # 30 days
    }
)
```

### Artifact Content TTL

Large artifact content expires after 30 days:

```python
client.save_state(
    store_name="workflowstatestore",
    key=f"artifact:{artifact_id}:content",
    value=content,
    state_metadata={
        "ttlInSeconds": str(30 * 24 * 60 * 60)  # 30 days
    }
)
```

---

## Queries

### List Workflows by Status

```python
async def list_workflows_by_status(status: str) -> List[dict]:
    """Query workflows by status (requires Redis query support)."""
    with DaprClient() as client:
        result = client.query_state(
            store_name="workflowstatestore",
            query=json.dumps({
                "filter": {
                    "EQ": {"status": status}
                },
                "sort": [
                    {"key": "created_at", "order": "DESC"}
                ],
                "page": {"limit": 100}
            })
        )
        return [json.loads(item.value) for item in result.results]
```

Note: Query support depends on Redis configuration with query indexing enabled.
