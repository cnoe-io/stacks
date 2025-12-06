"""Workflow Queue Service for managing concurrent workflow limits.

Provides:
- Concurrent workflow limit enforcement per agent
- Queue position tracking for waiting workflows
- Fair scheduling with FIFO ordering
- Automatic cleanup of completed/failed workflows
"""

from __future__ import annotations

import asyncio
import logging
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID

logger = logging.getLogger(__name__)


class QueueStatus(str, Enum):
    """Status of a queued workflow."""

    WAITING = "waiting"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class QueuedWorkflow:
    """A workflow in the queue."""

    workflow_id: UUID
    agent_name: str
    priority: int = 0  # Higher = more priority
    queued_at: datetime = field(default_factory=datetime.utcnow)
    started_at: Optional[datetime] = None
    status: QueueStatus = QueueStatus.WAITING


@dataclass
class QueuePosition:
    """Queue position information for a workflow."""

    workflow_id: UUID
    position: int  # 0 = currently processing, 1+ = waiting
    total_waiting: int
    estimated_wait_seconds: Optional[int] = None
    status: QueueStatus = QueueStatus.WAITING


class WorkflowQueue:
    """Manages concurrent workflow limits per agent."""

    def __init__(
        self,
        max_concurrent_per_agent: int = 5,
        default_timeout_seconds: int = 3600,
    ):
        """Initialize workflow queue.

        Args:
            max_concurrent_per_agent: Maximum concurrent workflows per agent
            default_timeout_seconds: Default timeout for workflow processing
        """
        self.max_concurrent = max_concurrent_per_agent
        self.default_timeout = default_timeout_seconds

        # Queues per agent
        self._waiting: dict[str, deque[QueuedWorkflow]] = {}
        self._processing: dict[str, list[QueuedWorkflow]] = {}

        # Quick lookup by workflow ID
        self._workflows: dict[UUID, QueuedWorkflow] = {}

        # Lock for thread safety
        self._lock = asyncio.Lock()

    async def enqueue(
        self,
        workflow_id: UUID,
        agent_name: str,
        priority: int = 0,
    ) -> QueuePosition:
        """Add a workflow to the queue.

        Args:
            workflow_id: Workflow ID
            agent_name: Target agent name
            priority: Priority level (higher = more urgent)

        Returns:
            Queue position information
        """
        async with self._lock:
            # Initialize agent queues if needed
            if agent_name not in self._waiting:
                self._waiting[agent_name] = deque()
                self._processing[agent_name] = []

            # Create queued workflow
            qw = QueuedWorkflow(
                workflow_id=workflow_id,
                agent_name=agent_name,
                priority=priority,
            )

            # Check if we can start immediately
            if len(self._processing[agent_name]) < self.max_concurrent:
                qw.status = QueueStatus.PROCESSING
                qw.started_at = datetime.utcnow()
                self._processing[agent_name].append(qw)
                self._workflows[workflow_id] = qw

                logger.info(
                    f"Workflow {workflow_id} started immediately on {agent_name} "
                    f"({len(self._processing[agent_name])}/{self.max_concurrent})"
                )

                return QueuePosition(
                    workflow_id=workflow_id,
                    position=0,
                    total_waiting=len(self._waiting[agent_name]),
                    status=QueueStatus.PROCESSING,
                )

            # Add to waiting queue
            self._waiting[agent_name].append(qw)
            self._workflows[workflow_id] = qw

            position = len(self._waiting[agent_name])
            total_waiting = position

            logger.info(
                f"Workflow {workflow_id} queued at position {position} "
                f"for {agent_name}"
            )

            return QueuePosition(
                workflow_id=workflow_id,
                position=position,
                total_waiting=total_waiting,
                estimated_wait_seconds=self._estimate_wait(agent_name, position),
                status=QueueStatus.WAITING,
            )

    async def complete(
        self,
        workflow_id: UUID,
        success: bool = True,
    ) -> Optional[QueuedWorkflow]:
        """Mark a workflow as completed and start next in queue.

        Args:
            workflow_id: Workflow ID
            success: Whether workflow completed successfully

        Returns:
            Next workflow started, if any
        """
        async with self._lock:
            qw = self._workflows.get(workflow_id)
            if not qw:
                return None

            qw.status = QueueStatus.COMPLETED if success else QueueStatus.FAILED
            agent_name = qw.agent_name

            # Remove from processing
            if qw in self._processing.get(agent_name, []):
                self._processing[agent_name].remove(qw)

            logger.info(
                f"Workflow {workflow_id} completed on {agent_name} "
                f"(success={success})"
            )

            # Start next waiting workflow
            return await self._start_next(agent_name)

    async def cancel(self, workflow_id: UUID) -> bool:
        """Cancel a queued workflow.

        Args:
            workflow_id: Workflow ID to cancel

        Returns:
            True if cancelled, False if not found
        """
        async with self._lock:
            qw = self._workflows.get(workflow_id)
            if not qw:
                return False

            qw.status = QueueStatus.CANCELLED
            agent_name = qw.agent_name

            # Remove from waiting queue
            if qw in self._waiting.get(agent_name, deque()):
                self._waiting[agent_name].remove(qw)

            # Remove from processing
            if qw in self._processing.get(agent_name, []):
                self._processing[agent_name].remove(qw)

            logger.info(f"Workflow {workflow_id} cancelled")
            return True

    async def get_position(self, workflow_id: UUID) -> Optional[QueuePosition]:
        """Get current queue position for a workflow.

        Args:
            workflow_id: Workflow ID

        Returns:
            Queue position or None if not found
        """
        async with self._lock:
            qw = self._workflows.get(workflow_id)
            if not qw:
                return None

            if qw.status == QueueStatus.PROCESSING:
                return QueuePosition(
                    workflow_id=workflow_id,
                    position=0,
                    total_waiting=len(self._waiting.get(qw.agent_name, [])),
                    status=QueueStatus.PROCESSING,
                )

            if qw.status == QueueStatus.WAITING:
                waiting = list(self._waiting.get(qw.agent_name, []))
                try:
                    position = waiting.index(qw) + 1
                except ValueError:
                    position = 0

                return QueuePosition(
                    workflow_id=workflow_id,
                    position=position,
                    total_waiting=len(waiting),
                    estimated_wait_seconds=self._estimate_wait(qw.agent_name, position),
                    status=QueueStatus.WAITING,
                )

            return QueuePosition(
                workflow_id=workflow_id,
                position=-1,
                total_waiting=0,
                status=qw.status,
            )

    async def get_agent_status(self, agent_name: str) -> dict[str, Any]:
        """Get queue status for an agent.

        Args:
            agent_name: Agent name

        Returns:
            Queue status including processing and waiting counts
        """
        async with self._lock:
            processing = len(self._processing.get(agent_name, []))
            waiting = len(self._waiting.get(agent_name, []))

            return {
                "agent_name": agent_name,
                "max_concurrent": self.max_concurrent,
                "processing": processing,
                "waiting": waiting,
                "available_slots": max(0, self.max_concurrent - processing),
            }

    async def _start_next(self, agent_name: str) -> Optional[QueuedWorkflow]:
        """Start the next waiting workflow for an agent.

        Must be called with lock held.

        Args:
            agent_name: Agent name

        Returns:
            Started workflow or None
        """
        waiting = self._waiting.get(agent_name, deque())
        processing = self._processing.get(agent_name, [])

        if not waiting or len(processing) >= self.max_concurrent:
            return None

        # Get next workflow (FIFO)
        qw = waiting.popleft()
        qw.status = QueueStatus.PROCESSING
        qw.started_at = datetime.utcnow()
        processing.append(qw)

        logger.info(
            f"Started queued workflow {qw.workflow_id} on {agent_name} "
            f"({len(processing)}/{self.max_concurrent})"
        )

        return qw

    def _estimate_wait(self, agent_name: str, position: int) -> int:
        """Estimate wait time in seconds.

        Args:
            agent_name: Agent name
            position: Queue position

        Returns:
            Estimated seconds to wait
        """
        # Simple estimation: 5 minutes per position
        avg_processing_time = 300  # 5 minutes
        return position * avg_processing_time


# Singleton instance
_workflow_queue: Optional[WorkflowQueue] = None


def get_workflow_queue() -> WorkflowQueue:
    """Get or create the workflow queue singleton."""
    global _workflow_queue
    if _workflow_queue is None:
        _workflow_queue = WorkflowQueue()
    return _workflow_queue
