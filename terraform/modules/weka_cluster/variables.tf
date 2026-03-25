variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "cluster_name" {
  description = "Weka cluster name."
  type        = string
}

variable "cluster_size" {
  description = "Number of Weka backend instances."
  type        = number
  default     = 6
}

variable "instance_type" {
  description = "EC2 instance type for Weka backend nodes."
  type        = string
  default     = "i3en.2xlarge"
}

variable "weka_version" {
  description = "Weka software version. Empty string uses the latest available."
  type        = string
  default     = ""
}

variable "get_weka_io_token" {
  description = "Token for downloading Weka from get.weka.io."
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key string for EC2 instances."
  type        = string
  default     = null
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name. If null, module generates one."
  type        = string
  default     = null
}

variable "weka_subnet_id" {
  description = "Subnet ID for Weka backend nodes."
  type        = string
}

variable "alb_subnet_id" {
  description = "Second subnet ID for the ALB (must be in a different AZ than weka_subnet_id)."
  type        = string
}

variable "weka_sg_id" {
  description = "Security group ID for Weka backend nodes (must include self-reference rule)."
  type        = string
}

variable "alb_sg_id" {
  description = "Security group ID for the Weka ALB."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block for SSH and Weka API admin access."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "tags_map" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
