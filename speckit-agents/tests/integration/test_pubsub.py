"""Integration tests for Dapr pub/sub messaging.

Tests:
- Message publishing to topics
- Message subscription handling
- Trace context propagation in messages

Note: These tests use mocked Dapr client for unit testing.
For actual integration tests, run with Dapr sidecar available.
"""

from datetime import datetime
from unittest.mock import patch, AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.common.models import (
    TraceContext,
    WorkflowMessage,
    WorkflowPhase,
)


class TestPubSubPublishing:
    """Integration tests for Dapr pub/sub publishing."""

    @pytest.fixture
    def mock_dapr_client(self, mock_dapr_client):
        """Get Dapr client with pub/sub mock."""
        return mock_dapr_client

    @pytest.mark.asyncio
    async def test_publish_workflow_message(self, patch_dapr_client, mock_dapr_client):
        """Should publish workflow message to topic."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="start_specification",
            context={"feature_description": "Add user auth"},
        )

        # Simulate publishing
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        # Verify message was published
        published = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(published) == 1
        assert str(workflow_id) in published[0]

    @pytest.mark.asyncio
    async def test_publish_phase_complete_message(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Should publish phase completion message."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="phase_complete:specification",
            context={
                "completed_phase": "specification",
                "artifact_type": "spec",
                "next_phase": "planning",
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(published) == 1
        assert "phase_complete:specification" in published[0]

    @pytest.mark.asyncio
    async def test_publish_with_trace_context(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Should include trace context in published message."""
        workflow_id = uuid4()

        trace_ctx = TraceContext(
            trace_id="trace-xyz",
            workflow_id=workflow_id,
            agent_name="orchestrator",
            parent_observation_id="obs-123",
        )

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="start_planning",
            context={
                **trace_ctx.to_message_context(),
                "input_artifact": "spec.md",
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(published) == 1
        assert "langfuse_trace_id" in published[0]
        assert "trace-xyz" in published[0]

    @pytest.mark.asyncio
    async def test_publish_to_specific_agent_topic(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Should publish to agent-specific topic."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="execute",
            context={"phase": "specification"},
        )

        # Publish to specifier-specific topic
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="agent-specifier",
            data=message.model_dump_json(),
        )

        # Verify topic isolation
        specifier_messages = mock_dapr_client._pubsub.get_messages("agent-specifier")
        workflow_messages = mock_dapr_client._pubsub.get_messages("workflow-events")

        assert len(specifier_messages) == 1
        assert len(workflow_messages) == 0

    @pytest.mark.asyncio
    async def test_publish_error_message(self, patch_dapr_client, mock_dapr_client):
        """Should publish error notification message."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="planner",
            workflow_id=workflow_id,
            task="phase_failed",
            context={
                "phase": "planning",
                "error": "Claude SDK timeout",
                "error_code": "TIMEOUT",
                "retry_count": 3,
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-errors",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("workflow-errors")
        assert len(published) == 1
        assert "phase_failed" in published[0]
        assert "TIMEOUT" in published[0]


class TestPubSubSubscription:
    """Integration tests for Dapr pub/sub subscription handling."""

    @pytest.fixture
    def mock_dapr_client(self, mock_dapr_client):
        """Get Dapr client with pub/sub mock."""
        return mock_dapr_client

    @pytest.mark.asyncio
    async def test_subscribe_to_workflow_events(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Should receive messages from workflow events topic."""
        workflow_id = uuid4()

        # Publish a message
        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="start_specification",
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        # Simulate subscription callback
        received = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(received) == 1

        # Deserialize and validate
        received_msg = WorkflowMessage.model_validate_json(received[0])
        assert received_msg.workflow_id == workflow_id
        assert received_msg.task == "start_specification"

    @pytest.mark.asyncio
    async def test_message_acknowledgment(self, patch_dapr_client, mock_dapr_client):
        """Should acknowledge processed messages."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="test_task",
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        # Simulate acknowledgment
        mock_dapr_client._pubsub.acknowledge("workflow-events")

        # Verify messages cleared after ack
        remaining = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(remaining) == 0

    @pytest.mark.asyncio
    async def test_extract_trace_context_from_message(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Should extract trace context from received message."""
        workflow_id = uuid4()

        # Message with trace context
        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="execute_planning",
            context={
                "langfuse_trace_id": "trace-abc",
                "langfuse_parent_observation_id": "gen-xyz",
                "phase": "planning",
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        # Receive and extract
        received = mock_dapr_client._pubsub.get_messages("workflow-events")
        received_msg = WorkflowMessage.model_validate_json(received[0])

        trace_ctx = TraceContext.from_message_context(
            workflow_id=received_msg.workflow_id,
            agent_name="planner",
            context=received_msg.context,
        )

        assert trace_ctx.trace_id == "trace-abc"
        assert trace_ctx.parent_observation_id == "gen-xyz"


class TestPubSubMessageOrdering:
    """Tests for message ordering and sequencing."""

    @pytest.mark.asyncio
    async def test_messages_preserve_order(self, patch_dapr_client, mock_dapr_client):
        """Messages should be received in publication order."""
        workflow_id = uuid4()

        # Publish multiple messages in order
        for i in range(5):
            message = WorkflowMessage(
                source="orchestrator",
                workflow_id=workflow_id,
                task=f"task_{i}",
            )
            await mock_dapr_client.publish_event(
                pubsub_name="speckit-pubsub",
                topic_name="workflow-events",
                data=message.model_dump_json(),
            )

        received = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(received) == 5

        # Verify order
        for i, msg_json in enumerate(received):
            msg = WorkflowMessage.model_validate_json(msg_json)
            assert msg.task == f"task_{i}"

    @pytest.mark.asyncio
    async def test_workflow_isolation(self, patch_dapr_client, mock_dapr_client):
        """Messages for different workflows should be isolated."""
        workflow_1 = uuid4()
        workflow_2 = uuid4()

        # Publish to both workflows
        msg1 = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_1,
            task="wf1_task",
        )
        msg2 = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_2,
            task="wf2_task",
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=msg1.model_dump_json(),
        )
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=msg2.model_dump_json(),
        )

        received = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(received) == 2

        # Filter by workflow
        wf1_msgs = [
            WorkflowMessage.model_validate_json(m)
            for m in received
            if str(workflow_1) in m
        ]
        wf2_msgs = [
            WorkflowMessage.model_validate_json(m)
            for m in received
            if str(workflow_2) in m
        ]

        assert len(wf1_msgs) == 1
        assert len(wf2_msgs) == 1
        assert wf1_msgs[0].task == "wf1_task"
        assert wf2_msgs[0].task == "wf2_task"


