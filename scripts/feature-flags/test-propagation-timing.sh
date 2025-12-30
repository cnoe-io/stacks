#!/bin/bash
# T038: Verify flag changes propagate within 30 seconds (SC-004)
#
# This script tests that changes to flag configurations are reflected
# in flag evaluations within the required 30-second propagation window.
#
# Test flow:
# 1. Record current flag value
# 2. Update flag configuration in ConfigMap
# 3. Measure time until flagd returns new value
# 4. Verify propagation time is under 30 seconds
#
# Usage:
#   ./test-propagation-timing.sh [--namespace <namespace>]
#
# Prerequisites:
#   - kubectl configured with cluster access
#   - Ability to edit ConfigMaps

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${FLAGD_NAMESPACE:-feature-flags}"
OFREP_PORT="${FLAGD_OFREP_PORT:-8016}"
MAX_PROPAGATION_SECONDS=30
POLL_INTERVAL_SECONDS=2

# Test flag - using existing flag from ConfigMap
TEST_FLAG="dark-mode"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
log_time() { echo -e "${CYAN}[TIME]${NC} $1"; }

# Parse arguments
SKIP_MUTATION=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift 2 ;;
        --skip-mutation) SKIP_MUTATION=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--namespace <ns>] [--skip-mutation]"
            echo ""
            echo "Options:"
            echo "  --skip-mutation  Skip ConfigMap modification (dry run)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=========================================="
echo "  Flag Propagation Timing Test (T038)"
echo "=========================================="
echo ""
echo "Requirement: SC-004 - Changes propagate within 30 seconds"
echo "Test flag:   ${TEST_FLAG}"
echo "Namespace:   ${NAMESPACE}"
echo ""

# Get flagd pod
FLAGD_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=flagd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "${FLAGD_POD}" ]]; then
    log_error "Could not find flagd pod in namespace ${NAMESPACE}"
    exit 1
fi

# Helper function to get current flag value
get_flag_value() {
    kubectl exec -n "${NAMESPACE}" "${FLAGD_POD}" -- sh -c "
        wget -q -O- --post-data='{\"context\":{\"targetingKey\":\"propagation-test\"}}' \
             --header='Content-Type: application/json' \
             'http://localhost:${OFREP_PORT}/ofrep/v1/evaluate/flags/${TEST_FLAG}' 2>/dev/null
    " | grep -o '"value":[^,}]*' | cut -d: -f2 | tr -d ' '
}

# Helper function to get default variant from ConfigMap
get_configmap_default() {
    kubectl get configmap flagd-config -n "${NAMESPACE}" -o jsonpath='{.data.flagd\.json}' 2>/dev/null | \
        grep -A5 "\"${TEST_FLAG}\"" | grep "defaultVariant" | head -1 | \
        sed 's/.*: *"\([^"]*\)".*/\1/' || echo "unknown"
}

echo "=========================================="
echo "  Test Suite 1: Baseline Measurement"
echo "=========================================="
echo ""

# Test 1.1: Record current state
log_test "1.1: Recording current flag state..."
ORIGINAL_VALUE=$(get_flag_value)
ORIGINAL_VARIANT=$(get_configmap_default)

log_info "Current flag value: ${ORIGINAL_VALUE}"
log_info "Current default variant: ${ORIGINAL_VARIANT}"

if [[ -z "${ORIGINAL_VALUE}" ]] || [[ "${ORIGINAL_VALUE}" == "error" ]]; then
    log_error "Could not get current flag value"
    exit 1
fi

echo ""
echo "=========================================="
echo "  Test Suite 2: Configuration Change"
echo "=========================================="
echo ""

if [[ "${SKIP_MUTATION}" == "true" ]]; then
    log_warn "Skipping ConfigMap mutation (--skip-mutation flag set)"
    log_info "To run full propagation test: $0 --namespace ${NAMESPACE}"
    echo ""

    # Still provide timing analysis for polling interval
    log_test "2.1: Analyzing current sync configuration..."

    # Check flagd config for file source polling
    log_info "flagd uses file-based sync from ConfigMap"
    log_info "File changes are detected via inotify or polling"
    log_info "ConfigMap updates trigger pod config reload"
    echo ""
