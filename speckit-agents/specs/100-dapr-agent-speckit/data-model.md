# Data Model: SpecKit Agent Observability

**Feature ID:** 100-dapr-agent-speckit-observability
**Date:** 2025-12-03

---

## Overview

This document defines the data entities for the observability system. Note that Jaeger and Langfuse have their own internal schemas; this document describes the logical model and how data flows between systems.

---

## Entity Relationship Diagram

```
┌─────────────────┐         ┌─────────────────┐
│    Workflow     │         │     Agent       │
│   Instance      │         │                 │
└────────┬────────┘         └────────┬────────┘
         │                           │
         │ 1:N                       │ 1:N
         ▼                           ▼
┌─────────────────┐         ┌─────────────────┐
│     Trace       │◄────────│      Span       │
│   (Jaeger)      │  1:N    │   (Jaeger)      │
└────────┬────────┘         └─────────────────┘
         │
         │ 1:1 (via trace_id)
         ▼
┌─────────────────┐         ┌─────────────────┐
│    Session      │◄────────│   Generation    │
│  (Langfuse)     │  1:N    │  (Langfuse)     │
└─────────────────┘         └─────────────────┘
```

---

## Entities

### 1. WorkflowInstance

Represents a single execution of the SpecKit workflow pipeline.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| workflow_id | UUID | Unique workflow identifier | Orchestrator |
| task | string | Original user task description | API request |
| status | enum | pending, running, completed, failed | Orchestrator |
| started_at | timestamp | When workflow began | Orchestrator |
| completed_at | timestamp | When workflow ended | Orchestrator |

**Relationships:**
- Has many Traces (1:N)
- Has one Session (1:1)

**Notes:**
- `workflow_id` is the correlation key across all observability systems
- Propagated via W3C trace context and Langfuse session_id

---

### 2. Trace (Jaeger)

A distributed trace representing end-to-end workflow execution.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| trace_id | string(32) | W3C trace ID (hex) | Dapr sidecar |
| workflow_id | string | Workflow instance correlation | Agent code |
| service_count | int | Number of services involved | Jaeger (computed) |
| span_count | int | Total spans in trace | Jaeger (computed) |
| duration_ms | int | Total trace duration | Jaeger (computed) |
| has_errors | boolean | Contains error spans | Jaeger (computed) |
| started_at | timestamp | First span start time | Jaeger |

**Relationships:**
- Belongs to WorkflowInstance (N:1)
- Has many Spans (1:N)
- Linked to Session via workflow_id (1:1)

**Storage:**
- Jaeger Badger embedded storage
- TTL: 7 days (configurable)

---

### 3. Span (Jaeger)

A single unit of work within a distributed trace.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| span_id | string(16) | Unique span ID (hex) | Dapr sidecar |
| trace_id | string(32) | Parent trace ID | Dapr sidecar |
| parent_span_id | string(16) | Parent span (nullable) | Dapr sidecar |
| operation_name | string | Name of operation | Dapr/Agent |
| service_name | string | Agent or service name | Dapr annotation |
| duration_ns | long | Span duration in nanoseconds | Dapr sidecar |
| status | enum | OK, ERROR, UNSET | Dapr sidecar |
| tags | map<string,string> | Key-value metadata | Agent code |
| logs | array | Timestamped events | Agent code |
| started_at | timestamp | Span start time | Dapr sidecar |

**Common Tags:**

| Tag | Description | Example |
|-----|-------------|---------|
| `agent.name` | Agent identifier | specifier |
| `agent.role` | Agent role | Specification Writer |
| `task.type` | Type of task | process_spec |
| `workflow.id` | Workflow correlation | uuid |
| `dapr.app.id` | Dapr application ID | specifier |
| `pubsub.topic` | Pub/sub topic name | speckit.specifier.requests |

**Relationships:**
- Belongs to Trace (N:1)
- Has parent Span (optional, N:1)
- Has child Spans (optional, 1:N)

---

### 4. Session (Langfuse)

A Langfuse session grouping related LLM generations for a workflow.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| session_id | string | Unique session ID (= workflow_id) | Agent code |
| project_id | string | Langfuse project ID | Langfuse config |
| user_id | string | Agent name | Agent code |
| total_tokens | int | Sum of all generation tokens | Langfuse (computed) |
| total_cost | decimal | Estimated total cost | Langfuse (computed) |
| generation_count | int | Number of LLM calls | Langfuse (computed) |
| started_at | timestamp | First generation time | Langfuse |
| ended_at | timestamp | Last generation time | Langfuse |

**Relationships:**
- Belongs to WorkflowInstance (N:1)
- Has many Generations (1:N)
- Linked to Trace via session_id = workflow_id (1:1)

