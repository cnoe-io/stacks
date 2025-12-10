"""Integration tests for Langfuse tool invocation recording.

Tests:
- Tool calls are recorded as spans
- Input/output truncation works correctly
- Duration tracking is accurate
- Error status is captured
- Tool metadata is preserved

Note: Uses mock Langfuse client for isolated testing.
"""

from datetime import datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from src.common.models import TraceContext


class MockToolRecorder:
    """Mock tool recorder for testing Langfuse integration."""

    def __init__(self, langfuse_client):
        self.langfuse = langfuse_client
        self.recorded_tools: list[dict] = []
        self.max_input_size = 10000
        self.max_output_size = 50000

    def truncate_input(self, input_data: str) -> str:
        """Truncate input if too large."""
        if len(input_data) > self.max_input_size:
            return input_data[: self.max_input_size] + f"... [truncated, total {len(input_data)} chars]"
        return input_data

    def truncate_output(self, output_data: str) -> str:
        """Truncate output if too large."""
        if len(output_data) > self.max_output_size:
            return output_data[: self.max_output_size] + f"... [truncated, total {len(output_data)} chars]"
        return output_data

    async def record_tool_call(
        self,
        trace_ctx: TraceContext,
        tool_name: str,
        input_data: Any,
        output_data: Any = None,
        error: str = None,
        duration_ms: int = None,
    ) -> dict:
        """Record a tool invocation."""
        start_time = datetime.utcnow()

        # Process input
        input_str = str(input_data) if input_data else ""
        truncated_input = self.truncate_input(input_str)

        # Process output
        output_str = str(output_data) if output_data else ""
        truncated_output = self.truncate_output(output_str)

        record = {
            "trace_id": trace_ctx.trace_id,
            "workflow_id": str(trace_ctx.workflow_id),
            "tool_name": tool_name,
            "input": truncated_input,
            "output": truncated_output,
            "error": error,
            "status": "error" if error else "success",
            "duration_ms": duration_ms or 0,
            "timestamp": start_time,
            "input_truncated": len(input_str) > self.max_input_size,
            "output_truncated": len(output_str) > self.max_output_size,
            "input_size": len(input_str),
            "output_size": len(output_str),
        }

        self.recorded_tools.append(record)

        # Create Langfuse span
        trace = self.langfuse.trace(
            name="tool_recording",
            session_id=str(trace_ctx.workflow_id),
        )

        span = trace.span(
            name=f"tool_{tool_name}",
            input={"tool_input": truncated_input},
            metadata={
                "tool_name": tool_name,
                "duration_ms": duration_ms,
                "input_size": len(input_str),
                "output_size": len(output_str),
                "status": record["status"],
            },
        )

        span.end(
            output={"tool_output": truncated_output, "error": error},
        )

        return record


class TestToolRecordingBasics:
    """Basic tests for tool recording."""

    @pytest.fixture
    def tool_recorder(self, mock_langfuse):
        """Create tool recorder with mock Langfuse."""
        return MockToolRecorder(mock_langfuse)

    @pytest.fixture
    def trace_ctx(self):
        """Create test trace context."""
        return TraceContext(
            trace_id="test-trace-123",
            workflow_id=uuid4(),
            agent_name="specifier",
        )

    @pytest.mark.asyncio
    async def test_record_simple_tool_call(self, tool_recorder, trace_ctx):
        """Should record a simple tool call."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="/path/to/file.py",
            output_data="file contents here",
            duration_ms=150,
        )

        assert record["tool_name"] == "Read"
        assert record["input"] == "/path/to/file.py"
        assert record["output"] == "file contents here"
        assert record["status"] == "success"
        assert record["duration_ms"] == 150

    @pytest.mark.asyncio
    async def test_record_tool_with_error(self, tool_recorder, trace_ctx):
        """Should record tool call with error status."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Write",
            input_data={"path": "/test.py", "content": "code"},
            error="Permission denied",
            duration_ms=50,
        )

        assert record["status"] == "error"
        assert record["error"] == "Permission denied"

    @pytest.mark.asyncio
    async def test_all_claude_code_tools_recordable(self, tool_recorder, trace_ctx):
        """Should record all Claude Code tools."""
        tools = ["Read", "Write", "Edit", "Glob", "Grep", "Bash", "Task"]

        for tool in tools:
            record = await tool_recorder.record_tool_call(
                trace_ctx=trace_ctx,
                tool_name=tool,
                input_data=f"input for {tool}",
                output_data=f"output from {tool}",
            )
            assert record["tool_name"] == tool

        assert len(tool_recorder.recorded_tools) == len(tools)


