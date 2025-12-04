# Data Model: Langfuse Tracing Integration

**Feature**: 009-langfuse-tracing-integration
**Date**: 2024-12-04

## Overview

This document defines the data entities involved in Langfuse tracing integration for SpecKit agents. The model follows Langfuse's trace hierarchy and maps SpecKit workflow concepts to Langfuse observability primitives.

---

## Entity Definitions

### 1. Trace (Langfuse Concept)

A trace represents a single workflow execution, grouping all related LLM calls.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| trace_id | `str` | Unique trace identifier (UUID format) | Required, auto-generated |
| name | `str` | Trace name (e.g., `workflow_{workflow_id}`) | Required, max 256 chars |
| session_id | `str` | Session grouping ID (equals workflow_id) | Required for correlation |
| user_id | `str?` | Optional user identifier | Optional |
| metadata | `dict[str, Any]` | Additional context (workflow_id, agent) | Optional |
| input | `str?` | Initial input (feature description) | Optional |
| output | `str?` | Final output (artifact summary) | Optional |

**Langfuse SDK Mapping**:
```python
langfuse.trace(
    name=name,
    session_id=session_id,
    user_id=user_id,
    metadata=metadata,
    input=input,
    output=output,
)
```

---

### 2. Generation (Langfuse Concept)

A generation represents a single LLM API call with prompt, response, and usage.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| trace_id | `str` | Parent trace ID | Required |
| name | `str` | Operation name (e.g., `generate_spec`) | Required |
| model | `str` | Model identifier | Required (e.g., `claude-sonnet-4-20250514`) |
| input_messages | `list[Message]` | Prompt messages | Required, non-empty |
| output | `str?` | LLM response text | Optional (null on error) |
| usage | `TokenUsage?` | Token counts | Optional |
| metadata | `dict[str, Any]` | Additional context | Optional |
| latency_ms | `int?` | Call duration in milliseconds | Optional |
| level | `str` | Status level (`DEFAULT`, `ERROR`) | Default: `DEFAULT` |

**Langfuse SDK Mapping**:
```python
langfuse.generation(
    trace_id=trace_id,
    name=name,
    model=model,
    input=input_messages,
    output=output,
    usage=usage,
    metadata=metadata,
)
```

---

### 3. Message (Internal Type)

Represents a chat message in OpenAI format.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| role | `str` | Message role | Required, one of: `system`, `user`, `assistant` |
| content | `str` | Message content | Required |

**Example**:
```json
{
  "role": "system",
  "content": "You are a specification writer..."
}
```

---

### 4. TokenUsage (Internal Type)

Represents token consumption for an LLM call.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| prompt_tokens | `int` | Input token count | Required, >= 0 |
| completion_tokens | `int` | Output token count | Required, >= 0 |
| total_tokens | `int` | Sum of prompt + completion | Required, >= 0 |

**Example**:
```json
{
  "prompt_tokens": 1250,
  "completion_tokens": 2340,
  "total_tokens": 3590
}
```

---

### 5. TraceContext (Application State)

Runtime state for propagating trace context across agents.

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| trace_id | `str?` | Current Langfuse trace ID | Set at workflow start |
| workflow_id | `UUID` | Workflow being traced | Required |
| agent_name | `str` | Current agent name | Required |
| parent_observation_id | `str?` | Parent span ID for nesting | Optional |

**State Transitions**:
```
Orchestrator: initialize_trace_for_workflow(workflow_id)
    → trace_id = langfuse.trace(...).trace_id
    → Embed trace_id in route_to_agent context

Worker Agent: process_task(workflow_id, task, context)
    → Extract trace_id = context.get("langfuse_trace_id")
    → Use trace_id for create_generation() calls
```

---

## Entity Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                    Langfuse Dashboard                       │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                         Trace                                │
│  session_id = workflow_id                                    │
│  name = "workflow_{uuid}"                                    │
└─────────────────────────────────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   Generation    │ │   Generation    │ │   Generation    │
│ name="specifier"│ │  name="planner" │ │ name="tasker"   │
│ agent=specifier │ │  agent=planner  │ │ agent=task_gen  │
│ input=[msgs]    │ │  input=[msgs]   │ │ input=[msgs]    │
│ output=spec     │ │  output=plan    │ │ output=tasks    │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## Pydantic Models

```python
# src/common/models.py - Add these types

from pydantic import BaseModel, Field
from typing import Optional, Any
from uuid import UUID


class Message(BaseModel):
    """Chat message in OpenAI format."""
    role: str = Field(..., pattern="^(system|user|assistant)$")
    content: str


class TokenUsage(BaseModel):
    """Token consumption for an LLM call."""
    prompt_tokens: int = Field(..., ge=0)
    completion_tokens: int = Field(..., ge=0)
    total_tokens: int = Field(..., ge=0)


class GenerationInput(BaseModel):
    """Input for logging a generation to Langfuse."""
    trace_id: str
    name: str
    model: str
    input_messages: list[Message]
    output: Optional[str] = None
    usage: Optional[TokenUsage] = None
    metadata: Optional[dict[str, Any]] = None
    latency_ms: Optional[int] = None


class TraceContext(BaseModel):
    """Runtime trace context for agents."""
    trace_id: Optional[str] = None
    workflow_id: UUID
    agent_name: str
    parent_observation_id: Optional[str] = None

    def to_message_context(self) -> dict[str, Any]:
        """Convert to dict for embedding in workflow message."""
        return {
            "langfuse_trace_id": self.trace_id,
            "langfuse_parent_observation_id": self.parent_observation_id,
        }

    @classmethod
    def from_message_context(
        cls,
        workflow_id: UUID,
        agent_name: str,
        context: dict[str, Any],
    ) -> "TraceContext":
        """Extract trace context from workflow message."""
        return cls(
            trace_id=context.get("langfuse_trace_id"),
            workflow_id=workflow_id,
            agent_name=agent_name,
            parent_observation_id=context.get("langfuse_parent_observation_id"),
        )
```

---

## State Machine: Trace Lifecycle

```
                 ┌────────────────────┐
                 │      PENDING       │
                 │  (no trace_id)     │
                 └─────────┬──────────┘
                           │ initialize_trace_for_workflow()
                           ▼
                 ┌────────────────────┐
                 │      ACTIVE        │
                 │  (trace_id set)    │
                 │  Generations added │
                 └─────────┬──────────┘
                           │ workflow completes
                           ▼
                 ┌────────────────────┐
                 │     FLUSHING       │
                 │  flush_langfuse()  │
                 └─────────┬──────────┘
                           │ flush complete
                           ▼
                 ┌────────────────────┐
                 │      CLOSED        │
                 │  (trace visible    │
                 │   in Langfuse UI)  │
                 └────────────────────┘
```

---

## Validation Rules

1. **Trace ID Format**: UUID v4 string (auto-generated by Langfuse)
2. **Session ID**: Must equal `str(workflow_id)` for proper grouping
3. **Model Name**: Must be valid Anthropic/OpenAI model identifier
4. **Token Usage**: All fields must be non-negative integers
5. **Latency**: Measured in milliseconds, must be >= 0
6. **Message Role**: Must be one of `system`, `user`, `assistant`
