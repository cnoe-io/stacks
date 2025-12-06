# Research: Claude SDK + Dapr Multi-Agent Integration

**Feature**: 102-claude-reference-dapr-integration
**Date**: 2025-12-06
**Status**: Complete

## 1. Claude Agent SDK Integration

### 1.1 ClaudeSDKClient Patterns

From the Anthropic quickstarts reference (`autonomous-coding` example):

```python
from claude_code_sdk import ClaudeSDKClient

async def run_agent_session(client: ClaudeSDKClient, message: str) -> tuple[str, str]:
    """Run a single agent session using Claude Agent SDK."""

    # Send the query
    await client.query(message)

    # Collect response via streaming
    response_text = ""
    async for msg in client.receive_response():
        msg_type = type(msg).__name__

        # Handle AssistantMessage (text and tool use)
        if msg_type == "AssistantMessage" and hasattr(msg, "content"):
            for block in msg.content:
                block_type = type(block).__name__

                if block_type == "TextBlock":
                    response_text += block.text
                elif block_type == "ToolUseBlock":
                    # Tool invocation - name and input available
                    tool_name = block.name
                    tool_input = block.input

        # Handle UserMessage (tool results)
        elif msg_type == "UserMessage" and hasattr(msg, "content"):
            for block in msg.content:
                if type(block).__name__ == "ToolResultBlock":
                    result_content = getattr(block, "content", "")
                    is_error = getattr(block, "is_error", False)

    return "continue", response_text
```

**Key Patterns:**
- Async streaming with `receive_response()`
- Message block types: `TextBlock`, `ToolUseBlock`, `ToolResultBlock`
- Context manager pattern: `async with client:`
- Fresh context per session (stateless between sessions)

### 1.2 Security Hooks

The autonomous-coding example uses command allowlisting:

```python
# security.py
ALLOWED_COMMANDS = {
    "ls", "cat", "head", "tail", "wc", "grep",  # File inspection
    "npm", "node",                                # Node.js
    "git",                                        # Version control
    "ps", "lsof", "sleep", "pkill"               # Process management
}

def validate_bash_command(command: str) -> bool:
    """Check if bash command is in allowlist."""
    cmd_parts = command.strip().split()
    if not cmd_parts:
        return False
    base_cmd = cmd_parts[0]
    return base_cmd in ALLOWED_COMMANDS
```

**Application for SpecKit Agents:**
- Specifier: Read-only file access, glob patterns
- Planner: Read-only + research tools (web fetch)
- TaskGenerator: Read-only file access
- Implementer: Full file read/write, git, build tools

### 1.3 Client Configuration

```python
# client.py
def create_client(project_dir: Path, model: str) -> ClaudeSDKClient:
    """Create configured Claude SDK client."""
    return ClaudeSDKClient(
        working_directory=str(project_dir.resolve()),
        model=model,
        # Security hooks configured here
    )
```

---

## 2. Dapr Agent Patterns

### 2.1 Configuration Classes

From the Dapr Agents quickstarts (`05-multi-agent-workflows`):

```python
from dapr_agents.agents.durable import DurableAgent
from dapr_agents.agents.configs import (
    AgentMemoryConfig,
    AgentPubSubConfig,
    AgentRegistryConfig,
    AgentStateConfig,
)
from dapr_agents.agents.prompting import AgentProfileConfig
from dapr_agents.storage.daprstores.stateservice import StateStoreService

# Registry - shared across team
registry = AgentRegistryConfig(
    store=StateStoreService(store_name="agentregistrystore"),
    team_name="speckit",  # Team namespace
)

# Pub/Sub - per agent
pubsub = AgentPubSubConfig(
    pubsub_name="messagepubsub",
    agent_topic="speckit.specifier.requests",    # Agent-specific
    broadcast_topic="speckit.broadcast",          # Team-wide
)

# State - per agent with key prefix isolation
state = AgentStateConfig(
    store=StateStoreService(
        store_name="workflowstatestore",
        key_prefix="specifier:"  # Isolation
    )
)

# Memory - conversation history per session
memory = AgentMemoryConfig(
    store=ConversationDaprStateMemory(
        store_name="memorystore",
        session_id=f"specifier-{workflow_id}",
    )
)

# Profile - agent personality
profile = AgentProfileConfig(
    name="Specifier",
    role="Specification Writer",
    goal="Create detailed feature specifications...",
    instructions=[...],
    style_guidelines=[...],
)
```

