"""
Observability Extensions Contract

This file defines the interface extensions for Langfuse tracing integration
in SpecKit agents. These methods will be added to BaseAgent and observability.py.
"""

from abc import ABC, abstractmethod
from typing import Any, Optional
from uuid import UUID


class TracedAgentInterface(ABC):
    """
    Interface for agents with Langfuse tracing capabilities.

    All agents (Orchestrator, Specifier, Planner, TaskGenerator, Implementer)
    must implement this interface for consistent tracing behavior.
    """

    @abstractmethod
    async def initialize_trace_for_workflow(self, workflow_id: UUID) -> None:
        """
        Initialize a Langfuse trace for a new workflow.

        Called at the start of workflow execution (typically by Orchestrator).
        Sets self._trace_id which is used by all subsequent LLM calls.

        Args:
            workflow_id: The workflow instance ID (used as session_id)

        Side Effects:
            - Sets self._trace_id to the Langfuse trace ID
            - Sets self._workflow_id to the workflow ID
        """
        pass

    @abstractmethod
    def extract_trace_context_from_message(
        self, context: dict[str, Any]
    ) -> Optional[str]:
        """
        Extract Langfuse trace ID from incoming workflow message context.

        Called by worker agents when receiving routed tasks. The trace_id
        is embedded in the message context by the sender (Orchestrator).

        Args:
            context: The context dict from WorkflowMessage

        Returns:
            The trace_id if present, None otherwise
        """
        pass

    @abstractmethod
    async def log_llm_generation(
        self,
        name: str,
        model: str,
        input_messages: list[dict[str, str]],
        output: Optional[str],
        usage: Optional[dict[str, int]],
        latency_ms: int,
        error: Optional[Exception] = None,
    ) -> None:
        """
        Log an LLM generation to Langfuse.

        Called after each LLM API call to record the prompt, response,
        and metrics.

        Args:
            name: Operation name (e.g., "generate_spec")
            model: Model identifier (e.g., "claude-sonnet-4-20250514")
            input_messages: List of {"role": str, "content": str} messages
            output: LLM response text (None if error)
            usage: Token counts {"prompt_tokens", "completion_tokens", "total_tokens"}
            latency_ms: Call duration in milliseconds
            error: Exception if call failed

        Side Effects:
            - Calls create_generation() with trace_id from self._trace_id
        """
        pass


class TracedOrchestratorInterface(TracedAgentInterface):
    """
    Extended interface for the Orchestrator agent.

    The Orchestrator is responsible for initializing traces and
    propagating trace context to worker agents.
    """

    @abstractmethod
    async def route_to_agent_with_trace(
        self,
        target_agent: str,
        workflow_id: UUID,
        task: str,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        """
        Route a task to another agent with embedded trace context.

        Extends the standard route_to_agent() to include Langfuse trace_id
        in the message context for propagation.

        Args:
            target_agent: Target agent name (e.g., "specifier")
            workflow_id: Workflow instance ID
            task: Task description
            context: Additional context (trace_id will be added)

        Side Effects:
            - Publishes message with enriched context including trace_id
        """
        pass


# Expected implementation signatures for observability.py extensions

def set_workflow_context(
    workflow_id: UUID,
    agent_name: str,
    user_id: Optional[str] = None,
) -> Optional[str]:
    """
    Initialize or resume a Langfuse trace for a workflow.

    Creates a new trace with workflow_id as session_id for grouping.
    Returns the trace_id for embedding in routed messages.

    Args:
        workflow_id: Workflow instance ID (becomes session_id)
        agent_name: Current agent name for metadata
        user_id: Optional user identifier

    Returns:
        The Langfuse trace_id, or None if Langfuse is disabled

    Example:
        trace_id = set_workflow_context(
            workflow_id=UUID("abc-123"),
            agent_name="orchestrator",
        )
        # trace_id can now be embedded in routed messages
    """
    pass


def log_generation_with_context(
    trace_id: str,
    name: str,
    model: str,
    input_messages: list[dict[str, str]],
    output: Optional[str] = None,
    usage: Optional[dict[str, int]] = None,
    metadata: Optional[dict[str, Any]] = None,
) -> None:
    """
    Log an LLM generation to a specific trace.

    Wrapper around create_generation() with additional context handling.

    Args:
        trace_id: Parent trace ID
        name: Operation name
        model: Model identifier
        input_messages: Prompt messages
        output: LLM response (None if error)
        usage: Token usage dict
        metadata: Additional context (latency_ms, error, etc.)

    Example:
        log_generation_with_context(
            trace_id="abc-123",
            name="generate_spec",
            model="claude-sonnet-4-20250514",
            input_messages=[
                {"role": "system", "content": "..."},
                {"role": "user", "content": "..."},
            ],
            output="Generated specification...",
            usage={"prompt_tokens": 100, "completion_tokens": 200, "total_tokens": 300},
            metadata={"latency_ms": 1500, "agent": "specifier"},
        )
    """
    pass


# Expected environment variables
"""
LANGFUSE_ENABLED=true
LANGFUSE_HOST=http://langfuse.observability.svc.cluster.local:3000
LANGFUSE_PUBLIC_KEY=pk_xxx  # From Azure Key Vault via External Secrets
LANGFUSE_SECRET_KEY=sk_xxx  # From Azure Key Vault via External Secrets
"""

# Expected trace structure in Langfuse
"""
Trace: workflow_{workflow_id}
├── session_id: {workflow_id}
├── metadata: {workflow_id, agent: orchestrator}
│
├── Generation: orchestrator_route
│   └── metadata: {target_agent, routing_decision}
│
├── Generation: specifier_generate_spec
│   ├── model: claude-sonnet-4-20250514
│   ├── input: [system prompt, user request]
│   ├── output: specification content
│   └── usage: {prompt_tokens, completion_tokens, total_tokens}
│
├── Generation: planner_generate_plan
│   ├── model: claude-sonnet-4-20250514
│   ├── input: [system prompt, spec content]
│   ├── output: plan content
│   └── usage: {...}
│
└── Generation: task_generator_generate_tasks
    ├── model: claude-sonnet-4-20250514
    ├── input: [system prompt, plan content]
    ├── output: tasks content
    └── usage: {...}
"""
