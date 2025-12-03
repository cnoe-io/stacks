"""Main entrypoint for SpecKit agents using DurableAgent pattern.

This module implements the dapr-agents SDK pattern for running agents:
- Worker agents (specifier, planner, task-generator, implementer) use DurableAgent
- Orchestrator uses LLMOrchestrator for workflow coordination
- Follows the reference implementation from dapr-agents quickstart 05-multi-agent-workflows
"""

from __future__ import annotations

import logging
import signal
import sys
from datetime import datetime
from typing import TYPE_CHECKING, Optional

from dapr_agents.agents.durable import DurableAgent
from dapr_agents.workflow.runners import AgentRunner

from src.common.config import get_config
from src.agents.base import create_durable_agent

if TYPE_CHECKING:
    pass

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Agent configuration registry - contains role, goal, and instructions for each agent
AGENT_CONFIGS = {
    "specifier": {
        "role": "Specification Writer",
        "goal": "Transform natural language feature descriptions into comprehensive, actionable spec.md documents",
        "instructions": [
            "Analyze feature descriptions to extract core requirements",
            "Generate user stories with clear acceptance criteria",
            "Define explicit scope boundaries (in/out of scope)",
            "Document assumptions and technical constraints",
            "Ensure all requirements are testable and measurable",
            "Follow the spec.md template format exactly",
        ],
    },
    "planner": {
        "role": "Implementation Planner",
        "goal": "Transform specifications into comprehensive implementation plans with architecture, research, and data models",
        "instructions": [
            "Analyze spec.md to understand all requirements",
            "Design a high-level architecture that addresses all user stories",
            "Research and justify technology choices",
            "Define clear data models with relationships",
            "Create an implementation roadmap in dependency order",
            "Identify risks and propose mitigations",
        ],
    },
    "task-generator": {
        "role": "Task Breakdown Specialist",
        "goal": "Convert implementation plans into actionable, dependency-ordered task lists",
        "instructions": [
            "Analyze plan.md to identify all required work items",
            "Order tasks by dependencies so they can be executed sequentially",
            "Mark parallel-safe tasks with [P] indicator",
            "Tag tasks with user story references for traceability",
            "Include specific file paths for each task",
            "Group tasks into logical phases (Setup, Core, Tests, etc.)",
        ],
    },
    "implementer": {
        "role": "Task Implementer",
        "goal": "Execute tasks with TDD approach, writing tests before code",
        "instructions": [
            "Read and understand task requirements",
            "Identify task dependencies",
            "Write failing tests first",
            "Implement minimum code to pass tests",
            "Refactor for quality",
            "Report completion status",
        ],
    },
}


def create_worker_agent(agent_name: str) -> tuple[DurableAgent, AgentRunner]:
    """Create a worker agent (specifier, planner, task-generator, implementer).

    Args:
        agent_name: Name of the agent to create

    Returns:
        Tuple of (DurableAgent, AgentRunner)

    Raises:
        ValueError: If agent_name is not a valid worker agent
    """
    if agent_name not in AGENT_CONFIGS:
        raise ValueError(
            f"Unknown worker agent: {agent_name}. "
            f"Available agents: {list(AGENT_CONFIGS.keys())}"
        )

    config = AGENT_CONFIGS[agent_name]
    return create_durable_agent(
        name=agent_name,
        role=config["role"],
        goal=config["goal"],
        instructions=config["instructions"],
    )


def create_orchestrator() -> tuple["LLMOrchestrator", AgentRunner]:
    """Create the orchestrator using LLMOrchestrator pattern.

    The orchestrator coordinates the workflow by routing tasks
    to appropriate agents based on the current phase.

    Returns:
        Tuple of (LLMOrchestrator, AgentRunner)
    """
    import dapr.ext.workflow as wf
    from dapr_agents.agents.configs import (
        AgentExecutionConfig,
        AgentPubSubConfig,
        AgentRegistryConfig,
        AgentStateConfig,
    )
    from dapr_agents.agents.orchestrators.llm import LLMOrchestrator
    from dapr_agents.llm.dapr import DaprChatClient
    from dapr_agents.storage.daprstores.stateservice import StateStoreService

    config = get_config()

    # Configure pub/sub for orchestrator
    pubsub = AgentPubSubConfig(
        pubsub_name=config.pubsub_name,
        agent_topic=f"{config.team_name}.orchestrator.requests",
        broadcast_topic=config.broadcast_topic,
    )

    # State store for workflow state
    state = AgentStateConfig(
        store=StateStoreService(
            store_name=config.workflow_state_store,
            key_prefix="orchestrator:",
        )
    )

    # Agent registry to track available agents
    registry = AgentRegistryConfig(
        store=StateStoreService(store_name=config.registry_state_store),
        team_name=config.team_name,
    )

    # Execution configuration
    execution = AgentExecutionConfig(
        max_iterations=4,  # One per workflow phase
    )

    # Create LLM client using Dapr conversation component (anthropic)
    # Uses Claude Opus 4.5 via the conversation.anthropic component
    llm = DaprChatClient(
        component_name="anthropic",
    )

    # Summary callback when workflow completes
    def on_summary(summary: str):
        logger.info(f"Workflow complete! Summary: {summary}")

    # Create the LLM Orchestrator with Dapr workflow runtime
    orchestrator = LLMOrchestrator(
        name="SpecKitOrchestrator",
        llm=llm,
        pubsub=pubsub,
        state=state,
        registry=registry,
        execution=execution,
        agent_metadata={
            "type": "LLMOrchestrator",
            "description": "SpecKit workflow orchestrator - routes tasks through specification, planning, task generation, and implementation phases",
        },
        timeout_seconds=120,  # 2 minutes per agent interaction
        runtime=wf.WorkflowRuntime(),
        final_summary_callback=on_summary,
    )

    # Create runner
    runner = AgentRunner()

    logger.info(f"Created LLMOrchestrator with topic {pubsub.agent_topic}")

    return orchestrator, runner


