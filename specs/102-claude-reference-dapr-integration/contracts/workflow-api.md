# Contract: Workflow REST API

**Feature**: 102-claude-reference-dapr-integration
**Version**: 1.0.0
**Date**: 2025-12-06

## Overview

REST API for initiating and monitoring feature development workflows.

---

## Authentication

All endpoints require API key authentication via the `X-API-Key` header.

```
X-API-Key: <api-key-from-azure-keyvault>
```

### Error Responses

| Status | Description |
|--------|-------------|
| 401 | Missing or invalid API key |
| 403 | API key valid but insufficient permissions |

```json
{
  "error": "unauthorized",
  "message": "Invalid or missing API key"
}
```

---

## Endpoints

### POST /run

Initiate a new feature development workflow.

#### Request

```http
POST /run HTTP/1.1
Host: api.speckit.local
Content-Type: application/json
X-API-Key: sk-xxx

{
  "description": "Add a user authentication system with OAuth2 support and JWT tokens",
  "metadata": {
    "priority": "high",
    "team": "platform"
  }
}
```

#### Request Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | Yes | Feature description (10-10,000 chars) |
| `metadata` | object | No | Optional key-value metadata |

#### Success Response (202 Accepted)

```json
{
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "status_url": "/workflows/550e8400-e29b-41d4-a716-446655440000/status",
  "created_at": "2025-12-06T10:30:00Z"
}
```

#### Error Responses

| Status | Condition | Response |
|--------|-----------|----------|
| 400 | Invalid request body | `{"error": "validation_error", "details": [...]}` |
| 401 | Authentication failed | `{"error": "unauthorized"}` |
| 429 | Rate limit exceeded | `{"error": "rate_limit", "retry_after": 60}` |
| 503 | Service unavailable | `{"error": "service_unavailable"}` |

---

### GET /workflows/{id}/status

Query workflow status and progress.

#### Request

```http
GET /workflows/550e8400-e29b-41d4-a716-446655440000/status HTTP/1.1
Host: api.speckit.local
X-API-Key: sk-xxx
```

#### Success Response (200 OK)

```json
{
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "in_progress",
  "current_phase": "planning",
  "queue_position": null,
  "phases": {
    "specification": {
      "status": "completed",
      "retry_count": 0,
      "started_at": "2025-12-06T10:30:05Z",
      "completed_at": "2025-12-06T10:33:45Z",
      "duration_seconds": 220.5
    },
    "planning": {
      "status": "in_progress",
      "retry_count": 0,
      "started_at": "2025-12-06T10:33:50Z",
      "completed_at": null,
      "duration_seconds": null
    },
    "task_generation": {
      "status": "pending",
      "retry_count": 0,
      "started_at": null,
      "completed_at": null,
      "duration_seconds": null
    },
    "implementation": {
      "status": "pending",
      "retry_count": 0,
      "started_at": null,
      "completed_at": null,
      "duration_seconds": null
    }
  },
  "artifacts": [
    {
      "id": "art-001",
      "type": "spec",
      "name": "spec.md",
      "size_bytes": 15420,
      "generated_at": "2025-12-06T10:33:45Z"
    }
  ],
  "trace_ids": {
    "langfuse_session_id": "550e8400-e29b-41d4-a716-446655440000",
    "langfuse_trace_id": "lf-abc123",
    "jaeger_trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"
  },
  "created_at": "2025-12-06T10:30:00Z",
  "updated_at": "2025-12-06T10:33:50Z"
}
```

#### Queued Response

When workflow is queued due to concurrent limit:

```json
{
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued",
  "current_phase": null,
  "queue_position": 3,
  "phases": {...},
  "artifacts": [],
  "trace_ids": {...},
  "created_at": "2025-12-06T10:30:00Z",
  "updated_at": "2025-12-06T10:30:00Z"
}
```

#### Failed Response

When workflow has failed:

```json
{
  "workflow_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "failed",
  "current_phase": "planning",
  "queue_position": null,
  "phases": {
    "specification": {
      "status": "completed",
      ...
    },
    "planning": {
      "status": "failed",
      "retry_count": 3,
      "error_message": "Timeout exceeded after 3 retries",
      ...
    },
    ...
  },
  ...
}
```

#### Error Responses

| Status | Condition | Response |
|--------|-----------|----------|
| 401 | Authentication failed | `{"error": "unauthorized"}` |
| 404 | Workflow not found | `{"error": "not_found", "message": "Workflow not found"}` |

---

## Response Schema Reference

### WorkflowStatus Enum

| Value | Description |
|-------|-------------|
| `pending` | Created, waiting for processing |
| `queued` | Waiting in agent queue |
| `in_progress` | Currently being processed |
| `completed` | Successfully finished |
| `failed` | Terminal failure after retries |
| `cancelled` | User-cancelled |

### PhaseType Enum

