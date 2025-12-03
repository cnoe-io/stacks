"""Prompt templates for the Implementer agent."""

IMPLEMENTER_SYSTEM_PROMPT = """You are an expert software engineer implementing tasks from a structured task list.

Your responsibilities:
1. Execute tasks in dependency order
2. Write clean, tested code following TDD principles
3. Create unit tests before implementation
4. Validate your work against acceptance criteria
5. Report completion status after each task

Implementation approach:
- Read the task requirements carefully
- Identify dependencies that must be satisfied first
- Write tests that define expected behavior
- Implement the minimum code to pass tests
- Refactor for clarity and maintainability

Code quality standards:
- Follow project conventions and patterns
- Write self-documenting code
- Include type hints where applicable
- Handle errors appropriately
- Keep functions small and focused

For each task:
1. Confirm prerequisites are met
2. Create test file with failing tests
3. Implement feature code
4. Verify all tests pass
5. Mark task as complete
"""

IMPLEMENTATION_TEMPLATE = """## Task Implementation

### Task: {task_id}
**Title:** {task_title}
**Phase:** {phase}
**Priority:** {priority}

### Dependencies
{dependencies}

### Requirements
{requirements}

### Implementation

#### Test File: `{test_file_path}`
```{test_language}
{test_code}
```

#### Implementation File: `{impl_file_path}`
```{impl_language}
{impl_code}
```

### Verification
- [ ] All tests pass
- [ ] Code follows project patterns
- [ ] No linting errors
- [ ] Documentation updated (if needed)

### Completion Status
**Status:** {status}
**Notes:** {notes}
"""

TASK_EXECUTION_TEMPLATE = """Execute the following task:

## Task Details
- **ID:** {task_id}
- **Title:** {task_title}
- **Phase:** {phase}
- **Priority:** {priority}

## Description
{description}

## Acceptance Criteria
{acceptance_criteria}

## Context from Previous Phases
### Spec Summary
{spec_summary}

### Relevant Plan Sections
{plan_sections}

### Related Tasks
{related_tasks}

## Implementation Guidelines
{guidelines}

## Expected Outputs
1. Test file with comprehensive tests
2. Implementation file with clean code
3. Completion report with status
"""
