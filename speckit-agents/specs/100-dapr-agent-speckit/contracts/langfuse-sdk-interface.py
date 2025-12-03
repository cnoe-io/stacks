"""
Langfuse SDK Interface Contract

This file defines the expected interface for integrating Langfuse
with SpecKit agents. It serves as a contract for the observability
module implementation.
"""

from typing import Optional, Dict, Any
from abc import ABC, abstractmethod


class LangfuseObservabilityInterface(ABC):
    """
    Abstract interface for Langfuse observability integration.

    Implementations must provide methods to:
    1. Initialize the Langfuse client
    2. Set workflow context for session grouping
    3. Trace LLM calls with full prompt/response capture
    4. Handle errors gracefully
    """

    @abstractmethod
    def initialize(
        self,
        public_key: str,
        secret_key: str,
        host: str = "http://langfuse.observability.svc.cluster.local:3000"
    ) -> None:
        """
        Initialize the Langfuse client.

        Args:
            public_key: Langfuse project public key (pk_xxx)
            secret_key: Langfuse project secret key (sk_xxx)
            host: Langfuse server URL

        Raises:
            ConnectionError: If unable to connect to Langfuse
        """
        pass

    @abstractmethod
    def set_workflow_context(
        self,
        workflow_id: str,
        agent_name: str,
        agent_role: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Set the context for the current workflow execution.

        This groups all subsequent LLM calls under the same session.

        Args:
            workflow_id: Unique workflow instance ID (UUID)
            agent_name: Name of the current agent (e.g., "specifier")
            agent_role: Role description (e.g., "Specification Writer")
            metadata: Additional key-value pairs to attach
        """
        pass

    @abstractmethod
    def trace_llm_call(
        self,
        name: str,
        prompt: str,
        completion: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
        latency_ms: int,
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Record an LLM API call.

        Args:
            name: Operation name (e.g., "generate_spec")
            prompt: Full prompt sent to LLM
            completion: Full response from LLM
            model: Model identifier (e.g., "claude-opus-4-5-20251101")
            input_tokens: Number of prompt tokens
            output_tokens: Number of completion tokens
            latency_ms: Call duration in milliseconds
            metadata: Additional context

        Returns:
            Generation ID for correlation
        """
        pass

    @abstractmethod
    def trace_error(
        self,
        name: str,
        error: Exception,
        context: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Record an error during agent execution.

        Args:
            name: Operation name where error occurred
            error: The exception that was raised
            context: Additional context about the error
        """
        pass

    @abstractmethod
    def flush(self) -> None:
        """
        Flush any pending traces to Langfuse.

        Should be called before agent shutdown or at end of workflow.
        """
        pass


# Example expected usage in agent code:
"""
from src.common.observability import get_langfuse, set_workflow_context

# At workflow start
set_workflow_context(
    workflow_id="abc123",
    agent_name="specifier",
    agent_role="Specification Writer"
)

# LLM calls are automatically traced via @observe() decorator
@observe(name="generate_spec")
async def generate_spec(description: str) -> str:
    result = await llm.generate(prompt=description)
    return result.content

# At workflow end
get_langfuse().flush()
"""


# Expected environment variables:
"""
LANGFUSE_HOST=http://langfuse.observability.svc.cluster.local:3000
LANGFUSE_PUBLIC_KEY=pk_xxx
LANGFUSE_SECRET_KEY=sk_xxx
"""


# Expected span tags for Jaeger correlation:
"""
Tags added to each Langfuse generation:
- trace_id: W3C trace ID from Dapr (for Jaeger correlation)
- agent_name: Agent identifier
- agent_role: Agent role description
- workflow_id: Workflow instance ID (also used as session_id)
- task_type: Type of operation being performed
"""
