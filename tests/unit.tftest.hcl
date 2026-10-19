# Unit tests against a mock provider. Needs Terraform 1.7+ (mock providers), while the
# module itself supports >= 1.3.0. Run with `make test`.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
      zone_ids = ["euw1-az1", "euw1-az2", "euw1-az3"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  # Generated values are random strings, which fail the provider's ARN checks on apply.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vpc-flow-log/unit-test"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/vpc-flow-log-role-unit-test"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/vpc-flow-log-to-cloudwatch-unit-test"
    }
  }
}

variables {
  name = "unit-test"
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_vpc.this[0].cidr_block == "172.31.0.0/16"
    error_message = "With cidr left at its default the VPC must use 172.31.0.0/16."
  }

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.database) == 3
    error_message = "Defaults must create three public, three private and three database subnets."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0
    error_message = "NAT gateways must be off by default."
  }

  assert {
    condition     = aws_flow_log.default[0].traffic_type == "REJECT" && aws_cloudwatch_log_group.flow_log[0].retention_in_days == 90
    error_message = "Flow logs must be on by default, capturing REJECT traffic with 90-day retention."
  }

  assert {
    condition     = length(aws_db_subnet_group.database) == 1 && aws_db_subnet_group.database[0].name == "unit-test"
    error_message = "The database subnet group must be created and named after the VPC."
  }

  assert {
    condition     = length(aws_vpn_gateway.this) == 0 && length(aws_vpn_gateway_attachment.this) == 0 && length(aws_customer_gateway.this) == 0
    error_message = "No VPN resources may be created by default."
  }
}

run "default_security_group_has_no_rules" {
  command = apply

  assert {
    condition     = length(aws_default_security_group.this[0].ingress) == 0 && length(aws_default_security_group.this[0].egress) == 0
    error_message = "The default security group must have no rules by default."
  }

  assert {
    condition     = aws_default_security_group.this[0].tags["Name"] == "unit-test-default-security-group"
    error_message = "The default security group Name tag must be derived from name."
  }
}

run "carves_subnets_from_cidr" {
  command = plan

  variables {
    cidr = "10.10.0.0/16"
  }

  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
    error_message = "Public subnets must be carved from the first /20 of cidr."
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.10.16.0/24", "10.10.17.0/24", "10.10.18.0/24"]
    error_message = "Private subnets must be carved from the second /20 of cidr."
  }

  assert {
    condition     = aws_subnet.database[*].cidr_block == ["10.10.32.0/24", "10.10.33.0/24", "10.10.34.0/24"]
    error_message = "Database subnets must be carved from the third /20 of cidr."
  }
}

run "uses_given_subnets" {
  command = plan

  variables {
    cidr             = "10.20.0.0/16"
    azs              = ["eu-west-1a", "eu-west-1b"]
    public_subnets   = ["10.20.0.0/24", "10.20.1.0/24"]
    private_subnets  = ["10.20.16.0/20", "10.20.32.0/20"]
    database_subnets = ["10.20.64.0/24", "10.20.65.0/24"]
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.20.16.0/20", "10.20.32.0/20"]
    error_message = "Given private subnets must be used as they are."
  }

  assert {
    condition     = aws_subnet.public[*].availability_zone == ["eu-west-1a", "eu-west-1b"]
    error_message = "AZ names in azs must be set as availability_zone."
  }
}

run "single_nat_gateway" {
  command = plan

  variables {
    enable_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "single_nat_gateway defaults to true, so one NAT gateway and one EIP are expected."
  }

  assert {
    condition     = aws_eip.nat[0].domain == "vpc"
    error_message = "NAT EIPs must be VPC EIPs."
  }
}

run "nothing_without_vpc" {
  command = plan

  variables {
    create_vpc     = false
    vpn_gateway_id = "vgw-0123456789abcdef0"
  }

  assert {
    condition     = length(aws_vpc.this) == 0 && length(aws_subnet.public) == 0 && length(aws_flow_log.default) == 0
    error_message = "create_vpc = false must create no VPC resources."
  }

  assert {
    condition     = length(aws_vpn_gateway_attachment.this) == 0
    error_message = "The VPN gateway attachment must respect create_vpc."
  }

  assert {
    condition     = output.vpc_id == null && output.vpc_arn == null && output.database_subnet_group == null && output.vgw_id == null
    error_message = "Outputs for resources that are not created must be null."
  }
}

