# Tasks: Claude Agent SDK Integration with Dapr Orchestration

**Input**: Design documents from `/specs/101-dapr-claude-code/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓

**Tests**: Not explicitly requested in specification - test tasks omitted (TDD available if needed).

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US6)
- All paths relative to repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization with Claude Agent SDK dependencies

- [X] T001 Create speckit-agents/ directory structure per plan.md
- [X] T002 Create pyproject.toml with claude-agent-sdk, dapr-client, fastapi, langfuse dependencies in speckit-agents/pyproject.toml
- [X] T003 [P] Create requirements.txt with pinned versions in speckit-agents/requirements.txt
- [X] T004 [P] Create .gitignore for Python project in speckit-agents/.gitignore
- [X] T005 [P] Create empty __init__.py files in speckit-agents/src/, speckit-agents/src/agents/, speckit-agents/src/tools/, speckit-agents/src/common/, speckit-agents/src/prompts/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that ALL user stories depend on - must complete before any agent work

**⚠️ CRITICAL**: No agent implementation can begin until this phase is complete

- [X] T006 Implement environment configuration in speckit-agents/src/common/config.py (ANTHROPIC_API_KEY, LANGFUSE_*, DAPR_* settings)
- [X] T007 Implement Pydantic models (Workflow, Artifact, WorkflowMessage, WorkflowStatus, WorkflowPhase, ArtifactType) in speckit-agents/src/common/models.py
- [X] T008 [P] Implement Kubernetes health probes (liveness, readiness with Dapr check) in speckit-agents/src/common/health.py
- [X] T009 [P] Implement Claude SDK options factory (model selection, max_turns, allowed_tools builder) in speckit-agents/src/common/claude_config.py
- [X] T010 Implement entry point dispatcher (AGENT_NAME env var routing) in speckit-agents/src/main.py
- [X] T011 Implement BaseClaudeAgent class (Dapr client init, common MCP tools registration, Langfuse context) in speckit-agents/src/agents/base.py
- [X] T012 Create multi-stage Dockerfile in speckit-agents/Dockerfile

**Checkpoint**: Foundation ready - agent and tool implementation can now begin

---

## Phase 3: User Story 5 - Custom Tools Bridge Claude and Infrastructure (Priority: P2)

**Goal**: Create MCP tools that expose Dapr infrastructure to Claude agents

**Why first**: All worker agents (US1-US3) depend on these tools being available

**Independent Test**: Invoke tool functions directly with mock Dapr client, verify correct state store/pub/sub calls

### Implementation for User Story 5

- [X] T013 [P] [US5] Implement get_workflow_state tool (Dapr state store read) in speckit-agents/src/tools/dapr_tools.py
- [X] T014 [P] [US5] Implement save_workflow_state tool (Dapr state store write) in speckit-agents/src/tools/dapr_tools.py
- [X] T015 [P] [US5] Implement publish_event tool (Dapr pub/sub publish) in speckit-agents/src/tools/dapr_tools.py
- [X] T016 [P] [US5] Implement publish_phase_complete tool (phase completion signal) in speckit-agents/src/tools/dapr_tools.py
- [X] T017 [US5] Implement get_artifact tool (file read from artifacts path) in speckit-agents/src/tools/artifact_tools.py
- [X] T018 [US5] Implement run_tests tool (pytest execution with coverage option) in speckit-agents/src/tools/test_tools.py
- [X] T019 [US5] Create dapr_mcp_server using create_sdk_mcp_server() in speckit-agents/src/tools/dapr_tools.py
- [X] T020 [US5] Create tests_mcp_server using create_sdk_mcp_server() in speckit-agents/src/tools/test_tools.py

**Checkpoint**: MCP tools ready - worker agents can now access Dapr infrastructure

---

## Phase 4: User Story 4 - Orchestrator Manages Agent Communication (Priority: P1)

**Goal**: Pure Dapr router that manages workflow lifecycle without any LLM calls

**Independent Test**: Start workflow via POST /run, verify Dapr pub/sub message sent to specifier topic

### Implementation for User Story 4

- [X] T021 [P] [US4] Create orchestrator system prompt (routing logic, no AI) in speckit-agents/src/prompts/__init__.py
- [X] T022 [US4] Implement DaprOrchestrator class (route_to_agent, handle_phase_completion) in speckit-agents/src/agents/orchestrator.py
- [X] T023 [US4] Implement FastAPI router with /run, /status/{id}, /healthz, /ready endpoints in speckit-agents/src/agents/orchestrator.py
- [X] T024 [US4] Implement Dapr pub/sub subscription handler for phase completion events in speckit-agents/src/agents/orchestrator.py
- [X] T025 [US4] Add workflow state management (create, update, get from state store) in speckit-agents/src/agents/orchestrator.py

**Checkpoint**: Orchestrator can route tasks and manage workflow state

---

## Phase 5: User Story 1 - Developer Submits Feature Request (Priority: P1) 🎯 MVP

**Goal**: Specifier agent generates spec.md from feature description using Claude SDK

**Independent Test**: Send feature description, verify spec.md generated with proper structure within 90 seconds

### Implementation for User Story 1

- [X] T026 [P] [US1] Create specifier system prompt (specification format, sections, constraints) in speckit-agents/src/prompts/specifier.py
- [X] T027 [US1] Implement ClaudeSpecifierAgent class extending BaseClaudeAgent in speckit-agents/src/agents/specifier.py
- [X] T028 [US1] Configure Claude SDK options (model, max_turns=3, tools: Read, Write, mcp__dapr__get_workflow_state) in speckit-agents/src/agents/specifier.py
- [X] T029 [US1] Implement process_task method with async query() iteration in speckit-agents/src/agents/specifier.py
- [X] T030 [US1] Implement artifact registration (spec.md path, hash, created_by) in speckit-agents/src/agents/specifier.py
- [X] T031 [US1] Add phase completion publishing via mcp__dapr__publish_phase_complete in speckit-agents/src/agents/specifier.py

**Checkpoint**: Feature request → spec.md generation fully functional (MVP!)

---

## Phase 6: User Story 2 - Planner Generates Implementation Artifacts in Parallel (Priority: P1)

**Goal**: Planner spawns parallel subagents for research.md, data-model.md, plan.md

**Independent Test**: Provide spec.md, verify 3 artifacts generated with observability traces showing parallel execution

### Implementation for User Story 2

- [X] T032 [P] [US2] Create planner main prompt (orchestration, subagent delegation) in speckit-agents/src/prompts/planner.py
- [X] T033 [P] [US2] Create research-agent subagent prompt (technology research) in speckit-agents/src/prompts/planner.py
- [X] T034 [P] [US2] Create data-modeler subagent prompt (entity design) in speckit-agents/src/prompts/planner.py
- [X] T035 [P] [US2] Create architecture-agent subagent prompt (implementation plan) in speckit-agents/src/prompts/planner.py
- [X] T036 [US2] Implement ClaudePlannerAgent class with subagents configuration in speckit-agents/src/agents/planner.py
- [X] T037 [US2] Configure parallel subagents (research-agent: haiku, data-modeler: sonnet, architecture-agent: sonnet) in speckit-agents/src/agents/planner.py
- [X] T038 [US2] Implement subagent result aggregation in speckit-agents/src/agents/planner.py
- [X] T039 [US2] Add retry logic for failed subagents (without re-running successful ones) in speckit-agents/src/agents/planner.py

**Checkpoint**: spec.md → research.md + data-model.md + plan.md in parallel

---

## Phase 7: User Story 3 - Implementer Executes Tasks with Full Tool Access (Priority: P1)

**Goal**: Implementer agent with TDD workflow using full Claude SDK tools

**Independent Test**: Provide tasks.md, verify tests written first, then implementation, with file changes tracked

### Implementation for User Story 3

- [X] T040 [P] [US3] Create task generator system prompt (task breakdown, phases, [P] markers) in speckit-agents/src/prompts/task_generator.py
- [X] T041 [US3] Implement ClaudeTaskGeneratorAgent class in speckit-agents/src/agents/task_generator.py
- [X] T042 [US3] Configure tools (Read, Write, mcp__dapr__get_artifact) in speckit-agents/src/agents/task_generator.py
- [X] T043 [P] [US3] Create implementer system prompt (TDD workflow, test-first, iterate until pass) in speckit-agents/src/prompts/implementer.py
- [X] T044 [US3] Implement ClaudeImplementerAgent class with max_turns=50 in speckit-agents/src/agents/implementer.py
- [X] T045 [US3] Configure full tool access (Read, Write, Edit, Bash, Glob, Grep, mcp__dapr__*, mcp__tests__*) in speckit-agents/src/agents/implementer.py
- [X] T046 [US3] Implement TDD iteration logic (run tests, check fail, implement, run tests, check pass) in speckit-agents/src/agents/implementer.py
- [X] T047 [US3] Implement task completion tracking (mark tasks done in tasks.md) in speckit-agents/src/agents/implementer.py

**Checkpoint**: Full workflow from tasks.md to implemented code with TDD

---

## Phase 8: User Story 6 - Observability Tracks AI Calls Across Agents (Priority: P2)

**Goal**: All Claude API calls traced in Langfuse with workflow ID session grouping

**Independent Test**: Run complete workflow, verify all AI calls grouped under single session ID

### Implementation for User Story 6

- [X] T048 [P] [US6] Implement Langfuse client initialization with graceful degradation in speckit-agents/src/common/config.py
- [X] T049 [US6] Add trace creation with workflow_id as session_id in BaseClaudeAgent in speckit-agents/src/agents/base.py
- [X] T050 [US6] Implement generation span wrapping for query() calls in speckit-agents/src/agents/base.py
- [X] T051 [US6] Add trace context propagation via WorkflowMessage.context in speckit-agents/src/agents/base.py
- [X] T052 [US6] Implement child span creation for subagent calls in planner in speckit-agents/src/agents/planner.py
- [X] T053 [US6] Add error context logging to traces on failures in speckit-agents/src/agents/base.py

**Checkpoint**: Full observability - all AI calls visible in Langfuse grouped by workflow

---

## Phase 9: Infrastructure Updates

**Purpose**: CDK8s chart updates and Kubernetes deployment

- [X] T054 [P] Update dapr-components-chart.ts to remove anthropic/openai conversation components in cdk8s/charts/infra/dapr-components-chart.ts
- [X] T055 [P] Update speckit-agents-chart.ts environment variables (remove CONVERSATION_COMPONENT, keep ANTHROPIC_API_KEY) in cdk8s/charts/apps/speckit-agents-chart.ts
- [X] T056 Verify Dapr components (workflowstatestore, messagepubsub) still work after updates in cdk8s/charts/infra/dapr-components-chart.ts

**Checkpoint**: Kubernetes deployment ready

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, validation, and final integration

- [X] T057 Remove unused observability.py (replaced by Langfuse in base.py) from speckit-agents/src/common/
- [X] T058 [P] Add type hints to all public functions across speckit-agents/src/
- [X] T059 Verify full workflow: /run → specifier → planner → task-generator → implementer
- [X] T060 Run quickstart.md validation (deploy, start workflow, check status, view artifacts)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Story 5 (Phase 3)**: Depends on Foundational - BLOCKS US1-US4 (tools needed by agents)
- **User Story 4 (Phase 4)**: Depends on US5 (needs Dapr tools)
- **User Story 1 (Phase 5)**: Depends on US5 (needs MCP tools) - MVP!
- **User Story 2 (Phase 6)**: Depends on US1 (planner needs specifier to produce spec.md)
- **User Story 3 (Phase 7)**: Depends on US2 (implementer needs planner artifacts)
- **User Story 6 (Phase 8)**: Can start after Foundational, integrates with all agents
- **Infrastructure (Phase 9)**: Can run in parallel with agent implementation
- **Polish (Phase 10)**: Depends on all user stories complete

### User Story Dependencies

```
Setup → Foundational → US5 (Tools) → US4 (Orchestrator) → US1 (Specifier) → US2 (Planner) → US3 (Implementer)
                                                                                                    ↑
                                                     US6 (Observability) ─────────────────────────────┘
