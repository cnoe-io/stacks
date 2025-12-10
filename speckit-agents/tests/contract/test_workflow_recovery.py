"""Contract tests for workflow recovery schema.

Tests:
- Checkpoint model validation
- Session model validation
- RecoveryPlan model validation
- Checkpoint type handling

These tests validate the contract for session recovery functionality.
"""

from datetime import datetime
from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.services.session_recovery import (
    Checkpoint,
    CheckpointType,
    RecoveryPlan,
    Session,
    SessionState,
)


class TestCheckpointSchema:
    """Contract tests for Checkpoint model."""

    def test_checkpoint_required_fields(self):
        """Checkpoint should require workflow_id, session_id, agent_name, checkpoint_type, phase."""
        with pytest.raises(ValidationError):
            Checkpoint()

        with pytest.raises(ValidationError):
            Checkpoint(workflow_id=uuid4())

    def test_checkpoint_with_minimal_fields(self):
        """Checkpoint should accept minimal required fields."""
        workflow_id = uuid4()
        session_id = uuid4()

        checkpoint = Checkpoint(
            workflow_id=workflow_id,
            session_id=session_id,
            agent_name="specifier",
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            phase="specification",
        )

        assert checkpoint.workflow_id == workflow_id
        assert checkpoint.session_id == session_id
        assert checkpoint.agent_name == "specifier"
        assert checkpoint.checkpoint_type == CheckpointType.PHASE_PROGRESS
        assert checkpoint.phase == "specification"

    def test_checkpoint_with_all_fields(self):
        """Checkpoint should accept all optional fields."""
        workflow_id = uuid4()
        session_id = uuid4()

        checkpoint = Checkpoint(
            workflow_id=workflow_id,
            session_id=session_id,
            agent_name="planner",
            checkpoint_type=CheckpointType.LLM_RESPONSE,
            phase="planning",
            step_index=5,
            total_steps=10,
            data={"current_section": "architecture"},
            conversation_history=[
                {"role": "user", "content": "Design the system"},
                {"role": "assistant", "content": "Here's my design..."},
            ],
            partial_artifacts={"plan.md": "# Plan\n\n## Architecture"},
            error=None,
            retry_count=0,
        )

        assert checkpoint.step_index == 5
        assert checkpoint.total_steps == 10
        assert len(checkpoint.conversation_history) == 2
        assert "plan.md" in checkpoint.partial_artifacts

    def test_checkpoint_auto_generated_fields(self):
        """Checkpoint should auto-generate id and timestamp."""
        checkpoint = Checkpoint(
            workflow_id=uuid4(),
            session_id=uuid4(),
            agent_name="specifier",
            checkpoint_type=CheckpointType.PHASE_START,
            phase="specification",
        )

        assert checkpoint.id is not None
        assert checkpoint.timestamp is not None
        assert isinstance(checkpoint.timestamp, datetime)


class TestCheckpointTypeHandling:
    """Contract tests for CheckpointType enum."""

    def test_all_checkpoint_types_valid(self):
        """All checkpoint types should be valid."""
        types = [
            CheckpointType.PHASE_START,
            CheckpointType.PHASE_PROGRESS,
            CheckpointType.PHASE_COMPLETE,
            CheckpointType.TOOL_INVOCATION,
            CheckpointType.LLM_RESPONSE,
            CheckpointType.ARTIFACT_PARTIAL,
            CheckpointType.ERROR,
        ]

        for cp_type in types:
            checkpoint = Checkpoint(
                workflow_id=uuid4(),
                session_id=uuid4(),
                agent_name="test",
                checkpoint_type=cp_type,
                phase="test",
            )
            assert checkpoint.checkpoint_type == cp_type

    def test_checkpoint_type_string_values(self):
        """CheckpointType should have correct string values."""
        assert CheckpointType.PHASE_START.value == "phase_start"
        assert CheckpointType.PHASE_PROGRESS.value == "phase_progress"
        assert CheckpointType.PHASE_COMPLETE.value == "phase_complete"
        assert CheckpointType.TOOL_INVOCATION.value == "tool_invocation"
        assert CheckpointType.LLM_RESPONSE.value == "llm_response"
        assert CheckpointType.ARTIFACT_PARTIAL.value == "artifact_partial"
        assert CheckpointType.ERROR.value == "error"


