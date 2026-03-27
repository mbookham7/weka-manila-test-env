output "devstack_public_ip" {
  description = "Public IP address of the DevStack instance."
  value       = module.devstack.devstack_public_ip
}

output "devstack_ssh" {
  description = "SSH command to connect to the DevStack instance."
  value       = "ssh ubuntu@${module.devstack.devstack_public_ip} -i <your-key.pem>"
}

output "horizon_url" {
  description = "OpenStack Horizon dashboard URL."
  value       = "http://${module.devstack.devstack_public_ip}/dashboard"
}

output "keystone_url" {
  description = "OpenStack Keystone endpoint."
  value       = "http://${module.devstack.devstack_public_ip}:5000/v3"
}

output "manila_endpoint" {
  description = "Manila share service API endpoint."
  value       = "http://${module.devstack.devstack_public_ip}:8786/v2"
}

output "weka_ui_url" {
  description = "Weka cluster management UI URL (internal ALB — VPC access only)."
  value       = "https://${module.weka_cluster.weka_alb_dns_name}"
}

output "weka_api_url" {
  description = "Weka REST API base URL (internal ALB — VPC access only)."
  value       = "https://${module.weka_cluster.weka_alb_dns_name}:14000/api/v2"
}

output "weka_external_ui_url" {
  description = "Weka cluster management UI URL via internet-facing NLB (accessible from admin_cidr)."
  value       = "https://${aws_lb.weka_external.dns_name}"
}

output "weka_external_api_url" {
  description = "Weka REST API URL via internet-facing NLB (accessible from admin_cidr)."
  value       = "https://${aws_lb.weka_external.dns_name}:14000/api/v2"
}

output "weka_secret_id" {
  description = "AWS Secrets Manager secret ID containing the Weka admin password."
  value       = module.weka_cluster.weka_password_secret_id
}

output "weka_lambda_status_name" {
  description = "Name of the Weka status Lambda function (used to poll cluster readiness)."
  value       = module.weka_cluster.lambda_status_name
}

output "aws_region" {
  description = "AWS region the environment is deployed in."
  value       = var.aws_region
}

output "devstack_log_cmd" {
  description = "Command to stream the DevStack stack.sh log."
  value       = "ssh ubuntu@${module.devstack.devstack_public_ip} -i <key.pem> 'tail -f /var/log/stack.sh.log'"
}

output "bootstrap_log_cmd" {
  description = "Command to stream the cloud-init bootstrap log."
  value       = "ssh ubuntu@${module.devstack.devstack_public_ip} -i <key.pem> 'sudo tail -f /var/log/devstack-bootstrap.log'"
}

output "manila_check_cmd" {
  description = "Command to verify Manila services and pools after deployment."
  value       = "ssh ubuntu@${module.devstack.devstack_public_ip} -i <key.pem> 'source /opt/stack/devstack/openrc admin admin && manila service-list && manila pool-list --detail'"
}

output "weka_password_cmd" {
  description = "AWS CLI command to retrieve the Weka admin password from Secrets Manager."
  value       = "aws secretsmanager get-secret-value --secret-id ${module.weka_cluster.weka_password_secret_id} --region ${var.aws_region} --query SecretString --output text"
}

output "next_steps" {
  description = "Instructions for what to do after terraform apply."
  value       = <<-EOF
    Deployment started. Follow these steps:

    1. Wait ~20 min for Weka cluster to clusterize:
       make wait-weka

    2. Wait ~40 min for DevStack to finish bootstrapping:
       make wait-devstack

    3. Stream the DevStack log:
       ${join("", ["ssh ubuntu@", module.devstack.devstack_public_ip, " -i <key.pem> 'tail -f /var/log/stack.sh.log'"])}

    4. Check Manila services (after DevStack complete):
       ${join("", ["ssh ubuntu@", module.devstack.devstack_public_ip, " -i <key.pem> 'source /opt/stack/devstack/openrc admin admin && manila service-list'"])}

    5. Access Horizon dashboard:
       http://${module.devstack.devstack_public_ip}/dashboard
       Username: admin  Password: (set in terraform.tfvars)

    6. Access Weka UI (external — from your laptop):
       https://${aws_lb.weka_external.dns_name}
       Password: $(aws secretsmanager get-secret-value --secret-id ${module.weka_cluster.weka_password_secret_id} --region ${var.aws_region} --query SecretString --output text)

    7. Run Manila tempest tests:
       make test SSH_KEY=<key.pem>

    8. To destroy: make destroy SSH_KEY=<key.pem>
  EOF
}
