# Contract: Dapr Pub/Sub Messages

**Feature**: 102-claude-reference-dapr-integration
**Version**: 1.0.0
**Date**: 2025-12-06

## Overview

Defines message contracts for inter-agent communication via Dapr pub/sub (Redis backend).

---

## Topics

### Topic Naming Convention

Pattern: `{team_name}.{agent_name}.requests`

| Topic | Subscriber | Purpose |
|-------|------------|---------|
| `speckit.orchestrator.requests` | Orchestrator | Workflow initiation and coordination |
| `speckit.specifier.requests` | Specifier Agent | Specification phase tasks |
| `speckit.planner.requests` | Planner Agent | Planning phase tasks |
| `speckit.taskgenerator.requests` | TaskGenerator Agent | Task generation phase |
| `speckit.implementer.requests` | Implementer Agent | Implementation phase tasks |
| `speckit.broadcast` | All Agents | Team-wide announcements |

### Dapr Pub/Sub Configuration

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: messagepubsub
  namespace: speckit
spec:
  type: pubsub.redis
  version: v1
  metadata:
    - name: redisHost
      value: redis.speckit.svc.cluster.local:6379
    - name: consumerID
      value: "{podName}"
```

---

## Message Envelope

All messages use CloudEvents format with the following envelope:

```json
{
  "specversion": "1.0",
  "type": "TriggerAction",
  "source": "speckit.orchestrator",
  "id": "msg-550e8400-e29b-41d4-a716-446655440000",
  "time": "2025-12-06T10:30:00Z",
  "datacontenttype": "application/json",
  "data": {
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "source_agent": "orchestrator",
    "target_agent": "specifier",
    "trace_context": {
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    },
    "payload": { ... }
  }
}
```

### CloudEvent Types

| Type | Description |
|------|-------------|
| `TriggerAction` | Start workflow or phase |
| `PhaseComplete` | Phase finished successfully |
| `PhaseFailed` | Phase failed (may retry) |
| `ArtifactReady` | New artifact available |
| `Broadcast` | Team-wide message |

---

## Message Types

### TriggerAction

Initiates a workflow or individual phase.

**Publisher**: Orchestrator, API Service
**Subscribers**: All agents (filtered by target_agent)

```json
{
  "type": "TriggerAction",
  "data": {
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "source_agent": "orchestrator",
    "target_agent": "specifier",
    "trace_context": {
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    },
    "payload": {
      "task": "Create a feature specification for: Add user authentication with OAuth2 support",
      "phase": "specification",
      "context": {
        "repository": "/workspace/my-project",
        "existing_specs": ["specs/001-initial-setup/spec.md"]
      }
    }
  }
}
```

#### Payload Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `task` | string | Yes | Task description or instruction |
| `phase` | PhaseType | No | Target phase (null for workflow start) |
| `context` | object | No | Additional context for the agent |

---

### PhaseComplete

Indicates successful phase completion.

**Publisher**: Phase agents
**Subscriber**: Orchestrator

```json
{
  "type": "PhaseComplete",
  "data": {
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "source_agent": "specifier",
    "target_agent": "orchestrator",
    "trace_context": {
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    },
    "payload": {
      "phase": "specification",
      "artifacts": ["art-001", "art-002"],
      "duration_seconds": 220.5,
      "token_usage": {
        "prompt_tokens": 15420,
        "completion_tokens": 8230,
        "total_tokens": 23650
      }
    }
  }
}
```

#### Payload Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `phase` | PhaseType | Yes | Completed phase |
| `artifacts` | string[] | Yes | IDs of generated artifacts |
| `duration_seconds` | number | Yes | Phase execution time |
| `token_usage` | object | No | LLM token consumption |

---

### PhaseFailed

Indicates phase failure.

**Publisher**: Phase agents, Orchestrator
**Subscriber**: Orchestrator

```json
{
  "type": "PhaseFailed",
  "data": {
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "source_agent": "planner",
    "target_agent": "orchestrator",
    "trace_context": {
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    },
    "payload": {
      "phase": "planning",
      "error": "Timeout exceeded: phase took 612 seconds (limit: 600)",
      "retry_count": 2,
      "is_retryable": true
    }
  }
}
```

#### Payload Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `phase` | PhaseType | Yes | Failed phase |
| `error` | string | Yes | Error description |
| `retry_count` | number | Yes | Number of retries so far |
| `is_retryable` | boolean | Yes | Whether retry is possible |

---

### ArtifactReady

Announces new artifact availability.

**Publisher**: Phase agents
**Subscriber**: Orchestrator, interested agents

```json
{
  "type": "ArtifactReady",
  "data": {
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "source_agent": "specifier",
    "target_agent": null,
    "trace_context": {
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    },
    "payload": {
      "artifact_id": "art-001",
      "artifact_type": "spec",
      "name": "spec.md",
      "storage_ref": "workflow:550e8400/artifacts/spec.md",
      "size_bytes": 15420,
      "content_hash": "sha256:a3f2b..."
    }
  }
}
```

#### Payload Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `artifact_id` | string | Yes | Unique artifact ID |
| `artifact_type` | ArtifactType | Yes | Type of artifact |
| `name` | string | Yes | Filename |
| `storage_ref` | string | Yes | State store key |
| `size_bytes` | number | Yes | Content size |
| `content_hash` | string | Yes | SHA256 of content |

---

### Broadcast

Team-wide announcements.

**Publisher**: Orchestrator, any agent
**Subscriber**: All agents

```json
{
  "type": "Broadcast",
  "data": {
    "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
    "source_agent": "orchestrator",
    "target_agent": null,
    "trace_context": {
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    },
    "payload": {
      "message": "Workflow cancelled by user request",
      "action": "cancel_workflow"
    }
  }
}
```

---

## Trace Context Propagation

All messages MUST include W3C Trace Context in the `trace_context` field:

```json
{
  "trace_context": {
    "traceparent": "00-{trace-id}-{span-id}-{trace-flags}",
    "tracestate": "vendor1=value1,vendor2=value2"
  }
}
```

### traceparent Format

```
00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
 │  │                                │                 │
 │  │                                │                 └─ trace-flags (01 = sampled)
 │  │                                └─ parent-id (8 bytes)
 │  └─ trace-id (16 bytes)
 └─ version
