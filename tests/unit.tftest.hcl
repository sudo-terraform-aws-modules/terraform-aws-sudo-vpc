# Unit tests against a mock provider. Needs Terraform 1.7+ (mock providers), while the
# module itself supports >= 1.3.0. Run with `make test`.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  # Generated values are random strings, which fail the provider's ARN checks on apply.
  mock_resource "aws_vpc" {
    defaults = {
      ipv6_cidr_block = "2600:1f18:abcd:1200::/56"
    }
  }

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
  cidr = "10.0.0.0/16"
  azs  = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_vpc.this[0].cidr_block == "10.0.0.0/16"
    error_message = "The VPC must use the given cidr."
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
    condition     = aws_flow_log.default[0].traffic_type == "REJECT" && aws_cloudwatch_log_group.flow_log[0].retention_in_days == 365
    error_message = "Flow logs must be on by default, capturing REJECT traffic with 365-day retention."
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

run "database_route_tables_per_az" {
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
    error_message = "With one NAT per AZ each database subnet must get its own route table."
  }

  assert {
    condition     = aws_route.database_nat_gateway[*].nat_gateway_id == aws_nat_gateway.this[*].id
    error_message = "Each database route table must use the NAT gateway in its own AZ."
  }

  assert {
    condition     = aws_route_table.database[0].tags["Name"] == "unit-test-database-eu-west-1a"
    error_message = "Per-AZ database route tables must be named after their AZ."
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

run "database_network_acl_default_rules" {
  command = plan

  variables {
    database_dedicated_network_acl = true
  }

  assert {
    condition     = aws_network_acl.this["database"].subnet_ids == toset(aws_subnet.database[*].id)
    error_message = "The dedicated database NACL must hold the database subnets."
  }

  assert {
    condition     = aws_network_acl_rule.this["database-ingress-100"].cidr_block == "10.0.0.0/16" && aws_network_acl_rule.this["database-ingress-100"].protocol == "-1"
    error_message = "The database NACL must allow all traffic from the VPC."
  }

  assert {
    condition     = aws_network_acl_rule.this["database-ingress-200"].from_port == 1024 && aws_network_acl_rule.this["database-ingress-200"].cidr_block == "0.0.0.0/0" && !contains(keys(aws_network_acl_rule.this), "database-ingress-300")
    error_message = "The database NACL must allow replies on ephemeral ports, and nothing else from outside the VPC."
  }

  assert {
    condition     = aws_network_acl_rule.this["database-egress-100"].egress && aws_network_acl_rule.this["database-egress-100"].cidr_block == "0.0.0.0/0"
    error_message = "The database NACL must allow all outbound traffic."
  }
}

run "database_network_acl_custom_rules" {
  command = plan

  variables {
    database_dedicated_network_acl = true
    database_inbound_acl_rules = [
      { rule_number = 100, rule_action = "allow", protocol = "tcp", from_port = 5432, to_port = 5432, cidr_block = "10.0.0.0/16" },
      { rule_number = 110, rule_action = "allow", protocol = "tcp", from_port = 1024, to_port = 65535, cidr_block = "0.0.0.0/0" },
    ]
  }

  assert {
    condition     = length([for k in keys(aws_network_acl_rule.this) : k if startswith(k, "database-ingress-")]) == 2 && aws_network_acl_rule.this["database-ingress-100"].from_port == 5432
    error_message = "Custom inbound rules must replace the defaults."
  }

  assert {
    condition     = !aws_network_acl_rule.this["database-ingress-100"].egress && aws_network_acl_rule.this["database-egress-100"].egress
    error_message = "Inbound rules must be ingress, and outbound keeps its default."
  }
}

# Issue #10: subnet inputs that were silently ignored.

run "rejects_subnets_without_cidr" {
  command = plan

  variables {
    cidr            = null
    public_subnets  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
    private_subnets = ["10.0.16.0/24", "10.0.17.0/24", "10.0.18.0/24"]
  }

  expect_failures = [aws_vpc.this]
}

run "rejects_ipam_without_subnets" {
  command = plan

  variables {
    cidr                = null
    use_ipam_pool       = true
    ipv4_ipam_pool_id   = "ipam-pool-0123456789abcdef0"
    ipv4_netmask_length = 16
  }

  expect_failures = [aws_vpc.this]
}

run "ipam_with_given_subnets" {
  command = plan

  variables {
    cidr                = null
    use_ipam_pool       = true
    ipv4_ipam_pool_id   = "ipam-pool-0123456789abcdef0"
    ipv4_netmask_length = 16
    public_subnets      = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
    private_subnets     = ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]
    error_message = "With IPAM, the given subnets must be used."
  }
}

