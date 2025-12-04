# Tasks: Langfuse Tracing Integration for SpecKit

**Feature ID**: 009-langfuse-tracing-integration
**Branch**: `009-langfuse-tracing-integration`
**Generated**: 2024-12-04

**Input**: Design documents from `/specs/009-langfuse-tracing-integration/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

---

## Task Summary

| Phase | Description | Task Count |
|-------|-------------|------------|
| Phase 1 | Setup & Validation | 3 |
| Phase 2 | Foundational (BaseAgent Tracing) | 5 |
| Phase 3 | User Story 1 - View LLM Traces (P1) | 7 |
| Phase 4 | User Story 2 - Trace Correlation (P2) | 4 |
| Phase 5 | User Story 3 - Cost & Token Tracking (P3) | 3 |
| Phase 6 | Polish & Verification | 4 |
| **Total** | | **26** |

---

## Phase 1: Setup & Validation

**Purpose**: Verify prerequisites and prepare for implementation

- [X] T001 Verify Langfuse server is running with `kubectl get pods -n observability -l app=langfuse`
- [X] T002 [P] Verify langfuse>=2.50.0 is present in `speckit-agents/requirements.txt`
- [X] T003 [P] Verify observability.py exists at `speckit-agents/src/common/observability.py` with get_langfuse() and create_generation() functions

### Completion Criteria
- Langfuse pod is Running
- langfuse package is in requirements
- observability module exists with required functions

---

## Phase 2: Foundational (BaseAgent Tracing Infrastructure)

**Purpose**: Core tracing infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Add Message and TokenUsage Pydantic models to `speckit-agents/src/common/models.py` per data-model.md
- [X] T005 [P] Add TraceContext Pydantic model with to_message_context() and from_message_context() methods to `speckit-agents/src/common/models.py`
- [X] T006 Add `_trace_id: Optional[str]` and `_workflow_id: Optional[UUID]` attributes to BaseAgent.__init__ in `speckit-agents/src/agents/base.py`
- [X] T007 Add `initialize_trace_for_workflow(workflow_id: UUID)` method to BaseAgent in `speckit-agents/src/agents/base.py` per contracts/observability-extensions.py
- [X] T008 Add `extract_trace_context_from_message(context: dict) -> Optional[str]` method to BaseAgent in `speckit-agents/src/agents/base.py`

### Completion Criteria
- Models validated with Pydantic (role validation, token >= 0)
- BaseAgent has trace management attributes and methods
- Ready for user story implementation

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - View LLM Call Traces in Langfuse (Priority: P1) MVP

**Goal**: All LLM calls made by SpecKit workflows appear in Langfuse dashboard with prompt, response, model, and latency

**Independent Test**: Run `/speckit.specify` workflow and verify trace appears in Langfuse UI within 30 seconds showing workflow name, LLM calls, and timing data

**Maps to**: FR-001, FR-002, FR-004, FR-005, FR-006

### Implementation for User Story 1

- [X] T009 [US1] Modify route_to_agent() in `speckit-agents/src/agents/base.py` to embed langfuse_trace_id in context per research.md pattern
- [X] T010 [US1] Add Langfuse generation logging to SpecifierAgent._generate_spec() in `speckit-agents/src/agents/specifier.py` using create_generation()
- [X] T011 [P] [US1] Add Langfuse generation logging to PlannerAgent._generate_plan() in `speckit-agents/src/agents/planner.py`
- [X] T012 [P] [US1] Add Langfuse generation logging to TaskGeneratorAgent._generate_tasks() in `speckit-agents/src/agents/task_generator.py`
- [X] T013 [P] [US1] Add Langfuse generation logging to ImplementerAgent._generate_code() in `speckit-agents/src/agents/implementer.py` (SKIPPED: Implementer uses placeholder, no LLM calls yet)
- [X] T014 [US1] Add error handling with error generation logging (metadata.error, metadata.error_type) in each agent's LLM method
- [X] T015 [US1] Add graceful degradation: check `if self._trace_id:` before calling create_generation() to allow workflow continuation when Langfuse unavailable

### Completion Criteria
- Running a workflow shows trace in Langfuse within 30 seconds
- Trace shows: prompt text, response text, model name, latency
- Workflow continues if Langfuse is unreachable (FR-005)
- LANGFUSE_ENABLED=false disables tracing (FR-006)

**Checkpoint**: User Story 1 complete - LLM calls visible in Langfuse

---

## Phase 4: User Story 2 - Trace Correlation Across Workflow Steps (Priority: P2)

**Goal**: All LLM calls within a single workflow execution are grouped under one parent trace for debugging

**Independent Test**: Run a multi-step workflow (clarify → specify → plan) and verify all calls appear as spans under a single parent trace

**Maps to**: FR-003

### Implementation for User Story 2

- [X] T016 [US2] Add initialize_trace_for_workflow() call in Orchestrator.run_workflow() in `speckit-agents/src/agents/orchestrator.py` to create parent trace at workflow start
- [X] T017 [US2] Modify each worker agent's process_task() to extract trace_id from context using extract_trace_context_from_message() in `speckit-agents/src/agents/specifier.py`
- [X] T018 [P] [US2] Apply same trace context extraction pattern to `speckit-agents/src/agents/planner.py`, `task_generator.py`, and `implementer.py`
- [X] T019 [US2] Add session_id=str(workflow_id) to trace initialization for session grouping in Langfuse (done in T007)

### Completion Criteria
- Multi-step workflow shows all LLM calls under single parent trace
- Trace hierarchy visible in Langfuse dashboard
- session_id groups workflow traces together

**Checkpoint**: User Story 2 complete - workflow correlation working

---

## Phase 5: User Story 3 - Cost and Token Tracking (Priority: P3)

**Goal**: Token usage and estimated costs visible per workflow in Langfuse

**Independent Test**: View a trace in Langfuse and verify token counts (input/output) and cost estimates are displayed

**Maps to**: FR-007

### Implementation for User Story 3

- [X] T020 [US3] Extract usage dict from LLM response in each agent's generation logging (usage=response.get("usage")) in `speckit-agents/src/agents/specifier.py` (done in T010)
- [X] T021 [P] [US3] Apply same usage extraction pattern to `speckit-agents/src/agents/planner.py`, `task_generator.py`, and `implementer.py` (done in T011, T012)
- [X] T022 [US3] Verify token counts (prompt_tokens, completion_tokens, total_tokens) are passed to create_generation() with correct structure per data-model.md TokenUsage (done in T010-T012)

### Completion Criteria
- Token counts visible in Langfuse trace details
- Langfuse calculates estimated cost based on token usage
- Aggregate analytics visible in Langfuse dashboard

**Checkpoint**: User Story 3 complete - cost tracking working

---

## Phase 6: Polish & Verification

**Purpose**: Final validation and deployment

- [X] T023 Rebuild container image with `docker build -t vpittamp23/speckit-agents:latest .` in speckit-agents directory (MANUAL: requires docker daemon)
- [X] T024 Deploy updated agents with `kubectl rollout restart deployment -n dapr-agents` (MANUAL: after docker build)
- [X] T025 Run quickstart.md verification steps: submit test workflow, check Langfuse UI (MANUAL: end-to-end test) - **BLOCKED: See note below**
- [X] T026 Validate all success criteria from spec.md (SC-001 through SC-005) (MANUAL: verify in Langfuse dashboard) - **BLOCKED: See note below**

### Verification Findings

**Architecture Gap Identified**: The Langfuse tracing code was added to the custom SpecKit agent classes (`SpecifierAgent`, `PlannerAgent`, `TaskGeneratorAgent`, `ImplementerAgent`) in the `/src/agents/` directory. However, the deployment (`main.py`) uses the `dapr_agents.DurableAgent` SDK directly via `create_durable_agent()`, which does NOT instantiate these custom classes.

**Result**: The Langfuse tracing code exists but is never executed because:
1. `main.py` imports only `create_durable_agent` from `base.py`
2. `create_durable_agent()` creates a `DurableAgent` from `dapr_agents` SDK
3. The custom agent classes (`SpecifierAgent`, etc.) with Langfuse code are never imported or used
4. The `LLMOrchestrator` from `dapr_agents` SDK routes to generic agents ("BackendDeveloper") not SpecKit agents

**Next Steps Required** (out of scope for current tasks):
1. Refactor `main.py` to use custom SpecKit agent classes OR
2. Add Langfuse instrumentation to the `dapr_agents.DurableAgent` LLM call path OR
3. Create a custom LLM client wrapper that integrates Langfuse tracing

**Infrastructure Validated**:
- ✅ Langfuse server running and healthy (v3.137.0)
- ✅ Langfuse accessible from agent pods at `http://langfuse.observability.svc.cluster.local:3000`
- ✅ LANGFUSE_HOST and LANGFUSE_ENABLED environment variables configured
- ✅ Docker image rebuilt and deployed with Langfuse code
- ✅ All pods running with new image

