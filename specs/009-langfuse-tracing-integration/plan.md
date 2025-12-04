# Implementation Plan: Langfuse Tracing Integration for SpecKit

**Branch**: `009-langfuse-tracing-integration` | **Date**: 2024-12-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-langfuse-tracing-integration/spec.md`

## Summary

Add Langfuse tracing to dapr-agents to capture LLM observability data. The infrastructure (Langfuse server, secrets, basic observability module) already exists from feature 100-dapr-agent-speckit. This feature completes the integration by instrumenting actual LLM calls made through the dapr-agents SDK's `DurableAgent` and `OpenAIChatClient`, ensuring traces appear in Langfuse with prompt/response text, token counts, latency, and workflow correlation.

## Technical Context

**Language/Version**: Python 3.11+ (existing speckit-agents codebase)
**Primary Dependencies**:
- `dapr-agents>=0.10.0` (SDK handles LLM calls via DurableAgent)
- `langfuse>=2.50.0` (already in requirements.txt)
- `OpenAIChatClient` from dapr-agents (actual LLM client)
- `anthropic>=0.30.0` (Claude SDK)

**Storage**: Redis-backed Dapr state stores (existing)
**Testing**: Manual verification via Langfuse UI (pytest for unit tests)
**Target Platform**: Kubernetes (dapr-agents namespace)
**Project Type**: Single project (Python backend)
**Performance Goals**: Traces appear in Langfuse within 30 seconds
**Constraints**: <50ms overhead per LLM call for tracing
**Scale/Scope**: 5 agents (orchestrator, specifier, planner, task-generator, implementer)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Tracing module already isolated in `src/common/observability.py` |
| III. Test-Before-Apply | ✅ PASS | Will verify via manual testing against Langfuse UI |
| VI. Declarative Configuration | ✅ PASS | Environment variables for Langfuse config |
| X. Python Development Standards | ✅ PASS | async/await, type hints, Pydantic models |
| XII. Forward-Only Development | ✅ PASS | Building on existing observability module, no backwards compatibility needed |
| XIV. Test-Driven Development | ⚠️ PARTIAL | LLM tracing difficult to unit test; will use integration testing via Langfuse UI |

**Gate Result**: PASS - No blocking violations. TDD principle has justified deviation (external service integration).

## Project Structure

### Documentation (this feature)

```
specs/009-langfuse-tracing-integration/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
speckit-agents/
├── src/
│   ├── agents/
│   │   ├── base.py              # BaseAgent class with Langfuse integration
│   │   ├── orchestrator.py      # Central workflow coordinator
│   │   ├── specifier.py         # Specification writer agent
│   │   ├── planner.py           # Implementation planner agent
│   │   ├── task_generator.py    # Task breakdown agent
│   │   └── implementer.py       # Code implementer agent
│   ├── common/
│   │   ├── observability.py     # Langfuse integration module (EXTEND)
│   │   ├── traced_llm_client.py # NEW: Wrapped LLM client with tracing
│   │   ├── config.py            # Configuration loading
│   │   └── models.py            # Pydantic models
│   └── main.py                  # Agent entrypoint
├── requirements.txt             # Python dependencies
└── pyproject.toml               # Package configuration

tests/
├── unit/
│   └── test_observability.py    # Unit tests for tracing utilities
└── integration/
    └── test_langfuse_traces.py  # Integration tests for trace verification
```

**Structure Decision**: Extend existing `src/common/observability.py` and create new `src/common/traced_llm_client.py` to wrap the `OpenAIChatClient` with Langfuse instrumentation. This follows the modular composition principle by adding a single responsibility module.

## Post-Design Constitution Check

*Re-evaluated after Phase 1 design artifacts.*

| Principle | Status | Post-Design Notes |
|-----------|--------|-------------------|
| I. Modular Composition | ✅ PASS | Design adds `traced_llm_client.py` as single-responsibility module |
| III. Test-Before-Apply | ✅ PASS | quickstart.md includes verification steps |
| VI. Declarative Configuration | ✅ PASS | All config via LANGFUSE_* environment variables |
| X. Python Development Standards | ✅ PASS | Pydantic models defined in data-model.md, async patterns used |
| XII. Forward-Only Development | ✅ PASS | Extends existing observability.py, no legacy compatibility |
| XIV. Test-Driven Development | ⚠️ PARTIAL | Unit tests for data models; integration via Langfuse UI for LLM calls |

**Post-Design Gate Result**: PASS - Design adheres to constitution. TDD deviation documented and justified.

## Complexity Tracking

*No violations requiring justification.*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | N/A | N/A |

## Generated Artifacts Summary

| Artifact | Path | Description |
|----------|------|-------------|
| Research | `specs/009-langfuse-tracing-integration/research.md` | LLM instrumentation patterns, Langfuse SDK usage |
| Data Model | `specs/009-langfuse-tracing-integration/data-model.md` | Trace, Generation, TraceContext entities |
| Contract | `specs/009-langfuse-tracing-integration/contracts/observability-extensions.py` | TracedAgentInterface, TracedOrchestratorInterface |
| Quickstart | `specs/009-langfuse-tracing-integration/quickstart.md` | Implementation steps, verification, troubleshooting |