def create_app_with_health(agent_name: str) -> FastAPI:
    """Create a FastAPI app with health endpoints for Kubernetes probes.

    Args:
        agent_name: Name of the agent for health response

    Returns:
        FastAPI app with /healthz and /ready endpoints
    """
    app = FastAPI(
        title=f"SpecKit {agent_name} Agent",
        version="1.0.0",
    )

    @app.get("/healthz")
    async def health():
        """Liveness probe - returns healthy if server is running."""
        return {
            "status": "healthy",
            "agent": agent_name,
            "timestamp": datetime.utcnow().isoformat(),
        }

    @app.get("/ready")
    async def ready():
        """Readiness probe - returns ready if agent is ready to accept work."""
        return {
            "ready": True,
            "agent": agent_name,
            "timestamp": datetime.utcnow().isoformat(),
        }

    return app


def handle_signal(signum: int, frame) -> None:
    """Handle shutdown signals gracefully."""
    logger.info(f"Received signal {signum}, initiating shutdown...")
    sys.exit(0)


def add_health_endpoints(app, agent_name: str) -> None:
    """Add Kubernetes health probe endpoints to a FastAPI app.

    Args:
        app: FastAPI application instance
        agent_name: Name of the agent for health response
    """
    from fastapi import FastAPI
    from datetime import datetime

    @app.get("/healthz")
    async def health():
        """Liveness probe - returns healthy if server is running."""
        return {
            "status": "healthy",
            "agent": agent_name,
            "timestamp": datetime.utcnow().isoformat(),
        }

    @app.get("/ready")
    async def ready():
        """Readiness probe - returns ready if agent is ready to accept work."""
        return {
            "ready": True,
            "agent": agent_name,
            "timestamp": datetime.utcnow().isoformat(),
        }


def run_worker_agent(agent_name: str, port: int) -> None:
    """Run a worker agent with HTTP endpoints for Kubernetes compatibility.

    Uses runner.serve() which returns a FastAPI app with:
    - /run endpoint for workflow entry
    - /dapr/subscribe endpoint for pub/sub subscriptions
    - /dapr/config endpoint for Dapr configuration

    We add health endpoints to the same app for Kubernetes probes.
    """
    import uvicorn
    from fastapi import FastAPI

    agent, runner = create_worker_agent(agent_name)
    logger.info(f"Running DurableAgent: {agent_name}...")

    # Create base FastAPI app with health endpoints
    base_app = FastAPI(title=f"SpecKit {agent_name} Agent", version="1.0.0")
    add_health_endpoints(base_app, agent_name)

    # runner.serve() adds agent routes (/run, /dapr/subscribe, etc.) to our app
    # and returns the configured FastAPI app (does NOT start uvicorn)
    app = runner.serve(agent, app=base_app, port=port)

    try:
        # Start uvicorn with the fully configured app
        uvicorn.run(app, host="0.0.0.0", port=port)
    finally:
        # Graceful shutdown
        runner.shutdown()


def main() -> None:
    """Main entrypoint for SpecKit agents using dapr-agents SDK pattern.

    Follows the reference implementation from dapr-agents quickstart 05-multi-agent-workflows:
    - Orchestrator: runner.serve(orchestrator, port=PORT) - blocking call with uvicorn
    - Worker agents: runner.register_routes(agent) + wait_for_shutdown() - async pattern

    Key fix: Let runner.serve() handle everything (including uvicorn startup) instead of
    calling uvicorn.run() separately which was causing the double-startup issue.
    """
    # Register signal handlers
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    config = get_config()

    # Validate configuration
    errors = config.validate()
    if errors:
        logger.error(f"Configuration errors: {errors}")
        sys.exit(1)

    agent_name = config.agent_name
    port = config.agent_port

    logger.info(f"Starting SpecKit agent: {agent_name}")
    logger.info(f"Listening on port: {port}")
    logger.info(f"Team: {config.team_name}")
    logger.info(f"Topic: {config.agent_topic}")

    try:
        if agent_name == "orchestrator":
            # Create orchestrator using runner.serve() pattern
            import uvicorn
            from fastapi import FastAPI

            orchestrator, runner = create_orchestrator()
            logger.info("Running LLMOrchestrator...")

            # CRITICAL: Start the orchestrator's workflow runtime BEFORE serving
            # This registers workflows/activities with Dapr and starts the runtime
            # Without this, Dapr will report "DaprBuiltInActorNotFoundRetries"
            # because the workflow actors are never registered
            orchestrator.start()
            logger.info("Started orchestrator workflow runtime")

            # Create base FastAPI app with health endpoints
            base_app = FastAPI(title=f"SpecKit {agent_name} Agent", version="1.0.0")
            add_health_endpoints(base_app, agent_name)

            # runner.serve() adds orchestrator routes (/run, /dapr/subscribe, etc.)
            # and returns the configured FastAPI app (does NOT start uvicorn)
            app = runner.serve(orchestrator, app=base_app, port=port)

            try:
                # Start uvicorn with the fully configured app
                uvicorn.run(app, host="0.0.0.0", port=port)
            finally:
                runner.shutdown()
        else:
            # Run worker agent using serve() pattern for Kubernetes health probes
            # All agents need HTTP endpoints for liveness/readiness probes
            run_worker_agent(agent_name, port)

    except Exception as e:
        logger.error(f"Failed to start agent {agent_name}: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
