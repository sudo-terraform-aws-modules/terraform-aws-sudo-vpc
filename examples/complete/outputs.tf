output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "IDs of the database subnets"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Name of the database subnet group"
  value       = module.vpc.database_subnet_group_name
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = module.vpc.private_route_table_ids
}

output "vgw_id" {
  description = "ID of the VPN gateway"
  value       = module.vpc.vgw_id
}

output "cgw_ids" {
  description = "IDs of the customer gateways"
  value       = module.vpc.cgw_ids
}

output "intra_subnets" {
  description = "IDs of the intra subnets"
  value       = module.vpc.intra_subnets
}

output "gateway_endpoint_ids" {
  description = "Gateway endpoint IDs, by service"
  value       = module.vpc.gateway_endpoint_ids
}

output "interface_endpoint_ids" {
  description = "Interface endpoint IDs, by service"
  value       = module.vpc.interface_endpoint_ids
}
