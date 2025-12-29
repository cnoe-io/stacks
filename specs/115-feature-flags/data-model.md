# Data Model: Feature Flagging System

**Feature**: 115-feature-flags | **Date**: 2025-12-29

## Overview

This document defines the key entities, their relationships, and validation rules for the feature flagging system. The model aligns with OpenFeature specification and Flipt's data structures.

---

## Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                 Namespace                                    │
│  (development, staging, production)                                          │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         │ contains 1:N
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                   Flag                                       │
│  key, type, description, enabled, defaultVariant                            │
└─────────────────────────────────────────────────────────────────────────────┘
         │                                    │
         │ has 1:N                            │ has 0:N
         ▼                                    ▼
┌─────────────────────┐              ┌─────────────────────────────────────────┐
│      Variant        │              │              Rule                        │
│  key, value, weight │              │  segment, distributions, priority        │
└─────────────────────┘              └─────────────────────────────────────────┘
                                              │
                                              │ references 1:1
                                              ▼
                                     ┌─────────────────────────────────────────┐
                                     │             Segment                      │
                                     │  key, matchType, constraints             │
                                     └─────────────────────────────────────────┘
                                              │
                                              │ has 1:N
                                              ▼
                                     ┌─────────────────────────────────────────┐
                                     │           Constraint                     │
                                     │  property, operator, value               │
                                     └─────────────────────────────────────────┘
```

---

## Core Entities

### 1. Namespace

Logical grouping for flags, representing an environment or tenant.

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `key` | string | Yes | `^[a-z][a-z0-9-]{0,62}$` | Unique identifier (e.g., `production`) |
| `name` | string | Yes | max 255 chars | Display name |
| `description` | string | No | max 1000 chars | Purpose description |
| `protected` | boolean | No | default: false | Requires elevated permissions |

**Example**:
```yaml
key: production
name: Production Environment
description: Live production feature flags
protected: true
```

---

### 2. Flag

Core feature flag definition controlling feature behavior.

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `key` | string | Yes | `^[a-z][a-z0-9-]{0,126}$` | Unique identifier within namespace |
| `name` | string | Yes | max 255 chars | Display name |
| `type` | enum | Yes | `BOOLEAN\|STRING\|INTEGER\|FLOAT\|OBJECT` | Value type |
| `description` | string | No | max 1000 chars | Flag purpose |
| `enabled` | boolean | Yes | default: false | Master on/off toggle |
| `defaultVariant` | string | Yes | Must match variant key | Fallback when no rules match |
| `variants` | array | Yes | min 1 item | Possible values |
| `rules` | array | No | - | Targeting rules |
| `metadata` | object | No | - | Custom key-value pairs |

**Flag Types** (per FR-005):

| Type | Use Case | Example Value |
|------|----------|---------------|
| `BOOLEAN` | Simple on/off | `true`, `false` |
| `STRING` | Text variants | `"control"`, `"variant-a"` |
| `INTEGER` | Numeric limits | `10`, `100`, `1000` |
| `FLOAT` | Percentages | `0.5`, `1.0` |
| `OBJECT` | Complex config | `{"theme": "dark", "maxItems": 50}` |

**Example**:
```yaml
key: dark-mode-enabled
name: Dark Mode Feature
type: BOOLEAN
description: Enables dark mode UI theme
enabled: true
defaultVariant: "off"
variants:
  - key: "on"
    value: true
  - key: "off"
    value: false
rules:
  - segment: beta-users
    distributions:
      - variant: "on"
        rollout: 100
```

---

### 3. Variant

Possible value a flag can return.

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `key` | string | Yes | `^[a-z][a-z0-9-]{0,62}$` | Unique within flag |
| `value` | any | Yes | Must match flag type | Actual value returned |
| `description` | string | No | max 255 chars | Variant description |
| `attachment` | object | No | - | Additional metadata |

**Example**:
```yaml
variants:
  - key: control
    value: "original"
    description: Original experience
  - key: variant-a
    value: "new-design"
    description: New design test
  - key: variant-b
    value: "simplified"
    description: Simplified flow
