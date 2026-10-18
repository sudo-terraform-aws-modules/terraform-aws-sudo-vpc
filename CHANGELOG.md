# Changelog

All notable changes to this module are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the module uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Validations for `instance_tenancy`, `flow_log_traffic_type`, `flow_log_destination_type` and `flow_log_max_aggregation_interval`. Invalid values now fail at plan time instead of at apply time (#9).
- `flow_log_file_format`, `flow_log_hive_compatible_partitions` and `flow_log_per_hour_partition` for S3 flow log destinations. Previously an S3 destination failed because these variables were missing (#9).

### Changed

- **Breaking:** the minimum Terraform version is now `1.3.0` (was `0.13.1`), and the AWS provider must be `>= 6.0, < 7.0` (was `>= 3.67`). To migrate, upgrade Terraform to 1.3.0 or later and the AWS provider to 6.x, then run `terraform init -upgrade` and review the plan before applying (#9).
- **Breaking:** `flow_log_cloudwatch_log_group_retention_in_days` defaults to `90` (was `null`, which kept logs forever). Existing CloudWatch flow log groups created by the module change to 90-day retention on the next apply. Set the variable to `0` to keep logs forever (#9).
- **Breaking:** `vpn_gateway_id`, `flow_log_destination_arn`, `flow_log_cloudwatch_iam_role_arn` and `flow_log_cloudwatch_log_group_name_suffix` default to `null` instead of `""`, and an empty string now fails validation at plan time. To migrate, replace any `""` you pass for these with `null` or remove the argument. The behaviour for `null` matches what `""` used to do (#12).
- **Breaking:** outputs for resources that are not created return `null` instead of `""`. This covers the `vpc_*`, `default_*`, `vgw_*`, `default_vpc_*` and `database_subnet_group*` outputs. To migrate, replace checks such as `output != ""` with `output != null`, and wrap string interpolation of these outputs in `coalesce()` or a conditional (#12).

### Removed

- **Breaking:** the unused variables `default_vpc_enable_classiclink` and `propagate_intra_route_tables_vgw`. Neither changed any resource. To migrate, delete them from your module call, otherwise Terraform reports an unsupported argument (#12).

### Fixed

- `aws_vpn_gateway_attachment` is no longer created when `create_vpc = false`. Before, setting `vpn_gateway_id` without a VPC still planned an attachment, with an empty `vpc_id` (#12).
- The `default_vpc_enable_dns_hostnames` description now states the real default, `false` (#12).
- Flow logs with an S3 destination no longer send an empty `iam_role_arn`; it is now `null` (#12).

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