### 2.2 DurableAgent Construction

```python
from dapr_agents.workflow.runners import AgentRunner
from dapr_agents.workflow.utils.core import wait_for_shutdown

agent = DurableAgent(
    profile=profile,
    pubsub=pubsub,
    state=state,
    registry=registry,
    memory=memory,
    llm=llm_client,  # Replace with Claude SDK wrapper
)

# Register routes and run
runner = AgentRunner()
runner.register_routes(agent)
await wait_for_shutdown()
```

### 2.3 Topic Naming Convention

Pattern: `{team_name}.{agent_name}.requests`

For SpecKit:
- `speckit.orchestrator.requests` - Workflow orchestration
- `speckit.specifier.requests` - Specification phase
- `speckit.planner.requests` - Planning phase
- `speckit.taskgenerator.requests` - Task generation phase
- `speckit.implementer.requests` - Implementation phase
- `speckit.broadcast` - Team-wide broadcasts

### 2.4 Dapr Components Configuration

```yaml
# pubsub.yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: messagepubsub
spec:
  type: pubsub.redis
  version: v1
  metadata:
    - name: redisHost
      value: redis:6379

# statestore.yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: workflowstatestore
spec:
  type: state.redis
  version: v1
  metadata:
    - name: redisHost
      value: redis:6379
    - name: actorStateStore
      value: "true"
```

---

## 3. Observability Integration

### 3.1 Langfuse Integration Pattern

```python
from langfuse import Langfuse

class LangfuseObservability:
    def __init__(self):
        self.langfuse = Langfuse(
            public_key=os.environ["LANGFUSE_PUBLIC_KEY"],
            secret_key=os.environ["LANGFUSE_SECRET_KEY"],
            host=os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com"),
        )

    def start_trace(self, workflow_id: str, agent_name: str) -> "Trace":
        """Start a new trace for a workflow."""
        return self.langfuse.trace(
            id=f"{workflow_id}-{agent_name}",
            name=f"{agent_name}-execution",
            session_id=workflow_id,  # Groups all agents for same workflow
            metadata={
                "agent": agent_name,
                "phase": self._get_phase_name(agent_name),
            }
        )

    def record_generation(
        self,
        trace: "Trace",
        model: str,
        input_messages: list,
        output_text: str,
        usage: dict,
    ) -> "Generation":
        """Record LLM generation."""
        return trace.generation(
            name="llm-call",
            model=model,
            input=input_messages,
            output=output_text,
            usage={
                "prompt_tokens": usage.get("input_tokens", 0),
                "completion_tokens": usage.get("output_tokens", 0),
            }
        )

    def record_tool_call(
        self,
        trace: "Trace",
        tool_name: str,
        tool_input: dict,
        tool_output: str,
        duration_ms: float,
        is_error: bool = False,
    ) -> "Span":
        """Record tool invocation."""
        output = tool_output
        if len(output) > 10240:  # Truncate >10KB
            output = f"{output[:10240]}... [truncated, total {len(tool_output)} chars]"

        return trace.span(
            name=f"tool:{tool_name}",
            input=tool_input,
            output=output,
            metadata={
                "is_error": is_error,
                "duration_ms": duration_ms,
            }
        )

    def flush(self):
        """Ensure all traces are sent before shutdown."""
        self.langfuse.flush()
```

### 3.2 Jaeger/OpenTelemetry Integration

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.propagate import inject, extract
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

def setup_tracing(service_name: str):
    """Configure OpenTelemetry for Jaeger."""
    provider = TracerProvider()

    jaeger_exporter = JaegerExporter(
        agent_host_name=os.environ.get("JAEGER_AGENT_HOST", "jaeger"),
        agent_port=int(os.environ.get("JAEGER_AGENT_PORT", "6831")),
    )

    provider.add_span_processor(BatchSpanProcessor(jaeger_exporter))
    trace.set_tracer_provider(provider)

    return trace.get_tracer(service_name)

