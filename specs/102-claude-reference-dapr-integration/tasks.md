# Tasks: Claude SDK + Dapr Multi-Agent Integration with Full Observability

**Input**: Design documents from `/specs/102-claude-reference-dapr-integration/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Contract and integration tests are included per the spec's test-driven development approach.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and Python environment setup

- [X] T001 Create project structure per plan.md at repository root
- [X] T002 Initialize Python 3.11 project with pyproject.toml and dependencies (claude-code-sdk, dapr-agents, langfuse, opentelemetry-api, opentelemetry-sdk, pydantic, fastapi, uvicorn)
- [X] T003 [P] Configure ruff linting and formatting in pyproject.toml
- [X] T004 [P] Create .env.example with required environment variables (ANTHROPIC_API_KEY, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST, JAEGER_ENDPOINT, DAPR_HTTP_PORT)
- [X] T005 [P] Create Dockerfile for agent services in src/agents/Dockerfile
- [X] T006 [P] Create pytest configuration in pyproject.toml with pytest-asyncio settings

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

### Core Models

- [X] T007 [P] Create workflow status enums (WorkflowStatus, PhaseType, PhaseStatus) in src/models/workflow.py
- [X] T008 [P] Create artifact models (ArtifactType, Artifact) in src/models/artifacts.py
- [X] T009 [P] Create Dapr message models (MessageType, AgentMessage, TriggerActionPayload, PhaseCompletePayload, PhaseFailedPayload) in src/models/messages.py
- [X] T010 Create Phase and Workflow models with validation and state transitions in src/models/workflow.py (depends on T007)
- [X] T011 Create TraceIds model for cross-system correlation in src/models/workflow.py (depends on T010)
- [X] T012 Create ToolInvocation model for Langfuse in src/models/observability.py

### Core Services

- [X] T013 Create environment configuration module with Pydantic Settings in src/lib/config.py (depends on T004)
- [X] T014 [P] Create Langfuse client wrapper with session management in src/services/langfuse_client.py
- [X] T015 [P] Create OpenTelemetry/Jaeger tracing setup with W3C traceparent in src/services/tracing.py
- [X] T016 Create Dapr state store wrapper with workflow CRUD operations in src/services/state_manager.py (depends on T010)

### Base Agent Infrastructure

- [X] T017 Create base ClaudeAgent class wrapping ClaudeSDKClient with Langfuse integration in src/agents/base/claude_agent.py (depends on T012, T014)
- [X] T018 Create agent profile configuration (AgentProfileConfig) in src/agents/base/config.py
- [X] T019 Create tool invocation recorder for Langfuse spans in src/agents/base/tool_recorder.py (depends on T012, T014)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Platform Operator Deploys Multi-Agent System (Priority: P1)

**Goal**: Deploy the integrated Claude SDK + Dapr multi-agent system with all agents registered, observability endpoints accessible

**Independent Test**: Deploy via Kubernetes manifests and verify all agent pods reach Running state, Langfuse dashboard accessible, Jaeger UI shows agent startup traces

### Tests for User Story 1

- [X] T020 [P] [US1] Contract test for agent registration schema in tests/contract/test_agent_registry.py
- [X] T021 [P] [US1] Integration test for Dapr state store connectivity in tests/integration/test_state_store.py
- [X] T022 [P] [US1] Integration test for Dapr pub/sub connectivity in tests/integration/test_pubsub.py

### Implementation for User Story 1

- [X] T023 [P] [US1] Create Orchestrator agent with DurableAgent integration in src/agents/orchestrator/app.py (depends on T017, T018)
- [X] T024 [P] [US1] Create Specifier agent with DurableAgent integration in src/agents/specifier/app.py (depends on T017, T018)
- [X] T025 [P] [US1] Create Planner agent with subagent support in src/agents/planner/app.py (depends on T017, T018)
- [X] T026 [P] [US1] Create TaskGenerator agent in src/agents/task_generator/app.py (depends on T017, T018)
- [X] T027 [P] [US1] Create Implementer agent in src/agents/implementer/app.py (depends on T017, T018)
- [X] T028 [US1] Implement agent registry service for registration and discovery in src/services/agent_registry.py (depends on T016)
- [X] T029 [US1] Add agent startup logging with Langfuse trace in src/agents/base/claude_agent.py (depends on T017)
- [X] T030 [US1] Add Jaeger span for agent registration in src/services/tracing.py (depends on T015, T028)

### CDK8s Infrastructure for User Story 1

- [X] T031 [P] [US1] Create Dapr components chart (pub/sub, state stores) in cdk8s/charts/infra/dapr-components-chart.ts
- [X] T032 [P] [US1] Create External Secrets chart for API keys in cdk8s/charts/secrets/speckit-agents-secrets-chart.ts
- [X] T033 [US1] Create agent deployment chart with Dapr annotations in cdk8s/charts/apps/speckit-agents-chart.ts (depends on T031, T032)
- [X] T034 [US1] Add speckit-agents application configuration in cdk8s/config/applications.ts (depends on T033)

**Checkpoint**: At this point, User Story 1 should be fully functional - agents deploy and register successfully

---

## Phase 4: User Story 2 - Developer Initiates Feature Workflow with End-to-End Tracing (Priority: P1)

**Goal**: Submit feature description, process through all phases (Spec -> Plan -> Tasks -> Impl) with full LLM observability

**Independent Test**: Submit "Add a hello world endpoint" and verify workflow completes with artifacts, Langfuse shows conversation tree, Jaeger shows distributed trace

### Tests for User Story 2

- [X] T035 [P] [US2] Contract test for POST /run endpoint in tests/contract/test_workflow_api.py
- [X] T036 [P] [US2] Contract test for GET /workflows/{id}/status endpoint in tests/contract/test_workflow_api.py
- [X] T037 [P] [US2] Contract test for Dapr pub/sub message format in tests/contract/test_dapr_messages.py
- [X] T038 [US2] Integration test for workflow initiation via pub/sub in tests/integration/test_workflow_pubsub.py
- [X] T039 [US2] E2E test for complete workflow execution in tests/e2e/test_workflow_execution.py

### Implementation for User Story 2

- [X] T040 [P] [US2] Create FastAPI app with health check in src/api/main.py
- [X] T041 [P] [US2] Create API key authentication middleware in src/api/auth.py
- [X] T042 [US2] Implement POST /run endpoint in src/api/routes/workflows.py (depends on T009, T016, T040, T041)
- [X] T043 [US2] Implement GET /workflows/{id}/status endpoint in src/api/routes/workflows.py (depends on T010, T016, T040)
- [X] T044 [US2] Implement Orchestrator phase routing logic in src/agents/orchestrator/app.py (depends on T023, T009)
- [X] T045 [US2] Implement Specifier agent task processing with Langfuse generation in src/agents/specifier/app.py (depends on T024, T017)
- [X] T046 [US2] Implement Planner agent task processing with subagent coordination in src/agents/planner/app.py (depends on T025, T017)
- [X] T047 [US2] Implement TaskGenerator agent task processing in src/agents/task_generator/app.py (depends on T026, T017)
- [X] T048 [US2] Implement Implementer agent task processing in src/agents/implementer/app.py (depends on T027, T017)
- [X] T049 [US2] Implement phase transition logic with Dapr pub/sub messaging in src/agents/orchestrator/app.py (depends on T044, T009)
- [X] T050 [US2] Add W3C traceparent propagation to all Dapr messages in src/services/tracing.py (depends on T015, T009)
- [X] T051 [US2] Create artifact storage service for generated documents in src/services/artifact_storage.py (depends on T008, T016)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - full workflow execution with tracing

---

## Phase 5: User Story 3 - Developer Views Tool Calls and Responses in Langfuse (Priority: P2)

**Goal**: Each tool call appears in Langfuse with timing, inputs, outputs, and error status

**Independent Test**: Trigger workflow using multiple tools (Read, Write, Glob), verify each tool call appears in Langfuse with complete metadata

### Tests for User Story 3

- [X] T052 [P] [US3] Contract test for tool invocation schema in tests/contract/test_tool_invocation.py
- [X] T053 [US3] Integration test for tool recording in Langfuse in tests/integration/test_langfuse_tools.py

### Implementation for User Story 3

- [X] T054 [US3] Enhance tool_recorder to capture tool inputs with truncation in src/agents/base/tool_recorder.py (depends on T019)
- [X] T055 [US3] Enhance tool_recorder to capture tool outputs with size indicator in src/agents/base/tool_recorder.py (depends on T054)
- [X] T056 [US3] Add error status tracking to tool invocations in src/agents/base/tool_recorder.py (depends on T055)
- [X] T057 [US3] Implement tool duration measurement in src/agents/base/tool_recorder.py (depends on T056)
- [X] T058 [US3] Add Langfuse span creation for each tool call in src/services/langfuse_client.py (depends on T014, T054)
- [X] T059 [US3] Integrate tool recorder with base ClaudeAgent in src/agents/base/claude_agent.py (depends on T017, T057)

**Checkpoint**: At this point, User Stories 1, 2, AND 3 should all work independently

---

## Phase 6: User Story 4 - Developer Correlates Langfuse and Jaeger Traces (Priority: P2)

**Goal**: Navigate between Langfuse (LLM behavior) and Jaeger (infrastructure timing) using workflow ID

**Independent Test**: Run workflow, search by workflow ID in both systems, verify timestamps align within 1 second

### Tests for User Story 4

- [X] T060 [P] [US4] Contract test for trace ID correlation schema in tests/contract/test_trace_correlation.py
- [X] T061 [US4] Integration test for cross-system trace correlation in tests/integration/test_trace_correlation.py

### Implementation for User Story 4

- [X] T062 [US4] Add Jaeger trace ID to Langfuse metadata in src/services/langfuse_client.py (depends on T014, T015)
- [X] T063 [US4] Add workflow_id tag to all Jaeger spans in src/services/tracing.py (depends on T015, T050)
- [X] T064 [US4] Store Langfuse trace ID in workflow state for cross-reference in src/services/state_manager.py (depends on T016, T011)
- [X] T065 [US4] Add trace_ids to workflow status API response in src/api/routes/workflows.py (depends on T043, T064)

**Checkpoint**: At this point, User Stories 1-4 should all work independently

---

## Phase 7: User Story 5 - Operator Monitors System Health and Usage (Priority: P3)

**Goal**: Monitor workflow counts, completion times, error rates, and token consumption

**Independent Test**: Run 5 workflows and verify Langfuse dashboard shows aggregate statistics

### Tests for User Story 5

- [X] T066 [P] [US5] Contract test for token usage schema in tests/contract/test_token_usage.py
- [X] T067 [US5] Integration test for Langfuse dashboard metrics in tests/integration/test_langfuse_metrics.py

### Implementation for User Story 5

- [X] T068 [US5] Add token usage tracking to LLM generations in src/services/metrics.py (depends on T014)
- [X] T069 [US5] Add latency tracking per agent type in src/services/metrics.py (depends on T068)
- [X] T070 [US5] Add error rate tracking with failure flags in src/services/metrics.py (depends on T069)
- [X] T071 [US5] Add Prometheus metrics endpoint with workflow/phase/tool tracking in src/common/health.py (depends on T063)

**Checkpoint**: At this point, User Stories 1-5 should all work independently

---

## Phase 8: User Story 6 - Developer Resumes Interrupted Session (Priority: P3)

**Goal**: Understand what completed after interruption, resume or restart appropriately

**Independent Test**: Forcefully terminate agent mid-workflow, query state to determine completed phases and existing artifacts

### Tests for User Story 6

- [X] T072 [P] [US6] Contract test for workflow recovery schema in tests/contract/test_workflow_recovery.py
- [X] T073 [US6] Integration test for phase recovery logic in tests/integration/test_phase_recovery.py
- [X] T074 [US6] E2E test for workflow resumption in tests/e2e/test_workflow_resumption.py

### Implementation for User Story 6

- [X] T075 [US6] Implement session state persistence and checkpoint operations in src/services/session_recovery.py (depends on T016)
- [X] T076 [US6] Implement recovery plan creation and execution in src/services/session_recovery.py (depends on T075)
- [X] T077 [US6] Add Claude SDK conversation history storage for resumption in src/services/session_recovery.py (depends on T076)
- [X] T078 [US6] Add retry logic with exponential backoff in src/agents/orchestrator.py (depends on T077)
- [X] T079 [US6] Implement phase-specific timeout enforcement in src/agents/orchestrator.py (depends on T078)
- [X] T080 [US6] Add incomplete generation detection to Langfuse viewer in src/services/langfuse_client.py (depends on T070)

**Checkpoint**: All user stories should now be independently functional

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T081 [P] Add graceful shutdown with Langfuse flush in src/agents/base/claude_agent.py
- [X] T082 [P] Add health check endpoints to all agent services in src/agents/*/app.py
- [X] T083 [P] Create API documentation with OpenAPI spec in src/agents/orchestrator.py
- [X] T084 Implement concurrent workflow limit (5 per agent) with queue in src/services/workflow_queue.py
- [X] T085 Add queue position to status API response in src/agents/orchestrator.py (depends on T084)
- [X] T086 [P] Add security hardening: input validation, rate limiting in src/services/auth_middleware.py
- [X] T087 [P] Update quickstart.md with actual deployment commands
- [X] T088 Run quickstart.md validation with end-to-end test
- [X] T089 Code cleanup and docstring additions across all modules
- [X] T090 Final integration test: run 5 concurrent workflows and verify all success criteria from spec.md (tests/e2e/test_concurrent_workflows.py)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational - Deployment infrastructure
- **User Story 2 (Phase 4)**: Depends on Foundational - Core workflow execution
- **User Story 3 (Phase 5)**: Depends on Foundational - Tool observability
- **User Story 4 (Phase 6)**: Depends on Foundational + parts of US2 (tracing setup) - Trace correlation
- **User Story 5 (Phase 7)**: Depends on Foundational + parts of US3 (Langfuse spans) - Metrics
- **User Story 6 (Phase 8)**: Depends on US2 (workflow execution) - Recovery
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational - No dependencies on other stories (parallel with US1)
- **User Story 3 (P2)**: Can start after Foundational - Enhances observability from US2
- **User Story 4 (P2)**: Can start after Foundational - Requires tracing from US2
- **User Story 5 (P3)**: Can start after Foundational - Requires Langfuse from US3
- **User Story 6 (P3)**: Requires US2 workflow execution to test recovery

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models before services
- Services before endpoints
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- US1 and US2 can be worked in parallel after Foundational (both P1)
- US3 and US4 can be worked in parallel after Foundational (both P2)
- US5 and US6 can be worked in parallel after their dependencies (both P3)
- All tests for a user story marked [P] can run in parallel
- Models within a story marked [P] can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# Launch all model tasks in parallel:
Task: "Create workflow status enums in src/models/workflow.py"
Task: "Create artifact models in src/models/artifacts.py"
Task: "Create Dapr message models in src/models/messages.py"

# Launch all parallel services:
Task: "Create Langfuse client wrapper in src/services/langfuse_client.py"
Task: "Create OpenTelemetry/Jaeger tracing setup in src/services/tracing.py"
```

