#!/usr/bin/env bash
#
# cleanup-stale-machines.sh - Remove stale Tailscale operator machines
#
# This script identifies and removes offline Tailscale machines created by
# operator pod restarts, keeping only the currently active operator instance.
#
# Usage:
#   ./cleanup-stale-machines.sh [--dry-run] [--keep-count N]
#
# Options:
#   --dry-run        Show what would be deleted without actually deleting
#   --keep-count N   Keep N most recent offline machines (default: 0)
#
# Prerequisites:
#   - tailscale CLI installed and authenticated
#   - Appropriate permissions to remove machines from tailnet
#

set -euo pipefail

# Configuration
DRY_RUN=false
KEEP_COUNT=0
OPERATOR_PREFIX="kind-operator"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-count)
            KEEP_COUNT="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--keep-count N]"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "🧹 Tailscale Machine Cleanup"
echo "=========================================="
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE - No machines will be deleted"
    echo ""
fi

# Check if tailscale is installed
if ! command -v tailscale &> /dev/null; then
    log_error "tailscale CLI not found. Please install Tailscale first."
    exit 1
fi

# Check if kubectl is available (optional, for context)
CLUSTER_INFO=""
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    CLUSTER_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
    CLUSTER_INFO=" (current cluster: $CLUSTER_CONTEXT)"
fi

log_info "Scanning for Tailscale machines with prefix: $OPERATOR_PREFIX$CLUSTER_INFO"

# Get all operator machines
ALL_MACHINES=$(tailscale status --json | jq -r '.Peer[] | select(.HostName | startswith("'$OPERATOR_PREFIX'")) | "\(.HostName)|\(.ID)|\(.Online)|\(.TailscaleIPs[0])"' 2>/dev/null || echo "")

if [ -z "$ALL_MACHINES" ]; then
    log_warn "No operator machines found with prefix: $OPERATOR_PREFIX"
    exit 0
fi

# Count machines
TOTAL_COUNT=$(echo "$ALL_MACHINES" | wc -l | tr -d ' ')
ONLINE_COUNT=$(echo "$ALL_MACHINES" | grep "|true|" | wc -l | tr -d ' ')
OFFLINE_COUNT=$(echo "$ALL_MACHINES" | grep "|false|" | wc -l | tr -d ' ')

echo ""
log_info "Found $TOTAL_COUNT operator machines:"
echo "  - Online:  $ONLINE_COUNT"
echo "  - Offline: $OFFLINE_COUNT"
echo ""

# Show all machines
echo "=========================================="
echo "📋 Current Machines:"
echo "=========================================="
echo ""
printf "%-30s %-20s %-10s\n" "HOSTNAME" "IP ADDRESS" "STATUS"
echo "-----------------------------------------------------------"

while IFS='|' read -r hostname id online ip; do
    status="ONLINE"
    if [ "$online" = "false" ]; then
        status="OFFLINE"
    fi
    printf "%-30s %-20s %-10s\n" "$hostname" "$ip" "$status"
done <<< "$ALL_MACHINES"

echo ""

# Identify machines to delete (offline ones)
OFFLINE_MACHINES=$(echo "$ALL_MACHINES" | grep "|false|" || true)

if [ -z "$OFFLINE_MACHINES" ]; then
    log_info "✓ No offline machines to clean up!"
    exit 0
fi

OFFLINE_MACHINE_COUNT=$(echo "$OFFLINE_MACHINES" | wc -l | tr -d ' ')

# Calculate how many to delete
TO_DELETE_COUNT=$((OFFLINE_MACHINE_COUNT - KEEP_COUNT))

if [ $TO_DELETE_COUNT -le 0 ]; then
    log_info "✓ Keeping all $OFFLINE_MACHINE_COUNT offline machines (keep-count=$KEEP_COUNT)"
    exit 0
fi

echo "=========================================="
echo "🗑️  Machines to Delete:"
echo "=========================================="
echo ""

# Sort offline machines by hostname (older numbers first) and select ones to delete
MACHINES_TO_DELETE=$(echo "$OFFLINE_MACHINES" | sort | head -n $TO_DELETE_COUNT)

printf "%-30s %-20s\n" "HOSTNAME" "IP ADDRESS"
echo "-------------------------------------------"

while IFS='|' read -r hostname id online ip; do
    printf "%-30s %-20s\n" "$hostname" "$ip"
done <<< "$MACHINES_TO_DELETE"

echo ""
log_warn "Will delete $TO_DELETE_COUNT offline machine(s)"

if [ $KEEP_COUNT -gt 0 ]; then
    KEPT_COUNT=$((OFFLINE_MACHINE_COUNT - TO_DELETE_COUNT))
    log_info "Keeping $KEPT_COUNT most recent offline machine(s)"
fi

echo ""

# Confirm deletion (unless dry-run)
if [ "$DRY_RUN" = false ]; then
    read -p "Proceed with deletion? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deletion cancelled by user"
        exit 0
    fi
fi

# Delete machines
echo ""
log_step "Removing machines..."
echo ""

DELETED_COUNT=0
FAILED_COUNT=0

while IFS='|' read -r hostname id online ip; do
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete: $hostname ($ip)"
        ((DELETED_COUNT++))
    else
        log_info "Deleting: $hostname ($ip)"
        # Use Tailscale CLI to remove the machine
        # Note: tailscale CLI doesn't have direct machine removal, need to use API
        log_warn "Tailscale CLI doesn't support direct machine removal"
        log_warn "Please use Tailscale admin console: https://login.tailscale.com/admin/machines"
        log_warn "Or use Tailscale API with machine ID: $id"
        ((FAILED_COUNT++))
    fi
done <<< "$MACHINES_TO_DELETE"

echo ""
echo "=========================================="
echo "📊 Summary"
echo "=========================================="
echo ""

if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN: Would have deleted $DELETED_COUNT machine(s)"
    echo ""
    log_info "To actually delete, run without --dry-run flag"
else
    log_warn "Automatic deletion not available via Tailscale CLI"
    echo ""
    log_info "Manual cleanup required:"
    echo ""
    echo "1. Visit Tailscale Admin Console:"
    echo "   https://login.tailscale.com/admin/machines"
    echo ""
    echo "2. Filter for offline machines with prefix: $OPERATOR_PREFIX"
    echo ""
    echo "3. Delete the following machines:"
    while IFS='|' read -r hostname id online ip; do
        echo "   - $hostname ($ip)"
    done <<< "$MACHINES_TO_DELETE"
    echo ""
    log_info "Or use Tailscale API for programmatic deletion:"
    echo "   https://tailscale.com/api#tag/devices/DELETE/device/%7Bid%7D"
fi

echo ""
log_info "Cleanup scan complete! 🎉"
