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

# ─── DevStack Instance ───────────────────────────────────────────────────────

module "devstack" {
  source = "./modules/devstack"

  depends_on = [module.weka_cluster]

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  devstack_subnet_id = module.networking.devstack_subnet_id
  devstack_sg_id     = module.networking.devstack_sg_id

  instance_type = var.devstack_instance_type
  key_pair_name = aws_key_pair.main.key_name

  weka_backend            = module.weka_cluster.weka_alb_dns_name
  weka_password_secret_id = module.weka_cluster.weka_password_secret_id
  lambda_status_name      = module.weka_cluster.lambda_status_name

  devstack_branch = var.devstack_branch
  driver_branch   = var.driver_branch
  admin_password  = var.admin_password

  tags = local.common_tags
}
