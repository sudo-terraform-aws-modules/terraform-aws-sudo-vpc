locals {
  max_subnet_length = max(
    length(var.public_subnets),
    length(var.private_subnets),
  )
  actual_subnet_length = max(
    length(local.public_subnets),
    length(local.private_subnets),
  )
  nat_gateway_count  = local.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(local.public_subnets) : local.actual_subnet_length
  single_nat_gateway = var.one_nat_gateway_per_az ? false : var.single_nat_gateway
  # Use `local.vpc_id` to give a hint to Terraform that subnets should be deleted before secondary CIDR blocks can be free!
  vpc_id                      = try(aws_vpc_ipv4_cidr_block_association.this[0].vpc_id, aws_vpc.this[0].id, "")
  default_security_group_name = coalesce(var.default_security_group_name, "${var.name}-default-security-group")
  cidr                        = var.cidr
  create_vpc                  = var.create_vpc

  azs = var.azs

  # DNS64 only means something on subnets with an IPv6 range.
  private_dns64 = var.enable_ipv6 && var.private_subnet_enable_dns64 && length(var.private_subnet_ipv6_prefixes) > 0

  # Carving splits cidr into four blocks and each block into three subnets, 8 bits in all.
  # A /20 gives /28 subnets, the smallest AWS allows; smaller VPCs are rejected below.
  # One subnet per tier per AZ in var.azs, up to three.
  carve_az_count = min(3, length(var.azs))
  carve_prefix   = try(tonumber(split("/", local.cidr)[1]), null)
  subnets        = try([for cidr_block in cidrsubnets(local.cidr, 4, 4, 4, 4) : slice(cidrsubnets(cidr_block, 4, 4, 4), 0, local.carve_az_count)], [[], [], []])

  # Given subnet lists are always used; without them the module carves subnets from cidr.
  use_given_subnets = local.max_subnet_length > 0

  # Create private subnets without NAT in default mode.
  public_subnets   = local.use_given_subnets ? var.public_subnets : local.subnets[0]
  private_subnets  = local.use_given_subnets ? var.private_subnets : local.subnets[1]
  database_subnets = local.use_given_subnets ? var.database_subnets : local.subnets[2]

  enable_flow_log = local.create_vpc && var.enable_flow_log

  create_flow_log_cloudwatch_iam_role  = local.enable_flow_log && var.flow_log_destination_type != "s3" && var.create_flow_log_cloudwatch_iam_role
  create_flow_log_cloudwatch_log_group = local.enable_flow_log && var.flow_log_destination_type != "s3" && var.create_flow_log_cloudwatch_log_group

  flow_log_destination_arn                  = local.create_flow_log_cloudwatch_log_group ? try(aws_cloudwatch_log_group.flow_log[0].arn, null) : var.flow_log_destination_arn
  flow_log_iam_role_arn                     = var.flow_log_destination_type != "s3" && local.create_flow_log_cloudwatch_iam_role ? try(aws_iam_role.vpc_flow_log_cloudwatch[0].arn, null) : var.flow_log_cloudwatch_iam_role_arn
  flow_log_cloudwatch_log_group_name_suffix = var.flow_log_cloudwatch_log_group_name_suffix == null ? local.vpc_id : var.flow_log_cloudwatch_log_group_name_suffix
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  count = local.create_vpc ? 1 : 0

  cidr_block          = var.use_ipam_pool ? null : local.cidr
  ipv4_ipam_pool_id   = var.ipv4_ipam_pool_id
  ipv4_netmask_length = var.ipv4_netmask_length

  assign_generated_ipv6_cidr_block = var.enable_ipv6 && !var.use_ipam_pool ? true : null
  ipv6_cidr_block                  = var.ipv6_cidr
  ipv6_ipam_pool_id                = var.ipv6_ipam_pool_id
  ipv6_netmask_length              = var.ipv6_netmask_length

  instance_tenancy     = var.instance_tenancy
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.vpc_tags,
  )

  lifecycle {
    precondition {
      condition     = var.cidr != null || var.use_ipam_pool
      error_message = "Set cidr to the VPC's IPv4 range, for example 10.0.0.0/16, or take the range from IPAM with use_ipam_pool, ipv4_ipam_pool_id and ipv4_netmask_length."
    }

    precondition {
      condition     = !var.use_ipam_pool || local.max_subnet_length > 0
      error_message = "With use_ipam_pool = true the VPC range is only known after apply, so the module cannot carve subnets from it. Pass public_subnets and private_subnets (and database_subnets if needed) inside the IPAM range."
    }

    precondition {
      condition     = local.use_given_subnets || var.use_ipam_pool || var.cidr == null || try(local.carve_prefix <= 20, false)
      error_message = "Automatic subnet carving needs a VPC of /20 or larger, which gives /28 subnets, the smallest AWS allows. Use a larger cidr or pass public_subnets, private_subnets and database_subnets."
    }

    precondition {
      condition     = !(var.enable_ipv6 && var.private_subnet_enable_dns64) || var.enable_nat_gateway
      error_message = "DNS64 hands IPv6-only workloads synthesized addresses that only work through NAT64. Set enable_nat_gateway = true, or turn private_subnet_enable_dns64 off."
    }
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count = local.create_vpc && length(var.secondary_cidr_blocks) > 0 ? length(var.secondary_cidr_blocks) : 0

  # Do not turn this into `local.vpc_id`
  vpc_id = aws_vpc.this[0].id

  cidr_block = element(var.secondary_cidr_blocks, count.index)
}

