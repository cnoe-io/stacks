"""MCP tools for artifact management.

Provides tools for reading and managing workflow artifacts (spec.md, plan.md, etc.)
from the artifacts directory structure.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from src.common.config import get_settings

logger = logging.getLogger(__name__)


# ============================================================================
# Artifact Type Mapping
# ============================================================================

ARTIFACT_FILENAMES = {
    "spec": "spec.md",
    "plan": "plan.md",
    "research": "research.md",
    "data_model": "data-model.md",
    "tasks": "tasks.md",
    "quickstart": "quickstart.md",
}


# ============================================================================
# Tool Functions
# ============================================================================


async def get_artifact(workflow_id: str, artifact_type: str) -> dict[str, Any]:
    """Read artifact content from workflow artifacts directory.

    Args:
        workflow_id: UUID of the workflow
        artifact_type: Type of artifact (spec, plan, research, data_model, tasks, quickstart)

    Returns:
        Dict with artifact content or error message
    """
    settings = get_settings()

    # Map artifact type to filename
    filename = ARTIFACT_FILENAMES.get(artifact_type.lower())
    if not filename:
        return {
            "success": False,
            "content": [
                {
                    "type": "text",
                    "text": f"Unknown artifact type: {artifact_type}. "
                    f"Available types: {', '.join(ARTIFACT_FILENAMES.keys())}",
                }
            ],
        }

    # Build path
    path = Path(settings.artifacts_path) / workflow_id / filename

    try:
        content = path.read_text()
        logger.info(f"Read artifact: {artifact_type} for workflow {workflow_id}")
        return {
            "success": True,
            "content": [{"type": "text", "text": content}],
        }
    except FileNotFoundError:
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Artifact not found: {path}"}],
        }
    except Exception as e:
        logger.error(f"Failed to read artifact: {e}")
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error reading artifact: {str(e)}"}],
        }


async def list_artifacts(workflow_id: str) -> dict[str, Any]:
    """List all artifacts in workflow directory.

    Args:
        workflow_id: UUID of the workflow

    Returns:
        Dict with list of artifact files
    """
    settings = get_settings()
    path = Path(settings.artifacts_path) / workflow_id

    try:
        if not path.exists():
            return {
                "success": False,
                "content": [{"type": "text", "text": f"Workflow directory not found: {path}"}],
            }

        files = [f.name for f in path.iterdir() if f.is_file()]
        logger.info(f"Listed artifacts for workflow {workflow_id}: {files}")

        return {
            "success": True,
            "content": [{"type": "text", "text": "\n".join(files) if files else "No artifacts found"}],
        }
    except Exception as e:
        logger.error(f"Failed to list artifacts: {e}")
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error listing artifacts: {str(e)}"}],
        }


async def save_artifact(
    workflow_id: str,
    artifact_type: str,
    content: str,
) -> dict[str, Any]:
    """Save artifact content to workflow artifacts directory.

    Args:
        workflow_id: UUID of the workflow
        artifact_type: Type of artifact
        content: Artifact content to save

    Returns:
        Dict with success status
    """
    settings = get_settings()

    # Map artifact type to filename
    filename = ARTIFACT_FILENAMES.get(artifact_type.lower())
    if not filename:
        return {
            "success": False,
            "content": [
                {
                    "type": "text",
                    "text": f"Unknown artifact type: {artifact_type}. "
                    f"Available types: {', '.join(ARTIFACT_FILENAMES.keys())}",
                }
            ],
        }

    # Build path and ensure directory exists
    dir_path = Path(settings.artifacts_path) / workflow_id
    dir_path.mkdir(parents=True, exist_ok=True)
    path = dir_path / filename

    try:
        path.write_text(content)
        logger.info(f"Saved artifact: {artifact_type} for workflow {workflow_id}")
        return {
            "success": True,
            "content": [{"type": "text", "text": f"Saved {artifact_type} to {path}"}],
        }
    except Exception as e:
        logger.error(f"Failed to save artifact: {e}")
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error saving artifact: {str(e)}"}],
        }


# ============================================================================
# MCP Server Factory
# ============================================================================

ARTIFACT_TOOLS = {
    "get_artifact": {
        "description": "Read artifact from previous workflow phase",
        "parameters": {
            "workflow_id": {"type": "string", "description": "Workflow UUID"},
            "artifact_type": {
                "type": "string",
                "description": "Artifact type (spec, plan, research, data_model, tasks, quickstart)",
            },
        },
        "function": get_artifact,
    },
    "list_artifacts": {
        "description": "List all artifacts in workflow directory",
        "parameters": {
            "workflow_id": {"type": "string", "description": "Workflow UUID"},
        },
        "function": list_artifacts,
    },
    "save_artifact": {
        "description": "Save artifact to workflow directory",
        "parameters": {
            "workflow_id": {"type": "string", "description": "Workflow UUID"},
            "artifact_type": {
                "type": "string",
                "description": "Artifact type (spec, plan, research, data_model, tasks)",
            },
            "content": {"type": "string", "description": "Artifact content"},
        },
        "function": save_artifact,
    },
}


def create_artifact_mcp_server():
    """Create MCP server for artifact tools.

    Returns:
        MCP server instance with artifact tools registered.
    """
    return {
        "name": "artifacts",
        "version": "1.0.0",
        "tools": ARTIFACT_TOOLS,
    }


artifact_mcp_server = create_artifact_mcp_server()
