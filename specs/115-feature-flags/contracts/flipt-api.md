# Flipt API Contract

**Version**: v2.5+ | **Protocol**: REST + gRPC

## Overview

Flipt provides a management API for creating, updating, and managing feature flags. The API supports both REST and gRPC protocols.

---

## Endpoints

### Internal Cluster Access

| Service | Port | Protocol | Address |
|---------|------|----------|---------|
| HTTP (UI + API) | 8080 | HTTP | `http://flipt.feature-flags.svc.cluster.local:8080` |
| gRPC (API) | 9000 | gRPC | `flipt.feature-flags.svc.cluster.local:9000` |

### External Access (via Tailscale)

| Service | URL |
|---------|-----|
| Flipt UI | `https://flipt-{cluster}.ts.net` |
| Flipt API | `https://flipt-{cluster}.ts.net/api/v1` |

---

## Authentication

All API requests require authentication via Keycloak OIDC.

**Headers**:
```
Authorization: Bearer <access_token>
```

**Token Acquisition**:
```bash
# Get token from Keycloak
TOKEN=$(curl -s -X POST \
  "https://keycloak.cnoe.localtest.me/realms/cnoe/protocol/openid-connect/token" \
  -d "client_id=flipt" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "grant_type=client_credentials" \
  | jq -r '.access_token')
```

---

## Namespaces API

### GET /api/v1/namespaces

List all namespaces.

**Response (200)**:
```json
{
  "namespaces": [
    {
      "key": "development",
      "name": "Development",
      "description": "Dev environment",
      "protected": false,
      "createdAt": "2025-01-01T00:00:00Z",
      "updatedAt": "2025-01-01T00:00:00Z"
    },
    {
      "key": "production",
      "name": "Production",
      "description": "Prod environment",
      "protected": true,
      "createdAt": "2025-01-01T00:00:00Z",
      "updatedAt": "2025-01-01T00:00:00Z"
    }
  ]
}
```

### POST /api/v1/namespaces

Create a namespace.

**Request**:
```json
{
  "key": "staging",
  "name": "Staging Environment",
  "description": "Pre-production testing"
}
```

**Response (201)**:
```json
{
  "key": "staging",
  "name": "Staging Environment",
  "description": "Pre-production testing",
  "protected": false,
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-01T00:00:00Z"
}
```

---

## Flags API

### GET /api/v1/namespaces/{namespace}/flags

List flags in a namespace.

**Response (200)**:
```json
{
  "flags": [
    {
      "key": "dark-mode-enabled",
      "name": "Dark Mode",
      "type": "BOOLEAN_FLAG_TYPE",
      "description": "Enable dark mode UI",
      "enabled": true,
      "createdAt": "2025-01-01T00:00:00Z",
      "updatedAt": "2025-01-01T00:00:00Z",
      "variants": [
        {"key": "on", "value": true},
        {"key": "off", "value": false}
      ],
      "defaultVariant": {"key": "off"}
    }
  ],
  "totalCount": 1,
  "nextPageToken": ""
}
```

### POST /api/v1/namespaces/{namespace}/flags

Create a new flag.

**Request**:
```json
{
  "key": "new-feature",
  "name": "New Feature",
  "type": "BOOLEAN_FLAG_TYPE",
  "description": "A new feature toggle",
  "enabled": false,
  "defaultVariantKey": "off"
}
```

**Response (201)**:
```json
{
  "key": "new-feature",
  "name": "New Feature",
  "type": "BOOLEAN_FLAG_TYPE",
  "description": "A new feature toggle",
  "enabled": false,
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-01T00:00:00Z"
}
```

### GET /api/v1/namespaces/{namespace}/flags/{flagKey}

Get a specific flag.

**Response (200)**:
```json
{
  "key": "dark-mode-enabled",
  "name": "Dark Mode",
  "type": "BOOLEAN_FLAG_TYPE",
  "description": "Enable dark mode UI",
  "enabled": true,
  "variants": [
    {"key": "on", "value": true},
    {"key": "off", "value": false}
  ],
  "defaultVariant": {"key": "off"},
  "rules": [
    {
      "id": "rule-123",
      "rank": 0,
      "segmentKey": "beta-users",
      "distributions": [
        {"variantKey": "on", "rollout": 100}
      ]
    }
  ]
}
```

### PUT /api/v1/namespaces/{namespace}/flags/{flagKey}

Update a flag.

**Request**:
```json
{
  "name": "Dark Mode Toggle",
  "description": "Updated description",
  "enabled": true
}
```

### DELETE /api/v1/namespaces/{namespace}/flags/{flagKey}

Delete a flag.

**Response (204)**: No content

---

## Variants API

### POST /api/v1/namespaces/{namespace}/flags/{flagKey}/variants

Add a variant to a flag.

**Request**:
```json
{
  "key": "variant-b",
  "value": "new-design",
  "description": "New design variant"
}
```

### PUT /api/v1/namespaces/{namespace}/flags/{flagKey}/variants/{variantKey}

