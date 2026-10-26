provider "aws" {
  region = var.region
}

locals {
  name = "example-complete"
  cidr = "10.20.0.0/16"
  # Listed rather than looked up, so a new AZ in the region never moves subnets.
  azs = ["${var.region}a", "${var.region}b", "${var.region}c"]

  tags = {
    Example = local.name
  }
}

module "vpc" {
  source = "../../"

  name = local.name
  cidr = local.cidr
  azs  = local.azs

  public_subnets   = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnets  = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
  database_subnets = ["10.20.64.0/24", "10.20.65.0/24", "10.20.66.0/24"]

  map_public_ip_on_launch = false

  # One NAT gateway for the whole VPC keeps the example cheap. Production VPCs
  # usually want one per AZ, with one_nat_gateway_per_az = true.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Database subnets get a subnet group named after the VPC, their own route
  # table with a NAT route for patching, and a dedicated network ACL. The NACL
  # keeps its default allow-all rules here; security groups do the filtering.
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  create_database_nat_gateway_route  = true
  database_dedicated_network_acl     = true

  # Flow logs to a module-created CloudWatch log group. ALL captures accepted
  # traffic too, which helps incident investigation but costs more to ingest.
  enable_flow_log                                 = true
  flow_log_traffic_type                           = "ALL"
  flow_log_cloudwatch_log_group_retention_in_days = 365

  # The default security group stays with no rules, so nothing can use it by
  # accident. Add rules here only if something must rely on it.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Site-to-site VPN building blocks. The VGW propagates its routes into the
  # private route tables.
  enable_vpn_gateway                 = true
  amazon_side_asn                    = "64620"
  propagate_private_route_tables_vgw = true

  customer_gateways = {
    head-office = {
      bgp_asn     = 65010
      ip_address  = "203.0.113.10"
      device_name = "head-office-firewall"
    }
  }

  tags = local.tags
}
