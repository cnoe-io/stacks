"""Prompts and templates for the Task Generator agent."""

from __future__ import annotations

# System prompt for the Task Generator agent
TASK_GENERATOR_SYSTEM_PROMPT = """You are the SpecKit Task Generator Agent, an expert at converting implementation plans into actionable, dependency-ordered task lists.

## Your Role
You transform plan.md documents into structured tasks.md files that developers can execute sequentially to implement features.

## Guidelines
1. **Dependency Ordering**: Tasks must be ordered so dependencies are resolved before dependent tasks.
2. **Parallelism**: Mark tasks that can run in parallel with [P] when they modify different files.
3. **Specificity**: Each task must reference specific file paths and be actionable.
4. **Phase Organization**: Group tasks into logical phases (Setup, Core, Tests, Integration, Polish).
5. **User Story Mapping**: Tag tasks with [US#] to trace back to user stories.

## Task Format
Each task follows this format:
- [ID] [P?] [Story] Description in speckit-agents/path/to/file.py

Where:
- ID: Sequential identifier (T001, T002, etc.)
- [P]: Optional - indicates task can run in parallel with others
- [Story]: User story reference (US1, US2, etc.)
- Description: Clear, actionable task description
- Path: Exact file path to create or modify

## Quality Checklist
Before finalizing, verify:
- [ ] All tasks have unique IDs
- [ ] Dependencies are respected in ordering
- [ ] Parallel tasks truly can run concurrently
- [ ] Each task maps to a user story
- [ ] File paths are specific and accurate
"""

# Tasks.md template
TASKS_TEMPLATE = """# Tasks: {feature_title}

**Input**: Design documents from `/specs/{feature_id}/`
**Prerequisites**: plan.md (required), spec.md (required)

**Organization**: Tasks are grouped by phase and user story for systematic implementation.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

---

{task_phases}

---

## Dependencies & Execution Order

{dependencies}

---

## Notes

{notes}

---

## Summary

{summary}
"""

# Prompt for generating tasks.md
GENERATE_TASKS_PROMPT = """Analyze the following implementation plan and generate a comprehensive tasks.md file.

## Plan (plan.md)
{plan_content}

## Specification Summary
{spec_summary}

## Instructions
Generate a tasks.md file with:

1. **Phase-organized tasks**: Group into Setup, Core, Tests, Integration, Polish
2. **Dependency ordering**: Tasks must be executable in order
3. **Parallel markers**: Mark [P] for tasks that can run concurrently
4. **User story tags**: Tag each task with [US#] for traceability
5. **Specific file paths**: Include exact paths for each task
6. **Checkboxes**: Use [ ] for pending, [X] for completed

## Output Format
Return a complete tasks.md following the template structure.

Each task line must follow:
- [ ] T### [P?] [US#] Description in path/to/file.ext

Generate the complete tasks.md content now:
"""


def format_tasks_prompt(plan_content: str, spec_summary: str = "") -> str:
    """Format the tasks generation prompt.

    Args:
        plan_content: Content of plan.md
        spec_summary: Optional summary from spec.md

    Returns:
        Formatted prompt string for the LLM
    """
    return GENERATE_TASKS_PROMPT.format(
        plan_content=plan_content,
        spec_summary=spec_summary or "See plan.md for full specification context.",
    )


def get_system_prompt() -> str:
    """Get the system prompt for the Task Generator agent.

    Returns:
        System prompt string
    """
    return TASK_GENERATOR_SYSTEM_PROMPT


def parse_tasks(content: str) -> list[dict]:
    """Parse tasks.md content into structured task objects.

    Args:
        content: Raw tasks.md content

    Returns:
        List of task dictionaries
    """
    import re

    tasks = []
    # Match task lines: - [ ] T### [P?] [US#] Description
    # or: - [X] T### [P?] [US#] Description
    pattern = r"-\s*\[([ X])\]\s*(T\d+)\s*(\[P\])?\s*(\[US\d+\])?\s*(.+)"

    for line in content.split("\n"):
        match = re.match(pattern, line.strip())
        if match:
            completed = match.group(1) == "X"
            task_id = match.group(2)
            is_parallel = match.group(3) is not None
            user_story = match.group(4).strip("[]") if match.group(4) else None
            description = match.group(5).strip()

            # Extract file path if present (usually at the end after "in")
            file_path = None
            if " in " in description:
                parts = description.rsplit(" in ", 1)
                if len(parts) == 2:
                    description = parts[0]
                    file_path = parts[1]

            tasks.append({
                "id": task_id,
                "completed": completed,
                "is_parallel": is_parallel,
                "user_story": user_story,
                "description": description,
                "file_path": file_path,
            })

    return tasks
