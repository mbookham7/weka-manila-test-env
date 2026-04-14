output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "weka_subnet_id" {
  description = "ID of the Weka backend subnet."
  value       = aws_subnet.weka.id
}

output "devstack_subnet_id" {
  description = "ID of the DevStack subnet."
  value       = aws_subnet.devstack.id
}

output "alb_subnet_id" {
  description = "ID of the ALB second subnet."
  value       = aws_subnet.alb.id
}

output "weka_sg_id" {
  description = "ID of the Weka cluster security group."
  value       = aws_security_group.weka.id
}

output "devstack_sg_id" {
  description = "ID of the DevStack security group."
  value       = aws_security_group.devstack.id
}

output "alb_sg_id" {
  description = "ID of the Weka ALB security group."
  value       = aws_security_group.alb.id
}

output "main_route_table_id" {
  description = "ID of the main VPC route table (shared by all subnets)."
  value       = aws_route_table.main.id
}
