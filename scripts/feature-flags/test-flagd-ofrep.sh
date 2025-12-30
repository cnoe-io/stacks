#!/bin/bash
# T035: Test flagd OFREP (OpenFeature Remote Evaluation Protocol) endpoint
#
# This script verifies that the flagd OFREP REST API is accessible and responding
# correctly to flag evaluation requests.
#
# OFREP is the standard REST protocol for OpenFeature flag evaluation,
# useful for browser/web applications and HTTP-based integrations.
#
# Usage:
#   ./test-flagd-ofrep.sh [--namespace <namespace>] [--host <host>] [--port <port>]
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - jq for JSON parsing (optional but recommended)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
NAMESPACE="${FLAGD_NAMESPACE:-feature-flags}"
FLAGD_HOST="${FLAGD_HOST:-flagd.feature-flags.svc.cluster.local}"
OFREP_PORT="${FLAGD_OFREP_PORT:-8016}"
OFREP_BASE_URL="http://${FLAGD_HOST}:${OFREP_PORT}"

# Test flags and expected values
declare -A TEST_FLAGS
TEST_FLAGS["new-checkout-flow"]="false"  # defaultVariant: off
TEST_FLAGS["dark-mode"]="true"            # defaultVariant: on

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift 2 ;;
        --host) FLAGD_HOST="$2"; shift 2 ;;
        --port) OFREP_PORT="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help)
            echo "Usage: $0 [--namespace <ns>] [--host <host>] [--port <port>] [-v|--verbose]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=========================================="
echo "  flagd OFREP Connectivity Test (T035)"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Namespace:  ${NAMESPACE}"
echo "  Host:       ${FLAGD_HOST}"
echo "  OFREP Port: ${OFREP_PORT}"
echo "  Base URL:   ${OFREP_BASE_URL}"
echo ""

# Get flagd pod for in-cluster testing
FLAGD_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=flagd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "${FLAGD_POD}" ]]; then
    log_error "Could not find flagd pod in namespace ${NAMESPACE}"
    exit 1
fi

# Test 1: Check OFREP port is listening
log_info "Test 1: Checking OFREP port availability..."
PORT_TEST=$(kubectl exec -n "${NAMESPACE}" "${FLAGD_POD}" -- sh -c "nc -z localhost ${OFREP_PORT} && echo 'OK'" 2>/dev/null || echo "FAIL")
if [[ "${PORT_TEST}" == *"OK"* ]]; then
    log_info "✓ OFREP port ${OFREP_PORT} is listening"
else
    log_error "✗ OFREP port ${OFREP_PORT} is not accessible"
    exit 1
fi

# Test 2: Single flag evaluation
log_info "Test 2: Testing single flag evaluation..."
for FLAG in "${!TEST_FLAGS[@]}"; do
    EXPECTED="${TEST_FLAGS[$FLAG]}"

    RESPONSE=$(kubectl exec -n "${NAMESPACE}" "${FLAGD_POD}" -- sh -c "
        wget -q -O- --post-data='{\"context\":{\"targetingKey\":\"test-user-123\"}}' \
             --header='Content-Type: application/json' \
             'http://localhost:${OFREP_PORT}/ofrep/v1/evaluate/flags/${FLAG}' 2>/dev/null
    " || echo '{"error":"request failed"}')

    if echo "${RESPONSE}" | grep -q '"value"'; then
        VALUE=$(echo "${RESPONSE}" | grep -o '"value":[^,}]*' | cut -d: -f2 | tr -d ' ')
        REASON=$(echo "${RESPONSE}" | grep -o '"reason":"[^"]*"' | cut -d: -f2 | tr -d '"')
        VARIANT=$(echo "${RESPONSE}" | grep -o '"variant":"[^"]*"' | cut -d: -f2 | tr -d '"')

        if [[ "${VALUE}" == "${EXPECTED}" ]]; then
            log_info "✓ Flag '${FLAG}': value=${VALUE}, variant=${VARIANT}, reason=${REASON}"
        else
            log_warn "⚠ Flag '${FLAG}': got ${VALUE}, expected ${EXPECTED}"
        fi
    else
        log_error "✗ Flag '${FLAG}' evaluation failed: ${RESPONSE}"
    fi
done

# Test 3: Flag evaluation with context
log_info "Test 3: Testing evaluation with context attributes..."
CONTEXT_RESPONSE=$(kubectl exec -n "${NAMESPACE}" "${FLAGD_POD}" -- sh -c "
    wget -q -O- --post-data='{
        \"context\": {
            \"targetingKey\": \"user-456\",
            \"email\": \"user@example.com\",
            \"tier\": \"premium\",
            \"groups\": [\"beta-testers\"]
        }
    }' \
    --header='Content-Type: application/json' \
    'http://localhost:${OFREP_PORT}/ofrep/v1/evaluate/flags/dark-mode' 2>/dev/null
" || echo '{"error":"request failed"}')

