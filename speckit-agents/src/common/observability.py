"""Observability module for LLM tracing with Langfuse.

This module provides Langfuse integration for tracing LLM calls in SpecKit agents.
Configuration is loaded from environment variables:
- LANGFUSE_HOST: Langfuse server URL (default: http://langfuse.observability.svc.cluster.local:3000)
- LANGFUSE_PUBLIC_KEY: Public key for Langfuse authentication
- LANGFUSE_SECRET_KEY: Secret key for Langfuse authentication

Usage:
    from src.common.observability import get_langfuse, observe_llm_call

    # Use @observe decorator on async methods
    @observe_llm_call(name="my_llm_operation")
    async def my_function():
        ...

    # Or use the client directly for more control
    langfuse = get_langfuse()
    with langfuse.trace(name="workflow") as trace:
        # Your code here
        pass
"""

from __future__ import annotations

import logging
import os
from functools import wraps
from typing import Any, Callable, Optional, TypeVar

logger = logging.getLogger(__name__)

# Langfuse client singleton
_langfuse_client: Optional["Langfuse"] = None
_langfuse_enabled: bool = True

# Type variable for decorators
F = TypeVar("F", bound=Callable[..., Any])


def get_langfuse() -> Optional["Langfuse"]:
    """Get or create the singleton Langfuse client.

    Returns None if Langfuse is disabled or not configured.

    Environment variables:
    - LANGFUSE_ENABLED: Set to 'false' to disable Langfuse (default: true)
    - LANGFUSE_HOST: Langfuse server URL
    - LANGFUSE_PUBLIC_KEY: Public key for authentication
    - LANGFUSE_SECRET_KEY: Secret key for authentication
    """
    global _langfuse_client, _langfuse_enabled

    # Check if Langfuse is disabled
    if not _langfuse_enabled:
        return None

    # Check if disabled via env var
    if os.getenv("LANGFUSE_ENABLED", "true").lower() == "false":
        _langfuse_enabled = False
        logger.info("Langfuse disabled via LANGFUSE_ENABLED=false")
        return None

    # Return existing client if available
    if _langfuse_client is not None:
        return _langfuse_client

    # Check for required environment variables
    host = os.getenv("LANGFUSE_HOST", "http://langfuse.observability.svc.cluster.local:3000")
    public_key = os.getenv("LANGFUSE_PUBLIC_KEY")
    secret_key = os.getenv("LANGFUSE_SECRET_KEY")

    if not public_key or not secret_key:
        logger.warning(
            "Langfuse not configured: LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY are required. "
            "LLM tracing will be disabled."
        )
        _langfuse_enabled = False
        return None

    try:
        from langfuse import Langfuse

        _langfuse_client = Langfuse(
            host=host,
            public_key=public_key,
            secret_key=secret_key,
        )
        logger.info(f"Langfuse client initialized with host: {host}")
        return _langfuse_client

    except ImportError:
        logger.warning("Langfuse package not installed. LLM tracing will be disabled.")
        _langfuse_enabled = False
        return None
    except Exception as e:
        logger.error(f"Failed to initialize Langfuse client: {e}")
        _langfuse_enabled = False
        return None


def observe_llm_call(
    name: Optional[str] = None,
    metadata: Optional[dict[str, Any]] = None,
) -> Callable[[F], F]:
    """Decorator to observe/trace an LLM call with Langfuse.

    This decorator wraps a function to automatically trace it in Langfuse.
    If Langfuse is not configured or disabled, the function runs normally without tracing.

    Args:
        name: Optional name for the trace (defaults to function name)
        metadata: Optional metadata to attach to the trace

    Example:
        @observe_llm_call(name="generate_spec", metadata={"agent": "specifier"})
        async def generate_specification(task: str) -> str:
            # LLM call here
            return result
    """

    def decorator(func: F) -> F:
        @wraps(func)
        async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
            langfuse = get_langfuse()
            trace_name = name or func.__name__

            if langfuse is None:
                # Langfuse not available, run function normally
                return await func(*args, **kwargs)

            try:
                # Create a trace for this operation
                trace = langfuse.trace(
                    name=trace_name,
                    metadata=metadata or {},
                )

                # Run the function
                result = await func(*args, **kwargs)

                # Mark trace as successful
                trace.update(
                    output=str(result) if result else None,
                    level="DEFAULT",
                )

                return result

            except Exception as e:
                # Log error to trace
                if trace:
                    trace.update(
                        level="ERROR",
                        status_message=str(e),
                    )
                raise

        @wraps(func)
        def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
            langfuse = get_langfuse()
            trace_name = name or func.__name__

            if langfuse is None:
                # Langfuse not available, run function normally
                return func(*args, **kwargs)

            try:
                # Create a trace for this operation
                trace = langfuse.trace(
                    name=trace_name,
                    metadata=metadata or {},
                )

                # Run the function
                result = func(*args, **kwargs)

                # Mark trace as successful
                trace.update(
                    output=str(result) if result else None,
                    level="DEFAULT",
                )

                return result

            except Exception as e:
                # Log error to trace
                if trace:
                    trace.update(
                        level="ERROR",
                        status_message=str(e),
                    )
                raise

        # Return appropriate wrapper based on function type
        import asyncio

        if asyncio.iscoroutinefunction(func):
            return async_wrapper  # type: ignore
        return sync_wrapper  # type: ignore

    return decorator


