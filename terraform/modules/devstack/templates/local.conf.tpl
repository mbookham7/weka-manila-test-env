# =============================================================================
# DevStack local.conf reference template for Manila + Weka driver
#
# This file documents the local.conf configuration. The actual local.conf
# is generated at instance boot time by userdata.sh with the Weka password
# fetched dynamically from AWS Secrets Manager.
#
# Template variables:
#   weka_backend    = DNS name of the Weka ALB (e.g. weka-test-manila-dev-alb-xxxx.eu-west-1.elb.amazonaws.com)
#   weka_password   = Weka admin password (fetched from Secrets Manager at runtime)
#   admin_password  = OpenStack admin password
#   host_ip         = Private IP of the DevStack instance (from EC2 metadata)
#   devstack_branch = DevStack git branch (e.g. stable/2024.2)
#   driver_branch   = Manila Weka driver branch (e.g. main)
# =============================================================================

[[local|localrc]]
# ── Credentials ──────────────────────────────────────────────────────────────
ADMIN_PASSWORD=${admin_password}
DATABASE_PASSWORD=${admin_password}
RABBIT_PASSWORD=${admin_password}
SERVICE_PASSWORD=${admin_password}

# ── Network ───────────────────────────────────────────────────────────────────
HOST_IP=${host_ip}

# ── Paths ─────────────────────────────────────────────────────────────────────
DEST=/opt/stack
DATA_DIR=/opt/stack/data

# ── Neutron: force ML2/OVS (OVN is now default but incompatible with q-agt) ──
Q_AGENT=openvswitch
Q_ML2_PLUGIN_MECHANISM_DRIVERS=openvswitch
Q_ML2_PLUGIN_TYPE_DRIVERS=flat,vlan,vxlan,geneve

# ── Services ──────────────────────────────────────────────────────────────────
disable_all_services

# Core infrastructure
enable_service key mysql rabbit

# Nova
enable_service n-api n-cpu n-cond n-sch n-api-meta placement-api

# Neutron (ML2/OVS)
enable_service neutron q-svc q-agt q-dhcp q-l3 q-meta

# Glance
enable_service g-api

# Manila
enable_service manila m-api m-shr m-sch m-dat

# Tempest
enable_service tempest

# Horizon disabled (saves ~5 minutes of setup)
disable_service horizon

# ── Plugins ───────────────────────────────────────────────────────────────────
enable_plugin manila https://opendev.org/openstack/manila ${devstack_branch}
enable_plugin manila-weka-driver https://github.com/mbookham7/manila-weka-driver ${driver_branch}
enable_plugin manila-tempest-plugin https://opendev.org/openstack/manila-tempest-plugin

# ── Manila configuration ──────────────────────────────────────────────────────
MANILA_ENABLED_BACKENDS=weka
MANILA_SERVICE_IMAGE_ENABLED=False
MANILA_CONFIGURE_DEFAULT_TYPES=True
MANILA_DEFAULT_SHARE_TYPE=weka
MANILA_ALLOW_NAS_SERVER_PORTS_ON_HOST=True

# Weka backend — all options prefixed MANILA_OPTGROUP_weka_
MANILA_OPTGROUP_weka_share_backend_name=weka
MANILA_OPTGROUP_weka_share_driver=manila.share.drivers.weka.driver.WekaShareDriver
MANILA_OPTGROUP_weka_driver_handles_share_servers=False
MANILA_OPTGROUP_weka_snapshot_support=True
MANILA_OPTGROUP_weka_create_share_from_snapshot_support=True
MANILA_OPTGROUP_weka_revert_to_snapshot_support=True
MANILA_OPTGROUP_weka_weka_api_server=${weka_backend}
MANILA_OPTGROUP_weka_weka_api_port=14000
MANILA_OPTGROUP_weka_weka_username=admin
MANILA_OPTGROUP_weka_weka_password=${weka_password}
MANILA_OPTGROUP_weka_weka_ssl_verify=False
MANILA_OPTGROUP_weka_weka_organization=Root
MANILA_OPTGROUP_weka_weka_filesystem_group=default
MANILA_OPTGROUP_weka_weka_mount_point_base=/mnt/weka
MANILA_OPTGROUP_weka_weka_num_cores=1

# ── Logging ───────────────────────────────────────────────────────────────────
LOGFILE=/var/log/stack.sh.log
LOGDAYS=2
VERBOSE=True
LOG_COLOR=False

# ── Post-config: direct INI injection into manila.conf ────────────────────────
[[post-config|/etc/manila/manila.conf]]
[DEFAULT]
enabled_share_backends = weka
enabled_share_protocols = NFS,CIFS,WEKAFS

[weka]
share_backend_name = weka
share_driver = manila.share.drivers.weka.driver.WekaShareDriver
driver_handles_share_servers = False
snapshot_support = True
create_share_from_snapshot_support = True
revert_to_snapshot_support = True
weka_api_server = ${weka_backend}
weka_api_port = 14000
weka_username = admin
weka_password = ${weka_password}
weka_ssl_verify = False
weka_organization = Root
weka_filesystem_group = default
weka_mount_point_base = /mnt/weka
weka_num_cores = 1
weka_api_timeout = 30
weka_max_api_retries = 3
