# terraform-aws-sudo-vpc

| [![Terraform CI](https://github.com/sudo-terraform-aws-modules/terraform-aws-sudo-vpc/actions/workflows/main.yml/badge.svg)](https://github.com/sudo-terraform-aws-modules/terraform-aws-sudo-vpc/actions/workflows/main.yml) | [![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.3.0-7B42BC?logo=terraform)](versions.tf) | [![AWS provider](https://img.shields.io/badge/aws%20provider-%3E%3D6.0.0-FF9900)](versions.tf) | [![License](https://img.shields.io/github/license/sudo-terraform-aws-modules/terraform-aws-sudo-vpc)](LICENSE) |
|---|---|---|---|

<img width="600" alt="SUDO x AWS" src="https://github.com/user-attachments/assets/f7044ff9-afce-4811-91c6-2f3c95635abb" />

Terraform module that creates an Amazon VPC and the network around it: public, private and database subnets across availability zones, an internet gateway, optional NAT gateways, route tables, a database subnet group and VPC flow logs. It can also create a VPN gateway and customer gateways, and it takes over the VPC's default security group and removes its rules.

Given only `name`, `cidr` and `azs`, the module carves three public, three private and three database subnets, one of each per availability zone in the first three zones of `azs`. With a `/16` `cidr` each subnet is a `/24`. There is no NAT gateway, so the private and database subnets have no route to the internet. Public subnets do not give instances a public IP on launch. Flow logs capture rejected traffic into a CloudWatch log group kept for 365 days, the default security group has no rules, the default route table has no routes, and the default network ACL allows all traffic. These defaults suit a sandbox or a first environment. For production, size the subnets yourself, turn on NAT gateways (one per AZ if an AZ outage must not cut egress) and consider `flow_log_traffic_type = "ALL"` for incident investigation.

## Usage

```hcl
module "vpc" {
  source  = "sudo-terraform-aws-modules/sudo-vpc/aws"
  version = "0.1.0"

  name = "acme-prod"
  cidr = "10.20.0.0/16"
  azs  = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnets   = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnets  = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
  database_subnets = ["10.20.64.0/24", "10.20.65.0/24", "10.20.66.0/24"]

  map_public_ip_on_launch = false

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = "prod"
  }
}
```

See [examples/minimal](examples/minimal) and [examples/complete](examples/complete). The complete example adds flow logs for all traffic with one-year retention, a database route table and network ACL, a VPN gateway with route propagation, and a customer gateway.

## Things to know before you apply

**Settings fixed at creation.** Changing `cidr` replaces the VPC and everything in it. `azs` is required rather than looked up, so a new availability zone in the region never moves subnets. Changing a subnet's CIDR or availability zone replaces that subnet, which fails while network interfaces are still attached to it. Subnets are created with `count`, so removing or reordering entries in a subnet list or in `azs` replaces every subnet after that position. With IPAM, pass the subnet lists yourself, because the range is only known after apply; the plan fails otherwise. Automatic subnet carving needs a `/20` or larger VPC.

**Deletion protection.** VPCs have no deletion protection. `terraform destroy` removes the VPC with all its subnets, gateways and route tables. AWS refuses to delete a subnet while other resources, such as load balancers, RDS instances or Lambda functions, still have network interfaces in it, so remove those first.

**Costs.** NAT gateways are billed per hour and per GB processed, and each one holds an Elastic IP. With `enable_nat_gateway = true` the module creates one NAT gateway for the VPC unless `single_nat_gateway` is set to `false`. Flow logs are billed for CloudWatch Logs ingestion and storage, and `flow_log_traffic_type = "ALL"` ingests far more than the default `REJECT`. Public IPv4 addresses, including those assigned through `map_public_ip_on_launch`, are billed per hour.

**Default route table and network ACL.** The module adopts both by default. Adopting the default route table removes every route except the local one, and adopting the default network ACL replaces its rules with `default_network_acl_ingress` and `default_network_acl_egress`. Routes or rules added to them outside Terraform are deleted on apply. Set `manage_default_route_table` or `manage_default_network_acl` to `false` to leave them alone.

**Secrets in state.** The module takes no secrets. State holds network IDs, CIDR ranges, the public IPs of the NAT gateways and the IP addresses of customer gateways. Treat it as internal network documentation and keep access to it narrow.

**Permissions the caller needs.** Applying needs EC2 permissions for VPCs, subnets, route tables, internet and NAT gateways, Elastic IPs, network ACLs, security groups and, if used, VPN and customer gateways. The default flow logs also need CloudWatch Logs permissions to create the log group and set its retention, and IAM permissions to create the flow log role and policy, attach them and pass the role (`iam:PassRole`). To leave IAM out, send flow logs to S3, or pass `flow_log_cloudwatch_iam_role_arn` with `create_flow_log_cloudwatch_iam_role = false`. `vpc_flow_log_permissions_boundary` sets a permissions boundary on the role the module creates.

**Naming.** The database subnet group is named after `name`, so use a `name` that is unique in the account and region.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_customer_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/customer_gateway) | resource |
| [aws_db_subnet_group.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_default_network_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_network_acl) | resource |
| [aws_default_route_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_route_table) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_default_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_vpc) | resource |
| [aws_egress_only_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/egress_only_internet_gateway) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_policy.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_network_acl.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl) | resource |
| [aws_network_acl_rule.database_inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_network_acl_rule.database_outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule) | resource |
| [aws_route.database_internet_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.database_ipv6_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.database_nat_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_ipv6_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_nat_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet_gateway_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_ipv4_cidr_block_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv4_cidr_block_association) | resource |
| [aws_vpn_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway) | resource |
| [aws_vpn_gateway_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_attachment) | resource |
| [aws_vpn_gateway_route_propagation.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_vpn_gateway_route_propagation.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_vpn_gateway_route_propagation.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.flow_log_cloudwatch_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.vpc_flow_log_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_amazon_side_asn"></a> [amazon\_side\_asn](#input\_amazon\_side\_asn) | (optional) Provide ASN for the gateway. Default: 64512 | `string` | `"64512"` | no |
| <a name="input_assign_ipv6_address_on_creation"></a> [assign\_ipv6\_address\_on\_creation](#input\_assign\_ipv6\_address\_on\_creation) | Assign IPv6 address on subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map\_public\_ip\_on\_launch | `bool` | `false` | no |
| <a name="input_azs"></a> [azs](#input\_azs) | Availability zone names or IDs in the region, for example ["eu-west-1a", "eu-west-1b", "eu-west-1c"]. Required, so a new AZ in the region never moves subnets. Subnets are spread across them in order, and carving uses the first three. | `list(string)` | n/a | yes |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | The IPv4 CIDR block for the VPC, for example 10.0.0.0/16. Required unless the range comes from IPAM (use\_ipam\_pool, ipv4\_ipam\_pool\_id and ipv4\_netmask\_length). Pick a range that does not overlap networks you peer or connect with; the AWS default VPC uses 172.31.0.0/16. | `string` | `null` | no |
| <a name="input_create_database_internet_gateway_route"></a> [create\_database\_internet\_gateway\_route](#input\_create\_database\_internet\_gateway\_route) | Controls if an internet gateway route for public database access should be created | `bool` | `false` | no |
| <a name="input_create_database_nat_gateway_route"></a> [create\_database\_nat\_gateway\_route](#input\_create\_database\_nat\_gateway\_route) | Controls if a nat gateway route should be created to give internet access to the database subnets | `bool` | `false` | no |
| <a name="input_create_database_subnet_group"></a> [create\_database\_subnet\_group](#input\_create\_database\_subnet\_group) | Controls if database subnet group should be created (n.b. database\_subnets must also be set) | `bool` | `true` | no |
| <a name="input_create_database_subnet_route_table"></a> [create\_database\_subnet\_route\_table](#input\_create\_database\_subnet\_route\_table) | Controls if separate route table for database should be created | `bool` | `false` | no |
| <a name="input_create_egress_only_igw"></a> [create\_egress\_only\_igw](#input\_create\_egress\_only\_igw) | Controls if an Egress Only Internet Gateway is created and its related routes. | `bool` | `true` | no |
| <a name="input_create_flow_log_cloudwatch_iam_role"></a> [create\_flow\_log\_cloudwatch\_iam\_role](#input\_create\_flow\_log\_cloudwatch\_iam\_role) | (optional) Create Flow Log CloudWatch IAM Role. Default: true | `bool` | `true` | no |
| <a name="input_create_flow_log_cloudwatch_log_group"></a> [create\_flow\_log\_cloudwatch\_log\_group](#input\_create\_flow\_log\_cloudwatch\_log\_group) | (optional) Create Flow Log CloudWatch Log Group. Default: true | `bool` | `true` | no |
| <a name="input_create_igw"></a> [create\_igw](#input\_create\_igw) | Controls if an Internet Gateway is created for public subnets and the related routes that connect them. | `bool` | `true` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Controls if VPC should be created (it affects almost all resources) | `bool` | `true` | no |
| <a name="input_customer_gateway_tags"></a> [customer\_gateway\_tags](#input\_customer\_gateway\_tags) | (optional) Customer Gateway additional tags | `map(string)` | `{}` | no |
| <a name="input_customer_gateways"></a> [customer\_gateways](#input\_customer\_gateways) | (optional) Map of customer gateways to create, keyed by a name used in the Name tag. bgp\_asn and ip\_address are required. | <pre>map(object({<br/>    bgp_asn     = string<br/>    ip_address  = string<br/>    device_name = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_database_dedicated_network_acl"></a> [database\_dedicated\_network\_acl](#input\_database\_dedicated\_network\_acl) | Whether to give the database subnets a dedicated network ACL with database\_inbound\_acl\_rules and database\_outbound\_acl\_rules, instead of the VPC default NACL | `bool` | `false` | no |
| <a name="input_database_inbound_acl_rules"></a> [database\_inbound\_acl\_rules](#input\_database\_inbound\_acl\_rules) | Inbound rules for the dedicated database network ACL, used when database\_dedicated\_network\_acl is true. NACLs are stateless, so allow return traffic for anything the subnets reach out to. Set cidr\_block or ipv6\_cidr\_block on each rule. Default: allow all. | <pre>list(object({<br/>    rule_number     = number<br/>    rule_action     = string<br/>    protocol        = string<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "cidr_block": "0.0.0.0/0",<br/>    "protocol": "-1",<br/>    "rule_action": "allow",<br/>    "rule_number": 100<br/>  }<br/>]</pre> | no |
| <a name="input_database_outbound_acl_rules"></a> [database\_outbound\_acl\_rules](#input\_database\_outbound\_acl\_rules) | Outbound rules for the dedicated database network ACL, used when database\_dedicated\_network\_acl is true. Same shape as database\_inbound\_acl\_rules. Default: allow all. | <pre>list(object({<br/>    rule_number     = number<br/>    rule_action     = string<br/>    protocol        = string<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "cidr_block": "0.0.0.0/0",<br/>    "protocol": "-1",<br/>    "rule_action": "allow",<br/>    "rule_number": 100<br/>  }<br/>]</pre> | no |
| <a name="input_database_route_table_tags"></a> [database\_route\_table\_tags](#input\_database\_route\_table\_tags) | Additional tags for the database route tables | `map(string)` | `{}` | no |
| <a name="input_database_subnet_assign_ipv6_address_on_creation"></a> [database\_subnet\_assign\_ipv6\_address\_on\_creation](#input\_database\_subnet\_assign\_ipv6\_address\_on\_creation) | Assign IPv6 address on database subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map\_public\_ip\_on\_launch | `bool` | `null` | no |
| <a name="input_database_subnet_group_name"></a> [database\_subnet\_group\_name](#input\_database\_subnet\_group\_name) | Name to be used on the database subnet group | `string` | `null` | no |
| <a name="input_database_subnet_group_tags"></a> [database\_subnet\_group\_tags](#input\_database\_subnet\_group\_tags) | Additional tags for the database subnet group | `map(string)` | `{}` | no |
| <a name="input_database_subnet_ipv6_prefixes"></a> [database\_subnet\_ipv6\_prefixes](#input\_database\_subnet\_ipv6\_prefixes) | Assigns IPv6 database subnet id based on the Amazon provided /56 prefix base 10 integer (0-256). Must be of equal length to the corresponding IPv4 subnet list | `list(string)` | `[]` | no |
| <a name="input_database_subnet_names"></a> [database\_subnet\_names](#input\_database\_subnet\_names) | Explicit values to use in the Name tag on database subnets. If empty, Name tags are generated. | `list(string)` | `[]` | no |
| <a name="input_database_subnet_suffix"></a> [database\_subnet\_suffix](#input\_database\_subnet\_suffix) | Suffix to append to database subnets name | `string` | `"database"` | no |
| <a name="input_database_subnet_tags"></a> [database\_subnet\_tags](#input\_database\_subnet\_tags) | Additional tags for the database subnets | `map(string)` | `{}` | no |
| <a name="input_database_subnets"></a> [database\_subnets](#input\_database\_subnets) | A list of database subnets inside the VPC | `list(string)` | `[]` | no |
| <a name="input_default_network_acl_egress"></a> [default\_network\_acl\_egress](#input\_default\_network\_acl\_egress) | (optional) Outbound rules for the default network ACL. Same shape as default\_network\_acl\_ingress. An empty list denies all outbound traffic. Default: allow all IPv4 and IPv6. | <pre>list(object({<br/>    rule_no         = number<br/>    action          = string<br/>    protocol        = string<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "action": "allow",<br/>    "cidr_block": "0.0.0.0/0",<br/>    "protocol": "-1",<br/>    "rule_no": 100<br/>  },<br/>  {<br/>    "action": "allow",<br/>    "ipv6_cidr_block": "::/0",<br/>    "protocol": "-1",<br/>    "rule_no": 101<br/>  }<br/>]</pre> | no |
| <a name="input_default_network_acl_ingress"></a> [default\_network\_acl\_ingress](#input\_default\_network\_acl\_ingress) | (optional) Inbound rules for the default network ACL. NACLs are stateless, so allow return traffic for anything the subnets reach out to. An empty list denies all inbound traffic. Default: allow all IPv4 and IPv6. | <pre>list(object({<br/>    rule_no         = number<br/>    action          = string<br/>    protocol        = string<br/>    from_port       = optional(number, 0)<br/>    to_port         = optional(number, 0)<br/>    icmp_type       = optional(number)<br/>    icmp_code       = optional(number)<br/>    cidr_block      = optional(string)<br/>    ipv6_cidr_block = optional(string)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "action": "allow",<br/>    "cidr_block": "0.0.0.0/0",<br/>    "protocol": "-1",<br/>    "rule_no": 100<br/>  },<br/>  {<br/>    "action": "allow",<br/>    "ipv6_cidr_block": "::/0",<br/>    "protocol": "-1",<br/>    "rule_no": 101<br/>  }<br/>]</pre> | no |
| <a name="input_default_network_acl_name"></a> [default\_network\_acl\_name](#input\_default\_network\_acl\_name) | (optional) Name tag for the default network ACL. null uses "<name>-default". Default: null | `string` | `null` | no |
| <a name="input_default_network_acl_tags"></a> [default\_network\_acl\_tags](#input\_default\_network\_acl\_tags) | (optional) Additional tags for the default network ACL | `map(string)` | `{}` | no |
| <a name="input_default_route_table_name"></a> [default\_route\_table\_name](#input\_default\_route\_table\_name) | (optional) Name tag for the default route table. null uses "<name>-default". Default: null | `string` | `null` | no |
| <a name="input_default_route_table_tags"></a> [default\_route\_table\_tags](#input\_default\_route\_table\_tags) | (optional) Additional tags for the default route table | `map(string)` | `{}` | no |
| <a name="input_default_security_group_egress"></a> [default\_security\_group\_egress](#input\_default\_security\_group\_egress) | List of egress rules to set on the default security group. An empty list removes all egress rules. from\_port and to\_port default to 0 and protocol to "-1" (all traffic). | <pre>list(object({<br/>    description      = optional(string)<br/>    from_port        = optional(number, 0)<br/>    to_port          = optional(number, 0)<br/>    protocol         = optional(string, "-1")<br/>    self             = optional(bool)<br/>    cidr_blocks      = optional(list(string), [])<br/>    ipv6_cidr_blocks = optional(list(string), [])<br/>    prefix_list_ids  = optional(list(string), [])<br/>    security_groups  = optional(list(string), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_default_security_group_ingress"></a> [default\_security\_group\_ingress](#input\_default\_security\_group\_ingress) | List of ingress rules to set on the default security group. An empty list removes all ingress rules. from\_port and to\_port default to 0 and protocol to "-1" (all traffic). | <pre>list(object({<br/>    description      = optional(string)<br/>    from_port        = optional(number, 0)<br/>    to_port          = optional(number, 0)<br/>    protocol         = optional(string, "-1")<br/>    self             = optional(bool)<br/>    cidr_blocks      = optional(list(string), [])<br/>    ipv6_cidr_blocks = optional(list(string), [])<br/>    prefix_list_ids  = optional(list(string), [])<br/>    security_groups  = optional(list(string), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_default_security_group_name"></a> [default\_security\_group\_name](#input\_default\_security\_group\_name) | Name to be used on the default security group | `string` | `null` | no |
| <a name="input_default_security_group_tags"></a> [default\_security\_group\_tags](#input\_default\_security\_group\_tags) | Additional tags for the default security group | `map(string)` | `{}` | no |
| <a name="input_default_vpc_enable_dns_hostnames"></a> [default\_vpc\_enable\_dns\_hostnames](#input\_default\_vpc\_enable\_dns\_hostnames) | (optional) Set to true to enable Default VPC DNS Hostname. Default: false | `bool` | `false` | no |
| <a name="input_default_vpc_enable_dns_support"></a> [default\_vpc\_enable\_dns\_support](#input\_default\_vpc\_enable\_dns\_support) | (optional) Set to true to enable Default VPC DNS Support. Default: true | `bool` | `true` | no |
| <a name="input_default_vpc_name"></a> [default\_vpc\_name](#input\_default\_vpc\_name) | (optional) Default VPC Name. Default: null | `string` | `null` | no |
| <a name="input_default_vpc_tags"></a> [default\_vpc\_tags](#input\_default\_vpc\_tags) | (optional) Default VPC tags. Default: {} | `map(string)` | `{}` | no |
| <a name="input_enable_dns_hostnames"></a> [enable\_dns\_hostnames](#input\_enable\_dns\_hostnames) | Should be true to enable DNS hostnames in the VPC | `bool` | `true` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Should be true to enable DNS support in the VPC | `bool` | `true` | no |
| <a name="input_enable_flow_log"></a> [enable\_flow\_log](#input\_enable\_flow\_log) | (optional) Enable Flow Logs. Default: true | `bool` | `true` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Requests an Amazon-provided IPv6 CIDR block with a /56 prefix length for the VPC. You cannot specify the range of IP addresses, or the size of the CIDR block. | `bool` | `false` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Should be true if you want to provision NAT Gateways for each of your private networks | `bool` | `false` | no |
| <a name="input_enable_vpn_gateway"></a> [enable\_vpn\_gateway](#input\_enable\_vpn\_gateway) | (optional) Set it to true if you want to create new vpn gateway. Default: false | `bool` | `false` | no |
| <a name="input_external_nat_ip_ids"></a> [external\_nat\_ip\_ids](#input\_external\_nat\_ip\_ids) | List of EIP IDs to be assigned to the NAT Gateways (used in combination with reuse\_nat\_ips) | `list(string)` | `[]` | no |
| <a name="input_flow_log_cloudwatch_iam_role_arn"></a> [flow\_log\_cloudwatch\_iam\_role\_arn](#input\_flow\_log\_cloudwatch\_iam\_role\_arn) | (optional) The ARN for the IAM role that's used to post flow logs to a CloudWatch Logs log group. When flow\_log\_destination\_arn is set to ARN of Cloudwatch Logs, this argument needs to be provided. Default: null | `string` | `null` | no |
| <a name="input_flow_log_cloudwatch_log_group_kms_key_id"></a> [flow\_log\_cloudwatch\_log\_group\_kms\_key\_id](#input\_flow\_log\_cloudwatch\_log\_group\_kms\_key\_id) | (optional) The ARN of the KMS Key to use when encrypting log data for VPC flow logs. | `string` | `null` | no |
| <a name="input_flow_log_cloudwatch_log_group_name_prefix"></a> [flow\_log\_cloudwatch\_log\_group\_name\_prefix](#input\_flow\_log\_cloudwatch\_log\_group\_name\_prefix) | (optional) Specifies the name prefix of CloudWatch Log Group for VPC flow logs. | `string` | `"/aws/vpc-flow-log/"` | no |
| <a name="input_flow_log_cloudwatch_log_group_name_suffix"></a> [flow\_log\_cloudwatch\_log\_group\_name\_suffix](#input\_flow\_log\_cloudwatch\_log\_group\_name\_suffix) | (optional) Specifies the name suffix of CloudWatch Log Group for VPC flow logs. null uses the VPC ID. Default: null | `string` | `null` | no |
| <a name="input_flow_log_cloudwatch_log_group_retention_in_days"></a> [flow\_log\_cloudwatch\_log\_group\_retention\_in\_days](#input\_flow\_log\_cloudwatch\_log\_group\_retention\_in\_days) | (optional) Specifies the number of days you want to retain log events in the specified log group for VPC flow logs. 0 keeps them forever. Default: 365 | `number` | `365` | no |
| <a name="input_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#input\_flow\_log\_destination\_arn) | (optional) The ARN of the CloudWatch log group or S3 bucket where VPC Flow Logs will be pushed. If this ARN is a S3 bucket the appropriate permissions need to be set on that bucket's policy. When create\_flow\_log\_cloudwatch\_log\_group is set to false this argument must be provided. Default: null | `string` | `null` | no |
| <a name="input_flow_log_destination_type"></a> [flow\_log\_destination\_type](#input\_flow\_log\_destination\_type) | Type of flow log destination. Can be s3 or cloud-watch-logs. Default: cloud-watch-logs | `string` | `"cloud-watch-logs"` | no |
| <a name="input_flow_log_file_format"></a> [flow\_log\_file\_format](#input\_flow\_log\_file\_format) | (optional) The format for the flow log. Valid values: plain-text, parquet. Default: plain-text | `string` | `"plain-text"` | no |
| <a name="input_flow_log_hive_compatible_partitions"></a> [flow\_log\_hive\_compatible\_partitions](#input\_flow\_log\_hive\_compatible\_partitions) | (optional) Indicates whether to use Hive-compatible prefixes for flow logs stored in Amazon S3. Default: false | `bool` | `false` | no |
| <a name="input_flow_log_log_format"></a> [flow\_log\_log\_format](#input\_flow\_log\_log\_format) | The fields to include in the flow log record, in the order in which they should appear. | `string` | `null` | no |
| <a name="input_flow_log_max_aggregation_interval"></a> [flow\_log\_max\_aggregation\_interval](#input\_flow\_log\_max\_aggregation\_interval) | (optional) The maximum interval of time during which a flow of packets is captured and aggregated into a flow log record. Valid Values: `60` seconds or `600` seconds. | `number` | `600` | no |
| <a name="input_flow_log_per_hour_partition"></a> [flow\_log\_per\_hour\_partition](#input\_flow\_log\_per\_hour\_partition) | (optional) Indicates whether to partition the flow log per hour. This reduces the cost and response time for queries. Default: false | `bool` | `false` | no |
| <a name="input_flow_log_traffic_type"></a> [flow\_log\_traffic\_type](#input\_flow\_log\_traffic\_type) | The type of traffic to capture. Valid values: ACCEPT, REJECT, ALL. Default: REJECT | `string` | `"REJECT"` | no |
| <a name="input_igw_tags"></a> [igw\_tags](#input\_igw\_tags) | Additional tags for the internet gateway | `map(string)` | `{}` | no |
| <a name="input_instance_tenancy"></a> [instance\_tenancy](#input\_instance\_tenancy) | A tenancy option for instances launched into the VPC | `string` | `"default"` | no |
| <a name="input_intra_route_table_tags"></a> [intra\_route\_table\_tags](#input\_intra\_route\_table\_tags) | Additional tags for the intra route table | `map(string)` | `{}` | no |
| <a name="input_intra_subnet_assign_ipv6_address_on_creation"></a> [intra\_subnet\_assign\_ipv6\_address\_on\_creation](#input\_intra\_subnet\_assign\_ipv6\_address\_on\_creation) | Assign IPv6 addresses on creation in intra subnets. null uses assign\_ipv6\_address\_on\_creation. | `bool` | `null` | no |
| <a name="input_intra_subnet_ipv6_prefixes"></a> [intra\_subnet\_ipv6\_prefixes](#input\_intra\_subnet\_ipv6\_prefixes) | IPv6 prefix numbers for the intra subnets, carved as /64s from the VPC IPv6 range. One per subnet, in order. | `list(string)` | `[]` | no |
| <a name="input_intra_subnet_names"></a> [intra\_subnet\_names](#input\_intra\_subnet\_names) | Names for the intra subnets, in order. Defaults to <name>-<intra\_subnet\_suffix>-<az>. | `list(string)` | `[]` | no |
| <a name="input_intra_subnet_suffix"></a> [intra\_subnet\_suffix](#input\_intra\_subnet\_suffix) | Suffix for intra subnet and route table names | `string` | `"intra"` | no |
| <a name="input_intra_subnet_tags"></a> [intra\_subnet\_tags](#input\_intra\_subnet\_tags) | Additional tags for the intra subnets | `map(string)` | `{}` | no |
| <a name="input_intra_subnets"></a> [intra\_subnets](#input\_intra\_subnets) | Intra subnets: no route to or from the internet. Created only from this list, never carved. | `list(string)` | `[]` | no |
| <a name="input_ipv4_ipam_pool_id"></a> [ipv4\_ipam\_pool\_id](#input\_ipv4\_ipam\_pool\_id) | (Optional) The ID of an IPv4 IPAM pool you want to use for allocating this VPC's CIDR. | `string` | `null` | no |
| <a name="input_ipv4_netmask_length"></a> [ipv4\_netmask\_length](#input\_ipv4\_netmask\_length) | (Optional) The netmask length of the IPv4 CIDR you want to allocate to this VPC. Requires specifying a ipv4\_ipam\_pool\_id. | `number` | `null` | no |
| <a name="input_ipv6_cidr"></a> [ipv6\_cidr](#input\_ipv6\_cidr) | (Optional) IPv6 CIDR block to request from an IPAM Pool. Can be set explicitly or derived from IPAM using `ipv6_netmask_length`. | `string` | `null` | no |
| <a name="input_ipv6_ipam_pool_id"></a> [ipv6\_ipam\_pool\_id](#input\_ipv6\_ipam\_pool\_id) | (Optional) IPAM Pool ID for a IPv6 pool. Conflicts with `assign_generated_ipv6_cidr_block`. | `string` | `null` | no |
| <a name="input_ipv6_netmask_length"></a> [ipv6\_netmask\_length](#input\_ipv6\_netmask\_length) | (Optional) Netmask length to request from IPAM Pool. Conflicts with `ipv6_cidr_block`. This can be omitted if IPAM pool as a `allocation_default_netmask_length` set. Valid values: `56`. | `number` | `null` | no |
| <a name="input_manage_default_network_acl"></a> [manage\_default\_network\_acl](#input\_manage\_default\_network\_acl) | (optional) Adopt the VPC's default network ACL and set its rules from default\_network\_acl\_ingress and default\_network\_acl\_egress. Every subnet without a dedicated NACL uses it. Default: true | `bool` | `true` | no |
| <a name="input_manage_default_route_table"></a> [manage\_default\_route\_table](#input\_manage\_default\_route\_table) | (optional) Adopt the VPC's default route table and remove every route except the local one, so subnets left on it have no path out of the VPC. Default: true | `bool` | `true` | no |
| <a name="input_manage_default_security_group"></a> [manage\_default\_security\_group](#input\_manage\_default\_security\_group) | Should be true to adopt and manage default security group | `bool` | `true` | no |
| <a name="input_manage_default_vpc"></a> [manage\_default\_vpc](#input\_manage\_default\_vpc) | (optional) Manage Default VPC. Default: false | `bool` | `false` | no |
| <a name="input_map_public_ip_on_launch"></a> [map\_public\_ip\_on\_launch](#input\_map\_public\_ip\_on\_launch) | (optional) Give instances launched in public subnets a public IPv4 address. Leave it false and attach Elastic IPs or use a load balancer where public access is needed. Default: false | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the VPC, used in the Name tag of every resource and as the database subnet group name. Use a name that is unique in the account and region, because subnet group names must be. | `string` | n/a | yes |
| <a name="input_nat_eip_tags"></a> [nat\_eip\_tags](#input\_nat\_eip\_tags) | Additional tags for the NAT EIP | `map(string)` | `{}` | no |
| <a name="input_nat_gateway_destination_cidr_block"></a> [nat\_gateway\_destination\_cidr\_block](#input\_nat\_gateway\_destination\_cidr\_block) | Used to pass a custom destination route for private NAT Gateway. If not specified, the default 0.0.0.0/0 is used as a destination route. | `string` | `"0.0.0.0/0"` | no |
| <a name="input_nat_gateway_tags"></a> [nat\_gateway\_tags](#input\_nat\_gateway\_tags) | Additional tags for the NAT gateways | `map(string)` | `{}` | no |
| <a name="input_one_nat_gateway_per_az"></a> [one\_nat\_gateway\_per\_az](#input\_one\_nat\_gateway\_per\_az) | Should be true if you want only one NAT Gateway per availability zone. Requires the number of `public_subnets` created to be greater than or equal to the number of availability zones in `var.azs`. | `bool` | `false` | no |
| <a name="input_private_route_table_tags"></a> [private\_route\_table\_tags](#input\_private\_route\_table\_tags) | Additional tags for the private route tables | `map(string)` | `{}` | no |
| <a name="input_private_subnet_assign_ipv6_address_on_creation"></a> [private\_subnet\_assign\_ipv6\_address\_on\_creation](#input\_private\_subnet\_assign\_ipv6\_address\_on\_creation) | Assign IPv6 address on private subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map\_public\_ip\_on\_launch | `bool` | `null` | no |
| <a name="input_private_subnet_ipv6_prefixes"></a> [private\_subnet\_ipv6\_prefixes](#input\_private\_subnet\_ipv6\_prefixes) | Assigns IPv6 private subnet id based on the Amazon provided /56 prefix base 10 integer (0-256). Must be of equal length to the corresponding IPv4 subnet list | `list(string)` | `[]` | no |
| <a name="input_private_subnet_names"></a> [private\_subnet\_names](#input\_private\_subnet\_names) | Explicit values to use in the Name tag on private subnets. If empty, Name tags are generated. | `list(string)` | `[]` | no |
| <a name="input_private_subnet_suffix"></a> [private\_subnet\_suffix](#input\_private\_subnet\_suffix) | Suffix to append to private subnets name | `string` | `"private"` | no |
| <a name="input_private_subnet_tags"></a> [private\_subnet\_tags](#input\_private\_subnet\_tags) | Additional tags for the private subnets | `map(string)` | `{}` | no |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | A list of private subnets inside the VPC | `list(string)` | `[]` | no |
| <a name="input_propagate_intra_route_tables_vgw"></a> [propagate\_intra\_route\_tables\_vgw](#input\_propagate\_intra\_route\_tables\_vgw) | Propagate VPN gateway routes into the intra route table | `bool` | `false` | no |
| <a name="input_propagate_private_route_tables_vgw"></a> [propagate\_private\_route\_tables\_vgw](#input\_propagate\_private\_route\_tables\_vgw) | (optional) Set to true to enable route table propagation. Default: false | `bool` | `false` | no |
| <a name="input_propagate_public_route_tables_vgw"></a> [propagate\_public\_route\_tables\_vgw](#input\_propagate\_public\_route\_tables\_vgw) | (optional) Set to true to enable route table propagation. Default: false | `bool` | `false` | no |
| <a name="input_public_route_table_tags"></a> [public\_route\_table\_tags](#input\_public\_route\_table\_tags) | Additional tags for the public route tables | `map(string)` | `{}` | no |
| <a name="input_public_subnet_assign_ipv6_address_on_creation"></a> [public\_subnet\_assign\_ipv6\_address\_on\_creation](#input\_public\_subnet\_assign\_ipv6\_address\_on\_creation) | Assign IPv6 address on public subnet, must be disabled to change IPv6 CIDRs. This is the IPv6 equivalent of map\_public\_ip\_on\_launch | `bool` | `null` | no |
| <a name="input_public_subnet_ipv6_prefixes"></a> [public\_subnet\_ipv6\_prefixes](#input\_public\_subnet\_ipv6\_prefixes) | Assigns IPv6 public subnet id based on the Amazon provided /56 prefix base 10 integer (0-256). Must be of equal length to the corresponding IPv4 subnet list | `list(string)` | `[]` | no |
| <a name="input_public_subnet_names"></a> [public\_subnet\_names](#input\_public\_subnet\_names) | Explicit values to use in the Name tag on public subnets. If empty, Name tags are generated. | `list(string)` | `[]` | no |
| <a name="input_public_subnet_suffix"></a> [public\_subnet\_suffix](#input\_public\_subnet\_suffix) | Suffix to append to public subnets name | `string` | `"public"` | no |
| <a name="input_public_subnet_tags"></a> [public\_subnet\_tags](#input\_public\_subnet\_tags) | Additional tags for the public subnets | `map(string)` | `{}` | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | A list of public subnets inside the VPC | `list(string)` | `[]` | no |
| <a name="input_reuse_nat_ips"></a> [reuse\_nat\_ips](#input\_reuse\_nat\_ips) | Should be true if you don't want EIPs to be created for your NAT Gateways and will instead pass them in via the 'external\_nat\_ip\_ids' variable | `bool` | `false` | no |
| <a name="input_secondary_cidr_blocks"></a> [secondary\_cidr\_blocks](#input\_secondary\_cidr\_blocks) | List of secondary CIDR blocks to associate with the VPC to extend the IP Address pool | `list(string)` | `[]` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Should be true if you want to provision a single shared NAT Gateway across all of your private networks | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_use_ipam_pool"></a> [use\_ipam\_pool](#input\_use\_ipam\_pool) | Determines whether IPAM pool is used for CIDR allocation | `bool` | `false` | no |
| <a name="input_vpc_flow_log_permissions_boundary"></a> [vpc\_flow\_log\_permissions\_boundary](#input\_vpc\_flow\_log\_permissions\_boundary) | (Optional) The ARN of the Permissions Boundary for the VPC Flow Log IAM Role | `string` | `null` | no |
| <a name="input_vpc_flow_log_tags"></a> [vpc\_flow\_log\_tags](#input\_vpc\_flow\_log\_tags) | (optional) Additional tags for the VPC Flow Logs | `map(string)` | `{}` | no |
| <a name="input_vpc_tags"></a> [vpc\_tags](#input\_vpc\_tags) | Additional tags for the VPC | `map(string)` | `{}` | no |
| <a name="input_vpn_gateway_az"></a> [vpn\_gateway\_az](#input\_vpn\_gateway\_az) | VPN Gateway Availability Zone | `string` | `null` | no |
| <a name="input_vpn_gateway_id"></a> [vpn\_gateway\_id](#input\_vpn\_gateway\_id) | (optional) Provide the ID of existing VPN gateway to attach to VPC. null attaches none. Default: null | `string` | `null` | no |
| <a name="input_vpn_gateway_tags"></a> [vpn\_gateway\_tags](#input\_vpn\_gateway\_tags) | (optional) Additional tags for the VPN gateway | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_azs"></a> [azs](#output\_azs) | Availability zones the subnets are spread across |
| <a name="output_cgw_arns"></a> [cgw\_arns](#output\_cgw\_arns) | Customer Gateway ARNs list |
| <a name="output_cgw_ids"></a> [cgw\_ids](#output\_cgw\_ids) | Customer Gateway ID List |
| <a name="output_database_route_table_ids"></a> [database\_route\_table\_ids](#output\_database\_route\_table\_ids) | Database route table IDs |
| <a name="output_database_subnet_arns"></a> [database\_subnet\_arns](#output\_database\_subnet\_arns) | Database subnet ARNs |
| <a name="output_database_subnet_group"></a> [database\_subnet\_group](#output\_database\_subnet\_group) | ID of database subnet group, or null when not created |
| <a name="output_database_subnet_group_name"></a> [database\_subnet\_group\_name](#output\_database\_subnet\_group\_name) | Name of database subnet group, or null when not created |
| <a name="output_database_subnets"></a> [database\_subnets](#output\_database\_subnets) | Database Subnet ID List |
| <a name="output_database_subnets_cidr_blocks"></a> [database\_subnets\_cidr\_blocks](#output\_database\_subnets\_cidr\_blocks) | Database subnet CIDR blocks |
| <a name="output_database_subnets_ipv6_cidr_blocks"></a> [database\_subnets\_ipv6\_cidr\_blocks](#output\_database\_subnets\_ipv6\_cidr\_blocks) | Database subnet IPv6 CIDR blocks |
| <a name="output_default_network_acl_id"></a> [default\_network\_acl\_id](#output\_default\_network\_acl\_id) | Default Network ACL ID, or null when not created |
| <a name="output_default_route_table_id"></a> [default\_route\_table\_id](#output\_default\_route\_table\_id) | Default Route Table ID, or null when not created |
| <a name="output_default_security_group_id"></a> [default\_security\_group\_id](#output\_default\_security\_group\_id) | Default Security Group ID, or null when not created |
| <a name="output_default_vpc_arn"></a> [default\_vpc\_arn](#output\_default\_vpc\_arn) | Default VPC ARN, or null when not created |
| <a name="output_default_vpc_cidr_block"></a> [default\_vpc\_cidr\_block](#output\_default\_vpc\_cidr\_block) | Default VPC CIDR Block, or null when not created |
| <a name="output_default_vpc_default_network_acl_id"></a> [default\_vpc\_default\_network\_acl\_id](#output\_default\_vpc\_default\_network\_acl\_id) | Default NACL ID of the Default VPC, or null when not created |
| <a name="output_default_vpc_default_route_table_id"></a> [default\_vpc\_default\_route\_table\_id](#output\_default\_vpc\_default\_route\_table\_id) | Default route table ID of the default VPC, or null when not created |
| <a name="output_default_vpc_default_security_group_id"></a> [default\_vpc\_default\_security\_group\_id](#output\_default\_vpc\_default\_security\_group\_id) | Security Group ID for default security group of default VPC, or null when not created |
| <a name="output_default_vpc_id"></a> [default\_vpc\_id](#output\_default\_vpc\_id) | Default VPC ID, or null when not created |
| <a name="output_egress_only_internet_gateway_id"></a> [egress\_only\_internet\_gateway\_id](#output\_egress\_only\_internet\_gateway\_id) | Egress-only internet gateway ID, or null when not created |
| <a name="output_igw_arn"></a> [igw\_arn](#output\_igw\_arn) | Internet gateway ARN, or null when not created |
| <a name="output_igw_id"></a> [igw\_id](#output\_igw\_id) | Internet gateway ID, or null when not created |
| <a name="output_intra_route_table_ids"></a> [intra\_route\_table\_ids](#output\_intra\_route\_table\_ids) | Intra route table IDs |
| <a name="output_intra_subnet_arns"></a> [intra\_subnet\_arns](#output\_intra\_subnet\_arns) | Intra subnet ARNs |
| <a name="output_intra_subnets"></a> [intra\_subnets](#output\_intra\_subnets) | Intra subnet IDs |
| <a name="output_intra_subnets_cidr_blocks"></a> [intra\_subnets\_cidr\_blocks](#output\_intra\_subnets\_cidr\_blocks) | Intra subnet CIDR blocks |
| <a name="output_nat_ids"></a> [nat\_ids](#output\_nat\_ids) | Elastic IP allocation IDs created for the NAT gateways |
| <a name="output_nat_public_ips"></a> [nat\_public\_ips](#output\_nat\_public\_ips) | Public IPs of the NAT gateways |
| <a name="output_natgw_ids"></a> [natgw\_ids](#output\_natgw\_ids) | NAT gateway IDs |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | Private route tables IDs |
| <a name="output_private_subnet_arns"></a> [private\_subnet\_arns](#output\_private\_subnet\_arns) | Private Subnet ARN List |
| <a name="output_private_subnets"></a> [private\_subnets](#output\_private\_subnets) | Private Subnet ID List |
| <a name="output_private_subnets_cidr_blocks"></a> [private\_subnets\_cidr\_blocks](#output\_private\_subnets\_cidr\_blocks) | Private Subnets CIDR Block list |
| <a name="output_private_subnets_ipv6_cidr_blocks"></a> [private\_subnets\_ipv6\_cidr\_blocks](#output\_private\_subnets\_ipv6\_cidr\_blocks) | Private Subnet IPv6 cidr blocks |
| <a name="output_public_route_table_ids"></a> [public\_route\_table\_ids](#output\_public\_route\_table\_ids) | public route tables IDs |
| <a name="output_public_subnet_arns"></a> [public\_subnet\_arns](#output\_public\_subnet\_arns) | Public Subnet ARN List |
| <a name="output_public_subnets"></a> [public\_subnets](#output\_public\_subnets) | Public Subnet ID List |
| <a name="output_public_subnets_cidr_blocks"></a> [public\_subnets\_cidr\_blocks](#output\_public\_subnets\_cidr\_blocks) | Public Subnet CIDR Block list |
| <a name="output_public_subnets_ipv6_cidr_blocks"></a> [public\_subnets\_ipv6\_cidr\_blocks](#output\_public\_subnets\_ipv6\_cidr\_blocks) | Public Subnet IPv6 CIDR block list |
| <a name="output_this_customer_gateway"></a> [this\_customer\_gateway](#output\_this\_customer\_gateway) | Customer Gateway attributes map |
| <a name="output_vgw_arn"></a> [vgw\_arn](#output\_vgw\_arn) | VPN Gateway ARN, or null when not created |
| <a name="output_vgw_id"></a> [vgw\_id](#output\_vgw\_id) | VPN Gateway ID, or null when not created |
| <a name="output_vpc_arn"></a> [vpc\_arn](#output\_vpc\_arn) | VPC ARN, or null when not created |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | VPC CIDR Block, or null when not created |
| <a name="output_vpc_flow_log_cloudwatch_iam_role_arn"></a> [vpc\_flow\_log\_cloudwatch\_iam\_role\_arn](#output\_vpc\_flow\_log\_cloudwatch\_iam\_role\_arn) | ARN of the IAM role flow logs use to write to CloudWatch, or null when not used |
| <a name="output_vpc_flow_log_cloudwatch_log_group_arn"></a> [vpc\_flow\_log\_cloudwatch\_log\_group\_arn](#output\_vpc\_flow\_log\_cloudwatch\_log\_group\_arn) | ARN of the flow log CloudWatch log group the module created, or null when not created |
| <a name="output_vpc_flow_log_cloudwatch_log_group_name"></a> [vpc\_flow\_log\_cloudwatch\_log\_group\_name](#output\_vpc\_flow\_log\_cloudwatch\_log\_group\_name) | Name of the flow log CloudWatch log group the module created, or null when not created |
| <a name="output_vpc_flow_log_destination_arn"></a> [vpc\_flow\_log\_destination\_arn](#output\_vpc\_flow\_log\_destination\_arn) | ARN of the flow log destination, or null when flow logs are off |
| <a name="output_vpc_flow_log_id"></a> [vpc\_flow\_log\_id](#output\_vpc\_flow\_log\_id) | Flow log ID, or null when not created |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID, or null when not created |
| <a name="output_vpc_ipv6_cidr_block"></a> [vpc\_ipv6\_cidr\_block](#output\_vpc\_ipv6\_cidr\_block) | VPC IPv6 CIDR block, or null when not created or IPv6 is off |
<!-- END_TF_DOCS -->
