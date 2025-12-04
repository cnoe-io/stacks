# Research: Langfuse Tracing Integration

**Feature**: 009-langfuse-tracing-integration
**Date**: 2024-12-04

## Summary

This research resolves the key technical questions for integrating Langfuse tracing with the dapr-agents SDK in the SpecKit workflow. The primary challenge is that `dapr-agents` uses `OpenAIChatClient` internally via `DurableAgent`, and LLM calls are not directly exposed for instrumentation.

---

## Research Questions & Decisions

### 1. How to Instrument dapr-agents OpenAIChatClient LLM Calls

**Decision**: Use manual `create_generation()` calls at LLM call sites

**Rationale**:
- The `OpenAIChatClient` is instantiated inside `create_durable_agent()` factory function
- `DurableAgent` handles LLM calls internally, not exposing a hook point
- The Langfuse `@observe()` decorator works for async functions but doesn't automatically capture LLM-specific data (prompts, tokens, model)
- Manual `create_generation()` provides explicit control over what gets traced

**Alternatives Considered**:
1. **Drop-in OpenAI replacement** (wrap OpenAI with `langfuse.openai`): Rejected because dapr-agents uses its own `OpenAIChatClient` wrapper, not raw OpenAI client
2. **Subclass OpenAIChatClient**: Rejected because it requires modifying the dapr-agents SDK or complex monkey-patching
3. **Dapr conversation component interception**: Not feasible - Dapr invoke_method is synchronous and returns raw response

**Implementation Pattern**:
```python
import time
from src.common.observability import create_generation, get_langfuse

async def _generate_spec(self, feature_description: str, context: dict) -> str:
    """Generate spec with Langfuse generation logging."""

    start_time = time.time()
    langfuse = get_langfuse()

    try:
        # Build messages
        messages = [
            {"role": "system", "content": self._system_prompt},
            {"role": "user", "content": prompt},
        ]

        # Make LLM call via Dapr
        response = await self._call_llm(messages)

        # Extract content and usage
        content = response.get("content", "")
        usage = response.get("usage", {})

        # Log to Langfuse
        if langfuse and self._trace_id:
            create_generation(
                trace_id=self._trace_id,
                name="generate_spec",
                model="claude-sonnet-4-20250514",
                input_messages=messages,
                output=content,
                usage=usage,
                metadata={
                    "agent": self.name,
                    "latency_ms": int((time.time() - start_time) * 1000),
                }
            )

        return content

    except Exception as e:
        # Log error generation
        if langfuse and self._trace_id:
            create_generation(
                trace_id=self._trace_id,
                name="generate_spec",
                model="claude-sonnet-4-20250514",
                input_messages=messages,
                output=None,
                metadata={"error": str(e), "error_type": type(e).__name__}
            )
        raise
```

---

### 2. Langfuse Python SDK Patterns for Async Tracing

**Decision**: Use Langfuse client singleton with workflow-level traces and generation-level spans

**Rationale**:
- Langfuse SDK supports both `@observe()` decorator and manual `trace()`/`generation()` API
- For multi-agent workflows, we need workflow-level trace grouping (session_id)
- Manual API gives more control over trace hierarchy and metadata

**Key Patterns**:

1. **Singleton Client** (already implemented in `observability.py`):
```python
def get_langfuse() -> Optional[Langfuse]:
    """Get or create the singleton Langfuse client."""
    # Already implemented - handles env vars and graceful degradation
```

2. **Workflow Trace Initialization**:
```python
async def initialize_trace_for_workflow(self, workflow_id: UUID) -> None:
    """Initialize Langfuse trace at workflow start."""
    langfuse = get_langfuse()
    if langfuse:
        trace = langfuse.trace(
            name=f"workflow_{workflow_id}",
            session_id=str(workflow_id),  # Groups all agent calls
            metadata={
                "workflow_id": str(workflow_id),
                "agent": self.name,
            }
        )
        self._trace_id = trace.trace_id
```

3. **Generation Logging** (already implemented in `observability.py`):
```python
def create_generation(
    trace_id: str,
    name: str,
    model: str,
    input_messages: list[dict[str, str]],
    output: Optional[str] = None,
    usage: Optional[dict[str, int]] = None,
    metadata: Optional[dict[str, Any]] = None,
) -> None:
    """Record an LLM generation (completion) in Langfuse."""
    # Already implemented - just needs to be called at LLM sites
```

---

### 3. Workflow Context Propagation Across Agents

**Decision**: Embed trace_id in workflow message context, propagate via pub/sub

