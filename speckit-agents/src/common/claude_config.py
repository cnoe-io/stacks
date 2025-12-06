"""Claude SDK configuration and options factory for SpecKit agents."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .config import get_settings


@dataclass
class SubagentConfig:
    """Configuration for a parallel subagent."""

    description: str
    prompt: str
    tools: list[str] = field(default_factory=list)
    model: str = "sonnet"


@dataclass
class AgentConfig:
    """Configuration for a SpecKit agent using Claude SDK."""

    name: str
    role: str
    system_prompt: str
    max_turns: int = 5
    model: str = "claude-sonnet-4-20250514"
    allowed_tools: list[str] = field(default_factory=list)
    mcp_servers: dict[str, Any] = field(default_factory=dict)
    subagents: dict[str, SubagentConfig] = field(default_factory=dict)


def build_claude_options(
    agent_config: AgentConfig,
    additional_tools: list[str] | None = None,
    override_model: str | None = None,
    override_max_turns: int | None = None,
) -> dict[str, Any]:
    """Build Claude SDK options dictionary from AgentConfig.

    Args:
        agent_config: Agent configuration
        additional_tools: Extra tools to add to allowed_tools
        override_model: Override the default model
        override_max_turns: Override the default max_turns

    Returns:
        Dictionary suitable for ClaudeAgentOptions
    """
    settings = get_settings()

    tools = list(agent_config.allowed_tools)
    if additional_tools:
        tools.extend(additional_tools)

    model = override_model or agent_config.model or settings.claude_model
    max_turns = override_max_turns or agent_config.max_turns or settings.claude_max_turns

    options: dict[str, Any] = {
        "system_prompt": agent_config.system_prompt,
        "max_turns": max_turns,
        "model": model,
    }

    if tools:
        options["allowed_tools"] = tools

    if agent_config.mcp_servers:
        options["mcp_servers"] = agent_config.mcp_servers

    if agent_config.subagents:
        options["agents"] = {
            name: {
                "description": cfg.description,
                "prompt": cfg.prompt,
                "tools": cfg.tools,
                "model": cfg.model,
            }
            for name, cfg in agent_config.subagents.items()
        }

    return options


# Pre-defined agent configurations from data-model.md

SPECIFIER_CONFIG = AgentConfig(
    name="specifier",
    role="Specification Writer",
    system_prompt="""You are a specification writer. Transform feature descriptions into structured spec.md documents.

Output format: Markdown specification with sections:
- User Scenarios & Testing (user stories with acceptance criteria)
- Requirements (functional requirements)
- Success Criteria (measurable outcomes)

Use the Write tool to save the specification to the workflow artifacts directory.""",
    max_turns=3,
    model="claude-sonnet-4-20250514",
    allowed_tools=["Read", "Write", "mcp__dapr__get_workflow_state"],
)


PLANNER_CONFIG = AgentConfig(
    name="planner",
    role="Implementation Planner",
    system_prompt="""You are a planning orchestrator. Based on the specification, generate:
1. research.md - Technology research and decisions
2. data-model.md - Entity definitions and relationships
3. plan.md - Implementation approach and file structure

Delegate specialized work to subagents for parallel execution.""",
    max_turns=10,
    model="claude-sonnet-4-20250514",
    allowed_tools=["Read", "Write", "Glob", "mcp__dapr__get_artifact"],
    subagents={
        "research-agent": SubagentConfig(
            description="Research technology choices and best practices",
            prompt="You are a technology researcher. Analyze requirements and recommend technologies.",
            tools=["WebSearch", "Read"],
            model="haiku",
        ),
        "data-modeler": SubagentConfig(
            description="Design data models and entity relationships",
            prompt="You are a data modeling expert. Define entities, fields, and relationships.",
            tools=["Read", "Write"],
            model="sonnet",
        ),
        "architecture-agent": SubagentConfig(
            description="Design system architecture and implementation approach",
            prompt="You are a software architect. Create implementation plans with file structure.",
            tools=["Read", "Write", "Glob"],
            model="sonnet",
        ),
    },
)


TASK_GENERATOR_CONFIG = AgentConfig(
    name="task-generator",
    role="Task Breakdown Specialist",
    system_prompt="""You are a task breakdown specialist. Convert implementation plans into ordered tasks.

Output: tasks.md with phases:
- Setup: Environment and configuration
- Tests: Test files (TDD - tests before implementation)
- Core: Core implementation files
- Integration: Integration and wiring
- Polish: Documentation and cleanup

Mark parallel-safe tasks with [P]. Include file paths for each task.""",
    max_turns=5,
    model="claude-sonnet-4-20250514",
    allowed_tools=["Read", "Write", "mcp__dapr__get_artifact"],
)


IMPLEMENTER_CONFIG = AgentConfig(
    name="implementer",
    role="Task Implementer",
    system_prompt="""You are a TDD implementation agent. For each task in tasks.md:
1. Write tests first (use mcp__tests__run_tests to verify they fail)
2. Implement the code to make tests pass
3. Run tests to verify success
4. Refactor if needed
5. Mark task complete in tasks.md

Use Edit for precise file modifications. Use Bash for commands.""",
    max_turns=50,  # Many iterations for TDD workflow
    model="claude-sonnet-4-20250514",
    allowed_tools=[
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Glob",
        "Grep",
        "mcp__dapr__get_artifact",
        "mcp__dapr__save_workflow_state",
        "mcp__tests__run_tests",
    ],
)


# Agent configuration registry
AGENT_CONFIGS: dict[str, AgentConfig] = {
    "specifier": SPECIFIER_CONFIG,
    "planner": PLANNER_CONFIG,
    "task-generator": TASK_GENERATOR_CONFIG,
    "implementer": IMPLEMENTER_CONFIG,
}


def get_agent_config(agent_name: str) -> AgentConfig:
    """Get configuration for a specific agent."""
    if agent_name not in AGENT_CONFIGS:
        raise ValueError(f"Unknown agent: {agent_name}. Available: {list(AGENT_CONFIGS.keys())}")
    return AGENT_CONFIGS[agent_name]
