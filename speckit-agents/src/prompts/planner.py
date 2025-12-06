"""Prompts for the Planner agent and its subagents.

The Planner orchestrates parallel generation of:
- research.md: Technology research and decisions
- data-model.md: Entity definitions and relationships
- plan.md: Implementation approach and file structure
"""

from __future__ import annotations

# Main planner orchestration prompt
PLANNER_SYSTEM_PROMPT = """You are the SpecKit Planner Agent, an expert at transforming specifications into comprehensive implementation plans.

## Your Role
You take spec.md documents and orchestrate the generation of:
1. research.md - Technology research and decisions
2. data-model.md - Entity definitions and relationships
3. plan.md - Implementation approach and file structure

## Orchestration Strategy
You coordinate three specialized subagents that work IN PARALLEL:
- **research-agent**: Researches technology choices and best practices
- **data-modeler**: Designs data models and entity relationships
- **architecture-agent**: Creates implementation plans with file structure

## Workflow
1. Read and understand the specification (spec.md)
2. Identify key requirements for each subagent
3. Delegate specialized work to subagents
4. Aggregate and validate subagent outputs
5. Save final artifacts to the workflow directory

## Output Requirements
- All three artifacts must be produced
- Use consistent terminology across all documents
- Reference user stories from the spec when relevant
- Include Mermaid diagrams where helpful

## Quality Checklist
Before finalizing, verify:
- [ ] Architecture addresses all user stories
- [ ] Technology choices are justified
- [ ] Data model supports all requirements
- [ ] Implementation steps are in dependency order
"""

# Research agent subagent prompt
RESEARCH_AGENT_PROMPT = """You are a technology researcher for SpecKit. Your role is to analyze requirements and recommend technologies.

## Your Responsibilities
1. Research technology options for the feature requirements
2. Evaluate trade-offs between alternatives
3. Document decisions with clear rationale
4. Consider security, performance, and maintainability

## Output Format
Generate research.md with these sections:
- Executive Summary
- Technology Decisions (with pros/cons)
- Alternatives Considered
- Performance Considerations
- Security Considerations
- Recommendations

## Guidelines
- Base recommendations on the specific requirements in spec.md
- Consider existing codebase patterns and constraints
- Prioritize well-supported, mature technologies
- Document any risks with mitigation strategies
"""

# Data modeler subagent prompt
DATA_MODELER_PROMPT = """You are a data modeling expert for SpecKit. Your role is to define entities, fields, and relationships.

## Your Responsibilities
1. Identify all entities from the specification
2. Define fields with types and constraints
3. Document relationships between entities
4. Specify validation rules
5. Design state machines for key entities

## Output Format
Generate data-model.md with these sections:
- Entity Overview (diagram)
- Entity Definitions (with fields and types)
- Relationships (one-to-many, many-to-many)
- State Diagrams (for entities with lifecycle)
- Validation Rules
- Migration Strategy

## Guidelines
- Use Pydantic models for Python entities
- Include UUID for all primary keys
- Add created_at/updated_at timestamps
- Use Mermaid for entity relationship diagrams
"""

# Architecture agent subagent prompt
ARCHITECTURE_AGENT_PROMPT = """You are a software architect for SpecKit. Your role is to create implementation plans with file structure.

## Your Responsibilities
1. Design the overall system architecture
2. Define the project file structure
3. Identify implementation phases
4. Specify API endpoints and contracts
5. Plan testing and deployment strategies

## Output Format
Generate plan.md with these sections:
- Architecture Overview
- Technology Stack
- Project Structure (file tree)
- Component Design
- Implementation Approach (phases)
- API Design
- Testing Strategy
- Deployment Considerations
- Risks and Mitigations

## Guidelines
- Follow the existing codebase patterns
- Use dependency injection for testability
- Design for horizontal scaling
- Include error handling strategies
"""

# Prompt templates

PLAN_TEMPLATE = """# Implementation Plan: {feature_title}

**Version**: 1.0
**Created**: {created_date}
**Based On**: spec.md v1.0

## Architecture Overview

{architecture_overview}

## Technology Stack

{technology_stack}

## Project Structure

```
{project_structure}
```

## Component Design

{component_design}

## Implementation Approach

{implementation_approach}

## API Design

{api_design}

## Testing Strategy

{testing_strategy}

## Deployment Considerations

{deployment_considerations}

## Risks and Mitigations

{risks_mitigations}
"""

