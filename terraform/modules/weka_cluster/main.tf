# Weka cluster module — wraps the official weka/weka/aws Terraform Registry module.
#
# Reference: https://github.com/weka/terraform-aws-weka (v1.0.23)
# This is the same module used by github.com/mbookham7/mb-weka-aws-terraform.
#
# Key design decisions for this test environment:
#   - Use caller-provided subnets and security groups (from the networking module)
#   - Disable all protocol gateways (NFS, S3, SMB) — only WekaFS/POSIX needed
#   - Set clients_number=0 — the DevStack node joins as a client separately
#   - Disable VPC endpoints for Secrets Manager to simplify networking
#   - Set data_services_number=0 to reduce cost

module "weka" {
  source  = "weka/weka/aws"
  version = "1.0.23"

  # ── Identity ────────────────────────────────────────────────────────────────
  prefix       = var.prefix
  cluster_name = var.cluster_name

  # ── Compute ─────────────────────────────────────────────────────────────────
  cluster_size               = var.cluster_size
  instance_type              = var.instance_type
  set_dedicated_fe_container = false

  # ── Weka software ───────────────────────────────────────────────────────────
  get_weka_io_token = var.get_weka_io_token
  weka_version      = var.weka_version

  # ── SSH ─────────────────────────────────────────────────────────────────────
  ssh_public_key = var.ssh_public_key
  key_pair_name  = var.key_pair_name

  # ── Networking — use caller-provided subnets and SGs ────────────────────────
  # Provide our pre-created subnet instead of letting the module create one.
  # When subnet_ids is non-empty the module skips VPC/subnet creation.
  subnet_ids = [var.weka_subnet_id]

  # Our pre-created SG with the required self-reference rule.
  # When sg_ids is non-empty the module skips SG creation.
  sg_ids = [var.weka_sg_id]

  # ALB requires a second subnet in a DIFFERENT AZ.
  # Use alb_additional_subnet_id (not cidr_block) since we have a pre-created subnet.
  alb_additional_subnet_id = var.alb_subnet_id
  alb_sg_ids               = [var.alb_sg_id]

  # Admin access CIDRs
  allow_ssh_cidrs      = [var.admin_cidr]
  allow_weka_api_cidrs = [var.admin_cidr]

  # ── ALB ─────────────────────────────────────────────────────────────────────
  create_alb       = true
  assign_public_ip = true

  # ── Secrets Manager — disable VPC endpoints (test env has public IPs) ───────
  secretmanager_use_vpc_endpoint    = false
  secretmanager_create_vpc_endpoint = false

  # ── Disabled features (cost reduction for test environment) ─────────────────
  clients_number               = 0 # DevStack joins as client via user_data
  data_services_number         = 0
  s3_protocol_gateways_number  = 0
  smb_protocol_gateways_number = 0

  # ── NFS protocol gateway ─────────────────────────────────────────────────────
  # Required for Manila NFS scenario tests (TestShareBasicOpsNFS).
  # The gateway runs in the same Weka subnet and serves NFS on port 2049.
  nfs_protocol_gateways_number   = 1
  nfs_protocol_gateway_subnet_id = var.weka_subnet_id

  # ── Tags ────────────────────────────────────────────────────────────────────
  tags_map = var.tags_map
}
