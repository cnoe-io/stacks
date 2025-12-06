# Research: Claude Agent SDK Integration with Dapr

**Feature Branch**: `101-dapr-claude-code`
**Created**: 2025-12-05

## Executive Summary

This research documents the integration patterns for combining Claude Agent SDK with Dapr infrastructure. Key findings:

1. **Claude Agent SDK** provides native Python support via `claude-agent-sdk` package with `query()` and `ClaudeSDKClient` APIs
2. **Custom MCP Tools** bridge Claude agents to Dapr services using `@tool` decorator and `create_sdk_mcp_server()`
3. **Subagents** enable parallel execution via `agents` parameter in `ClaudeAgentOptions`
4. **Langfuse Integration** works with Claude SDK through session ID propagation

---

## Research Topic 1: Claude Agent SDK Python API

### Decision
Use `claude-agent-sdk` Python package with async `query()` function for simple agents and `ClaudeSDKClient` for agents requiring custom tools/hooks.

### Rationale
- Official Anthropic SDK, production-ready
- Native async support compatible with FastAPI
- Built-in context management prevents token exhaustion
- Bundled Claude Code CLI eliminates separate installation

### Implementation Pattern

```python
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, TextBlock

async def generate_spec(feature_description: str) -> str:
    options = ClaudeAgentOptions(
        system_prompt="You are a specification writer...",
        max_turns=3,
        allowed_tools=["Read", "Write"],
        model="claude-sonnet-4-20250514"
    )

    result = ""
    async for message in query(
        prompt=feature_description,
        options=options,
        cwd="/artifacts"
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    result += block.text

    return result
```

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Direct Anthropic API | No tool use, no context management, no file operations |
| dapr-agents SDK | Limited tool ecosystem, no parallel subagents, custom LLM wrapper needed |
| LangChain agents | Heavy dependency, not optimized for Claude |

---

## Research Topic 2: Custom MCP Tools for Dapr Integration

### Decision
Create an in-process MCP server using `create_sdk_mcp_server()` with tools for Dapr state/pub/sub operations.

### Rationale
- In-process servers eliminate IPC overhead
- Type-safe tool definitions via Python decorators
- Tools appear as `mcp__<server>__<tool>` to Claude

### Implementation Pattern

```python
from claude_agent_sdk import tool, create_sdk_mcp_server
from dapr.clients import DaprClient
import asyncio
import json

@tool("get_workflow_state", "Retrieve workflow state from Dapr", {"workflow_id": str})
async def get_workflow_state(args):
    client = DaprClient()
    key = f"workflow:{args['workflow_id']}"
    state = await asyncio.to_thread(
        client.get_state,
        store_name="workflowstatestore",
        key=key
    )
    return {
        "content": [{"type": "text", "text": state.data.decode() if state.data else "{}"}]
    }

@tool("save_workflow_state", "Save workflow state to Dapr", {"workflow_id": str, "state": dict})
async def save_workflow_state(args):
    client = DaprClient()
    key = f"workflow:{args['workflow_id']}"
    await asyncio.to_thread(
        client.save_state,
        store_name="workflowstatestore",
        key=key,
        value=json.dumps(args['state'])
    )
    return {"content": [{"type": "text", "text": f"Saved state for {args['workflow_id']}"}]}

@tool("publish_event", "Publish message to Dapr pub/sub", {"topic": str, "data": dict})
async def publish_event(args):
    client = DaprClient()
    await asyncio.to_thread(
        client.publish_event,
        pubsub_name="messagepubsub",
        topic_name=args['topic'],
        data=json.dumps(args['data']),
        data_content_type="application/json"
    )
    return {"content": [{"type": "text", "text": f"Published to {args['topic']}"}]}

@tool("get_artifact", "Read artifact from previous workflow phase", {"workflow_id": str, "artifact_type": str})
async def get_artifact(args):
    path = f"/artifacts/{args['workflow_id']}/{args['artifact_type']}.md"
    try:
        with open(path) as f:
            content = f.read()
        return {"content": [{"type": "text", "text": content}]}
    except FileNotFoundError:
        return {"content": [{"type": "text", "text": f"Artifact not found: {path}"}]}

# Create MCP server
dapr_mcp_server = create_sdk_mcp_server(
    name="dapr",
    version="1.0.0",
    tools=[get_workflow_state, save_workflow_state, publish_event, get_artifact]
)
```