## Parallel Example: User Story 1 (After Foundational)

```bash
# Launch all agent implementations in parallel:
Task: "Create Orchestrator agent in src/agents/orchestrator/app.py"
Task: "Create Specifier agent in src/agents/specifier/app.py"
Task: "Create Planner agent in src/agents/planner/app.py"
Task: "Create TaskGenerator agent in src/agents/task_generator/app.py"
Task: "Create Implementer agent in src/agents/implementer/app.py"

# Launch all cdk8s charts in parallel:
Task: "Create Dapr components chart in cdk8s/charts/infra/dapr-components-chart.ts"
Task: "Create External Secrets chart in cdk8s/charts/secrets/speckit-agents-secrets-chart.ts"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (Deployment)
4. Complete Phase 4: User Story 2 (Workflow Execution)
5. **STOP and VALIDATE**: Test US1 + US2 independently
6. Deploy/demo if ready - system can execute workflows with basic tracing

### Incremental Delivery

1. Complete Setup + Foundational -> Foundation ready
2. Add User Story 1 -> Test independently -> Agents deploy and register
3. Add User Story 2 -> Test independently -> Full workflow execution (MVP!)
4. Add User Story 3 -> Test independently -> Tool visibility
5. Add User Story 4 -> Test independently -> Cross-system correlation
6. Add User Story 5 -> Test independently -> Operational metrics
7. Add User Story 6 -> Test independently -> Workflow recovery
8. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (cdk8s/deployment)
   - Developer B: User Story 2 (workflow execution)
3. After US1+US2:
   - Developer A: User Story 3 (tool observability)
   - Developer B: User Story 4 (trace correlation)
4. After US3+US4:
   - Developer A: User Story 5 (metrics)
   - Developer B: User Story 6 (recovery)
5. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
