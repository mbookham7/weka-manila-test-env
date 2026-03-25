variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "weka_subnet_cidr" {
  description = "CIDR block for the Weka backend subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "devstack_subnet_cidr" {
  description = "CIDR block for the DevStack subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "alb_subnet_cidr" {
  description = "CIDR block for the Weka ALB second subnet (must be in alb_availability_zone)."
  type        = string
  default     = "10.0.3.0/24"
}

variable "availability_zone" {
  description = "Primary availability zone for Weka backends and DevStack."
  type        = string
}

variable "alb_availability_zone" {
  description = "Secondary availability zone for the ALB subnet (must differ from availability_zone)."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block for administrative SSH/HTTPS access."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
