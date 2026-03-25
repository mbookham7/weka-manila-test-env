# ─── Required variables (no defaults) ───────────────────────────────────────

variable "get_weka_io_token" {
  description = "Token for downloading Weka software from get.weka.io. Request at https://get.weka.io."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key string (e.g. the contents of ~/.ssh/id_rsa.pub) for EC2 instances."
  type        = string
}

variable "admin_cidr" {
  description = "Your public IP address in CIDR notation for SSH and admin access (e.g. 1.2.3.4/32)."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block (e.g. 1.2.3.4/32)."
  }
}

# ─── AWS region / AZ ─────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "availability_zone" {
  description = "Primary availability zone for Weka backends and DevStack (must be in aws_region)."
  type        = string
  default     = "eu-west-1a"
}

variable "alb_availability_zone" {
  description = "Secondary availability zone for the Weka ALB second subnet (must differ from availability_zone)."
  type        = string
  default     = "eu-west-1b"
}

# ─── Naming ───────────────────────────────────────────────────────────────────

variable "prefix" {
  description = "Resource name prefix applied to all created AWS resources."
  type        = string
  default     = "weka-test"
}

variable "cluster_name" {
  description = "Weka cluster name. Used in resource names and tags."
  type        = string
  default     = "manila-dev"
}

# ─── Weka cluster sizing ─────────────────────────────────────────────────────

variable "weka_cluster_size" {
  description = "Number of Weka backend EC2 instances. Minimum 6 for a production-like cluster."
  type        = number
  default     = 6
}

variable "weka_instance_type" {
  description = "EC2 instance type for Weka backend nodes. i3en.2xlarge provides local NVMe storage."
  type        = string
  default     = "i3en.2xlarge"
}

variable "weka_version" {
  description = "Weka software version to deploy. Must match a version available for your get_weka_io_token."
  type        = string
  default     = "4.4.10.196"
}

# ─── DevStack sizing ──────────────────────────────────────────────────────────

variable "devstack_instance_type" {
  description = "EC2 instance type for the DevStack host. Requires ≥8 vCPU and ≥32 GB RAM."
  type        = string
  default     = "m5.4xlarge"
}

variable "devstack_branch" {
  description = "OpenStack DevStack git branch to check out (e.g. stable/2024.2)."
  type        = string
  default     = "stable/2024.2"
}

variable "driver_branch" {
  description = "Manila Weka driver git branch to use when cloning mbookham7/manila-weka-driver."
  type        = string
  default     = "main"
}

# ─── Credentials / secrets ───────────────────────────────────────────────────

variable "admin_password" {
  description = "Password for the OpenStack admin user, RabbitMQ, and MariaDB in DevStack."
  type        = string
  default     = "WekaM@nila2024!"
  sensitive   = true
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair. If null, the Weka module generates a key pair."
  type        = string
  default     = null
}
