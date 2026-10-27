# Changelog

All notable changes to this module are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Validations for `instance_tenancy`, `flow_log_traffic_type`, `flow_log_destination_type` and `flow_log_max_aggregation_interval`. Invalid values now fail at plan time instead of at apply time (#9).
- `flow_log_file_format`, `flow_log_hive_compatible_partitions` and `flow_log_per_hour_partition` for S3 flow log destinations. Previously an S3 destination failed because these variables were missing (#9).
- `examples/minimal` and `examples/complete`, replacing `example/`, which was a module call with no provider. The complete example covers NAT, flow logs, the database subnet group, route table and network ACL, the default security group, and VPN gateways with route propagation (#10, #12).
- `database_inbound_acl_rules` and `database_outbound_acl_rules` for the dedicated database network ACL. Both default to one rule that allows all traffic, as upstream does. NACLs are stateless, so tighter rules must also allow return traffic for anything the database subnets reach out to (#10).
- `manage_default_route_table`, `default_route_table_name` and `default_route_table_tags`, and `default_network_acl_name`, `default_network_acl_ingress`, `default_network_acl_egress` and `default_network_acl_tags`, for managing the VPC default route table and default network ACL (#11).
- Outputs for the internet gateway, egress-only gateway, NAT gateways and their public IPs, database subnet ARNs and CIDRs, database route tables, the AZs in use, the VPC IPv6 CIDR, and the flow log, its destination, IAM role and log group (#13).

### Changed

- **Breaking:** the minimum Terraform version is now `1.3.0` (was `0.13.1`), and the minimum AWS provider version is now `6.0` (was `3.67`). There is no upper bound. #9 added a `< 7.0` cap and #12 removed it again, following the team standard of `>=` constraints only. To migrate, upgrade Terraform to 1.3.0 or later and the AWS provider to 6.0 or later, then run `terraform init -upgrade` and review the plan before applying (#9, #12).
- **Breaking:** `flow_log_cloudwatch_log_group_retention_in_days` defaults to `365` (was `null` in `v0.0.5`, which kept logs forever). #9 set it to `90`, and #11 raised it to a year. Existing CloudWatch flow log groups created by the module change to 365-day retention on the next apply. Set the variable to `0` to keep logs forever (#9, #11).
- **Breaking:** `vpn_gateway_id`, `flow_log_destination_arn`, `flow_log_cloudwatch_iam_role_arn` and `flow_log_cloudwatch_log_group_name_suffix` default to `null` instead of `""`, and an empty string now fails validation at plan time. To migrate, replace any `""` you pass for these with `null` or remove the argument. The behaviour for `null` matches what `""` used to do (#12).
- **Breaking:** outputs for resources that are not created return `null` instead of `""`. This covers the `vpc_*`, `default_*`, `vgw_*`, `default_vpc_*` and `database_subnet_group*` outputs. To migrate, replace checks such as `output != ""` with `output != null`, and wrap string interpolation of these outputs in `coalesce()` or a conditional (#12).
- `customer_gateways` is now a map of objects with `bgp_asn`, `ip_address` and optional `device_name`, instead of `map(map(any))`. Inputs that worked before keep working; a numeric `bgp_asn` is converted to the string the provider expects. A missing `bgp_asn` or `ip_address` is now reported as a type error at plan time (#12).
- **Breaking:** `default_security_group_ingress` and `default_security_group_egress` are now lists of objects. `cidr_blocks`, `ipv6_cidr_blocks`, `prefix_list_ids` and `security_groups` are lists instead of comma-separated strings, `from_port` and `to_port` are numbers, and `self` is a bool. Defaults are unchanged: ports `0`, protocol `"-1"`, empty lists. To migrate, change `cidr_blocks = "10.0.0.0/8,172.16.0.0/12"` to `cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]`, and the same for the other three. Old string input fails at plan time with "Invalid value for input variable" (#12).
- **Breaking:** subnet inputs the module used to ignore now fail at plan time with an error that says what to set. This covers `public_subnets` or `private_subnets` passed without `cidr` (they were replaced by subnets carved from `172.31.0.0/16`), `use_ipam_pool = true` without subnet lists (subnets were carved from `172.31.0.0/16`, outside the IPAM range), and automatic carving of a VPC smaller than `/20` (a `/24` gave `/32` subnets). To migrate, set `cidr` to the range that holds your subnets, pass subnet lists with IPAM, or use a `/20` or larger VPC (#10).
- **Breaking:** the module now adopts the VPC default route table and default network ACL. `manage_default_route_table` and `manage_default_network_acl` default to `true`; `manage_default_network_acl` existed before but did nothing. The default route table keeps only its local route, so subnets not associated with another route table have no path out of the VPC. The default network ACL gets explicit allow-all IPv4 and IPv6 rules. Routes or rules added to either outside Terraform are deleted on the next apply. To keep managing them yourself, set both variables to `false` (#11).
- **Breaking:** `cidr` is required unless the VPC range comes from IPAM. It defaulted to `0.0.0.0/0`, which the module turned into `172.31.0.0/16`, the same range as the AWS default VPC, so it clashed with peering, Transit Gateway and VPN. A missing `cidr` now fails at plan time, and `0.0.0.0/0` fails validation. To migrate, set `cidr` explicitly; set it to `172.31.0.0/16` to keep a VPC created with the old default (#11).
- **Breaking:** `name` is required. It defaulted to `sudo-vpc`, so two VPCs created with the defaults in one region collided on the database subnet group name. To migrate, set `name`; set it to `sudo-vpc` to keep resources created with the old default unchanged (#11).
- **Breaking:** `map_public_ip_on_launch` defaults to `false` (was `true`). Instances launched in public subnets no longer get a public IPv4 address automatically. Existing public subnets change in place on the next apply; running instances keep their addresses. Set the variable to `true` to keep the old behaviour (#11).
- **Breaking:** `azs` is required, with at least one entry and no blank or repeated entries. The module no longer looks availability zones up, so a new AZ in the region can no longer move subnets. To migrate, set `azs` to the zones your subnets use now. If you did not set `azs` before, the module used zone IDs, the region's first ones in order (such as `["euw1-az1", "euw1-az2", "euw1-az3"]`); pass those IDs, not names, because names map to different zones in each account and a mismatch replaces the subnets (#13).

### Removed

- **Breaking:** the unused variables `default_vpc_enable_classiclink` and `propagate_intra_route_tables_vgw`. Neither changed any resource. To migrate, delete them from your module call, otherwise Terraform reports an unsupported argument (#12).
- **Breaking:** the `hashicorp/random` provider requirement and the `random_string.random` resource. The random suffix only ever reached the default security group Name tag: with `name = "sudo-vpc"` (the default) that tag changes in place from `sudo-vpc-<6 random characters>-default-security-group` to `sudo-vpc-default-security-group`, and `random_string.random` is destroyed on the next apply. Nothing in AWS is replaced. To keep a unique tag, set `name` or `default_security_group_name` (#12).

### Fixed

- `aws_vpn_gateway_attachment` is no longer created when `create_vpc = false`. Before, setting `vpn_gateway_id` without a VPC still planned an attachment, with an empty `vpc_id` (#12).
- The `default_vpc_enable_dns_hostnames` description now states the real default, `false` (#12).
- Flow logs with an S3 destination no longer send an empty `iam_role_arn`; it is now `null` (#12).
- `one_nat_gateway_per_az = true` now routes each private subnet through the NAT gateway in its own AZ. Before, every private subnet was associated with the first private route table, so losing that AZ cut egress for all of them. Existing VPCs with this setting see the private route table associations replaced on the next apply (#10).
- `single_nat_gateway = false` with subnets carved by the module now creates one NAT gateway and private route table per private subnet. Before, it created none and the plan failed (#10).
- Private VGW route propagation now creates one propagation per private route table. Before, it created one per entry in `private_subnets`: with a single NAT gateway that put several propagations on the same route table, and with subnets carved by the module it created none (#10).
- `create_database_subnet_route_table = true` now associates the database subnets with the database route table, so the database NAT and internet gateway routes take effect. Before, no association existed and the subnets stayed on the main route table. Existing VPCs with this setting get the associations on the next apply, which moves the database subnets onto the database route table (#10).
- Database route tables and routes now follow the subnets the module actually creates: database subnets carved from `cidr` get a route table, per-AZ database route tables no longer fail the plan when `azs` is not set, and `one_nat_gateway_per_az` gives each database subnet the route table and NAT gateway of its AZ. With `one_nat_gateway_per_az = true`, existing VPCs gain the second and third database route tables on the next apply (#10).
- `database_dedicated_network_acl = true` no longer denies all traffic. The NACL was created with no rules, which made every database in those subnets unreachable. It now gets the rules from `database_inbound_acl_rules` and `database_outbound_acl_rules`, which allow all traffic by default. Existing VPCs with this setting get the allow-all rules on the next apply (#10).
- With `use_ipam_pool = true`, the given `public_subnets`, `private_subnets` and `database_subnets` are now used. Before, they were ignored unless `cidr` was also set (#10).
- Automatic subnet carving works in regions with two availability zones. It carves one subnet per tier per AZ, up to three, using the AZs in `azs` when given. Before, it always carved three per tier and failed the plan in a 2-AZ region (#11).
- With `enable_ipv6 = true`, private subnets get a `::/0` route through the egress-only internet gateway, one per private route table. Before, only the public and database tiers had an IPv6 default route, so private IPv6 egress did not work (#11).
- The egress-only internet gateway is created when the module carves the subnets. Before, it was only created when subnet lists were passed in (#11).

### Security

- The VPC flow log IAM policy is scoped to the flow log group, instead of `resources = ["*"]`: stream writes are limited to that group, and `DescribeLogGroups` to the account and region. The role trust policy now requires `aws:SourceAccount` to be this account and `aws:SourceArn` to be one of its flow logs, which blocks confused deputy use of the role. Existing roles and policies are updated in place on the next apply (#11).

<!--
Group entries under Added, Changed, Deprecated, Removed, Fixed or Security, and drop the
headings you do not need. On release, rename this section to the version and date and add a
link for it at the bottom, for example:

## [1.0.0] - YYYY-MM-DD

### Added

- Initial release.

[1.0.0]: https://github.com/sudo-terraform-aws-modules/<repo>/releases/tag/v1.0.0
-->

[Unreleased]: https://github.com/sudo-terraform-aws-modules/terraform-aws-sudo-vpc/compare/v0.0.5...HEAD
