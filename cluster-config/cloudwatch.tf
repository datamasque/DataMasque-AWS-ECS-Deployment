resource "aws_cloudwatch_log_group" "ecs_log_group" {
  for_each          = lookup(local.ecs_config["ecs"], "clusters", {})
  name              = "/ecs/${each.key}"
  retention_in_days = 7 # Optional: Retain logs for 7 days
}
