# Spec-Kit Setup for Stacks Project

## Overview
This directory contains the Spec-Kit configuration for the Stacks CDK8s GitOps Platform. Spec-Kit enables Spec-Driven Development (SDD) for managing feature specifications, technical plans, and implementation tasks.

## Directory Structure

```
.specify/
├── memory/
│   └── constitution.md          # Project governing principles (template)
├── scripts/
│   └── bash/                    # Utility scripts for spec management
│       ├── check-prerequisites.sh
│       ├── common.sh
│       ├── create-new-feature.sh
│       ├── setup-plan.sh
│       └── update-agent-context.sh
└── templates/
    ├── agent-file-template.md   # AI agent context template
    ├── checklist-template.md    # Quality checklist template
    ├── plan-template.md         # Technical planning template
    ├── spec-template.md         # Feature specification template
    └── tasks-template.md        # Task breakdown template
```

## Available Slash Commands

The following slash commands are available in `.claude/commands/`:

1. **/speckit.constitution** - Create or update project principles and governance
2. **/speckit.specify** - Create feature specifications from natural language
3. **/speckit.plan** - Generate technical implementation plans
4. **/speckit.tasks** - Break down plans into actionable tasks with dependencies
5. **/speckit.implement** - Execute implementation from task list
6. **/speckit.clarify** - Identify underspecified areas and ask clarification questions
7. **/speckit.analyze** - Cross-artifact consistency and quality analysis
8. **/speckit.checklist** - Generate custom validation checklists

## Getting Started

### 1. Establish Project Constitution
```
/speckit.constitution
```
Define the core principles, development standards, and governance for the Stacks platform.

### 2. Create a Feature Specification
```
/speckit.specify <feature-description>
```
Example: `/speckit.specify Add support for multi-region ArgoCD sync`

### 3. Generate Implementation Plan
```
/speckit.plan
```
Creates technical design and architecture plan from the specification.

### 4. Break Down into Tasks
```
/speckit.tasks
```
Generates dependency-ordered, actionable tasks from the plan.

### 5. Execute Implementation
```
/speckit.implement
```
Processes and executes all tasks defined in tasks.md.

## Spec-Kit CLI Tool

The `specify` CLI tool is available for project management:

```bash
# Check installed version
specify --help

# Initialize new feature spec (if needed in future)
specify init <feature-name>

# Check prerequisites
specify check
```

## Integration with Stacks Project

Spec-Kit complements the existing Stacks workflow:

- **CDK8s Development**: Use specs for new chart features
- **GitOps Workflows**: Document ArgoCD application changes
- **Secret Management**: Specify ESO and Azure Key Vault integrations
- **Pipeline Design**: Plan Kargo promotion workflows
- **VCluster Features**: Design multi-environment capabilities

## Best Practices

1. **Start with Constitution**: Define project principles before creating specs
2. **Iterative Refinement**: Use `/speckit.clarify` for ambiguous requirements
3. **Quality Checks**: Run `/speckit.analyze` before implementation
4. **Task Dependencies**: Ensure proper ordering in tasks.md
5. **Version Control**: Commit specs, plans, and tasks alongside code

## NixOS Integration

The `specify` CLI is managed via NixOS home-manager in `/etc/nixos/home-modules/ai-assistants/spec-kit.nix`. It uses `uv` (Python package manager) to run the latest version from GitHub.

## Resources

- [Spec-Kit GitHub Repository](https://github.com/github/spec-kit)
- [Stacks Project Documentation](../docs/)
- [CLAUDE.md](../CLAUDE.md) - Stacks project overview