def propagate_context_to_headers(headers: dict):
    """Inject W3C traceparent into outgoing headers."""
    propagator = TraceContextTextMapPropagator()
    inject(headers, setter=lambda h, k, v: h.update({k: v}))

def extract_context_from_headers(headers: dict):
    """Extract trace context from incoming headers."""
    propagator = TraceContextTextMapPropagator()
    return extract(headers, getter=lambda h, k: h.get(k))
```

### 3.3 Combined Observability Wrapper

```python
class ObservableClaudeAgent:
    """Wraps Claude SDK with Langfuse and Jaeger observability."""

    def __init__(
        self,
        agent_name: str,
        claude_client: ClaudeSDKClient,
        langfuse: LangfuseObservability,
        tracer: trace.Tracer,
    ):
        self.agent_name = agent_name
        self.claude = claude_client
        self.langfuse = langfuse
        self.tracer = tracer

    async def execute(
        self,
        workflow_id: str,
        message: str,
        parent_context: dict = None,
    ) -> str:
        """Execute agent with full observability."""

        # Start Langfuse trace
        lf_trace = self.langfuse.start_trace(workflow_id, self.agent_name)

        # Start Jaeger span (with parent context if provided)
        ctx = extract_context_from_headers(parent_context or {})
        with self.tracer.start_as_current_span(
            f"{self.agent_name}.execute",
            context=ctx,
            attributes={
                "workflow.id": workflow_id,
                "agent.name": self.agent_name,
            }
        ) as span:
            try:
                await self.claude.query(message)

                response_text = ""
                async for msg in self.claude.receive_response():
                    # Process message blocks
                    if hasattr(msg, "content"):
                        for block in msg.content:
                            block_type = type(block).__name__

                            if block_type == "TextBlock":
                                response_text += block.text

                            elif block_type == "ToolUseBlock":
                                start_time = time.time()
                                # Record tool start in Jaeger
                                with self.tracer.start_span(
                                    f"tool.{block.name}"
                                ) as tool_span:
                                    tool_span.set_attribute("tool.input", str(block.input))

                            elif block_type == "ToolResultBlock":
                                duration_ms = (time.time() - start_time) * 1000
                                # Record in Langfuse
                                self.langfuse.record_tool_call(
                                    lf_trace,
                                    tool_name=block.name,
                                    tool_input=block.input,
                                    tool_output=str(block.content),
                                    duration_ms=duration_ms,
                                    is_error=block.is_error,
                                )

                # Record final generation
                self.langfuse.record_generation(
                    lf_trace,
                    model="claude-opus-4-5-20251101",
                    input_messages=[{"role": "user", "content": message}],
                    output_text=response_text,
                    usage={},  # Populated from SDK
                )

                # Store Langfuse trace ID for cross-reference
                span.set_attribute("langfuse.trace_id", lf_trace.id)

                return response_text

            except Exception as e:
                span.record_exception(e)
                raise
            finally:
                self.langfuse.flush()
```

---

## 4. Kubernetes Deployment Patterns

### 4.1 Dapr Sidecar Annotations

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: specifier-agent
spec:
  template:
    metadata:
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "specifier"
        dapr.io/app-port: "8080"
        dapr.io/enable-api-logging: "true"
        dapr.io/log-level: "info"
        # Enable tracing
        dapr.io/config: "dapr-tracing-config"
```

### 4.2 Dapr Tracing Configuration

```yaml
apiVersion: dapr.io/v1alpha1
kind: Configuration
metadata:
  name: dapr-tracing-config
spec:
  tracing:
    samplingRate: "1"
    zipkin:
      endpointAddress: "http://jaeger-collector:9411/api/v2/spans"
```

### 4.3 External Secrets Pattern (from existing cdk8s)

