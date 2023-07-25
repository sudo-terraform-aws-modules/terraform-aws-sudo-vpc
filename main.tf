locals {
  max_subnet_length = max(
    length(var.public_subnets),
    length(var.private_subnets),
  )
  actual_subnet_length = max(
    length(local.public_subnets),
    length(local.private_subnets),
  )
  nat_gateway_count = local.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(local.public_subnets) : local.max_subnet_length
  single_nat_gateway = var.one_nat_gateway_per_az ? false : var.single_nat_gateway
  # Use `local.vpc_id` to give a hint to Terraform that subnets should be deleted before secondary CIDR blocks can be free!
  vpc_id = try(aws_vpc_ipv4_cidr_block_association.this[0].vpc_id, aws_vpc.this[0].id, "")
  name = var.name == "sudo-vpc" ? "sudo-vpc-${random_string.random.result}" : var.name
  default_security_group_name = coalesce(var.default_security_group_name, "${local.name}-default-security-group")
  cidr = var.cidr == "0.0.0.0/0" ? "172.31.0.0/16" : var.cidr
  create_vpc = var.create_vpc
  cidr_prefix_match = regexall("/([0-9]{2})", local.cidr)
  cidr_prefix = length(local.cidr_prefix_match) > 0 ? tonumber(local.cidr_prefix_match[0][0]) : 16
  validate_cidr_prefix = local.max_subnet_length == 0 && var.cidr != "0.0.0.0/0" && local.cidr_prefix > 20 ? tobool("Please provide subnet addressing for VPC greater than /20 prefix") : true

  azs = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.azs.zone_ids,0,length(local.public_subnets))
  subnets = [for cidr_block in cidrsubnets(local.cidr, 4, 4, 4, 4) : cidrsubnets(cidr_block, 4, 4, 4)]

  # Create private subnets without NAT in default mode.
  public_subnets = local.max_subnet_length > 0 && var.cidr != "0.0.0.0/0" ? var .public_subnets : local.subnets[0]
  private_subnets = local.max_subnet_length > 0 && var.cidr != "0.0.0.0/0" ? var .private_subnets : local.subnets[1]
}
data "aws_availability_zones" "azs" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "random_string" "random" {
  length  = 6
  special = false
  upper   = false
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

  instance_tenancy               = var.instance_tenancy
  enable_dns_hostnames           = var.enable_dns_hostnames
  enable_dns_support             = var.enable_dns_support
  enable_classiclink             = null
  enable_classiclink_dns_support = null

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.vpc_tags,
  )
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count = local.create_vpc && length(var.secondary_cidr_blocks) > 0 ? length(var.secondary_cidr_blocks) : 0

  # Do not turn this into `local.vpc_id`
  vpc_id = aws_vpc.this[0].id

  cidr_block = element(var.secondary_cidr_blocks, count.index)
}

################################################################################
# DHCP Options Set
################################################################################

resource "aws_vpc_dhcp_options" "this" {
  count = local.create_vpc && var.enable_dhcp_options ? 1 : 0

  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers
  ntp_servers          = var.dhcp_options_ntp_servers
  netbios_name_servers = var.dhcp_options_netbios_name_servers
  netbios_node_type    = var.dhcp_options_netbios_node_type

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
# Subnet
################################################################################

resource "aws_subnet" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 && (false == var.one_nat_gateway_per_az || length(local.public_subnets) >= length(local.azs)) ? length(local.public_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = element(concat(local.public_subnets, [""]), count.index)
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

################################################################################
# EIP
################################################################################

resource "aws_eip" "nat" {
  count = local.create_vpc && var.enable_nat_gateway && false == var.reuse_nat_ips ? local.nat_gateway_count : 0

  vpc = true

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
# Publiс routes
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

resource "aws_route_table" "private" {
  count = local.create_vpc && local.actual_subnet_length > 0 ? local.nat_gateway_count : 0

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

resource "aws_default_security_group" "this" {
  count = local.create_vpc && var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  dynamic "ingress" {
    for_each = var.default_security_group_ingress
    content {
      self             = lookup(ingress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(ingress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(ingress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(ingress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(ingress.value, "security_groups", "")))
      description      = lookup(ingress.value, "description", null)
      from_port        = lookup(ingress.value, "from_port", 0)
      to_port          = lookup(ingress.value, "to_port", 0)
      protocol         = lookup(ingress.value, "protocol", "-1")
    }
  }

  dynamic "egress" {
    for_each = var.default_security_group_egress
    content {
      self             = lookup(egress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(egress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(egress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(egress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(egress.value, "security_groups", "")))
      description      = lookup(egress.value, "description", null)
      from_port        = lookup(egress.value, "from_port", 0)
      to_port          = lookup(egress.value, "to_port", 0)
      protocol         = lookup(egress.value, "protocol", "-1")
    }
  }

  tags = merge(
    { "Name" = local.default_security_group_name },
    var.tags,
    var.default_security_group_tags,
  )
}

################################################################################
# Route table association
################################################################################

resource "aws_route_table_association" "private" {
  count = local.create_vpc && length(local.private_subnets) > 0 ? length(local.private_subnets) : 0

  subnet_id = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(
    aws_route_table.private[*].id,
    var.single_nat_gateway ? 0 : count.index,
  )
}

resource "aws_route_table_association" "public" {
  count = local.create_vpc && length(local.public_subnets) > 0 ? length(local.public_subnets) : 0

  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public[0].id
}
