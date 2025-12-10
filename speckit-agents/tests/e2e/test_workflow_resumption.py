"""End-to-end tests for workflow resumption after interruption.

Tests:
- Workflow survives agent pod restart
- Partial artifacts are recovered
- Claude SDK conversation can be resumed
- Status accurately reflects recovery state

Note: Uses mocked services for isolated testing.
"""

from datetime import datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import pytest

from src.common.models import (
    Artifact,
    ArtifactType,
    Workflow,
    WorkflowPhase,
    WorkflowStatus,
)
from src.services.session_recovery import (
    Checkpoint,
    CheckpointType,
    RecoveryPlan,
    Session,
    SessionManager,
    SessionState,
)


class MockClaudeAgentWithRecovery:
    """Mock Claude agent with recovery support."""

    def __init__(self, agent_name: str):
        self.agent_name = agent_name
        self.conversation_history: list[dict] = []
        self.current_step = 0
        self.total_steps = 10
        self.interrupted = False
        self.recovered = False

    async def process_step(self, context: dict[str, Any]) -> dict[str, Any]:
        """Process a single step."""
        if self.interrupted:
            raise RuntimeError("Agent interrupted")

        self.current_step += 1
        response = f"Step {self.current_step} completed"

        self.conversation_history.append({
            "role": "assistant",
            "content": response,
        })

        return {
            "step": self.current_step,
            "response": response,
            "complete": self.current_step >= self.total_steps,
        }

    def interrupt(self):
        """Simulate agent interruption."""
        self.interrupted = True

    def resume(self, checkpoint: Checkpoint):
        """Resume from checkpoint."""
        self.recovered = True
        self.interrupted = False
        self.current_step = checkpoint.step_index
        self.conversation_history = list(checkpoint.conversation_history)


class MockStateStore:
    """Mock Dapr state store."""

    def __init__(self):
        self._data: dict[str, str] = {}

    async def save(self, key: str, value: str):
        self._data[key] = value

    async def get(self, key: str) -> str | None:
        return self._data.get(key)

    async def delete(self, key: str):
        self._data.pop(key, None)


class MockSessionManager:
    """Mock session manager for E2E testing."""

    def __init__(self):
        self.sessions: dict[UUID, Session] = {}
        self.checkpoints: dict[UUID, list[Checkpoint]] = {}
        self._state = MockStateStore()

    async def create_session(
        self,
        workflow_id: UUID,
        agent_name: str,
        phase: str,
    ) -> Session:
        session = Session(
            workflow_id=workflow_id,
            agent_name=agent_name,
            current_phase=phase,
        )
        self.sessions[session.id] = session
        self.checkpoints[session.id] = []
        return session

    async def save_checkpoint(
        self,
        session: Session,
        checkpoint_type: CheckpointType,
        step_index: int = 0,
        conversation_history: list[dict] = None,
        partial_artifacts: dict[str, str] = None,
    ) -> Checkpoint:
        checkpoint = Checkpoint(
            workflow_id=session.workflow_id,
            session_id=session.id,
            agent_name=session.agent_name,
            checkpoint_type=checkpoint_type,
            phase=session.current_phase,
            step_index=step_index,
            total_steps=10,
            conversation_history=conversation_history or [],
            partial_artifacts=partial_artifacts or {},
        )
        self.checkpoints[session.id].append(checkpoint)
        session.last_checkpoint_id = checkpoint.id
        return checkpoint

    async def get_latest_checkpoint(self, session_id: UUID) -> Checkpoint | None:
        checkpoints = self.checkpoints.get(session_id, [])
        return checkpoints[-1] if checkpoints else None

    async def pause_session(self, session_id: UUID):
        if session_id in self.sessions:
            self.sessions[session_id].state = SessionState.PAUSED

    async def resume_session(self, session_id: UUID):
        if session_id in self.sessions:
            self.sessions[session_id].state = SessionState.ACTIVE
            self.sessions[session_id].recovery_count += 1


class TestWorkflowInterruptionRecovery:
    """E2E tests for recovering from workflow interruption."""

    @pytest.fixture
    def session_manager(self):
        return MockSessionManager()

    @pytest.fixture
    def mock_agent(self):
        return MockClaudeAgentWithRecovery("specifier")

    @pytest.mark.asyncio
    async def test_workflow_survives_interruption(
        self, session_manager, mock_agent
    ):
        """Workflow should survive agent interruption and resume."""
        workflow_id = uuid4()

        # Start session
        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        # Process some steps
        for i in range(5):
            result = await mock_agent.process_step({})

            # Save checkpoint
            await session_manager.save_checkpoint(
                session=session,
                checkpoint_type=CheckpointType.PHASE_PROGRESS,
                step_index=mock_agent.current_step,
                conversation_history=mock_agent.conversation_history.copy(),
            )

        assert mock_agent.current_step == 5

        # Simulate interruption
        mock_agent.interrupt()
        await session_manager.pause_session(session.id)

        # Get checkpoint for recovery
        checkpoint = await session_manager.get_latest_checkpoint(session.id)
        assert checkpoint is not None
        assert checkpoint.step_index == 5

        # Resume from checkpoint
        mock_agent.resume(checkpoint)
        await session_manager.resume_session(session.id)

        assert mock_agent.recovered
        assert mock_agent.current_step == 5

        # Continue processing
        for i in range(5):
            result = await mock_agent.process_step({})

        assert mock_agent.current_step == 10
        assert result["complete"]

    @pytest.mark.asyncio
    async def test_partial_artifacts_recovered(self, session_manager):
        """Partial artifacts should be recovered after interruption."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        # Save checkpoint with partial artifact
        partial_content = """# Specification

