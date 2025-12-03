"""Prompts and templates for the Planner agent."""

from __future__ import annotations

# System prompt for the Planner agent
PLANNER_SYSTEM_PROMPT = """You are the SpecKit Planner Agent, an expert at transforming specifications into comprehensive implementation plans.

## Your Role
You take spec.md documents and produce detailed technical plans including:
- plan.md: Implementation approach and architecture
- research.md: Technology decisions and rationale
- data-model.md: Entity definitions and relationships

## Guidelines
1. **Architecture First**: Define the high-level architecture before diving into details.
2. **Technology Choices**: Research and justify technology decisions with pros/cons.
3. **Data Modeling**: Define clear entity relationships with proper normalization.
4. **Implementation Path**: Create a logical sequence of implementation steps.
5. **Risk Assessment**: Identify technical risks and mitigation strategies.

## Output Requirements
- Produce all three artifacts (plan.md, research.md, data-model.md)
- Use consistent naming conventions across all documents
- Reference user stories from the spec when relevant
- Include diagrams using Mermaid syntax where helpful

## Quality Checklist
Before finalizing, verify:
- [ ] Architecture addresses all user stories
- [ ] Technology choices are justified
- [ ] Data model supports all requirements
- [ ] Implementation steps are in dependency order
- [ ] Risks have mitigation strategies
"""

# Plan.md template
PLAN_TEMPLATE = """# Implementation Plan: {feature_title}

**Version**: 1.0
**Created**: {created_date}
**Based On**: spec.md v1.0

## Architecture Overview

{architecture_overview}

## Technology Stack

{technology_stack}

## Component Design

{component_design}

## Implementation Approach

{implementation_approach}

## API Design

{api_design}

## Integration Points

{integration_points}

## Testing Strategy

{testing_strategy}

## Deployment Considerations

{deployment_considerations}

## Risks and Mitigations

{risks_mitigations}

## Open Questions

{open_questions}
"""

# Research.md template
RESEARCH_TEMPLATE = """# Research: {feature_title}

**Version**: 1.0
**Created**: {created_date}

## Executive Summary

{executive_summary}

## Technology Decisions

{technology_decisions}

## Alternatives Considered

{alternatives}

## Proof of Concept Results

{poc_results}

## Performance Considerations

{performance}

## Security Considerations

{security}

## Recommendations

{recommendations}

## References

{references}
"""

# Data-model.md template
DATA_MODEL_TEMPLATE = """# Data Model: {feature_title}

**Version**: 1.0
**Created**: {created_date}

## Overview

{overview}

## Entity Definitions

{entity_definitions}

## Relationships

{relationships}

## Entity Diagram

```mermaid
{entity_diagram}
```

## State Diagrams

{state_diagrams}

## Data Validation Rules

{validation_rules}

## Migration Strategy

{migration_strategy}
"""

# Prompt for generating plan artifacts
GENERATE_PLAN_PROMPT = """Analyze the following specification and generate comprehensive planning artifacts.

## Specification (spec.md)
{spec_content}

## Instructions
Based on the specification, generate THREE artifacts:

### 1. plan.md
- Define the high-level architecture
- List the technology stack with justifications
- Design components and their interactions
- Outline the implementation approach in phases
- Define the API design
- Include testing and deployment strategies

### 2. research.md
- Document technology decisions and rationale
- Compare alternatives that were considered
- Note performance and security considerations
- Provide recommendations

### 3. data-model.md
- Define all entities with their properties
- Document relationships between entities
- Include a Mermaid entity diagram
- Define state machines for key entities
- Specify validation rules

## Output Format
Return the content for each artifact, clearly separated with headers:

=== PLAN.MD ===
[plan content here]

=== RESEARCH.MD ===
[research content here]

=== DATA-MODEL.MD ===
[data model content here]

Generate the complete content now:
"""


def format_plan_prompt(spec_content: str) -> str:
    """Format the plan generation prompt with the spec content.

    Args:
        spec_content: Content of spec.md

    Returns:
        Formatted prompt string for the LLM
    """
    return GENERATE_PLAN_PROMPT.format(spec_content=spec_content)


def get_system_prompt() -> str:
    """Get the system prompt for the Planner agent.

    Returns:
        System prompt string
    """
    return PLANNER_SYSTEM_PROMPT


def parse_plan_response(response: str) -> dict[str, str]:
    """Parse the LLM response into separate artifact contents.

    Args:
        response: Raw LLM response with all artifacts

    Returns:
        Dict mapping artifact names to content
    """
    artifacts = {}

    # Split by artifact markers
    sections = response.split("===")

    current_name = None
    for section in sections:
        section = section.strip()
        if not section:
            continue

        if section.upper().endswith(".MD ===") or section.upper().endswith(".MD"):
            # This is a header
            current_name = section.lower().replace(" ===", "").replace("===", "").strip()
        elif current_name:
            # This is content
            artifacts[current_name] = section.strip()
            current_name = None

    return artifacts
