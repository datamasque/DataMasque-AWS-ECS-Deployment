resource "aws_cloudwatch_log_group" "ecs_log_group" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "/ecs/${each.key}"
  # Default 7 days for disposable environments; raise via logRetentionDays in
  # the environment config for compliance/audit retention.
  retention_in_days = lookup(each.value, "logRetentionDays", 7)
}