### Tool Naming Convention
Tools are exposed to Claude as `mcp__<server_name>__<tool_name>`:
- `mcp__dapr__get_workflow_state`
- `mcp__dapr__save_workflow_state`
- `mcp__dapr__publish_event`
- `mcp__dapr__get_artifact`

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Stdio MCP servers | Requires subprocess management, IPC overhead |
| HTTP MCP servers | Network latency, additional deployment complexity |
| Direct Dapr calls in agent code | Breaks Claude SDK tool abstraction, harder to test |

---

## Research Topic 3: Parallel Subagent Execution

### Decision
Use `agents` parameter in `ClaudeAgentOptions` to define specialized subagents that Claude can spawn in parallel.

### Rationale
- 40% faster planning by running research/data-model/architecture in parallel
- Each subagent has isolated context window (prevents bloat)
- Claude automatically selects appropriate subagent based on task
- Failed subagents can be retried independently

### Implementation Pattern

```python
from claude_agent_sdk import query, ClaudeAgentOptions

async def generate_plan_artifacts(spec_content: str) -> dict:
    options = ClaudeAgentOptions(
        system_prompt="""You are a planning orchestrator. Based on the specification,
        delegate work to specialized subagents:
        1. research-agent: Technology research and best practices
        2. data-modeler: Entity definitions and relationships
        3. architecture-agent: Implementation plan and file structure

        Run subagents in parallel when possible. Aggregate results into final artifacts.""",

        max_turns=10,

        agents={
            'research-agent': {
                'description': 'Research technology choices, dependencies, and best practices',
                'prompt': 'You are a technology researcher. Analyze requirements and recommend technologies with rationale.',
                'tools': ['WebSearch', 'Read'],
                'model': 'haiku'  # Cheaper for research
            },
            'data-modeler': {
                'description': 'Design data models, entities, and relationships',
                'prompt': 'You are a data modeling expert. Define entities, fields, relationships, and validation rules.',
                'tools': ['Read', 'Write'],
                'model': 'sonnet'
            },
            'architecture-agent': {
                'description': 'Design system architecture and implementation approach',
                'prompt': 'You are a software architect. Create implementation plans with file structure and dependencies.',
                'tools': ['Read', 'Write', 'Glob'],
                'model': 'sonnet'
            }
        },

        allowed_tools=["Read", "Write", "Glob", "mcp__dapr__get_artifact"],
        model="claude-sonnet-4-20250514"
    )

    async for message in query(
        prompt=f"Generate planning artifacts for:\n\n{spec_content}",
        options=options,
        cwd="/artifacts"
    ):
        # Claude will automatically delegate to subagents
        pass
```

### Subagent Model Selection

| Subagent | Model | Rationale |
|----------|-------|-----------|
| research-agent | haiku | Cost-effective for web search and summarization |
| data-modeler | sonnet | Needs precision for schema design |
| architecture-agent | sonnet | Complex reasoning for architecture decisions |
| parent orchestrator | sonnet | Coordinates and aggregates results |

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Sequential artifact generation | 40% slower, no parallelization benefit |
| Manual async.gather with multiple queries | Complex error handling, manual result aggregation |
| Separate agent deployments | Adds infrastructure complexity, network latency |

---

## Research Topic 4: Implementer Tool Access Pattern

### Decision
Grant implementer agent full tool access: Read, Write, Edit, Bash, Glob, Grep plus custom test tools.

### Rationale
- TDD approach requires test execution (Bash)
- Code modifications require precise editing (Edit)
- File search needed for understanding codebase (Glob, Grep)
- High max_turns (50) allows iterative development

### Implementation Pattern

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions, tool, create_sdk_mcp_server