################################################################################
# Subnet
################################################################################

resource "aws_subnet" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 && (false == var.one_nat_gateway_per_az || length(local.public_subnets) >= length(local.azs)) ? length(local.public_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = local.public_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  map_public_ip_on_launch         = var.map_public_ip_on_launch
  assign_ipv6_address_on_creation = var.public_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.public_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.public_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.public_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      Name = try(
        var.public_subnet_names[count.index],
        format("${var.name}-${var.public_subnet_suffix}-%s", element(local.azs, count.index))
      )
    },
    var.tags,
    var.public_subnet_tags,
  )
}

resource "aws_subnet" "private" {
  count = local.create_vpc && length(local.private_subnets) > 0 ? length(local.private_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = local.private_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  assign_ipv6_address_on_creation = var.private_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.private_subnet_assign_ipv6_address_on_creation
  enable_dns64                    = local.private_dns64

  ipv6_cidr_block = var.enable_ipv6 && length(var.private_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.private_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      Name = try(
        var.private_subnet_names[count.index],
        format("${var.name}-${var.private_subnet_suffix}-%s", element(local.azs, count.index))
      )
    },
    var.tags,
    var.private_subnet_tags,
  )
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  count = local.create_vpc && var.create_igw && length(local.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.igw_tags,
  )
}

resource "aws_egress_only_internet_gateway" "this" {
  count = local.create_vpc && var.create_egress_only_igw && var.enable_ipv6 && local.actual_subnet_length > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.igw_tags,
  )
}
################################################################################
# EIP
################################################################################

resource "aws_eip" "nat" {
  count = local.create_vpc && var.enable_nat_gateway && false == var.reuse_nat_ips ? local.nat_gateway_count : 0

  domain = "vpc"

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(local.azs, local.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
    var.nat_eip_tags,
  )
}

################################################################################
# Nat Gateway
################################################################################

locals {
  nat_gateway_ips = var.reuse_nat_ips ? var.external_nat_ip_ids : try(aws_eip.nat[*].id, [])
}

resource "aws_nat_gateway" "this" {
  count = local.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = element(
    local.nat_gateway_ips,
    local.single_nat_gateway ? 0 : count.index,
  )
  subnet_id = element(
    aws_subnet.public[*].id,
    local.single_nat_gateway ? 0 : count.index,
  )

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(local.azs, local.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
    var.nat_gateway_tags,
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat_gateway" {
  count = local.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  route_table_id         = element(aws_route_table.private[*].id, count.index)
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, count.index)

  timeouts {
    create = "5m"
  }
}



################################################################################
# Public routes
################################################################################

resource "aws_route_table" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.public_subnet_suffix}" },
    var.tags,
    var.public_route_table_tags,
  )
}

resource "aws_route" "public_internet_gateway" {
  count = local.create_vpc && var.create_igw && length(local.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_internet_gateway_ipv6" {
  count = local.create_vpc && var.create_igw && var.enable_ipv6 && length(local.public_subnets) > 0 ? 1 : 0

  route_table_id              = aws_route_table.public[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this[0].id
}

################################################################################
# Private routes
# There are as many routing tables as the number of NAT gateways
################################################################################

locals {
  private_route_table_count = local.create_vpc && local.actual_subnet_length > 0 ? local.nat_gateway_count : 0
}

resource "aws_route_table" "private" {
  count = local.private_route_table_count

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = local.single_nat_gateway ? "${var.name}-${var.private_subnet_suffix}" : format(
        "${var.name}-${var.private_subnet_suffix}-%s",
        element(local.azs, count.index),
      )
    },
    var.tags,
    var.private_route_table_tags,
  )
}

