"""Integration tests for Dapr state store connectivity.

Tests:
- Workflow state CRUD operations
- Artifact content storage
- Checkpoint persistence

Note: These tests use mocked Dapr client for unit testing.
For actual integration tests, run with Dapr sidecar available.
"""

from datetime import datetime
from unittest.mock import patch, AsyncMock
from uuid import uuid4

import pytest

from src.common.models import (
    ArtifactType,
    Workflow,
    WorkflowPhase,
    WorkflowStatus,
)
from src.services.state_manager import StateManager, get_state_manager


class TestStateManagerWorkflowOperations:
    """Integration tests for workflow state operations."""

    @pytest.fixture
    def state_manager(self, patch_dapr_client, mock_dapr_client):
        """Get state manager with mocked Dapr client."""
        manager = StateManager()
        manager._dapr_client = mock_dapr_client
        return manager

    @pytest.mark.asyncio
    async def test_create_workflow(self, state_manager):
        """Should create workflow with initial state."""
        workflow = await state_manager.create_workflow(
            feature_description="Implement user authentication"
        )

        assert workflow.id is not None
        assert workflow.feature_description == "Implement user authentication"
        assert workflow.status == WorkflowStatus.PENDING
        assert workflow.current_phase == WorkflowPhase.SPECIFICATION

    @pytest.mark.asyncio
    async def test_save_and_get_workflow(self, state_manager, sample_workflow):
        """Should save and retrieve workflow state."""
        await state_manager.save_workflow(sample_workflow)

        retrieved = await state_manager.get_workflow(sample_workflow.id)

        assert retrieved is not None
        assert retrieved.id == sample_workflow.id
        assert retrieved.feature_description == sample_workflow.feature_description

    @pytest.mark.asyncio
    async def test_update_workflow_status(self, state_manager, sample_workflow):
        """Should update workflow status fields."""
        await state_manager.save_workflow(sample_workflow)

        updated = await state_manager.update_workflow_status(
            workflow_id=sample_workflow.id,
            status=WorkflowStatus.PLANNING,
            phase=WorkflowPhase.PLANNING,
            agent="planner",
        )

        assert updated is not None
        assert updated.status == WorkflowStatus.PLANNING
        assert updated.current_phase == WorkflowPhase.PLANNING
        assert updated.current_agent == "planner"

    @pytest.mark.asyncio
    async def test_update_workflow_with_error(self, state_manager, sample_workflow):
        """Should update workflow with error message."""
        await state_manager.save_workflow(sample_workflow)

        updated = await state_manager.update_workflow_status(
            workflow_id=sample_workflow.id,
            status=WorkflowStatus.FAILED,
            error="Claude SDK timeout",
        )

        assert updated is not None
        assert updated.status == WorkflowStatus.FAILED
        assert updated.error == "Claude SDK timeout"

    @pytest.mark.asyncio
    async def test_get_nonexistent_workflow(self, state_manager):
        """Should return None for nonexistent workflow."""
        result = await state_manager.get_workflow(uuid4())

        assert result is None

    @pytest.mark.asyncio
    async def test_delete_workflow(self, state_manager, sample_workflow):
        """Should delete workflow state."""
        await state_manager.save_workflow(sample_workflow)

        deleted = await state_manager.delete_workflow(sample_workflow.id)

        assert deleted is True

        # Verify deleted
        result = await state_manager.get_workflow(sample_workflow.id)
        assert result is None


