# Feature Specification: Claude Agent SDK Integration with Dapr Orchestration

**Feature Branch**: `101-dapr-claude-code`
**Created**: 2025-12-05
**Status**: Draft
**Input**: User description: "Revise the SpecKit multi-agent workflow to use Claude Agent SDK for each agent's LLM-powered execution, while keeping Dapr for workflow orchestration, state management, and inter-agent communication"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Developer Submits Feature Request (Priority: P1)

A developer submits a natural language feature description and receives a structured specification document generated using Claude's agent capabilities.

**Why this priority**: This is the entry point to the entire workflow. The specifier agent demonstrates the core integration pattern that all other agents will follow.

**Independent Test**: Can be fully tested by sending a feature description and verifying spec.md is generated with proper structure, and that the generation used Claude's native capabilities (verified via observability traces).

**Acceptance Scenarios**:

1. **Given** a developer has a feature idea, **When** they submit a description to the orchestrator endpoint, **Then** the system generates a structured spec.md within 90 seconds
2. **Given** the specifier agent receives a request, **When** it processes the request, **Then** it uses Claude's agent capabilities with appropriate instructions and file access
3. **Given** the specifier needs to write the spec file, **When** generation completes, **Then** it uses native file writing capabilities rather than custom code

---

### User Story 2 - Planner Generates Implementation Artifacts in Parallel (Priority: P1)

After a specification is created, the planner agent uses parallel sub-workers to generate research.md, data-model.md, and plan.md concurrently.

**Why this priority**: Demonstrates the key differentiator of Claude's agent capabilities - parallel execution - which significantly reduces planning time.

**Independent Test**: Can be tested by providing a spec.md and verifying all three planning artifacts are generated, with observability traces showing parallel worker invocations.

**Acceptance Scenarios**:

1. **Given** a completed spec.md exists, **When** the planner agent receives the workflow trigger, **Then** it spawns three subagents (research, data-model, architecture) in parallel
2. **Given** the subagents are working, **When** they complete, **Then** each writes its artifact independently and results are aggregated by the parent agent
3. **Given** one subagent fails, **When** the planner detects the failure, **Then** it retries that specific subagent without rerunning successful ones

---

### User Story 3 - Implementer Executes Tasks with Full Tool Access (Priority: P1)

The implementer agent uses Claude's agent capabilities with full tool access (file reading, file writing, file editing, command execution, file search) to execute tasks from tasks.md using a TDD approach.

**Why this priority**: The implementer is the most tool-intensive agent and benefits most from Claude's native file and code execution capabilities.

**Independent Test**: Can be tested by providing tasks.md and verifying the implementer writes tests first, then implementation code, with file changes tracked via version control.

**Acceptance Scenarios**:

1. **Given** tasks.md exists with pending tasks, **When** the implementer receives a trigger, **Then** it uses native command execution to run tests
2. **Given** a task requires code changes, **When** the implementer processes it, **Then** it uses native file editing for precise modifications
3. **Given** tests fail after implementation, **When** the implementer detects failures, **Then** it iterates automatically (up to the configured limit) until tests pass

---

### User Story 4 - Orchestrator Manages Agent Communication (Priority: P1)

The orchestrator manages workflow phases using messaging infrastructure while each agent uses Claude's capabilities internally for AI work.

**Why this priority**: Establishes the separation of concerns - distributed systems infrastructure handles messaging, state, and durability while Claude handles AI agent concerns (generation, tools, context).

**Independent Test**: Can be tested by tracing a complete workflow and verifying infrastructure handles all inter-agent messages while Claude handles all AI operations.

**Acceptance Scenarios**:

1. **Given** a workflow is started, **When** the orchestrator routes to the next agent, **Then** it uses messaging infrastructure for message delivery
2. **Given** an agent completes its work, **When** it signals completion, **Then** it publishes via messaging and updates workflow state via persistent storage
3. **Given** workflow state needs to be persisted, **When** any agent saves state, **Then** it uses the persistent state store

---

### User Story 5 - Custom Tools Bridge Claude and Infrastructure (Priority: P2)

Agents can interact with infrastructure services (state store, messaging) through custom tools exposed to Claude's agent capabilities.

**Why this priority**: Enables Claude agents to interact with infrastructure when needed (e.g., reading previous artifacts, publishing phase completion) without breaking the separation of concerns.

**Independent Test**: Can be tested by invoking an agent with a prompt that requires reading workflow state, and verifying the agent uses custom tools to access the state store.