resource "aws_route" "private_ipv6_egress" {
  count = length(aws_egress_only_internet_gateway.this) > 0 ? local.private_route_table_count : 0

  route_table_id              = aws_route_table.private[count.index].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "private_dns64_nat_gateway" {
  count = local.create_vpc && local.private_dns64 && var.enable_nat_gateway ? local.private_route_table_count : 0

  route_table_id              = aws_route_table.private[count.index].id
  destination_ipv6_cidr_block = "64:ff9b::/96"
  nat_gateway_id              = element(aws_nat_gateway.this[*].id, count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_default_security_group" "this" {
  count = local.create_vpc && var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  dynamic "ingress" {
    for_each = var.default_security_group_ingress
    content {
      self             = ingress.value.self
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
      prefix_list_ids  = ingress.value.prefix_list_ids
      security_groups  = ingress.value.security_groups
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
    }
  }

  dynamic "egress" {
    for_each = var.default_security_group_egress
    content {
      self             = egress.value.self
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
      prefix_list_ids  = egress.value.prefix_list_ids
      security_groups  = egress.value.security_groups
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
    }
  }

  tags = merge(
    { "Name" = local.default_security_group_name },
    var.tags,
    var.default_security_group_tags,
  )
}

################################################################################
# Default route table and network ACL
################################################################################

# Adopting the default route table with no routes leaves only the local route, so a subnet
# that is not explicitly associated with a route table cannot reach outside the VPC.
resource "aws_default_route_table" "this" {
  count = local.create_vpc && var.manage_default_route_table ? 1 : 0

  default_route_table_id = aws_vpc.this[0].default_route_table_id
  route                  = []

  timeouts {
    create = "5m"
    update = "5m"
  }

  tags = merge(
    { "Name" = coalesce(var.default_route_table_name, "${var.name}-default") },
    var.tags,
    var.default_route_table_tags,
  )
}

resource "aws_default_network_acl" "this" {
  count = local.create_vpc && var.manage_default_network_acl ? 1 : 0

  default_network_acl_id = aws_vpc.this[0].default_network_acl_id

  # Subnets join the default NACL whenever they leave another one; AWS manages that.
  subnet_ids = null

  dynamic "ingress" {
    for_each = var.default_network_acl_ingress
    content {
      rule_no         = ingress.value.rule_no
      action          = ingress.value.action
      protocol        = ingress.value.protocol
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      icmp_type       = ingress.value.icmp_type
      icmp_code       = ingress.value.icmp_code
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
    }
  }

  dynamic "egress" {
    for_each = var.default_network_acl_egress
    content {
      rule_no         = egress.value.rule_no
      action          = egress.value.action
      protocol        = egress.value.protocol
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      icmp_type       = egress.value.icmp_type
      icmp_code       = egress.value.icmp_code
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
    }
  }

  tags = merge(
    { "Name" = coalesce(var.default_network_acl_name, "${var.name}-default") },
    var.tags,
    var.default_network_acl_tags,
  )

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

################################################################################
# Route table association
################################################################################

resource "aws_route_table_association" "private" {
  count = local.create_vpc && length(local.private_subnets) > 0 ? length(local.private_subnets) : 0

  subnet_id = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(
    aws_route_table.private[*].id,
    local.single_nat_gateway ? 0 : count.index,
  )
}

resource "aws_route_table_association" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 ? length(local.public_subnets) : 0

  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public[0].id
}

################################################################################
# Customer Gateways
################################################################################

resource "aws_customer_gateway" "this" {
  for_each = var.customer_gateways

  bgp_asn     = each.value.bgp_asn
  ip_address  = each.value.ip_address
  device_name = each.value.device_name
  type        = "ipsec.1"

  tags = merge(
    { Name = "${var.name}-${each.key}" },
    var.tags,
    var.customer_gateway_tags,
  )
}

################################################################################
# VPN Gateway
################################################################################

resource "aws_vpn_gateway" "this" {
  count = local.create_vpc && var.enable_vpn_gateway ? 1 : 0

  vpc_id            = local.vpc_id
  amazon_side_asn   = var.amazon_side_asn
  availability_zone = var.vpn_gateway_az

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.vpn_gateway_tags,
  )
}

resource "aws_vpn_gateway_attachment" "this" {
  count = local.create_vpc && var.vpn_gateway_id != null ? 1 : 0

  vpc_id         = local.vpc_id
  vpn_gateway_id = var.vpn_gateway_id
}

locals {
  propagate_vgw = local.create_vpc && (var.enable_vpn_gateway || var.vpn_gateway_id != null)
  # The module's own VPN gateway wins over an attached one, as before.
  propagation_vpn_gateway_id = try(aws_vpn_gateway.this[0].id, aws_vpn_gateway_attachment.this[0].vpn_gateway_id, null)
}

resource "aws_vpn_gateway_route_propagation" "public" {
  count = local.propagate_vgw && var.propagate_public_route_tables_vgw && length(local.public_subnets) > 0 ? 1 : 0

  route_table_id = aws_route_table.public[0].id
  vpn_gateway_id = local.propagation_vpn_gateway_id
}

# One propagation per private route table. There is one private route table per NAT gateway,
# not per private subnet, so counting subnets created duplicates.
resource "aws_vpn_gateway_route_propagation" "private" {
  count = local.propagate_vgw && var.propagate_private_route_tables_vgw ? local.private_route_table_count : 0

  route_table_id = aws_route_table.private[count.index].id
  vpn_gateway_id = local.propagation_vpn_gateway_id
}

################################################################################
# Defaults
################################################################################

resource "aws_default_vpc" "this" {
  count = var.manage_default_vpc ? 1 : 0

  enable_dns_support   = var.default_vpc_enable_dns_support
  enable_dns_hostnames = var.default_vpc_enable_dns_hostnames

  tags = merge(
    { "Name" = coalesce(var.default_vpc_name, "default") },
    var.tags,
    var.default_vpc_tags,
  )
}


################################################################################
# Database Subnets
################################################################################

locals {
  create_database_subnets = local.create_vpc && length(local.database_subnets) > 0 ? true : false
  #create_database_route_table = local.create_database_subnets && var.create_database_subnet_route_table
}

resource "aws_subnet" "database" {
  count = local.create_database_subnets ? length(local.database_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = local.database_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  assign_ipv6_address_on_creation = var.database_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.database_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.database_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.database_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      Name = try(
        var.database_subnet_names[count.index],
        format("${var.name}-${var.database_subnet_suffix}-%s", element(local.azs, count.index), )
      )
    },
    var.tags,
    var.database_subnet_tags,
  )

}

