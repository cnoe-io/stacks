"""Workflow state management service using Dapr state store.

Provides unified CRUD operations for:
- Workflow state (creation, updates, retrieval)
- Artifact storage (content and metadata)
- Session resumption (checkpoint/restore)

Uses Dapr state store with Redis backend for durability.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from dapr.clients import DaprClient

from src.common.config import get_settings
from src.common.models import (
    Artifact,
    ArtifactType,
    Workflow,
    WorkflowPhase,
    WorkflowStatus,
)

logger = logging.getLogger(__name__)


class StateManager:
    """Centralized state management using Dapr state store.

    Provides:
    - Workflow CRUD operations with optimistic concurrency
    - Artifact content storage and retrieval
    - Session checkpoint/restore for resumption
    - Consistent key prefix patterns for queries
    """

    def __init__(self) -> None:
        """Initialize the state manager."""
        self.settings = get_settings()
        self._dapr_client: Optional[DaprClient] = None

    @property
    def dapr_client(self) -> DaprClient:
        """Get or create Dapr client."""
        if self._dapr_client is None:
            self._dapr_client = DaprClient()
        return self._dapr_client

    # =========================================================================
    # Workflow State Operations
    # =========================================================================

    def _workflow_key(self, workflow_id: UUID) -> str:
        """Generate state key for workflow."""
        return f"workflow:{workflow_id}"

    async def create_workflow(
        self,
        feature_description: str,
        initial_phase: WorkflowPhase = WorkflowPhase.SPECIFICATION,
    ) -> Workflow:
        """Create a new workflow.

        Args:
            feature_description: Feature to implement
            initial_phase: Starting phase

        Returns:
            Created Workflow instance
        """
        workflow = Workflow(
            feature_description=feature_description,
            status=WorkflowStatus.PENDING,
            current_phase=initial_phase,
        )

        await self.save_workflow(workflow)
        logger.info(f"Created workflow: {workflow.id}")

        return workflow

    async def save_workflow(self, workflow: Workflow) -> None:
        """Save workflow state to Dapr state store.

        Args:
            workflow: Workflow to save
        """
        workflow.updated_at = datetime.utcnow()
        key = self._workflow_key(workflow.id)
        value = workflow.model_dump_json()

        try:
            await asyncio.to_thread(
                self.dapr_client.save_state,
                store_name=self.settings.workflow_state_store,
                key=key,
                value=value,
            )
            logger.debug(f"Saved workflow state: {workflow.id}")
        except Exception as e:
            logger.error(f"Failed to save workflow state: {e}")
            raise

    async def get_workflow(self, workflow_id: UUID) -> Optional[Workflow]:
        """Get workflow from state store.

        Args:
            workflow_id: Workflow UUID

        Returns:
            Workflow instance or None if not found
        """
        key = self._workflow_key(workflow_id)

        try:
            state = await asyncio.to_thread(
                self.dapr_client.get_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            if state.data:
                data = state.data.decode() if isinstance(state.data, bytes) else state.data
                return Workflow.model_validate_json(data)
        except Exception as e:
            logger.error(f"Failed to get workflow state: {e}")

        return None

    async def update_workflow_status(
        self,
        workflow_id: UUID,
        status: WorkflowStatus,
        phase: Optional[WorkflowPhase] = None,
        agent: Optional[str] = None,
        error: Optional[str] = None,
    ) -> Optional[Workflow]:
        """Update workflow status fields.

        Args:
            workflow_id: Workflow UUID
            status: New status
            phase: Optional new phase
            agent: Optional current agent
            error: Optional error message

        Returns:
            Updated Workflow or None if not found
        """
        workflow = await self.get_workflow(workflow_id)
        if not workflow:
            return None

        workflow.status = status
        if phase:
            workflow.current_phase = phase
        if agent:
            workflow.current_agent = agent
        if error:
            workflow.error = error
        if status == WorkflowStatus.COMPLETED:
            workflow.completed_at = datetime.utcnow()

        await self.save_workflow(workflow)
        return workflow

    async def delete_workflow(self, workflow_id: UUID) -> bool:
        """Delete a workflow from state store.

        Args:
            workflow_id: Workflow to delete

        Returns:
            True if deleted, False otherwise
        """
        key = self._workflow_key(workflow_id)

        try:
            await asyncio.to_thread(
                self.dapr_client.delete_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            logger.info(f"Deleted workflow: {workflow_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete workflow: {e}")
            return False

    # =========================================================================
    # Artifact Operations
    # =========================================================================

    def _artifact_key(self, workflow_id: UUID, artifact_type: ArtifactType) -> str:
        """Generate state key for artifact content."""
        return f"artifact:{workflow_id}:{artifact_type.value}"

    async def save_artifact(
        self,
        workflow_id: UUID,
        artifact_type: ArtifactType,
        content: str,
        created_by: str,
    ) -> Artifact:
        """Save artifact content and register in workflow.

        Args:
            workflow_id: Parent workflow ID
            artifact_type: Type of artifact
            content: Artifact content
            created_by: Agent that created artifact

        Returns:
            Created Artifact instance
        """
        import hashlib

        # Save content to state store
        key = self._artifact_key(workflow_id, artifact_type)

        try:
            await asyncio.to_thread(
                self.dapr_client.save_state,
                store_name=self.settings.workflow_state_store,
                key=key,
                value=content,
            )
            logger.debug(f"Saved artifact content: {key}")
        except Exception as e:
            logger.error(f"Failed to save artifact content: {e}")
            raise

        # Create artifact metadata
        content_hash = hashlib.sha256(content.encode()).hexdigest()
        artifact = Artifact(
            workflow_id=workflow_id,
            type=artifact_type,
            path=f"{artifact_type.value}.md",
            content_hash=content_hash,
            created_by=created_by,
        )

        # Update workflow with artifact metadata
        workflow = await self.get_workflow(workflow_id)
        if workflow:
            # Replace existing artifact of same type
            workflow.artifacts = [a for a in workflow.artifacts if a.type != artifact_type]
            workflow.artifacts.append(artifact)
            await self.save_workflow(workflow)

        return artifact

    async def get_artifact_content(
        self,
        workflow_id: UUID,
        artifact_type: ArtifactType,
    ) -> Optional[str]:
        """Get artifact content from state store.

        Args:
            workflow_id: Parent workflow ID
            artifact_type: Type of artifact

        Returns:
            Artifact content or None if not found
        """
        key = self._artifact_key(workflow_id, artifact_type)

        try:
            state = await asyncio.to_thread(
                self.dapr_client.get_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            if state.data:
                content = state.data.decode() if isinstance(state.data, bytes) else state.data
                return content
        except Exception as e:
            logger.error(f"Failed to get artifact content: {e}")

        return None

    # =========================================================================
    # Session Checkpoint/Resume
    # =========================================================================

    def _checkpoint_key(self, workflow_id: UUID) -> str:
        """Generate state key for session checkpoint."""
        return f"checkpoint:{workflow_id}"

    async def save_checkpoint(
        self,
        workflow_id: UUID,
        agent_name: str,
        checkpoint_data: dict[str, Any],
    ) -> None:
        """Save session checkpoint for resumption.

        Args:
            workflow_id: Workflow UUID
            agent_name: Agent saving checkpoint
            checkpoint_data: Checkpoint state data
        """
        key = self._checkpoint_key(workflow_id)

        checkpoint = {
            "workflow_id": str(workflow_id),
            "agent_name": agent_name,
            "timestamp": datetime.utcnow().isoformat(),
            "data": checkpoint_data,
        }

        try:
            await asyncio.to_thread(
                self.dapr_client.save_state,
                store_name=self.settings.workflow_state_store,
                key=key,
                value=json.dumps(checkpoint),
            )
            logger.info(f"Saved checkpoint: {workflow_id} ({agent_name})")
        except Exception as e:
            logger.error(f"Failed to save checkpoint: {e}")
            raise

    async def get_checkpoint(
        self,
        workflow_id: UUID,
    ) -> Optional[dict[str, Any]]:
        """Get session checkpoint for resumption.

        Args:
            workflow_id: Workflow UUID

        Returns:
            Checkpoint data or None if not found
        """
        key = self._checkpoint_key(workflow_id)

        try:
            state = await asyncio.to_thread(
                self.dapr_client.get_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            if state.data:
                data = state.data.decode() if isinstance(state.data, bytes) else state.data
                return json.loads(data)
        except Exception as e:
            logger.error(f"Failed to get checkpoint: {e}")

        return None

    async def delete_checkpoint(self, workflow_id: UUID) -> bool:
        """Delete session checkpoint.

        Args:
            workflow_id: Workflow UUID

        Returns:
            True if deleted
        """
        key = self._checkpoint_key(workflow_id)

        try:
            await asyncio.to_thread(
                self.dapr_client.delete_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            return True
        except Exception as e:
            logger.error(f"Failed to delete checkpoint: {e}")
            return False

    # =========================================================================
    # Internal State Operations (for session_recovery service)
    # =========================================================================

    async def _save_state(self, key: str, value: str) -> None:
        """Low-level state save operation.

        Args:
            key: State key
            value: JSON string value
        """
        try:
            await asyncio.to_thread(
                self.dapr_client.save_state,
                store_name=self.settings.workflow_state_store,
                key=key,
                value=value,
            )
        except Exception as e:
            logger.error(f"Failed to save state {key}: {e}")
            raise

    async def _get_state(self, key: str) -> Optional[str]:
        """Low-level state get operation.

        Args:
            key: State key

        Returns:
            JSON string value or None if not found
        """
        try:
            state = await asyncio.to_thread(
                self.dapr_client.get_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            if state.data:
                return state.data.decode() if isinstance(state.data, bytes) else state.data
        except Exception as e:
            logger.error(f"Failed to get state {key}: {e}")

        return None

    async def _delete_state(self, key: str) -> bool:
        """Low-level state delete operation.

        Args:
            key: State key

        Returns:
            True if deleted
        """
        try:
            await asyncio.to_thread(
                self.dapr_client.delete_state,
                store_name=self.settings.workflow_state_store,
                key=key,
            )
            return True
        except Exception as e:
            logger.error(f"Failed to delete state {key}: {e}")
            return False

    # =========================================================================
    # Lifecycle
    # =========================================================================

    def shutdown(self) -> None:
        """Close Dapr client connection."""
        if self._dapr_client:
            try:
                self._dapr_client.close()
            except Exception as e:
                logger.error(f"Error closing Dapr client: {e}")
            self._dapr_client = None


# Singleton instance
_state_manager: Optional[StateManager] = None


def get_state_manager() -> StateManager:
    """Get or create the singleton state manager."""
    global _state_manager
    if _state_manager is None:
        _state_manager = StateManager()
    return _state_manager
