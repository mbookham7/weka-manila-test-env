#!/usr/bin/env bash
# =============================================================================
# wait-for-devstack.sh — Poll until DevStack bootstrap has completed.
#
# Usage: ./wait-for-devstack.sh <devstack_ip> <ssh_key_path>
#
# Arguments:
#   devstack_ip   — Public IP of the DevStack instance
#   ssh_key_path  — Path to the SSH private key file
#
# Environment variables (alternative to positional args):
#   DEVSTACK_IP
#   SSH_KEY
#
# Exit codes:
#   0 — DevStack is ready
#   1 — timed out (75 minutes) or SSH error
# =============================================================================

set -euo pipefail

DEVSTACK_IP="${1:-${DEVSTACK_IP:-}}"
SSH_KEY="${2:-${SSH_KEY:-}}"

if [ -z "${DEVSTACK_IP}" ] || [ -z "${SSH_KEY}" ]; then
    echo "Usage: $0 <devstack_ip> <ssh_key_path>"
    echo ""
    echo "Get the DevStack IP from Terraform:"
    echo "  cd terraform && terraform output devstack_public_ip"
    exit 1
fi

if [ ! -f "${SSH_KEY}" ]; then
    echo "ERROR: SSH key not found: ${SSH_KEY}"
    exit 1
fi

MAX_RETRIES=150  # 150 × 30s = 75 minutes
RETRY=0
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"

echo "=== Waiting for DevStack to complete ==="
echo "IP:      ${DEVSTACK_IP}"
echo "Key:     ${SSH_KEY}"
echo "Timeout: $((MAX_RETRIES * 30 / 60)) minutes"
echo ""

while [ ${RETRY} -lt ${MAX_RETRIES} ]; do
    RETRY=$((RETRY + 1))
    ELAPSED=$(( (RETRY - 1) * 30 ))
    echo -n "[$(date '+%H:%M:%S')] Attempt ${RETRY}/${MAX_RETRIES} (${ELAPSED}s elapsed)... "

    # Check for the completion sentinel file
    if ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
        "test -f /var/log/devstack-complete" 2>/dev/null; then
        echo "COMPLETE ✓"
        echo ""
        echo "=== DevStack bootstrap is complete! ==="

        # Show a quick status summary
        echo ""
        echo "--- Manila service list ---"
        ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
            "source /opt/stack/devstack/openrc admin admin 2>/dev/null && manila service-list 2>/dev/null" \
            || echo "(Manila not yet responding)"

        echo ""
        echo "--- Manila pool list ---"
        ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
            "source /opt/stack/devstack/openrc admin admin 2>/dev/null && manila pool-list --detail 2>/dev/null" \
            || echo "(No pools yet)"

        exit 0
    fi

    # Check for stack.sh failure
    STACK_FAILED=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
        "grep -c '^Error:' /var/log/stack.sh.log 2>/dev/null || echo 0" 2>/dev/null || echo "0")

    if [ "${STACK_FAILED}" -gt "0" ] 2>/dev/null; then
        echo "ERRORS DETECTED in stack.sh log!"
        echo ""
        echo "=== Last 50 lines of stack.sh.log ==="
        ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
            "tail -50 /var/log/stack.sh.log 2>/dev/null" || true
        echo ""
        echo "SSH in and check: ssh ubuntu@${DEVSTACK_IP} -i ${SSH_KEY} 'tail -100 /var/log/stack.sh.log'"
        exit 1
    fi

    # Show current progress from log
    LAST_LINE=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
        "tail -1 /var/log/stack.sh.log 2>/dev/null || echo 'waiting for SSH...'" 2>/dev/null \
        || echo "SSH not ready yet")

    echo "in progress"
    echo "  > ${LAST_LINE}"

    if [ ${RETRY} -lt ${MAX_RETRIES} ]; then
        sleep 30
    fi
done

echo ""
echo "=== TIMEOUT: DevStack did not complete within $((MAX_RETRIES * 30 / 60)) minutes ==="
echo "Troubleshooting:"
echo "  1. SSH in: ssh ubuntu@${DEVSTACK_IP} -i ${SSH_KEY}"
echo "  2. Check bootstrap log: sudo tail -100 /var/log/devstack-bootstrap.log"
echo "  3. Check stack.sh log: tail -100 /var/log/stack.sh.log"
echo "  4. Check screen session: screen -r devstack"
exit 1
