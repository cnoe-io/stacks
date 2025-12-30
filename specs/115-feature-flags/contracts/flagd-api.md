# flagd API Contract

**Version**: v0.10+ | **Protocol**: gRPC + REST (OFREP)

## Overview

flagd provides two evaluation interfaces:
1. **gRPC** (port 8013) - Native OpenFeature SDK communication
2. **OFREP** (port 8016) - REST API following OpenFeature Remote Evaluation Protocol

---

## Endpoints

### Internal Cluster Access

| Service | Port | Protocol | Address |
|---------|------|----------|---------|
| gRPC Evaluation | 8013 | gRPC | `flagd.feature-flags.svc.cluster.local:8013` |
| OFREP REST | 8016 | HTTP | `http://flagd.feature-flags.svc.cluster.local:8016` |
| Metrics | 8015 | HTTP | `http://flagd.feature-flags.svc.cluster.local:8015/metrics` |

### External Access (via Tailscale)

| Service | URL |
|---------|-----|
| OFREP REST | `https://flagd-{cluster}.ts.net:8016` |

---

## gRPC Service Definition

```protobuf
// schema/v1/schema.proto
syntax = "proto3";

package flagd.evaluation.v1;

service Service {
  rpc ResolveBoolean(ResolveBooleanRequest) returns (ResolveBooleanResponse);
  rpc ResolveString(ResolveStringRequest) returns (ResolveStringResponse);
  rpc ResolveInt(ResolveIntRequest) returns (ResolveIntResponse);
  rpc ResolveFloat(ResolveFloatRequest) returns (ResolveFloatResponse);
  rpc ResolveObject(ResolveObjectRequest) returns (ResolveObjectResponse);
  rpc EventStream(EventStreamRequest) returns (stream EventStreamResponse);
}

message ResolveBooleanRequest {
  string flag_key = 1;
  google.protobuf.Struct context = 2;
}

message ResolveBooleanResponse {
  bool value = 1;
  string reason = 2;
  string variant = 3;
  google.protobuf.Struct metadata = 4;
}
```

---

## OFREP REST API

### POST /ofrep/v1/evaluate/flags/{flagKey}

Evaluate a single flag.

**Request**:
```json
POST /ofrep/v1/evaluate/flags/dark-mode-enabled
Content-Type: application/json

{
  "context": {
    "targetingKey": "user-123",
    "email": "user@example.com",
    "tier": "premium"
  }
}
```

**Response (200)**:
```json
{
  "key": "dark-mode-enabled",
  "value": true,
  "reason": "TARGETING_MATCH",
  "variant": "on",
  "metadata": {
    "scope": "development"
  }
}
```

**Response (404 - Flag Not Found)**:
```json
{
  "key": "unknown-flag",
  "errorCode": "FLAG_NOT_FOUND",
  "errorDetails": "flag 'unknown-flag' not found"
}
```

### POST /ofrep/v1/evaluate/flags

Bulk evaluate multiple flags.

**Request**:
```json
POST /ofrep/v1/evaluate/flags
Content-Type: application/json

{
  "context": {
    "targetingKey": "user-123"
  },
  "flags": ["dark-mode-enabled", "api-rate-limit", "new-dashboard"]
}
```

**Response (200)**:
```json
{
  "flags": [
    {
      "key": "dark-mode-enabled",
      "value": true,
      "reason": "TARGETING_MATCH",
      "variant": "on"
    },
    {
      "key": "api-rate-limit",
      "value": 100,
      "reason": "DEFAULT",
      "variant": "default"
    },
    {
      "key": "new-dashboard",
      "value": false,
      "reason": "DISABLED",
      "variant": "off"
    }
  ]
}
```

---

## Evaluation Reasons

| Reason | Description |
|--------|-------------|
| `STATIC` | Flag has only one variant |
| `DEFAULT` | Default variant returned (no rules matched) |
| `TARGETING_MATCH` | Rule matched based on context |
| `SPLIT` | Percentage rollout determined variant |
| `CACHED` | Value from cache |
| `DISABLED` | Flag is disabled |
| `UNKNOWN` | Evaluation failed |
| `ERROR` | Error during evaluation |

