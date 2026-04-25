# Weka Manila Test Environment

Terraform-based AWS test environment for end-to-end testing of the
[Manila Weka driver](https://github.com/mbookham7/manila-weka-driver) against
a real Weka storage cluster.

**Guides:**
- [Demo: POSIX Share Lifecycle](docs/demo-posix-share-lifecycle.md) — create, extend, shrink and delete a share via the Manila CLI

## Architecture

```
[Your Laptop / CI Runner]
         │
         │  SSH / OpenStack API / Weka UI
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  AWS VPC  10.0.0.0/16                      (eu-west-1)          │
│                                                                   │
│  ┌── Weka Subnet 10.0.1.0/24 (eu-west-1b) ──────────────────┐  │
│  │                                                             │  │
│  │   ┌────────────┐  ┌────────────┐  ┌────────────┐          │  │
│  │   │i3en.2xlarge│  │i3en.2xlarge│  │i3en.2xlarge│   × 6    │  │
│  │   │  Weka Node │  │  Weka Node │  │  Weka Node │  nodes   │  │
│  │   └─────┬──────┘  └─────┬──────┘  └─────┬──────┘          │  │
│  │         └───────────────┴───────────────┘                   │  │
│  │                         │ WekaFS cluster fabric              │  │
│  └─────────────────────────┼───────────────────────────────────┘  │
│                            │                                       │
│  ┌── ALB Subnet 10.0.3.0/24 (eu-west-1c) ─────────────────────┐  │
│  │   [Application Load Balancer — port 443 (UI) + 14000 (API)] │  │
│  └────────────────────────┬────────────────────────────────────┘  │
│                            │ HTTPS :14000 REST API                 │
│  ┌── DevStack Subnet 10.0.2.0/24 (eu-west-1b) ────────────────┐  │
│  │                                                               │  │
│  │   ┌─────────────────────────────────────────────────────┐    │  │
│  │   │  m5.4xlarge  DevStack Host  (Ubuntu 22.04)           │    │  │
│  │   │                                                       │    │  │
│  │   │  ┌─────────────────────────────────────────────┐     │    │  │
│  │   │  │  OpenStack Services                          │     │    │  │
│  │   │  │   • Keystone  :5000                          │     │    │  │
│  │   │  │   • Nova      (compute)                      │     │    │  │
│  │   │  │   • Neutron   (networking)                   │     │    │  │
│  │   │  │   • Glance    (images)                       │     │    │  │
│  │   │  │   • Manila    :8786  ─────────────────────── │ ─── │ ──►│  │
│  │   │  └─────────────────────────────────────────────┘     │    │  │
│  │   │                                                       │    │  │
│  │   │  ┌──────────────────────┐  ┌─────────────────────┐   │    │  │
│  │   │  │ Manila Weka Driver   │  │ WekaFS POSIX Client  │   │    │  │
│  │   │  │ ─────────────────── │  │ ─────────────────── │   │    │  │
│  │   │  │ REST API → Weka ALB │  │ mount -t wekafs      │   │    │  │
│  │   │  │ port 14000           │  │ /mnt/weka/<share>    │   │    │  │
│  │   │  └──────────────────────┘  └─────────────────────┘   │    │  │
│  │   └─────────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

**Data flows:**
- Manila → Weka REST API via ALB on port 14000 (share/snapshot CRUD, quota management)
- Manila → WekaFS POSIX client on the DevStack host (filesystem mounts for share access)
- Test clients → Manila API on port 8786

## Prerequisites

### AWS
- AWS credentials with permissions for: EC2, VPC, IAM, Lambda, DynamoDB,
  Secrets Manager, CloudWatch, Step Functions, S3, Auto Scaling
- The Weka module creates Lambda functions, DynamoDB tables, IAM roles,
  and Step Functions — ensure your IAM user/role has those permissions

### Software
- [Terraform](https://terraform.io) >= 1.4.6
- AWS CLI v2 (configured with credentials)
- `jq` (for helper scripts)

### Weka
- A [get.weka.io](https://get.weka.io) token (request from your Weka representative)
- This token is used to download the Weka software during cluster bootstrap

### SSH
- An SSH key pair (local file + AWS key pair, or just a public key string)
- Your public IP address for `admin_cidr`

## Quick Start

### 1. Configure

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` and fill in:

```hcl
# REQUIRED
get_weka_io_token = "your-token-from-get.weka.io"
ssh_public_key    = "ssh-rsa AAAA..."      # contents of ~/.ssh/id_rsa.pub
admin_cidr        = "203.0.113.5/32"       # your public IP: curl ifconfig.me

# OPTIONAL — adjust for your region
aws_region            = "eu-west-1"
availability_zone     = "eu-west-1b"
alb_availability_zone = "eu-west-1c"
```

### 2. Deploy

```bash
make init
make apply
```

Terraform will provision:
- VPC with 3 subnets across 2 AZs
- 6× i3en.2xlarge Weka backend nodes + ALB
- 1× m5.4xlarge DevStack host (bootstraps automatically via cloud-init)

> The bootstrap script waits for the Weka cluster to fully clusterize, then
> automatically deletes the default Weka filesystem (which otherwise consumes
> all cluster capacity) before starting DevStack.

### 3. Wait for readiness

```bash
make wait SSH_KEY=~/.ssh/id_rsa
```

This runs both:
- `wait-for-weka.sh` — polls the Weka status Lambda until cluster is clusterized (~20 min)
- `wait-for-devstack.sh` — polls until `/var/log/devstack-complete` appears (~40 min)

### 4. Verify

```bash
# SSH into DevStack
make ssh SSH_KEY=~/.ssh/id_rsa

# Inside the instance:
source /opt/stack/devstack/openrc admin admin
manila service-list
manila pool-list --detail
```

Expected `manila service-list` output:
```
+----+-----------+-------+--------+...
| Id | Binary    | Host  | Status |...
+----+-----------+-------+--------+...
|  1 | manila-shr| ...   | up     |...
|  2 | manila-sch| ...   | up     |...
+----+-----------+-------+--------+...
```

Expected `manila pool-list --detail` output:
```
+------+----------+-----------+...
| Name | Backend  | Driver    |...
+------+----------+-----------+...
| weka | weka     | WekaShare |...
+------+----------+-----------+...
```

## Cost Estimate

| Component | Instance | Count | Price/hr (eu-west-1) | Subtotal |
|-----------|----------|-------|----------------------|----------|
| Weka nodes | i3en.2xlarge | 6 | ~$0.624 | ~$3.74/hr |
| DevStack | m5.4xlarge | 1 | ~$0.768 | ~$0.77/hr |
| ALB | — | 1 | ~$0.025 | ~$0.03/hr |
| EBS volumes | gp3 | ~7 | ~$0.01 | ~$0.07/hr |
| **Total** | | | | **~$4.61/hr** |

> Prices approximate as of early 2025. Check the [AWS pricing calculator](https://calculator.aws) for current rates.
>
> **Tip:** Stop instances when not testing. The Weka cluster must be running to re-join after stop.

## Verifying the Setup

### Check Weka cluster

```bash
# Get Weka admin password
aws secretsmanager get-secret-value \
  --secret-id $(cd terraform && terraform output -raw weka_secret_id) \
  --region eu-west-1 --query SecretString --output text

# Access Weka UI
open $(cd terraform && terraform output -raw weka_ui_url)
```

### Check Manila + Weka driver

```bash
make ssh SSH_KEY=~/.ssh/id_rsa

# Inside DevStack:
source /opt/stack/devstack/openrc admin admin

# List services
manila service-list

# List backend pools (should show NFS and WEKAFS protocols)
manila pool-list --detail

# Create share types (one per protocol)
manila type-create weka_nfs false --extra-specs share_backend_name=weka
manila type-create weka_wekafs false --extra-specs share_backend_name=weka

# Create test shares
manila create --share-type weka_nfs --name test-nfs NFS 1
manila create --share-type weka_wekafs --name test-wekafs WEKAFS 1

# Wait for available status
manila list

# Grant access (NFS only — WEKAFS access rules are rejected; see note below)
manila access-allow test-nfs ip 10.0.0.0/8 --access-level rw

# List access rules
manila access-list test-nfs

# Check export locations
manila share-export-location-list test-nfs
manila share-export-location-list test-wekafs
```

> **WEKAFS access rules:** `manila access-allow` on a WEKAFS share will return
> `error` state. Access control for WEKAFS shares is managed via Weka's own
> authentication layer (filesystem `auth_required` and mount tokens), not via
> Manila access rules. Use network-level controls (VPC security groups) for
> WEKAFS share security. See
> [Known Issues §6](https://github.com/mbookham7/manila-weka-driver/blob/main/docs/known-issues.md#6-wekafs-shares-do-not-support-manila-access-rules).

Both `NFS` and `WEKAFS` protocols are supported by the driver. The driver
automatically patches Manila's `SUPPORTED_SHARE_PROTOCOLS` to add `WEKAFS`
during DevStack setup.

> **Note:** `WEKAFS` protocol shares require the WekaFS kernel module to be
> loaded on the Manila host. This environment uses Ubuntu 22.04 (kernel 5.15)
> which is fully compatible with the WekaFS module. Do not upgrade to Ubuntu
> 24.04 until Weka supports kernel 6.17+. See
> [Known Issues](https://github.com/mbookham7/manila-weka-driver/blob/main/docs/known-issues.md)
> for details.

### Mount the share (WekaFS POSIX)

```bash
# Get the export location from above
EXPORT_LOCATION="<weka-backend>/<filesystem-name>"

# Mount using WekaFS kernel module
sudo mount -t wekafs "${EXPORT_LOCATION}" /mnt/test \
  -o num_cores=1

# Verify
df -h /mnt/test
ls /mnt/test
```

## Running Tests

```bash
# Run Manila tempest API tests
make test SSH_KEY=~/.ssh/id_rsa

# Results are saved to ./results/tempest-<timestamp>/
```

Manual tempest run inside DevStack:

```bash
source /opt/stack/devstack/openrc admin admin
cd /opt/stack/tempest

# List available Manila tests
python -m pytest --collect-only -q tempest/api/share/ 2>/dev/null | grep manila

# Run all Manila API tests
python -m pytest \
  --config-file etc/tempest.conf \
  -v \
  -k "share" \
  tempest/api/share/

# Run a specific test
python -m pytest \
  --config-file etc/tempest.conf \
  -v \
  tempest/api/share/test_shares.py::SharesNFSTest::test_create_get_delete_share
```

## Teardown

**Always** clean up Manila resources before destroying infrastructure:

```bash
# Step 1: Delete all Manila shares/snapshots (prevents orphaned Weka filesystems)
make destroy-prep SSH_KEY=~/.ssh/id_rsa

# Step 2: Destroy infrastructure
make destroy SSH_KEY=~/.ssh/id_rsa
```

Or manually:

```bash
cd terraform
terraform destroy -var-file=../terraform.tfvars
```

## DevStack Plugin for the Driver Repo

The `enable_plugin manila-weka-driver ...` directive in `local.conf` requires
`devstack/plugin.sh` and `devstack/settings` to exist in the
`mbookham7/manila-weka-driver` GitHub repository.

These files are provided in `driver-devstack/` in this repo and are already
present in the `mbookham7/manila-weka-driver` GitHub repository under
`devstack/plugin.sh` and `devstack/settings`.

If you fork the driver repo, copy them across before deploying:

```bash
cd /path/to/manila-weka-driver
mkdir -p devstack
cp /path/to/weka-manila-test-env/driver-devstack/plugin.sh devstack/
cp /path/to/weka-manila-test-env/driver-devstack/settings devstack/
git add devstack/
git commit -m "Add DevStack plugin for CI integration"
git push
```

Until the plugin files exist in the driver repo, the DevStack bootstrap will
fail at the `enable_plugin manila-weka-driver` step.

## Troubleshooting

### Weka cluster not clusterizing

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/<lambda-name> --region eu-west-1 --since 2h

# Check the status Lambda directly
cd terraform && terraform output cluster_helper_commands

# Check EC2 instance status in AWS console
# Look for: Auto Scaling Group → Activity → failed launches
```

**Common causes:**
- Invalid `get_weka_io_token` — verify at [get.weka.io](https://get.weka.io)
- Security group missing self-reference rule (already handled by this module)
- Instance type not available in the chosen AZ — try a different AZ
- IAM permissions insufficient for Lambda, DynamoDB, or Secrets Manager

### DevStack failing

```bash
# Stream bootstrap log
make bootstrap-logs SSH_KEY=~/.ssh/id_rsa

# Stream stack.sh log
make logs SSH_KEY=~/.ssh/id_rsa

# SSH in and check
make ssh SSH_KEY=~/.ssh/id_rsa
tail -100 /var/log/stack.sh.log
screen -r devstack  # Attach to the running stack.sh session
```

**Common causes:**
- Insufficient RAM (`m5.4xlarge` minimum; try `m5.8xlarge` if OOM)
- Network issues downloading packages — check egress SG rules
- DevStack branch incompatible with driver — try `master` branch

### Manila can't reach Weka

```bash
# Check Manila can reach the Weka API
ssh -i ~/.ssh/id_rsa ubuntu@<devstack_ip>
curl -sk https://<weka_alb_dns>:14000/api/v2/cluster

# Check Manila configuration
sudo cat /etc/manila/manila.conf | grep -A 20 '\[weka\]'

# Re-apply Manila config
make reconfigure-manila SSH_KEY=~/.ssh/id_rsa
```

**Common causes:**
- Security group not allowing TCP 14000 from DevStack subnet to Weka (handled by this module)
- Wrong `weka_api_server` — should be the ALB DNS name, not a node IP
- TLS certificate verification failing — ensure `weka_ssl_verify = False` for test env

### WekaFS kernel module not loading

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<devstack_ip>

# Check if module is loaded
lsmod | grep wekafs
cat /proc/filesystems | grep weka

# Try loading manually
sudo modprobe wekafs

# Check Weka agent status
weka status
weka local status
```

**Common causes:**
- Weka agent install failed (cluster not ready when bootstrap ran)
- Kernel 6.17+ — the WekaFS kernel module does not compile against Linux
  kernel 6.17+ due to a breaking `inode_operations.mkdir` return type change.
  The bootstrap script pins the kernel to prevent this, but if the AMI
  already ships with kernel ≥ 6.17 the pin has no effect.
  See [Known Issues](https://github.com/mbookham7/manila-weka-driver/blob/main/docs/known-issues.md#1-wekafs-kernel-module-incompatible-with-linux-kernel-617).
- Weka agent version mismatch with cluster version

To reinstall the agent:
```bash
curl -sk https://<weka_alb_dns>:14000/dist/v1/install | bash
sudo modprobe wekafs
```

## Directory Structure

```
weka-manila-test-env/
├── README.md                           This file
├── .gitignore                          Excludes state, .tfvars, .pem files
├── Makefile                            Convenience targets
├── driver-devstack/                    DevStack plugin for the driver repo
│   ├── plugin.sh                       DevStack plugin (push to manila-weka-driver/devstack/)
│   └── settings                        DevStack settings (push to manila-weka-driver/devstack/)
├── terraform/
│   ├── main.tf                         Root module — wires everything together
│   ├── variables.tf                    All input variables with descriptions
│   ├── outputs.tf                      All operationally useful outputs
│   ├── versions.tf                     Provider version constraints
│   ├── locals.tf                       Computed locals and name prefixes
│   ├── terraform.tfvars.example        Example config — copy to terraform.tfvars
│   └── modules/
│       ├── networking/                 Shared VPC, subnets, security groups
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── weka_cluster/               Weka cluster (wraps weka/weka/aws Registry module)
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── devstack/                   DevStack EC2 instance with full bootstrapping
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── templates/
│               ├── userdata.sh.tpl     Cloud-init bootstrap script
│               └── local.conf.tpl      DevStack local.conf reference template
└── scripts/
    ├── wait-for-weka.sh                Polls Weka Lambda until cluster ready
    ├── wait-for-devstack.sh            Polls DevStack until bootstrap complete
    ├── configure-manila.sh             Re-applies Manila Weka configuration
    ├── run-tempest.sh                  Runs Manila tempest test suite
    └── destroy-prep.sh                 Cleans up Manila resources before destroy
```

## Security Notes

- **Never commit `terraform.tfvars`** — it contains your get.weka.io token and passwords
- The Weka admin password is generated by Terraform, stored in AWS Secrets Manager,
  and fetched at instance boot time — it is never stored in Terraform state in plaintext
- The DevStack `admin_password` IS stored in Terraform state (marked sensitive)
  and is also written to `local.conf` on the instance — this is acceptable for a
  **test environment only**
- For production use, rotate all credentials after testing and destroy the environment
- The `admin_cidr` should be your specific IP (`curl ifconfig.me`), not `0.0.0.0/0`