| Value | Description |
|-------|-------------|
| `specification` | Spec generation phase |
| `planning` | Planning and research phase |
| `task_generation` | Task breakdown phase |
| `implementation` | Code implementation phase |

### PhaseStatus Enum

| Value | Description |
|-------|-------------|
| `pending` | Not yet started |
| `in_progress` | Currently executing |
| `completed` | Successfully finished |
| `failed` | Failed after retries |
| `skipped` | Intentionally skipped |

### ArtifactType Enum

| Value | Description |
|-------|-------------|
| `spec` | spec.md |
| `plan` | plan.md |
| `research` | research.md |
| `data_model` | data-model.md |
| `contracts` | contracts/ directory |
| `quickstart` | quickstart.md |
| `tasks` | tasks.md |
| `source_code` | Implementation files |

---

## Rate Limits

| Endpoint | Limit | Window |
|----------|-------|--------|
| POST /run | 10 requests | per minute |
| GET /workflows/{id}/status | 60 requests | per minute |

Rate limit headers included in response:

```
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 8
X-RateLimit-Reset: 1733486400
```

---

## Timeouts

| Phase | Timeout |
|-------|---------|
| Specification | 5 minutes |
| Planning | 10 minutes |
| Task Generation | 5 minutes |
| Implementation | 30 minutes |
| **Total (no retries)** | **50 minutes** |

---

## OpenAPI Specification

```yaml
openapi: 3.1.0
info:
  title: SpecKit Workflow API
  version: 1.0.0
  description: API for initiating and monitoring feature development workflows

servers:
  - url: https://api.speckit.local
    description: Local development

security:
  - ApiKeyAuth: []

paths:
  /run:
    post:
      summary: Initiate workflow
      operationId: createWorkflow
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/WorkflowCreateRequest'
      responses:
        '202':
          description: Workflow created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/WorkflowCreateResponse'
        '400':
          $ref: '#/components/responses/ValidationError'
        '401':
          $ref: '#/components/responses/Unauthorized'

  /workflows/{id}/status:
    get:
      summary: Get workflow status
      operationId: getWorkflowStatus
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: Workflow status
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/WorkflowStatusResponse'
        '401':
          $ref: '#/components/responses/Unauthorized'
        '404':
          $ref: '#/components/responses/NotFound'

components:
  securitySchemes:
    ApiKeyAuth:
      type: apiKey
      in: header
      name: X-API-Key

  schemas:
    WorkflowCreateRequest:
      type: object
      required: [description]
      properties:
        description:
          type: string
          minLength: 10
          maxLength: 10000
        metadata:
          type: object
          additionalProperties:
            type: string

    WorkflowCreateResponse:
      type: object
      properties:
        workflow_id:
          type: string
          format: uuid
        status:
          $ref: '#/components/schemas/WorkflowStatus'
        status_url:
          type: string
        created_at:
          type: string
          format: date-time

    WorkflowStatusResponse:
      type: object
      properties:
        workflow_id:
          type: string
          format: uuid
        status:
          $ref: '#/components/schemas/WorkflowStatus'
        current_phase:
          $ref: '#/components/schemas/PhaseType'
        queue_position:
          type: integer
          nullable: true
        phases:
          type: object
          additionalProperties:
            $ref: '#/components/schemas/PhaseStatusSummary'
        artifacts:
          type: array
          items:
            $ref: '#/components/schemas/ArtifactSummary'
        trace_ids:
          $ref: '#/components/schemas/TraceIds'
        created_at:
          type: string
          format: date-time
        updated_at:
          type: string
          format: date-time

    WorkflowStatus:
      type: string
      enum: [pending, queued, in_progress, completed, failed, cancelled]

    PhaseType:
      type: string
      enum: [specification, planning, task_generation, implementation]

    PhaseStatusSummary:
      type: object
      properties:
        status:
          type: string
          enum: [pending, in_progress, completed, failed, skipped]
        retry_count:
          type: integer
        started_at:
          type: string
          format: date-time
          nullable: true
        completed_at:
          type: string
          format: date-time
          nullable: true
        duration_seconds:
          type: number
          nullable: true
        error_message:
          type: string
          nullable: true

    ArtifactSummary:
      type: object
      properties:
        id:
          type: string
        type:
          type: string
        name:
          type: string
        size_bytes:
          type: integer
        generated_at:
          type: string
          format: date-time

    TraceIds:
      type: object
      properties:
        langfuse_session_id:
          type: string
        langfuse_trace_id:
          type: string
        jaeger_trace_id:
          type: string

  responses:
    ValidationError:
      description: Validation error
      content:
        application/json:
          schema:
            type: object
            properties:
              error:
                type: string
              details:
                type: array
                items:
                  type: object

    Unauthorized:
      description: Unauthorized
      content:
        application/json:
          schema:
            type: object
            properties:
              error:
                type: string

    NotFound:
      description: Not found
      content:
        application/json:
          schema:
            type: object
            properties:
              error:
                type: string
              message:
                type: string
```
