"""Tests for Pydantic models in src/common/models.py."""

from datetime import datetime
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError

from src.common.models import (
    Agent,
    AgentStatus,
    Artifact,
    ArtifactType,
    ErrorResponse,
    HealthResponse,
    Message,
    ReadinessResponse,
    Task,
    TaskPhase,
    TaskStatus,
    TokenUsage,
    TraceContext,
    Workflow,
    WorkflowMessage,
    WorkflowPhase,
    WorkflowRequest,
    WorkflowResponse,
    WorkflowStatus,
    WorkflowStatusResponse,
)


class TestWorkflowModel:
    """Tests for Workflow model."""

    def test_workflow_creation_defaults(self):
        """Workflow should have sensible defaults."""
        workflow = Workflow(feature_description="Test feature")

        assert workflow.id is not None
        assert isinstance(workflow.id, UUID)
        assert workflow.status == WorkflowStatus.PENDING
        assert workflow.current_phase == WorkflowPhase.SPECIFICATION
        assert workflow.current_agent is None
        assert workflow.artifacts == []
        assert workflow.error is None
        assert workflow.completed_at is None

    def test_workflow_with_all_fields(self):
        """Workflow should accept all fields."""
        workflow_id = uuid4()
        now = datetime.utcnow()

        workflow = Workflow(
            id=workflow_id,
            feature_description="Full feature",
            status=WorkflowStatus.COMPLETED,
            current_phase=WorkflowPhase.IMPLEMENTATION,
            current_agent="implementer",
            created_at=now,
            updated_at=now,
            completed_at=now,
        )

        assert workflow.id == workflow_id
        assert workflow.status == WorkflowStatus.COMPLETED
        assert workflow.completed_at == now

    def test_workflow_progress_percent(self):
        """Progress percentage should reflect phase."""
        workflow = Workflow(feature_description="Test")

        # Pending specification = 0%
        assert workflow.progress_percent() == 0

        # Planning phase = 25%
        workflow.current_phase = WorkflowPhase.PLANNING
        assert workflow.progress_percent() == 25

        # Task generation = 50%
        workflow.current_phase = WorkflowPhase.TASK_GENERATION
        assert workflow.progress_percent() == 50

        # Implementation = 75%
        workflow.current_phase = WorkflowPhase.IMPLEMENTATION
        assert workflow.progress_percent() == 75

        # Completed = 100%
        workflow.status = WorkflowStatus.COMPLETED
        assert workflow.progress_percent() == 100

    def test_workflow_validation_required_field(self):
        """Workflow should require feature_description."""
        with pytest.raises(ValidationError):
            Workflow()


class TestArtifactModel:
    """Tests for Artifact model."""

    def test_artifact_creation(self):
        """Artifact should create with required fields."""
        workflow_id = uuid4()

        artifact = Artifact(
            workflow_id=workflow_id,
            type=ArtifactType.SPEC,
            path="spec.md",
            created_by="specifier",
        )

        assert artifact.workflow_id == workflow_id
        assert artifact.type == ArtifactType.SPEC
        assert artifact.path == "spec.md"
        assert artifact.created_by == "specifier"
        assert artifact.version == 1
        assert artifact.content_hash is None

    def test_artifact_types(self):
        """All artifact types should be valid."""
        workflow_id = uuid4()

        for artifact_type in ArtifactType:
            artifact = Artifact(
                workflow_id=workflow_id,
                type=artifact_type,
                path=f"{artifact_type.value}.md",
                created_by="test",
            )
            assert artifact.type == artifact_type


class TestTaskModel:
    """Tests for Task model."""

    def test_task_creation(self):
        """Task should create with required fields."""
        workflow_id = uuid4()

        task = Task(
            id="T001",
            workflow_id=workflow_id,
            phase=TaskPhase.SETUP,
            description="Initialize project",
        )

        assert task.id == "T001"
        assert task.phase == TaskPhase.SETUP
        assert task.status == TaskStatus.PENDING
        assert task.dependencies == []
        assert task.file_paths == []
        assert task.is_parallel is False

    def test_task_with_dependencies(self):
        """Task should support dependencies."""
        workflow_id = uuid4()

        task = Task(
            id="T002",
            workflow_id=workflow_id,
            phase=TaskPhase.CORE,
            description="Implement feature",
            dependencies=["T001"],
            file_paths=["src/main.py", "src/utils.py"],
            is_parallel=True,
            user_story="US1",
        )

        assert "T001" in task.dependencies
        assert len(task.file_paths) == 2
        assert task.is_parallel is True
        assert task.user_story == "US1"