def create_generation(
    trace_id: str,
    name: str,
    model: str,
    input_messages: list[dict[str, str]],
    output: Optional[str] = None,
    usage: Optional[dict[str, int]] = None,
    metadata: Optional[dict[str, Any]] = None,
) -> None:
    """Record an LLM generation (completion) in Langfuse.

    Use this for more granular control over LLM call logging,
    especially when using the Dapr conversation component.

    Args:
        trace_id: Parent trace ID to attach this generation to
        name: Name for this generation (e.g., "generate_spec")
        model: Model name (e.g., "claude-opus-4-5-20251101")
        input_messages: Input messages in OpenAI format
        output: Generated output text
        usage: Token usage dict with keys: prompt_tokens, completion_tokens, total_tokens
        metadata: Additional metadata
    """
    langfuse = get_langfuse()
    if langfuse is None:
        return

    try:
        langfuse.generation(
            trace_id=trace_id,
            name=name,
            model=model,
            input=input_messages,
            output=output,
            usage=usage,
            metadata=metadata or {},
        )
    except Exception as e:
        logger.error(f"Failed to log generation to Langfuse: {e}")


def flush_langfuse() -> None:
    """Flush any pending Langfuse events.

    Call this during graceful shutdown to ensure all events are sent.
    """
    if _langfuse_client is not None:
        try:
            _langfuse_client.flush()
            logger.debug("Langfuse events flushed")
        except Exception as e:
            logger.error(f"Failed to flush Langfuse events: {e}")


def shutdown_langfuse() -> None:
    """Shutdown Langfuse client gracefully.

    Call this during application shutdown.
    """
    global _langfuse_client

    if _langfuse_client is not None:
        try:
            _langfuse_client.flush()
            _langfuse_client.shutdown()
            logger.info("Langfuse client shutdown complete")
        except Exception as e:
            logger.error(f"Error during Langfuse shutdown: {e}")
        finally:
            _langfuse_client = None