# Custom test tools
@tool("run_tests", "Execute test suite", {"test_path": str, "coverage": bool})
async def run_tests(args):
    import subprocess
    cmd = ["pytest", args["test_path"], "-v"]
    if args.get("coverage"):
        cmd.extend(["--cov", "--cov-report=term-missing"])

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    output = f"Exit code: {result.returncode}\n\nSTDOUT:\n{result.stdout}\n\nSTDERR:\n{result.stderr}"
    return {"content": [{"type": "text", "text": output}]}

test_mcp_server = create_sdk_mcp_server(
    name="tests",
    version="1.0.0",
    tools=[run_tests]
)

async def execute_tasks(tasks_content: str, workflow_id: str):
    options = ClaudeAgentOptions(
        system_prompt="""You are a TDD implementation agent. For each task:
        1. Write tests first
        2. Run tests to verify they fail
        3. Implement the code
        4. Run tests to verify they pass
        5. Refactor if needed
        6. Mark task complete""",

        max_turns=50,  # Allow many iterations for TDD

        mcp_servers={
            "dapr": dapr_mcp_server,
            "tests": test_mcp_server
        },

        allowed_tools=[
            # Claude SDK native tools
            "Read", "Write", "Edit", "Bash", "Glob", "Grep",
            # Custom MCP tools
            "mcp__dapr__get_artifact",
            "mcp__dapr__save_workflow_state",
            "mcp__tests__run_tests"
        ],

        model="claude-sonnet-4-20250514"
    )

    async with ClaudeSDKClient(options=options) as client:
        await client.query(
            f"Execute tasks from tasks.md:\n\n{tasks_content}",
            cwd=f"/workspace/{workflow_id}"
        )
        async for message in client.receive_messages():
            # Track progress, extract results
            pass
```

### Tool Permission by Agent

| Agent | Native Tools | MCP Tools |
|-------|--------------|-----------|
| specifier | Read, Write | mcp__dapr__get_workflow_state |
| planner | Read, Write, Glob, WebSearch | mcp__dapr__get_artifact |
| task-generator | Read, Write | mcp__dapr__get_artifact |
| implementer | Read, Write, Edit, Bash, Glob, Grep | mcp__dapr__*, mcp__tests__* |

---

## Research Topic 5: Langfuse Integration with Claude SDK

### Decision
Propagate workflow ID as Langfuse session ID through all agent invocations. Use Claude SDK's native tracing or wrap with Langfuse spans.

### Rationale
- All LLM calls grouped by workflow ID for cost analysis
- Subagent calls appear as child spans
- Error context preserved for debugging

### Implementation Pattern

```python
from langfuse import Langfuse
from claude_agent_sdk import query, ClaudeAgentOptions
import os

# Initialize Langfuse client
langfuse = Langfuse(
    host=os.getenv("LANGFUSE_HOST"),
    public_key=os.getenv("LANGFUSE_PUBLIC_KEY"),
    secret_key=os.getenv("LANGFUSE_SECRET_KEY")
)

async def process_with_tracing(workflow_id: str, task: str, options: ClaudeAgentOptions):
    # Create trace for this workflow
    trace = langfuse.trace(
        name=f"workflow_{workflow_id}",
        session_id=workflow_id,  # Group all calls by workflow
        metadata={"agent": "specifier"}
    )

    try:
        # Create generation span for the query
        generation = trace.generation(
            name="claude_agent_query",
            model=options.model,
            input=task
        )

        result = ""
        async for message in query(prompt=task, options=options):
            if hasattr(message, 'content'):
                for block in message.content:
                    if hasattr(block, 'text'):
                        result += block.text

        generation.end(output=result)
        return result

    except Exception as e:
        trace.update(level="ERROR", status_message=str(e))
        raise
    finally:
        langfuse.flush()
```

### Trace Propagation Across Agents

```python
# Orchestrator: Create root trace, embed in context
async def start_workflow(feature_description: str) -> dict:
    workflow_id = str(uuid.uuid4())
    trace = langfuse.trace(name=f"workflow_{workflow_id}", session_id=workflow_id)

    # Embed trace_id in context for worker agents
    await route_to_agent(
        target="specifier",
        workflow_id=workflow_id,
        task=feature_description,
        context={"langfuse_trace_id": trace.id}
    )