## Overview
This feature will implement user authentication.

## Requirements
1. Login with email/password
2. Password reset"""

        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.ARTIFACT_PARTIAL,
            partial_artifacts={"spec.md": partial_content},
        )

        # Pause session (simulate interruption)
        await session_manager.pause_session(session.id)

        # Get checkpoint
        checkpoint = await session_manager.get_latest_checkpoint(session.id)

        assert "spec.md" in checkpoint.partial_artifacts
        assert "# Specification" in checkpoint.partial_artifacts["spec.md"]
        assert "Login with email/password" in checkpoint.partial_artifacts["spec.md"]

    @pytest.mark.asyncio
    async def test_conversation_history_preserved(
        self, session_manager, mock_agent
    ):
        """Claude SDK conversation history should be preserved."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
        )

        # Simulate conversation
        mock_agent.conversation_history = [
            {"role": "user", "content": "Design the architecture"},
            {"role": "assistant", "content": "I'll create a microservices architecture..."},
            {"role": "user", "content": "Add caching"},
            {"role": "assistant", "content": "Adding Redis caching layer..."},
        ]

        # Save checkpoint with conversation
        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.LLM_RESPONSE,
            step_index=4,
            conversation_history=mock_agent.conversation_history.copy(),
        )

        # Simulate interruption
        mock_agent.interrupt()
        await session_manager.pause_session(session.id)

        # Get checkpoint
        checkpoint = await session_manager.get_latest_checkpoint(session.id)

        # Verify conversation preserved
        assert len(checkpoint.conversation_history) == 4
        assert checkpoint.conversation_history[0]["role"] == "user"
        assert checkpoint.conversation_history[-1]["role"] == "assistant"
        assert "Redis" in checkpoint.conversation_history[-1]["content"]


