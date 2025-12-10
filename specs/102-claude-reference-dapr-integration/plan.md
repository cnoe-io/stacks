# Implementation Plan: Claude SDK + Dapr Multi-Agent Integration with Full Observability

**Branch**: `102-claude-reference-dapr-integration` | **Date**: 2025-12-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/102-claude-reference-dapr-integration/spec.md`

## Summary

Replace the existing Dapr multi-agent system with Claude Agent SDK-based agents while retaining Dapr for workflow orchestration. Each specialized agent (Orchestrator, Specifier, Planner, TaskGenerator, Implementer) uses the Claude SDK streaming interface for LLM interactions, with Langfuse capturing all generations/tool calls and Jaeger providing distributed tracing across the Dapr pub/sub messaging layer.

## Technical Context

**Language/Version**: Python 3.11+
**Primary Dependencies**:
- `claude-code-sdk` (Claude Agent SDK for LLM interactions)
- `dapr-agents` (Dapr integration: DurableAgent, AgentPubSubConfig, AgentStateConfig, AgentRegistryConfig)
- `langfuse` (LLM observability)
- `opentelemetry-api`, `opentelemetry-sdk` (Jaeger trace propagation)
- `pydantic` (Data validation)
- `fastapi` (REST API for workflow initiation)
**Storage**: Redis (Dapr state store and pub/sub backend)
**Testing**: pytest with pytest-asyncio
**Target Platform**: Kubernetes with Dapr sidecar injection
**Project Type**: Single project (multi-service deployment via Kubernetes)
**Performance Goals**: Process simple workflow (4 phases, ~20 LLM calls) within 50 minutes total
**Constraints**: Phase timeouts (Specifier 5min, Planner 10min, TaskGenerator 5min, Implementer 30min), 5 concurrent workflows per agent
**Scale/Scope**: Single cluster deployment, 5 agent services + 1 orchestrator

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| I. Claude SDK Agent Architecture | ✅ PASS | Using ClaudeSDKClient with streaming, message blocks |
| II. Dapr Integration for Orchestration | ✅ PASS | Using Dapr pub/sub, state stores, topic patterns |
| III. Comprehensive Observability | ✅ PASS | Langfuse for LLM traces, Jaeger for distributed tracing |
| IV. Workflow State Management | ✅ PASS | Unique workflow IDs, phase tracking, retry logic |
| V. Phase-Specific Timeout Enforcement | ✅ PASS | Per-phase timeouts defined in spec |
| VI. API Security Standards | ✅ PASS | API key auth via Azure Key Vault + ESO |
| VII. Kubernetes-Native Deployment | ✅ PASS | cdk8s charts, ArgoCD GitOps |
| VIII. Test-Driven Development | ✅ PASS | Contract, integration, e2e tests planned |
| IX. Forward-Only Development | ✅ PASS | Full replacement, no backward compatibility |
| X. Documentation as Code | ✅ PASS | Contracts, data models, quickstart documented |

## Project Structure

### Documentation (this feature)

```
specs/102-claude-reference-dapr-integration/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── workflow-api.md  # REST API contract
│   ├── dapr-pubsub.md   # Pub/sub message contracts
│   └── dapr-state.md    # State store contracts
├── tasks.md             # Phase 2 output
└── checklists/
    └── requirements.md  # Checklist (completed)
```

### Source Code (repository root)

```
src/
├── agents/              # Claude SDK-based agent implementations
│   ├── base/            # Base agent class with Langfuse integration
│   │   ├── __init__.py
│   │   └── claude_agent.py    # Base ClaudeSDKClient wrapper with observability
│   ├── orchestrator/    # Workflow orchestrator (phase routing)
│   │   ├── __init__.py
│   │   └── app.py
│   ├── specifier/       # Specification agent
│   │   ├── __init__.py
│   │   └── app.py
│   ├── planner/         # Planning agent (with subagents)
│   │   ├── __init__.py
│   │   └── app.py
│   ├── task_generator/  # Task generation agent
│   │   ├── __init__.py
│   │   └── app.py
│   └── implementer/     # Implementation agent
│       ├── __init__.py
│       └── app.py
├── models/              # Pydantic data models
│   ├── __init__.py
│   ├── workflow.py      # Workflow, Phase, Status models
│   ├── messages.py      # Dapr pub/sub message models
│   └── artifacts.py     # Artifact reference models
├── services/            # Shared services
│   ├── __init__.py
│   ├── langfuse_client.py    # Langfuse integration
│   ├── tracing.py            # Jaeger/OpenTelemetry integration
│   └── state_manager.py      # Dapr state store wrapper
├── api/                 # REST API for workflow initiation
│   ├── __init__.py
│   ├── main.py          # FastAPI app
│   ├── routes/
│   │   ├── __init__.py
│   │   └── workflows.py # /run, /workflows/{id}/status endpoints
│   └── auth.py          # API key authentication
└── lib/                 # Utilities
    ├── __init__.py
    └── config.py        # Environment configuration