resource "aws_db_subnet_group" "database" {
  count = local.create_database_subnets && var.create_database_subnet_group ? 1 : 0

  name        = lower(coalesce(var.database_subnet_group_name, var.name))
  description = "Database subnet group for ${var.name}"
  subnet_ids  = aws_subnet.database[*].id

  tags = merge(
    {
      "Name" = lower(coalesce(var.database_subnet_group_name, var.name))
    },
    var.tags,
    var.database_subnet_group_tags,
  )
}

################################################################################
# Database routes
################################################################################

locals {
  create_database_route_table = local.create_database_subnets && var.create_database_subnet_route_table
  # One shared database route table unless each AZ has its own NAT gateway to route through.
  single_database_route_table = local.single_nat_gateway || var.create_database_internet_gateway_route
  database_route_table_count  = local.create_database_route_table ? (local.single_database_route_table ? 1 : length(local.database_subnets)) : 0
}

resource "aws_route_table" "database" {
  count = local.database_route_table_count

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = local.single_database_route_table ? "${var.name}-${var.database_subnet_suffix}" : format(
        "%s-${var.database_subnet_suffix}-%s",
        var.name,
        element(local.azs, count.index),
      )
    },
    var.tags,
    var.database_route_table_tags,
  )
}

resource "aws_route_table_association" "database" {
  count = local.create_database_route_table ? length(local.database_subnets) : 0

  subnet_id = aws_subnet.database[count.index].id
  route_table_id = element(
    aws_route_table.database[*].id,
    local.single_database_route_table ? 0 : count.index,
  )
}

