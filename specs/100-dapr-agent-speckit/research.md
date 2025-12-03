# Research: SpecKit Multi-Agent Workflow System

**Branch**: `100-dapr-agent-speckit`
**Date**: 2025-12-03

## Technology Decisions

### 1. Python Framework for Dapr Agents

**Decision**: Use `dapr-agents` Python SDK with FastAPI-based `AgentRunner`

**Rationale**:
- Official Dapr Agents SDK provides high-level abstractions for agent orchestration
- Built-in support for `DurableAgent` with pub/sub, state, memory, and registry configs
- `LLMOrchestrator` provides intelligent agent routing based on task content
- `AgentRunner` handles HTTP/gRPC endpoints, Dapr subscriptions, and graceful shutdown

**Alternatives Considered**:
- Raw Dapr SDK: More control but requires implementing agent patterns manually
- LangGraph: Different paradigm, less integrated with Dapr pub/sub model
- AutoGen: Microsoft-focused, heavier dependency tree

### 2. LLM Provider Integration

**Decision**: Use Anthropic Claude as primary LLM via Dapr conversation component

**Rationale**:
- Dapr conversation component provides abstraction over LLM providers
- Existing infrastructure has `anthropic` component configured with Claude Opus 4.5
- Prompt caching enabled for cost optimization
- Can fallback to OpenAI via separate component if needed

**Alternatives Considered**:
- Direct API calls: Loses Dapr abstraction benefits, harder to swap providers
- LangChain: Additional abstraction layer not needed with Dapr conversation

### 3. State Management Pattern

**Decision**: Use Redis-backed Dapr state stores with agent-specific key prefixes

**Rationale**:
- Redis already deployed in cluster (`dapr-agents-redis`)
- Key prefix isolation prevents state collisions between agents
- `actorStateStore: true` enables workflow actor patterns for orchestrator
- Three separate logical stores:
  - `workflowstatestore`: Workflow execution state (actor-enabled)
  - `agentregistrystore`: Agent discovery (shared across team)
  - `memorystore`: Conversation history per agent

**Alternatives Considered**:
- PostgreSQL: More complex for key-value patterns, overkill for this use case
- In-memory: Lost on pod restart, not suitable for durable workflows

### 4. Message Routing Pattern

**Decision**: Use pub/sub topics with team-based naming convention

**Rationale**:
- Topic pattern: `{team_name}.{agent_name}.requests`
- Broadcast topic: `{team_name}.broadcast` for team-wide messages
- CloudEvents envelope with `TriggerAction` type for workflow triggers
- Dapr handles subscription management and delivery guarantees

**Alternatives Considered**:
- Direct HTTP invocation: Less decoupled, harder to scale horizontally
- Actor-based messaging: More complex, pub/sub sufficient for this use case

### 5. Container Image Strategy

**Decision**: Single multi-agent container image with entrypoint selection

**Rationale**:
- All agents share common dependencies (dapr-agents, anthropic SDK)
- Environment variable `AGENT_NAME` determines which agent to start
- Reduces image maintenance overhead (one Dockerfile, one build pipeline)
- Agents differentiated by deployment config, not image

**Alternatives Considered**:
- Separate images per agent: More isolated but 5x build/push overhead
- Monorepo with shared base: More complex CI/CD setup

### 6. Artifact Storage

**Decision**: Use shared volume mount at `/artifacts/{workflow_id}/`

**Rationale**:
- All agents need read/write access to generated artifacts
- Workflow ID provides isolation between concurrent executions
- PersistentVolumeClaim ensures artifacts survive pod restarts
- Simple file-based approach aligns with SpecKit template system

**Alternatives Considered**:
- Object storage (MinIO): More overhead for simple file access
- Git repository: Would require auth handling, overkill for intermediate artifacts

## Best Practices Identified

### Dapr Agents Configuration Classes

From the dapr-agents documentation, each agent should configure:

```python
# Agent Profile (personality and instructions)
AgentProfileConfig(
    name="...",
    role="...",
    goal="...",
    instructions=[...],
    style_guidelines=[...]
)

# Pub/Sub (messaging)
AgentPubSubConfig(
    pubsub_name="messagepubsub",
    agent_topic="speckit.{agent}.requests",
    broadcast_topic="speckit.broadcast"
)

# State (workflow state)
AgentStateConfig(
    store=StateStoreService(store_name="workflowstatestore", key_prefix="{agent}:")
)

# Registry (agent discovery)
AgentRegistryConfig(
    store=StateStoreService(store_name="agentregistrystore"),
    team_name="speckit"
)

# Memory (conversation history)
AgentMemoryConfig(
    store=ConversationDaprStateMemory(store_name="memorystore", session_id="{agent}-session")
)
```

### Orchestrator Pattern

The LLM Orchestrator pattern from dapr-agents:
- Queries registry for available agents
- Uses LLM to select appropriate agent based on task content
- Routes via pub/sub to selected agent's topic
- Tracks workflow state for multi-step orchestration

### Health Endpoints

Each agent must expose:
- `/healthz`: Liveness probe (return 200 if process is alive)
- `/ready`: Readiness probe (return 200 if Dapr sidecar connected and agent initialized)

## Unresolved Items

None - all technical decisions have been made based on existing infrastructure and best practices.
