"""Tool invocation recorder for Langfuse observability.

Records Claude SDK tool calls as Langfuse spans with:
- Tool name, parameters, result, duration
- Error tracking and status
- Token usage attribution
- Correlation with parent generation spans

Integrates with BaseClaudeAgent Langfuse tracing for
end-to-end tool call visibility.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional

logger = logging.getLogger(__name__)


@dataclass
class ToolInvocation:
    """Recorded tool invocation for observability."""

    tool_name: str
    input_params: dict[str, Any]
    output: Optional[Any] = None
    error: Optional[str] = None
    duration_ms: float = 0.0
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    status: str = "pending"  # pending, success, error


class ToolRecorder:
    """Records tool invocations to Langfuse spans.

    Provides:
    - Tool call span creation with parent linking
    - Parameter and result capture
    - Duration tracking
    - Error recording with stack traces
    - Batch flushing for performance
    """

    def __init__(self) -> None:
        """Initialize the tool recorder."""
        self._langfuse: Optional[Any] = None
        self._current_trace: Optional[Any] = None
        self._pending_spans: list[Any] = []
        self._invocations: list[ToolInvocation] = []

    def set_langfuse_trace(self, trace: Any) -> None:
        """Set the parent Langfuse trace for tool spans.

        Args:
            trace: Langfuse trace object from agent
        """
        self._current_trace = trace

    def set_langfuse_client(self, client: Any) -> None:
        """Set the Langfuse client for direct span creation.

        Args:
            client: Langfuse client instance
        """
        self._langfuse = client

    def start_tool_span(
        self,
        tool_name: str,
        input_params: dict[str, Any],
        metadata: Optional[dict[str, Any]] = None,
    ) -> ToolInvocation:
        """Start recording a tool invocation.

        Args:
            tool_name: Name of the tool being invoked
            input_params: Tool input parameters
            metadata: Additional metadata

        Returns:
            ToolInvocation for tracking
        """
        invocation = ToolInvocation(
            tool_name=tool_name,
            input_params=input_params,
            started_at=datetime.utcnow(),
        )

        # Create Langfuse span if trace available
        if self._current_trace:
            try:
                # Create span under current trace
                span = self._current_trace.span(
                    name=f"tool:{tool_name}",
                    input=self._truncate_params(input_params),
                    metadata={
                        "tool_name": tool_name,
                        "start_time": invocation.started_at.isoformat(),
                        **(metadata or {}),
                    },
                )
                self._pending_spans.append((invocation, span))
            except Exception as e:
                logger.warning(f"Failed to create tool span: {e}")

        self._invocations.append(invocation)
        return invocation

    def end_tool_span(
        self,
        invocation: ToolInvocation,
        output: Any = None,
        error: Optional[str] = None,
    ) -> None:
        """End a tool invocation recording.

        Args:
            invocation: ToolInvocation to complete
            output: Tool output/result
            error: Error message if failed
        """
        invocation.ended_at = datetime.utcnow()
        invocation.output = output
        invocation.error = error

        if error:
            invocation.status = "error"
        else:
            invocation.status = "success"

        # Calculate duration
        if invocation.started_at and invocation.ended_at:
            delta = invocation.ended_at - invocation.started_at
            invocation.duration_ms = delta.total_seconds() * 1000

        # End Langfuse span
        for inv, span in self._pending_spans:
            if inv is invocation:
                try:
                    span.end(
                        output=self._truncate_output(output),
                        level="ERROR" if error else "DEFAULT",
                        status_message=error,
                    )
                except Exception as e:
                    logger.warning(f"Failed to end tool span: {e}")
                self._pending_spans.remove((inv, span))
                break

    def record_tool_error(
        self,
        invocation: ToolInvocation,
        exception: Exception,
    ) -> None:
        """Record an exception for a tool invocation.

        Args:
            invocation: ToolInvocation that failed
            exception: Exception that occurred
        """
        error_msg = f"{type(exception).__name__}: {str(exception)}"
        self.end_tool_span(invocation, error=error_msg)

        # Log error event to trace
        if self._current_trace:
            try:
                self._current_trace.event(
                    name="tool_error",
                    level="ERROR",
                    metadata={
                        "tool_name": invocation.tool_name,
                        "error_type": type(exception).__name__,
                        "error_message": str(exception),
                    },
                )
            except Exception as e:
                logger.warning(f"Failed to log tool error: {e}")

    def get_invocations(self) -> list[ToolInvocation]:
        """Get all recorded tool invocations.

        Returns:
            List of ToolInvocation records
        """
        return self._invocations.copy()

    def get_summary(self) -> dict[str, Any]:
        """Get summary statistics of tool invocations.

        Returns:
            Summary dict with counts, durations, errors
        """
        total = len(self._invocations)
        successful = sum(1 for i in self._invocations if i.status == "success")
        failed = sum(1 for i in self._invocations if i.status == "error")
        pending = sum(1 for i in self._invocations if i.status == "pending")

        durations = [i.duration_ms for i in self._invocations if i.duration_ms > 0]
        avg_duration = sum(durations) / len(durations) if durations else 0

        return {
            "total_invocations": total,
            "successful": successful,
            "failed": failed,
            "pending": pending,
            "avg_duration_ms": round(avg_duration, 2),
            "tools_used": list(set(i.tool_name for i in self._invocations)),
        }

    def flush(self) -> None:
        """Flush any pending spans to Langfuse."""
        if self._langfuse:
            try:
                self._langfuse.flush()
            except Exception as e:
                logger.warning(f"Failed to flush tool spans: {e}")

    def clear(self) -> None:
        """Clear all recorded invocations."""
        self._invocations.clear()
        self._pending_spans.clear()

    def _truncate_params(
        self,
        params: dict[str, Any],
        max_length: int = 1000,
    ) -> dict[str, Any]:
        """Truncate parameter values for storage.

        Args:
            params: Parameters to truncate
            max_length: Maximum string length

        Returns:
            Truncated parameters
        """
        result = {}
        for key, value in params.items():
            if isinstance(value, str) and len(value) > max_length:
                result[key] = value[:max_length] + "...[truncated]"
            elif isinstance(value, (dict, list)):
                str_val = str(value)
                if len(str_val) > max_length:
                    result[key] = str_val[:max_length] + "...[truncated]"
                else:
                    result[key] = value
            else:
                result[key] = value
        return result

    def _truncate_output(
        self,
        output: Any,
        max_length: int = 2000,
    ) -> Any:
        """Truncate output for storage.

        Args:
            output: Output to truncate
            max_length: Maximum length

        Returns:
            Truncated output
        """
        if output is None:
            return None

        str_output = str(output)
        if len(str_output) > max_length:
            return str_output[:max_length] + "...[truncated]"
        return output


# Singleton instance
_tool_recorder: Optional[ToolRecorder] = None


def get_tool_recorder() -> ToolRecorder:
    """Get or create the singleton tool recorder."""
    global _tool_recorder
    if _tool_recorder is None:
        _tool_recorder = ToolRecorder()
    return _tool_recorder


# Context manager for tool recording
class RecordTool:
    """Context manager for recording tool invocations.

    Usage:
        recorder = get_tool_recorder()
        with RecordTool(recorder, "my_tool", {"param": "value"}) as invocation:
            result = my_tool(param="value")
            invocation.output = result
    """

    def __init__(
        self,
        recorder: ToolRecorder,
        tool_name: str,
        input_params: dict[str, Any],
        metadata: Optional[dict[str, Any]] = None,
    ) -> None:
        """Initialize the context manager.

        Args:
            recorder: ToolRecorder instance
            tool_name: Name of tool
            input_params: Tool parameters
            metadata: Additional metadata
        """
        self.recorder = recorder
        self.tool_name = tool_name
        self.input_params = input_params
        self.metadata = metadata
        self.invocation: Optional[ToolInvocation] = None

    def __enter__(self) -> ToolInvocation:
        """Start recording."""
        self.invocation = self.recorder.start_tool_span(
            self.tool_name,
            self.input_params,
            self.metadata,
        )
        return self.invocation

    def __exit__(
        self,
        exc_type: Optional[type],
        exc_val: Optional[Exception],
        exc_tb: Any,
    ) -> bool:
        """End recording."""
        if self.invocation:
            if exc_val:
                self.recorder.record_tool_error(self.invocation, exc_val)
            else:
                self.recorder.end_tool_span(
                    self.invocation,
                    output=self.invocation.output,
                )
        return False  # Don't suppress exceptions