**Storage:**
- Langfuse PostgreSQL database
- Retention: 7 days (configurable)

---

### 5. Generation (Langfuse)

A single LLM API call captured by Langfuse.

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| generation_id | UUID | Unique generation ID | Langfuse SDK |
| session_id | string | Parent session | Agent code |
| trace_id | string | Jaeger trace correlation | Agent code |
| name | string | Operation name | Agent code |
| model | string | LLM model used | LLM response |
| prompt | text | Full prompt content | Agent code |
| completion | text | LLM response content | LLM response |
| input_tokens | int | Prompt token count | LLM response |
| output_tokens | int | Completion token count | LLM response |
| total_tokens | int | input + output tokens | Langfuse (computed) |
| latency_ms | int | LLM call duration | Langfuse SDK |
| cost | decimal | Estimated cost (USD) | Langfuse (computed) |
| status | enum | success, error | Agent code |
| error_message | text | Error details (if failed) | Agent code |
| metadata | json | Additional context | Agent code |
| started_at | timestamp | Call start time | Langfuse SDK |

**Common Metadata:**

| Key | Description | Example |
|-----|-------------|---------|
| `agent_name` | Agent identifier | specifier |
| `agent_role` | Agent role | Specification Writer |
| `task_type` | Operation type | generate_spec |
| `workflow_phase` | Pipeline phase | specification |

**Relationships:**
- Belongs to Session (N:1)
- Linked to Span via trace_id (optional)

---

## Data Flow

### 1. Trace Creation Flow

```
1. Client submits workflow request
   └─> Orchestrator generates workflow_id

2. Orchestrator creates W3C trace context
   └─> trace_id created by Dapr sidecar

3. Each agent receives trace context
   └─> Dapr propagates traceparent header

4. Agent processes task
   └─> Spans created for each operation
   └─> workflow_id added to span tags

5. Agent makes LLM call
   └─> Langfuse SDK creates generation
   └─> session_id = workflow_id
   └─> trace_id added to metadata

6. Spans sent to Jaeger
   └─> Dapr sidecar → Zipkin endpoint → Jaeger collector

7. Generations sent to Langfuse
   └─> Langfuse SDK → Langfuse API → PostgreSQL
```

### 2. Query Correlation

To view a complete workflow execution:

```sql
-- Find all traces for a workflow
SELECT * FROM jaeger.traces WHERE tags['workflow.id'] = '${workflow_id}'

-- Find all LLM calls for a workflow
SELECT * FROM langfuse.generations WHERE session_id = '${workflow_id}'

-- Cross-reference by trace_id
SELECT g.* FROM langfuse.generations g
JOIN jaeger.spans s ON g.metadata->>'trace_id' = s.trace_id
WHERE s.tags['workflow.id'] = '${workflow_id}'
```

---

## Validation Rules

### Workflow Instance
- `workflow_id` must be valid UUID
- `status` must be one of: pending, running, completed, failed
- `started_at` required when status != pending

### Span Tags
- `agent.name` required for all agent spans
- `workflow.id` required for workflow correlation
- `dapr.app.id` auto-populated by Dapr

### Generation Metadata
- `agent_name` required for filtering
- `session_id` must equal `workflow_id` for correlation

---

## State Transitions

### Workflow Status

```
    ┌──────────────────────────────────────┐
    │                                      │
    ▼                                      │
┌────────┐    ┌─────────┐    ┌───────────┐│   ┌────────┐
│pending │───▶│ running │───▶│ completed ││   │ failed │
└────────┘    └─────────┘    └───────────┘│   └────────┘
                   │                       │       ▲
                   │                       │       │
                   └───────────────────────┴───────┘
                          (on error)
```

### Span Status

```
┌───────┐    ┌────┐    ┌───────┐
│ UNSET │───▶│ OK │    │ ERROR │
└───────┘    └────┘    └───────┘
     │                     ▲
     └─────────────────────┘
         (on exception)
```

---

## Retention Policy

| Data Type | Retention | Cleanup Method |
|-----------|-----------|----------------|
| Jaeger Traces | 7 days | Badger TTL auto-cleanup |
| Jaeger Spans | 7 days | Badger TTL auto-cleanup |
| Langfuse Sessions | 7 days | Langfuse retention setting |
| Langfuse Generations | 7 days | Langfuse retention setting |

---

## Index Requirements

### Jaeger (Badger)
- Primary: trace_id
- Secondary: service_name, operation_name
- Tag index: workflow.id, agent.name

### Langfuse (PostgreSQL)
- Primary: generation_id, session_id
- Index: session_id, user_id (agent_name)
- Index: created_at (for retention cleanup)
