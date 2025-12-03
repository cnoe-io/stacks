"""Environment configuration with validation for SpecKit agents."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Optional

from dotenv import load_dotenv

# Load .env file if present (for local development)
load_dotenv()


@dataclass
class Config:
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
    conversation_component: str = field(
        default_factory=lambda: os.getenv("CONVERSATION_COMPONENT", "anthropic")
    )

    # Dapr sidecar
    dapr_http_port: int = field(default_factory=lambda: int(os.getenv("DAPR_HTTP_PORT", "3500")))
    dapr_grpc_port: int = field(default_factory=lambda: int(os.getenv("DAPR_GRPC_PORT", "50001")))

    # Artifact storage
    artifacts_path: str = field(
        default_factory=lambda: os.getenv("ARTIFACTS_PATH", "/artifacts")
    )

    # LLM configuration
    llm_timeout_seconds: int = field(
        default_factory=lambda: int(os.getenv("LLM_TIMEOUT_SECONDS", "120"))
    )
    max_iterations: int = field(
        default_factory=lambda: int(os.getenv("MAX_ITERATIONS", "5"))
    )

    def __post_init__(self) -> None:
        """Set derived values after initialization."""
        if not self.agent_topic:
            self.agent_topic = f"{self.team_name}.{self.agent_name}.requests"
        if not self.broadcast_topic:
            self.broadcast_topic = f"{self.team_name}.broadcast"
        if not self.workflow_status_topic:
            self.workflow_status_topic = f"{self.team_name}.workflow.status"

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

        return errors

    @classmethod
    def from_env(cls) -> "Config":
        """Create Config instance from environment variables."""
        config = cls()
        errors = config.validate()
        if errors:
            raise ValueError(f"Configuration errors: {', '.join(errors)}")
        return config


# Singleton config instance
_config: Optional[Config] = None


def get_config() -> Config:
    """Get the singleton configuration instance."""
    global _config
    if _config is None:
        _config = Config.from_env()
    return _config
