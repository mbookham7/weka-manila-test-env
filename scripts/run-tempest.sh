#!/usr/bin/env bash
# =============================================================================
# run-tempest.sh — Run Manila tempest tests against the Weka backend.
#
# Usage: ./run-tempest.sh <devstack_ip> <ssh_key_path> [test_pattern]
#
# Arguments:
#   devstack_ip   — Public IP of the DevStack instance
#   ssh_key_path  — Path to the SSH private key file
#   test_pattern  — Optional pytest -k pattern (default: "share")
#
# Results are saved to ./results/tempest-<timestamp>/
# =============================================================================

set -euo pipefail

DEVSTACK_IP="${1:-${DEVSTACK_IP:-}}"
SSH_KEY="${2:-${SSH_KEY:-}}"
TEST_PATTERN="${3:-share}"

if [ -z "${DEVSTACK_IP}" ] || [ -z "${SSH_KEY}" ]; then
    echo "Usage: $0 <devstack_ip> <ssh_key_path> [test_pattern]"
    exit 1
fi

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
RESULTS_DIR="$(pwd)/results/tempest-${TIMESTAMP}"
mkdir -p "${RESULTS_DIR}"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes -o LogLevel=ERROR"

echo "=== Running Manila tempest tests ==="
echo "IP:      ${DEVSTACK_IP}"
echo "Pattern: ${TEST_PATTERN}"
echo "Results: ${RESULTS_DIR}"
echo ""

# Run tempest tests on the remote DevStack instance.
# TEST_PATTERN is passed as an argument ($1) to the remote script so the
# heredoc can remain single-quoted (preventing unwanted local expansion of
# shell variables that only exist on the remote host).
ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
    "bash -s" "${TEST_PATTERN}" << 'REMOTE_SCRIPT'
set -eo pipefail

TEST_PATTERN="${1:-share}"

# DevStack's openrc sources functions that use unbound variables — disable -u
set +u
source /opt/stack/devstack/openrc admin admin
set -u

# Ensure tempest is installed and configured
TEMPEST_DIR=/opt/stack/tempest
if [ ! -f "${TEMPEST_DIR}/etc/tempest.conf" ]; then
    echo "ERROR: Tempest not configured. Has DevStack completed?"
    exit 1
fi

cd "${TEMPEST_DIR}"

# Use the DevStack virtualenv — system 'python' is not available on Ubuntu 24.04
VENV=/opt/stack/data/venv
export PATH="${VENV}/bin:${PATH}"

echo "--- Manila service list ---"
manila service-list

echo ""
echo "--- Manila pool list ---"
manila pool-list --detail

echo ""
echo "--- Running Manila tempest tests ---"
# stestr is the test runner used by DevStack / tempest
stestr run --concurrency 2 "${TEST_PATTERN}" || true

echo ""
echo "--- Test summary ---"
stestr last 2>/dev/null || true

echo "Tests complete."
REMOTE_SCRIPT

# Download results
echo ""
echo "--- Downloading test results ---"
scp ${SSH_OPTS} -i "${SSH_KEY}" \
    "ubuntu@${DEVSTACK_IP}:/var/log/stack.sh.log" \
    "${RESULTS_DIR}/stack.sh.log" 2>/dev/null || echo "No stack.sh log to download"

echo ""
echo "=== Results saved to: ${RESULTS_DIR} ==="
