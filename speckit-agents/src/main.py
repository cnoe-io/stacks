"""Main entrypoint for SpecKit agents with AGENT_NAME selection."""

from __future__ import annotations

import asyncio
import logging
import signal
import sys
from contextlib import asynccontextmanager
from typing import TYPE_CHECKING

import uvicorn
from fastapi import FastAPI

from src.common.config import get_config
from src.common.health import router as health_router

if TYPE_CHECKING:
    from collections.abc import AsyncGenerator

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Agent registry - maps AGENT_NAME to agent module
AGENT_REGISTRY: dict[str, str] = {
    "orchestrator": "src.agents.orchestrator",
    "specifier": "src.agents.specifier",
    "planner": "src.agents.planner",
    "task-generator": "src.agents.task_generator",
    "implementer": "src.agents.implementer",
}


def get_agent_router(agent_name: str):
    """Dynamically import and return the agent's router.

    Args:
        agent_name: Name of the agent to load

    Returns:
        FastAPI router for the agent

    Raises:
        ValueError: If agent_name is not registered
        ImportError: If agent module cannot be imported
    """
    if agent_name not in AGENT_REGISTRY:
        raise ValueError(
            f"Unknown agent: {agent_name}. "
            f"Available agents: {list(AGENT_REGISTRY.keys())}"
        )

    module_path = AGENT_REGISTRY[agent_name]
    try:
        # Dynamic import of agent module
        import importlib

        module = importlib.import_module(module_path)
        if not hasattr(module, "router"):
            raise ImportError(f"Agent module {module_path} has no 'router' attribute")
        return module.router
    except ImportError as e:
        logger.error(f"Failed to import agent module {module_path}: {e}")
        raise


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan handler for startup/shutdown."""
    config = get_config()
    logger.info(f"Starting SpecKit agent: {config.agent_name}")
    logger.info(f"Listening on port: {config.agent_port}")
    logger.info(f"Team: {config.team_name}")
    logger.info(f"Topic: {config.agent_topic}")

    yield

    logger.info(f"Shutting down SpecKit agent: {config.agent_name}")


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    config = get_config()

    app = FastAPI(
        title=f"SpecKit {config.agent_name.title()} Agent",
        description=f"SpecKit workflow agent: {config.agent_name}",
        version="0.1.0",
        lifespan=lifespan,
    )

    # Always include health endpoints
    app.include_router(health_router)

    # Include agent-specific router if available
    try:
        agent_router = get_agent_router(config.agent_name)
        app.include_router(agent_router)
        logger.info(f"Loaded agent router for: {config.agent_name}")
    except (ValueError, ImportError) as e:
        # Agent not yet implemented - log warning but continue
        # This allows health endpoints to work during development
        logger.warning(f"Agent router not available: {e}")

    return app


def handle_signal(signum: int, frame) -> None:
    """Handle shutdown signals gracefully."""
    logger.info(f"Received signal {signum}, initiating shutdown...")
    sys.exit(0)


def main() -> None:
    """Main entrypoint for the SpecKit agent."""
    # Register signal handlers
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    config = get_config()

    # Validate configuration
    errors = config.validate()
    if errors:
        logger.error(f"Configuration errors: {errors}")
        sys.exit(1)

    logger.info(f"Configuration validated for agent: {config.agent_name}")

    # Create and run the application
    app = create_app()

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=config.agent_port,
        log_level="info",
        access_log=True,
    )


if __name__ == "__main__":
    main()
