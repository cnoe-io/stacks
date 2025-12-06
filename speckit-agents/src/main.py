"""Main entrypoint for SpecKit agents using Claude Agent SDK with Dapr orchestration.

This module implements the hybrid pattern:
- Claude Agent SDK handles all LLM-powered agent execution
- Dapr handles distributed systems (pub/sub, state, durability)
- Orchestrator is pure Dapr routing (no LLM)
"""

from __future__ import annotations

import logging
import signal
import sys
from typing import TYPE_CHECKING

import uvicorn
from fastapi import FastAPI

from src.common.config import get_settings
from src.common.health import router as health_router

if TYPE_CHECKING:
    pass

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def create_app(agent_name: str) -> FastAPI:
    """Create FastAPI app with health endpoints.

    Args:
        agent_name: Name of the agent

    Returns:
        Configured FastAPI app
    """
    app = FastAPI(
        title=f"SpecKit {agent_name} Agent",
        version="2.0.0",
        description=f"Claude Agent SDK powered {agent_name} agent with Dapr orchestration",
    )

    # Add health endpoints from common module
    app.include_router(health_router)

    return app


def handle_signal(signum: int, frame: object) -> None:
    """Handle shutdown signals gracefully."""
    logger.info(f"Received signal {signum}, initiating shutdown...")
    sys.exit(0)


def run_orchestrator(port: int) -> None:
    """Run the orchestrator (pure Dapr router - no LLM).

    The orchestrator manages workflow lifecycle using only Dapr pub/sub
    and state management. It does NOT use Claude SDK.
    """
    from src.agents.orchestrator import create_orchestrator_app

    app = create_orchestrator_app()
    logger.info("Starting orchestrator (pure Dapr routing, no LLM)...")

    uvicorn.run(app, host="0.0.0.0", port=port)


def run_claude_agent(agent_name: str, port: int) -> None:
    """Run a Claude SDK powered agent.

    Claude SDK agents:
    - specifier: Generates spec.md from feature descriptions
    - planner: Generates research.md, data-model.md, plan.md with parallel subagents
    - task-generator: Generates tasks.md from planning artifacts
    - implementer: Executes tasks with TDD workflow

    Args:
        agent_name: Name of the agent
        port: HTTP port
    """
    # Import agent-specific module based on name
    if agent_name == "specifier":
        from src.agents.specifier import create_specifier_app
        app = create_specifier_app()
    elif agent_name == "planner":
        from src.agents.planner import create_planner_app
        app = create_planner_app()
    elif agent_name == "task-generator":
        from src.agents.task_generator import create_task_generator_app
        app = create_task_generator_app()
    elif agent_name == "implementer":
        from src.agents.implementer import create_implementer_app
        app = create_implementer_app()
    else:
        raise ValueError(
            f"Unknown agent: {agent_name}. "
            f"Available agents: orchestrator, specifier, planner, task-generator, implementer"
        )

    logger.info(f"Starting Claude SDK agent: {agent_name}...")
    uvicorn.run(app, host="0.0.0.0", port=port)


def main() -> None:
    """Main entrypoint for SpecKit agents.

    Dispatches to the appropriate agent based on AGENT_NAME environment variable:
    - orchestrator: Pure Dapr router (no Claude SDK)
    - specifier, planner, task-generator, implementer: Claude SDK agents
    """
    # Register signal handlers
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    settings = get_settings()

    # Validate configuration
    errors = settings.validate()
    if errors:
        logger.error(f"Configuration errors: {errors}")
        sys.exit(1)

    agent_name = settings.agent_name
    port = settings.agent_port

    logger.info(f"Starting SpecKit agent: {agent_name}")
    logger.info(f"Listening on port: {port}")
    logger.info(f"Team: {settings.team_name}")
    logger.info(f"Topic: {settings.agent_topic}")

    try:
        if agent_name == "orchestrator":
            run_orchestrator(port)
        else:
            run_claude_agent(agent_name, port)

    except Exception as e:
        logger.error(f"Failed to start agent {agent_name}: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