```

---

### 4. Rule

Targeting logic determining which variant a user receives.

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `id` | string | Yes | UUID | Unique identifier |
| `segment` | string | Conditional | Must reference valid segment | Target segment key |
| `rank` | integer | Yes | >= 0 | Priority (lower = higher priority) |
| `distributions` | array | Yes | weights sum to 100 | Variant distribution |

**Distribution**:

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `variant` | string | Yes | Must match variant key | Target variant |
| `rollout` | float | Yes | 0-100, sum = 100 | Percentage |

**Example**:
```yaml
rules:
  # Rule 1: Beta users get 100% variant-a
  - segment: beta-users
    rank: 0
    distributions:
      - variant: variant-a
        rollout: 100

  # Rule 2: 20% rollout for everyone else
  - rank: 1
    distributions:
      - variant: variant-a
        rollout: 20
      - variant: control
        rollout: 80
```

---

### 5. Segment

Reusable user group definition for targeting.

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `key` | string | Yes | `^[a-z][a-z0-9-]{0,62}$` | Unique identifier |
| `name` | string | Yes | max 255 chars | Display name |
| `description` | string | No | max 1000 chars | Segment purpose |
| `matchType` | enum | Yes | `ALL\|ANY` | Constraint matching logic |
| `constraints` | array | Yes | min 1 item | Matching criteria |

**Example**:
```yaml
key: beta-users
name: Beta Program Users
matchType: ANY
constraints:
  - property: email
    operator: ENDS_WITH
    value: "@beta.example.com"
  - property: groups
    operator: CONTAINS
    value: "beta-testers"
```

---

### 6. Constraint

Individual matching condition within a segment.

| Field | Type | Required | Validation | Description |
|-------|------|----------|------------|-------------|
| `property` | string | Yes | max 64 chars | Context property to match |
| `operator` | enum | Yes | See operators | Comparison operation |
| `value` | string | Yes | max 1024 chars | Value to compare |
| `type` | enum | No | `STRING\|NUMBER\|BOOLEAN\|DATETIME` | Property type hint |

**Operators**:

| Operator | Description | Example |
|----------|-------------|---------|
| `EQ` | Equals | `property: tier, value: "premium"` |
| `NEQ` | Not equals | `property: country, value: "US"` |
| `LT` / `LTE` | Less than (or equal) | `property: age, value: "18"` |
| `GT` / `GTE` | Greater than (or equal) | `property: score, value: "100"` |
| `CONTAINS` | Contains substring | `property: email, value: "example.com"` |
| `NOT_CONTAINS` | Does not contain | `property: email, value: "test"` |
| `STARTS_WITH` | Prefix match | `property: userId, value: "user_"` |
| `ENDS_WITH` | Suffix match | `property: email, value: "@corp.com"` |
| `MATCHES` | Regex match | `property: path, value: "^/api/v[0-9]+"` |
| `IN` | In list | `property: country, value: "US,CA,UK"` |
| `NOT_IN` | Not in list | `property: plan, value: "free,trial"` |
| `IS_ONE_OF` | Member of array | `property: roles, value: "admin,super"` |
| `IS_NOT_ONE_OF` | Not member of array | `property: roles, value: "guest"` |

---

### 7. Evaluation Context

Runtime information provided during flag evaluation (OpenFeature spec).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `targetingKey` | string | Recommended | Unique user/session identifier |
| `attributes` | object | No | Custom key-value properties |

**Standard Attributes**:

| Attribute | Type | Description |
|-----------|------|-------------|
| `userId` | string | User identifier |
| `email` | string | User email |
| `groups` | string[] | Group memberships |
| `tier` | string | Subscription tier |
| `country` | string | ISO country code |
| `deviceType` | string | Device category |
| `appVersion` | string | Application version |

**Example**:
```typescript
const context: EvaluationContext = {
  targetingKey: "user-123",
  attributes: {
    email: "user@example.com",
    tier: "premium",
    groups: ["beta-testers", "early-adopters"],
    country: "US"
  }
};
```

---

### 8. Audit Event

Record of flag changes for audit trail (FR-014).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Event UUID |
| `timestamp` | datetime | Yes | ISO 8601 timestamp |
| `action` | enum | Yes | `CREATE\|UPDATE\|DELETE` |
| `resourceType` | enum | Yes | `FLAG\|SEGMENT\|NAMESPACE` |
| `resourceKey` | string | Yes | Affected resource key |
| `namespace` | string | Yes | Target namespace |
| `actor` | object | Yes | User who made change |
| `changes` | object | No | Diff of before/after |

**Actor**:
| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Keycloak user ID |
| `email` | string | User email |
| `method` | string | `oidc`, `api`, `git` |

---

## State Transitions

### Flag Lifecycle

```
                    ┌──────────┐
                    │  DRAFT   │
                    └────┬─────┘
                         │ enable
                         ▼
    ┌────────────────────────────────────────┐
    │                ENABLED                  │
    │  ┌──────────────────────────────────┐  │
    │  │ Rules evaluated for each request │  │
    │  └──────────────────────────────────┘  │
    └────────────────────────────────────────┘
         │                        │
         │ disable               │ archive
         ▼                        ▼
    ┌──────────┐            ┌──────────┐
    │ DISABLED │            │ ARCHIVED │
    └──────────┘            └──────────┘