```

### Implementation

```python
from opentelemetry.propagate import inject, extract
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

def add_trace_context(message: dict) -> dict:
    """Add W3C trace context to message."""
    carrier = {}
    inject(carrier)
    message["data"]["trace_context"] = {
        "traceparent": carrier.get("traceparent"),
        "tracestate": carrier.get("tracestate"),
    }
    return message

def extract_trace_context(message: dict) -> Context:
    """Extract trace context from message."""
    carrier = message.get("data", {}).get("trace_context", {})
    return extract(carrier)
```

---

## Subscription Configuration

Each agent subscribes to its topic via Dapr subscription:

```yaml
apiVersion: dapr.io/v2alpha1
kind: Subscription
metadata:
  name: specifier-subscription
  namespace: speckit
spec:
  pubsubname: messagepubsub
  topic: speckit.specifier.requests
  routes:
    default: /messages
  scopes:
    - specifier
```

### Agent Message Handler

```python
from fastapi import FastAPI, Request
from dapr.ext.fastapi import DaprApp

app = FastAPI()
dapr_app = DaprApp(app)

@dapr_app.subscribe(pubsub="messagepubsub", topic="speckit.specifier.requests")
async def handle_message(request: Request):
    """Handle incoming messages."""
    event = await request.json()
    message_type = event.get("type")
    data = event.get("data", {})

    if message_type == "TriggerAction":
        await process_trigger_action(data)
    elif message_type == "Broadcast":
        await process_broadcast(data)

    return {"status": "SUCCESS"}
```

---

## Error Handling

### Retry Policy

Messages are retried by Dapr pub/sub on failure:

```yaml
apiVersion: dapr.io/v1alpha1
kind: Resiliency
metadata:
  name: speckit-resiliency
spec:
  policies:
    retries:
      pubsubRetry:
        policy: constant
        maxRetries: 3
        duration: 5s
```

### Dead Letter Topic

Failed messages after retries go to dead letter:

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: messagepubsub
spec:
  type: pubsub.redis
  metadata:
    - name: deadLetterTopic
      value: "speckit.deadletter"
```

---

## Message Flow Diagram

```
┌──────────┐     TriggerAction      ┌─────────────┐
│   API    │ ─────────────────────> │ Orchestrator│
│ Service  │                        │             │
└──────────┘                        └──────┬──────┘
                                           │
                         TriggerAction     │
                    ┌──────────────────────┤
                    │                      │
                    ▼                      │
             ┌───────────┐                 │
             │ Specifier │                 │
             └─────┬─────┘                 │
                   │                       │
     PhaseComplete │                       │
                   └───────────────────────┤
                                           │
                         TriggerAction     │
                    ┌──────────────────────┤
                    │                      │
                    ▼                      │
              ┌──────────┐                 │
              │ Planner  │                 │
              └────┬─────┘                 │
                   │                       │
     PhaseComplete │                       │
                   └───────────────────────┤
                                           │
                         TriggerAction     │
                    ┌──────────────────────┤
                    │                      │
                    ▼                      │
          ┌─────────────────┐              │
          │ TaskGenerator   │              │
          └────────┬────────┘              │
                   │                       │
     PhaseComplete │                       │
                   └───────────────────────┤
                                           │
                         TriggerAction     │
                    ┌──────────────────────┤
                    │                      │
                    ▼                      │
           ┌─────────────┐                 │
           │ Implementer │                 │
           └──────┬──────┘                 │
                  │                        │
    PhaseComplete │                        │
                  └────────────────────────┘
```
