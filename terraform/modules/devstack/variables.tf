variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "devstack_subnet_id" {
  description = "Subnet ID for the DevStack instance."
  type        = string
}

variable "devstack_sg_id" {
  description = "Security group ID for the DevStack instance."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for DevStack. Requires ≥8 vCPU, ≥32 GB RAM."
  type        = string
  default     = "m5.4xlarge"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB. DevStack + Weka agent + images need ≥150 GB."
  type        = number
  default     = 150
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH access."
  type        = string
}

variable "weka_backend" {
  description = "Weka ALB DNS name (used as weka_api_server in Manila config and for agent install)."
  type        = string
}

variable "weka_password_secret_id" {
  description = "AWS Secrets Manager secret ID/ARN containing the Weka admin password."
  type        = string
}

variable "lambda_status_name" {
  description = "Name of the Weka status Lambda function (used to poll cluster readiness)."
  type        = string
}

variable "devstack_branch" {
  description = "DevStack git branch (e.g. stable/2024.2)."
  type        = string
  default     = "stable/2024.2"
}

variable "driver_branch" {
  description = "Manila Weka driver git branch."
  type        = string
  default     = "main"
}

variable "admin_password" {
  description = "OpenStack admin password for DevStack."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
