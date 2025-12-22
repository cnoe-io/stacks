# Quickstart: Langfuse Tracing Integration

**Feature**: 009-langfuse-tracing-integration
**Date**: 2024-12-04

## Prerequisites

Before implementing this feature, verify the following are in place:

### 1. Langfuse Server is Running

```bash
# Check Langfuse pod status
kubectl get pods -n observability -l app=langfuse
# Expected: langfuse-xxx Running

# Check Langfuse service
kubectl get svc -n observability langfuse
# Expected: langfuse ClusterIP 3000/TCP
```

### 2. Langfuse Secrets are Configured

```bash
# Check secrets exist in Azure Key Vault
az keyvault secret show --vault-name <vault-name> --name LANGFUSE-PUBLIC-KEY --query value -o tsv
az keyvault secret show --vault-name <vault-name> --name LANGFUSE-SECRET-KEY --query value -o tsv

# Check External Secrets are synced
kubectl get externalsecret -n observability langfuse-secrets
# Expected: SecretSynced True
```

### 3. Observability Module Exists

```bash
# Verify observability.py exists
ls speckit-agents/src/common/observability.py
# Expected: file exists

# Verify langfuse is in requirements
grep langfuse speckit-agents/requirements.txt
# Expected: langfuse>=2.50.0
```

---

## Implementation Steps

### Step 1: Extend BaseAgent with Trace Management

Edit `speckit-agents/src/agents/base.py`:

```python
# Add to imports
from typing import Optional
from uuid import UUID

# Add to BaseAgent.__init__
self._trace_id: Optional[str] = None
self._workflow_id: Optional[UUID] = None

# Add new method
async def initialize_trace_for_workflow(self, workflow_id: UUID) -> None:
    """Initialize Langfuse trace for this workflow."""
    from src.common.observability import get_langfuse

    langfuse = get_langfuse()
    if langfuse:
        trace = langfuse.trace(
            name=f"workflow_{workflow_id}",
            session_id=str(workflow_id),
            metadata={
                "workflow_id": str(workflow_id),
                "agent": self.name,
            }
        )
        self._trace_id = trace.trace_id
        self._workflow_id = workflow_id
        logger.info(f"Initialized Langfuse trace: {self._trace_id}")
```

### Step 2: Modify route_to_agent to Propagate Trace Context

Edit `speckit-agents/src/agents/base.py`:

```python
# Update route_to_agent method
async def route_to_agent(
    self,
    target_agent: str,
    workflow_id: UUID,
    task: str,
    context: Optional[dict[str, Any]] = None,
) -> None:
    """Route task with embedded trace context."""
    topic = f"{self.config.team_name}.{target_agent}.requests"

    # Embed trace_id in context
    enriched_context = context or {}
    if self._trace_id:
        enriched_context["langfuse_trace_id"] = self._trace_id

    message = WorkflowMessage(
        source=self.name,
        workflow_id=workflow_id,
        task=task,
        context=enriched_context,
    )

    try:
        await asyncio.to_thread(
            self.dapr_client.publish_event,
            pubsub_name=self.config.pubsub_name,
            topic_name=topic,
            data=message.model_dump_json(),
            data_content_type="application/json",
            publish_metadata={"cloudevent.type": "AgentTask"},
        )
        logger.info(f"Routed to {target_agent} (trace_id: {self._trace_id})")
    except Exception as e:
        logger.error(f"Failed to route: {e}")
        raise
```

### Step 3: Add LLM Generation Logging to SpecifierAgent

Edit `speckit-agents/src/agents/specifier.py`:

