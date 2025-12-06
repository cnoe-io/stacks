"""Integration tests for phase recovery logic.

Tests:
- Checkpoint persistence and retrieval
- Recovery plan creation
- Session state management
- Partial artifact restoration

Note: Uses mock state manager for isolated testing.
"""

from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import pytest

from src.services.session_recovery import (
    Checkpoint,
    CheckpointType,
    RecoveryPlan,
    Session,
    SessionManager,
    SessionState,
)


class MockStateManager:
    """Mock state manager for testing session recovery."""

    def __init__(self):
        self._state: dict[str, str] = {}

    async def _save_state(self, key: str, value: str) -> None:
        self._state[key] = value

    async def _get_state(self, key: str) -> str | None:
        return self._state.get(key)

    async def _delete_state(self, key: str) -> bool:
        if key in self._state:
            del self._state[key]
            return True
        return False


class TestSessionCreation:
    """Integration tests for session creation."""

    @pytest.fixture
    def session_manager(self, monkeypatch):
        """Create session manager with mock state."""
        manager = SessionManager()
        mock_state = MockStateManager()
        manager._state_manager = mock_state
        return manager

    @pytest.mark.asyncio
    async def test_create_session(self, session_manager):
        """Should create a new session for a workflow."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        assert session.workflow_id == workflow_id
        assert session.agent_name == "specifier"
        assert session.current_phase == "specification"
        assert session.state == SessionState.ACTIVE

    @pytest.mark.asyncio
    async def test_create_session_with_langfuse(self, session_manager):
        """Should create session with Langfuse trace ID."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
            langfuse_trace_id="trace-abc",
        )

        assert session.langfuse_trace_id == "trace-abc"
        assert session.langfuse_session_id is not None

    @pytest.mark.asyncio
    async def test_get_session_by_id(self, session_manager):
        """Should retrieve session by ID."""
        workflow_id = uuid4()

        created = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        retrieved = await session_manager.get_session(created.id)

        assert retrieved is not None
        assert retrieved.id == created.id
        assert retrieved.workflow_id == workflow_id

    @pytest.mark.asyncio
    async def test_get_workflow_session(self, session_manager):
        """Should retrieve session by workflow and agent."""
        workflow_id = uuid4()

        created = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        retrieved = await session_manager.get_workflow_session(
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        assert retrieved is not None
        assert retrieved.id == created.id


class TestCheckpointPersistence:
    """Integration tests for checkpoint persistence."""

    @pytest.fixture
    def session_manager(self, monkeypatch):
        """Create session manager with mock state."""
        manager = SessionManager()
        mock_state = MockStateManager()
        manager._state_manager = mock_state
        return manager

    @pytest.mark.asyncio
    async def test_save_checkpoint(self, session_manager):
        """Should save checkpoint for a session."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        checkpoint = await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            data={"progress": "50%"},
            step_index=5,
            total_steps=10,
        )

        assert checkpoint.workflow_id == workflow_id
        assert checkpoint.session_id == session.id
        assert checkpoint.step_index == 5

    @pytest.mark.asyncio
    async def test_save_checkpoint_with_conversation(self, session_manager):
        """Should save checkpoint with conversation history."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
        )

        conversation = [
            {"role": "user", "content": "Design the architecture"},
            {"role": "assistant", "content": "Here's my proposal..."},
        ]

        checkpoint = await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.LLM_RESPONSE,
            conversation_history=conversation,
        )

        assert len(checkpoint.conversation_history) == 2
        assert checkpoint.conversation_history[0]["role"] == "user"

    @pytest.mark.asyncio
    async def test_save_checkpoint_with_partial_artifacts(self, session_manager):
        """Should save checkpoint with partial artifacts."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        partial_artifacts = {
            "spec.md": "# Specification\n\n## Overview\n\nThis feature...",
        }

        checkpoint = await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.ARTIFACT_PARTIAL,
            partial_artifacts=partial_artifacts,
        )

        assert "spec.md" in checkpoint.partial_artifacts
        assert "# Specification" in checkpoint.partial_artifacts["spec.md"]

    @pytest.mark.asyncio
    async def test_get_checkpoint(self, session_manager):
        """Should retrieve checkpoint by ID."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        saved = await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=3,
            total_steps=10,
        )

        retrieved = await session_manager.get_checkpoint(saved.id)

        assert retrieved is not None
        assert retrieved.id == saved.id
        assert retrieved.step_index == 3

    @pytest.mark.asyncio
    async def test_get_latest_checkpoint(self, session_manager):
        """Should retrieve the most recent checkpoint."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        # Save multiple checkpoints
        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_START,
            step_index=0,
        )

        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=5,
        )

        last = await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=8,
        )

        latest = await session_manager.get_latest_checkpoint(session.id)

        assert latest is not None
        assert latest.id == last.id
        assert latest.step_index == 8

    @pytest.mark.asyncio
    async def test_get_session_checkpoints(self, session_manager):
        """Should retrieve all checkpoints for a session."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        # Save multiple checkpoints
        for i in range(5):
            await session_manager.save_checkpoint(
                session=session,
                checkpoint_type=CheckpointType.PHASE_PROGRESS,
                step_index=i,
            )

        checkpoints = await session_manager.get_session_checkpoints(session.id)

        assert len(checkpoints) == 5