```

### Parallel Opportunities

**Within Phase 1 (Setup)**:
- T003, T004, T005 can run in parallel

**Within Phase 2 (Foundational)**:
- T008, T009 can run in parallel

**Within Phase 3 (US5 - Tools)**:
- T013, T014, T015, T016 can run in parallel (different tool functions)

**Within Phase 6 (US2 - Planner)**:
- T032, T033, T034, T035 can run in parallel (different prompt files)

**Within Phase 7 (US3 - Implementer)**:
- T040, T043 can run in parallel (different prompt files)

**Infrastructure (Phase 9)**:
- T054, T055 can run in parallel (different chart files)

---

## Parallel Example: User Story 5 Tools

```bash
# Launch all tool implementations together:
Task: "Implement get_workflow_state tool in speckit-agents/src/tools/dapr_tools.py"
Task: "Implement save_workflow_state tool in speckit-agents/src/tools/dapr_tools.py"
Task: "Implement publish_event tool in speckit-agents/src/tools/dapr_tools.py"
Task: "Implement publish_phase_complete tool in speckit-agents/src/tools/dapr_tools.py"
```

---

## Implementation Strategy

### MVP First (User Stories 4, 5, 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: US5 (Tools) - needed by all agents
4. Complete Phase 4: US4 (Orchestrator) - workflow routing
5. Complete Phase 5: US1 (Specifier) - generates spec.md
6. **STOP and VALIDATE**: Submit feature request, verify spec.md generated
7. Deploy/demo if ready

### Full Workflow

1. Setup → Foundational → Tools ready
2. Add Orchestrator → Workflow routing ready
3. Add Specifier → MVP! Test independently
4. Add Planner → Parallel artifact generation
5. Add Task Generator + Implementer → Full workflow
6. Add Observability → Production monitoring
7. Infrastructure updates → Deploy to Kubernetes

### Key Performance Targets

| Phase | Target | Agent(s) |
|-------|--------|----------|
| Specification | <2 minutes | Specifier |
| Planning | <4 minutes (40% faster) | Planner + subagents |
| 10 concurrent workflows | No degradation | All agents |

---

## Notes

- [P] tasks = different files, no dependencies
- [US?] label maps task to specific user story
- Tools (US5) must complete before any agent implementation
- Orchestrator has NO Claude SDK - pure Dapr routing
- Claude SDK reads ANTHROPIC_API_KEY directly from environment
- Langfuse integration gracefully degrades if unavailable
- Commit after each task or logical group
- Stop at any checkpoint to validate independently