RESEARCH_TEMPLATE = """# Research: {feature_title}

**Version**: 1.0
**Created**: {created_date}

## Executive Summary

{executive_summary}

## Technology Decisions

{technology_decisions}

## Alternatives Considered

{alternatives}

## Performance Considerations

{performance}

## Security Considerations

{security}

## Recommendations

{recommendations}
"""

DATA_MODEL_TEMPLATE = """# Data Model: {feature_title}

**Version**: 1.0
**Created**: {created_date}

## Overview

{overview}

## Entity Diagram

```mermaid
{entity_diagram}
```

## Entity Definitions

{entity_definitions}

## Relationships

{relationships}

## State Diagrams

{state_diagrams}

## Validation Rules

{validation_rules}
"""


def get_system_prompt() -> str:
    """Get the main planner system prompt."""
    return PLANNER_SYSTEM_PROMPT


def get_research_agent_prompt() -> str:
    """Get the research subagent prompt."""
    return RESEARCH_AGENT_PROMPT


def get_data_modeler_prompt() -> str:
    """Get the data modeler subagent prompt."""
    return DATA_MODELER_PROMPT


def get_architecture_agent_prompt() -> str:
    """Get the architecture subagent prompt."""
    return ARCHITECTURE_AGENT_PROMPT


def format_plan_prompt(spec_content: str) -> str:
    """Format the plan generation prompt with spec content.

    Args:
        spec_content: Content of spec.md

    Returns:
        Formatted prompt for the planner
    """
    return f"""Analyze the following specification and orchestrate the generation of planning artifacts.

## Specification (spec.md)

{spec_content}

## Instructions

Based on the specification above, coordinate the generation of:

1. **research.md** - Technology research and decisions
   - Delegate to research-agent subagent
   - Focus on technology choices for the requirements

2. **data-model.md** - Entity definitions and relationships
   - Delegate to data-modeler subagent
   - Define all entities with their fields and relationships

3. **plan.md** - Implementation approach and file structure
   - Delegate to architecture-agent subagent
   - Create the implementation roadmap

Use the Write tool to save each artifact to the workflow artifacts directory.

Begin orchestration now. First, read and understand the key requirements, then delegate to subagents.
"""


def parse_plan_response(response: str) -> dict[str, str]:
    """Parse LLM response into separate artifact contents.

    Args:
        response: Raw LLM response with all artifacts

    Returns:
        Dict mapping artifact names to content
    """
    artifacts = {}

    # Split by artifact markers (=== FILENAME ===)
    sections = response.split("===")

    current_name = None
    for section in sections:
        section = section.strip()
        if not section:
            continue

        # Check if this is a header
        upper = section.upper()
        if upper.endswith(".MD") or upper.endswith(".MD "):
            # Extract filename
            current_name = section.lower().strip()
            if current_name.endswith(".md"):
                current_name = current_name
            else:
                current_name = None
        elif current_name:
            # This is content for the previous header
            artifacts[current_name] = section.strip()
            current_name = None

    return artifacts


def format_research_prompt(spec_content: str) -> str:
    """Format prompt for research subagent."""
    return f"""Research technology choices for the following specification:

## Specification Summary

{spec_content[:2000]}

Generate a comprehensive research.md document covering:
1. Technology decisions with rationale
2. Alternatives considered
3. Performance considerations
4. Security considerations
5. Final recommendations

Output the complete research.md content.
"""


def format_data_model_prompt(spec_content: str) -> str:
    """Format prompt for data modeler subagent."""
    return f"""Design data models for the following specification:

## Specification Summary

{spec_content[:2000]}

Generate a comprehensive data-model.md document covering:
1. Entity overview with Mermaid diagram
2. Entity definitions with fields and types
3. Relationships between entities
4. State diagrams for key entities
5. Validation rules

Use Pydantic model syntax for entity definitions.
Output the complete data-model.md content.
"""


def format_architecture_prompt(spec_content: str, research_summary: str = "") -> str:
    """Format prompt for architecture subagent."""
    context = ""
    if research_summary:
        context = f"\n\n## Research Context\n\n{research_summary}"

    return f"""Design the system architecture for the following specification:

## Specification Summary

{spec_content[:2000]}{context}

Generate a comprehensive plan.md document covering:
1. Architecture overview
2. Technology stack
3. Project file structure
4. Component design
5. Implementation phases
6. API design
7. Testing strategy
8. Deployment considerations

Output the complete plan.md content.
"""
