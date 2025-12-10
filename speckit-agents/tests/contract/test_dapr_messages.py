"""Contract tests for Dapr pub/sub message formats.

Tests:
- WorkflowMessage schema validation
- CloudEvent envelope format
- Trace context propagation format
"""

from datetime import datetime
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError

from src.common.models import (
    TraceContext,
    WorkflowMessage,
    WorkflowPhase,
)


class TestWorkflowMessageContract:
    """Contract tests for Dapr pub/sub message schema."""

    def test_valid_message_minimal(self):
        """Message with minimum required fields should be valid."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="process_feature",
        )

        assert message.id is not None
        assert message.source == "orchestrator"
        assert message.workflow_id == workflow_id
        assert message.task == "process_feature"
        assert message.type == "TriggerAction"
        assert message.context == {}
        assert message.timestamp is not None

    def test_valid_message_with_context(self):
        """Message with context should be valid."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="phase_complete:specification",
            context={
                "completed_phase": "specification",
                "artifact_path": "spec.md",
                "langfuse_trace_id": "trace-abc123",
            },
        )

        assert message.context["completed_phase"] == "specification"
        assert "langfuse_trace_id" in message.context

    def test_valid_message_phase_complete(self):
        """Phase completion message should follow expected format."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="planner",
            workflow_id=workflow_id,
            task="phase_complete:planning",
            context={
                "completed_phase": "planning",
                "result": {
                    "artifacts": ["research.md", "data-model.md", "plan.md"],
                    "artifact_count": 3,
                },
            },
        )

        assert message.task.startswith("phase_complete:")
        assert "completed_phase" in message.context
        assert message.context["result"]["artifact_count"] == 3

    def test_message_serialization_json(self):
        """Message should serialize to JSON for Dapr pub/sub."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="Execute planning phase",
            context={"phase": "planning"},
        )

        json_data = message.model_dump_json()

        # Verify JSON structure
        assert str(workflow_id) in json_data
        assert "orchestrator" in json_data
        assert "planning" in json_data
        assert "TriggerAction" in json_data

    def test_message_deserialization(self):
        """Message should deserialize from JSON correctly."""
        workflow_id = uuid4()

        original = WorkflowMessage(
            source="task-generator",
            workflow_id=workflow_id,
            task="generate_tasks",
            context={"input_artifacts": ["spec.md", "plan.md"]},
        )

        json_data = original.model_dump_json()
        restored = WorkflowMessage.model_validate_json(json_data)

        assert restored.source == original.source
        assert restored.workflow_id == original.workflow_id
        assert restored.task == original.task
        assert restored.context == original.context

    def test_message_id_uniqueness(self):
        """Each message should have a unique ID."""
        workflow_id = uuid4()

        messages = [
            WorkflowMessage(
                source="orchestrator",
                workflow_id=workflow_id,
                task=f"task_{i}",
            )
            for i in range(5)
        ]

        ids = [m.id for m in messages]
        assert len(ids) == len(set(ids)), "Message IDs should be unique"


class TestTraceContextContract:
    """Contract tests for trace context propagation."""

    def test_trace_context_creation(self):
        """TraceContext should create with required fields."""
        workflow_id = uuid4()

        ctx = TraceContext(
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        assert ctx.workflow_id == workflow_id
        assert ctx.agent_name == "specifier"
        assert ctx.trace_id is None
        assert ctx.parent_observation_id is None

    def test_trace_context_with_ids(self):
        """TraceContext should accept trace and observation IDs."""
        workflow_id = uuid4()

        ctx = TraceContext(
            trace_id="trace-xyz789",
            workflow_id=workflow_id,
            agent_name="planner",
            parent_observation_id="gen-abc123",
        )

        assert ctx.trace_id == "trace-xyz789"
        assert ctx.parent_observation_id == "gen-abc123"

    def test_trace_context_to_message_context(self):
        """TraceContext should convert to message context dict."""
        workflow_id = uuid4()

        ctx = TraceContext(
            trace_id="trace-abc",
            workflow_id=workflow_id,
            agent_name="implementer",
            parent_observation_id="span-123",
        )

        msg_ctx = ctx.to_message_context()

        assert msg_ctx["langfuse_trace_id"] == "trace-abc"
        assert msg_ctx["langfuse_parent_observation_id"] == "span-123"

    def test_trace_context_from_message_context(self):
        """TraceContext should extract from message context."""
        workflow_id = uuid4()

        msg_context = {
            "langfuse_trace_id": "trace-def",
            "langfuse_parent_observation_id": "obs-456",
            "phase": "implementation",  # Extra field should be ignored
        }

        ctx = TraceContext.from_message_context(
            workflow_id=workflow_id,
            agent_name="implementer",
            context=msg_context,
        )

        assert ctx.trace_id == "trace-def"
        assert ctx.parent_observation_id == "obs-456"
        assert ctx.workflow_id == workflow_id
        assert ctx.agent_name == "implementer"

    def test_trace_context_missing_fields(self):
        """TraceContext should handle missing optional fields."""
        workflow_id = uuid4()

        ctx = TraceContext.from_message_context(
            workflow_id=workflow_id,
            agent_name="specifier",
            context={},  # Empty context
        )

        assert ctx.trace_id is None
        assert ctx.parent_observation_id is None

    def test_trace_context_roundtrip(self):
        """TraceContext should survive roundtrip through message context."""
        workflow_id = uuid4()

        original = TraceContext(
            trace_id="trace-roundtrip",
            workflow_id=workflow_id,
            agent_name="planner",
            parent_observation_id="parent-obs",
        )

        msg_ctx = original.to_message_context()

        restored = TraceContext.from_message_context(
            workflow_id=workflow_id,
            agent_name="task-generator",  # Different agent
            context=msg_ctx,
        )

        assert restored.trace_id == original.trace_id
        assert restored.parent_observation_id == original.parent_observation_id


class TestCloudEventEnvelope:
    """Contract tests for CloudEvent envelope format used by Dapr."""

    def test_message_type_is_cloudevent_compatible(self):
        """Message type should be CloudEvent compatible."""
        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=uuid4(),
            task="test",
        )

        # CloudEvent type field
        assert message.type == "TriggerAction"

    def test_message_has_required_cloudevent_fields(self):
        """Message should have fields compatible with CloudEvent spec."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="generate_spec",
        )

        # Required CloudEvent fields (mapped to our message fields):
        # - id: message.id
        # - source: message.source
        # - type: message.type
        # - time: message.timestamp (optional in CloudEvent but we include it)

        assert message.id is not None
        assert isinstance(message.id, UUID)
        assert message.source is not None
        assert message.type is not None
        assert message.timestamp is not None

    def test_dapr_pubsub_payload_format(self):
        """Message should serialize to Dapr pub/sub expected format."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="process",
            context={"key": "value"},
        )

        # Dapr expects JSON with data field containing our payload
        json_str = message.model_dump_json()

        # Verify it's valid JSON with expected fields
        import json
        parsed = json.loads(json_str)

        assert "id" in parsed
        assert "source" in parsed
        assert "workflow_id" in parsed
        assert "task" in parsed
        assert "context" in parsed
        assert "timestamp" in parsed
