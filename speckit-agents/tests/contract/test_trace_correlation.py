"""Contract tests for trace ID correlation schema.

Tests:
- TraceContext model validation
- Cross-system correlation ID formats
- Message context extraction
- Jaeger-Langfuse ID mapping

These tests validate the contract between agents and observability systems.
"""

from datetime import datetime
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError

from src.common.models import TraceContext, WorkflowMessage


class TestTraceContextSchema:
    """Contract tests for TraceContext model."""

    def test_trace_context_required_fields(self):
        """TraceContext should require workflow_id and agent_name."""
        with pytest.raises(ValidationError):
            TraceContext()

        with pytest.raises(ValidationError):
            TraceContext(workflow_id=uuid4())

        with pytest.raises(ValidationError):
            TraceContext(agent_name="test")

    def test_trace_context_with_minimal_fields(self):
        """TraceContext should accept minimal required fields."""
        workflow_id = uuid4()

        ctx = TraceContext(
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        assert ctx.workflow_id == workflow_id
        assert ctx.agent_name == "specifier"
        assert ctx.trace_id is None
        assert ctx.parent_observation_id is None

    def test_trace_context_with_all_fields(self):
        """TraceContext should accept all optional fields."""
        workflow_id = uuid4()

        ctx = TraceContext(
            trace_id="langfuse-trace-123",
            workflow_id=workflow_id,
            agent_name="planner",
            parent_observation_id="gen-456",
            span_id="span-789",
        )

        assert ctx.trace_id == "langfuse-trace-123"
        assert ctx.parent_observation_id == "gen-456"
        assert ctx.span_id == "span-789"

    def test_trace_context_workflow_id_is_uuid(self):
        """workflow_id should be a valid UUID."""
        ctx = TraceContext(
            workflow_id=uuid4(),
            agent_name="test",
        )

        assert isinstance(ctx.workflow_id, UUID)

    def test_trace_context_agent_name_constraints(self):
        """agent_name should be a non-empty string."""
        # Empty string should fail
        with pytest.raises(ValidationError):
            TraceContext(
                workflow_id=uuid4(),
                agent_name="",
            )


class TestTraceIdFormats:
    """Contract tests for trace ID formats."""

    def test_langfuse_trace_id_format(self):
        """Langfuse trace IDs should be valid strings."""
        # Langfuse typically uses UUID-like IDs
        trace_id = "550e8400-e29b-41d4-a716-446655440000"

        ctx = TraceContext(
            trace_id=trace_id,
            workflow_id=uuid4(),
            agent_name="test",
        )

        assert ctx.trace_id == trace_id

    def test_jaeger_trace_id_format(self):
        """Jaeger trace IDs (hex strings) should be storable."""
        # Jaeger uses hex string trace IDs
        jaeger_trace_id = "6b7c5c8e9f0a1b2c3d4e5f6a7b8c9d0e"

        ctx = TraceContext(
            trace_id=jaeger_trace_id,
            workflow_id=uuid4(),
            agent_name="test",
        )

        assert ctx.trace_id == jaeger_trace_id

    def test_observation_id_format(self):
        """Observation IDs can be generation or span IDs from Langfuse."""
        observation_id = "gen_abc123def456"

        ctx = TraceContext(
            workflow_id=uuid4(),
            agent_name="test",
            parent_observation_id=observation_id,
        )

        assert ctx.parent_observation_id == observation_id


class TestMessageContextConversion:
    """Contract tests for message context conversion."""

    def test_to_message_context_minimal(self):
        """to_message_context should include workflow_id."""
        workflow_id = uuid4()

        ctx = TraceContext(
            workflow_id=workflow_id,
            agent_name="test",
        )

        result = ctx.to_message_context()

        assert "workflow_id" in result
        assert result["workflow_id"] == str(workflow_id)

    def test_to_message_context_with_trace_id(self):
        """to_message_context should include langfuse_trace_id when set."""
        ctx = TraceContext(
            trace_id="trace-123",
            workflow_id=uuid4(),
            agent_name="test",
        )

        result = ctx.to_message_context()

        assert "langfuse_trace_id" in result
        assert result["langfuse_trace_id"] == "trace-123"

    def test_to_message_context_with_parent_observation(self):
        """to_message_context should include parent observation ID."""
        ctx = TraceContext(
            workflow_id=uuid4(),
            agent_name="test",
            parent_observation_id="obs-456",
        )

        result = ctx.to_message_context()

        assert "langfuse_parent_observation_id" in result
        assert result["langfuse_parent_observation_id"] == "obs-456"

    def test_to_message_context_all_fields(self):
        """to_message_context should include all trace fields."""
        workflow_id = uuid4()

        ctx = TraceContext(
            trace_id="trace-xyz",
            workflow_id=workflow_id,
            agent_name="specifier",
            parent_observation_id="gen-123",
            span_id="span-456",
        )

        result = ctx.to_message_context()

        expected_keys = [
            "workflow_id",
            "langfuse_trace_id",
            "langfuse_parent_observation_id",
        ]
        for key in expected_keys:
            assert key in result


class TestFromMessageContext:
    """Contract tests for creating TraceContext from message context."""

    def test_from_message_context_minimal(self):
        """Should create TraceContext from minimal message context."""
        workflow_id = uuid4()
        context = {}

        ctx = TraceContext.from_message_context(
            workflow_id=workflow_id,
            agent_name="planner",
            context=context,
        )

        assert ctx.workflow_id == workflow_id
        assert ctx.agent_name == "planner"
        assert ctx.trace_id is None

    def test_from_message_context_with_trace_id(self):
        """Should extract trace_id from langfuse_trace_id field."""
        workflow_id = uuid4()
        context = {
            "langfuse_trace_id": "trace-abc",
        }

        ctx = TraceContext.from_message_context(
            workflow_id=workflow_id,
            agent_name="planner",
            context=context,
        )

        assert ctx.trace_id == "trace-abc"

    def test_from_message_context_with_parent_observation(self):
        """Should extract parent observation ID."""
        workflow_id = uuid4()
        context = {
            "langfuse_parent_observation_id": "gen-789",
        }

        ctx = TraceContext.from_message_context(
            workflow_id=workflow_id,
            agent_name="planner",
            context=context,
        )

        assert ctx.parent_observation_id == "gen-789"

    def test_round_trip_conversion(self):
        """Converting to and from message context should preserve data."""
        original = TraceContext(
            trace_id="trace-round-trip",
            workflow_id=uuid4(),
            agent_name="specifier",
            parent_observation_id="gen-original",
        )

        # Convert to message context
        message_ctx = original.to_message_context()

        # Convert back
        restored = TraceContext.from_message_context(
            workflow_id=original.workflow_id,
            agent_name="planner",  # Agent name changes between phases
            context=message_ctx,
        )

        assert restored.trace_id == original.trace_id
        assert restored.workflow_id == original.workflow_id
        assert restored.parent_observation_id == original.parent_observation_id


class TestWorkflowMessageTraceContext:
    """Contract tests for trace context in workflow messages."""

    def test_message_preserves_trace_context(self):
        """WorkflowMessage should preserve trace context in context field."""
        workflow_id = uuid4()

        trace_ctx = TraceContext(
            trace_id="trace-msg",
            workflow_id=workflow_id,
            agent_name="orchestrator",
            parent_observation_id="gen-msg",
        )

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="execute_phase",
            context=trace_ctx.to_message_context(),
        )

        # Verify trace context in message
        assert "langfuse_trace_id" in message.context
        assert message.context["langfuse_trace_id"] == "trace-msg"

    def test_extract_trace_context_from_message(self):
        """Should extract TraceContext from WorkflowMessage."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="phase_complete",
            context={
                "langfuse_trace_id": "trace-extract",
                "langfuse_parent_observation_id": "gen-extract",
                "other_data": "preserved",
            },
        )

        ctx = TraceContext.from_message_context(
            workflow_id=message.workflow_id,
            agent_name="planner",
            context=message.context,
        )

        assert ctx.trace_id == "trace-extract"
        assert ctx.parent_observation_id == "gen-extract"


class TestCrossSystemCorrelation:
    """Contract tests for cross-system correlation (Langfuse + Jaeger)."""

    def test_workflow_id_as_correlation_key(self):
        """workflow_id should serve as primary correlation key."""
        workflow_id = uuid4()

        # Same workflow ID used in Langfuse trace
        langfuse_ctx = TraceContext(
            trace_id="langfuse-trace-1",
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        # And in Jaeger span
        jaeger_ctx = TraceContext(
            trace_id="0123456789abcdef",  # Jaeger hex format
            workflow_id=workflow_id,
            agent_name="specifier",
            span_id="abcdef0123456789",
        )

        # Both should reference same workflow
        assert langfuse_ctx.workflow_id == jaeger_ctx.workflow_id

    def test_trace_context_includes_both_systems(self):
        """TraceContext should support both Langfuse and Jaeger IDs."""
        workflow_id = uuid4()

        # During execution, context may have both system IDs
        ctx = TraceContext(
            trace_id="langfuse-abc",
            workflow_id=workflow_id,
            agent_name="planner",
            span_id="jaeger-span-123",
        )

        assert ctx.trace_id is not None  # Langfuse trace
        assert ctx.span_id is not None  # Jaeger span

    def test_message_context_supports_correlation(self):
        """Message context should include correlation-relevant fields."""
        workflow_id = uuid4()

        ctx = TraceContext(
            trace_id="correlation-trace",
            workflow_id=workflow_id,
            agent_name="test",
            parent_observation_id="correlation-obs",
        )

        message_ctx = ctx.to_message_context()

        # These fields enable cross-system lookup
        correlation_fields = ["workflow_id", "langfuse_trace_id"]
        for field in correlation_fields:
            assert field in message_ctx


class TestTraceContextValidation:
    """Contract tests for trace context validation."""

    def test_reject_invalid_workflow_id(self):
        """Should reject invalid workflow_id types."""
        with pytest.raises(ValidationError):
            TraceContext(
                workflow_id="not-a-uuid",
                agent_name="test",
            )

    def test_accept_uuid_string_conversion(self):
        """Should accept UUID strings and convert them."""
        uuid_str = str(uuid4())

        # Pydantic should convert string to UUID
        ctx = TraceContext(
            workflow_id=uuid_str,
            agent_name="test",
        )

        assert isinstance(ctx.workflow_id, UUID)

    def test_trace_id_can_be_none(self):
        """trace_id should be optional (None for new workflows)."""
        ctx = TraceContext(
            workflow_id=uuid4(),
            agent_name="test",
        )

        assert ctx.trace_id is None

    def test_empty_agent_name_rejected(self):
        """Empty agent_name should be rejected."""
        with pytest.raises(ValidationError):
            TraceContext(
                workflow_id=uuid4(),
                agent_name="",
            )
