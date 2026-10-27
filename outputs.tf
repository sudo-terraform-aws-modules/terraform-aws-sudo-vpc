output "vpc_id" {
  description = "VPC ID, or null when not created"
  value       = try(aws_vpc.this[0].id, null)
}

output "vpc_arn" {
  description = "VPC ARN, or null when not created"
  value       = try(aws_vpc.this[0].arn, null)
}

output "vpc_cidr_block" {
  description = "VPC CIDR Block, or null when not created"
  value       = try(aws_vpc.this[0].cidr_block, null)
}

output "default_security_group_id" {
  description = "Default Security Group ID, or null when not created"
  value       = try(aws_vpc.this[0].default_security_group_id, null)
}

output "default_network_acl_id" {
  description = "Default Network ACL ID, or null when not created"
  value       = try(aws_vpc.this[0].default_network_acl_id, null)
}

output "default_route_table_id" {
  description = "Default Route Table ID, or null when not created"
  value       = try(aws_vpc.this[0].default_route_table_id, null)
}


output "private_subnets" {
  description = "Private Subnet ID List"
  value       = aws_subnet.private[*].id
}
output "database_subnets" {
  description = "Database Subnet ID List"
  value       = aws_subnet.database[*].id
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
  description = "VPN Gateway ID, or null when not created"
  value       = try(aws_vpn_gateway.this[0].id, aws_vpn_gateway_attachment.this[0].vpn_gateway_id, null)
}

output "vgw_arn" {
  description = "VPN Gateway ARN, or null when not created"
  value       = try(aws_vpn_gateway.this[0].arn, null)
}

output "default_vpc_id" {
  description = "Default VPC ID, or null when not created"
  value       = try(aws_default_vpc.this[0].id, null)
}

output "default_vpc_arn" {
  description = "Default VPC ARN, or null when not created"
  value       = try(aws_default_vpc.this[0].arn, null)
}

output "default_vpc_cidr_block" {
  description = "Default VPC CIDR Block, or null when not created"
  value       = try(aws_default_vpc.this[0].cidr_block, null)
}

output "default_vpc_default_security_group_id" {
  description = "Security Group ID for default security group of default VPC, or null when not created"
  value       = try(aws_default_vpc.this[0].default_security_group_id, null)
}

output "default_vpc_default_network_acl_id" {
  description = "Default NACL ID of the Default VPC, or null when not created"
  value       = try(aws_default_vpc.this[0].default_network_acl_id, null)
}

output "default_vpc_default_route_table_id" {
  description = "Default route table ID of the default VPC, or null when not created"
  value       = try(aws_default_vpc.this[0].default_route_table_id, null)
}

output "public_route_table_ids" {
  description = "public route tables IDs"
  value       = aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "Private route tables IDs"
  value       = aws_route_table.private[*].id
}

output "database_subnet_group" {
  description = "ID of database subnet group, or null when not created"
  value       = try(aws_db_subnet_group.database[0].id, null)
}

output "database_subnet_group_name" {
  description = "Name of database subnet group, or null when not created"
  value       = try(aws_db_subnet_group.database[0].name, null)
}

output "database_subnet_arns" {
  description = "Database subnet ARNs"
  value       = aws_subnet.database[*].arn
}

output "database_subnets_cidr_blocks" {
  description = "Database subnet CIDR blocks"
  value       = compact(aws_subnet.database[*].cidr_block)
}

output "database_subnets_ipv6_cidr_blocks" {
  description = "Database subnet IPv6 CIDR blocks"
  value       = compact(aws_subnet.database[*].ipv6_cidr_block)
}

output "database_route_table_ids" {
  description = "Database route table IDs"
  value       = aws_route_table.database[*].id
}

output "azs" {
  description = "Availability zones the subnets are spread across"
  value       = var.azs
}

output "vpc_ipv6_cidr_block" {
  description = "VPC IPv6 CIDR block, or null when not created or IPv6 is off"
  value       = try(aws_vpc.this[0].ipv6_cidr_block, null)
}

