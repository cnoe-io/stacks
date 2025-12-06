"""Contract tests for tool invocation schema.

Tests:
- ToolInvocation dataclass validation
- Tool recording span format
- Error status tracking format
"""

from datetime import datetime
from uuid import uuid4

import pytest

from src.services.tool_recorder import ToolInvocation, ToolRecorder, RecordTool


class TestToolInvocationContract:
    """Contract tests for ToolInvocation schema."""

    def test_tool_invocation_creation(self):
        """ToolInvocation should create with required fields."""
        invocation = ToolInvocation(
            tool_name="Read",
            input_params={"file_path": "/path/to/file.py"},
        )

        assert invocation.tool_name == "Read"
        assert invocation.input_params["file_path"] == "/path/to/file.py"
        assert invocation.output is None
        assert invocation.error is None
        assert invocation.duration_ms == 0.0
        assert invocation.status == "pending"

    def test_tool_invocation_with_output(self):
        """ToolInvocation should track output."""
        invocation = ToolInvocation(
            tool_name="Glob",
            input_params={"pattern": "**/*.py"},
            output=["file1.py", "file2.py"],
            status="success",
        )

        assert invocation.output == ["file1.py", "file2.py"]
        assert invocation.status == "success"

    def test_tool_invocation_with_error(self):
        """ToolInvocation should track errors."""
        invocation = ToolInvocation(
            tool_name="Read",
            input_params={"file_path": "/nonexistent"},
            error="FileNotFoundError: File not found",
            status="error",
        )

        assert invocation.error is not None
        assert "FileNotFoundError" in invocation.error
        assert invocation.status == "error"

    def test_tool_invocation_with_timing(self):
        """ToolInvocation should track timing."""
        now = datetime.utcnow()

        invocation = ToolInvocation(
            tool_name="Bash",
            input_params={"command": "ls -la"},
            started_at=now,
            ended_at=now,
            duration_ms=123.45,
            status="success",
        )

        assert invocation.started_at is not None
        assert invocation.ended_at is not None
        assert invocation.duration_ms == 123.45


class TestToolRecorderContract:
    """Contract tests for ToolRecorder behavior."""

    def test_recorder_start_span(self):
        """Recorder should create invocation on start."""
        recorder = ToolRecorder()

        invocation = recorder.start_tool_span(
            tool_name="Write",
            input_params={"file_path": "/test.py", "content": "..."},
        )

        assert invocation.tool_name == "Write"
        assert invocation.started_at is not None
        assert invocation.status == "pending"

    def test_recorder_end_span_success(self):
        """Recorder should update invocation on success."""
        recorder = ToolRecorder()

        invocation = recorder.start_tool_span(
            tool_name="Edit",
            input_params={"file_path": "/test.py"},
        )

        recorder.end_tool_span(
            invocation,
            output={"lines_changed": 5},
        )

        assert invocation.status == "success"
        assert invocation.output == {"lines_changed": 5}
        assert invocation.ended_at is not None
        assert invocation.duration_ms > 0

    def test_recorder_end_span_error(self):
        """Recorder should update invocation on error."""
        recorder = ToolRecorder()

        invocation = recorder.start_tool_span(
            tool_name="Bash",
            input_params={"command": "invalid_command"},
        )

        recorder.end_tool_span(
            invocation,
            error="Command not found",
        )

        assert invocation.status == "error"
        assert invocation.error == "Command not found"

    def test_recorder_get_invocations(self):
        """Recorder should track all invocations."""
        recorder = ToolRecorder()

        # Create multiple invocations
        inv1 = recorder.start_tool_span("Read", {"file": "a.py"})
        inv2 = recorder.start_tool_span("Write", {"file": "b.py"})

        recorder.end_tool_span(inv1, output="content")
        recorder.end_tool_span(inv2, output="ok")

        invocations = recorder.get_invocations()

        assert len(invocations) == 2
        assert invocations[0].tool_name == "Read"
        assert invocations[1].tool_name == "Write"

    def test_recorder_get_summary(self):
        """Recorder should provide summary statistics."""
        recorder = ToolRecorder()

        inv1 = recorder.start_tool_span("Read", {"file": "a.py"})
        inv2 = recorder.start_tool_span("Read", {"file": "b.py"})
        inv3 = recorder.start_tool_span("Write", {"file": "c.py"})

        recorder.end_tool_span(inv1, output="ok")
        recorder.end_tool_span(inv2, error="not found")
        recorder.end_tool_span(inv3, output="ok")

        summary = recorder.get_summary()

        assert summary["total_invocations"] == 3
        assert summary["successful"] == 2
        assert summary["failed"] == 1
        assert "Read" in summary["tools_used"]
        assert "Write" in summary["tools_used"]

    def test_recorder_clear(self):
        """Recorder should clear all invocations."""
        recorder = ToolRecorder()

        inv = recorder.start_tool_span("Read", {"file": "a.py"})
        recorder.end_tool_span(inv, output="ok")

        recorder.clear()

        assert len(recorder.get_invocations()) == 0


class TestRecordToolContextManager:
    """Contract tests for RecordTool context manager."""

    def test_record_tool_success(self):
        """Context manager should record successful tool call."""
        recorder = ToolRecorder()

        with RecordTool(recorder, "Read", {"file": "test.py"}) as invocation:
            invocation.output = "file content"

        assert invocation.status == "success"
        assert invocation.output == "file content"

    def test_record_tool_exception(self):
        """Context manager should record exception."""
        recorder = ToolRecorder()

        with pytest.raises(ValueError):
            with RecordTool(recorder, "Read", {"file": "bad.py"}) as invocation:
                raise ValueError("Test error")

        assert invocation.status == "error"
        assert "ValueError" in invocation.error

    def test_record_tool_with_metadata(self):
        """Context manager should accept metadata."""
        recorder = ToolRecorder()

        with RecordTool(
            recorder,
            "Bash",
            {"command": "ls"},
            metadata={"timeout": 30},
        ) as invocation:
            invocation.output = "file1.py\nfile2.py"

        assert invocation.status == "success"


class TestToolInputTruncation:
    """Contract tests for input/output truncation."""

    def test_truncate_long_input(self):
        """Long input parameters should be truncated."""
        recorder = ToolRecorder()

        long_content = "x" * 5000

        # Internal truncation method
        truncated = recorder._truncate_params(
            {"content": long_content},
            max_length=1000,
        )

        assert len(truncated["content"]) <= 1020  # 1000 + "[truncated]"
        assert "[truncated]" in truncated["content"]

    def test_truncate_long_output(self):
        """Long output should be truncated."""
        recorder = ToolRecorder()

        long_output = "y" * 5000

        truncated = recorder._truncate_output(long_output, max_length=2000)

        assert len(truncated) <= 2020
        assert "[truncated]" in truncated

    def test_preserve_short_values(self):
        """Short values should not be truncated."""
        recorder = ToolRecorder()

        short_content = "short"

        truncated = recorder._truncate_params(
            {"content": short_content},
            max_length=1000,
        )

        assert truncated["content"] == short_content