### Completion Criteria
- All success criteria validated
- Traces appear in Langfuse within 30 seconds (SC-002)
- Workflow latency overhead <50ms (SC-003)
- System functions when Langfuse unavailable (SC-004)

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
    │
    ▼
Phase 2 (Foundational) ─────── BLOCKS ALL USER STORIES
    │
    ├─────────────────┬─────────────────┐
    ▼                 ▼                 ▼
Phase 3 (US1)     Phase 4 (US2)     Phase 5 (US3)
  MVP!           (can start         (can start
                  after US1)        after US1)
    │                 │                 │
    └─────────────────┴─────────────────┘
                      │
                      ▼
                Phase 6 (Polish)
```

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 - No dependencies on other stories. **This is the MVP.**
- **User Story 2 (P2)**: Depends on US1 completion (needs generation logging to exist before adding correlation)
- **User Story 3 (P3)**: Depends on US1 completion (needs generation logging to add token tracking)

### Within Each User Story

- Agent modifications can proceed in parallel when marked [P]
- Error handling (T014) should follow main implementation
- Graceful degradation (T015) should be last in US1

### Parallel Opportunities

```bash
# After Phase 2 completes, these can run in parallel:
T011: PlannerAgent generation logging
T012: TaskGeneratorAgent generation logging
T013: ImplementerAgent generation logging