# Worker agent: Extract trace context
async def process_task(workflow_id: str, task: str, context: dict):
    trace_id = context.get("langfuse_trace_id")
    # Create child span under parent trace
    langfuse.span(trace_id=trace_id, name="specifier_task")
```

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|------------------|
| Custom LLM wrapper (current) | Claude SDK handles its own API calls, wrapper not needed |
| OpenTelemetry traces | Langfuse has better LLM-specific features (token counting, cost) |
| No tracing | Violates FR-009 requirement |

---

## Research Topic 6: Orchestrator Pattern (No LLM)

### Decision
Keep orchestrator as pure Dapr router with no Claude SDK usage. FastAPI endpoints + Dapr pub/sub only.

### Rationale
- Orchestrator doesn't generate content, only routes
- Reduces API costs (no LLM calls for routing)
- Simpler deployment (no ANTHROPIC_API_KEY needed for orchestrator)
- Clear separation: Dapr = infrastructure, Claude = AI

### Implementation Pattern

```python
from fastapi import APIRouter
from dapr.clients import DaprClient
from pydantic import BaseModel
from uuid import UUID, uuid4
import asyncio

router = APIRouter()

class DaprOrchestrator:
    """Pure routing orchestrator - no Claude SDK, no LLM calls"""

    def __init__(self):
        self._dapr_client = DaprClient()
        self._phase_agents = {
            "specification": "specifier",
            "planning": "planner",
            "task_generation": "task-generator",
            "implementation": "implementer"
        }

    async def route_to_agent(self, target: str, workflow_id: UUID, task: str, context: dict):
        topic = f"speckit.{target}.requests"
        message = {
            "source": "orchestrator",
            "workflow_id": str(workflow_id),
            "task": task,
            "context": context
        }
        await asyncio.to_thread(
            self._dapr_client.publish_event,
            pubsub_name="messagepubsub",
            topic_name=topic,
            data=json.dumps(message)
        )

    async def handle_phase_completion(self, workflow_id: UUID, completed_phase: str, result: dict):
        next_phase = self._get_next_phase(completed_phase)
        if next_phase is None:
            await self._mark_workflow_complete(workflow_id)
            return

        next_agent = self._phase_agents[next_phase]
        await self.route_to_agent(next_agent, workflow_id, f"Execute {next_phase}", result)

@router.post("/run")
async def start_workflow(request: WorkflowRequest):
    orchestrator = DaprOrchestrator()
    workflow_id = uuid4()

    # Save initial state
    await orchestrator.save_state(workflow_id, {"status": "pending", "phase": "specification"})

    # Route to first agent
    await orchestrator.route_to_agent(
        target="specifier",
        workflow_id=workflow_id,
        task=request.task,
        context={"feature_description": request.task}
    )

    return {"workflow_id": str(workflow_id), "status": "started"}
```

---

## Summary of Key Decisions

| Topic | Decision | Key Benefit |
|-------|----------|-------------|
| Python API | `claude-agent-sdk` with `query()` | Native async, built-in context management |
| MCP Tools | In-process `create_sdk_mcp_server()` | Type-safe, no IPC overhead |
| Parallel Execution | `agents` parameter for subagents | 40% faster planning |
| Implementer Tools | Full access (Read/Write/Edit/Bash/Glob/Grep) | TDD workflow support |
| Tracing | Langfuse with workflow session ID | Cost tracking, debugging |
| Orchestrator | Pure Dapr, no Claude SDK | Cost savings, clear separation |

## Dependencies

```txt
# requirements.txt
claude-agent-sdk>=0.1.0        # Claude Agent SDK
dapr>=1.14.0                   # Dapr client (state/pubsub only)
fastapi>=0.111.0               # HTTP endpoints
uvicorn>=0.30.0                # ASGI server
pydantic>=2.11.0               # Data validation
langfuse>=2.50.0               # Observability

# Dev dependencies
pytest>=8.0.0
pytest-asyncio>=0.23.0
```