class TestWorkflowMessageModel:
    """Tests for WorkflowMessage model."""

    def test_message_creation(self):
        """WorkflowMessage should create with required fields."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="orchestrator",
            workflow_id=workflow_id,
            task="process_feature",
        )

        assert message.source == "orchestrator"
        assert message.workflow_id == workflow_id
        assert message.task == "process_feature"
        assert message.type == "TriggerAction"
        assert message.context == {}

    def test_message_with_context(self):
        """WorkflowMessage should support context dict."""
        workflow_id = uuid4()

        message = WorkflowMessage(
            source="specifier",
            workflow_id=workflow_id,
            task="phase_complete:specification",
            context={
                "artifact_path": "spec.md",
                "langfuse_trace_id": "trace-123",
            },
        )

        assert message.context["artifact_path"] == "spec.md"
        assert message.context["langfuse_trace_id"] == "trace-123"


class TestTraceContextModel:
    """Tests for TraceContext model."""

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

    def test_trace_context_to_message_context(self):
        """TraceContext should convert to message context dict."""
        workflow_id = uuid4()

        ctx = TraceContext(
            trace_id="trace-abc",
            workflow_id=workflow_id,
            agent_name="planner",
            parent_observation_id="obs-123",
        )

        msg_ctx = ctx.to_message_context()

        assert msg_ctx["langfuse_trace_id"] == "trace-abc"
        assert msg_ctx["langfuse_parent_observation_id"] == "obs-123"

    def test_trace_context_from_message_context(self):
        """TraceContext should extract from message context."""
        workflow_id = uuid4()

        msg_context = {
            "langfuse_trace_id": "trace-xyz",
            "langfuse_parent_observation_id": "obs-456",
            "other_field": "ignored",
        }

        ctx = TraceContext.from_message_context(
            workflow_id=workflow_id,
            agent_name="implementer",
            context=msg_context,
        )

        assert ctx.trace_id == "trace-xyz"
        assert ctx.parent_observation_id == "obs-456"
        assert ctx.workflow_id == workflow_id
        assert ctx.agent_name == "implementer"


class TestResponseModels:
    """Tests for API response models."""

    def test_health_response(self):
        """HealthResponse should have agent name."""
        response = HealthResponse(agent="orchestrator")

        assert response.status == "healthy"
        assert response.agent == "orchestrator"
        assert response.timestamp is not None

    def test_readiness_response(self):
        """ReadinessResponse should track component status."""
        response = ReadinessResponse(
            ready=True,
            agent="specifier",
            dapr_connected=True,
            components_ready=["state_store", "pubsub"],
        )

        assert response.ready is True
        assert response.dapr_connected is True
        assert "state_store" in response.components_ready

    def test_workflow_request_validation(self):
        """WorkflowRequest should validate task length."""
        # Valid request
        request = WorkflowRequest(task="A" * 50)
        assert len(request.task) == 50

        # Too short
        with pytest.raises(ValidationError):
            WorkflowRequest(task="short")

    def test_workflow_response(self):
        """WorkflowResponse should include instance_id."""
        instance_id = uuid4()

        response = WorkflowResponse(
            instance_id=instance_id,
            status=WorkflowStatus.SPECIFYING,
            status_url=f"/status/{instance_id}",
        )

        assert response.instance_id == instance_id
        assert response.status == WorkflowStatus.SPECIFYING

    def test_error_response(self):
        """ErrorResponse should include error details."""
        response = ErrorResponse(
            error="validation_error",
            message="Invalid input",
            details={"field": "task", "reason": "too_short"},
        )

        assert response.error == "validation_error"
        assert response.details["field"] == "task"


class TestTokenUsageModel:
    """Tests for TokenUsage model."""

    def test_token_usage_positive(self):
        """TokenUsage should require non-negative values."""
        usage = TokenUsage(
            prompt_tokens=100,
            completion_tokens=50,
            total_tokens=150,
        )

        assert usage.prompt_tokens == 100
        assert usage.completion_tokens == 50
        assert usage.total_tokens == 150

    def test_token_usage_zero_valid(self):
        """TokenUsage should accept zero values."""
        usage = TokenUsage(
            prompt_tokens=0,
            completion_tokens=0,
            total_tokens=0,
        )

        assert usage.total_tokens == 0

    def test_token_usage_negative_invalid(self):
        """TokenUsage should reject negative values."""
        with pytest.raises(ValidationError):
            TokenUsage(
                prompt_tokens=-1,
                completion_tokens=50,
                total_tokens=49,
            )
