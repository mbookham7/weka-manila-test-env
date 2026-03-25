#!/usr/bin/env bash
# =============================================================================
# wait-for-weka.sh — Poll until the Weka cluster is clusterized and ready.
#
# Usage: ./wait-for-weka.sh <lambda_function_name> <aws_region>
#
# Arguments:
#   lambda_function_name  Name of the Weka status Lambda (terraform output: weka_secret_id)
#   aws_region            AWS region (e.g. eu-west-1)
#
# Environment variables (alternative to positional args):
#   LAMBDA_FUNCTION_NAME
#   AWS_REGION
#
# Exit codes:
#   0 — cluster is ready
#   1 — timed out (30 minutes)
# =============================================================================

set -euo pipefail

LAMBDA_FUNCTION_NAME="${1:-${LAMBDA_FUNCTION_NAME:-}}"
AWS_REGION="${2:-${AWS_REGION:-eu-west-1}}"

if [ -z "${LAMBDA_FUNCTION_NAME}" ]; then
    echo "Usage: $0 <lambda_function_name> <aws_region>"
    echo ""
    echo "Get the Lambda function name:"
    echo "  cd terraform && terraform output -raw weka_secret_id"
    echo "  OR: aws lambda list-functions --region ${AWS_REGION} --query 'Functions[?contains(FunctionName, \`status\`)].FunctionName'"
    exit 1
fi

MAX_RETRIES=60   # 60 × 30s = 30 minutes
RETRY=0

echo "=== Waiting for Weka cluster to be ready ==="
echo "Lambda: ${LAMBDA_FUNCTION_NAME}"
echo "Region: ${AWS_REGION}"
echo "Timeout: $((MAX_RETRIES * 30 / 60)) minutes"
echo ""

while [ ${RETRY} -lt ${MAX_RETRIES} ]; do
    RETRY=$((RETRY + 1))
    ELAPSED=$(( (RETRY - 1) * 30 ))
    printf "[%s] Attempt %d/%d (%ds elapsed)... " "$(date '+%H:%M:%S')" "${RETRY}" "${MAX_RETRIES}" "${ELAPSED}"

    TMPFILE=$(mktemp)
    RESPONSE=$(aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload '{"type": "progress"}' \
        --region "${AWS_REGION}" \
        --cli-binary-format raw-in-base64-out \
        "${TMPFILE}" 2>/dev/null \
        && cat "${TMPFILE}" \
        || echo '{}')
    rm -f "${TMPFILE}"

    # Check for cluster readiness indicators in the Lambda response
    if echo "${RESPONSE}" | grep -q '"clusterized":true'; then
        echo "READY"
        echo ""
        echo "=== Weka cluster is clusterized and ready! ==="
        echo "Full response: ${RESPONSE}"
        exit 0
    fi

    # Extract and show progress percentage if available
    PROGRESS=$(echo "${RESPONSE}" | grep -oE '"progress":[[:space:]]*[0-9.]+' | grep -oE '[0-9.]+$' | head -1 || echo "?")
    printf "not ready (progress: %s%%)\n" "${PROGRESS}"

    if [ ${RETRY} -lt ${MAX_RETRIES} ]; then
        sleep 30
    fi
done

echo ""
echo "=== TIMEOUT: Weka cluster did not become ready within $((MAX_RETRIES * 30 / 60)) minutes ==="
echo ""
echo "Troubleshooting steps:"
echo "  1. Check Lambda logs in CloudWatch:"
echo "     aws logs tail /aws/lambda/${LAMBDA_FUNCTION_NAME} --region ${AWS_REGION} --since 1h"
echo "  2. Check EC2 instances in the Weka ASG"
echo "  3. Verify the get_weka_io_token is valid at get.weka.io"
echo "  4. Check Terraform outputs: cd terraform && terraform output cluster_helper_commands"
exit 1
