# Feature Specification: Claude SDK + Dapr Multi-Agent Integration with Full Observability

**Feature Branch**: `102-claude-reference-dapr-integration`
**Created**: 2025-12-06
**Status**: Draft
**Input**: User description: "Revise/replace the current Dapr multi-agent system to use the Claude SDK recommended approach (autonomous-coding pattern), while retaining Dapr for workflow orchestration. Integrate comprehensive observability with Langfuse for LLM traces and Jaeger for distributed tracing. Full replacement—no backward compatibility required."

## Clarifications

### Session 2025-12-06

- Q: What authentication mechanism should the workflow API use? → A: API keys stored in Azure Key Vault (keyvault-thcmfmoo5oeow) using External Secrets Operator, following existing cdk8s chart patterns
- Q: What is the workflow failure recovery strategy? → A: Retry current phase (max 3 attempts) before marking workflow as FAILED
- Q: What is the concurrent workflow limit? → A: 5 concurrent workflows per agent (queued if exceeded)
- Q: What is the trace retention policy? → A: 30 days retention for both Langfuse and Jaeger traces
- Q: What are the per-phase timeout thresholds? → A: Phase-specific: Specifier 5min, Planner 10min, TaskGenerator 5min, Implementer 30min

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform Operator Deploys Multi-Agent System (Priority: P1)

A platform operator deploys the integrated Claude SDK + Dapr multi-agent system to orchestrate feature development workflows. The system must start successfully with all agents registered, observability endpoints accessible, and workflow initiation available.

**Why this priority**: Without successful deployment and agent registration, no other functionality is possible. This is the foundation for all subsequent features.

**Independent Test**: Deploy the system via Kubernetes manifests and verify all agent pods reach Running state, Langfuse dashboard is accessible, and Jaeger UI shows initial traces from agent startup.

**Acceptance Scenarios**:

1. **Given** the operator applies Kubernetes manifests, **When** ArgoCD syncs the application, **Then** all agent pods (Orchestrator, Specifier, Planner, TaskGenerator, Implementer) reach Running state within 5 minutes
2. **Given** agents are running, **When** the operator checks the agent registry via Dapr state store, **Then** all 5 agents are registered with their topics and capabilities
3. **Given** the system is deployed, **When** the operator accesses Langfuse at the configured URL, **Then** the dashboard loads and shows the project ready to receive traces
4. **Given** the system is deployed, **When** the operator accesses Jaeger UI, **Then** services appear for each Dapr-enabled agent

---

### User Story 2 - Developer Initiates Feature Workflow with End-to-End Tracing (Priority: P1)

A developer submits a feature description to the orchestrator. The system processes the request through all pipeline phases (Specification → Planning → Task Generation → Implementation), with every LLM call, tool invocation, and inter-agent message captured in observability systems.

**Why this priority**: This is the core user journey that validates the integration between Claude SDK agents and Dapr orchestration with full observability. It proves the system works end-to-end.

**Independent Test**: Submit a simple feature description (e.g., "Add a hello world endpoint") and verify the workflow completes with artifacts generated, Langfuse shows the complete conversation tree, and Jaeger shows the distributed trace across agents.

**Acceptance Scenarios**:

1. **Given** the system is running, **When** a developer POSTs a feature description to `/run`, **Then** the orchestrator returns a workflow ID within 2 seconds
2. **Given** a workflow is initiated, **When** the Specifier agent processes the request, **Then** Langfuse captures the generation with input prompt, output response, model used, and token counts
3. **Given** the Specifier completes, **When** it publishes a phase-complete event, **Then** Jaeger shows a span linking the Specifier to the Orchestrator with proper parent-child relationship
4. **Given** the workflow proceeds through all phases, **When** the developer queries Langfuse by session ID (workflow ID), **Then** all agent generations appear in chronological order with tool calls visible
5. **Given** the workflow completes, **When** the developer opens Jaeger and searches by workflow ID, **Then** a single distributed trace shows the complete flow: Orchestrator → Specifier → Orchestrator → Planner → ... → Implementer

---

### User Story 3 - Developer Views Tool Calls and Responses in Langfuse (Priority: P2)

A developer debugging agent behavior needs to see exactly which tools each agent called, what inputs were provided, what outputs were returned, and how long each tool took.

**Why this priority**: Tool visibility is essential for debugging agent behavior, optimizing prompts, and understanding why agents make certain decisions. It directly supports developer productivity.

**Independent Test**: Trigger a workflow that uses multiple tools (e.g., Read, Write, Glob) and verify each tool call appears in Langfuse with timing, inputs, and outputs.

**Acceptance Scenarios**:

1. **Given** an agent invokes a tool (e.g., Read), **When** the tool completes, **Then** Langfuse shows a span with tool name, input parameters, and execution duration
2. **Given** a tool returns a result, **When** viewing the trace in Langfuse, **Then** the output content is visible (truncated if large, with size indicator)
3. **Given** a tool fails with an error, **When** viewing the trace in Langfuse, **Then** the error is marked with `is_error: true` and the error message is visible
4. **Given** an agent makes multiple tool calls in sequence, **When** viewing the session, **Then** tools appear in execution order with cumulative timing visible

