"""Agent Registry Service for dynamic agent discovery and management.

Provides:
- Agent registration with heartbeat-based health tracking
- Agent discovery by name, capability, or availability
- Load balancing across multiple agent instances
- Automatic deregistration of stale agents

Uses Dapr state store for persistence with TTL-based expiration.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4

from dapr.clients import DaprClient
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

# Singleton instance
_agent_registry: Optional["AgentRegistry"] = None


class AgentStatus(str, Enum):
    """Agent health status."""

    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"


class AgentCapability(str, Enum):
    """Defined agent capabilities."""

    SPECIFICATION = "specification"
    PLANNING = "planning"
    TASK_GENERATION = "task_generation"
    IMPLEMENTATION = "implementation"
    ORCHESTRATION = "orchestration"
    ANALYSIS = "analysis"


class AgentInfo(BaseModel):
    """Registered agent information."""

    id: UUID = Field(default_factory=uuid4)
    name: str
    instance_id: str  # Unique per agent instance (pod)
    capabilities: list[AgentCapability]
    endpoint: str  # Service endpoint URL
    status: AgentStatus = AgentStatus.UNKNOWN
    current_workload: int = 0  # Number of active workflows
    max_workload: int = 5  # Maximum concurrent workflows
    metadata: dict[str, Any] = Field(default_factory=dict)
    registered_at: datetime = Field(default_factory=datetime.utcnow)
    last_heartbeat: datetime = Field(default_factory=datetime.utcnow)

    @property
    def is_available(self) -> bool:
        """Check if agent can accept new work."""
        return (
            self.status == AgentStatus.HEALTHY
            and self.current_workload < self.max_workload
        )

    @property
    def is_stale(self) -> bool:
        """Check if agent heartbeat is stale (>30s)."""
        return datetime.utcnow() - self.last_heartbeat > timedelta(seconds=30)


class AgentRegistration(BaseModel):
    """Request to register an agent."""

    name: str
    instance_id: str
    capabilities: list[AgentCapability]
    endpoint: str
    max_workload: int = 5
    metadata: dict[str, Any] = Field(default_factory=dict)


class HeartbeatRequest(BaseModel):
    """Agent heartbeat request."""

    instance_id: str
    status: AgentStatus = AgentStatus.HEALTHY
    current_workload: int = 0
    metadata: dict[str, Any] = Field(default_factory=dict)


class AgentRegistry:
    """Agent registry service using Dapr state store."""

    STORE_NAME = "agentregistrystore"
    AGENT_PREFIX = "agent:"
    INDEX_KEY = "agent:index"
    HEARTBEAT_TTL_SECONDS = 60

    def __init__(self, store_name: str = None):
        """Initialize registry with optional custom store name."""
        self._store_name = store_name or self.STORE_NAME
        self._dapr_client: Optional[DaprClient] = None
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._local_agent: Optional[AgentInfo] = None

    @property
    def dapr_client(self) -> DaprClient:
        """Get or create Dapr client."""
        if self._dapr_client is None:
            self._dapr_client = DaprClient()
        return self._dapr_client

    async def register(self, registration: AgentRegistration) -> AgentInfo:
        """Register an agent instance.

        Args:
            registration: Agent registration details

        Returns:
            Registered agent info with assigned ID
        """
        agent = AgentInfo(
            name=registration.name,
            instance_id=registration.instance_id,
            capabilities=registration.capabilities,
            endpoint=registration.endpoint,
            max_workload=registration.max_workload,
            metadata=registration.metadata,
            status=AgentStatus.HEALTHY,
        )

        # Save agent to state store
        key = f"{self.AGENT_PREFIX}{agent.instance_id}"
        self.dapr_client.save_state(
            store_name=self._store_name,
            key=key,
            value=agent.model_dump_json(),
        )

        # Update index
        await self._add_to_index(agent.instance_id)

        logger.info(
            f"Registered agent: {agent.name} ({agent.instance_id})",
            extra={
                "agent_id": str(agent.id),
                "capabilities": [c.value for c in agent.capabilities],
            },
        )

        return agent

    async def deregister(self, instance_id: str) -> bool:
        """Remove an agent from the registry.

        Args:
            instance_id: Agent instance ID to deregister

        Returns:
            True if agent was removed, False if not found
        """
        key = f"{self.AGENT_PREFIX}{instance_id}"

        # Check if exists
        state = self.dapr_client.get_state(store_name=self._store_name, key=key)
        if not state.data:
            return False

        # Delete from store
        self.dapr_client.delete_state(store_name=self._store_name, key=key)

        # Update index
        await self._remove_from_index(instance_id)

        logger.info(f"Deregistered agent: {instance_id}")
        return True

    async def heartbeat(self, request: HeartbeatRequest) -> Optional[AgentInfo]:
        """Update agent heartbeat.

        Args:
            request: Heartbeat request with status update

        Returns:
            Updated agent info or None if not found
        """
        key = f"{self.AGENT_PREFIX}{request.instance_id}"

        state = self.dapr_client.get_state(store_name=self._store_name, key=key)
        if not state.data:
            logger.warning(f"Heartbeat for unknown agent: {request.instance_id}")
            return None

        agent = AgentInfo.model_validate_json(state.data)
        agent.last_heartbeat = datetime.utcnow()
        agent.status = request.status
        agent.current_workload = request.current_workload
        agent.metadata.update(request.metadata)

        self.dapr_client.save_state(
            store_name=self._store_name,
            key=key,
            value=agent.model_dump_json(),
        )

        logger.debug(
            f"Heartbeat from {agent.name}: status={agent.status}, workload={agent.current_workload}"
        )
        return agent

    async def get_agent(self, instance_id: str) -> Optional[AgentInfo]:
        """Get agent by instance ID.

        Args:
            instance_id: Agent instance ID

        Returns:
            Agent info or None if not found
        """
        key = f"{self.AGENT_PREFIX}{instance_id}"
        state = self.dapr_client.get_state(store_name=self._store_name, key=key)

        if not state.data:
            return None

        return AgentInfo.model_validate_json(state.data)

    async def get_agents_by_name(self, name: str) -> list[AgentInfo]:
        """Get all agent instances by name.

        Args:
            name: Agent name (e.g., 'specifier', 'planner')

        Returns:
            List of matching agent instances
        """
        all_agents = await self.list_agents()
        return [a for a in all_agents if a.name == name]

    async def get_agents_by_capability(
        self, capability: AgentCapability
    ) -> list[AgentInfo]:
        """Get all agents with a specific capability.

        Args:
            capability: Required capability

        Returns:
            List of agents with the capability
        """
        all_agents = await self.list_agents()
        return [a for a in all_agents if capability in a.capabilities]

    async def get_available_agent(
        self,
        name: str = None,
        capability: AgentCapability = None,
    ) -> Optional[AgentInfo]:
        """Get an available agent for work assignment.

        Selects the agent with lowest current workload.

        Args:
            name: Optional agent name filter
            capability: Optional capability filter

        Returns:
            Available agent or None if none available
        """
        all_agents = await self.list_agents()

        # Apply filters
        candidates = [a for a in all_agents if a.is_available and not a.is_stale]

        if name:
            candidates = [a for a in candidates if a.name == name]

        if capability:
            candidates = [a for a in candidates if capability in a.capabilities]

        if not candidates:
            return None

        # Select agent with lowest workload
        return min(candidates, key=lambda a: a.current_workload)

    async def list_agents(self, include_stale: bool = False) -> list[AgentInfo]:
        """List all registered agents.

        Args:
            include_stale: Include agents with stale heartbeats

        Returns:
            List of registered agents
        """
        index = await self._get_index()
        agents = []

        for instance_id in index:
            agent = await self.get_agent(instance_id)
            if agent:
                if include_stale or not agent.is_stale:
                    agents.append(agent)

        return agents

    async def cleanup_stale_agents(self) -> int:
        """Remove agents with stale heartbeats.

        Returns:
            Number of agents removed
        """
        all_agents = await self.list_agents(include_stale=True)
        removed = 0

        for agent in all_agents:
            if agent.is_stale:
                await self.deregister(agent.instance_id)
                removed += 1
                logger.info(f"Removed stale agent: {agent.instance_id}")

        return removed

    async def update_workload(
        self, instance_id: str, workload_delta: int
    ) -> Optional[AgentInfo]:
        """Update agent workload count.

        Args:
            instance_id: Agent instance ID
            workload_delta: Change in workload (+1 or -1)

        Returns:
            Updated agent info or None if not found
        """
        agent = await self.get_agent(instance_id)
        if not agent:
            return None

        agent.current_workload = max(0, agent.current_workload + workload_delta)

        key = f"{self.AGENT_PREFIX}{instance_id}"
        self.dapr_client.save_state(
            store_name=self._store_name,
            key=key,
            value=agent.model_dump_json(),
        )

        return agent

    # -------------------------------------------------------------------------
    # Local Agent Management (for self-registration)
    # -------------------------------------------------------------------------

    async def register_local(
        self,
        name: str,
        capabilities: list[AgentCapability],
        endpoint: str,
        instance_id: str = None,
        max_workload: int = 5,
    ) -> AgentInfo:
        """Register the local agent and start heartbeat.

        Args:
            name: Agent name
            capabilities: Agent capabilities
            endpoint: Agent endpoint URL
            instance_id: Optional instance ID (defaults to hostname)
            max_workload: Maximum concurrent workflows

        Returns:
            Registered agent info
        """
        import socket

        instance_id = instance_id or socket.gethostname()

        registration = AgentRegistration(
            name=name,
            instance_id=instance_id,
            capabilities=capabilities,
            endpoint=endpoint,
            max_workload=max_workload,
        )

        self._local_agent = await self.register(registration)
        self._start_heartbeat()

        return self._local_agent

    async def deregister_local(self) -> bool:
        """Deregister the local agent and stop heartbeat."""
        self._stop_heartbeat()

        if self._local_agent:
            result = await self.deregister(self._local_agent.instance_id)
            self._local_agent = None
            return result

        return False

    def _start_heartbeat(self):
        """Start background heartbeat task."""
        if self._heartbeat_task is None or self._heartbeat_task.done():
            self._heartbeat_task = asyncio.create_task(self._heartbeat_loop())

    def _stop_heartbeat(self):
        """Stop background heartbeat task."""
        if self._heartbeat_task and not self._heartbeat_task.done():
            self._heartbeat_task.cancel()
            self._heartbeat_task = None

    async def _heartbeat_loop(self):
        """Background loop sending heartbeats."""
        while self._local_agent:
            try:
                await asyncio.sleep(10)  # Send heartbeat every 10 seconds

                if self._local_agent:
                    await self.heartbeat(
                        HeartbeatRequest(
                            instance_id=self._local_agent.instance_id,
                            status=self._local_agent.status,
                            current_workload=self._local_agent.current_workload,
                        )
                    )
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Heartbeat failed: {e}")

    # -------------------------------------------------------------------------
    # Index Management
    # -------------------------------------------------------------------------

    async def _get_index(self) -> list[str]:
        """Get list of all agent instance IDs."""
        state = self.dapr_client.get_state(
            store_name=self._store_name,
            key=self.INDEX_KEY,
        )

        if not state.data:
            return []

        return json.loads(state.data)

    async def _add_to_index(self, instance_id: str):
        """Add instance ID to index."""
        index = await self._get_index()
        if instance_id not in index:
            index.append(instance_id)
            self.dapr_client.save_state(
                store_name=self._store_name,
                key=self.INDEX_KEY,
                value=json.dumps(index),
            )

    async def _remove_from_index(self, instance_id: str):
        """Remove instance ID from index."""
        index = await self._get_index()
        if instance_id in index:
            index.remove(instance_id)
            self.dapr_client.save_state(
                store_name=self._store_name,
                key=self.INDEX_KEY,
                value=json.dumps(index),
            )

    def close(self):
        """Clean up resources."""
        self._stop_heartbeat()
        if self._dapr_client:
            self._dapr_client.close()
            self._dapr_client = None


def get_agent_registry(store_name: str = None) -> AgentRegistry:
    """Get or create the agent registry singleton.

    Args:
        store_name: Optional custom state store name

    Returns:
        AgentRegistry singleton instance
    """
    global _agent_registry
    if _agent_registry is None:
        _agent_registry = AgentRegistry(store_name=store_name)
    return _agent_registry
