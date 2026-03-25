output "devstack_public_ip" {
  description = "Public IP address of the DevStack instance."
  value       = aws_instance.devstack.public_ip
}

output "devstack_private_ip" {
  description = "Private IP address of the DevStack instance."
  value       = aws_instance.devstack.private_ip
}

output "devstack_instance_id" {
  description = "EC2 instance ID of the DevStack instance."
  value       = aws_instance.devstack.id
}

output "devstack_ssh_command" {
  description = "SSH command to connect to DevStack."
  value       = "ssh ubuntu@${aws_instance.devstack.public_ip} -i <your-key.pem>"
}

output "horizon_url" {
  description = "OpenStack Horizon dashboard URL."
  value       = "http://${aws_instance.devstack.public_ip}/dashboard"
}

output "manila_endpoint" {
  description = "Manila share service API endpoint."
  value       = "http://${aws_instance.devstack.public_ip}:8786/v2"
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the DevStack instance."
  value       = aws_iam_role.devstack.arn
}
