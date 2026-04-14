provider "aws" {
  region = var.aws_region
}

# ─── SSH Key Pair ─────────────────────────────────────────────────────────────
# Single key pair shared by both Weka backends and the DevStack instance.

resource "aws_key_pair" "main" {
  key_name   = local.name_prefix
  public_key = var.ssh_public_key

  tags = local.common_tags
}

# ─── Shared Networking ───────────────────────────────────────────────────────

module "networking" {
  source = "./modules/networking"

  name_prefix           = local.name_prefix
  vpc_cidr              = "10.0.0.0/16"
  weka_subnet_cidr      = "10.0.1.0/24"
  devstack_subnet_cidr  = "10.0.2.0/24"
  alb_subnet_cidr       = "10.0.3.0/24"
  availability_zone     = var.availability_zone
  alb_availability_zone = var.alb_availability_zone
  admin_cidr            = var.admin_cidr
  tags                  = local.common_tags
}

# ─── Weka Cluster ────────────────────────────────────────────────────────────

module "weka_cluster" {
  source = "./modules/weka_cluster"

  depends_on = [module.networking]

  prefix       = var.prefix
  cluster_name = var.cluster_name

  cluster_size  = var.weka_cluster_size
  instance_type = var.weka_instance_type
  weka_version  = var.weka_version

  get_weka_io_token = var.get_weka_io_token
  ssh_public_key    = null # key pair is pre-created; pass name only
  key_pair_name     = aws_key_pair.main.key_name

  weka_subnet_id = module.networking.weka_subnet_id
  alb_subnet_id  = module.networking.alb_subnet_id
  weka_sg_id     = module.networking.weka_sg_id
  alb_sg_id      = module.networking.alb_sg_id

  admin_cidr = var.admin_cidr
  aws_region = var.aws_region
  tags_map   = local.common_tags
}

# ─── External NLB for Weka cluster access ────────────────────────────────────
# The upstream weka/weka/aws module creates an internal ALB only.
# This internet-facing NLB provides external access to the Weka UI (443)
# and REST API (14000) from admin_cidr, using TCP passthrough (no SSL
# termination — the Weka nodes handle their own self-signed certs).

resource "aws_lb" "weka_external" {
  name               = "${local.name_prefix}-ext-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [module.networking.weka_subnet_id, module.networking.alb_subnet_id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ext-nlb" })
}

resource "aws_lb_target_group" "weka_ui_external" {
  name_prefix = "wkui-"
  port        = 14000
  protocol    = "TCP"
  vpc_id      = module.networking.vpc_id

  health_check {
    protocol            = "TCP"
    port                = 14000
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "weka_api_external" {
  name_prefix = "wkapi-"
  port        = 14000
  protocol    = "TCP"
  vpc_id      = module.networking.vpc_id

  health_check {
    protocol            = "TCP"
    port                = 14000
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "weka_ui_external" {
  load_balancer_arn = aws_lb.weka_external.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weka_ui_external.arn
  }
}

resource "aws_lb_listener" "weka_api_external" {
  load_balancer_arn = aws_lb.weka_external.arn
  port              = 14000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weka_api_external.arn
  }
}

resource "aws_autoscaling_attachment" "weka_ui_external" {
  autoscaling_group_name = module.weka_cluster.asg_name
  lb_target_group_arn    = aws_lb_target_group.weka_ui_external.arn
}

resource "aws_autoscaling_attachment" "weka_api_external" {
  autoscaling_group_name = module.weka_cluster.asg_name
  lb_target_group_arn    = aws_lb_target_group.weka_api_external.arn
}

# ─── NFS Gateway NLB ─────────────────────────────────────────────────────────
# An internal NLB that forwards NFS (TCP 2049) traffic to the Weka NFS protocol
# gateway instance. This gives the Manila driver a stable hostname to use as
# the NFS server in share export locations (weka_nfs_server in manila.conf).
# The Weka ALB handles REST API traffic (port 14000) — NFS cannot be added to
# an ALB because ALBs only support HTTP/HTTPS listeners.

data "aws_instances" "nfs_gateways" {
  depends_on = [module.weka_cluster]

  filter {
    name   = "tag:Name"
    values = [module.weka_cluster.nfs_gateway_name]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

resource "aws_lb" "weka_nfs_internal" {
  name               = "${local.name_prefix}-nfs-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [module.networking.weka_subnet_id]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nfs-nlb" })
}

resource "aws_lb_target_group" "weka_nfs" {
  name_prefix = "wknfs-"
  port        = 2049
  protocol    = "TCP"
  vpc_id      = module.networking.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = 2049
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_lb_target_group_attachment" "weka_nfs" {
  count            = 1
  target_group_arn = aws_lb_target_group.weka_nfs.arn
  target_id        = data.aws_instances.nfs_gateways.ids[count.index]
  port             = 2049
}

resource "aws_lb_listener" "weka_nfs_internal" {
  load_balancer_arn = aws_lb.weka_nfs_internal.arn
  port              = 2049
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weka_nfs.arn
  }
}

# ─── DevStack Instance ───────────────────────────────────────────────────────

# ─── VPC route: Nova VM floating IPs → DevStack instance ─────────────────────
# Nova VMs get floating IPs in 10.0.4.0/24 (within VPC CIDR — avoids MASQUERADE).
# Return traffic from the Weka NFS gateway must be routed back through the
# DevStack instance (which has source/destination check disabled).
resource "aws_route" "devstack_floating_ips" {
  route_table_id         = module.networking.main_route_table_id
  destination_cidr_block = "10.0.4.0/24"
  network_interface_id   = module.devstack.devstack_eni_id

  depends_on = [module.devstack]
}

module "devstack" {
  source = "./modules/devstack"

  depends_on = [module.weka_cluster, aws_lb_listener.weka_nfs_internal]

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  devstack_subnet_id = module.networking.devstack_subnet_id
  devstack_sg_id     = module.networking.devstack_sg_id

  instance_type = var.devstack_instance_type
  key_pair_name = aws_key_pair.main.key_name

  weka_backend            = module.weka_cluster.weka_alb_dns_name
  # Use the NFS gateway's direct private IP rather than the NLB hostname.
  # The NLB is TCP-only and does not respond to ICMP; Manila tempest scenario
  # tests call ping_to_export_location() which pings the NFS server before
  # mounting. The gateway instance itself responds to ICMP (with the ICMP
  # ingress rule now added to the Weka SG for vpc_cidr).
  weka_nfs_server         = data.aws_instances.nfs_gateways.private_ips[0]
  weka_password_secret_id = module.weka_cluster.weka_password_secret_id
  lambda_status_name      = module.weka_cluster.lambda_status_name

  devstack_branch = var.devstack_branch
  driver_branch   = var.driver_branch
  admin_password  = var.admin_password

  tags = local.common_tags
}
