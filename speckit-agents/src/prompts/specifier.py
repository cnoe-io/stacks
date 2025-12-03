"""Prompts and templates for the Specifier agent."""

from __future__ import annotations

# System prompt for the Specifier agent
SPECIFIER_SYSTEM_PROMPT = """You are the SpecKit Specifier Agent, an expert at transforming natural language feature descriptions into structured, actionable specifications.

## Your Role
You convert vague feature requests into clear, comprehensive specification documents that development teams can implement confidently.

## Guidelines
1. **Clarify Ambiguity**: Identify underspecified areas and make reasonable assumptions. Document all assumptions explicitly.
2. **User-Centric**: Frame requirements in terms of user stories with clear acceptance criteria.
3. **Scope Definition**: Clearly distinguish what IS and IS NOT in scope for this feature.
4. **Technical Constraints**: Note any technical constraints or dependencies mentioned or implied.
5. **Testability**: Ensure every requirement is verifiable with clear success criteria.

## Output Format
Always produce a spec.md document following the template structure exactly.
Use markdown formatting consistently.
Number user stories sequentially (US1, US2, etc.).
Include acceptance criteria for each user story.

## Quality Checklist
Before finalizing, verify:
- [ ] All user stories have clear acceptance criteria
- [ ] Scope is explicitly defined (in/out)
- [ ] Assumptions are documented
- [ ] Non-functional requirements are addressed
- [ ] Success metrics are measurable
"""

# Template for spec.md generation
SPEC_TEMPLATE = """# Feature Specification: {feature_title}

**Version**: 1.0
**Created**: {created_date}
**Status**: Draft

## Overview

{overview}

## User Stories

{user_stories}

## Scope

### In Scope
{in_scope}

### Out of Scope
{out_of_scope}

## Assumptions
{assumptions}

## Technical Constraints
{technical_constraints}

## Non-Functional Requirements
{non_functional_requirements}

## Success Metrics
{success_metrics}

## Dependencies
{dependencies}

## Risks
{risks}
"""

# Prompt for generating spec.md from feature description
GENERATE_SPEC_PROMPT = """Analyze the following feature description and generate a comprehensive spec.md document.

## Feature Description
{feature_description}

## Instructions
1. Extract the core feature purpose and value proposition
2. Identify all user-facing capabilities as user stories
3. Define clear acceptance criteria for each story
4. Determine what's in and out of scope
5. Document any assumptions you make
6. Note technical constraints and dependencies
7. Define measurable success metrics

## Output Requirements
- Use the spec.md template format exactly
- Number user stories as US1, US2, etc.
- Each user story must have 2-5 acceptance criteria
- Be specific and avoid vague language
- Include at least one non-functional requirement
- Identify at least one potential risk

Generate the complete spec.md content now:
"""

# User story template
USER_STORY_TEMPLATE = """### {story_id}: {story_title}

**As a** {actor}
**I want to** {action}
**So that** {benefit}

**Acceptance Criteria**:
{acceptance_criteria}

**Priority**: {priority}
"""


def format_spec_prompt(feature_description: str) -> str:
    """Format the spec generation prompt with the feature description.

    Args:
        feature_description: Natural language description of the feature

    Returns:
        Formatted prompt string for the LLM
    """
    return GENERATE_SPEC_PROMPT.format(feature_description=feature_description)


def get_system_prompt() -> str:
    """Get the system prompt for the Specifier agent.

    Returns:
        System prompt string
    """
    return SPECIFIER_SYSTEM_PROMPT
