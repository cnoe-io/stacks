"""MCP tools for Dapr integration with Claude SDK.

These tools expose Dapr state store and pub/sub operations to Claude agents
via the MCP (Model Context Protocol) pattern.

Tools:
- get_workflow_state: Read workflow state from Dapr state store
- save_workflow_state: Write workflow state to Dapr state store
- publish_event: Publish message to Dapr pub/sub
- publish_phase_complete: Signal phase completion to orchestrator
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime
from typing import Any
from uuid import UUID

from dapr.clients import DaprClient

from src.common.config import get_settings

logger = logging.getLogger(__name__)


# ============================================================================
# Tool Functions
# ============================================================================


async def get_workflow_state(workflow_id: str) -> dict[str, Any]:
    """Get workflow state from Dapr state store.

    Args:
        workflow_id: UUID of the workflow

    Returns:
        Dict with workflow state or error message
    """
    settings = get_settings()
    client = DaprClient()

    try:
        key = f"workflow:{workflow_id}"
        state = await asyncio.to_thread(
            client.get_state,
            store_name=settings.workflow_state_store,
            key=key,
        )

        if state.data:
            return {
                "success": True,
                "content": [{"type": "text", "text": state.data.decode()}],
            }
        else:
            return {
                "success": False,
                "content": [{"type": "text", "text": f"No state found for workflow {workflow_id}"}],
            }
    except Exception as e:
        logger.error(f"Failed to get workflow state: {e}")
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
        }
    finally:
        client.close()


async def save_workflow_state(workflow_id: str, state: dict[str, Any]) -> dict[str, Any]:
    """Save workflow state to Dapr state store.

    Args:
        workflow_id: UUID of the workflow
        state: State dict to save

    Returns:
        Dict with success status
    """
    settings = get_settings()
    client = DaprClient()

    try:
        key = f"workflow:{workflow_id}"

        # Add updated_at timestamp
        state["updated_at"] = datetime.utcnow().isoformat()

        await asyncio.to_thread(
            client.save_state,
            store_name=settings.workflow_state_store,
            key=key,
            value=json.dumps(state),
        )

        logger.info(f"Saved workflow state: {workflow_id}")
        return {
            "success": True,
            "content": [{"type": "text", "text": f"Saved state for workflow {workflow_id}"}],
        }
    except Exception as e:
        logger.error(f"Failed to save workflow state: {e}")
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
        }
    finally:
        client.close()


async def publish_event(topic: str, data: dict[str, Any]) -> dict[str, Any]:
    """Publish message to Dapr pub/sub.

    Args:
        topic: Topic name to publish to
        data: Message data

    Returns:
        Dict with success status
    """
    settings = get_settings()
    client = DaprClient()

    try:
        await asyncio.to_thread(
            client.publish_event,
            pubsub_name=settings.pubsub_name,
            topic_name=topic,
            data=json.dumps(data),
            data_content_type="application/json",
        )

        logger.info(f"Published event to topic: {topic}")
        return {
            "success": True,
            "content": [{"type": "text", "text": f"Published to {topic}"}],
        }
    except Exception as e:
        logger.error(f"Failed to publish event: {e}")
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
        }
    finally:
        client.close()


async def publish_phase_complete(
    workflow_id: str,
    phase: str,
    agent_name: str,
    result: dict[str, Any] | None = None,
    trace_id: str | None = None,
) -> dict[str, Any]:
    """Publish phase completion event to orchestrator.

    Args:
        workflow_id: UUID of the workflow
        phase: Completed phase name (specification, planning, task_generation, implementation)
        agent_name: Name of the completing agent
        result: Optional result data
        trace_id: Optional Langfuse trace ID

    Returns:
        Dict with success status
    """
    settings = get_settings()
    client = DaprClient()

    try:
        topic = f"{settings.team_name}.orchestrator.requests"

        message = {
            "id": str(UUID(int=0)),  # Will be replaced with actual UUID
            "type": "PhaseComplete",
            "source": agent_name,
            "workflow_id": workflow_id,
            "task": f"phase_complete:{phase}",
            "context": {
                "completed_phase": phase,
                "result": result or {},
                "langfuse_trace_id": trace_id,
            },
            "timestamp": datetime.utcnow().isoformat(),
        }

        await asyncio.to_thread(
            client.publish_event,
            pubsub_name=settings.pubsub_name,
            topic_name=topic,
            data=json.dumps(message),
            data_content_type="application/json",
        )

        logger.info(f"Published phase completion: {phase} for workflow {workflow_id}")
        return {
            "success": True,
            "content": [
                {"type": "text", "text": f"Phase {phase} complete for workflow {workflow_id}"}
            ],
        }
    except Exception as e:
        logger.error(f"Failed to publish phase completion: {e}")
        return {
            "success": False,
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
        }
    finally:
        client.close()


# ============================================================================
# MCP Server Factory
# ============================================================================

# Note: The actual MCP server creation depends on the claude-code-sdk package.
# This is a placeholder that will be updated once we have the actual SDK.
# The pattern follows the research.md specification for create_sdk_mcp_server().

DAPR_TOOLS = {
    "get_workflow_state": {
        "description": "Get workflow state from Dapr state store",
        "parameters": {"workflow_id": {"type": "string", "description": "Workflow UUID"}},
        "function": get_workflow_state,
    },
    "save_workflow_state": {
        "description": "Save workflow state to Dapr state store",
        "parameters": {
            "workflow_id": {"type": "string", "description": "Workflow UUID"},
            "state": {"type": "object", "description": "State dict to save"},
        },
        "function": save_workflow_state,
    },
    "publish_event": {
        "description": "Publish message to Dapr pub/sub",
        "parameters": {
            "topic": {"type": "string", "description": "Topic name"},
            "data": {"type": "object", "description": "Message data"},
        },
        "function": publish_event,
    },
    "publish_phase_complete": {
        "description": "Signal phase completion to orchestrator",
        "parameters": {
            "workflow_id": {"type": "string", "description": "Workflow UUID"},
            "phase": {
                "type": "string",
                "description": "Phase name (specification, planning, task_generation, implementation)",
            },
            "agent_name": {"type": "string", "description": "Name of completing agent"},
            "result": {"type": "object", "description": "Optional result data"},
            "trace_id": {"type": "string", "description": "Optional Langfuse trace ID"},
        },
        "function": publish_phase_complete,
    },
}


def create_dapr_mcp_server():
    """Create MCP server for Dapr tools.

    Returns:
        MCP server instance with Dapr tools registered.

    Note: This is a placeholder. The actual implementation will use
    claude-code-sdk's create_sdk_mcp_server() function.
    """
    # Placeholder until we have the actual SDK
    return {
        "name": "dapr",
        "version": "1.0.0",
        "tools": DAPR_TOOLS,
    }


# Convenience export
dapr_mcp_server = create_dapr_mcp_server()
