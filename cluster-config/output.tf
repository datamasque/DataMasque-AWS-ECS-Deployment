output "ecs_cluster_name" {
  description = "ECS Fargate cluster name"
  value       = { for cluster in sort(keys(local.ecs_config["ecs"]["clusters"])) : cluster => aws_ecs_cluster.datamasque_cluster[cluster].arn }
}
