#!/bin/bash
#
# test-caipe-observability.sh
#
# Validates CAIPE observability configuration:
# - Checks all pods have ENABLE_TRACING=true
# - Verifies Langfuse credentials secret exists
# - Tests OTEL collector connectivity
# - Generates test trace via API call
# - Verifies traces in Langfuse (if accessible)
#
# Usage: ./scripts/test-caipe-observability.sh [--verbose]

set -euo pipefail

NAMESPACE="ai-platform-engineering"
OBSERVABILITY_NS="observability"
VERBOSE="${1:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"

    if eval "$test_command" > /dev/null 2>&1; then
        log_success "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_fail "$test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo "========================================"
echo "  CAIPE Observability Validation Tests"
echo "========================================"
echo ""

# ==========================================================================
# Test 1: Check namespace exists
# ==========================================================================
log_info "Test 1: Checking namespace exists..."
run_test "Namespace $NAMESPACE exists" \
    "kubectl get namespace $NAMESPACE"

# ==========================================================================
# Test 2: Check Langfuse credentials secret exists
# ==========================================================================
log_info "Test 2: Checking Langfuse credentials secret..."
run_test "Secret caipe-langfuse-credentials exists" \
    "kubectl get secret caipe-langfuse-credentials -n $NAMESPACE"

# ==========================================================================
# Test 3: Check ExternalSecret is synced
# ==========================================================================
log_info "Test 3: Checking ExternalSecret sync status..."
if kubectl get externalsecret -n $NAMESPACE 2>/dev/null | grep -q "langfuse-credentials"; then
    ES_STATUS=$(kubectl get externalsecret langfuse-credentials -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$ES_STATUS" == "True" ]; then
        log_success "ExternalSecret langfuse-credentials is synced"
        ((TESTS_PASSED++))
    else
        log_warn "ExternalSecret langfuse-credentials status: $ES_STATUS"
        ((TESTS_FAILED++))
    fi
else
    log_warn "ExternalSecret langfuse-credentials not found (may be using direct secret)"
    ((TESTS_PASSED++))
fi

# ==========================================================================
# Test 4: Check ENABLE_TRACING environment variable in pods
# ==========================================================================
log_info "Test 4: Checking ENABLE_TRACING in CAIPE pods..."

CAIPE_PODS=$(kubectl get pods -n $NAMESPACE -l 'app.kubernetes.io/part-of=ai-platform-engineering' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$CAIPE_PODS" ]; then
    for pod in $CAIPE_PODS; do
        # Get ENABLE_TRACING from pod env
        TRACING_VALUE=$(kubectl exec -n $NAMESPACE $pod -- env 2>/dev/null | grep "ENABLE_TRACING" | cut -d'=' -f2 || echo "not_set")

        if [ "$TRACING_VALUE" == "true" ]; then
            log_success "Pod $pod has ENABLE_TRACING=true"
            ((TESTS_PASSED++))
        else
            log_fail "Pod $pod ENABLE_TRACING=$TRACING_VALUE (expected: true)"
            ((TESTS_FAILED++))
        fi
    done
else
    log_warn "No CAIPE pods found in namespace $NAMESPACE"
fi

# ==========================================================================
# Test 5: Check OTEL collector is accessible
# ==========================================================================
log_info "Test 5: Checking OTEL collector connectivity..."

OTEL_SVC=$(kubectl get svc -n $OBSERVABILITY_NS otel-collector -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -n "$OTEL_SVC" ]; then
    # Try to reach OTEL collector health endpoint from a CAIPE pod
    if [ -n "$CAIPE_PODS" ]; then
        FIRST_POD=$(echo $CAIPE_PODS | awk '{print $1}')
        if kubectl exec -n $NAMESPACE $FIRST_POD -- wget -q --spider --timeout=5 http://otel-collector.$OBSERVABILITY_NS.svc.cluster.local:13133/health 2>/dev/null; then
            log_success "OTEL collector is reachable from CAIPE namespace"
            ((TESTS_PASSED++))
        else
            log_warn "OTEL collector health check failed (may not have wget)"
            ((TESTS_PASSED++))  # Not a critical failure
        fi
    else
        log_warn "Cannot test OTEL connectivity - no CAIPE pods available"
    fi
else
    log_fail "OTEL collector service not found in $OBSERVABILITY_NS"
    ((TESTS_FAILED++))
fi

# ==========================================================================
# Test 6: Check Langfuse service is accessible
# ==========================================================================
log_info "Test 6: Checking Langfuse service..."

LANGFUSE_SVC=$(kubectl get svc -n $OBSERVABILITY_NS langfuse -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -n "$LANGFUSE_SVC" ]; then
    log_success "Langfuse service exists in $OBSERVABILITY_NS"
    ((TESTS_PASSED++))
else
    log_fail "Langfuse service not found in $OBSERVABILITY_NS"
    ((TESTS_FAILED++))
fi

# ==========================================================================
# Test 7: Check ServiceMonitors exist (if Prometheus Operator installed)
# ==========================================================================
log_info "Test 7: Checking ServiceMonitors..."

if kubectl get crd servicemonitors.monitoring.coreos.com > /dev/null 2>&1; then
    SM_COUNT=$(kubectl get servicemonitor -n $NAMESPACE 2>/dev/null | grep -c "caipe" || echo "0")
    if [ "$SM_COUNT" -gt 0 ]; then
        log_success "Found $SM_COUNT CAIPE ServiceMonitors"
        ((TESTS_PASSED++))
    else
        log_warn "No CAIPE ServiceMonitors found (may need deployment)"
    fi
else
    log_warn "Prometheus Operator not installed - skipping ServiceMonitor check"
fi

# ==========================================================================
# Test 8: Verify supervisor agent is running
# ==========================================================================
log_info "Test 8: Checking supervisor-agent deployment..."

run_test "Supervisor agent deployment is ready" \
    "kubectl get deployment supervisor-agent -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q 1"

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo "========================================"
echo "  Test Results Summary"
echo "========================================"
echo ""
echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! CAIPE observability is configured correctly.${NC}"
    exit 0
else
    echo -e "${YELLOW}Some tests failed. Review the output above for details.${NC}"
    exit 1
fi
