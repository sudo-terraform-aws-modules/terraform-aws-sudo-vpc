provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "example-complete"
  cidr = "10.20.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

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
  # usually want one per AZ; see #10 before using one_nat_gateway_per_az.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Database subnets get a subnet group named after the VPC. The database route
  # table, its NAT route and the dedicated NACL stay off: until #10 is fixed the
  # route table is never associated and the NACL denies all traffic.
  create_database_subnet_group = true

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

  # Site-to-site VPN building blocks. Route propagation to the VGW is left off
  # until #10 fixes it.
  enable_vpn_gateway = true
  amazon_side_asn    = "64620"

  customer_gateways = {
    head-office = {
      bgp_asn     = 65010
      ip_address  = "203.0.113.10"
      device_name = "head-office-firewall"
    }
  }

  tags = local.tags
}