resource "aws_route" "database_internet_gateway" {
  count = local.create_database_route_table && var.create_igw && var.create_database_internet_gateway_route && !var.create_database_nat_gateway_route ? 1 : 0

  route_table_id         = aws_route_table.database[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "database_nat_gateway" {
  count = local.create_database_route_table && !var.create_database_internet_gateway_route && var.create_database_nat_gateway_route && var.enable_nat_gateway ? local.database_route_table_count : 0

  route_table_id         = aws_route_table.database[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "database_ipv6_egress" {
  count = local.create_database_route_table && var.create_egress_only_igw && var.enable_ipv6 && var.create_database_internet_gateway_route ? 1 : 0

  route_table_id              = aws_route_table.database[0].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

################################################################################
# Intra subnets
# No internet route in either direction. One shared route table.
################################################################################

locals {
  create_intra_subnets = local.create_vpc && length(var.intra_subnets) > 0
}

resource "aws_subnet" "intra" {
  count = local.create_intra_subnets ? length(var.intra_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.intra_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  assign_ipv6_address_on_creation = var.intra_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.intra_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.intra_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.intra_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      Name = try(
        var.intra_subnet_names[count.index],
        format("${var.name}-${var.intra_subnet_suffix}-%s", element(local.azs, count.index))
      )
    },
    var.tags,
    var.intra_subnet_tags,
  )
}

resource "aws_route_table" "intra" {
  count = local.create_intra_subnets ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.intra_subnet_suffix}" },
    var.tags,
    var.intra_route_table_tags,
  )
}

resource "aws_route_table_association" "intra" {
  count = local.create_intra_subnets ? length(var.intra_subnets) : 0

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra[0].id
}

resource "aws_vpn_gateway_route_propagation" "intra" {
  count = local.propagate_vgw && var.propagate_intra_route_tables_vgw && local.create_intra_subnets ? 1 : 0

  route_table_id = aws_route_table.intra[0].id
  vpn_gateway_id = local.propagation_vpn_gateway_id
}

################################################################################
# ElastiCache subnets
################################################################################

locals {
  create_elasticache_subnets     = local.create_vpc && length(var.elasticache_subnets) > 0
  create_elasticache_route_table = local.create_elasticache_subnets && var.create_elasticache_subnet_route_table
}

resource "aws_subnet" "elasticache" {
  count = local.create_elasticache_subnets ? length(var.elasticache_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.elasticache_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  assign_ipv6_address_on_creation = var.elasticache_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.elasticache_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.elasticache_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.elasticache_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      Name = try(
        var.elasticache_subnet_names[count.index],
        format("${var.name}-${var.elasticache_subnet_suffix}-%s", element(local.azs, count.index))
      )
    },
    var.tags,
    var.elasticache_subnet_tags,
  )
}

resource "aws_elasticache_subnet_group" "elasticache" {
  count = local.create_elasticache_subnets && var.create_elasticache_subnet_group ? 1 : 0

  name        = lower(coalesce(var.elasticache_subnet_group_name, var.name))
  description = "ElastiCache subnet group for ${var.name}"
  subnet_ids  = aws_subnet.elasticache[*].id

  tags = merge(
    { "Name" = lower(coalesce(var.elasticache_subnet_group_name, var.name)) },
    var.tags,
    var.elasticache_subnet_group_tags,
  )
}

resource "aws_route_table" "elasticache" {
  count = local.create_elasticache_route_table ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.elasticache_subnet_suffix}" },
    var.tags,
    var.elasticache_route_table_tags,
  )
}

resource "aws_route_table_association" "elasticache" {
  count = local.create_elasticache_route_table ? length(var.elasticache_subnets) : 0

  subnet_id      = aws_subnet.elasticache[count.index].id
  route_table_id = aws_route_table.elasticache[0].id
}

################################################################################
# Redshift subnets
################################################################################

locals {
  create_redshift_subnets     = local.create_vpc && length(var.redshift_subnets) > 0
  create_redshift_route_table = local.create_redshift_subnets && var.create_redshift_subnet_route_table
}

resource "aws_subnet" "redshift" {
  count = local.create_redshift_subnets ? length(var.redshift_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.redshift_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) > 0 ? element(local.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(local.azs, count.index))) == 0 ? element(local.azs, count.index) : null
  assign_ipv6_address_on_creation = var.redshift_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.redshift_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.redshift_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.redshift_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      Name = try(
        var.redshift_subnet_names[count.index],
        format("${var.name}-${var.redshift_subnet_suffix}-%s", element(local.azs, count.index))
      )
    },
    var.tags,
    var.redshift_subnet_tags,
  )
}

resource "aws_redshift_subnet_group" "redshift" {
  count = local.create_redshift_subnets && var.create_redshift_subnet_group ? 1 : 0

  name        = lower(coalesce(var.redshift_subnet_group_name, var.name))
  description = "Redshift subnet group for ${var.name}"
  subnet_ids  = aws_subnet.redshift[*].id

  tags = merge(
    { "Name" = lower(coalesce(var.redshift_subnet_group_name, var.name)) },
    var.tags,
    var.redshift_subnet_group_tags,
  )
}

resource "aws_route_table" "redshift" {
  count = local.create_redshift_route_table ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.redshift_subnet_suffix}" },
    var.tags,
    var.redshift_route_table_tags,
  )
}

resource "aws_route_table_association" "redshift" {
  count = local.create_redshift_route_table ? length(var.redshift_subnets) : 0

  subnet_id      = aws_subnet.redshift[count.index].id
  route_table_id = aws_route_table.redshift[0].id
}