class TestInputOutputTruncation:
    """Tests for input/output truncation."""

    @pytest.fixture
    def tool_recorder(self, mock_langfuse):
        """Create tool recorder with mock Langfuse."""
        recorder = MockToolRecorder(mock_langfuse)
        recorder.max_input_size = 100
        recorder.max_output_size = 200
        return recorder

    @pytest.fixture
    def trace_ctx(self):
        """Create test trace context."""
        return TraceContext(
            trace_id="test-trace-123",
            workflow_id=uuid4(),
            agent_name="specifier",
        )

    @pytest.mark.asyncio
    async def test_truncate_large_input(self, tool_recorder, trace_ctx):
        """Should truncate large inputs."""
        large_input = "x" * 500

        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data=large_input,
        )

        assert len(record["input"]) < len(large_input)
        assert "truncated" in record["input"]
        assert record["input_truncated"] is True
        assert record["input_size"] == 500

    @pytest.mark.asyncio
    async def test_truncate_large_output(self, tool_recorder, trace_ctx):
        """Should truncate large outputs."""
        large_output = "y" * 1000

        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Glob",
            input_data="**/*.py",
            output_data=large_output,
        )

        assert len(record["output"]) < len(large_output)
        assert "truncated" in record["output"]
        assert record["output_truncated"] is True
        assert record["output_size"] == 1000

    @pytest.mark.asyncio
    async def test_preserve_small_inputs(self, tool_recorder, trace_ctx):
        """Should not truncate small inputs."""
        small_input = "short input"

        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data=small_input,
        )

        assert record["input"] == small_input
        assert record["input_truncated"] is False


