# Implementation Plan: Claude Agent SDK Integration with Dapr Orchestration

**Branch**: `101-dapr-claude-code` | **Date**: 2025-12-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/101-dapr-claude-code/spec.md`

**User Constraint**: Full replacement of current implementation. No backwards compatibility required. Discard unused code/files.

## Summary

Replace the current dapr-agents SDK implementation with Claude Agent SDK for all LLM-powered agent execution. Each worker agent (specifier, planner, task-generator, implementer) will use Claude Agent SDK's `query()` or `ClaudeSDKClient` for AI interactions, with custom MCP tools bridging to Dapr infrastructure for state management and inter-agent messaging. The orchestrator remains non-AI, using only Dapr pub/sub for routing.

## Technical Context

**Language/Version**: Python 3.11+
**Primary Dependencies**:
- claude-agent-sdk (Claude Agent SDK for Python)
- dapr-client>=1.14.0 (Dapr client only - no dapr-agents)
- fastapi>=0.111.0 (HTTP endpoints)
- uvicorn>=0.30.0 (ASGI server)
- pydantic>=2.11.0 (Data validation)
- langfuse>=2.50.0 (Observability)

**Removed Dependencies**:
- dapr-agents (replaced by claude-agent-sdk)
- anthropic (Claude SDK bundles its own client)

**Storage**: Redis via Dapr state store (unchanged)
**Testing**: pytest with pytest-asyncio
**Target Platform**: Kubernetes (Kind cluster for local dev)
**Project Type**: Single Python package with multi-entrypoint agents
**Performance Goals**:
- Spec generation: <2 minutes
- Planning with parallel subagents: <4 minutes (40% faster)
- 10 concurrent workflows
**Constraints**:
- Keep Dapr for all distributed systems (pub/sub, state, durability)
- Claude SDK handles all AI/LLM work
- Langfuse tracing required for all AI calls
**Scale/Scope**: 5 agents, single Kubernetes namespace

## Constitution Check

*No constitution file found - proceeding without constitution gates*

**Pre-Design Check**: N/A (no constitution defined)
**Post-Design Check**: N/A (no constitution defined)

## Project Structure

### Documentation (this feature)

```
specs/101-dapr-claude-code/
├── plan.md              # This file
├── research.md          # Phase 0: Claude SDK patterns, MCP tools
├── data-model.md        # Phase 1: Entity definitions
├── quickstart.md        # Phase 1: Deployment guide
├── contracts/           # Phase 1: API contracts
│   ├── orchestrator-api.yaml
│   └── mcp-tools-schema.yaml
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```
speckit-agents/
├── pyproject.toml           # Updated dependencies (claude-agent-sdk, no dapr-agents)
├── requirements.txt         # Pinned dependencies
├── Dockerfile               # Multi-stage build
├── src/
│   ├── __init__.py
│   ├── main.py              # Entry point (AGENT_NAME dispatch)
│   ├── agents/
│   │   ├── __init__.py
│   │   ├── base.py          # BaseClaudeAgent (Dapr integration + Claude SDK)
│   │   ├── orchestrator.py  # DaprOrchestrator (no LLM - routing only)
│   │   ├── specifier.py     # ClaudeSpecifierAgent
│   │   ├── planner.py       # ClaudePlannerAgent (with subagents)
│   │   ├── task_generator.py # ClaudeTaskGeneratorAgent
│   │   └── implementer.py   # ClaudeImplementerAgent (full tools)
│   ├── tools/
│   │   ├── __init__.py
│   │   ├── dapr_tools.py    # MCP tools for Dapr integration
│   │   ├── artifact_tools.py # MCP tools for artifact management
│   │   └── test_tools.py    # MCP tools for test execution
│   ├── common/
│   │   ├── __init__.py
│   │   ├── config.py        # Environment configuration
│   │   ├── models.py        # Pydantic models (Workflow, Artifact, etc.)
│   │   ├── health.py        # Kubernetes probes
│   │   └── claude_config.py # Claude SDK options factory
│   └── prompts/
│       ├── __init__.py
│       ├── specifier.py     # Specifier system prompts
│       ├── planner.py       # Planner + subagent prompts
│       ├── task_generator.py # Task generator prompts
│       └── implementer.py   # Implementer prompts
└── tests/
    ├── unit/
    │   ├── test_tools.py
    │   ├── test_agents.py
    │   └── test_models.py
    └── integration/
        └── test_workflow.py

# CDK8s (infrastructure - minimal changes)
cdk8s/charts/
├── infra/
│   ├── dapr-crds-chart.ts         # Keep unchanged
│   ├── dapr-runtime-chart.ts      # Keep unchanged
│   ├── dapr-agents-redis-chart.ts # Keep unchanged
│   ├── dapr-components-chart.ts   # MODIFY: Remove conversation components
│   └── dapr-tracing-config-chart.ts # Keep unchanged
├── apps/
│   └── speckit-agents-chart.ts    # MODIFY: Update env vars for Claude SDK
└── secrets/
    └── dapr-agents-secrets-chart.ts # Keep unchanged (still need ANTHROPIC_API_KEY)
```