class TestSessionStateTransitions:
    """Integration tests for session state transitions."""

    @pytest.fixture
    def session_manager(self, monkeypatch):
        """Create session manager with mock state."""
        manager = SessionManager()
        mock_state = MockStateManager()
        manager._state_manager = mock_state
        return manager

    @pytest.mark.asyncio
    async def test_update_session_state(self, session_manager):
        """Should update session state."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        assert session.state == SessionState.ACTIVE

        updated = await session_manager.update_session_state(
            session_id=session.id,
            state=SessionState.PAUSED,
        )

        assert updated.state == SessionState.PAUSED

    @pytest.mark.asyncio
    async def test_complete_session(self, session_manager):
        """Should mark session as completed."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        completed = await session_manager.complete_session(session.id)

        assert completed.state == SessionState.COMPLETED

    @pytest.mark.asyncio
    async def test_fail_session(self, session_manager):
        """Should mark session as failed with error checkpoint."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        failed = await session_manager.fail_session(
            session_id=session.id,
            error="Claude SDK timeout",
        )

        assert failed.state == SessionState.FAILED


class TestRecoveryPlanning:
    """Integration tests for recovery plan creation."""

    @pytest.fixture
    def session_manager(self, monkeypatch):
        """Create session manager with mock state."""
        manager = SessionManager()
        mock_state = MockStateManager()
        manager._state_manager = mock_state
        return manager

    @pytest.mark.asyncio
    async def test_plan_recovery_no_checkpoint(self, session_manager):
        """Should plan restart_phase when no checkpoint exists."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        await session_manager.update_session_state(
            session_id=session.id,
            state=SessionState.PAUSED,
        )

        plan = await session_manager.plan_recovery(
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        assert plan is not None
        assert plan.recovery_strategy == "restart_phase"
        assert plan.steps_to_skip == 0

    @pytest.mark.asyncio
    async def test_plan_recovery_with_progress_checkpoint(self, session_manager):
        """Should plan resume from progress checkpoint."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
        )

        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=5,
            total_steps=10,
        )

        await session_manager.update_session_state(
            session_id=session.id,
            state=SessionState.PAUSED,
        )

        plan = await session_manager.plan_recovery(
            workflow_id=workflow_id,
            agent_name="planner",
        )

        assert plan is not None
        assert plan.recovery_strategy == "resume"
        assert plan.steps_to_skip == 5
        assert plan.estimated_work_saved_percent == 50.0

    @pytest.mark.asyncio
    async def test_plan_recovery_phase_complete(self, session_manager):
        """Should plan skip_phase when phase already complete."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_COMPLETE,
            step_index=10,
            total_steps=10,
        )

        await session_manager.update_session_state(
            session_id=session.id,
            state=SessionState.PAUSED,
        )

        plan = await session_manager.plan_recovery(
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        assert plan is not None
        assert plan.recovery_strategy == "skip_phase"
        assert plan.estimated_work_saved_percent == 100.0

    @pytest.mark.asyncio
    async def test_plan_recovery_after_error(self, session_manager):
        """Should plan restart after error checkpoint."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="implementer",
            phase="implementation",
        )

        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.ERROR,
            data={"error": "API rate limit exceeded"},
        )

        await session_manager.update_session_state(
            session_id=session.id,
            state=SessionState.PAUSED,
        )

        plan = await session_manager.plan_recovery(
            workflow_id=workflow_id,
            agent_name="implementer",
        )

        assert plan is not None
        assert plan.recovery_strategy == "restart_phase"

    @pytest.mark.asyncio
    async def test_plan_recovery_max_attempts_exceeded(self, session_manager):
        """Should not plan recovery if max attempts exceeded."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        # Simulate multiple recovery attempts
        for _ in range(3):
            session.recovery_count += 1

        session.state = SessionState.PAUSED
        await session_manager._save_session(session)

        plan = await session_manager.plan_recovery(
            workflow_id=workflow_id,
            agent_name="specifier",
        )

        assert plan is None  # Cannot recover


class TestRecoveryExecution:
    """Integration tests for recovery execution."""

    @pytest.fixture
    def session_manager(self, monkeypatch):
        """Create session manager with mock state."""
        manager = SessionManager()
        mock_state = MockStateManager()
        manager._state_manager = mock_state
        return manager

    @pytest.mark.asyncio
    async def test_execute_recovery(self, session_manager):
        """Should execute recovery plan and update session."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
        )

        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=5,
            total_steps=10,
        )

        await session_manager.update_session_state(
            session_id=session.id,
            state=SessionState.PAUSED,
        )

        plan = await session_manager.plan_recovery(
            workflow_id=workflow_id,
            agent_name="planner",
        )

        recovered = await session_manager.execute_recovery(plan)

        assert recovered.state == SessionState.ACTIVE
        assert recovered.recovery_count == 1

    @pytest.mark.asyncio
    async def test_get_conversation_history(self, session_manager):
        """Should retrieve conversation history for resumption."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
        )

        conversation = [
            {"role": "user", "content": "Create the architecture"},
            {"role": "assistant", "content": "I'll design a modular system..."},
            {"role": "user", "content": "Add caching"},
            {"role": "assistant", "content": "Adding Redis cache layer..."},
        ]

        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.LLM_RESPONSE,
            conversation_history=conversation,
        )

        history = await session_manager.get_conversation_history(session.id)

        assert len(history) == 4
        assert history[0]["role"] == "user"
        assert history[-1]["role"] == "assistant"