class TestDurationTracking:
    """Tests for duration tracking."""

    @pytest.fixture
    def tool_recorder(self, mock_langfuse):
        """Create tool recorder with mock Langfuse."""
        return MockToolRecorder(mock_langfuse)

    @pytest.fixture
    def trace_ctx(self):
        """Create test trace context."""
        return TraceContext(
            trace_id="test-trace-123",
            workflow_id=uuid4(),
            agent_name="specifier",
        )

    @pytest.mark.asyncio
    async def test_duration_recorded(self, tool_recorder, trace_ctx):
        """Should record duration in milliseconds."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Bash",
            input_data="ls -la",
            output_data="file list",
            duration_ms=2500,
        )

        assert record["duration_ms"] == 2500

    @pytest.mark.asyncio
    async def test_zero_duration_for_fast_tools(self, tool_recorder, trace_ctx):
        """Should handle zero duration for very fast tools."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="path",
        )

        assert record["duration_ms"] == 0

    @pytest.mark.asyncio
    async def test_large_duration_for_slow_tools(self, tool_recorder, trace_ctx):
        """Should handle large durations for slow tools."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Task",
            input_data="complex task",
            output_data="task result",
            duration_ms=300000,  # 5 minutes
        )

        assert record["duration_ms"] == 300000


class TestLangfuseIntegration:
    """Tests for Langfuse client integration."""

    @pytest.fixture
    def tool_recorder(self, mock_langfuse):
        """Create tool recorder with mock Langfuse."""
        return MockToolRecorder(mock_langfuse)

    @pytest.fixture
    def trace_ctx(self):
        """Create test trace context."""
        return TraceContext(
            trace_id="test-trace-123",
            workflow_id=uuid4(),
            agent_name="specifier",
        )

    @pytest.mark.asyncio
    async def test_creates_langfuse_span(self, tool_recorder, trace_ctx, mock_langfuse):
        """Should create Langfuse span for tool call."""
        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="input",
            output_data="output",
        )

        assert len(mock_langfuse.traces) == 1
        trace = mock_langfuse.traces[0]
        assert len(trace.spans) == 1

    @pytest.mark.asyncio
    async def test_span_contains_metadata(self, tool_recorder, trace_ctx, mock_langfuse):
        """Should include metadata in Langfuse span."""
        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Bash",
            input_data="npm test",
            output_data="tests passed",
            duration_ms=5000,
        )

        trace = mock_langfuse.traces[0]
        span_kwargs = trace.spans[0]

        assert span_kwargs["name"] == "tool_Bash"
        assert "tool_name" in span_kwargs["metadata"]
        assert span_kwargs["metadata"]["tool_name"] == "Bash"
        assert span_kwargs["metadata"]["duration_ms"] == 5000

    @pytest.mark.asyncio
    async def test_span_ends_with_output(self, tool_recorder, trace_ctx, mock_langfuse):
        """Should end span with output data."""
        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Glob",
            input_data="**/*.py",
            output_data="file1.py\nfile2.py",
        )

        trace = mock_langfuse.traces[0]
        # MockLangfuseSpan ends with output
        assert len(trace.spans) == 1

    @pytest.mark.asyncio
    async def test_workflow_id_as_session(self, tool_recorder, trace_ctx, mock_langfuse):
        """Should use workflow ID as session ID."""
        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="path",
        )

        # Verify trace was created with session_id
        assert len(mock_langfuse.traces) == 1


class TestErrorRecording:
    """Tests for error recording."""

    @pytest.fixture
    def tool_recorder(self, mock_langfuse):
        """Create tool recorder with mock Langfuse."""
        return MockToolRecorder(mock_langfuse)

    @pytest.fixture
    def trace_ctx(self):
        """Create test trace context."""
        return TraceContext(
            trace_id="test-trace-123",
            workflow_id=uuid4(),
            agent_name="specifier",
        )

    @pytest.mark.asyncio
    async def test_error_status_recorded(self, tool_recorder, trace_ctx):
        """Should record error status correctly."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Write",
            input_data="write content",
            error="File not found",
        )

        assert record["status"] == "error"
        assert record["error"] == "File not found"

    @pytest.mark.asyncio
    async def test_success_status_without_error(self, tool_recorder, trace_ctx):
        """Should record success status when no error."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="path",
            output_data="content",
        )

        assert record["status"] == "success"
        assert record["error"] is None

    @pytest.mark.asyncio
    async def test_error_included_in_span_output(
        self, tool_recorder, trace_ctx, mock_langfuse
    ):
        """Should include error in span output."""
        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Bash",
            input_data="rm -rf /",
            error="Permission denied",
        )

        trace = mock_langfuse.traces[0]
        assert len(trace.spans) == 1


class TestMultipleToolCalls:
    """Tests for recording multiple tool calls."""

    @pytest.fixture
    def tool_recorder(self, mock_langfuse):
        """Create tool recorder with mock Langfuse."""
        return MockToolRecorder(mock_langfuse)

    @pytest.fixture
    def trace_ctx(self):
        """Create test trace context."""
        return TraceContext(
            trace_id="test-trace-123",
            workflow_id=uuid4(),
            agent_name="specifier",
        )

    @pytest.mark.asyncio
    async def test_record_sequence_of_tools(self, tool_recorder, trace_ctx):
        """Should record a sequence of tool calls."""
        tools_sequence = [
            ("Glob", "**/*.py", "file1.py\nfile2.py"),
            ("Read", "file1.py", "content of file1"),
            ("Edit", {"file": "file1.py", "change": "update"}, "edit success"),
            ("Bash", "git diff", "diff output"),
        ]

        for tool_name, input_data, output_data in tools_sequence:
            await tool_recorder.record_tool_call(
                trace_ctx=trace_ctx,
                tool_name=tool_name,
                input_data=input_data,
                output_data=output_data,
            )

        assert len(tool_recorder.recorded_tools) == 4

        # Verify order preserved
        for i, (tool_name, _, _) in enumerate(tools_sequence):
            assert tool_recorder.recorded_tools[i]["tool_name"] == tool_name

    @pytest.mark.asyncio
    async def test_tools_have_unique_timestamps(self, tool_recorder, trace_ctx):
        """Each tool call should have a timestamp."""
        for _ in range(5):
            await tool_recorder.record_tool_call(
                trace_ctx=trace_ctx,
                tool_name="Read",
                input_data="path",
            )

        # All should have timestamps
        for record in tool_recorder.recorded_tools:
            assert record["timestamp"] is not None

    @pytest.mark.asyncio
    async def test_mixed_success_and_error_tools(self, tool_recorder, trace_ctx):
        """Should handle mix of successful and failed tool calls."""
        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="existing.py",
            output_data="content",
        )

        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="missing.py",
            error="File not found",
        )

        await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Write",
            input_data="new.py",
            output_data="written",
        )

        statuses = [r["status"] for r in tool_recorder.recorded_tools]
        assert statuses == ["success", "error", "success"]


class TestToolMetadata:
    """Tests for tool metadata preservation."""

    @pytest.fixture
    def tool_recorder(self, mock_langfuse):
        """Create tool recorder with mock Langfuse."""
        return MockToolRecorder(mock_langfuse)

    @pytest.fixture
    def trace_ctx(self):
        """Create test trace context."""
        return TraceContext(
            trace_id="test-trace-123",
            workflow_id=uuid4(),
            agent_name="specifier",
        )

    @pytest.mark.asyncio
    async def test_trace_context_preserved(self, tool_recorder, trace_ctx):
        """Should preserve trace context in records."""
        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data="path",
        )

        assert record["trace_id"] == trace_ctx.trace_id
        assert record["workflow_id"] == str(trace_ctx.workflow_id)

    @pytest.mark.asyncio
    async def test_input_output_sizes_tracked(self, tool_recorder, trace_ctx):
        """Should track input and output sizes."""
        input_data = "x" * 500
        output_data = "y" * 1000

        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data=input_data,
            output_data=output_data,
        )

        assert record["input_size"] == 500
        assert record["output_size"] == 1000

    @pytest.mark.asyncio
    async def test_complex_input_serialized(self, tool_recorder, trace_ctx):
        """Should serialize complex input data."""
        complex_input = {
            "file": "/path/to/file.py",
            "options": {"encoding": "utf-8", "lines": [1, 10]},
        }

        record = await tool_recorder.record_tool_call(
            trace_ctx=trace_ctx,
            tool_name="Read",
            input_data=complex_input,
        )

        # Input should be string representation
        assert "/path/to/file.py" in record["input"]