else
    # Determine target value (toggle the default)
    if [[ "${ORIGINAL_VARIANT}" == "on" ]]; then
        NEW_VARIANT="off"
        EXPECTED_VALUE="false"
    else
        NEW_VARIANT="on"
        EXPECTED_VALUE="true"
    fi

    log_test "2.1: Preparing configuration change..."
    log_info "Changing '${TEST_FLAG}' defaultVariant: ${ORIGINAL_VARIANT} → ${NEW_VARIANT}"
    log_info "Expected new value: ${EXPECTED_VALUE}"
    echo ""

    # Backup current ConfigMap
    log_step "Backing up current ConfigMap..."
    kubectl get configmap flagd-config -n "${NAMESPACE}" -o yaml > /tmp/flagd-config-backup.yaml

    # Create modified ConfigMap data
    log_step "Preparing modified configuration..."
    CURRENT_CONFIG=$(kubectl get configmap flagd-config -n "${NAMESPACE}" -o jsonpath='{.data.flagd\.json}')

    # Update the defaultVariant for our test flag
    MODIFIED_CONFIG=$(echo "${CURRENT_CONFIG}" | sed "s/\"defaultVariant\": \"${ORIGINAL_VARIANT}\"/\"defaultVariant\": \"${NEW_VARIANT}\"/")

    log_test "2.2: Applying configuration change..."
    echo ""
    log_time "START: $(date '+%Y-%m-%d %H:%M:%S.%3N')"
    START_TIME=$(date +%s%N)

    # Apply the change
    kubectl create configmap flagd-config \
        --from-literal="flagd.json=${MODIFIED_CONFIG}" \
        -n "${NAMESPACE}" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_info "ConfigMap updated"

    echo ""
    echo "=========================================="
    echo "  Test Suite 3: Propagation Timing"
    echo "=========================================="
    echo ""

    log_test "3.1: Polling for flag value change..."
    log_info "Max wait time: ${MAX_PROPAGATION_SECONDS} seconds"
    log_info "Poll interval: ${POLL_INTERVAL_SECONDS} seconds"
    echo ""

    PROPAGATION_TIME=0
    DETECTED=false

    # Poll for the change
    while [[ ${PROPAGATION_TIME} -lt ${MAX_PROPAGATION_SECONDS} ]]; do
        CURRENT_VALUE=$(get_flag_value)
        ELAPSED_MS=$(( ($(date +%s%N) - START_TIME) / 1000000 ))
        PROPAGATION_TIME=$(( ELAPSED_MS / 1000 ))

        printf "\r  [%2ds] Current value: %-6s (expecting: %s)" \
            "${PROPAGATION_TIME}" "${CURRENT_VALUE}" "${EXPECTED_VALUE}"

        if [[ "${CURRENT_VALUE}" == "${EXPECTED_VALUE}" ]]; then
            DETECTED=true
            echo ""
            break
        fi

        sleep "${POLL_INTERVAL_SECONDS}"
    done

    echo ""
    END_TIME=$(date +%s%N)
    TOTAL_MS=$(( (END_TIME - START_TIME) / 1000000 ))
    TOTAL_SECONDS=$(( TOTAL_MS / 1000 ))
    TOTAL_MS_REMAINDER=$(( TOTAL_MS % 1000 ))

    log_time "END: $(date '+%Y-%m-%d %H:%M:%S.%3N')"
    echo ""

    if [[ "${DETECTED}" == "true" ]]; then
        log_info "✓ Flag change detected!"
        log_info "  Propagation time: ${TOTAL_SECONDS}.${TOTAL_MS_REMAINDER}s"

        if [[ ${TOTAL_SECONDS} -lt ${MAX_PROPAGATION_SECONDS} ]]; then
            log_info "✓ PASS: Under ${MAX_PROPAGATION_SECONDS}s requirement (SC-004)"
        else
            log_warn "⚠ Propagation time equals max threshold"
        fi
    else
        log_error "✗ FAIL: Flag change not detected within ${MAX_PROPAGATION_SECONDS} seconds"
        log_error "  This violates requirement SC-004"
    fi

    echo ""
    echo "=========================================="
    echo "  Test Suite 4: Restore Configuration"
    echo "=========================================="
    echo ""

    log_test "4.1: Restoring original configuration..."
    kubectl apply -f /tmp/flagd-config-backup.yaml

    log_step "Waiting for restoration to propagate..."
    sleep 5

    RESTORED_VALUE=$(get_flag_value)
    if [[ "${RESTORED_VALUE}" == "${ORIGINAL_VALUE}" ]]; then
        log_info "✓ Original configuration restored"
    else
        log_warn "⚠ Restoration in progress (current: ${RESTORED_VALUE}, expected: ${ORIGINAL_VALUE})"
    fi

    rm -f /tmp/flagd-config-backup.yaml
fi

echo ""
echo "=========================================="
echo "  Propagation Architecture Analysis"
echo "=========================================="
echo ""

cat << 'EOF'
Current flagd sync configuration:

┌─────────────────┐     ┌──────────────────┐     ┌─────────────┐
│    ConfigMap    │────▶│  flagd (file)    │────▶│  Evaluation │
│   flagd-config  │     │  watch/inotify   │     │   Endpoint  │
└─────────────────┘     └──────────────────┘     └─────────────┘

When using file-based sync (current):
- ConfigMap changes trigger kubelet volume update (~10s)
- flagd detects file change via inotify
- Flag values update immediately after file change
- Total expected propagation: 10-15 seconds

When using Flipt sync (alternative):
- Flipt polls Git repository (30s interval configured)
- Changes in Git take up to poll interval
- flagd syncs from Flipt via gRPC
- Total expected propagation: 30-60 seconds

EOF

echo ""
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo ""

log_info "Requirement: SC-004 - Flag changes propagate within 30 seconds"
echo ""
echo "  Current architecture: ConfigMap file-based sync"
echo "  Expected propagation: 10-15 seconds"
echo "  Maximum allowed:      30 seconds"
echo ""

if [[ "${SKIP_MUTATION}" == "true" ]]; then
    log_warn "Full timing test skipped. Run without --skip-mutation to test."
else
    if [[ "${DETECTED}" == "true" ]] && [[ ${TOTAL_SECONDS} -lt ${MAX_PROPAGATION_SECONDS} ]]; then
        log_info "✓ PASS: Propagation timing meets SC-004 requirement"
    else
        log_error "✗ FAIL: Propagation timing does not meet SC-004 requirement"
        exit 1
    fi
fi

echo ""
log_info "Propagation timing test complete"
