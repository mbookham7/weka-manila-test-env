#!/usr/bin/env bash
# =============================================================================
# destroy-prep.sh — Safe teardown preparation before terraform destroy.
#
# Must be run BEFORE terraform destroy to:
#   1. Delete all Manila shares (prevents orphaned Weka filesystems)
#   2. Delete all Manila snapshots
#   3. Delete all Manila share types
#   4. Verify clean state
#
# Usage: ./destroy-prep.sh <devstack_ip> <ssh_key_path>
# =============================================================================

set -euo pipefail

DEVSTACK_IP="${1:-${DEVSTACK_IP:-}}"
SSH_KEY="${2:-${SSH_KEY:-}}"

if [ -z "${DEVSTACK_IP}" ] || [ -z "${SSH_KEY}" ]; then
    echo "Usage: $0 <devstack_ip> <ssh_key_path>"
    echo ""
    echo "This script must be run BEFORE 'terraform destroy'."
    echo "It cleanly removes all Manila shares and snapshots."
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes -o LogLevel=ERROR"

echo "=== Pre-destroy cleanup ==="
echo "IP:  ${DEVSTACK_IP}"
echo ""
echo "WARNING: This will DELETE ALL Manila shares and snapshots!"
echo "Press Ctrl+C within 10 seconds to abort..."
sleep 10

if ! ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" "echo ok" 2>/dev/null; then
    echo "Cannot reach DevStack instance — skipping Manila resource cleanup."
    echo "Safe to proceed with terraform destroy."
    exit 0
fi

ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
    "bash -s" << 'REMOTE_CLEANUP'
set -eo pipefail

# If DevStack never completed there are no Manila resources to clean up
if [ ! -f /opt/stack/devstack/openrc ]; then
    echo "DevStack openrc not found — no Manila resources to clean up."
    exit 0
fi

# DevStack's openrc sources functions that use nounset; disable it around the source
set +u
source /opt/stack/devstack/openrc admin admin 2>/dev/null || {
    echo "Could not source DevStack openrc — DevStack incomplete, no Manila resources to clean up."
    exit 0
}
set -u

echo "--- Cleaning up Manila resources ---"

# Delete all access rules first
SHARES=$(manila list --all-tenants --columns ID --format value 2>/dev/null || echo "")
for SHARE_ID in ${SHARES}; do
    ACCESS_IDS=$(manila access-list "${SHARE_ID}" --columns id --format value 2>/dev/null || echo "")
    for ACCESS_ID in ${ACCESS_IDS}; do
        echo "Revoking access rule ${ACCESS_ID} from share ${SHARE_ID}"
        manila access-deny "${SHARE_ID}" "${ACCESS_ID}" 2>/dev/null || true
    done
done

# Delete all share replicas
REPLICAS=$(manila share-replica-list --all-tenants --columns ID --format value 2>/dev/null || echo "")
for REPLICA_ID in ${REPLICAS}; do
    echo "Deleting share replica ${REPLICA_ID}"
    manila share-replica-delete "${REPLICA_ID}" 2>/dev/null || true
done

# Delete all snapshots
SNAPSHOTS=$(manila snapshot-list --all-tenants --columns ID --format value 2>/dev/null || echo "")
for SNAP_ID in ${SNAPSHOTS}; do
    echo "Deleting snapshot ${SNAP_ID}"
    manila snapshot-delete "${SNAP_ID}" 2>/dev/null || true
done

# Wait for snapshots to be deleted
if [ -n "${SNAPSHOTS}" ]; then
    echo "Waiting for snapshots to be deleted..."
    sleep 10
    REMAINING=$(manila snapshot-list --all-tenants --columns Status --format value 2>/dev/null | grep -v "^$" || echo "")
    WAIT=0
    while [ -n "${REMAINING}" ] && [ ${WAIT} -lt 20 ]; do
        WAIT=$((WAIT + 1))
        echo "Still waiting for snapshots... (${WAIT}/20)"
        sleep 10
        REMAINING=$(manila snapshot-list --all-tenants --columns Status --format value 2>/dev/null | grep -v "^$" || echo "")
    done
fi

# Delete all shares
SHARES=$(manila list --all-tenants --columns ID --format value 2>/dev/null || echo "")
for SHARE_ID in ${SHARES}; do
    echo "Deleting share ${SHARE_ID}"
    manila delete "${SHARE_ID}" 2>/dev/null || true
done

# Wait for shares to be deleted
if [ -n "${SHARES}" ]; then
    echo "Waiting for shares to be deleted..."
    sleep 15
    REMAINING=$(manila list --all-tenants --columns Status --format value 2>/dev/null | grep -v "^$" || echo "")
    WAIT=0
    while [ -n "${REMAINING}" ] && [ ${WAIT} -lt 30 ]; do
        WAIT=$((WAIT + 1))
        echo "Still waiting for shares... (${WAIT}/30)"
        sleep 10
        REMAINING=$(manila list --all-tenants --columns Status --format value 2>/dev/null | grep -v "^$" || echo "")
    done
fi

# Final verification
echo ""
echo "--- Final state verification ---"
echo "Shares:"
manila list --all-tenants 2>/dev/null || echo "(none)"
echo "Snapshots:"
manila snapshot-list --all-tenants 2>/dev/null || echo "(none)"

echo ""
echo "Manila resources cleaned up."
REMOTE_CLEANUP

echo ""
echo "=== Pre-destroy cleanup complete ==="
echo ""
echo "Safe to run: cd terraform && terraform destroy -var-file=terraform.tfvars"
