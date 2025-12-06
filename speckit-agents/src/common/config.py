"""Environment configuration with validation for SpecKit agents using Claude Agent SDK."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from typing import Optional


@dataclass
class Settings:
    """Configuration for SpecKit agents loaded from environment variables."""

    # Agent identity
    agent_name: str = field(default_factory=lambda: os.getenv("AGENT_NAME", "orchestrator"))
    agent_port: int = field(default_factory=lambda: int(os.getenv("AGENT_PORT", "8000")))
    agent_topic: str = field(default_factory=lambda: os.getenv("AGENT_TOPIC", ""))

    # Team configuration
    team_name: str = field(default_factory=lambda: os.getenv("TEAM_NAME", "speckit"))
    broadcast_topic: str = field(default_factory=lambda: os.getenv("BROADCAST_TOPIC", ""))
    workflow_status_topic: str = field(
        default_factory=lambda: os.getenv("WORKFLOW_STATUS_TOPIC", "")
    )

    # Dapr component names
    pubsub_name: str = field(default_factory=lambda: os.getenv("PUBSUB_NAME", "messagepubsub"))
    workflow_state_store: str = field(
        default_factory=lambda: os.getenv("WORKFLOW_STATE_STORE", "workflowstatestore")
    )
    registry_state_store: str = field(
        default_factory=lambda: os.getenv("REGISTRY_STATE_STORE", "agentregistrystore")
    )
    memory_store: str = field(default_factory=lambda: os.getenv("MEMORY_STORE", "memorystore"))

    # Dapr sidecar
    dapr_http_port: int = field(default_factory=lambda: int(os.getenv("DAPR_HTTP_PORT", "3500")))
    dapr_grpc_port: int = field(default_factory=lambda: int(os.getenv("DAPR_GRPC_PORT", "50001")))

    # Artifact storage
    artifacts_path: str = field(
        default_factory=lambda: os.getenv("ARTIFACTS_PATH", "/artifacts")
    )

    # Claude SDK configuration
    # Note: ANTHROPIC_API_KEY is read directly by Claude SDK from environment
    claude_model: str = field(
        default_factory=lambda: os.getenv("CLAUDE_MODEL", "claude-sonnet-4-20250514")
    )
    claude_max_turns: int = field(
        default_factory=lambda: int(os.getenv("CLAUDE_MAX_TURNS", "10"))
    )

    # Langfuse observability (graceful degradation if not configured)
    langfuse_enabled: bool = field(
        default_factory=lambda: os.getenv("LANGFUSE_ENABLED", "true").lower() == "true"
    )
    langfuse_host: str = field(
        default_factory=lambda: os.getenv("LANGFUSE_HOST", "")
    )
    langfuse_public_key: str = field(
        default_factory=lambda: os.getenv("LANGFUSE_PUBLIC_KEY", "")
    )
    langfuse_secret_key: str = field(
        default_factory=lambda: os.getenv("LANGFUSE_SECRET_KEY", "")
    )

    def __post_init__(self) -> None:
        """Set derived values after initialization."""
        if not self.agent_topic:
            self.agent_topic = f"{self.team_name}.{self.agent_name}.requests"
        if not self.broadcast_topic:
            self.broadcast_topic = f"{self.team_name}.broadcast"
        if not self.workflow_status_topic:
            self.workflow_status_topic = f"{self.team_name}.workflow.status"

        # Disable Langfuse if credentials are missing
        if self.langfuse_enabled and not all([
            self.langfuse_host,
            self.langfuse_public_key,
            self.langfuse_secret_key,
        ]):
            self.langfuse_enabled = False

    @property
    def dapr_base_url(self) -> str:
        """Get the Dapr sidecar HTTP base URL."""
        return f"http://localhost:{self.dapr_http_port}"

    @property
    def dapr_metadata_url(self) -> str:
        """Get the Dapr metadata endpoint URL for health checks."""
        return f"{self.dapr_base_url}/v1.0/metadata"

    def validate(self) -> list[str]:
        """Validate configuration and return list of errors."""
        errors: list[str] = []

        if not self.agent_name:
            errors.append("AGENT_NAME is required")
        if self.agent_port < 1 or self.agent_port > 65535:
            errors.append(f"AGENT_PORT must be 1-65535, got {self.agent_port}")
        if not self.team_name:
            errors.append("TEAM_NAME is required")
        if not self.pubsub_name:
            errors.append("PUBSUB_NAME is required")

        # Check ANTHROPIC_API_KEY for non-orchestrator agents
        if self.agent_name != "orchestrator" and not os.getenv("ANTHROPIC_API_KEY"):
            errors.append("ANTHROPIC_API_KEY is required for Claude SDK agents")

        return errors

    @classmethod
    def from_env(cls) -> "Settings":
        """Create Settings instance from environment variables."""
        settings = cls()
        errors = settings.validate()
        if errors:
            raise ValueError(f"Configuration errors: {', '.join(errors)}")
        return settings


# Singleton settings instance
_settings: Optional[Settings] = None


def get_settings() -> Settings:
    """Get the singleton settings instance."""
    global _settings
    if _settings is None:
        _settings = Settings.from_env()
    return _settings


# Backwards compatibility alias
Config = Settings
get_config = get_settings