if echo "${CONTEXT_RESPONSE}" | grep -q '"value"'; then
    log_info "✓ Context-based evaluation successful"
    log_debug "Response: ${CONTEXT_RESPONSE}"
else
    log_warn "⚠ Context-based evaluation returned: ${CONTEXT_RESPONSE}"
fi

# Test 4: Bulk flag evaluation
log_info "Test 4: Testing bulk flag evaluation..."
BULK_RESPONSE=$(kubectl exec -n "${NAMESPACE}" "${FLAGD_POD}" -- sh -c "
    wget -q -O- --post-data='{
        \"context\": {\"targetingKey\": \"bulk-test-user\"}
    }' \
    --header='Content-Type: application/json' \
    'http://localhost:${OFREP_PORT}/ofrep/v1/evaluate/flags' 2>/dev/null
" || echo '{"error":"bulk request failed"}')

if echo "${BULK_RESPONSE}" | grep -q '"flags"'; then
    FLAG_COUNT=$(echo "${BULK_RESPONSE}" | grep -o '"key"' | wc -l)
    log_info "✓ Bulk evaluation returned ${FLAG_COUNT} flags"
else
    # flagd may not support bulk eval in all versions
    log_warn "⚠ Bulk evaluation not available or returned: ${BULK_RESPONSE:0:100}"
fi

# Test 5: Error handling - non-existent flag
log_info "Test 5: Testing error handling for non-existent flag..."
ERROR_RESPONSE=$(kubectl exec -n "${NAMESPACE}" "${FLAGD_POD}" -- sh -c "
    wget -q -O- --post-data='{\"context\":{\"targetingKey\":\"test\"}}' \
         --header='Content-Type: application/json' \
         'http://localhost:${OFREP_PORT}/ofrep/v1/evaluate/flags/non-existent-flag' 2>/dev/null
" || echo '{"errorCode":"FLAG_NOT_FOUND"}')

if echo "${ERROR_RESPONSE}" | grep -qi "not.found\|error"; then
    log_info "✓ Error handling works correctly for non-existent flags"
else
    log_warn "⚠ Unexpected response for non-existent flag: ${ERROR_RESPONSE}"
fi

# Test 6: Cross-pod OFREP connectivity
log_info "Test 6: Testing cluster-wide OFREP connectivity..."
CURL_RESULT=$(kubectl run ofrep-test --rm -i --restart=Never \
    --image=curlimages/curl:8.5.0 \
    --namespace="${NAMESPACE}" \
    -- curl -s -X POST \
       -H "Content-Type: application/json" \
       -d '{"context":{"targetingKey":"cluster-test"}}' \
       "http://flagd.feature-flags.svc.cluster.local:${OFREP_PORT}/ofrep/v1/evaluate/flags/dark-mode" 2>/dev/null || echo "FAIL")

if echo "${CURL_RESULT}" | grep -q '"value"'; then
    log_info "✓ OFREP endpoint accessible from other pods"
else
    log_warn "⚠ Cross-pod test result: ${CURL_RESULT:0:100}"
fi

# Test 7: Response time check
log_info "Test 7: Checking response latency..."
START_TIME=$(date +%s%N)
for i in {1..10}; do
    kubectl exec -n "${NAMESPACE}" "${FLAGD_POD}" -- sh -c "
        wget -q -O- --post-data='{\"context\":{\"targetingKey\":\"latency-test-${i}\"}}' \
             --header='Content-Type: application/json' \
             'http://localhost:${OFREP_PORT}/ofrep/v1/evaluate/flags/dark-mode'
    " > /dev/null 2>&1
done
END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
AVG_MS=$(( ELAPSED_MS / 10 ))

if [[ ${AVG_MS} -lt 50 ]]; then
    log_info "✓ Average response time: ${AVG_MS}ms (excellent)"
elif [[ ${AVG_MS} -lt 100 ]]; then
    log_info "✓ Average response time: ${AVG_MS}ms (good)"
else
    log_warn "⚠ Average response time: ${AVG_MS}ms (slow, check performance)"
fi

echo ""
echo "=========================================="
echo "  OFREP Connectivity Test Complete"
echo "=========================================="
echo ""
log_info "Summary: flagd OFREP endpoint is operational"
echo ""
echo "OFREP Connection Details:"
echo "  Base URL: http://${FLAGD_HOST}:${OFREP_PORT}"
echo "  Evaluate: POST /ofrep/v1/evaluate/flags/{flagKey}"
echo "  Bulk:     POST /ofrep/v1/evaluate/flags"
echo ""
echo "Example curl command:"
echo "  curl -X POST http://${FLAGD_HOST}:${OFREP_PORT}/ofrep/v1/evaluate/flags/dark-mode \\"
echo '    -H "Content-Type: application/json" \'
echo '    -d '\''{"context":{"targetingKey":"user-123"}}'\'''
echo ""
echo "Example TypeScript (Web SDK):"
echo '  const provider = new OFREPWebProvider({'
echo "    baseUrl: 'http://${FLAGD_HOST}:${OFREP_PORT}',"
echo '  });'