```typescript
// Based on existing patterns in cdk8s/charts/secrets/
const anthropicSecret = new ExternalSecret(this, 'anthropic-api-key', {
  metadata: { name: 'anthropic-api-key' },
  spec: {
    refreshInterval: '1h',
    secretStoreRef: {
      name: 'azure-keyvault',
      kind: 'ClusterSecretStore',
    },
    target: {
      name: 'anthropic-api-key',
      creationPolicy: 'Owner',
    },
    data: [{
      secretKey: 'ANTHROPIC_API_KEY',
      remoteRef: {
        key: 'ANTHROPIC-API-KEY',
      },
    }],
  },
});
```

### 4.4 Sync Wave Ordering

```
-100: Namespace
-90:  Dapr Components (Redis, pub/sub, state stores)
-80:  External Secrets (API keys)
-70:  ConfigMaps
-50:  Langfuse, Jaeger (observability)
0:    Agent Deployments
10:   Orchestrator Deployment
50:   API Service (workflow initiation)
```

---

## 5. Key Implementation Decisions

### 5.1 Claude SDK vs Dapr LLM Component

**Decision**: Use Claude SDK directly, not Dapr's conversation component

**Rationale**:
- Claude SDK provides streaming, tool handling, message blocks
- Dapr conversation component is generic, lacks Claude-specific features
- Claude SDK enables proper Langfuse integration at message-block level
- Follows Anthropic's recommended autonomous-coding pattern

### 5.2 Hybrid Architecture

**Decision**: Claude SDK for LLM, Dapr for orchestration

**Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Orchestrator│  │  Specifier  │  │   Planner   │  ...    │
│  │  ┌─────────┐│  │  ┌─────────┐│  │  ┌─────────┐│         │
│  │  │ Claude  ││  │  │ Claude  ││  │  │ Claude  ││         │
│  │  │   SDK   ││  │  │   SDK   ││  │  │   SDK   ││         │
│  │  └────┬────┘│  │  └────┬────┘│  │  └────┬────┘│         │
│  │       │     │  │       │     │  │       │     │         │
│  │  ┌────┴────┐│  │  ┌────┴────┐│  │  ┌────┴────┐│         │
│  │  │Langfuse ││  │  │Langfuse ││  │  │Langfuse ││         │
│  │  │ Client  ││  │  │ Client  ││  │  │ Client  ││         │
│  │  └─────────┘│  │  └─────────┘│  │  └─────────┘│         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
│  ┌──────┴────────────────┴────────────────┴──────┐         │
│  │               Dapr Sidecar Mesh                │         │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────────┐    │         │
│  │  │ Pub/Sub │  │  State  │  │   Tracing   │    │         │
│  │  │ (Redis) │  │ (Redis) │  │  (Jaeger)   │    │         │
│  │  └─────────┘  └─────────┘  └─────────────┘    │         │
│  └───────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 Workflow ID as Correlation Key

**Decision**: Single workflow ID used across all systems

**Usage**:
- Langfuse: `session_id` groups all agent traces
- Jaeger: Tag `workflow.id` enables filtering
- Dapr State: Key prefix `workflow:{id}`
- API Response: Returned in `/run` response

### 5.4 Tool Output Truncation

**Decision**: Truncate tool outputs >10KB in Langfuse

**Rationale**:
- Large outputs (file contents) overwhelm Langfuse UI
- Full outputs stored in Dapr state store
- Langfuse shows truncated preview with size indicator

---

## 6. References

- [Anthropic Claude Quickstarts - autonomous-coding](docs/anthropics-claude-quickstarts-d6f3ebb3a1174e2f.txt)
- [Dapr Agents - 05-multi-agent-workflows](docs/dapr-dapr-agents-711c81bc738d9d59.txt)
- [Langfuse Python SDK](https://langfuse.com/docs/sdk/python)
- [OpenTelemetry Python](https://opentelemetry.io/docs/languages/python/)
- [Dapr Pub/Sub](https://docs.dapr.io/developing-applications/building-blocks/pubsub/)
- [Dapr State Management](https://docs.dapr.io/developing-applications/building-blocks/state-management/)