################################################################################
# Network ACLs
# One dedicated NACL per tier, opt-in. Without one a tier uses the default NACL.
################################################################################

locals {
  # var.cidr when given, so the rules are known at plan time and scanners can read them.
  vpc_ipv4_cidrs = local.create_vpc ? concat([var.use_ipam_pool ? aws_vpc.this[0].cidr_block : var.cidr], var.secondary_cidr_blocks) : []
  nacl_ipv6      = local.create_vpc && var.enable_ipv6

  # Building blocks for the default tier rules. NACLs are stateless, so ephemeral ports
  # must be open inbound for replies to anything the subnets reach out to. TCP skips 3389
  # so RDP is never open to the internet.
  nacl_rules_from_vpc = concat(
    [for i, cidr in local.vpc_ipv4_cidrs : { rule_number = 100 + i, rule_action = "allow", protocol = "-1", from_port = 0, to_port = 0, cidr_block = cidr, ipv6_cidr_block = null }],
    local.nacl_ipv6 ? [{ rule_number = 110, rule_action = "allow", protocol = "-1", from_port = 0, to_port = 0, cidr_block = null, ipv6_cidr_block = aws_vpc.this[0].ipv6_cidr_block }] : [],
  )
  nacl_rules_ephemeral = concat(
    [
      { rule_number = 200, rule_action = "allow", protocol = "tcp", from_port = 1024, to_port = 3388, cidr_block = "0.0.0.0/0", ipv6_cidr_block = null },
      { rule_number = 201, rule_action = "allow", protocol = "tcp", from_port = 3390, to_port = 65535, cidr_block = "0.0.0.0/0", ipv6_cidr_block = null },
      { rule_number = 210, rule_action = "allow", protocol = "udp", from_port = 1024, to_port = 65535, cidr_block = "0.0.0.0/0", ipv6_cidr_block = null },
    ],
    local.nacl_ipv6 ? [
      { rule_number = 220, rule_action = "allow", protocol = "tcp", from_port = 1024, to_port = 3388, cidr_block = null, ipv6_cidr_block = "::/0" },
      { rule_number = 221, rule_action = "allow", protocol = "tcp", from_port = 3390, to_port = 65535, cidr_block = null, ipv6_cidr_block = "::/0" },
      { rule_number = 230, rule_action = "allow", protocol = "udp", from_port = 1024, to_port = 65535, cidr_block = null, ipv6_cidr_block = "::/0" },
    ] : [],
  )
  nacl_rules_web = concat(
    [
      { rule_number = 300, rule_action = "allow", protocol = "tcp", from_port = 80, to_port = 80, cidr_block = "0.0.0.0/0", ipv6_cidr_block = null },
      { rule_number = 310, rule_action = "allow", protocol = "tcp", from_port = 443, to_port = 443, cidr_block = "0.0.0.0/0", ipv6_cidr_block = null },
    ],
    local.nacl_ipv6 ? [
      { rule_number = 320, rule_action = "allow", protocol = "tcp", from_port = 80, to_port = 80, cidr_block = null, ipv6_cidr_block = "::/0" },
      { rule_number = 330, rule_action = "allow", protocol = "tcp", from_port = 443, to_port = 443, cidr_block = null, ipv6_cidr_block = "::/0" },
    ] : [],
  )
  nacl_rules_all_out = concat(
    [{ rule_number = 100, rule_action = "allow", protocol = "-1", from_port = 0, to_port = 0, cidr_block = "0.0.0.0/0", ipv6_cidr_block = null }],
    local.nacl_ipv6 ? [{ rule_number = 110, rule_action = "allow", protocol = "-1", from_port = 0, to_port = 0, cidr_block = null, ipv6_cidr_block = "::/0" }] : [],
  )

  # Public: web traffic in from anywhere. Private tiers: VPC traffic and replies only.
  # Intra: VPC traffic only, both ways.
  network_acls = {
    public = {
      create   = local.create_vpc && var.public_dedicated_network_acl && length(local.public_subnets) > 0
      subnets  = aws_subnet.public[*].id
      suffix   = var.public_subnet_suffix
      tags     = var.public_acl_tags
      inbound  = var.public_inbound_acl_rules != null ? var.public_inbound_acl_rules : concat(local.nacl_rules_from_vpc, local.nacl_rules_ephemeral, local.nacl_rules_web)
      outbound = var.public_outbound_acl_rules != null ? var.public_outbound_acl_rules : local.nacl_rules_all_out
    }
    private = {
      create   = local.create_vpc && var.private_dedicated_network_acl && length(local.private_subnets) > 0
      subnets  = aws_subnet.private[*].id
      suffix   = var.private_subnet_suffix
      tags     = var.private_acl_tags
      inbound  = var.private_inbound_acl_rules != null ? var.private_inbound_acl_rules : concat(local.nacl_rules_from_vpc, local.nacl_rules_ephemeral)
      outbound = var.private_outbound_acl_rules != null ? var.private_outbound_acl_rules : local.nacl_rules_all_out
    }
    database = {
      create   = local.create_database_subnets && var.database_dedicated_network_acl
      subnets  = aws_subnet.database[*].id
      suffix   = var.database_subnet_suffix
      tags     = var.database_acl_tags
      inbound  = var.database_inbound_acl_rules != null ? var.database_inbound_acl_rules : concat(local.nacl_rules_from_vpc, local.nacl_rules_ephemeral)
      outbound = var.database_outbound_acl_rules != null ? var.database_outbound_acl_rules : local.nacl_rules_all_out
    }
    intra = {
      create   = local.create_intra_subnets && var.intra_dedicated_network_acl
      subnets  = aws_subnet.intra[*].id
      suffix   = var.intra_subnet_suffix
      tags     = var.intra_acl_tags
      inbound  = var.intra_inbound_acl_rules != null ? var.intra_inbound_acl_rules : local.nacl_rules_from_vpc
      outbound = var.intra_outbound_acl_rules != null ? var.intra_outbound_acl_rules : local.nacl_rules_from_vpc
    }
    elasticache = {
      create   = local.create_elasticache_subnets && var.elasticache_dedicated_network_acl
      subnets  = aws_subnet.elasticache[*].id
      suffix   = var.elasticache_subnet_suffix
      tags     = var.elasticache_acl_tags
      inbound  = var.elasticache_inbound_acl_rules != null ? var.elasticache_inbound_acl_rules : concat(local.nacl_rules_from_vpc, local.nacl_rules_ephemeral)
      outbound = var.elasticache_outbound_acl_rules != null ? var.elasticache_outbound_acl_rules : local.nacl_rules_all_out
    }
    redshift = {
      create   = local.create_redshift_subnets && var.redshift_dedicated_network_acl
      subnets  = aws_subnet.redshift[*].id
      suffix   = var.redshift_subnet_suffix
      tags     = var.redshift_acl_tags
      inbound  = var.redshift_inbound_acl_rules != null ? var.redshift_inbound_acl_rules : concat(local.nacl_rules_from_vpc, local.nacl_rules_ephemeral)
      outbound = var.redshift_outbound_acl_rules != null ? var.redshift_outbound_acl_rules : local.nacl_rules_all_out
    }
  }

  created_network_acls = { for tier, acl in local.network_acls : tier => acl if acl.create }

  network_acl_rules = merge(flatten([
    for tier, acl in local.created_network_acls : [
      { for rule in acl.inbound : "${tier}-ingress-${rule.rule_number}" => merge(rule, { tier = tier, egress = false }) },
      { for rule in acl.outbound : "${tier}-egress-${rule.rule_number}" => merge(rule, { tier = tier, egress = true }) },
    ]
  ])...)
}