```python
# Add to imports
import time
from src.common.observability import create_generation, get_langfuse

# Update _generate_spec method
async def _generate_spec(self, feature_description: str, context: dict) -> str:
    """Generate spec with Langfuse generation logging."""
    start_time = time.time()

    try:
        # Existing LLM call logic...
        messages = [
            {"role": "system", "content": self._system_prompt},
            {"role": "user", "content": prompt},
        ]
        response = await self._call_llm(messages)
        content = self._extract_content(response)

        # Log to Langfuse
        if self._trace_id:
            create_generation(
                trace_id=self._trace_id,
                name="generate_spec",
                model="claude-sonnet-4-20250514",
                input_messages=messages,
                output=content,
                usage=response.get("usage"),
                metadata={
                    "agent": self.name,
                    "latency_ms": int((time.time() - start_time) * 1000),
                }
            )

        return content

    except Exception as e:
        # Log error to Langfuse
        if self._trace_id:
            create_generation(
                trace_id=self._trace_id,
                name="generate_spec",
                model="claude-sonnet-4-20250514",
                input_messages=[],
                output=None,
                metadata={"error": str(e), "error_type": type(e).__name__}
            )
        raise
```

### Step 4: Extract Trace Context in Worker Agents

Edit each agent's `process_task` method:

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
        self._workflow_id = workflow_id
    else:
        # Fallback: create new trace
        await self.initialize_trace_for_workflow(workflow_id)

    # Continue with existing logic...
```

### Step 5: Update Orchestrator to Initialize Trace

Edit `speckit-agents/src/agents/orchestrator.py`:

```python
async def run_workflow(self, feature_description: str) -> dict:
    """Run workflow with Langfuse tracing."""
    workflow_id = uuid4()

    # Initialize trace at workflow start
    await self.initialize_trace_for_workflow(workflow_id)

    # Continue with existing workflow logic...
```

---

## Verification

### 1. Deploy Updated Agents

```bash
# Rebuild container image
cd speckit-agents
docker build -t vpittamp23/speckit-agents:latest .
docker push vpittamp23/speckit-agents:latest

# Restart pods
kubectl rollout restart deployment -n dapr-agents
```

### 2. Run a Test Workflow

```bash
# Port-forward to orchestrator
kubectl port-forward -n dapr-agents svc/orchestrator 8000:8000 &

# Submit a test workflow
curl -X POST http://localhost:8000/run \
  -H "Content-Type: application/json" \
  -d '{"task": "Add a simple greeting feature"}'
```

### 3. Verify Traces in Langfuse

```bash
# Open Langfuse UI
open https://langfuse-<cluster>.cnoe.localtest.me:8443

# Expected:
# - Trace named "workflow_{uuid}" appears
# - Session groups all agent calls
# - Generations show prompt/response text
# - Token counts and latency are visible
```

---

## Success Criteria Validation

| Criteria | Validation Method |
|----------|-------------------|
| SC-001: 100% LLM calls traced | Count generations in Langfuse equals LLM calls in logs |
| SC-002: Traces within 30s | Check Langfuse timestamp vs workflow completion time |
| SC-003: <50ms overhead | Compare latency_ms in trace to actual LLM response time |
| SC-004: Graceful degradation | Set LANGFUSE_ENABLED=false, verify workflow completes |
| SC-005: Dashboard visibility | Workflow name, model, execution time visible in UI |

---

## Troubleshooting

### Traces Not Appearing

1. Check Langfuse connectivity:
```bash
kubectl exec -n dapr-agents deployment/orchestrator -- \
  curl -s http://langfuse.observability.svc.cluster.local:3000/health
```

2. Check environment variables:
```bash
kubectl exec -n dapr-agents deployment/orchestrator -- \
  env | grep LANGFUSE
```

3. Check agent logs:
```bash
kubectl logs -n dapr-agents deployment/orchestrator | grep -i langfuse
```

### Trace Correlation Not Working

1. Verify trace_id in routed messages:
```bash
kubectl logs -n dapr-agents deployment/specifier | grep "trace_id"
```

2. Check message context:
```python
# Add debug logging
logger.debug(f"Context received: {context}")
logger.debug(f"Extracted trace_id: {trace_id}")
```

### Token Usage Not Recorded

1. Verify LLM response includes usage:
```python
# Add debug logging
logger.debug(f"LLM response: {response}")
logger.debug(f"Usage: {response.get('usage')}")
```

2. Check Dapr conversation component response format

---

## Next Steps

After completing implementation:

1. Run `/speckit.tasks` to generate detailed task breakdown
2. Implement each task following the dependency order
3. Run full verification against all success criteria
4. Update documentation with any learnings