tests/
├── contract/            # API contract tests
│   ├── test_workflow_api.py
│   └── test_dapr_messages.py
├── integration/         # Dapr integration tests
│   ├── test_pubsub.py
│   └── test_state_store.py
└── e2e/                 # End-to-end workflow tests
    └── test_workflow_execution.py

cdk8s/
├── charts/
│   ├── apps/
│   │   └── speckit-agents-chart.ts    # Agent deployment chart
│   ├── secrets/
│   │   └── speckit-agents-secrets-chart.ts  # ESO secrets
│   └── infra/
│       └── dapr-components-chart.ts   # Dapr components (pub/sub, state)
└── config/
    └── applications.ts  # Add speckit-agents application config
```

**Structure Decision**: Single project structure with multiple agent services deployed as separate Kubernetes pods. All agents share common base classes and models. cdk8s charts follow existing repository patterns.

## Complexity Tracking

*No violations identified - design follows constitution guidelines.*

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Langfuse + Jaeger | Two observability systems | Required by spec - Langfuse for LLM-specific traces, Jaeger for distributed infrastructure tracing |
| 5 Agent Services | Separate deployments | Each agent has distinct responsibility and scales independently |
| Claude SDK + Dapr | Dual integration | Claude SDK for LLM, Dapr for orchestration - clean separation of concerns |

---

## Phase 0: Research

*Research findings documented in [research.md](./research.md)*

### Research Questions

1. **Claude Agent SDK Integration**
   - How to wrap `ClaudeSDKClient` with Langfuse observability?
   - Streaming response handling: `receive_response()` → message blocks
   - Tool registration and invocation patterns
   - Security hooks for command allowlisting

2. **Dapr Agent Patterns**
   - `DurableAgent` configuration classes: `AgentProfileConfig`, `AgentPubSubConfig`, `AgentStateConfig`, `AgentRegistryConfig`
   - Pub/sub topic naming: `{team_name}.{agent_name}.requests`
   - State store key prefixing for isolation
   - Agent registry for discovery

3. **Observability Integration**
   - Langfuse Python SDK: `langfuse.trace()`, `langfuse.generation()`, `langfuse.span()`
   - Session grouping via `session_id`
   - Tool call recording
   - W3C traceparent propagation for Jaeger

4. **Kubernetes Deployment**
   - Dapr sidecar injection annotations
   - External Secrets Operator patterns (from existing cdk8s charts)
   - Sync wave ordering for dependencies

---

## Phase 1: Design

### Data Model

*Detailed in [data-model.md](./data-model.md)*

**Key Entities:**
- `Workflow`: ID, description, current_phase, status, artifacts, timestamps, trace_ids
- `Phase`: type (SPEC/PLAN/TASKS/IMPL), status, started_at, completed_at, retry_count
- `Artifact`: type, content_hash, storage_ref, generating_agent
- `AgentMessage`: Dapr pub/sub message envelope
- `ToolInvocation`: tool_name, inputs, outputs, duration, error_status

### API Contracts

*Detailed in [contracts/](./contracts/)*

**REST API:**
- `POST /run` - Initiate workflow, returns workflow_id
- `GET /workflows/{id}/status` - Query workflow state

**Dapr Pub/Sub Topics:**
- `speckit.orchestrator.requests` - Workflow initiation
- `speckit.specifier.requests` - Specification phase
- `speckit.planner.requests` - Planning phase
- `speckit.taskgenerator.requests` - Task generation phase
- `speckit.implementer.requests` - Implementation phase
- `speckit.broadcast` - Team-wide broadcasts

**Dapr State Store Keys:**
- `workflow:{id}` - Workflow state
- `{agent}:state:{id}` - Agent-specific state

### Quickstart

*Detailed in [quickstart.md](./quickstart.md)*

Steps:
1. Deploy Dapr components (Redis, pub/sub, state stores)
2. Deploy Langfuse and Jaeger
3. Configure External Secrets for API keys
4. Deploy agent services via ArgoCD
5. Verify agent registration
6. Submit test workflow
7. Verify traces in Langfuse and Jaeger

---

## Phase 2: Tasks

*Generated via `/speckit.tasks` command after design approval.*
