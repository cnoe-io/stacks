"""Base agent class with common Dapr configuration."""

from __future__ import annotations

import asyncio
import logging
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Any, Optional
from uuid import UUID

from dapr.clients import DaprClient
from dapr_agents.agents.configs import (
    AgentMemoryConfig,
    AgentPubSubConfig,
    AgentRegistryConfig,
    AgentStateConfig,
)
from dapr_agents.agents.prompting import AgentProfileConfig
from dapr_agents.memory import ConversationDaprStateMemory
from dapr_agents.storage.daprstores.stateservice import StateStoreService

from src.common.config import Config, get_config
from src.common.models import (
    Workflow,
    WorkflowMessage,
    WorkflowPhase,
    WorkflowStatus,
)

logger = logging.getLogger(__name__)


class BaseAgent(ABC):
    """Base class for all SpecKit agents with common Dapr configuration."""

    def __init__(
        self,
        name: str,
        role: str,
        goal: str,
        instructions: list[str],
        config: Optional[Config] = None,
    ) -> None:
        """Initialize base agent with Dapr configuration.

        Args:
            name: Agent name (e.g., "specifier", "planner")
            role: Agent role description
            goal: Agent's primary goal
            instructions: List of behavioral instructions
            config: Optional config override (defaults to env config)
        """
        self.config = config or get_config()
        self.name = name
        self.role = role
        self.goal = goal
        self.instructions = instructions

        # Dapr client (lazy initialized)
        self._dapr_client: Optional[DaprClient] = None

        # Build Dapr agent configurations
        self.profile = self._build_profile()
        self.pubsub = self._build_pubsub()
        self.state = self._build_state()
        self.registry = self._build_registry()
        self.memory = self._build_memory()

    def _build_profile(self) -> AgentProfileConfig:
        """Build agent profile configuration."""
        return AgentProfileConfig(
            name=self.name,
            role=self.role,
            goal=self.goal,
            instructions=self.instructions,
            style_guidelines=[
                "Be concise and focused on the task at hand.",
                "Follow SpecKit template formats strictly.",
                "Provide clear, actionable outputs.",
            ],
        )

    def _build_pubsub(self) -> AgentPubSubConfig:
        """Build pub/sub configuration."""
        return AgentPubSubConfig(
            pubsub_name=self.config.pubsub_name,
            agent_topic=f"{self.config.team_name}.{self.name}.requests",
            broadcast_topic=self.config.broadcast_topic,
        )

    def _build_state(self) -> AgentStateConfig:
        """Build state store configuration."""
        return AgentStateConfig(
            store=StateStoreService(
                store_name=self.config.workflow_state_store,
                key_prefix=f"{self.name}:",
            )
        )

    def _build_registry(self) -> AgentRegistryConfig:
        """Build agent registry configuration."""
        return AgentRegistryConfig(
            store=StateStoreService(store_name=self.config.registry_state_store),
            team_name=self.config.team_name,
        )

    def _build_memory(self) -> AgentMemoryConfig:
        """Build conversation memory configuration."""
        return AgentMemoryConfig(
            store=ConversationDaprStateMemory(
                store_name=self.config.memory_store,
                session_id=f"{self.name}-session",
            )
        )

    @property
    def dapr_client(self) -> DaprClient:
        """Get or create Dapr client."""
        if self._dapr_client is None:
            self._dapr_client = DaprClient()
        return self._dapr_client

    async def save_workflow_state(self, workflow: Workflow) -> None:
        """Save workflow state to Dapr state store."""
        workflow.updated_at = datetime.utcnow()
        key = f"workflow:{workflow.id}"
        value = workflow.model_dump_json()

        try:
            self.dapr_client.save_state(
                store_name=self.config.workflow_state_store,
                key=key,
                value=value,
            )
            logger.debug(f"Saved workflow state: {workflow.id}")
        except Exception as e:
            logger.error(f"Failed to save workflow state: {e}")
            raise

    async def get_workflow_state(self, workflow_id: UUID) -> Optional[Workflow]:
        """Get workflow state from Dapr state store."""
        key = f"workflow:{workflow_id}"

        try:
            state = self.dapr_client.get_state(
                store_name=self.config.workflow_state_store,
                key=key,
            )
            if state.data:
                return Workflow.model_validate_json(state.data)
        except Exception as e:
            logger.error(f"Failed to get workflow state: {e}")

        return None

    async def publish_status_update(
        self,
        workflow_id: UUID,
        status: WorkflowStatus,
        phase: WorkflowPhase,
        progress_percent: int = 0,
        error: Optional[str] = None,
    ) -> None:
        """Publish workflow status update to broadcast topic."""
        message = {
            "workflow_id": str(workflow_id),
            "status": status.value,
            "phase": phase.value,
            "agent": self.name,
            "progress_percent": progress_percent,
            "error": error,
            "timestamp": datetime.utcnow().isoformat(),
        }

        try:
            self.dapr_client.publish_event(
                pubsub_name=self.config.pubsub_name,
                topic_name=self.config.workflow_status_topic,
                data=message,
                data_content_type="application/json",
            )
            logger.debug(f"Published status update for workflow {workflow_id}")
        except Exception as e:
            logger.error(f"Failed to publish status update: {e}")

    async def route_to_agent(
        self,
        target_agent: str,
        workflow_id: UUID,
        task: str,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        """Route a task to another agent via pub/sub."""
        topic = f"{self.config.team_name}.{target_agent}.requests"
        message = WorkflowMessage(
            source=self.name,
            workflow_id=workflow_id,
            task=task,
            context=context or {},
        )

        try:
            self.dapr_client.publish_event(
                pubsub_name=self.config.pubsub_name,
                topic_name=topic,
                data=message.model_dump(),
                data_content_type="application/json",
                publish_metadata={"cloudevent.type": "AgentTask"},
            )
            logger.info(f"Routed task to {target_agent} for workflow {workflow_id}")
        except Exception as e:
            logger.error(f"Failed to route to {target_agent}: {e}")
            raise

    @abstractmethod
    async def process_task(
        self,
        workflow_id: UUID,
        task: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Process a task assigned to this agent.

        Args:
            workflow_id: The workflow this task belongs to
            task: Task description or instruction
            context: Additional context (artifacts, state, etc.)

        Returns:
            Result dict with output artifacts and status
        """
        pass

    async def shutdown(self) -> None:
        """Graceful shutdown of agent resources."""
        if self._dapr_client:
            try:
                self._dapr_client.close()
            except Exception as e:
                logger.error(f"Error closing Dapr client: {e}")
            self._dapr_client = None