run "vpn_gateway_attachment" {
  command = plan

  variables {
    vpn_gateway_id = "vgw-0123456789abcdef0"
  }

  assert {
    condition     = aws_vpn_gateway_attachment.this[0].vpn_gateway_id == "vgw-0123456789abcdef0"
    error_message = "An existing VPN gateway must be attached when vpn_gateway_id is set."
  }
}

run "customer_gateways" {
  command = plan

  variables {
    customer_gateways = {
      head-office = {
        bgp_asn    = 65010
        ip_address = "203.0.113.10"
      }
    }
  }

  assert {
    condition     = aws_customer_gateway.this["head-office"].bgp_asn == "65010"
    error_message = "A numeric bgp_asn must be passed to the provider as a string."
  }

  assert {
    condition     = aws_customer_gateway.this["head-office"].device_name == null
    error_message = "device_name must be optional."
  }
}

run "default_security_group_rules" {
  command = apply

  variables {
    default_security_group_ingress = [{ description = "self", self = true }]
    default_security_group_egress = [{
      cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
    }]
  }

  assert {
    condition     = one(aws_default_security_group.this[0].ingress).protocol == "-1" && one(aws_default_security_group.this[0].ingress).from_port == 0
    error_message = "Rule attributes left out must default to all traffic on port 0."
  }

  assert {
    condition     = one(aws_default_security_group.this[0].egress).cidr_blocks == tolist(["10.0.0.0/8", "172.16.0.0/12"])
    error_message = "cidr_blocks must be passed through as a list."
  }
}

run "s3_flow_logs" {
  command = plan

  variables {
    flow_log_destination_type = "s3"
    flow_log_destination_arn  = "arn:aws:s3:::unit-test-flow-logs"
  }

  assert {
    condition     = aws_flow_log.default[0].iam_role_arn == null && aws_flow_log.default[0].log_destination == "arn:aws:s3:::unit-test-flow-logs"
    error_message = "S3 flow logs must use the given bucket and no IAM role."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.flow_log) == 0 && length(aws_iam_role.vpc_flow_log_cloudwatch) == 0
    error_message = "S3 flow logs must not create a log group or IAM role."
  }
}

run "rejects_empty_vpn_gateway_id" {
  command = plan

  variables {
    vpn_gateway_id = ""
  }

  expect_failures = [var.vpn_gateway_id]
}

run "rejects_empty_flow_log_destination_arn" {
  command = plan

  variables {
    flow_log_destination_arn = ""
  }

  expect_failures = [var.flow_log_destination_arn]
}

run "rejects_empty_flow_log_iam_role_arn" {
  command = plan

  variables {
    flow_log_cloudwatch_iam_role_arn = ""
  }

  expect_failures = [var.flow_log_cloudwatch_iam_role_arn]
}

run "rejects_empty_log_group_name_suffix" {
  command = plan

  variables {
    flow_log_cloudwatch_log_group_name_suffix = ""
  }

  expect_failures = [var.flow_log_cloudwatch_log_group_name_suffix]
}

run "rejects_invalid_instance_tenancy" {
  command = plan

  variables {
    instance_tenancy = "shared"
  }

  expect_failures = [var.instance_tenancy]
}

run "rejects_invalid_flow_log_traffic_type" {
  command = plan

  variables {
    flow_log_traffic_type = "SOME"
  }

  expect_failures = [var.flow_log_traffic_type]
}

# Issue #10: NAT gateways and private routing.

run "one_nat_gateway_per_az" {
  command = apply

  variables {
    cidr                   = "10.0.0.0/16"
    enable_nat_gateway     = true
    one_nat_gateway_per_az = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_route_table.private) == 3
    error_message = "one_nat_gateway_per_az with three AZs must create three NAT gateways and three private route tables."
  }

  assert {
    condition     = aws_route_table_association.private[*].route_table_id == aws_route_table.private[*].id
    error_message = "Each private subnet must use the route table, and so the NAT gateway, of its own AZ."
  }
}

run "nat_gateway_per_subnet_with_carved_subnets" {
  command = plan

  variables {
    cidr               = "10.0.0.0/16"
    enable_nat_gateway = true
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_route_table.private) == 3 && length(aws_route_table_association.private) == 3
    error_message = "single_nat_gateway = false must give one NAT gateway and route table per private subnet when the module carves the subnets."
  }
}