---

### User Story 4 - Developer Correlates Langfuse and Jaeger Traces (Priority: P2)

A developer investigating a slow or failed workflow needs to navigate between Langfuse (for LLM behavior) and Jaeger (for infrastructure timing) using a common identifier.

**Why this priority**: Multi-system observability is only useful if traces can be correlated. This enables root-cause analysis across both LLM and infrastructure layers.

**Independent Test**: Run a workflow, note the workflow ID, and verify the same ID appears in both Langfuse session view and Jaeger trace search, with timestamps aligning.

**Acceptance Scenarios**:

1. **Given** a workflow runs, **When** the developer searches Langfuse by workflow ID, **Then** all traces for that workflow appear grouped in a session
2. **Given** the same workflow, **When** the developer searches Jaeger by workflow ID tag, **Then** the distributed trace appears with matching spans
3. **Given** both systems show the workflow, **When** comparing timestamps, **Then** Langfuse generation times fall within corresponding Jaeger span durations (within 1 second tolerance)
4. **Given** a trace in Langfuse, **When** viewing metadata, **Then** the Jaeger trace ID is visible for cross-reference

---

### User Story 5 - Operator Monitors System Health and Usage (Priority: P3)

An operator needs to monitor overall system health: how many workflows are running, average completion times, error rates, and token consumption across all agents.

**Why this priority**: Operational visibility enables capacity planning, cost management, and SLA monitoring. Less critical than core functionality but essential for production operation.

**Independent Test**: Run 5 workflows and verify Langfuse dashboard shows aggregate statistics (total tokens, average latency, success rate).

**Acceptance Scenarios**:

1. **Given** multiple workflows have completed, **When** the operator views Langfuse project dashboard, **Then** total token usage is displayed (prompt + completion)
2. **Given** workflows with varying completion times, **When** viewing the dashboard, **Then** average generation latency is displayed per agent type
3. **Given** a workflow fails, **When** viewing the dashboard, **Then** the error count increments and the failed trace is flagged
4. **Given** the Jaeger UI, **When** the operator views service metrics, **Then** request rates and error rates per agent service are visible

---

### User Story 6 - Developer Resumes Interrupted Session (Priority: P3)

A developer whose workflow was interrupted (e.g., pod restart, timeout) needs to understand what completed and what remains, using observability data to resume or restart appropriately.

**Why this priority**: Session persistence and resumability improve developer experience when dealing with long-running or interrupted workflows.

**Independent Test**: Forcefully terminate an agent mid-workflow, then query Langfuse and Dapr state to determine which phases completed and what artifacts exist.

**Acceptance Scenarios**:

1. **Given** a workflow is interrupted, **When** the developer queries Dapr state store by workflow ID, **Then** the last completed phase and current status are visible
2. **Given** an interrupted workflow, **When** viewing Langfuse session, **Then** all generations up to the interruption point are visible with timestamps
3. **Given** partial completion data, **When** the developer re-submits the workflow, **Then** the system detects existing artifacts and can skip completed phases

---

### Edge Cases

