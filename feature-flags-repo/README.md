# Feature Flags Repository

This repository contains feature flag configurations managed via GitOps workflow.

## Structure

```
feature-flags/
├── .flipt.yml              # Flipt configuration
├── flags/
│   ├── development/        # Development environment flags
│   │   └── features.yaml
│   ├── staging/            # Staging environment flags
│   │   └── features.yaml
│   └── production/         # Production environment flags
│       └── features.yaml
└── README.md
```

## Usage

### Creating a New Flag

1. Create a branch: `git checkout -b feat/my-new-flag`
2. Edit the appropriate environment file in `flags/<environment>/`
3. Follow the flag schema defined below
4. Create a PR and request review
5. After merge, Flipt syncs automatically within 30 seconds

### Flag Schema

```yaml
version: "1.0"
namespace: <environment>

flags:
  - key: my-flag-key          # Unique identifier (kebab-case)
    name: My Flag             # Human-readable name
    type: BOOLEAN             # BOOLEAN, STRING, INTEGER, FLOAT, OBJECT
    description: What this flag does
    enabled: true             # Master toggle
    defaultVariant: "off"     # Default variant key
    variants:
      - key: "on"
        value: true
      - key: "off"
        value: false
    rules:                    # Optional targeting rules
      - segment: beta-users   # Reference to segment
        rank: 0               # Priority (lower = higher)
        distributions:
          - variant: "on"
            rollout: 100

segments:
  - key: beta-users
    name: Beta Program
    matchType: ANY            # ALL (AND) or ANY (OR)
    constraints:
      - property: groups
        operator: IS_ONE_OF
        value: "beta-testers"
```

### Operators

| Operator | Description |
|----------|-------------|
| EQ | Equals |
| NEQ | Not equals |
| LT | Less than |
| LTE | Less than or equal |
| GT | Greater than |
| GTE | Greater than or equal |
| CONTAINS | Contains substring |
| STARTS_WITH | Prefix match |
| ENDS_WITH | Suffix match |
| IN | In comma-separated list |
| IS_ONE_OF | Array member |

## Environment Promotion

Promote flags through environments by copying configurations:

```bash
# After testing in development
cp flags/development/features.yaml flags/staging/features.yaml

# After staging validation
cp flags/staging/features.yaml flags/production/features.yaml
```

Edit values as needed before committing.

## Best Practices

1. **Naming**: Use kebab-case for flag keys (e.g., `dark-mode-enabled`)
2. **Description**: Always include a description
3. **Testing**: Test flags in development before promoting
4. **Rollouts**: Use percentage rollouts for gradual releases
5. **Cleanup**: Remove flags after features are fully released
