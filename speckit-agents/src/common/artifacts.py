"""Artifact storage utilities for SpecKit workflows."""

from __future__ import annotations

import hashlib
import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Optional
from uuid import UUID

from src.common.config import get_config
from src.common.models import Artifact, ArtifactType

logger = logging.getLogger(__name__)


class ArtifactStorage:
    """Handles reading and writing workflow artifacts.

    Artifacts are stored in a directory structure:
        {artifacts_path}/{workflow_id}/{filename}

    Example:
        /artifacts/abc123-def456/spec.md
        /artifacts/abc123-def456/plan.md
        /artifacts/abc123-def456/tasks.md
    """

    def __init__(self, base_path: Optional[str] = None) -> None:
        """Initialize artifact storage.

        Args:
            base_path: Base directory for artifacts. Defaults to config value.
        """
        config = get_config()
        self.base_path = Path(base_path or config.artifacts_path)

    def _get_workflow_dir(self, workflow_id: UUID) -> Path:
        """Get the directory path for a workflow's artifacts.

        Args:
            workflow_id: The workflow ID

        Returns:
            Path to the workflow's artifact directory
        """
        return self.base_path / str(workflow_id)

    def _get_artifact_path(self, workflow_id: UUID, filename: str) -> Path:
        """Get the full path for an artifact file.

        Args:
            workflow_id: The workflow ID
            filename: Artifact filename (e.g., "spec.md")

        Returns:
            Full path to the artifact file
        """
        return self._get_workflow_dir(workflow_id) / filename

    async def save(
        self,
        workflow_id: UUID,
        artifact_type: ArtifactType,
        content: str,
        created_by: str,
        filename: Optional[str] = None,
    ) -> Artifact:
        """Save an artifact to storage.

        Args:
            workflow_id: The workflow ID
            artifact_type: Type of artifact (SPEC, PLAN, etc.)
            content: Content to save
            created_by: Name of agent that created this
            filename: Optional custom filename. Defaults based on type.

        Returns:
            Created Artifact record
        """
        # Determine filename from type if not provided
        if filename is None:
            filename = self._get_default_filename(artifact_type)

        # Ensure directory exists
        workflow_dir = self._get_workflow_dir(workflow_id)
        workflow_dir.mkdir(parents=True, exist_ok=True)

        # Write content
        artifact_path = workflow_dir / filename
        artifact_path.write_text(content, encoding="utf-8")

        # Calculate hash
        content_hash = hashlib.sha256(content.encode()).hexdigest()

        # Create artifact record
        relative_path = f"{workflow_id}/{filename}"
        artifact = Artifact(
            workflow_id=workflow_id,
            type=artifact_type,
            path=relative_path,
            content_hash=content_hash,
            created_by=created_by,
        )

        logger.info(f"Saved artifact: {relative_path} ({artifact_type.value})")

        return artifact

    async def read(
        self,
        workflow_id: UUID,
        filename: str,
    ) -> Optional[str]:
        """Read an artifact's content.

        Args:
            workflow_id: The workflow ID
            filename: Artifact filename

        Returns:
            Content string or None if not found
        """
        artifact_path = self._get_artifact_path(workflow_id, filename)

        if not artifact_path.exists():
            logger.warning(f"Artifact not found: {artifact_path}")
            return None

        return artifact_path.read_text(encoding="utf-8")

    async def read_by_type(
        self,
        workflow_id: UUID,
        artifact_type: ArtifactType,
    ) -> Optional[str]:
        """Read an artifact by its type.

        Args:
            workflow_id: The workflow ID
            artifact_type: Type of artifact to read

        Returns:
            Content string or None if not found
        """
        filename = self._get_default_filename(artifact_type)
        return await self.read(workflow_id, filename)

    async def exists(
        self,
        workflow_id: UUID,
        filename: str,
    ) -> bool:
        """Check if an artifact exists.

        Args:
            workflow_id: The workflow ID
            filename: Artifact filename

        Returns:
            True if artifact exists
        """
        artifact_path = self._get_artifact_path(workflow_id, filename)
        return artifact_path.exists()

    async def list_artifacts(
        self,
        workflow_id: UUID,
    ) -> list[str]:
        """List all artifacts for a workflow.

        Args:
            workflow_id: The workflow ID

        Returns:
            List of artifact filenames
        """
        workflow_dir = self._get_workflow_dir(workflow_id)

        if not workflow_dir.exists():
            return []

        return [f.name for f in workflow_dir.iterdir() if f.is_file()]

    async def delete(
        self,
        workflow_id: UUID,
        filename: str,
    ) -> bool:
        """Delete an artifact.

        Args:
            workflow_id: The workflow ID
            filename: Artifact filename

        Returns:
            True if deleted, False if not found
        """
        artifact_path = self._get_artifact_path(workflow_id, filename)

        if not artifact_path.exists():
            return False

        artifact_path.unlink()
        logger.info(f"Deleted artifact: {workflow_id}/{filename}")
        return True

    async def delete_workflow_artifacts(
        self,
        workflow_id: UUID,
    ) -> int:
        """Delete all artifacts for a workflow.

        Args:
            workflow_id: The workflow ID

        Returns:
            Number of artifacts deleted
        """
        workflow_dir = self._get_workflow_dir(workflow_id)

        if not workflow_dir.exists():
            return 0

        count = 0
        for f in workflow_dir.iterdir():
            if f.is_file():
                f.unlink()
                count += 1

        # Remove empty directory
        try:
            workflow_dir.rmdir()
        except OSError:
            pass  # Directory not empty or other issue

        logger.info(f"Deleted {count} artifacts for workflow {workflow_id}")
        return count

    def _get_default_filename(self, artifact_type: ArtifactType) -> str:
        """Get default filename for an artifact type.

        Args:
            artifact_type: The artifact type

        Returns:
            Default filename
        """
        type_filenames = {
            ArtifactType.SPEC: "spec.md",
            ArtifactType.PLAN: "plan.md",
            ArtifactType.RESEARCH: "research.md",
            ArtifactType.DATA_MODEL: "data-model.md",
            ArtifactType.TASKS: "tasks.md",
            ArtifactType.CONTRACT: "contract.yaml",
            ArtifactType.SOURCE: "source.py",
            ArtifactType.TEST: "test.py",
        }
        return type_filenames.get(artifact_type, f"{artifact_type.value}.md")


# Singleton instance
_storage: Optional[ArtifactStorage] = None


def get_artifact_storage() -> ArtifactStorage:
    """Get the singleton artifact storage instance.

    Returns:
        ArtifactStorage instance
    """
    global _storage
    if _storage is None:
        _storage = ArtifactStorage()
    return _storage
