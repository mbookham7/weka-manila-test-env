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

# Run tempest tests on the remote DevStack instance
ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
    "bash -s" << 'REMOTE_SCRIPT'
set -euo pipefail

source /opt/stack/devstack/openrc admin admin

# Ensure tempest is installed and configured
TEMPEST_DIR=/opt/stack/tempest
if [ ! -f "${TEMPEST_DIR}/etc/tempest.conf" ]; then
    echo "ERROR: Tempest not configured. Has DevStack completed?"
    exit 1
fi

cd "${TEMPEST_DIR}"

echo "--- Manila service list ---"
manila service-list

echo ""
echo "--- Manila pool list ---"
manila pool-list --detail

echo ""
echo "--- Available tempest Manila tests ---"
python -m pytest \
    --config-file "${TEMPEST_DIR}/etc/tempest.conf" \
    --collect-only \
    -q \
    -k "TEST_PATTERN_PLACEHOLDER" \
    tempest/api/share/ 2>/dev/null | head -50 || true

echo ""
echo "--- Running Manila tempest tests ---"
python -m pytest \
    --config-file "${TEMPEST_DIR}/etc/tempest.conf" \
    -v \
    -k "TEST_PATTERN_PLACEHOLDER" \
    --tb=short \
    --junitxml=/tmp/manila-tempest-results.xml \
    tempest/api/share/ \
    || true   # Don't fail the script if tests fail — collect results first

echo "Tests complete."
REMOTE_SCRIPT

# Note: sed needed since heredoc can't use variables
ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
    "sed -i 's/TEST_PATTERN_PLACEHOLDER/${TEST_PATTERN}/g' /dev/null" 2>/dev/null || true

# Download results
echo ""
echo "--- Downloading test results ---"
scp ${SSH_OPTS} -i "${SSH_KEY}" \
    "ubuntu@${DEVSTACK_IP}:/tmp/manila-tempest-results.xml" \
    "${RESULTS_DIR}/results.xml" 2>/dev/null || echo "No XML results to download"

scp ${SSH_OPTS} -i "${SSH_KEY}" \
    "ubuntu@${DEVSTACK_IP}:/var/log/stack.sh.log" \
    "${RESULTS_DIR}/stack.sh.log" 2>/dev/null || echo "No stack.sh log to download"

echo ""
echo "=== Results saved to: ${RESULTS_DIR} ==="

# Summary
if [ -f "${RESULTS_DIR}/results.xml" ]; then
    PASSED=$(grep -c 'classname=' "${RESULTS_DIR}/results.xml" || echo 0)
    FAILED=$(grep -c '<failure' "${RESULTS_DIR}/results.xml" || echo 0)
    ERROR_COUNT=$(grep -c '<error' "${RESULTS_DIR}/results.xml" || echo 0)
    echo ""
    echo "Test summary:"
    echo "  Passed: ~$((PASSED - FAILED - ERROR_COUNT))"
    echo "  Failed: ${FAILED}"
    echo "  Errors: ${ERROR_COUNT}"
fi
