"""Session Recovery Service for long-running workflows.

Provides:
- Checkpoint persistence for workflow state
- Session restoration after agent restart
- Partial artifact recovery
- Claude SDK conversation resumption

Enables workflows to survive agent pod restarts without losing progress.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field

from .state_manager import get_state_manager

logger = logging.getLogger(__name__)

# Singleton instance
_session_manager: Optional["SessionManager"] = None


class CheckpointType(str, Enum):
    """Types of checkpoints that can be saved."""

    PHASE_START = "phase_start"
    PHASE_PROGRESS = "phase_progress"
    PHASE_COMPLETE = "phase_complete"
    TOOL_INVOCATION = "tool_invocation"
    LLM_RESPONSE = "llm_response"
    ARTIFACT_PARTIAL = "artifact_partial"
    ERROR = "error"


class SessionState(str, Enum):
    """Session lifecycle states."""

    ACTIVE = "active"
    PAUSED = "paused"
    RECOVERING = "recovering"
    COMPLETED = "completed"
    FAILED = "failed"


class Checkpoint(BaseModel):
    """Checkpoint for workflow session recovery."""

    id: UUID = Field(default_factory=uuid4)
    workflow_id: UUID
    session_id: UUID
    agent_name: str
    checkpoint_type: CheckpointType
    phase: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    # Progress tracking
    step_index: int = 0  # Current step within phase
    total_steps: int = 0  # Estimated total steps

    # State data
    data: dict[str, Any] = Field(default_factory=dict)

    # LLM conversation state (for Claude SDK resumption)
    conversation_history: list[dict[str, Any]] = Field(default_factory=list)

    # Partial artifacts
    partial_artifacts: dict[str, str] = Field(default_factory=dict)

    # Error context
    error: Optional[str] = None
    retry_count: int = 0


class Session(BaseModel):
    """Workflow session tracking."""

    id: UUID = Field(default_factory=uuid4)
    workflow_id: UUID
    agent_name: str
    state: SessionState = SessionState.ACTIVE
    current_phase: str = ""
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    # Langfuse integration
    langfuse_trace_id: Optional[str] = None
    langfuse_session_id: Optional[str] = None

    # Recovery metadata
    last_checkpoint_id: Optional[UUID] = None
    recovery_count: int = 0
    max_recoveries: int = 3

    @property
    def can_recover(self) -> bool:
        """Check if session can be recovered."""
        return (
            self.state in [SessionState.PAUSED, SessionState.RECOVERING]
            and self.recovery_count < self.max_recoveries
        )


class RecoveryPlan(BaseModel):
    """Plan for recovering a session."""

    session: Session
    checkpoint: Optional[Checkpoint]
    recovery_strategy: str  # "resume", "restart_phase", "restart_workflow"
    steps_to_skip: int = 0
    artifacts_to_restore: list[str] = Field(default_factory=list)
    estimated_work_saved_percent: float = 0.0


class SessionManager:
    """Manages workflow sessions and recovery."""

    def __init__(self):
        """Initialize session manager."""
        self._state_manager = get_state_manager()

    # -------------------------------------------------------------------------
    # Session Lifecycle
    # -------------------------------------------------------------------------

    async def create_session(
        self,
        workflow_id: UUID,
        agent_name: str,
        phase: str,
        langfuse_trace_id: str = None,
    ) -> Session:
        """Create a new session for a workflow phase.

        Args:
            workflow_id: Workflow being processed
            agent_name: Agent processing the workflow
            phase: Current workflow phase
            langfuse_trace_id: Optional Langfuse trace ID

        Returns:
            New session instance
        """
        session = Session(
            workflow_id=workflow_id,
            agent_name=agent_name,
            current_phase=phase,
            langfuse_trace_id=langfuse_trace_id,
            langfuse_session_id=f"session-{uuid4()}" if langfuse_trace_id else None,
        )

        await self._save_session(session)
        logger.info(
            f"Created session {session.id} for workflow {workflow_id} phase {phase}"
        )

        return session

    async def get_session(self, session_id: UUID) -> Optional[Session]:
        """Get session by ID."""
        key = f"session:{session_id}"
        data = await self._state_manager._get_state(key)
        if not data:
            return None
        return Session.model_validate_json(data)

    async def get_workflow_session(
        self, workflow_id: UUID, agent_name: str
    ) -> Optional[Session]:
        """Get active session for a workflow and agent."""
        key = f"workflow-session:{workflow_id}:{agent_name}"
        session_id = await self._state_manager._get_state(key)
        if not session_id:
            return None
        return await self.get_session(UUID(session_id))

    async def update_session_state(
        self, session_id: UUID, state: SessionState
    ) -> Optional[Session]:
        """Update session state."""
        session = await self.get_session(session_id)
        if not session:
            return None

        session.state = state
        session.updated_at = datetime.utcnow()
        await self._save_session(session)

        logger.info(f"Session {session_id} state updated to {state}")
        return session

    async def complete_session(self, session_id: UUID) -> Optional[Session]:
        """Mark session as completed."""
        return await self.update_session_state(session_id, SessionState.COMPLETED)

    async def fail_session(
        self, session_id: UUID, error: str = None
    ) -> Optional[Session]:
        """Mark session as failed."""
        session = await self.get_session(session_id)
        if not session:
            return None

        session.state = SessionState.FAILED
        session.updated_at = datetime.utcnow()
        await self._save_session(session)

        # Save error checkpoint
        if error:
            await self.save_checkpoint(
                session=session,
                checkpoint_type=CheckpointType.ERROR,
                data={"error": error},
            )

        return session

    # -------------------------------------------------------------------------
    # Checkpoint Management
    # -------------------------------------------------------------------------

    async def save_checkpoint(
        self,
        session: Session,
        checkpoint_type: CheckpointType,
        data: dict[str, Any] = None,
        step_index: int = 0,
        total_steps: int = 0,
        conversation_history: list[dict] = None,
        partial_artifacts: dict[str, str] = None,
    ) -> Checkpoint:
        """Save a checkpoint for session recovery.

        Args:
            session: Current session
            checkpoint_type: Type of checkpoint
            data: Checkpoint data
            step_index: Current step within phase
            total_steps: Total estimated steps
            conversation_history: Claude SDK conversation for resumption
            partial_artifacts: Partially generated artifacts

        Returns:
            Saved checkpoint
        """
        checkpoint = Checkpoint(
            workflow_id=session.workflow_id,
            session_id=session.id,
            agent_name=session.agent_name,
            checkpoint_type=checkpoint_type,
            phase=session.current_phase,
            step_index=step_index,
            total_steps=total_steps,
            data=data or {},
            conversation_history=conversation_history or [],
            partial_artifacts=partial_artifacts or {},
        )

        # Save checkpoint to state store
        key = f"checkpoint:{checkpoint.id}"
        await self._state_manager._save_state(key, checkpoint.model_dump_json())

        # Update session's last checkpoint
        session.last_checkpoint_id = checkpoint.id
        session.updated_at = datetime.utcnow()
        await self._save_session(session)

        # Index checkpoint by session for retrieval
        await self._add_checkpoint_to_index(session.id, checkpoint.id)

        logger.debug(
            f"Saved checkpoint {checkpoint.id} for session {session.id}: "
            f"{checkpoint_type} at step {step_index}/{total_steps}"
        )

        return checkpoint

    async def get_checkpoint(self, checkpoint_id: UUID) -> Optional[Checkpoint]:
        """Get checkpoint by ID."""
        key = f"checkpoint:{checkpoint_id}"
        data = await self._state_manager._get_state(key)
        if not data:
            return None
        return Checkpoint.model_validate_json(data)

    async def get_latest_checkpoint(self, session_id: UUID) -> Optional[Checkpoint]:
        """Get most recent checkpoint for a session."""
        session = await self.get_session(session_id)
        if not session or not session.last_checkpoint_id:
            return None
        return await self.get_checkpoint(session.last_checkpoint_id)

    async def get_session_checkpoints(self, session_id: UUID) -> list[Checkpoint]:
        """Get all checkpoints for a session."""
        key = f"checkpoint-index:{session_id}"
        index_data = await self._state_manager._get_state(key)
        if not index_data:
            return []

        checkpoint_ids = json.loads(index_data)
        checkpoints = []
        for cp_id in checkpoint_ids:
            cp = await self.get_checkpoint(UUID(cp_id))
            if cp:
                checkpoints.append(cp)

        return sorted(checkpoints, key=lambda c: c.timestamp)

    # -------------------------------------------------------------------------
    # Recovery Operations
    # -------------------------------------------------------------------------

    async def plan_recovery(self, workflow_id: UUID, agent_name: str) -> Optional[RecoveryPlan]:
        """Create a recovery plan for a workflow.

        Args:
            workflow_id: Workflow to recover
            agent_name: Agent recovering the workflow

        Returns:
            Recovery plan or None if no recovery needed
        """
        session = await self.get_workflow_session(workflow_id, agent_name)
        if not session:
            return None

        if not session.can_recover:
            logger.warning(
                f"Session {session.id} cannot recover: "
                f"state={session.state}, recoveries={session.recovery_count}"
            )
            return None

        checkpoint = await self.get_latest_checkpoint(session.id)

        # Determine recovery strategy based on checkpoint type
        if checkpoint is None:
            strategy = "restart_phase"
            steps_to_skip = 0
            work_saved = 0.0
        elif checkpoint.checkpoint_type == CheckpointType.PHASE_COMPLETE:
            strategy = "skip_phase"  # Phase already done, move to next
            steps_to_skip = checkpoint.total_steps
            work_saved = 100.0
        elif checkpoint.checkpoint_type in [
            CheckpointType.PHASE_PROGRESS,
            CheckpointType.LLM_RESPONSE,
        ]:
            strategy = "resume"  # Resume from checkpoint
            steps_to_skip = checkpoint.step_index
            work_saved = (checkpoint.step_index / max(checkpoint.total_steps, 1)) * 100
        elif checkpoint.checkpoint_type == CheckpointType.ERROR:
            strategy = "restart_phase"  # Restart phase after error
            steps_to_skip = 0
            work_saved = 0.0
        else:
            strategy = "restart_phase"
            steps_to_skip = 0
            work_saved = 0.0

        # Identify artifacts to restore
        artifacts_to_restore = list(checkpoint.partial_artifacts.keys()) if checkpoint else []

        plan = RecoveryPlan(
            session=session,
            checkpoint=checkpoint,
            recovery_strategy=strategy,
            steps_to_skip=steps_to_skip,
            artifacts_to_restore=artifacts_to_restore,
            estimated_work_saved_percent=work_saved,
        )

        logger.info(
            f"Recovery plan for workflow {workflow_id}: "
            f"strategy={strategy}, work_saved={work_saved:.1f}%"
        )

        return plan

    async def execute_recovery(self, plan: RecoveryPlan) -> Session:
        """Execute a recovery plan.

        Args:
            plan: Recovery plan to execute

        Returns:
            Recovered session
        """
        session = plan.session
        session.state = SessionState.RECOVERING
        session.recovery_count += 1
        session.updated_at = datetime.utcnow()

        await self._save_session(session)

        logger.info(
            f"Executing recovery for session {session.id}: "
            f"strategy={plan.recovery_strategy}, attempt={session.recovery_count}"
        )

        # Restore partial artifacts to workflow
        if plan.checkpoint and plan.artifacts_to_restore:
            for artifact_type, content in plan.checkpoint.partial_artifacts.items():
                logger.debug(f"Restoring partial artifact: {artifact_type}")
                # Note: actual artifact restoration would go through state_manager

        # Mark session as active again
        session.state = SessionState.ACTIVE
        await self._save_session(session)

        return session

    async def get_conversation_history(self, session_id: UUID) -> list[dict[str, Any]]:
        """Get Claude SDK conversation history for resumption.

        Args:
            session_id: Session to get history for

        Returns:
            List of conversation messages for Claude SDK
        """
        checkpoint = await self.get_latest_checkpoint(session_id)
        if not checkpoint:
            return []

        return checkpoint.conversation_history

    # -------------------------------------------------------------------------
    # Internal Methods
    # -------------------------------------------------------------------------

    async def _save_session(self, session: Session):
        """Save session to state store."""
        # Save by ID
        key = f"session:{session.id}"
        await self._state_manager._save_state(key, session.model_dump_json())

        # Index by workflow+agent for lookup
        index_key = f"workflow-session:{session.workflow_id}:{session.agent_name}"
        await self._state_manager._save_state(index_key, str(session.id))

    async def _add_checkpoint_to_index(self, session_id: UUID, checkpoint_id: UUID):
        """Add checkpoint to session's checkpoint index."""
        key = f"checkpoint-index:{session_id}"
        data = await self._state_manager._get_state(key)

        if data:
            index = json.loads(data)
        else:
            index = []

        index.append(str(checkpoint_id))
        await self._state_manager._save_state(key, json.dumps(index))


def get_session_manager() -> SessionManager:
    """Get or create the session manager singleton."""
    global _session_manager
    if _session_manager is None:
        _session_manager = SessionManager()
    return _session_manager