class TestSessionSchema:
    """Contract tests for Session model."""

    def test_session_required_fields(self):
        """Session should require workflow_id and agent_name."""
        with pytest.raises(ValidationError):
            Session()

    def test_session_with_minimal_fields(self):
        """Session should accept minimal required fields."""
        workflow_id = uuid4()

        session = Session(
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        assert session.workflow_id == workflow_id
        assert session.agent_name == "specifier"
        assert session.state == SessionState.ACTIVE  # Default

    def test_session_with_all_fields(self):
        """Session should accept all optional fields."""
        workflow_id = uuid4()
        checkpoint_id = uuid4()

        session = Session(
            workflow_id=workflow_id,
            agent_name="planner",
            state=SessionState.PAUSED,
            current_phase="planning",
            langfuse_trace_id="trace-123",
            langfuse_session_id="session-456",
            last_checkpoint_id=checkpoint_id,
            recovery_count=1,
            max_recoveries=3,
        )

        assert session.state == SessionState.PAUSED
        assert session.langfuse_trace_id == "trace-123"
        assert session.last_checkpoint_id == checkpoint_id
        assert session.recovery_count == 1

    def test_session_auto_generated_fields(self):
        """Session should auto-generate id and timestamps."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
        )

        assert session.id is not None
        assert session.created_at is not None
        assert session.updated_at is not None


class TestSessionStateHandling:
    """Contract tests for SessionState enum."""

    def test_all_session_states_valid(self):
        """All session states should be valid."""
        states = [
            SessionState.ACTIVE,
            SessionState.PAUSED,
            SessionState.RECOVERING,
            SessionState.COMPLETED,
            SessionState.FAILED,
        ]

        for state in states:
            session = Session(
                workflow_id=uuid4(),
                agent_name="test",
                state=state,
            )
            assert session.state == state

    def test_session_state_string_values(self):
        """SessionState should have correct string values."""
        assert SessionState.ACTIVE.value == "active"
        assert SessionState.PAUSED.value == "paused"
        assert SessionState.RECOVERING.value == "recovering"
        assert SessionState.COMPLETED.value == "completed"
        assert SessionState.FAILED.value == "failed"


class TestSessionCanRecover:
    """Contract tests for Session.can_recover property."""

    def test_active_session_cannot_recover(self):
        """Active session should not trigger recovery."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
            state=SessionState.ACTIVE,
        )

        assert session.can_recover is False

    def test_paused_session_can_recover(self):
        """Paused session should be recoverable."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
            state=SessionState.PAUSED,
            recovery_count=0,
            max_recoveries=3,
        )

        assert session.can_recover is True

    def test_recovering_session_can_continue_recover(self):
        """Recovering session should be recoverable (within limits)."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
            state=SessionState.RECOVERING,
            recovery_count=1,
            max_recoveries=3,
        )

        assert session.can_recover is True

    def test_completed_session_cannot_recover(self):
        """Completed session should not trigger recovery."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
            state=SessionState.COMPLETED,
        )

        assert session.can_recover is False

    def test_failed_session_cannot_recover(self):
        """Failed session should not trigger recovery."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
            state=SessionState.FAILED,
        )

        assert session.can_recover is False

    def test_max_recoveries_exceeded(self):
        """Session should not recover if max recoveries exceeded."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
            state=SessionState.PAUSED,
            recovery_count=3,
            max_recoveries=3,
        )

        assert session.can_recover is False


class TestRecoveryPlanSchema:
    """Contract tests for RecoveryPlan model."""

    def test_recovery_plan_required_fields(self):
        """RecoveryPlan should require session and recovery_strategy."""
        with pytest.raises(ValidationError):
            RecoveryPlan()

    def test_recovery_plan_with_minimal_fields(self):
        """RecoveryPlan should accept minimal required fields."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
        )

        plan = RecoveryPlan(
            session=session,
            checkpoint=None,
            recovery_strategy="restart_phase",
        )

        assert plan.session == session
        assert plan.checkpoint is None
        assert plan.recovery_strategy == "restart_phase"

    def test_recovery_plan_with_checkpoint(self):
        """RecoveryPlan should accept checkpoint for resume strategy."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="planner",
        )

        checkpoint = Checkpoint(
            workflow_id=session.workflow_id,
            session_id=session.id,
            agent_name=session.agent_name,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            phase="planning",
            step_index=5,
            total_steps=10,
        )

        plan = RecoveryPlan(
            session=session,
            checkpoint=checkpoint,
            recovery_strategy="resume",
            steps_to_skip=5,
            artifacts_to_restore=["research.md"],
            estimated_work_saved_percent=50.0,
        )

        assert plan.checkpoint is not None
        assert plan.steps_to_skip == 5
        assert len(plan.artifacts_to_restore) == 1
        assert plan.estimated_work_saved_percent == 50.0


class TestRecoveryStrategyTypes:
    """Contract tests for recovery strategy types."""

    def test_valid_recovery_strategies(self):
        """Should accept valid recovery strategy strings."""
        strategies = ["resume", "restart_phase", "restart_workflow", "skip_phase"]

        session = Session(
            workflow_id=uuid4(),
            agent_name="test",
        )

        for strategy in strategies:
            plan = RecoveryPlan(
                session=session,
                checkpoint=None,
                recovery_strategy=strategy,
            )
            assert plan.recovery_strategy == strategy


class TestCheckpointSerialization:
    """Contract tests for checkpoint serialization."""

    def test_checkpoint_json_roundtrip(self):
        """Checkpoint should serialize and deserialize correctly."""
        checkpoint = Checkpoint(
            workflow_id=uuid4(),
            session_id=uuid4(),
            agent_name="specifier",
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            phase="specification",
            step_index=3,
            total_steps=5,
            data={"key": "value"},
            conversation_history=[{"role": "user", "content": "test"}],
        )

        json_str = checkpoint.model_dump_json()
        restored = Checkpoint.model_validate_json(json_str)

        assert restored.workflow_id == checkpoint.workflow_id
        assert restored.session_id == checkpoint.session_id
        assert restored.checkpoint_type == checkpoint.checkpoint_type
        assert restored.step_index == checkpoint.step_index
        assert restored.data == checkpoint.data
        assert len(restored.conversation_history) == 1

    def test_session_json_roundtrip(self):
        """Session should serialize and deserialize correctly."""
        session = Session(
            workflow_id=uuid4(),
            agent_name="planner",
            state=SessionState.PAUSED,
            langfuse_trace_id="trace-123",
            recovery_count=1,
        )

        json_str = session.model_dump_json()
        restored = Session.model_validate_json(json_str)

        assert restored.workflow_id == session.workflow_id
        assert restored.agent_name == session.agent_name
        assert restored.state == session.state
        assert restored.langfuse_trace_id == session.langfuse_trace_id
        assert restored.recovery_count == session.recovery_count
