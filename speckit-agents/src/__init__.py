"""SpecKit Agents - Claude Agent SDK with Dapr Orchestration.

This package implements a multi-agent workflow system where:
- Claude Agent SDK powers all LLM-based agents (specifier, planner, task-generator, implementer)
- Dapr provides distributed systems infrastructure (pub/sub, state store, durability)
- Custom MCP tools bridge Claude agents to Dapr infrastructure
"""

__version__ = "2.0.0"
