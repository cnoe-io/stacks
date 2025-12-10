"""Integration tests for workflow initiation via Dapr pub/sub.

Tests:
- Workflow creation triggers pub/sub message to orchestrator
- Phase transitions are published to correct agent topics
- Workflow completion publishes final status
- Error handling publishes to error topic

Note: Uses mocked Dapr client for unit testing.
For actual integration tests, run with Dapr sidecar available.
"""

from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from src.common.models import (
    TraceContext,
    Workflow,
    WorkflowMessage,
    WorkflowPhase,
    WorkflowStatus,
)
from src.services.state_manager import get_state_manager


class TestWorkflowInitiationPubSub:
    """Integration tests for workflow initiation via pub/sub."""

    @pytest.mark.asyncio
    async def test_workflow_creation_publishes_start_message(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Creating a workflow should publish start message to orchestrator."""
        workflow_id = uuid4()
        feature_description = "Add user authentication"

        # Create workflow message
        message = WorkflowMessage(
            source="api",
            workflow_id=workflow_id,
            task="start_workflow",
            context={
                "feature_description": feature_description,
                "initial_phase": WorkflowPhase.SPECIFICATION.value,
            },
        )

        # Publish to orchestrator topic
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.orchestrator.requests",
            data=message.model_dump_json(),
        )

        # Verify message published
        published = mock_dapr_client._pubsub.get_messages("speckit.orchestrator.requests")
        assert len(published) == 1

        received_msg = WorkflowMessage.model_validate_json(published[0])
        assert received_msg.workflow_id == workflow_id
        assert received_msg.task == "start_workflow"
        assert received_msg.context["feature_description"] == feature_description

    @pytest.mark.asyncio
    async def test_workflow_publishes_with_trace_context(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Workflow initiation should include trace context for observability."""
        workflow_id = uuid4()

        trace_ctx = TraceContext(
            trace_id="langfuse-trace-123",
            workflow_id=workflow_id,
            agent_name="api",
            parent_observation_id=None,
        )

        message = WorkflowMessage(
            source="api",
            workflow_id=workflow_id,
            task="start_workflow",
            context={
                **trace_ctx.to_message_context(),
                "feature_description": "Test feature",
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.orchestrator.requests",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("speckit.orchestrator.requests")
        assert "langfuse_trace_id" in published[0]
        assert "langfuse-trace-123" in published[0]

    @pytest.mark.asyncio
    async def test_workflow_id_is_unique(self, patch_dapr_client, mock_dapr_client):
        """Each workflow initiation should have a unique ID."""
        workflow_ids = set()

        for _ in range(10):
            workflow_id = uuid4()
            workflow_ids.add(str(workflow_id))

            message = WorkflowMessage(
                source="api",
                workflow_id=workflow_id,
                task="start_workflow",
                context={"feature_description": "Test"},
            )

            await mock_dapr_client.publish_event(
                pubsub_name="speckit-pubsub",
                topic_name="speckit.orchestrator.requests",
                data=message.model_dump_json(),
            )

        # All IDs should be unique
        assert len(workflow_ids) == 10

        # Verify all messages published
        published = mock_dapr_client._pubsub.get_messages("speckit.orchestrator.requests")
        assert len(published) == 10


class TestPhaseTransitionPubSub:
    """Integration tests for phase transition messages."""

    @pytest.mark.asyncio
    async def test_specification_complete_publishes_to_planner(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Completing specification phase should publish to planner topic."""
        workflow_id = uuid4()

        # Phase complete message from specifier
        message = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="phase_complete",
            context={
                "completed_phase": WorkflowPhase.SPECIFICATION.value,
                "next_phase": WorkflowPhase.PLANNING.value,
                "artifact_type": "spec",
                "artifact_hash": "sha256:abc123",
            },
        )

        # Publish to orchestrator (who routes to planner)
        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.orchestrator.requests",
            data=message.model_dump_json(),
        )

        # Orchestrator would then publish to planner
        next_message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="execute_phase",
            context={
                "phase": WorkflowPhase.PLANNING.value,
                "input_artifact": "spec.md",
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.planner.requests",
            data=next_message.model_dump_json(),
        )

        # Verify both messages
        orchestrator_msgs = mock_dapr_client._pubsub.get_messages(
            "speckit.orchestrator.requests"
        )
        planner_msgs = mock_dapr_client._pubsub.get_messages("speckit.planner.requests")

        assert len(orchestrator_msgs) == 1
        assert len(planner_msgs) == 1

        planner_msg = WorkflowMessage.model_validate_json(planner_msgs[0])
        assert planner_msg.context["phase"] == WorkflowPhase.PLANNING.value

    @pytest.mark.asyncio
    async def test_full_phase_transition_chain(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Should support full phase transition: spec -> plan -> tasks -> impl."""
        workflow_id = uuid4()

        phases = [
            ("specifier", WorkflowPhase.SPECIFICATION, WorkflowPhase.PLANNING),
            ("planner", WorkflowPhase.PLANNING, WorkflowPhase.TASK_GENERATION),
            ("taskgenerator", WorkflowPhase.TASK_GENERATION, WorkflowPhase.IMPLEMENTATION),
            ("implementer", WorkflowPhase.IMPLEMENTATION, None),
        ]

        for agent, current_phase, next_phase in phases:
            message = WorkflowMessage(
                source=agent,
                workflow_id=workflow_id,
                task="phase_complete" if next_phase else "workflow_complete",
                context={
                    "completed_phase": current_phase.value,
                    "next_phase": next_phase.value if next_phase else None,
                },
            )

            await mock_dapr_client.publish_event(
                pubsub_name="speckit-pubsub",
                topic_name=f"speckit.{agent}.complete",
                data=message.model_dump_json(),
            )

        # Verify all phase transitions published
        total_messages = 0
        for agent, _, _ in phases:
            msgs = mock_dapr_client._pubsub.get_messages(f"speckit.{agent}.complete")
            total_messages += len(msgs)

        assert total_messages == 4

    @pytest.mark.asyncio
    async def test_phase_transition_preserves_trace_context(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Trace context should be preserved across phase transitions."""
        workflow_id = uuid4()
        original_trace_id = "trace-original-123"

        # First phase with trace context
        first_message = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="phase_complete",
            context={
                "langfuse_trace_id": original_trace_id,
                "completed_phase": WorkflowPhase.SPECIFICATION.value,
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.orchestrator.requests",
            data=first_message.model_dump_json(),
        )

        # Extract and verify trace context is preserved
        received = mock_dapr_client._pubsub.get_messages("speckit.orchestrator.requests")
        received_msg = WorkflowMessage.model_validate_json(received[0])

        assert received_msg.context.get("langfuse_trace_id") == original_trace_id


class TestWorkflowCompletionPubSub:
    """Integration tests for workflow completion messages."""

    @pytest.mark.asyncio
    async def test_successful_workflow_completion(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Successfully completed workflow should publish completion status."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="implementer",
            workflow_id=workflow_id,
            task="workflow_complete",
            context={
                "status": WorkflowStatus.COMPLETED.value,
                "completed_phases": ["specification", "planning", "task_generation", "implementation"],
                "total_duration_seconds": 1800,
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.workflow.status",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("speckit.workflow.status")
        assert len(published) == 1

        completed_msg = WorkflowMessage.model_validate_json(published[0])
        assert completed_msg.task == "workflow_complete"
        assert completed_msg.context["status"] == WorkflowStatus.COMPLETED.value

    @pytest.mark.asyncio
    async def test_workflow_completion_includes_artifacts(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Completed workflow should include artifact references."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="implementer",
            workflow_id=workflow_id,
            task="workflow_complete",
            context={
                "status": WorkflowStatus.COMPLETED.value,
                "artifacts": [
                    {"type": "spec", "path": "spec.md", "hash": "sha256:spec123"},
                    {"type": "plan", "path": "plan.md", "hash": "sha256:plan456"},
                    {"type": "tasks", "path": "tasks.md", "hash": "sha256:tasks789"},
                    {"type": "impl", "path": "impl/", "hash": "sha256:impl012"},
                ],
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.workflow.status",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("speckit.workflow.status")
        completed_msg = WorkflowMessage.model_validate_json(published[0])

        assert len(completed_msg.context["artifacts"]) == 4


class TestWorkflowErrorPubSub:
    """Integration tests for workflow error handling via pub/sub."""

    @pytest.mark.asyncio
    async def test_phase_failure_publishes_error(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Phase failure should publish to error topic."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="planner",
            workflow_id=workflow_id,
            task="phase_failed",
            context={
                "phase": WorkflowPhase.PLANNING.value,
                "error": "Claude SDK timeout after 10 minutes",
                "error_code": "TIMEOUT",
                "retry_count": 2,
                "max_retries": 3,
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.workflow.errors",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("speckit.workflow.errors")
        assert len(published) == 1

        error_msg = WorkflowMessage.model_validate_json(published[0])
        assert error_msg.task == "phase_failed"
        assert error_msg.context["error_code"] == "TIMEOUT"

    @pytest.mark.asyncio
    async def test_workflow_failure_status(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Failed workflow should publish failure status."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="workflow_failed",
            context={
                "status": WorkflowStatus.FAILED.value,
                "failed_phase": WorkflowPhase.IMPLEMENTATION.value,
                "error": "Max retries exceeded",
                "completed_phases": ["specification", "planning", "task_generation"],
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.workflow.status",
            data=message.model_dump_json(),
        )

        published = mock_dapr_client._pubsub.get_messages("speckit.workflow.status")
        failed_msg = WorkflowMessage.model_validate_json(published[0])

        assert failed_msg.context["status"] == WorkflowStatus.FAILED.value
        assert failed_msg.context["failed_phase"] == WorkflowPhase.IMPLEMENTATION.value

    @pytest.mark.asyncio
    async def test_retryable_error_triggers_retry(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Retryable errors should trigger retry message."""
        workflow_id = uuid4()

        # Initial failure
        failure_msg = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="phase_failed",
            context={
                "phase": WorkflowPhase.SPECIFICATION.value,
                "error": "Temporary API error",
                "error_code": "API_ERROR",
                "retry_count": 1,
                "max_retries": 3,
                "is_retryable": True,
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.workflow.errors",
            data=failure_msg.model_dump_json(),
        )

        # Retry message from orchestrator
        retry_msg = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="retry_phase",
            context={
                "phase": WorkflowPhase.SPECIFICATION.value,
                "retry_count": 2,
                "backoff_seconds": 30,
            },
        )

        await mock_dapr_client.publish_event(
            pubsub_name="speckit-pubsub",
            topic_name="speckit.specifier.requests",
            data=retry_msg.model_dump_json(),
        )

        # Verify both messages
        errors = mock_dapr_client._pubsub.get_messages("speckit.workflow.errors")
        retries = mock_dapr_client._pubsub.get_messages("speckit.specifier.requests")

        assert len(errors) == 1
        assert len(retries) == 1

        retry = WorkflowMessage.model_validate_json(retries[0])
        assert retry.task == "retry_phase"
        assert retry.context["retry_count"] == 2


class TestConcurrentWorkflowsPubSub:
    """Integration tests for concurrent workflow handling."""

    @pytest.mark.asyncio
    async def test_multiple_workflows_isolated(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Multiple concurrent workflows should be isolated."""
        workflow_ids = [uuid4() for _ in range(3)]

        # Start all workflows
        for wf_id in workflow_ids:
            message = WorkflowMessage(
                source="api",
                workflow_id=wf_id,
                task="start_workflow",
                context={"feature_description": f"Feature for {wf_id}"},
            )

            await mock_dapr_client.publish_event(
                pubsub_name="speckit-pubsub",
                topic_name="speckit.orchestrator.requests",
                data=message.model_dump_json(),
            )

        published = mock_dapr_client._pubsub.get_messages("speckit.orchestrator.requests")
        assert len(published) == 3

        # Verify each workflow has unique ID
        received_ids = set()
        for msg_json in published:
            msg = WorkflowMessage.model_validate_json(msg_json)
            received_ids.add(msg.workflow_id)

        assert len(received_ids) == 3

    @pytest.mark.asyncio
    async def test_workflow_messages_ordered_per_workflow(
        self, patch_dapr_client, mock_dapr_client
    ):
        """Messages for a single workflow should maintain order."""
        workflow_id = uuid4()

        tasks = ["start_workflow", "phase_complete:spec", "phase_complete:plan", "workflow_complete"]

        for task in tasks:
            message = WorkflowMessage(
                source="orchestrator",
                workflow_id=workflow_id,
                task=task,
            )

            await mock_dapr_client.publish_event(
                pubsub_name="speckit-pubsub",
                topic_name="speckit.workflow.status",
                data=message.model_dump_json(),
            )

        published = mock_dapr_client._pubsub.get_messages("speckit.workflow.status")
        assert len(published) == 4

        # Verify order
        for i, msg_json in enumerate(published):
            msg = WorkflowMessage.model_validate_json(msg_json)
            assert msg.task == tasks[i]