resource "aws_network_acl" "this" {
  # checkov:skip=CKV2_AWS_1:False positive. Checkov cannot follow subnet_ids through for_each; each NACL is created only when its tier has subnets, and holds them.
  for_each = local.created_network_acls

  vpc_id     = local.vpc_id
  subnet_ids = each.value.subnets

  tags = merge(
    { "Name" = "${var.name}-${each.value.suffix}" },
    var.tags,
    each.value.tags,
  )
}

resource "aws_network_acl_rule" "this" {
  for_each = local.network_acl_rules

  network_acl_id = aws_network_acl.this[each.value.tier].id

  egress          = each.value.egress
  rule_number     = each.value.rule_number
  rule_action     = each.value.rule_action
  protocol        = each.value.protocol
  from_port       = each.value.from_port
  to_port         = each.value.to_port
  icmp_type       = try(each.value.icmp_type, null)
  icmp_code       = try(each.value.icmp_code, null)
  cidr_block      = each.value.cidr_block
  ipv6_cidr_block = each.value.ipv6_cidr_block
}

# The database NACL was the only one before per-tier NACLs.
moved {
  from = aws_network_acl.database[0]
  to   = aws_network_acl.this["database"]
}

################################################################################
# VPC endpoints
################################################################################

locals {
  route_table_ids = concat(
    aws_route_table.public[*].id,
    aws_route_table.private[*].id,
    aws_route_table.database[*].id,
    aws_route_table.intra[*].id,
    aws_route_table.elasticache[*].id,
    aws_route_table.redshift[*].id,
  )

  gateway_endpoints   = local.create_vpc ? var.gateway_endpoints : toset([])
  interface_endpoints = local.create_vpc ? var.interface_endpoints : toset([])

  # Private subnets are spread across azs in order, so the first length(azs) are in distinct AZs.
  interface_endpoint_subnet_ids = var.interface_endpoint_subnet_ids != null ? var.interface_endpoint_subnet_ids : slice(aws_subnet.private[*].id, 0, min(length(local.azs), length(aws_subnet.private)))
}

