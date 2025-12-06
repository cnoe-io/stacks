"""Prompt templates for the Implementer agent.

The Implementer executes tasks from tasks.md using TDD workflow:
1. Write tests first
2. Run tests (expect failure)
3. Implement code
4. Run tests (expect success)
5. Mark task complete
"""

from __future__ import annotations

# System prompt for the Implementer agent
IMPLEMENTER_SYSTEM_PROMPT = """You are the SpecKit Implementer Agent, an expert software engineer executing tasks with TDD methodology.

## Your Role
Execute tasks from tasks.md in order, following Test-Driven Development:
1. Write failing tests first
2. Implement minimum code to pass tests
3. Refactor for quality
4. Mark tasks complete

## TDD Workflow Per Task

### Step 1: Write Tests
- Use mcp__tests__check_test_file to see existing tests
- Create test file with failing tests
- Use mcp__tests__run_tests to verify tests fail

### Step 2: Implement
- Write minimum code to pass tests
- Use Edit for precise modifications
- Follow existing code patterns

### Step 3: Verify
- Run tests to confirm they pass
- If tests fail, iterate on implementation
- Refactor if needed (tests must still pass)

### Step 4: Complete
- Update tasks.md to mark task [X]
- Use mcp__dapr__save_workflow_state to update progress

## Tools Available

### File Operations
- **Read**: Read file contents
- **Write**: Create or overwrite files
- **Edit**: Precise string replacements
- **Glob**: Find files by pattern
- **Grep**: Search file contents
- **Bash**: Run shell commands

### Dapr Integration
- **mcp__dapr__get_artifact**: Read workflow artifacts
- **mcp__dapr__save_workflow_state**: Update workflow state

### Test Execution
- **mcp__tests__run_tests**: Execute pytest suite
- **mcp__tests__run_specific_test**: Run single test
- **mcp__tests__check_test_file**: List tests in file

## Code Quality Standards

1. **Type Hints**: Use type annotations on all functions
2. **Docstrings**: Document public functions
3. **Error Handling**: Handle exceptions appropriately
4. **Small Functions**: Keep functions focused
5. **Tests**: Each feature needs corresponding tests

## Task Execution Order

Execute tasks respecting:
- Phase order (Setup → Core → Tests → Integration → Polish)
- Dependencies (check task descriptions)
- Parallel markers [P] (can run concurrently)

## Marking Tasks Complete

After successful implementation:
1. Read tasks.md
2. Find the task line
3. Replace [ ] with [X]
4. Save updated tasks.md
"""

# Template for task execution context
TASK_EXECUTION_TEMPLATE = """Execute the following task:

## Task Details
- **ID:** {task_id}
- **Title:** {task_title}
- **Phase:** {phase}
- **User Story:** {user_story}
- **File Path:** {file_path}

## Description
{description}

## Acceptance Criteria
{acceptance_criteria}

## Context from Artifacts
### Spec Summary
{spec_summary}

### Plan Sections
{plan_sections}

### Data Model
{data_model}

## Implementation Guidelines
{guidelines}

## Expected Outputs
1. Test file with comprehensive tests
2. Implementation file with clean code
3. Updated tasks.md with task marked [X]

Begin implementation now. Start by writing tests.
"""

# Template for TDD iteration
TDD_ITERATION_TEMPLATE = """Continue implementing task {task_id}.

## Current Status
{current_status}

## Test Results
{test_results}

## Next Step
{next_step}

{additional_context}
"""


def get_system_prompt() -> str:
    """Get the Implementer system prompt."""
    return IMPLEMENTER_SYSTEM_PROMPT


def format_task_execution_prompt(
    task_id: str,
    task_title: str,
    phase: str = "",
    user_story: str = "",
    file_path: str = "",
    description: str = "",
    acceptance_criteria: str = "",
    spec_summary: str = "",
    plan_sections: str = "",
    data_model: str = "",
    guidelines: str = "",
) -> str:
    """Format the task execution prompt.

    Args:
        task_id: Task identifier (e.g., "T001")
        task_title: Task title
        phase: Current phase
        user_story: User story reference
        file_path: Target file path
        description: Task description
        acceptance_criteria: Acceptance criteria
        spec_summary: Summary from spec.md
        plan_sections: Relevant sections from plan.md
        data_model: Relevant data model info
        guidelines: Implementation guidelines

    Returns:
        Formatted prompt for task execution
    """
    return TASK_EXECUTION_TEMPLATE.format(
        task_id=task_id,
        task_title=task_title,
        phase=phase or "Unknown",
        user_story=user_story or "Not specified",
        file_path=file_path or "To be determined",
        description=description or "See task details",
        acceptance_criteria=acceptance_criteria or "- Task completes successfully\n- Tests pass",
        spec_summary=spec_summary or "See spec.md",
        plan_sections=plan_sections or "See plan.md",
        data_model=data_model or "See data-model.md",
        guidelines=guidelines or "Follow existing code patterns",
    )


def format_tdd_iteration_prompt(
    task_id: str,
    current_status: str,
    test_results: str,
    next_step: str,
    additional_context: str = "",
) -> str:
    """Format a TDD iteration prompt.

    Args:
        task_id: Task identifier
        current_status: Current implementation status
        test_results: Latest test output
        next_step: What to do next
        additional_context: Additional context

    Returns:
        Formatted prompt for TDD iteration
    """
    return TDD_ITERATION_TEMPLATE.format(
        task_id=task_id,
        current_status=current_status,
        test_results=test_results,
        next_step=next_step,
        additional_context=additional_context,
    )


def parse_task_for_implementation(task: dict) -> dict:
    """Parse a task dictionary for implementation.

    Args:
        task: Task dictionary from parse_tasks()

    Returns:
        Enhanced task dictionary with implementation info
    """
    # Extract phase from task ID pattern or description
    phase = "Unknown"
    if task.get("id"):
        task_num = int(task["id"].replace("T", ""))
        if task_num <= 4:
            phase = "Setup"
        elif task_num <= 7:
            phase = "Core Models"
        elif task_num <= 10:
            phase = "Core Implementation"
        elif task_num <= 13:
            phase = "Integration"
        elif task_num <= 16:
            phase = "Testing"
        else:
            phase = "Polish"

    return {
        **task,
        "phase": phase,
        "requires_tests": phase not in ["Setup", "Polish"],
        "is_test_task": "test" in task.get("description", "").lower(),
    }