**Acceptance Scenarios**:

1. **Given** an agent needs previous artifacts, **When** it processes a task, **Then** it can use custom tools to retrieve artifacts from storage
2. **Given** an agent completes its phase, **When** it needs to notify the orchestrator, **Then** it can use custom tools to publish phase completion
3. **Given** custom tools are initialized, **When** the agent starts, **Then** all infrastructure tools are available with proper validation

---

### User Story 6 - Observability Tracks AI Calls Across Agents (Priority: P2)

All AI generation calls across all agents are traced in the observability system with proper session grouping by workflow ID.

**Why this priority**: Observability enables cost tracking, latency analysis, and debugging - essential for production operation but not core functionality.

**Independent Test**: Can be tested by running a complete workflow and verifying all AI calls appear in observability grouped under a single session ID matching the workflow identifier.

**Acceptance Scenarios**:

1. **Given** the orchestrator starts a workflow, **When** it initializes the agent, **Then** the workflow ID is set as the observability session ID
2. **Given** sub-workers are spawned, **When** they make AI calls, **Then** traces are grouped under the parent agent's trace
3. **Given** an AI call fails, **When** error details are logged, **Then** observability shows the error with full context

---

### Edge Cases

- What happens when Claude's context window fills up? The system automatically compacts context, preserving essential information
- How does the system handle AI rate limits? Built-in retry logic handles temporary limits; infrastructure provides durability if agent restarts
- What happens when a sub-worker times out? Parent agent receives timeout error and can retry or fail gracefully
- How are large artifacts (>100KB) handled? Artifacts are stored in persistent storage and referenced by path, not embedded in messages
- What happens when infrastructure services are unavailable? Agent health check fails, preventing work acceptance until services are ready

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each worker agent (specifier, planner, task-generator, implementer) MUST use Claude's agent capabilities for all AI interactions
- **FR-002**: The orchestrator MUST NOT use AI capabilities; it only routes messages and manages workflow state
- **FR-003**: System MUST use messaging infrastructure for all inter-agent communication
- **FR-004**: System MUST use persistent state storage for workflow state
- **FR-005**: Each agent MUST expose custom tools for infrastructure integration (state access, messaging, artifact retrieval)
- **FR-006**: The planner agent MUST use parallel sub-workers to accelerate artifact generation
- **FR-007**: The implementer agent MUST have access to file operations (read, write, edit), command execution, and search capabilities
- **FR-008**: Each agent MUST configure appropriate tool permissions to enforce least-privilege access
- **FR-009**: All AI calls MUST be traced in the observability system with workflow ID as session identifier
- **FR-010**: Agent configuration MUST be customizable per-agent (iteration limits, model selection, instructions, tool access)
- **FR-011**: System MUST gracefully degrade if observability is unavailable (continue without tracing)
- **FR-012**: Agents MUST use built-in context management rather than custom token counting

### Key Entities

- **Agent Configuration**: Configuration for each agent's AI capabilities; includes instructions, iteration limits, tool permissions, model selection
- **Custom Tool**: Tool definition exposed to Claude; bridges infrastructure services (state, messaging) with agent capabilities
- **Sub-worker Definition**: Configuration for parallel workers within the planner; includes role description, tool permissions, model selection
- **Workflow State**: Persisted in state storage; tracks phase, current agent, artifacts, trace ID for observability grouping

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can submit a feature description and receive a complete spec.md within 2 minutes (same as current baseline)
- **SC-002**: Planning phase completes 40% faster due to parallel execution (target: under 4 minutes vs current 6+ minutes)
- **SC-003**: Implementer agent successfully completes 80% of tasks autonomously using native tools
- **SC-004**: 100% of AI calls appear in observability with correct session grouping
- **SC-005**: Context management prevents token exhaustion in 99% of workflows (no manual intervention needed)
- **SC-006**: System handles 10 concurrent workflow executions without resource contention
- **SC-007**: Agent startup time remains under 10 seconds including AI capability initialization
- **SC-008**: Error recovery maintains workflow state - agents can resume from last checkpoint after restart

## Assumptions

- Claude's agent capabilities are available for programmatic use
- API access credentials are available via environment configuration
- Existing messaging and state infrastructure remains unchanged
- Observability platform is deployed and accessible from the cluster
- AI service rate limits are sufficient for expected workflow volume
- Container orchestration resources can support agent process overhead