Update a variant.

### DELETE /api/v1/namespaces/{namespace}/flags/{flagKey}/variants/{variantKey}

Delete a variant.

---

## Rules API

### GET /api/v1/namespaces/{namespace}/flags/{flagKey}/rules

List rules for a flag.

**Response (200)**:
```json
{
  "rules": [
    {
      "id": "rule-123",
      "rank": 0,
      "segmentKey": "beta-users",
      "segmentOperator": "OR",
      "distributions": [
        {"variantKey": "on", "rollout": 100.0}
      ]
    }
  ]
}
```

### POST /api/v1/namespaces/{namespace}/flags/{flagKey}/rules

Create a targeting rule.

**Request**:
```json
{
  "segmentKey": "premium-users",
  "rank": 1,
  "distributions": [
    {"variantKey": "on", "rollout": 50.0},
    {"variantKey": "off", "rollout": 50.0}
  ]
}
```

### PUT /api/v1/namespaces/{namespace}/flags/{flagKey}/rules/{ruleId}

Update a rule.

### DELETE /api/v1/namespaces/{namespace}/flags/{flagKey}/rules/{ruleId}

Delete a rule.

---

## Segments API

### GET /api/v1/namespaces/{namespace}/segments

List segments.

**Response (200)**:
```json
{
  "segments": [
    {
      "key": "beta-users",
      "name": "Beta Users",
      "description": "Beta program participants",
      "matchType": "ANY_MATCH_TYPE",
      "constraints": [
        {
          "id": "const-1",
          "type": "STRING_COMPARISON_TYPE",
          "property": "groups",
          "operator": "isoneof",
          "value": "beta-testers"
        }
      ]
    }
  ]
}
```

### POST /api/v1/namespaces/{namespace}/segments

Create a segment.

**Request**:
```json
{
  "key": "enterprise-users",
  "name": "Enterprise Users",
  "description": "Enterprise tier customers",
  "matchType": "ALL_MATCH_TYPE"
}
```

### POST /api/v1/namespaces/{namespace}/segments/{segmentKey}/constraints

Add a constraint to a segment.

**Request**:
```json
{
  "type": "STRING_COMPARISON_TYPE",
  "property": "tier",
  "operator": "eq",
  "value": "enterprise"
}
```

---

## Evaluation API

### POST /api/v1/namespaces/{namespace}/evaluate

Evaluate a flag (for testing in UI).

**Request**:
```json
{
  "flagKey": "dark-mode-enabled",
  "entityId": "user-123",
  "context": {
    "email": "user@example.com",
    "tier": "premium"
  }
}
```

**Response (200)**:
```json
{
  "flagKey": "dark-mode-enabled",
  "match": true,
  "segmentKeys": ["beta-users"],
  "reason": "MATCH_EVALUATION_REASON",
  "variantKey": "on",
  "value": true,
  "requestId": "eval-123",
  "requestDurationMillis": 1.5
}
```

---

## Rollouts API (Percentage-based)

### POST /api/v1/namespaces/{namespace}/flags/{flagKey}/rollouts

Create a percentage rollout.

**Request**:
```json
{
  "type": "PERCENTAGE_ROLLOUT_TYPE",
  "rank": 1,
  "percentage": {
    "value": 25.0,
    "variantKey": "on"
  }
}
```

---

## Audit API

### GET /api/v1/namespaces/{namespace}/audit

Get audit log for namespace.

**Response (200)**:
```json
{
  "events": [
    {
      "id": "audit-123",
      "timestamp": "2025-01-01T12:00:00Z",
      "type": "FLAG",
      "action": "UPDATED",
      "metadata": {
        "actor": {
          "email": "admin@example.com",
          "authentication": "oidc"
        }
      },
      "payload": {
        "flagKey": "dark-mode-enabled",
        "namespaceKey": "production"
      }
    }
  ],
  "nextPageToken": ""
}
```

---

## Error Responses

| HTTP Status | Error Code | Description |
|-------------|------------|-------------|
| 400 | `INVALID_ARGUMENT` | Invalid request parameters |
| 401 | `UNAUTHENTICATED` | Missing or invalid auth token |
| 403 | `PERMISSION_DENIED` | Insufficient permissions |
| 404 | `NOT_FOUND` | Resource not found |
| 409 | `ALREADY_EXISTS` | Resource already exists |
| 500 | `INTERNAL` | Internal server error |

**Error Response Format**:
```json
{
  "code": 3,
  "message": "flag key must be provided",
  "details": []
}
```

---

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| Read operations | 1000 req/min |
| Write operations | 100 req/min |
| Evaluation | 10000 req/min |

---

## RBAC Requirements (FR-015)

| Role | Namespaces | Operations |
|------|------------|------------|
| `developer` | development, staging | create, read, update, delete |
| `platform-team` | all (including production) | create, read, update, delete |
| `viewer` | all | read only |

**Namespace Protection**:
- Protected namespaces require `platform-team` role
- Production namespace is protected by default