output "igw_id" {
  description = "Internet gateway ID, or null when not created"
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "igw_arn" {
  description = "Internet gateway ARN, or null when not created"
  value       = try(aws_internet_gateway.this[0].arn, null)
}

output "egress_only_internet_gateway_id" {
  description = "Egress-only internet gateway ID, or null when not created"
  value       = try(aws_egress_only_internet_gateway.this[0].id, null)
}

output "natgw_ids" {
  description = "NAT gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

output "nat_ids" {
  description = "Elastic IP allocation IDs created for the NAT gateways"
  value       = aws_eip.nat[*].id
}

output "nat_public_ips" {
  description = "Public IPs of the NAT gateways"
  value       = aws_nat_gateway.this[*].public_ip
}

output "vpc_flow_log_id" {
  description = "Flow log ID, or null when not created"
  value       = try(aws_flow_log.default[0].id, null)
}

output "vpc_flow_log_destination_arn" {
  description = "ARN of the flow log destination, or null when flow logs are off"
  value       = local.enable_flow_log ? local.flow_log_destination_arn : null
}

output "vpc_flow_log_cloudwatch_iam_role_arn" {
  description = "ARN of the IAM role flow logs use to write to CloudWatch, or null when not used"
  value       = local.enable_flow_log ? local.flow_log_iam_role_arn : null
}

output "vpc_flow_log_cloudwatch_log_group_name" {
  description = "Name of the flow log CloudWatch log group the module created, or null when not created"
  value       = try(aws_cloudwatch_log_group.flow_log[0].name, null)
}

output "vpc_flow_log_cloudwatch_log_group_arn" {
  description = "ARN of the flow log CloudWatch log group the module created, or null when not created"
  value       = try(aws_cloudwatch_log_group.flow_log[0].arn, null)
}

output "intra_subnets" {
  description = "Intra subnet IDs"
  value       = aws_subnet.intra[*].id
}

output "intra_subnet_arns" {
  description = "Intra subnet ARNs"
  value       = aws_subnet.intra[*].arn
}

output "intra_subnets_cidr_blocks" {
  description = "Intra subnet CIDR blocks"
  value       = compact(aws_subnet.intra[*].cidr_block)
}

output "intra_route_table_ids" {
  description = "Intra route table IDs"
  value       = aws_route_table.intra[*].id
}

output "elasticache_subnets" {
  description = "ElastiCache subnet IDs"
  value       = aws_subnet.elasticache[*].id
}

output "elasticache_subnet_arns" {
  description = "ElastiCache subnet ARNs"
  value       = aws_subnet.elasticache[*].arn
}

output "elasticache_subnets_cidr_blocks" {
  description = "ElastiCache subnet CIDR blocks"
  value       = compact(aws_subnet.elasticache[*].cidr_block)
}

output "elasticache_subnet_group_name" {
  description = "Name of the ElastiCache subnet group, or null when not created"
  value       = try(aws_elasticache_subnet_group.elasticache[0].name, null)
}

output "elasticache_route_table_ids" {
  description = "ElastiCache route table IDs"
  value       = aws_route_table.elasticache[*].id
}

output "redshift_subnets" {
  description = "Redshift subnet IDs"
  value       = aws_subnet.redshift[*].id
}

output "redshift_subnet_arns" {
  description = "Redshift subnet ARNs"
  value       = aws_subnet.redshift[*].arn
}

output "redshift_subnets_cidr_blocks" {
  description = "Redshift subnet CIDR blocks"
  value       = compact(aws_subnet.redshift[*].cidr_block)
}

output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group, or null when not created"
  value       = try(aws_redshift_subnet_group.redshift[0].name, null)
}

output "redshift_route_table_ids" {
  description = "Redshift route table IDs"
  value       = aws_route_table.redshift[*].id
}

output "vpc_endpoint_ids" {
  description = "VPC endpoint IDs, by service short name"
  value       = merge({ for k, e in aws_vpc_endpoint.gateway : k => e.id }, { for k, e in aws_vpc_endpoint.interface : k => e.id })
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group for the interface endpoints, or null when not created"
  value       = try(aws_security_group.vpc_endpoints[0].id, null)
}

output "dhcp_options_id" {
  description = "DHCP options set ID, or null when not created"
  value       = try(aws_vpc_dhcp_options.this[0].id, null)
}