- What happens when Langfuse is unavailable? System continues with degraded observability (logs warning, does not block workflow)
- What happens when Jaeger is unavailable? Dapr sidecar buffers or drops traces; workflow continues unaffected
- What happens when a tool call times out? Agent receives timeout error, Langfuse records partial trace with error marker
- What happens when workflow ID collision occurs? System rejects duplicate workflow IDs with clear error message
- How does the system handle very large tool outputs (e.g., file content > 100KB)? Outputs are truncated in Langfuse with size indicator; full content in Dapr state store
- What happens when an agent crashes mid-generation? Langfuse trace shows incomplete generation; Dapr orchestrator detects timeout and marks workflow as failed
- What happens when API key validation fails? System returns HTTP 401 with error message; no workflow is created; failed attempt is logged for security audit
- What happens when a phase fails? Orchestrator retries up to 3 times with exponential backoff; if all retries fail, workflow is marked FAILED with retry history preserved
- What happens when concurrent workflow limit is exceeded? New workflows are queued; status endpoint returns queue position; workflows are processed in FIFO order

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST deploy Claude SDK agents (Specifier, Planner, TaskGenerator, Implementer) as Dapr-enabled Kubernetes pods
- **FR-002**: System MUST use Dapr pub/sub for all inter-agent communication, following the topic pattern `{team_name}.{agent_name}.requests`
- **FR-003**: System MUST use Dapr state store for workflow state persistence, including current phase, status, and artifact references
- **FR-004**: Each agent MUST send all LLM interactions (prompts, completions, tool calls, tool results) to Langfuse with session grouping by workflow ID
- **FR-005**: System MUST propagate trace context (W3C traceparent) across all Dapr interactions for Jaeger distributed tracing
- **FR-006**: System MUST record tool invocations with: tool name, input parameters, output content (truncated if >10KB), execution duration, and error status
- **FR-007**: Orchestrator MUST route workflows through phases in order: Specification → Planning → Task Generation → Implementation
- **FR-008**: Each agent MUST implement graceful degradation when Langfuse is unavailable (log warning, continue processing)
- **FR-009**: System MUST generate unique workflow IDs and use them as correlation keys in both Langfuse (session_id) and Jaeger (tag)
- **FR-010**: System MUST store Langfuse trace ID in workflow state for cross-system reference
- **FR-011**: Agents MUST use the Claude Agent SDK streaming interface to capture all message blocks (TextBlock, ToolUseBlock, ToolResultBlock)
- **FR-012**: System MUST expose workflow status via REST endpoint (`/workflows/{id}/status`) returning phase, status, and artifact list
- **FR-013**: System MUST flush Langfuse traces before agent shutdown to prevent data loss
- **FR-014**: System MUST tag all Jaeger spans with `workflow.id`, `agent.name`, and `phase` for filtering
- **FR-015**: Planner agent MUST support parallel subagent execution (research, data-modeling, architecture) with independent trace spans
- **FR-016**: Workflow API endpoints (`/run`, `/workflows/{id}/status`) MUST require API key authentication via `X-API-Key` header
- **FR-017**: API keys MUST be sourced from Azure Key Vault (keyvault-thcmfmoo5oeow) using External Secrets Operator, synced to Kubernetes secrets
- **FR-018**: System MUST reject requests with invalid or missing API keys with HTTP 401 Unauthorized
- **FR-019**: Orchestrator MUST retry a failed phase up to 3 times with exponential backoff before marking workflow as FAILED
- **FR-020**: System MUST record each retry attempt in workflow state with failure reason and timestamp
- **FR-021**: Each agent MUST limit concurrent workflow processing to 5; additional requests MUST be queued
- **FR-022**: System MUST return queue position in `/workflows/{id}/status` response when workflow is queued
- **FR-023**: Langfuse traces MUST be retained for 30 days before automatic deletion
- **FR-024**: Jaeger traces MUST be retained for 30 days before automatic deletion
- **FR-025**: Orchestrator MUST enforce phase-specific timeouts: Specifier 5 minutes, Planner 10 minutes, TaskGenerator 5 minutes, Implementer 30 minutes
- **FR-026**: System MUST mark phase as failed and trigger retry logic when timeout is exceeded

### Key Entities

- **Workflow**: Represents a feature development request; contains ID, description, current phase, status, artifact references, timestamps, and trace IDs
- **Agent**: A specialized Claude SDK worker; has name, topic, capabilities, and registered tools
- **Artifact**: A generated document (spec.md, plan.md, tasks.md, etc.); contains type, content hash, storage reference, and generating agent
- **Trace**: An observability record; exists in Langfuse (generations, spans) and Jaeger (distributed spans); linked by workflow ID
- **Session**: A Langfuse grouping of all traces for a single workflow execution; identified by workflow ID
- **Tool Invocation**: A record of an agent calling a tool; contains tool name, inputs, outputs, duration, and error status

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of LLM generations appear in Langfuse within 30 seconds of completion
- **SC-002**: 100% of tool invocations appear in Langfuse with input, output, and duration
- **SC-003**: Distributed traces in Jaeger show complete workflow execution path across all agents
- **SC-004**: Workflow ID search in Langfuse returns all generations for that workflow in a single session view
- **SC-005**: Workflow ID search in Jaeger returns the complete distributed trace with all agent spans
- **SC-006**: System processes a simple feature workflow (4 phases, ~20 LLM calls) end-to-end within phase timeout limits (max 50 minutes total if no retries)
- **SC-007**: Agent startup to registered state takes under 60 seconds per agent
- **SC-008**: Langfuse unavailability does not increase workflow error rate (graceful degradation verified)
- **SC-009**: Token usage per workflow is accurately captured in Langfuse (within 5% of actual API billing)
- **SC-010**: Cross-system correlation works: Jaeger trace ID appears in Langfuse metadata, Langfuse session ID matches workflow ID in Jaeger tags

## Assumptions

- **A-001**: Langfuse v2.50+ is deployed and accessible at a known endpoint with valid API keys
- **A-002**: Jaeger is deployed with Zipkin-compatible collector endpoint for Dapr tracing
- **A-003**: Redis is available as backend for Dapr state stores and pub/sub
- **A-004**: Anthropic API key is available and has sufficient quota for Claude Opus 4.5 calls
- **A-005**: Kubernetes cluster has Dapr runtime installed with sidecar injection enabled
- **A-006**: Claude Agent SDK version supports streaming response iteration with block-level access
- **A-007**: Network connectivity exists between agents and observability endpoints (Langfuse, Jaeger)
- **A-008**: Existing SpecKit agents codebase can be modified without backward compatibility constraints
