output "weka_alb_dns_name" {
  description = "DNS name of the Weka ALB (used as weka_api_server in Manila configuration)."
  value       = module.weka.alb_dns_name
}

output "weka_password_secret_id" {
  description = "AWS Secrets Manager secret ID/ARN containing the Weka cluster admin password."
  value       = module.weka.weka_cluster_admin_password_secret_id
}

output "lambda_status_name" {
  description = "Name of the Weka status Lambda function (used to poll cluster readiness)."
  value       = module.weka.lambda_status_name
}

output "asg_name" {
  description = "Name of the Weka backend Auto Scaling Group."
  value       = module.weka.asg_name
}

output "vpc_id" {
  description = "VPC ID (derived from provided subnet)."
  value       = module.weka.vpc_id
}

output "cluster_helper_commands" {
  description = "AWS CLI helper commands for cluster operations (get_ips, get_password, get_status)."
  value       = module.weka.cluster_helper_commands
}

output "pre_terraform_destroy_command" {
  description = "Command that must be run before terraform destroy (only relevant if S3/SMB gateways exist)."
  value       = module.weka.pre_terraform_destroy_command
}