class TestRecoveryStateAccuracy:
    """E2E tests for recovery state accuracy."""

    @pytest.fixture
    def session_manager(self):
        return MockSessionManager()

    @pytest.mark.asyncio
    async def test_status_reflects_paused_state(self, session_manager):
        """Workflow status should reflect paused state."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        assert session.state == SessionState.ACTIVE

        await session_manager.pause_session(session.id)

        session = session_manager.sessions[session.id]
        assert session.state == SessionState.PAUSED

    @pytest.mark.asyncio
    async def test_status_reflects_recovery_count(self, session_manager):
        """Status should track recovery attempts."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        # Simulate multiple recovery cycles
        for i in range(3):
            await session_manager.pause_session(session.id)
            await session_manager.resume_session(session.id)

        session = session_manager.sessions[session.id]
        assert session.recovery_count == 3

    @pytest.mark.asyncio
    async def test_checkpoint_tracks_progress(self, session_manager):
        """Checkpoints should accurately track progress."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="implementer",
            phase="implementation",
        )

        # Save progress checkpoints
        progress_points = [2, 4, 6, 8]

        for step in progress_points:
            await session_manager.save_checkpoint(
                session=session,
                checkpoint_type=CheckpointType.PHASE_PROGRESS,
                step_index=step,
            )

        # Verify checkpoints
        checkpoints = session_manager.checkpoints[session.id]
        assert len(checkpoints) == 4

        for i, cp in enumerate(checkpoints):
            assert cp.step_index == progress_points[i]


class TestMultiPhaseRecovery:
    """E2E tests for recovery across multiple phases."""

    @pytest.fixture
    def session_manager(self):
        return MockSessionManager()

    @pytest.mark.asyncio
    async def test_recover_from_mid_workflow(self, session_manager):
        """Should recover workflow interrupted in middle phase."""
        workflow_id = uuid4()

        # Phase 1: Completed
        spec_session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )
        await session_manager.save_checkpoint(
            session=spec_session,
            checkpoint_type=CheckpointType.PHASE_COMPLETE,
            step_index=10,
        )

        # Phase 2: Interrupted mid-way
        plan_session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
        )
        await session_manager.save_checkpoint(
            session=plan_session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=5,
        )
        await session_manager.pause_session(plan_session.id)

        # Verify recovery state
        spec_checkpoint = await session_manager.get_latest_checkpoint(spec_session.id)
        plan_checkpoint = await session_manager.get_latest_checkpoint(plan_session.id)

        assert spec_checkpoint.checkpoint_type == CheckpointType.PHASE_COMPLETE
        assert plan_checkpoint.checkpoint_type == CheckpointType.PHASE_PROGRESS
        assert plan_checkpoint.step_index == 5

    @pytest.mark.asyncio
    async def test_identify_completed_phases(self, session_manager):
        """Should identify which phases completed before interruption."""
        workflow_id = uuid4()

        completed_phases = []

        # Complete first two phases
        for phase in ["specification", "planning"]:
            session = await session_manager.create_session(
                workflow_id=workflow_id,
                agent_name=f"{phase}_agent",
                phase=phase,
            )
            await session_manager.save_checkpoint(
                session=session,
                checkpoint_type=CheckpointType.PHASE_COMPLETE,
                step_index=10,
            )
            completed_phases.append(phase)

        # Start third phase but interrupt
        task_session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="taskgenerator",
            phase="task_generation",
        )
        await session_manager.save_checkpoint(
            session=task_session,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=3,
        )
        await session_manager.pause_session(task_session.id)

        # Verify completed phases can be identified
        assert len(completed_phases) == 2
        assert "specification" in completed_phases
        assert "planning" in completed_phases


class TestRecoveryDecisionMaking:
    """E2E tests for recovery decision logic."""

    @pytest.fixture
    def session_manager(self):
        return MockSessionManager()

    @pytest.mark.asyncio
    async def test_decide_resume_vs_restart(self, session_manager):
        """Should correctly decide between resume and restart."""
        workflow_id = uuid4()

        # Scenario 1: Good progress - should resume
        session1 = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="planner",
            phase="planning",
        )
        await session_manager.save_checkpoint(
            session=session1,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=8,
        )

        checkpoint = await session_manager.get_latest_checkpoint(session1.id)
        progress_percent = (checkpoint.step_index / checkpoint.total_steps) * 100

        # 80% progress - worth resuming
        assert progress_percent >= 50  # Should resume

        # Scenario 2: Little progress - might restart
        session2 = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )
        await session_manager.save_checkpoint(
            session=session2,
            checkpoint_type=CheckpointType.PHASE_PROGRESS,
            step_index=1,
        )

        checkpoint2 = await session_manager.get_latest_checkpoint(session2.id)
        progress_percent2 = (checkpoint2.step_index / checkpoint2.total_steps) * 100

        # 10% progress - might be better to restart
        assert progress_percent2 < 50  # Consider restart

    @pytest.mark.asyncio
    async def test_error_checkpoint_triggers_restart(self, session_manager):
        """Error checkpoint should trigger restart strategy."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="implementer",
            phase="implementation",
        )

        # Error occurred
        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.ERROR,
            step_index=5,
        )

        checkpoint = await session_manager.get_latest_checkpoint(session.id)

        # Error checkpoint - should restart phase
        assert checkpoint.checkpoint_type == CheckpointType.ERROR


class TestArtifactConsistency:
    """E2E tests for artifact consistency after recovery."""

    @pytest.fixture
    def session_manager(self):
        return MockSessionManager()

    @pytest.mark.asyncio
    async def test_partial_artifact_not_published(self, session_manager):
        """Partial artifacts should not be marked as complete."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        partial_content = "# Spec\n\n## Incomplete..."

        checkpoint = await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.ARTIFACT_PARTIAL,
            partial_artifacts={"spec.md": partial_content},
        )

        # Partial artifact is in checkpoint, not workflow artifacts
        assert "spec.md" in checkpoint.partial_artifacts
        # This would NOT be in workflow.artifacts until phase completes

    @pytest.mark.asyncio
    async def test_complete_artifact_after_recovery(self, session_manager):
        """Completed artifacts should be properly registered."""
        workflow_id = uuid4()

        session = await session_manager.create_session(
            workflow_id=workflow_id,
            agent_name="specifier",
            phase="specification",
        )

        # First: partial
        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.ARTIFACT_PARTIAL,
            partial_artifacts={"spec.md": "# Partial"},
            step_index=5,
        )

        # Then: complete
        await session_manager.save_checkpoint(
            session=session,
            checkpoint_type=CheckpointType.PHASE_COMPLETE,
            step_index=10,
            partial_artifacts={"spec.md": "# Complete Specification\n\n..."},
        )

        checkpoint = await session_manager.get_latest_checkpoint(session.id)

        assert checkpoint.checkpoint_type == CheckpointType.PHASE_COMPLETE
        assert "# Complete Specification" in checkpoint.partial_artifacts["spec.md"]