```

### Rule Evaluation Order

1. Check if flag is enabled (return default if disabled)
2. Sort rules by rank (ascending)
3. For each rule:
   - If segment defined, check if context matches segment
   - If match (or no segment), apply distributions
   - Return variant based on targeting key hash
4. If no rules match, return default variant

---

## Validation Rules

### Flag Key Validation
```regex
^[a-z][a-z0-9-]{0,126}$
```
- Starts with lowercase letter
- Contains only lowercase letters, numbers, hyphens
- 1-127 characters

### Variant Weights
- All distribution rollouts must sum to exactly 100
- Each rollout must be 0-100

### Segment Constraints
- At least one constraint required
- Property names limited to 64 characters
- Values limited to 1024 characters

### Namespace Protection
- Protected namespaces require `platform-team` role for modifications
- Non-protected namespaces allow `developer` role access

---

## CDK8s Type Mappings

### Flag CRD (OpenFeature Operator)

```typescript
// From imports/core.openfeature.dev.ts
interface FeatureFlagSpec {
  flags: Record<string, {
    state: 'ENABLED' | 'DISABLED';
    defaultVariant: string;
    variants: Record<string, any>;
    targeting?: object;
  }>;
}
```

### Flipt Flag YAML

```typescript
interface FliptFlag {
  key: string;
  name: string;
  type: 'VARIANT_FLAG_TYPE' | 'BOOLEAN_FLAG_TYPE';
  description?: string;
  enabled: boolean;
  variants: Array<{
    key: string;
    value?: string;
    attachment?: string;
  }>;
  rules?: Array<{
    segment?: string;
    distributions: Array<{
      variant: string;
      rollout: number;
    }>;
  }>;
}
```

---

## Example Flag Configuration

Complete example for the `feature-flags` repository:

```yaml
# flags/development/features.yaml
namespace: development

flags:
  - key: dark-mode-enabled
    name: Dark Mode
    type: BOOLEAN
    enabled: true
    defaultVariant: "off"
    variants:
      - key: "on"
        value: true
      - key: "off"
        value: false
    rules:
      - segment: beta-users
        distributions:
          - variant: "on"
            rollout: 100

  - key: api-rate-limit
    name: API Rate Limit
    type: INTEGER
    enabled: true
    defaultVariant: "default"
    variants:
      - key: default
        value: 100
      - key: premium
        value: 1000
      - key: unlimited
        value: -1
    rules:
      - segment: premium-tier
        distributions:
          - variant: premium
            rollout: 100

segments:
  - key: beta-users
    name: Beta Program
    matchType: ANY
    constraints:
      - property: groups
        operator: IS_ONE_OF
        value: "beta-testers,early-adopters"

  - key: premium-tier
    name: Premium Users
    matchType: ALL
    constraints:
      - property: tier
        operator: EQ
        value: "premium"
```