class TestStateManagerArtifactOperations:
    """Integration tests for artifact storage operations."""

    @pytest.fixture
    def state_manager(self, patch_dapr_client, mock_dapr_client):
        """Get state manager with mocked Dapr client."""
        manager = StateManager()
        manager._dapr_client = mock_dapr_client
        return manager

    @pytest.mark.asyncio
    async def test_save_artifact(self, state_manager, sample_workflow):
        """Should save artifact content and metadata."""
        await state_manager.save_workflow(sample_workflow)

        artifact = await state_manager.save_artifact(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.SPEC,
            content="# Feature Specification\n\nContent here...",
            created_by="specifier",
        )

        assert artifact is not None
        assert artifact.type == ArtifactType.SPEC
        assert artifact.created_by == "specifier"
        assert artifact.content_hash is not None

    @pytest.mark.asyncio
    async def test_get_artifact_content(self, state_manager, sample_workflow):
        """Should retrieve artifact content."""
        await state_manager.save_workflow(sample_workflow)

        content = "# Plan\n\nImplementation plan..."

        await state_manager.save_artifact(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.PLAN,
            content=content,
            created_by="planner",
        )

        retrieved = await state_manager.get_artifact_content(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.PLAN,
        )

        assert retrieved == content

    @pytest.mark.asyncio
    async def test_get_nonexistent_artifact(self, state_manager, sample_workflow):
        """Should return None for nonexistent artifact."""
        result = await state_manager.get_artifact_content(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.TASKS,
        )

        assert result is None

    @pytest.mark.asyncio
    async def test_artifact_updates_workflow(self, state_manager, sample_workflow):
        """Saving artifact should update workflow state."""
        await state_manager.save_workflow(sample_workflow)

        await state_manager.save_artifact(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.SPEC,
            content="Spec content",
            created_by="specifier",
        )

        workflow = await state_manager.get_workflow(sample_workflow.id)

        assert len(workflow.artifacts) == 1
        assert workflow.artifacts[0].type == ArtifactType.SPEC

    @pytest.mark.asyncio
    async def test_artifact_replaces_same_type(self, state_manager, sample_workflow):
        """Saving artifact should replace existing of same type."""
        await state_manager.save_workflow(sample_workflow)

        # Save first version
        await state_manager.save_artifact(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.SPEC,
            content="Version 1",
            created_by="specifier",
        )

        # Save second version
        await state_manager.save_artifact(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.SPEC,
            content="Version 2",
            created_by="specifier",
        )

        workflow = await state_manager.get_workflow(sample_workflow.id)

        # Should still have only one spec artifact
        assert len(workflow.artifacts) == 1

        # Content should be version 2
        content = await state_manager.get_artifact_content(
            workflow_id=sample_workflow.id,
            artifact_type=ArtifactType.SPEC,
        )
        assert content == "Version 2"


class TestStateManagerCheckpointOperations:
    """Integration tests for checkpoint operations."""

    @pytest.fixture
    def state_manager(self, patch_dapr_client, mock_dapr_client):
        """Get state manager with mocked Dapr client."""
        manager = StateManager()
        manager._dapr_client = mock_dapr_client
        return manager

    @pytest.mark.asyncio
    async def test_save_checkpoint(self, state_manager, sample_workflow):
        """Should save checkpoint data."""
        await state_manager.save_checkpoint(
            workflow_id=sample_workflow.id,
            agent_name="planner",
            checkpoint_data={
                "completed_subtasks": ["research", "data_model"],
                "pending_subtasks": ["architecture"],
            },
        )

        # Verify by retrieving
        checkpoint = await state_manager.get_checkpoint(sample_workflow.id)

        assert checkpoint is not None
        assert checkpoint["agent_name"] == "planner"
        assert "completed_subtasks" in checkpoint["data"]

    @pytest.mark.asyncio
    async def test_get_checkpoint(self, state_manager, sample_workflow):
        """Should retrieve checkpoint data."""
        await state_manager.save_checkpoint(
            workflow_id=sample_workflow.id,
            agent_name="implementer",
            checkpoint_data={
                "current_task": "T005",
                "completed_tasks": ["T001", "T002", "T003", "T004"],
            },
        )

        checkpoint = await state_manager.get_checkpoint(sample_workflow.id)

        assert checkpoint["data"]["current_task"] == "T005"
        assert len(checkpoint["data"]["completed_tasks"]) == 4

    @pytest.mark.asyncio
    async def test_get_nonexistent_checkpoint(self, state_manager):
        """Should return None for nonexistent checkpoint."""
        result = await state_manager.get_checkpoint(uuid4())

        assert result is None

    @pytest.mark.asyncio
    async def test_delete_checkpoint(self, state_manager, sample_workflow):
        """Should delete checkpoint."""
        await state_manager.save_checkpoint(
            workflow_id=sample_workflow.id,
            agent_name="task-generator",
            checkpoint_data={"tasks_generated": 10},
        )

        deleted = await state_manager.delete_checkpoint(sample_workflow.id)

        assert deleted is True

        result = await state_manager.get_checkpoint(sample_workflow.id)
        assert result is None

    @pytest.mark.asyncio
    async def test_checkpoint_overwrite(self, state_manager, sample_workflow):
        """Should overwrite existing checkpoint."""
        # First checkpoint
        await state_manager.save_checkpoint(
            workflow_id=sample_workflow.id,
            agent_name="planner",
            checkpoint_data={"step": 1},
        )

        # Second checkpoint (same workflow)
        await state_manager.save_checkpoint(
            workflow_id=sample_workflow.id,
            agent_name="planner",
            checkpoint_data={"step": 2},
        )

        checkpoint = await state_manager.get_checkpoint(sample_workflow.id)

        assert checkpoint["data"]["step"] == 2


class TestStateManagerSingleton:
    """Tests for state manager singleton behavior."""

    def test_get_state_manager_singleton(self, reset_singletons, mock_environment):
        """Should return same instance."""
        import src.services.state_manager as sm_module
        sm_module._state_manager = None

        manager1 = get_state_manager()
        manager2 = get_state_manager()

        assert manager1 is manager2

        # Cleanup
        sm_module._state_manager = None