run "rejects_vpc_too_small_to_carve" {
  command = plan

  variables {
    cidr = "10.0.0.0/24"
  }

  expect_failures = [aws_vpc.this]
}

run "carves_smallest_supported_vpc" {
  command = plan

  variables {
    cidr = "10.0.0.0/20"
  }

  assert {
    condition     = aws_subnet.public[0].cidr_block == "10.0.0.0/28"
    error_message = "A /20 VPC must be carved into /28 subnets, the smallest size AWS allows."
  }
}

# Issue #11: flow log IAM and retention.

run "flow_log_policy_scoped_to_log_group" {
  command = apply

  assert {
    condition     = alltrue([for st in data.aws_iam_policy_document.vpc_flow_log_cloudwatch[0].statement : !contains(st.resources, "*")])
    error_message = "The flow log policy must not use resources = [\"*\"]."
  }

  assert {
    condition     = contains(flatten([for st in data.aws_iam_policy_document.vpc_flow_log_cloudwatch[0].statement : st.resources]), "${aws_cloudwatch_log_group.flow_log[0].arn}:*")
    error_message = "Writing log events must be scoped to the flow log group."
  }

  assert {
    condition     = contains(flatten([for st in data.aws_iam_policy_document.vpc_flow_log_cloudwatch[0].statement : st.resources]), "arn:aws:logs:eu-west-1:123456789012:log-group:*")
    error_message = "DescribeLogGroups must be scoped to the account and region."
  }
}

run "flow_log_policy_scoped_to_given_log_group" {
  command = apply

  variables {
    create_flow_log_cloudwatch_log_group = false
    flow_log_destination_arn             = "arn:aws:logs:eu-west-1:123456789012:log-group:existing-flow-logs"
  }

  assert {
    condition     = contains(flatten([for st in data.aws_iam_policy_document.vpc_flow_log_cloudwatch[0].statement : st.resources]), "arn:aws:logs:eu-west-1:123456789012:log-group:existing-flow-logs:*")
    error_message = "With a log group passed in, the policy must be scoped to that log group."
  }
}

run "flow_log_trust_policy_conditions" {
  command = apply

  assert {
    condition = anytrue([
      for c in one(data.aws_iam_policy_document.flow_log_cloudwatch_assume_role[0].statement).condition :
      c.test == "StringEquals" && c.variable == "aws:SourceAccount" && tolist(c.values) == tolist(["123456789012"])
    ])
    error_message = "The flow log role trust policy must pin aws:SourceAccount."
  }

  assert {
    condition = anytrue([
      for c in one(data.aws_iam_policy_document.flow_log_cloudwatch_assume_role[0].statement).condition :
      c.test == "ArnLike" && c.variable == "aws:SourceArn" && tolist(c.values) == tolist(["arn:aws:ec2:eu-west-1:123456789012:vpc-flow-log/*"])
    ])
    error_message = "The flow log role trust policy must pin aws:SourceArn to this account's flow logs."
  }
}

# Issue #11: default route table and default network ACL.

run "manages_default_route_table_and_nacl" {
  command = plan

  assert {
    condition     = length(aws_default_route_table.this) == 1 && length(aws_default_route_table.this[0].route) == 0
    error_message = "The default route table must be managed with no routes, so subnets left on it have no path out."
  }

  assert {
    condition     = aws_default_route_table.this[0].tags["Name"] == "unit-test-default"
    error_message = "The default route table must be tagged after the VPC."
  }

  assert {
    condition     = length(aws_default_network_acl.this) == 1 && length(aws_default_network_acl.this[0].ingress) == 2 && length(aws_default_network_acl.this[0].egress) == 2
    error_message = "The default NACL must be adopted with explicit IPv4 and IPv6 rules in each direction."
  }

  assert {
    condition     = alltrue([for r in aws_default_network_acl.this[0].ingress : r.action == "allow" && r.protocol == "-1"])
    error_message = "Default NACL rules must allow all traffic by default, because every public and private subnet uses it."
  }

  assert {
    condition     = aws_default_network_acl.this[0].tags["Name"] == "unit-test-default"
    error_message = "The default NACL must be tagged after the VPC."
  }
}