run "vgw_propagation_single_nat_given_subnets" {
  command = plan

  variables {
    cidr                               = "10.0.0.0/16"
    public_subnets                     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
    private_subnets                    = ["10.0.16.0/24", "10.0.17.0/24", "10.0.18.0/24"]
    enable_nat_gateway                 = true
    enable_vpn_gateway                 = true
    propagate_private_route_tables_vgw = true
  }

  assert {
    condition     = length(aws_route_table.private) == 1 && length(aws_vpn_gateway_route_propagation.private) == 1
    error_message = "With one private route table there must be exactly one private VGW propagation, not one per subnet."
  }
}

run "vgw_propagation_carved_subnets" {
  command = plan

  variables {
    cidr                               = "10.0.0.0/16"
    enable_vpn_gateway                 = true
    propagate_private_route_tables_vgw = true
  }

  assert {
    condition     = length(aws_vpn_gateway_route_propagation.private) == length(aws_route_table.private) && length(aws_route_table.private) > 0
    error_message = "Private VGW propagation must also work when the module carves the subnets."
  }
}

run "vgw_propagation_one_nat_per_az" {
  command = apply

  variables {
    cidr                               = "10.0.0.0/16"
    enable_nat_gateway                 = true
    one_nat_gateway_per_az             = true
    enable_vpn_gateway                 = true
    propagate_private_route_tables_vgw = true
  }

  assert {
    condition     = aws_vpn_gateway_route_propagation.private[*].route_table_id == aws_route_table.private[*].id
    error_message = "Every private route table must get exactly one VGW propagation."
  }

  assert {
    condition     = alltrue([for p in aws_vpn_gateway_route_propagation.private : p.vpn_gateway_id == aws_vpn_gateway.this[0].id])
    error_message = "Private propagations must use the module's VPN gateway."
  }
}

# Issue #10: database route tables and network ACL.

run "database_route_table_single_nat" {
  command = apply

  variables {
    cidr                               = "10.0.0.0/16"
    enable_nat_gateway                 = true
    create_database_subnet_route_table = true
    create_database_nat_gateway_route  = true
  }

  assert {
    condition     = length(aws_route_table.database) == 1 && length(aws_route_table_association.database) == 3
    error_message = "With a single NAT gateway there must be one database route table, associated with all three database subnets."
  }

  assert {
    condition     = alltrue([for a in aws_route_table_association.database : a.route_table_id == aws_route_table.database[0].id])
    error_message = "Database subnets must use the database route table, not the main one."
  }

  assert {
    condition     = aws_route_table_association.database[*].subnet_id == aws_subnet.database[*].id
    error_message = "Every database subnet must be associated."
  }

  assert {
    condition     = length(aws_route.database_nat_gateway) == 1 && aws_route.database_nat_gateway[0].nat_gateway_id == aws_nat_gateway.this[0].id
    error_message = "The database route table must route 0.0.0.0/0 through the NAT gateway."
  }
}

run "database_route_tables_per_az_without_azs" {
  command = apply

  variables {
    cidr                               = "10.0.0.0/16"
    enable_nat_gateway                 = true
    one_nat_gateway_per_az             = true
    create_database_subnet_route_table = true
    create_database_nat_gateway_route  = true
  }

  assert {
    condition     = length(aws_route_table.database) == 3 && aws_route_table_association.database[*].route_table_id == aws_route_table.database[*].id
    error_message = "With one NAT per AZ each database subnet must get its own route table, also when azs is not set."
  }

  assert {
    condition     = aws_route.database_nat_gateway[*].nat_gateway_id == aws_nat_gateway.this[*].id
    error_message = "Each database route table must use the NAT gateway in its own AZ."
  }

  assert {
    condition     = aws_route_table.database[0].tags["Name"] == "unit-test-database-euw1-az1"
    error_message = "Per-AZ database route tables must be named after the AZ the module picked."
  }
}

run "database_route_table_internet_gateway" {
  command = plan

  variables {
    cidr                                   = "10.0.0.0/16"
    create_database_subnet_route_table     = true
    create_database_internet_gateway_route = true
  }

  assert {
    condition     = length(aws_route_table.database) == 1 && length(aws_route.database_internet_gateway) == 1 && length(aws_route_table_association.database) == 3
    error_message = "create_database_internet_gateway_route must give one associated database route table with an internet gateway route."
  }
}

run "no_database_route_table_by_default" {
  command = plan

  assert {
    condition     = length(aws_route_table.database) == 0 && length(aws_route_table_association.database) == 0
    error_message = "Database subnets must stay on the main route table unless create_database_subnet_route_table is set."
  }
}