class LangfuseOpenAIChatClient:
    """Wrapper around OpenAIChatClient that instruments all LLM calls with Langfuse tracing.

    This wrapper intercepts the generate() method to automatically log all LLM calls
    to Langfuse with proper token usage, latency, and error tracking.

    Usage:
        from src.common.observability import LangfuseOpenAIChatClient

        # Use in place of OpenAIChatClient
        llm = LangfuseOpenAIChatClient(agent_name="planner")

        # Pass to DurableAgent or LLMOrchestrator
        agent = DurableAgent(..., llm=llm)
    """

    def __init__(self, agent_name: str = "unknown"):
        """Initialize the Langfuse-instrumented OpenAI client.

        Args:
            agent_name: Name of the agent using this client (for trace metadata)
        """
        from dapr_agents.llm.openai import OpenAIChatClient

        self._client = OpenAIChatClient()
        self._agent_name = agent_name
        self._trace_id: Optional[str] = None
        self._session_id: Optional[str] = None

        logger.info(f"LangfuseOpenAIChatClient initialized for agent: {agent_name}")

    def set_trace_context(self, trace_id: str, session_id: Optional[str] = None) -> None:
        """Set the trace context for subsequent LLM calls.

        Args:
            trace_id: Langfuse trace ID to attach generations to
            session_id: Optional session ID for grouping traces
        """
        self._trace_id = trace_id
        self._session_id = session_id

    def generate(self, messages: Any = None, **kwargs: Any) -> Any:
        """Generate LLM response with Langfuse instrumentation.

        Wraps the underlying OpenAIChatClient.generate() to log all calls to Langfuse.

        Args:
            messages: Input messages (string, dict, or list)
            **kwargs: Additional arguments passed to the underlying client

        Returns:
            LLMChatResponse from the underlying client
        """
        import time

        start_time = time.time()
        langfuse = get_langfuse()

        # Convert messages to list format for logging
        input_messages = self._normalize_messages(messages)

        # Get model from kwargs or use default
        model = kwargs.get("model") or self._client.config.model if hasattr(self._client, "config") else "gpt-4o"

        try:
            # Call the underlying client
            response = self._client.generate(messages, **kwargs)

            # Calculate latency
            latency_ms = int((time.time() - start_time) * 1000)

            # Log to Langfuse if available
            if langfuse:
                self._log_generation(
                    langfuse=langfuse,
                    name=f"{self._agent_name}_llm_call",
                    model=response.metadata.get("model", model),
                    input_messages=input_messages,
                    output=self._extract_output(response),
                    usage=response.metadata.get("usage"),
                    latency_ms=latency_ms,
                    metadata={
                        "agent": self._agent_name,
                        "provider": response.metadata.get("provider", "openai"),
                        "finish_reason": response.results[0].finish_reason if response.results else None,
                    },
                )

            return response

        except Exception as e:
            # Calculate latency even on error
            latency_ms = int((time.time() - start_time) * 1000)

            # Log error to Langfuse
            if langfuse:
                self._log_generation(
                    langfuse=langfuse,
                    name=f"{self._agent_name}_llm_call",
                    model=model,
                    input_messages=input_messages,
                    output=None,
                    usage=None,
                    latency_ms=latency_ms,
                    metadata={
                        "agent": self._agent_name,
                        "error": str(e),
                        "error_type": type(e).__name__,
                    },
                    level="ERROR",
                )

            raise

    def _normalize_messages(self, messages: Any) -> list[dict[str, str]]:
        """Convert messages to a normalized list format for logging."""
        if messages is None:
            return []

        if isinstance(messages, str):
            return [{"role": "user", "content": messages}]

        if isinstance(messages, dict):
            return [messages]

        if hasattr(messages, "__iter__"):
            result = []
            for msg in messages:
                if isinstance(msg, dict):
                    result.append(msg)
                elif hasattr(msg, "model_dump"):
                    result.append(msg.model_dump())
                elif hasattr(msg, "content") and hasattr(msg, "role"):
                    result.append({"role": msg.role, "content": msg.content})
                else:
                    result.append({"content": str(msg)})
            return result

        return [{"content": str(messages)}]

    def _extract_output(self, response: Any) -> Optional[str]:
        """Extract output text from LLMChatResponse."""
        if not response or not response.results:
            return None

        first_result = response.results[0]
        if first_result.message and first_result.message.content:
            return first_result.message.content

        return None

    def _log_generation(
        self,
        langfuse: "Langfuse",
        name: str,
        model: str,
        input_messages: list[dict[str, str]],
        output: Optional[str],
        usage: Optional[dict[str, Any]],
        latency_ms: int,
        metadata: Optional[dict[str, Any]] = None,
        level: str = "DEFAULT",
    ) -> None:
        """Log an LLM generation to Langfuse."""
        try:
            # If we have a trace context, attach to it; otherwise create a standalone trace
            if self._trace_id:
                langfuse.generation(
                    trace_id=self._trace_id,
                    name=name,
                    model=model,
                    input=input_messages,
                    output=output,
                    usage=usage,
                    metadata={
                        **(metadata or {}),
                        "latency_ms": latency_ms,
                    },
                    level=level,
                )
            else:
                # Create a new trace for this generation
                trace = langfuse.trace(
                    name=f"{self._agent_name}_workflow",
                    session_id=self._session_id,
                    metadata={"agent": self._agent_name},
                )
                langfuse.generation(
                    trace_id=trace.id,
                    name=name,
                    model=model,
                    input=input_messages,
                    output=output,
                    usage=usage,
                    metadata={
                        **(metadata or {}),
                        "latency_ms": latency_ms,
                    },
                    level=level,
                )

            # Flush to ensure traces are sent promptly
            langfuse.flush()

        except Exception as e:
            logger.error(f"Failed to log generation to Langfuse: {e}")

    # Delegate all other attributes to the underlying client
    def __getattr__(self, name: str) -> Any:
        """Delegate attribute access to the underlying client."""
        return getattr(self._client, name)
