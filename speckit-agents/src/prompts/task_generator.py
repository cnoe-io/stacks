"""Prompts and templates for the Task Generator agent.

The Task Generator converts planning artifacts into structured,
dependency-ordered task lists in tasks.md format.
"""

from __future__ import annotations

# System prompt for the Task Generator agent
TASK_GENERATOR_SYSTEM_PROMPT = """You are the SpecKit Task Generator Agent, an expert at converting implementation plans into actionable, dependency-ordered task lists.

## Your Role
You transform plan.md documents into structured tasks.md files that developers can execute sequentially to implement features.

## Guidelines

### 1. Dependency Ordering
Tasks must be ordered so dependencies are resolved before dependent tasks.
- Setup tasks come first
- Core models before services
- Services before APIs
- APIs before integration tests

### 2. Parallelism
Mark tasks that can run in parallel with [P] when they:
- Modify different files
- Have no shared dependencies
- Can be executed concurrently

### 3. Specificity
Each task must:
- Reference specific file paths
- Be actionable (clear what to do)
- Have testable completion criteria

### 4. Phase Organization
Group tasks into logical phases:
- **Setup**: Environment and configuration
- **Tests**: Test files (TDD - tests before implementation)
- **Core**: Core implementation files
- **Integration**: Integration and wiring
- **Polish**: Documentation and cleanup

### 5. User Story Mapping
Tag tasks with [US#] to trace back to user stories from spec.md.

## Task Format
Each task follows this format:
```
- [ ] T### [P?] [US#] Description in path/to/file.ext
```

Where:
- T###: Sequential identifier (T001, T002, etc.)
- [P]: Optional - indicates task can run in parallel
- [US#]: User story reference
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

**Input**: Design documents from `{spec_path}`
**Prerequisites**: plan.md (required), spec.md (required)

**Organization**: Tasks grouped by phase and user story for systematic implementation.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to
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

## Data Model Summary
{data_model_summary}

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


def format_tasks_prompt(
    plan_content: str,
    spec_summary: str = "",
    data_model_summary: str = "",
) -> str:
    """Format the tasks generation prompt.

    Args:
        plan_content: Content of plan.md
        spec_summary: Optional summary from spec.md
        data_model_summary: Optional summary from data-model.md

    Returns:
        Formatted prompt string for the LLM
    """
    return GENERATE_TASKS_PROMPT.format(
        plan_content=plan_content,
        spec_summary=spec_summary or "See plan.md for specification context.",
        data_model_summary=data_model_summary or "See data-model.md for entity definitions.",
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
        List of task dictionaries with id, completed, is_parallel,
        user_story, description, and file_path fields
    """
    import re

    tasks = []
    # Match task lines: - [ ] T### [P?] [US#] Description
    # or: - [X] T### [P?] [US#] Description
    pattern = r"-\s*\[([ Xx])\]\s*(T\d+)\s*(\[P\])?\s*(\[US\d+\])?\s*(.+)"

    for line in content.split("\n"):
        match = re.match(pattern, line.strip())
        if match:
            completed = match.group(1).upper() == "X"
            task_id = match.group(2)
            is_parallel = match.group(3) is not None
            user_story = match.group(4).strip("[]") if match.group(4) else None
            description = match.group(5).strip()

            # Extract file path if present (usually at the end after "in")
            file_path = None
            if " in " in description:
                parts = description.rsplit(" in ", 1)
                if len(parts) == 2 and "/" in parts[1]:
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


def mark_task_complete(content: str, task_id: str) -> str:
    """Mark a task as complete in tasks.md content.

    Args:
        content: tasks.md content
        task_id: Task ID to mark complete (e.g., "T001")

    Returns:
        Updated content with task marked as [X]
    """
    import re

    # Match the task line and replace [ ] with [X]
    pattern = rf"(-\s*)\[ \](\s*{task_id}\s)"
    replacement = r"\1[X]\2"

    return re.sub(pattern, replacement, content)


def get_incomplete_tasks(content: str) -> list[dict]:
    """Get list of incomplete tasks from tasks.md.

    Args:
        content: tasks.md content

    Returns:
        List of incomplete task dictionaries
    """
    all_tasks = parse_tasks(content)
    return [t for t in all_tasks if not t["completed"]]


def get_next_task(content: str) -> dict | None:
    """Get the next incomplete task respecting dependencies.

    Args:
        content: tasks.md content

    Returns:
        Next task to execute or None if all complete
    """
    incomplete = get_incomplete_tasks(content)
    if incomplete:
        return incomplete[0]
    return None