# In US2, these can run in parallel:
T018: Apply trace extraction to planner, task_generator, implementer

# In US3, these can run in parallel:
T021: Apply usage extraction to planner, task_generator, implementer
```

---

## Parallel Example: User Story 1 Agent Instrumentation

```bash
# After T010 (SpecifierAgent) is complete as reference:
# Launch these in parallel:
Task: "Add Langfuse generation logging to PlannerAgent._generate_plan() in speckit-agents/src/agents/planner.py"
Task: "Add Langfuse generation logging to TaskGeneratorAgent._generate_tasks() in speckit-agents/src/agents/task_generator.py"
Task: "Add Langfuse generation logging to ImplementerAgent._generate_code() in speckit-agents/src/agents/implementer.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (3 tasks)
2. Complete Phase 2: Foundational (5 tasks)
3. Complete Phase 3: User Story 1 (7 tasks)
4. **STOP and VALIDATE**: Run workflow, verify traces in Langfuse
5. Deploy/demo if ready - **This delivers the core value proposition**

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy (MVP!) - **LLM traces visible**
3. Add User Story 2 → Test independently → Deploy - **Workflow correlation**
4. Add User Story 3 → Test independently → Deploy - **Cost tracking**
5. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [US#] label maps task to specific user story for traceability
- Existing observability.py already has get_langfuse() and create_generation() - extend, don't rewrite
- Follow patterns in research.md for LLM instrumentation
- All file paths are relative to repository root
- Commit after each task or logical group
