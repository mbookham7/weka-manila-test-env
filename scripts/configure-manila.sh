#!/usr/bin/env bash
# =============================================================================
# configure-manila.sh — Post-deploy Manila configuration helper.
#
# Run this after DevStack completes if you need to reconfigure Manila
# to point to the Weka cluster, e.g. if the password has rotated.
#
# Usage: ./configure-manila.sh <devstack_ip> <ssh_key_path> <weka_backend> <weka_secret_id> <aws_region>
# =============================================================================

set -euo pipefail

DEVSTACK_IP="${1:-${DEVSTACK_IP:-}}"
SSH_KEY="${2:-${SSH_KEY:-}}"
WEKA_BACKEND="${3:-${WEKA_BACKEND:-}}"
WEKA_SECRET_ID="${4:-${WEKA_SECRET_ID:-}}"
AWS_REGION="${5:-${AWS_REGION:-eu-west-1}}"

if [ -z "${DEVSTACK_IP}" ] || [ -z "${SSH_KEY}" ] || [ -z "${WEKA_BACKEND}" ] || [ -z "${WEKA_SECRET_ID}" ]; then
    echo "Usage: $0 <devstack_ip> <ssh_key_path> <weka_backend> <weka_secret_id> [aws_region]"
    echo ""
    echo "Get values from Terraform:"
    echo "  cd terraform"
    echo "  DEVSTACK_IP=\$(terraform output -raw devstack_public_ip)"
    echo "  WEKA_BACKEND=\$(terraform output -raw weka_api_url | sed 's|https://||;s|:14000.*||')"
    echo "  WEKA_SECRET_ID=\$(terraform output -raw weka_secret_id)"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes -o LogLevel=ERROR"

echo "=== Reconfiguring Manila Weka backend ==="
echo "DevStack IP:  ${DEVSTACK_IP}"
echo "Weka backend: ${WEKA_BACKEND}"
echo "Secret ID:    ${WEKA_SECRET_ID}"
echo ""

# Fetch the current Weka password from the instance (it has the IAM role)
WEKA_PASSWORD=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
    "aws secretsmanager get-secret-value \
        --secret-id '${WEKA_SECRET_ID}' \
        --region '${AWS_REGION}' \
        --query 'SecretString' \
        --output text | jq -r '.password // .' 2>/dev/null")

echo "Password fetched (${#WEKA_PASSWORD} characters)"

# Apply configuration
ssh ${SSH_OPTS} -i "${SSH_KEY}" ubuntu@"${DEVSTACK_IP}" \
    "WEKA_BACKEND='${WEKA_BACKEND}' WEKA_PASSWORD='${WEKA_PASSWORD}' bash -s" << 'REMOTE'
set -euo pipefail

MANILA_CONF=/etc/manila/manila.conf

echo "Updating ${MANILA_CONF}..."

sudo crudini --set "${MANILA_CONF}" DEFAULT enabled_share_backends weka
sudo crudini --set "${MANILA_CONF}" weka share_backend_name weka
sudo crudini --set "${MANILA_CONF}" weka share_driver manila.share.drivers.weka.driver.WekaShareDriver
sudo crudini --set "${MANILA_CONF}" weka driver_handles_share_servers False
sudo crudini --set "${MANILA_CONF}" weka weka_api_server "${WEKA_BACKEND}"
sudo crudini --set "${MANILA_CONF}" weka weka_api_port 14000
sudo crudini --set "${MANILA_CONF}" weka weka_username admin
sudo crudini --set "${MANILA_CONF}" weka weka_password "${WEKA_PASSWORD}"
sudo crudini --set "${MANILA_CONF}" weka weka_ssl_verify False
sudo crudini --set "${MANILA_CONF}" weka weka_organization Root
sudo crudini --set "${MANILA_CONF}" weka weka_filesystem_group default
sudo crudini --set "${MANILA_CONF}" weka weka_mount_point_base /mnt/weka
sudo crudini --set "${MANILA_CONF}" weka weka_num_cores 1

echo "Restarting Manila services..."
for svc in devstack@m-shr devstack@m-sch devstack@m-dat devstack@m-api; do
    sudo systemctl restart "${svc}" && echo "  Restarted ${svc}" || echo "  WARNING: Could not restart ${svc}"
done

sleep 5

echo ""
echo "--- Manila service list ---"
source /opt/stack/devstack/openrc admin admin
manila service-list

echo ""
echo "--- Manila pool list ---"
manila pool-list --detail || echo "(No pools yet)"
REMOTE

echo ""
echo "=== Manila reconfiguration complete ==="