class TestPubSubErrorHandling:
    """Tests for pub/sub error handling."""

    @pytest.mark.asyncio
    async def test_invalid_message_format(self, patch_dapr_client, mock_dapr_client):
        """Should handle invalid message format gracefully."""
        # Publish invalid JSON
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data="invalid-json{",
        )

        received = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(received) == 1

        # Attempting to parse should raise
        with pytest.raises(Exception):
            WorkflowMessage.model_validate_json(received[0])

    @pytest.mark.asyncio
    async def test_missing_required_fields(self, patch_dapr_client, mock_dapr_client):
        """Should handle messages with missing required fields."""
        # Valid JSON but missing required fields
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data='{"source": "test"}',
        )

        received = mock_dapr_client._pubsub.get_messages("workflow-events")

        with pytest.raises(Exception):  # ValidationError
            WorkflowMessage.model_validate_json(received[0])

    @pytest.mark.asyncio
    async def test_dead_letter_handling(self, patch_dapr_client, mock_dapr_client):
        """Should support dead-letter queue for failed messages."""
        workflow_id = uuid4()

        # Simulate a message that will fail processing
        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="failing_task",
            context={"will_fail": True},
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        # Simulate moving to dead letter after processing failure
        mock_dapr_client._pubsub.move_to_dead_letter("workflow-events")

        # Original topic should be empty
        original = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(original) == 0

        # Dead letter should have the message
        dead_letter = mock_dapr_client._pubsub.get_messages("workflow-events-dlq")
        assert len(dead_letter) == 1


class TestPubSubMetadata:
    """Tests for pub/sub metadata handling."""

    @pytest.mark.asyncio
    async def test_cloudevent_metadata(self, patch_dapr_client, mock_dapr_client):
        """Should include CloudEvent metadata."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="test",
        )

        # Dapr adds CloudEvent envelope
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
            data_content_type="application/json",
        )

        # Message should be valid JSON
        received = mock_dapr_client._pubsub.get_messages("workflow-events")
        assert len(received) == 1

        import json
        parsed = json.loads(received[0])

        # CloudEvent-compatible fields
        assert "id" in parsed
        assert "source" in parsed
        assert "type" in parsed

    @pytest.mark.asyncio
    async def test_timestamp_in_message(self, patch_dapr_client, mock_dapr_client):
        """Should include timestamp in messages."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="test",
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="workflow-events",
            data=message.model_dump_json(),
        )

        received = mock_dapr_client._pubsub.get_messages("workflow-events")
        received_msg = WorkflowMessage.model_validate_json(received[0])

        assert received_msg.timestamp is not None
        assert isinstance(received_msg.timestamp, datetime)