data "aws_vpc_endpoint_service" "gateway" {
  for_each = local.gateway_endpoints

  service      = each.key
  service_type = "Gateway"
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoints

  vpc_id            = local.vpc_id
  service_name      = data.aws_vpc_endpoint_service.gateway[each.key].service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.route_table_ids

  tags = merge(
    { "Name" = "${var.name}-${each.key}" },
    var.tags,
    var.vpc_endpoint_tags,
  )
}

data "aws_vpc_endpoint_service" "interface" {
  for_each = local.interface_endpoints

  service      = each.key
  service_type = "Interface"
}

resource "aws_security_group" "vpc_endpoints" {
  count = length(local.interface_endpoints) > 0 ? 1 : 0

  name_prefix = "${var.name}-vpc-endpoints-"
  description = "HTTPS from the VPC to the interface endpoints"
  vpc_id      = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-vpc-endpoints" },
    var.tags,
    var.vpc_endpoint_tags,
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints" {
  count = length(local.interface_endpoints) > 0 ? length(local.vpc_ipv4_cidrs) : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = local.vpc_ipv4_cidrs[count.index]
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_ipv6" {
  count = length(local.interface_endpoints) > 0 && var.enable_ipv6 ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "HTTPS from the VPC over IPv6"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = aws_vpc.this[0].ipv6_cidr_block
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = local.vpc_id
  service_name        = data.aws_vpc_endpoint_service.interface[each.key].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.interface_endpoint_subnet_ids
  security_group_ids  = concat(aws_security_group.vpc_endpoints[*].id, var.interface_endpoint_security_group_ids)
  private_dns_enabled = true

  tags = merge(
    { "Name" = "${var.name}-${each.key}" },
    var.tags,
    var.vpc_endpoint_tags,
  )

  lifecycle {
    precondition {
      condition     = length(local.interface_endpoint_subnet_ids) > 0
      error_message = "Interface endpoints need subnets. Create private subnets or set interface_endpoint_subnet_ids."
    }

    precondition {
      condition     = var.enable_dns_support && var.enable_dns_hostnames
      error_message = "Interface endpoints use private DNS, which needs enable_dns_support and enable_dns_hostnames."
    }
  }
}

################################################################################
# DHCP options
################################################################################

resource "aws_vpc_dhcp_options" "this" {
  count = local.create_vpc && var.enable_dhcp_options ? 1 : 0

  domain_name                       = var.dhcp_options_domain_name
  domain_name_servers               = var.dhcp_options_domain_name_servers
  ntp_servers                       = var.dhcp_options_ntp_servers
  netbios_name_servers              = var.dhcp_options_netbios_name_servers
  netbios_node_type                 = var.dhcp_options_netbios_node_type
  ipv6_address_preferred_lease_time = var.dhcp_options_ipv6_address_preferred_lease_time

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.dhcp_options_tags,
  )
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = local.create_vpc && var.enable_dhcp_options ? 1 : 0

  vpc_id          = local.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

################################################################################
# Block Public Access exclusions
# Exclusions only. The account-level Block Public Access mode affects every VPC in the
# account and region, so it belongs in the account baseline, not here.
################################################################################

resource "aws_vpc_block_public_access_exclusion" "vpc" {
  count = local.create_vpc && var.vpc_block_public_access_exclusion_mode != null ? 1 : 0

  vpc_id                          = local.vpc_id
  internet_gateway_exclusion_mode = var.vpc_block_public_access_exclusion_mode

  tags = merge(
    { "Name" = var.name },
    var.tags,
  )
}

resource "aws_vpc_block_public_access_exclusion" "public_subnets" {
  count = local.create_vpc && var.public_subnets_block_public_access_exclusion_mode != null ? length(aws_subnet.public) : 0

  subnet_id                       = aws_subnet.public[count.index].id
  internet_gateway_exclusion_mode = var.public_subnets_block_public_access_exclusion_mode

  tags = merge(
    { "Name" = aws_subnet.public[count.index].tags["Name"] },
    var.tags,
  )
}
