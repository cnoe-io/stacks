# Feature Flags Test Scripts

This directory contains test scripts for validating the flagd feature flag evaluation service.

## Test Scripts

| Script | Task | Description |
|--------|------|-------------|
| `test-flagd-grpc.sh` | T034 | Verify flagd gRPC endpoint connectivity |
| `test-flagd-ofrep.sh` | T035 | Verify flagd OFREP REST endpoint |
| `test-targeting-rules.sh` | T036 | Validate targeting rules evaluation |
| `test-sdk-fallback.sh` | T037 | Test SDK fallback behavior when flagd is unavailable |
| `test-propagation-timing.sh` | T038 | Verify flag changes propagate within 30s (SC-004) |

## Quick Start

```bash
# Run all tests
cd scripts/feature-flags
chmod +x *.sh

# Test gRPC connectivity
./test-flagd-grpc.sh

# Test OFREP REST API
./test-flagd-ofrep.sh

# Test targeting rules
./test-targeting-rules.sh

# Test SDK fallback (non-destructive)
./test-sdk-fallback.sh --skip-destructive

# Test propagation timing (non-destructive)
./test-propagation-timing.sh --skip-mutation
```

## Prerequisites

- `kubectl` configured with cluster access
- flagd deployed in `feature-flags` namespace
- Pods in the cluster can reach flagd service

## Configuration

All scripts support environment variables:

```bash
export FLAGD_NAMESPACE=feature-flags  # Target namespace
export FLAGD_HOST=flagd.feature-flags.svc.cluster.local
export FLAGD_GRPC_PORT=8013
export FLAGD_OFREP_PORT=8016
```

Or pass as arguments:

```bash
./test-flagd-grpc.sh --namespace feature-flags --host flagd --port 8013
```

## Test Categories

### Connectivity Tests (T034, T035)

Validate that the flagd service is accessible and responding to requests.

- **gRPC (T034)**: Tests port 8013 for SDK communication
- **OFREP (T035)**: Tests port 8016 for REST/HTTP clients

### Functional Tests (T036)

Validates that flag evaluation works correctly:

- Default values when no rules match
- Targeting key consistency (sticky evaluation)
- Context attribute handling
- Evaluation reasons

### Resilience Tests (T037)

Tests graceful degradation per requirement SC-006:

- SDK fallback to default values
- Connection failure handling
- Recovery after flagd restart

### Performance Tests (T038)

Validates propagation timing per requirement SC-004:

- Flag changes reflect within 30 seconds
- ConfigMap update detection
- End-to-end propagation measurement

## Success Criteria

| Requirement | Test | Expected Result |
|-------------|------|-----------------|
| SC-003 | Performance | 1000 evaluations/second, <10ms p99 |
| SC-004 | Propagation | Changes reflect in <30 seconds |
| SC-006 | Resilience | Graceful degradation when unavailable |

## Troubleshooting

### flagd pod not found

```bash
# Check if flagd is deployed
kubectl get pods -n feature-flags -l app=flagd

# Check deployment status
kubectl describe deployment flagd -n feature-flags
```

### Connection refused

```bash
# Check service exists
kubectl get svc flagd -n feature-flags

# Check endpoints
kubectl get endpoints flagd -n feature-flags
```

### Evaluation errors

```bash
# Check flagd logs
kubectl logs -l app=flagd -n feature-flags

# Verify ConfigMap has valid JSON
kubectl get configmap flagd-config -n feature-flags -o jsonpath='{.data.flagd\.json}' | jq .
```

## Related Documentation

- [flagd Documentation](https://flagd.dev/)
- [OFREP Protocol](https://flagd.dev/reference/flagd-ofrep/)
- [OpenFeature Specification](https://openfeature.dev/specification/)
- [Feature Flags Quickstart](../../specs/115-feature-flags/quickstart.md)