run "default_route_table_and_nacl_can_be_left_alone" {
  command = plan

  variables {
    manage_default_route_table = false
    manage_default_network_acl = false
  }

  assert {
    condition     = length(aws_default_route_table.this) == 0 && length(aws_default_network_acl.this) == 0
    error_message = "manage_default_route_table and manage_default_network_acl = false must leave both alone."
  }
}

run "default_nacl_custom_rules" {
  command = plan

  variables {
    cidr = "10.0.0.0/16"
    default_network_acl_ingress = [
      { rule_no = 100, action = "allow", protocol = "-1", cidr_block = "10.0.0.0/16" },
    ]
    default_network_acl_egress = []
  }

  assert {
    condition     = one(aws_default_network_acl.this[0].ingress).cidr_block == "10.0.0.0/16" && length(aws_default_network_acl.this[0].egress) == 0
    error_message = "Custom default NACL rules must replace the defaults; an empty list means no rules."
  }
}

run "no_default_resources_without_vpc" {
  command = plan

  variables {
    create_vpc = false
  }

  assert {
    condition     = length(aws_default_route_table.this) == 0 && length(aws_default_network_acl.this) == 0
    error_message = "create_vpc = false must not manage the default route table or NACL."
  }
}

# Issue #11: safer defaults.

run "rejects_missing_cidr" {
  command = plan

  variables {
    cidr = null
  }

  expect_failures = [aws_vpc.this]
}

run "rejects_catch_all_cidr" {
  command = plan

  variables {
    cidr = "0.0.0.0/0"
  }

  expect_failures = [var.cidr]
}

run "rejects_blank_name" {
  command = plan

  variables {
    name = " "
  }

  expect_failures = [var.name]
}

run "public_subnets_assign_no_public_ip_by_default" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not assign public IPs on launch by default."
  }
}

run "carves_one_subnet_per_given_az" {
  command = plan

  variables {
    azs = ["eu-west-1a", "eu-west-1b"]
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && aws_subnet.public[*].availability_zone == ["eu-west-1a", "eu-west-1b"]
    error_message = "With two AZs given, the module must carve two subnets per tier, one in each."
  }
}

# Issue #13: the AZ list is pinned by the caller.

run "rejects_empty_azs" {
  command = plan

  variables {
    azs = []
  }

  expect_failures = [var.azs]
}

run "rejects_blank_or_duplicate_azs" {
  command = plan

  variables {
    azs = ["eu-west-1a", "eu-west-1a", " "]
  }

  expect_failures = [var.azs]
}

run "carves_only_in_given_azs" {
  command = plan

  variables {
    azs = ["euw1-az2", "euw1-az3"]
  }

  assert {
    condition     = length(aws_subnet.private) == 2 && aws_subnet.private[*].availability_zone_id == ["euw1-az2", "euw1-az3"]
    error_message = "Carving must use exactly the AZs given, by name or by ID."
  }
}

# Issue #11: IPv6 egress for private subnets.

run "private_ipv6_egress" {
  command = apply

  variables {
    enable_ipv6                  = true
    public_subnets               = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
    private_subnets              = ["10.0.16.0/24", "10.0.17.0/24", "10.0.18.0/24"]
    public_subnet_ipv6_prefixes  = [0, 1, 2]
    private_subnet_ipv6_prefixes = [3, 4, 5]
    enable_nat_gateway           = true
    one_nat_gateway_per_az       = true
  }

  assert {
    condition     = length(aws_route.private_ipv6_egress) == 3
    error_message = "Every private route table must get an IPv6 default route."
  }

  assert {
    condition     = aws_route.private_ipv6_egress[*].route_table_id == aws_route_table.private[*].id && alltrue([for r in aws_route.private_ipv6_egress : r.destination_ipv6_cidr_block == "::/0" && r.egress_only_gateway_id == aws_egress_only_internet_gateway.this[0].id])
    error_message = "Private IPv6 traffic must leave through the egress-only internet gateway."
  }
}

