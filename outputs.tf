output "vpc_id" {
  description = "VPC ID"
  value       = try(aws_vpc.this[0].id, "")
}

output "vpc_arn" {
  description = "VPC ARN"
  value       = try(aws_vpc.this[0].arn, "")
}

output "vpc_cidr_block" {
  description = "VPC CIDR Block"
  value       = try(aws_vpc.this[0].cidr_block, "")
}

output "default_security_group_id" {
  description = "Default Security Group ID"
  value       = try(aws_vpc.this[0].default_security_group_id, "")
}

output "default_network_acl_id" {
  description = "Default Network ACL ID"
  value       = try(aws_vpc.this[0].default_network_acl_id, "")
}

output "default_route_table_id" {
  description = "Default Route Table ID"
  value       = try(aws_vpc.this[0].default_route_table_id, "")
}


output "private_subnets" {
  description = "Private Subnet ID List"
  value       = aws_subnet.private[*].id
}

output "private_subnet_arns" {
  description = "Private Subnet ARN List"
  value       = aws_subnet.private[*].arn
}

output "private_subnets_cidr_blocks" {
  description = "Private Subnets CIDR Block list"
  value       = compact(aws_subnet.private[*].cidr_block)
}

output "private_subnets_ipv6_cidr_blocks" {
  description = "Private Subnet IPv6 cidr blocks"
  value       = compact(aws_subnet.private[*].ipv6_cidr_block)
}

output "public_subnets" {
  description = "Public Subnet ID List"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "Public Subnet ARN List"
  value       = aws_subnet.public[*].arn
}

output "public_subnets_cidr_blocks" {
  description = "Public Subnet CIDR Block list"
  value       = compact(aws_subnet.public[*].cidr_block)
}

output "public_subnets_ipv6_cidr_blocks" {
  description = "Public Subnet IPv6 CIDR block list"
  value       = compact(aws_subnet.public[*].ipv6_cidr_block)
}


output "cgw_ids" {
  description = "Customer Gateway ID List"
  value       = [for k, v in aws_customer_gateway.this : v.id]
}

output "cgw_arns" {
  description = "Customer Gateway ARNs list"
  value       = [for k, v in aws_customer_gateway.this : v.arn]
}

output "this_customer_gateway" {
  description = "Customer Gateway attributes map"
  value       = aws_customer_gateway.this
}

output "vgw_id" {
  description = "VPN Gateway ID"
  value       = try(aws_vpn_gateway.this[0].id, aws_vpn_gateway_attachment.this[0].vpn_gateway_id, "")
}

output "vgw_arn" {
  description = "VPN Gateway ARN"
  value       = try(aws_vpn_gateway.this[0].arn, "")
}

output "default_vpc_id" {
  description = "Default VPC ID"
  value       = try(aws_default_vpc.this[0].id, "")
}

output "default_vpc_arn" {
  description = "Default VPC ARN"
  value       = try(aws_default_vpc.this[0].arn, "")
}

output "default_vpc_cidr_block" {
  description = "Default VPC CIDR Block"
  value       = try(aws_default_vpc.this[0].cidr_block, "")
}

output "default_vpc_default_security_group_id" {
  description = "Seucrity Group ID for default security group of default VPC"
  value       = try(aws_default_vpc.this[0].default_security_group_id, "")
}

output "default_vpc_default_network_acl_id" {
  description = "Default NACL ID of the Default VPC"
  value       = try(aws_default_vpc.this[0].default_network_acl_id, "")
}

output "default_vpc_default_route_table_id" {
  description = "Default route table ID of the default VPC"
  value       = try(aws_default_vpc.this[0].default_route_table_id, "")
}

output "public_route_table_ids" {
  description = "public route tables IDs"
  value       = aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "Private route tables IDs"
  value       = aws_route_table.private[*].id
}