**Structure Decision**: Single Python package with `src/` layout. Agents are dispatched via `AGENT_NAME` environment variable in `main.py`. MCP tools in dedicated `tools/` directory expose Dapr integration to Claude SDK.

### Files to Delete

Per user instruction to discard unused code:

```
# Remove dapr-agents SDK usage (replaced by claude-agent-sdk)
speckit-agents/src/common/observability.py  # Replace with claude-native tracing
# Delete after rewrite - current base.py has dapr-agents imports

# Remove Dapr conversation components from CDK8s
# dapr-components-chart.ts sections: 'anthropic' and 'openai' components
```

## Complexity Tracking

*No constitution violations to justify*

| Change | Rationale |
|--------|-----------|
| Full dapr-agents removal | User explicitly requested full replacement, no backwards compatibility |
| Custom MCP tools for Dapr | Claude SDK requires MCP pattern for external integrations |
| Subagents in planner | Enables parallel artifact generation (key performance gain) |

## Key Implementation Patterns

### Pattern 1: BaseClaudeAgent

Base class providing:
- Dapr client for state/pub/sub (unchanged from current)
- Claude SDK options factory method
- Common MCP tools registration
- Langfuse trace context propagation

### Pattern 2: Orchestrator (No LLM)

```python
class DaprOrchestrator:
    """Pure routing - no Claude SDK, no LLM calls"""
    async def route_to_agent(target: str, workflow_id: UUID, task: str)
    async def handle_phase_completion(workflow_id: UUID, context: dict)
```

### Pattern 3: Worker Agent with Claude SDK

```python
class ClaudeSpecifierAgent(BaseClaudeAgent):
    def __init__(self):
        self._options = ClaudeAgentOptions(
            system_prompt=get_system_prompt(),
            max_turns=3,
            allowed_tools=["Read", "Write", "mcp__dapr__get_workflow_state"],
            model="claude-sonnet-4-20250514"
        )

    async def process_task(self, workflow_id, task, context):
        async for msg in query(prompt=task, options=self._options, cwd=artifacts_path):
            # Extract generated spec content
            pass
```

### Pattern 4: Planner with Parallel Subagents

```python
self._options = ClaudeAgentOptions(
    agents={
        'research-agent': {
            'description': 'Research technology choices',
            'tools': ['WebSearch', 'Read'],
            'model': 'haiku'
        },
        'data-modeler': {
            'description': 'Design data models',
            'tools': ['Read', 'Write'],
            'model': 'sonnet'
        },
        'architecture-agent': {
            'description': 'Design implementation plan',
            'tools': ['Read', 'Write', 'Glob'],
            'model': 'sonnet'
        }
    }
)
```

### Pattern 5: Custom MCP Tools for Dapr

```python
@tool("get_workflow_state", "Get workflow state from Dapr", {"workflow_id": str})
async def get_workflow_state(args):
    client = DaprClient()
    state = await asyncio.to_thread(client.get_state, ...)
    return {"content": [{"type": "text", "text": state.data}]}

dapr_mcp_server = create_sdk_mcp_server(
    name="dapr",
    version="1.0.0",
    tools=[get_workflow_state, save_workflow_state, publish_phase_complete, get_artifact]
)
```

## Infrastructure Changes

### CDK8s: dapr-components-chart.ts

**Remove**: `anthropic` and `openai` Dapr conversation components (Claude SDK calls API directly)

**Keep**:
- `workflowstatestore` (Redis state)
- `agentregistrystore` (Redis state)
- `memorystore` (Redis state)
- `messagepubsub` (Redis pub/sub)

### CDK8s: speckit-agents-chart.ts

**Update environment variables**:
```typescript
// Remove
{ name: 'CONVERSATION_COMPONENT', value: conversationComponent }

// Add
{ name: 'ANTHROPIC_API_KEY', valueFrom: { secretKeyRef: { name: llmSecretName, key: 'ANTHROPIC_API_KEY' } } }
// Claude SDK reads ANTHROPIC_API_KEY directly from environment
```

## Next Steps

1. **Phase 0** (research.md): Claude Agent SDK patterns, MCP tool examples, Langfuse integration
2. **Phase 1** (design): data-model.md, contracts/, quickstart.md
3. **Phase 2** (tasks.md): Via `/speckit.tasks` command