run "egress_only_gateway_with_carved_subnets" {
  command = plan

  variables {
    enable_ipv6 = true
  }

  assert {
    condition     = length(aws_egress_only_internet_gateway.this) == 1 && length(aws_route.private_ipv6_egress) == length(aws_route_table.private)
    error_message = "With IPv6 on, the egress-only gateway and private IPv6 routes must also exist when the module carves the subnets."
  }
}

run "no_private_ipv6_egress_without_ipv6" {
  command = plan

  assert {
    condition     = length(aws_egress_only_internet_gateway.this) == 0 && length(aws_route.private_ipv6_egress) == 0
    error_message = "Without IPv6 there must be no egress-only gateway or IPv6 routes."
  }
}

# Issue #13: outputs.

run "outputs" {
  command = apply

  variables {
    enable_nat_gateway                 = true
    single_nat_gateway                 = true
    create_database_subnet_route_table = true
  }

  assert {
    condition     = output.igw_id == aws_internet_gateway.this[0].id && output.natgw_ids == aws_nat_gateway.this[*].id && length(output.nat_public_ips) == 1
    error_message = "Gateway outputs must expose the IGW and NAT gateways."
  }

  assert {
    condition     = output.database_subnets_cidr_blocks == tolist(["10.0.32.0/24", "10.0.33.0/24", "10.0.34.0/24"]) && length(output.database_subnet_arns) == 3 && output.database_route_table_ids == aws_route_table.database[*].id
    error_message = "Database outputs must expose the subnets and route tables."
  }

  assert {
    condition     = output.azs == tolist(["eu-west-1a", "eu-west-1b", "eu-west-1c"])
    error_message = "azs output must return the AZs in use."
  }

  assert {
    condition     = output.vpc_flow_log_cloudwatch_log_group_arn == aws_cloudwatch_log_group.flow_log[0].arn && output.vpc_flow_log_destination_arn == aws_cloudwatch_log_group.flow_log[0].arn && output.vpc_flow_log_id == aws_flow_log.default[0].id
    error_message = "Flow log outputs must expose the flow log and its log group."
  }
}

run "outputs_null_without_vpc" {
  command = plan

  variables {
    create_vpc = false
  }

  assert {
    condition     = output.igw_id == null && output.vpc_flow_log_id == null && output.vpc_flow_log_destination_arn == null && output.natgw_ids == []
    error_message = "Outputs must be null or empty when nothing is created."
  }
}

run "intra_subnets" {
  command = apply

  variables {
    intra_subnets                    = ["10.0.48.0/24", "10.0.49.0/24"]
    enable_nat_gateway               = true
    enable_vpn_gateway               = true
    propagate_intra_route_tables_vgw = true
  }

  assert {
    condition     = output.intra_subnets_cidr_blocks == tolist(["10.0.48.0/24", "10.0.49.0/24"]) && aws_subnet.intra[1].availability_zone == "eu-west-1b"
    error_message = "Intra subnets must be created from the given list, spread across azs."
  }

  assert {
    condition     = length(aws_route_table.intra) == 1 && aws_route_table_association.intra[*].route_table_id == [aws_route_table.intra[0].id, aws_route_table.intra[0].id]
    error_message = "All intra subnets must share one intra route table."
  }

  assert {
    condition     = length(aws_vpn_gateway_route_propagation.intra) == 1
    error_message = "VGW routes must propagate into the intra route table when asked."
  }
}

run "no_intra_subnets_by_default" {
  command = plan

  assert {
    condition     = length(aws_subnet.intra) == 0 && length(aws_route_table.intra) == 0
    error_message = "Intra subnets are never carved."
  }
}

