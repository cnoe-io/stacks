# Feature Specification: Langfuse Tracing Integration for SpecKit

**Feature Branch**: `009-langfuse-tracing-integration`
**Created**: 2024-12-04
**Status**: Draft
**Input**: User description: "Add Langfuse tracing to dapr-agents to capture LLM observability data"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View LLM Call Traces in Langfuse (Priority: P1)

As a platform operator, I want to see all LLM calls made by SpecKit workflows traced in the Langfuse dashboard so I can understand model usage, latency, and costs.

**Why this priority**: Core value proposition - without traces appearing in Langfuse, the feature delivers no value. This is the minimum viable functionality.

**Independent Test**: Run a SpecKit workflow (e.g., `/speckit.specify`) and verify traces appear in Langfuse UI within 30 seconds showing the LLM provider, model, prompt, response, and latency.

**Acceptance Scenarios**:

1. **Given** Langfuse is deployed and healthy, **When** a user runs `/speckit.specify` workflow, **Then** a trace appears in Langfuse showing the workflow name, LLM calls, and timing data
2. **Given** the speckit-orchestrator has Langfuse credentials configured, **When** the orchestrator makes an LLM call via dapr-agents, **Then** the call is automatically instrumented and sent to Langfuse
3. **Given** a trace exists in Langfuse, **When** a user views the trace details, **Then** they can see: prompt text, response text, model name, token counts, and latency

---

### User Story 2 - Trace Correlation Across Workflow Steps (Priority: P2)

As a developer debugging a workflow, I want all LLM calls within a single workflow execution to be grouped under one trace so I can follow the entire conversation flow.

**Why this priority**: Enhances debugging capability but requires P1 to be working first. Individual traces (P1) provide value even without correlation.

**Independent Test**: Run a multi-step workflow and verify all LLM calls appear as spans under a single parent trace in Langfuse.

**Acceptance Scenarios**:

1. **Given** a workflow with multiple LLM calls (e.g., clarify → specify → plan), **When** the workflow completes, **Then** all calls appear as child spans under a single parent trace
2. **Given** a parent trace exists, **When** viewing it in Langfuse, **Then** the span hierarchy shows the logical workflow structure

---

### User Story 3 - Cost and Token Tracking (Priority: P3)

As a platform operator, I want to see token usage and estimated costs per workflow so I can monitor and optimize LLM spending.

**Why this priority**: Nice-to-have analytics that builds on P1/P2. Requires traces to exist first.

**Independent Test**: View a trace in Langfuse and verify token counts (input/output) and cost estimates are displayed.

**Acceptance Scenarios**:

1. **Given** Langfuse pricing is configured for the model, **When** viewing a trace, **Then** estimated cost is displayed based on token usage
2. **Given** multiple workflows have run, **When** viewing Langfuse analytics, **Then** aggregate token usage and costs are visible

---

### Edge Cases

- What happens when Langfuse is unavailable? Tracing should fail gracefully without blocking the workflow.
- How does the system handle Langfuse credential rotation? Should read credentials on each request or cache with TTL.
- What if LANGFUSE_ENABLED=false? All tracing code should be no-op with minimal overhead.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST send trace data to Langfuse for every LLM call made by the orchestrator
- **FR-002**: System MUST include prompt text, response text, model name, and latency in each trace span
- **FR-003**: System MUST group related LLM calls under a parent trace using workflow execution ID
- **FR-004**: System MUST read Langfuse credentials from environment variables (LANGFUSE_HOST, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY)
- **FR-005**: System MUST continue workflow execution if Langfuse is unreachable (graceful degradation)
- **FR-006**: System MUST respect LANGFUSE_ENABLED environment variable to enable/disable tracing
- **FR-007**: System MUST include token counts (input_tokens, output_tokens) when available from the LLM response

### Key Entities

- **Trace**: Top-level container representing a workflow execution (maps to Langfuse trace_id)
- **Span**: Individual LLM call within a trace (maps to Langfuse span/generation)
- **Generation**: Langfuse-specific entity for LLM calls with prompt/completion data

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of LLM calls from SpecKit workflows appear as traces in Langfuse when tracing is enabled
- **SC-002**: Traces appear in Langfuse within 30 seconds of workflow completion
- **SC-003**: Workflow execution latency increases by no more than 50ms due to tracing overhead
- **SC-004**: System continues functioning when Langfuse is unavailable (0 workflow failures due to tracing)
- **SC-005**: Users can identify the workflow name, model, and execution time from the Langfuse dashboard

## Assumptions

- Langfuse v3 is already deployed and accessible at `http://langfuse.observability.svc.cluster.local:3000`
- Langfuse API keys are pre-configured in the speckit-orchestrator deployment
- The dapr-agents library uses a Python LLM client that can be instrumented
- Langfuse Python SDK supports the required tracing primitives (trace, span, generation)

## Dependencies

- Langfuse v3 deployment (already complete)
- LANGFUSE_* environment variables in speckit-orchestrator (already configured)
- `langfuse` Python package added to speckit-agents dependencies