**Rationale**:
- Each agent runs as separate container (no shared memory)
- Dapr pub/sub is the communication mechanism between agents
- W3C trace context (traceparent) is used by Dapr for distributed tracing, but Langfuse uses its own trace_id
- Embedding in message context is simple and reliable

**Implementation Pattern**:

**Sender (Orchestrator/BaseAgent)**:
```python
async def route_to_agent(
    self,
    target_agent: str,
    workflow_id: UUID,
    task: str,
    context: Optional[dict[str, Any]] = None,
) -> None:
    """Route task with embedded trace context."""

    # Add trace context to message
    enriched_context = context or {}
    enriched_context["langfuse_trace_id"] = self._trace_id

    message = WorkflowMessage(
        source=self.name,
        workflow_id=workflow_id,
        task=task,
        context=enriched_context,
    )

    await asyncio.to_thread(
        self.dapr_client.publish_event,
        pubsub_name=self.config.pubsub_name,
        topic_name=f"{self.config.team_name}.{target_agent}.requests",
        data=message.model_dump_json(),
        data_content_type="application/json",
    )
```

**Receiver (Worker Agent)**:
```python
async def process_task(
    self,
    workflow_id: UUID,
    task: str,
    context: dict[str, Any],
) -> dict[str, Any]:
    """Process task, extracting trace context from message."""

    # Extract trace_id from context (propagated from orchestrator)
    trace_id = context.get("langfuse_trace_id")

    if trace_id:
        self._trace_id = trace_id
    else:
        # Fallback: create new trace for this workflow
        await self.initialize_trace_for_workflow(workflow_id)

    # Now all LLM calls will use this trace_id
    result = await self._do_work(task, context)
    return result
```

---

### 4. Dapr W3C Trace Correlation with Langfuse

**Decision**: Log Dapr trace_id as metadata for cross-system correlation (optional)

**Rationale**:
- Dapr emits traces to Jaeger using W3C traceparent format
- Langfuse uses its own trace_id format
- Logging both IDs in metadata enables cross-referencing in Jaeger and Langfuse dashboards

**Implementation** (optional enhancement):
```python
def correlate_traces(dapr_trace_id: Optional[str], langfuse_trace_id: Optional[str]) -> dict:
    """Create correlation metadata for cross-system debugging."""
    return {
        "dapr_trace_id": dapr_trace_id or "N/A",
        "langfuse_trace_id": langfuse_trace_id or "N/A",
        "correlation_key": f"dapr:{dapr_trace_id}|lf:{langfuse_trace_id}",
    }
```

---

## Dependencies & Prerequisites

| Dependency | Status | Notes |
|------------|--------|-------|
| `langfuse>=2.50.0` | ✅ Already in requirements.txt | Python SDK |
| Langfuse server | ✅ Deployed | `http://langfuse.observability.svc.cluster.local:3000` |
| LANGFUSE_* env vars | ✅ Configured | Via External Secrets from Azure Key Vault |
| `observability.py` module | ✅ Exists | Has `get_langfuse()`, `create_generation()`, `observe_llm_call()` |

---

## Implementation Approach

### Phase 1: Extend BaseAgent with Trace Management
1. Add `_trace_id` and `_workflow_id` attributes to `BaseAgent`
2. Add `initialize_trace_for_workflow()` method
3. Modify `route_to_agent()` to embed trace_id in context

### Phase 2: Instrument LLM Call Sites
1. Add `create_generation()` calls in each agent's LLM-calling method:
   - `SpecifierAgent._generate_spec()`
   - `PlannerAgent._generate_plan()`
   - `TaskGeneratorAgent._generate_tasks()`
   - `ImplementerAgent._generate_code()`

### Phase 3: Extract Trace Context in Worker Agents
1. Modify `process_task()` in each agent to extract trace_id from context
2. Set `self._trace_id` for subsequent LLM calls

### Phase 4: Verification
1. Run workflow and verify traces appear in Langfuse UI
2. Confirm workflow correlation (all agent calls under same session)
3. Verify latency overhead <50ms

---

## Sources

- [Langfuse Python SDK Decorators](https://langfuse.com/docs/sdk/python/decorators)
- [Langfuse OpenAI Integration](https://langfuse.com/integrations/model-providers/openai-py)
- [Dapr W3C Trace Context](https://docs.dapr.io/operations/observability/tracing/w3c-tracing-overview/)
- Existing implementation: `/speckit-agents/src/common/observability.py`
- Existing contract: `/speckit-agents/specs/100-dapr-agent-speckit/contracts/langfuse-sdk-interface.py`
