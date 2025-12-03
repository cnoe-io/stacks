# Tasks: SpecKit Multi-Agent Workflow System

**Input**: Design documents from `/specs/100-dapr-agent-speckit/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Test tasks are NOT included unless explicitly requested. Focus is on implementation.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4, US5)
- Include exact file paths in descriptions

## Path Conventions
Based on plan.md structure:
- Source: `speckit-agents/src/`
- Tests: `speckit-agents/tests/`
- Config: `speckit-agents/` (root level files)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create project directory structure per plan.md in speckit-agents/
- [X] T002 Create pyproject.toml with dependencies (dapr-agents, fastapi, uvicorn, anthropic, pydantic, python-dotenv) in speckit-agents/pyproject.toml
- [X] T003 [P] Create requirements.txt with pinned versions in speckit-agents/requirements.txt
- [X] T004 [P] Create .gitignore for Python project in speckit-agents/.gitignore
- [X] T005 [P] Create src/__init__.py with version info in speckit-agents/src/__init__.py
- [X] T006 [P] Create src/common/__init__.py in speckit-agents/src/common/__init__.py
- [X] T007 [P] Create src/agents/__init__.py in speckit-agents/src/agents/__init__.py
- [X] T008 [P] Create src/prompts/__init__.py in speckit-agents/src/prompts/__init__.py

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T009 Implement environment config with validation in speckit-agents/src/common/config.py
- [X] T010 [P] Implement Pydantic models (Workflow, WorkflowStatus, WorkflowPhase) in speckit-agents/src/common/models.py
- [X] T011 [P] Implement Pydantic models (Agent, AgentStatus, Artifact, ArtifactType) in speckit-agents/src/common/models.py
- [X] T012 [P] Implement Pydantic models (Task, TaskPhase, TaskStatus, WorkflowMessage) in speckit-agents/src/common/models.py
- [X] T013 Implement health and readiness endpoints with Dapr check in speckit-agents/src/common/health.py
- [X] T014 Implement base agent class with common Dapr configuration in speckit-agents/src/agents/base.py
- [X] T015 Implement main.py entrypoint with AGENT_NAME selection in speckit-agents/src/main.py

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Submit Feature Request (Priority: P1) 🎯 MVP

**Goal**: Developer submits natural language feature description and receives structured spec.md

**Independent Test**: Send feature description via HTTP POST to /run, verify spec.md generated

### Implementation for User Story 1

- [X] T016 [P] [US1] Create specifier agent prompts (system prompt, spec template) in speckit-agents/src/prompts/specifier.py
- [X] T017 [US1] Implement Specifier DurableAgent with spec.md generation in speckit-agents/src/agents/specifier.py
- [X] T018 [US1] Implement LLM Orchestrator with /run endpoint in speckit-agents/src/agents/orchestrator.py
- [X] T019 [US1] Add artifact storage utility for writing spec.md in speckit-agents/src/common/artifacts.py
- [X] T020 [US1] Add workflow state management for specifier phase in speckit-agents/src/agents/specifier.py

**Checkpoint**: User Story 1 complete - can submit feature request and receive spec.md

---

## Phase 4: User Story 2 - Generate Implementation Plan (Priority: P1)

**Goal**: After spec.md created, system generates plan.md, research.md, data-model.md

**Independent Test**: Provide spec.md, verify plan artifacts generated

### Implementation for User Story 2

- [X] T021 [P] [US2] Create planner agent prompts (plan template, research template, data-model template) in speckit-agents/src/prompts/planner.py
- [X] T022 [US2] Implement Planner DurableAgent with multi-artifact generation in speckit-agents/src/agents/planner.py
- [X] T023 [US2] Add orchestrator routing logic for planning phase in speckit-agents/src/agents/orchestrator.py
- [X] T024 [US2] Add artifact storage for plan.md, research.md, data-model.md in speckit-agents/src/common/artifacts.py
- [X] T025 [US2] Add workflow state management for planner phase in speckit-agents/src/agents/planner.py

**Checkpoint**: User Story 2 complete - can generate implementation plan artifacts

---

## Phase 5: User Story 3 - Generate Task Breakdown (Priority: P1)

**Goal**: System converts plan into dependency-ordered tasks.md

**Independent Test**: Provide plan.md, verify tasks.md generated with proper structure

### Implementation for User Story 3

- [X] T026 [P] [US3] Create task generator prompts (tasks template, phase structure) in speckit-agents/src/prompts/task_generator.py
- [X] T027 [US3] Implement TaskGenerator DurableAgent with tasks.md generation in speckit-agents/src/agents/task_generator.py
- [X] T028 [US3] Add orchestrator routing logic for task generation phase in speckit-agents/src/agents/orchestrator.py
- [X] T029 [US3] Add artifact storage for tasks.md in speckit-agents/src/common/artifacts.py
- [X] T030 [US3] Add workflow state management for task-generator phase in speckit-agents/src/agents/task_generator.py

**Checkpoint**: User Story 3 complete - can generate task breakdown

---

## Phase 6: User Story 4 - Execute Implementation Tasks (Priority: P2)

**Goal**: System executes tasks from tasks.md in order, generating code

**Independent Test**: Provide tasks.md, verify implementer executes and marks tasks complete

### Implementation for User Story 4

- [ ] T031 [P] [US4] Create implementer agent prompts (code generation, test generation) in speckit-agents/src/prompts/implementer.py
- [ ] T032 [US4] Implement Implementer DurableAgent with task execution logic in speckit-agents/src/agents/implementer.py
- [ ] T033 [US4] Add task parsing and dependency ordering in speckit-agents/src/agents/implementer.py
- [ ] T034 [US4] Add orchestrator routing logic for implementation phase in speckit-agents/src/agents/orchestrator.py
- [ ] T035 [US4] Add task completion marking (update tasks.md with [X]) in speckit-agents/src/agents/implementer.py
- [ ] T036 [US4] Add workflow state management for implementer phase in speckit-agents/src/agents/implementer.py

**Checkpoint**: User Story 4 complete - can execute implementation tasks

---

## Phase 7: User Story 5 - Monitor Workflow Progress (Priority: P2)

**Goal**: Users can observe workflow state and active agent

**Independent Test**: Start workflow, query state store, verify status returned

### Implementation for User Story 5

- [ ] T037 [P] [US5] Add /status/{workflow_id} endpoint to orchestrator in speckit-agents/src/agents/orchestrator.py
- [ ] T038 [US5] Implement workflow status query from state store in speckit-agents/src/agents/orchestrator.py
- [ ] T039 [US5] Add broadcast topic publishing for status updates in speckit-agents/src/agents/base.py
- [ ] T040 [US5] Add progress percentage calculation in speckit-agents/src/common/models.py

**Checkpoint**: User Story 5 complete - can monitor workflow progress

---

## Phase 8: Container & Deployment

**Purpose**: Package agents as container image and deploy to cluster

- [X] T041 Create multi-stage Dockerfile in speckit-agents/Dockerfile
- [X] T042 Create .dockerignore in speckit-agents/.dockerignore
- [X] T043 Build and load container image into Kind cluster
- [ ] T044 Restart speckit-agents deployments in cluster to pull new image
- [ ] T045 Verify agents start and register in Dapr dashboard

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T046 [P] Add error handling with exponential backoff in speckit-agents/src/agents/base.py
- [ ] T047 [P] Add structured logging across all agents in speckit-agents/src/common/logging.py
- [ ] T048 Run quickstart.md validation - test complete workflow in cluster
- [ ] T049 [P] Add README.md with local development instructions in speckit-agents/README.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 (P1): Orchestrator + Specifier
  - US2 (P1): Planner (depends on US1 being testable)
  - US3 (P1): Task Generator (depends on US2 being testable)
  - US4 (P2): Implementer (depends on US3 being testable)
  - US5 (P2): Monitoring (can be done in parallel with US4)
- **Container (Phase 8)**: Depends on at least US1-US3 complete
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - provides spec.md output
- **User Story 2 (P1)**: Can start after US1 tested - consumes spec.md, produces plan artifacts
- **User Story 3 (P1)**: Can start after US2 tested - consumes plan.md, produces tasks.md
- **User Story 4 (P2)**: Can start after US3 tested - consumes tasks.md
- **User Story 5 (P2)**: Can start after Foundational - parallel with US4

### Within Each User Story

- Prompts first (no dependencies)
- Agent implementation (depends on prompts)
- Orchestrator routing (depends on agent)
- Artifact storage (depends on agent knowing output format)
- State management (final integration)

### Parallel Opportunities

- T003, T004, T005, T006, T007, T008: All setup tasks
- T010, T011, T012: All model tasks
- T016, T021, T026, T031: All prompt tasks (once foundational complete)
- T037: Monitoring endpoint (independent of other US5 tasks)
- T046, T047, T049: All polish tasks

---

## Parallel Example: Setup Phase

```bash
# Launch all setup tasks in parallel:
Task: "Create requirements.txt" (T003)
Task: "Create .gitignore" (T004)
Task: "Create src/__init__.py" (T005)
Task: "Create src/common/__init__.py" (T006)
Task: "Create src/agents/__init__.py" (T007)
Task: "Create src/prompts/__init__.py" (T008)
```

---

## Implementation Strategy

### MVP First (User Stories 1-3 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (spec.md generation)
4. **STOP and VALIDATE**: Test spec generation independently
5. Complete Phase 4: User Story 2 (plan generation)
6. **STOP and VALIDATE**: Test plan generation
7. Complete Phase 5: User Story 3 (tasks.md generation)
8. **STOP and VALIDATE**: Test task generation
9. Complete Phase 8: Container & Deploy
10. **DEMO**: End-to-end spec → plan → tasks workflow

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Spec generation works!
3. Add User Story 2 → Test independently → Planning works!
4. Add User Story 3 → Test independently → Task generation works!
5. Deploy MVP → Demo spec-to-tasks workflow
6. Add User Story 4 → Test independently → Implementation works!
7. Add User Story 5 → Test independently → Monitoring works!

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently testable after completion
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Dapr sidecar injection handled by K8s annotations (already configured in CDK8s charts)
- LLM calls go through Dapr conversation component (anthropic)

---

## Summary

| Phase | Description | Task Count |
|-------|-------------|------------|
| Setup | Project structure | 8 |
| Foundational | Core infrastructure | 7 |
| US1 | Submit Feature Request | 5 |
| US2 | Generate Plan | 5 |
| US3 | Generate Tasks | 5 |
| US4 | Execute Tasks | 6 |
| US5 | Monitor Progress | 4 |
| Container | Build & Deploy | 5 |
| Polish | Cross-cutting | 4 |
| **Total** | | **49** |