run "elasticache_and_redshift_subnets" {
  command = apply

  variables {
    elasticache_subnets                = ["10.0.64.0/24", "10.0.65.0/24"]
    redshift_subnets                   = ["10.0.80.0/24", "10.0.81.0/24"]
    create_redshift_subnet_route_table = true
    redshift_subnet_group_name         = "Unit-Test-Redshift"
  }

  assert {
    condition     = output.elasticache_subnets_cidr_blocks == tolist(["10.0.64.0/24", "10.0.65.0/24"]) && output.elasticache_subnet_group_name == "unit-test"
    error_message = "ElastiCache subnets and their subnet group must be created from the given list."
  }

  assert {
    condition     = length(aws_route_table.elasticache) == 0 && length(aws_route_table_association.elasticache) == 0
    error_message = "ElastiCache subnets get no route table unless asked."
  }

  assert {
    condition     = output.redshift_subnet_group_name == "unit-test-redshift" && aws_redshift_subnet_group.redshift[0].subnet_ids == toset(aws_subnet.redshift[*].id)
    error_message = "The Redshift subnet group must hold the Redshift subnets, with a lower-case name."
  }

  assert {
    condition     = length(aws_route_table.redshift) == 1 && aws_route_table_association.redshift[*].route_table_id == [aws_route_table.redshift[0].id, aws_route_table.redshift[0].id]
    error_message = "Redshift subnets must share their own route table when asked."
  }
}

run "no_elasticache_or_redshift_by_default" {
  command = plan

  assert {
    condition     = length(aws_subnet.elasticache) == 0 && length(aws_subnet.redshift) == 0 && length(aws_elasticache_subnet_group.elasticache) == 0 && length(aws_redshift_subnet_group.redshift) == 0
    error_message = "ElastiCache and Redshift subnets are never carved."
  }
}

run "public_network_acl_default_rules" {
  command = plan

  variables {
    public_dedicated_network_acl = true
    secondary_cidr_blocks        = ["100.64.0.0/16"]
  }

  assert {
    condition     = aws_network_acl_rule.this["public-ingress-310"].from_port == 443 && aws_network_acl_rule.this["public-ingress-300"].from_port == 80 && aws_network_acl_rule.this["public-ingress-300"].cidr_block == "0.0.0.0/0"
    error_message = "The public NACL must allow HTTP and HTTPS from anywhere."
  }

  assert {
    condition     = aws_network_acl_rule.this["public-ingress-101"].cidr_block == "100.64.0.0/16"
    error_message = "VPC rules must cover secondary CIDR blocks."
  }

  assert {
    condition     = length(aws_network_acl.this) == 1 && contains(keys(aws_network_acl.this), "public")
    error_message = "Only the tiers asked for get a dedicated NACL."
  }
}

run "intra_network_acl_stays_inside_vpc" {
  command = plan

  variables {
    intra_subnets               = ["10.0.48.0/24"]
    intra_dedicated_network_acl = true
  }

  assert {
    condition     = toset([for k, r in aws_network_acl_rule.this : r.cidr_block]) == toset(["10.0.0.0/16"])
    error_message = "The intra NACL must only allow VPC traffic."
  }

  assert {
    condition     = aws_network_acl_rule.this["intra-egress-100"].egress && aws_network_acl_rule.this["intra-ingress-100"].protocol == "-1"
    error_message = "The intra NACL must allow VPC traffic both ways."
  }
}

run "network_acls_with_ipv6" {
  command = apply

  variables {
    enable_ipv6                    = true
    private_dedicated_network_acl  = true
    redshift_subnets               = ["10.0.80.0/24"]
    redshift_dedicated_network_acl = true
  }

  assert {
    condition     = aws_network_acl_rule.this["private-ingress-110"].ipv6_cidr_block == "2600:1f18:abcd:1200::/56" && aws_network_acl_rule.this["private-ingress-220"].ipv6_cidr_block == "::/0"
    error_message = "With IPv6 on, the private NACL must allow VPC IPv6 traffic and IPv6 replies."
  }

  assert {
    condition     = aws_network_acl_rule.this["private-egress-110"].ipv6_cidr_block == "::/0" && aws_network_acl.this["redshift"].subnet_ids == toset(aws_subnet.redshift[*].id)
    error_message = "IPv6 egress must be allowed, and the Redshift NACL must hold its subnets."
  }
}

run "no_dedicated_network_acls_by_default" {
  command = plan

  variables {
    intra_subnets       = ["10.0.48.0/24"]
    elasticache_subnets = ["10.0.64.0/24"]
  }

  assert {
    condition     = length(aws_network_acl.this) == 0 && length(aws_network_acl_rule.this) == 0
    error_message = "Dedicated NACLs are opt-in."
  }
}
