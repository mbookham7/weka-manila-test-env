locals {
  name_prefix = "${var.prefix}-${var.cluster_name}"

  common_tags = {
    Project     = "weka-manila-test"
    Environment = "test"
    ManagedBy   = "terraform"
    Prefix      = var.prefix
    ClusterName = var.cluster_name
  }
}