---

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `FLAG_NOT_FOUND` | 404 | Flag key does not exist |
| `PARSE_ERROR` | 400 | Invalid request format |
| `TYPE_MISMATCH` | 400 | Requested type doesn't match flag type |
| `TARGETING_KEY_MISSING` | 400 | targetingKey required but not provided |
| `GENERAL` | 500 | Internal server error |

---

## Health Endpoints

### GET /healthz

Liveness probe.

**Response (200)**:
```
OK
```

### GET /readyz

Readiness probe (includes sync source health).

**Response (200)**:
```
OK
```

**Response (503 - Not Ready)**:
```
sync source not ready
```

---

## Metrics Endpoint

### GET /metrics (port 8015)

Prometheus-format metrics.

**Key Metrics**:
```prometheus
# Flag evaluation metrics
flagd_evaluation_total{flag_key="dark-mode-enabled",reason="TARGETING_MATCH"} 1542
flagd_evaluation_duration_seconds_bucket{flag_key="dark-mode-enabled",le="0.001"} 1500
flagd_evaluation_errors_total{flag_key="unknown",error_code="FLAG_NOT_FOUND"} 5

# Sync metrics
flagd_sync_requests_total{source="grpc"} 100
flagd_sync_errors_total{source="grpc"} 0
flagd_flags_count{source="grpc"} 25
```

---

## SDK Usage Examples

### Go (gRPC)

```go
import (
    "context"
    "github.com/open-feature/go-sdk/pkg/openfeature"
    flagd "github.com/open-feature/go-sdk-contrib/providers/flagd/pkg/provider"
)

provider := flagd.NewProvider(
    flagd.WithHost("flagd.feature-flags.svc.cluster.local"),
    flagd.WithPort(8013),
    flagd.WithTLS(false),
)
openfeature.SetProvider(provider)

client := openfeature.NewClient("my-service")

// Boolean evaluation
enabled, err := client.BooleanValue(
    context.Background(),
    "dark-mode-enabled",
    false,
    openfeature.NewEvaluationContext("user-123", map[string]interface{}{
        "email": "user@example.com",
    }),
)
```

### TypeScript (gRPC)

```typescript
import { OpenFeature } from '@openfeature/server-sdk';
import { FlagdProvider } from '@openfeature/flagd-provider';

const provider = new FlagdProvider({
  host: 'flagd.feature-flags.svc.cluster.local',
  port: 8013,
  tls: false,
});

await OpenFeature.setProviderAndWait(provider);
const client = OpenFeature.getClient('my-service');

const enabled = await client.getBooleanValue(
  'dark-mode-enabled',
  false,
  { targetingKey: 'user-123', email: 'user@example.com' }
);
```

### TypeScript (OFREP - Web/Browser)

```typescript
import { OpenFeature } from '@openfeature/web-sdk';
import { OFREPWebProvider } from '@openfeature/ofrep-web-provider';

const provider = new OFREPWebProvider({
  baseUrl: 'http://flagd.feature-flags.svc.cluster.local:8016',
  pollInterval: 30000,
});

await OpenFeature.setProviderAndWait(provider);
const client = OpenFeature.getClient('web-app');

const enabled = await client.getBooleanValue('dark-mode-enabled', false);
```

### Python (gRPC)

```python
from openfeature import api
from openfeature.contrib.provider.flagd import FlagdProvider

api.set_provider(FlagdProvider(
    host="flagd.feature-flags.svc.cluster.local",
    port=8013,
    tls=False,
))

client = api.get_client("my-service")

enabled = client.get_boolean_value(
    flag_key="dark-mode-enabled",
    default_value=False,
    evaluation_context={"targetingKey": "user-123"},
)
```

---

## Configuration Reference

### flagd CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | 8013 | gRPC evaluation port |
| `--ofrep-port` | 8016 | OFREP HTTP port |
| `--metrics-port` | 8015 | Prometheus metrics port |
| `--sync-provider-args` | - | Sync source configuration |
| `--log-format` | json | Log output format |
| `--otel-collector-uri` | - | OTLP endpoint for telemetry |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `FLAGD_PORT` | gRPC port (default: 8013) |
| `FLAGD_OFREP_PORT` | OFREP port (default: 8016) |
| `FLAGD_METRICS_EXPORTER` | Metrics exporter (prometheus/otel) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint |
| `FLAGD_SOURCE_URI` | Flag source URI |
