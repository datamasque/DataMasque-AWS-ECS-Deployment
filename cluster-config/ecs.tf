resource "aws_ecs_cluster" "datamasque_cluster" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = each.key

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = terraform.workspace
    Application = each.key
  }
}

resource "aws_ecs_task_definition" "agent_task" {
  for_each                 = lookup(local.ecs_config["ecs"], "clusters", {})
  family                   = "agent-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value["agentContainer"]["cpu"]    # Task-level CPU allocation
  memory                   = each.value["agentContainer"]["memory"] # Task-level memory allocation
  task_role_arn            = aws_iam_role.ecs_task_role[each.key].arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role[each.key].arn

  container_definitions = jsonencode([
    {
      name              = "${each.key}-agent-worker"
      image             = "${local.ecr_base_url[each.key]}/agent:${local.ecr_image_url[each.key].image_tag}"
      essential         = true
      user              = "1000:1000"
      entryPoint        = ["/entrypoint.sh"]
      cpu               = each.value["agentContainer"]["cpu"]    # Minimum CPU for this container
      memory            = each.value["agentContainer"]["memory"] # Minimum memory for this container
      memoryReservation = 256                                    # Soft memory limit
      environment = [
        { name = "LOGLEVEL", value = each.value["loggingLevel"] },
        { name = "MASQUE_SANDBOX_PATH", value = "/files/user/" },
        { name = "MASQUE_ENV", value = "prod" },
        { name = "MASQUE_VERSION", value = each.value["masqueVersion"] },
        { name = "MASQUE_HOST_SUFFIX", value = lookup(each.value, "dnsNamespace", "internal") }
      ]

      mountPoints = [
        { sourceVolume = "license", containerPath = "/license", readOnly = false },
        { sourceVolume = "files", containerPath = "/files", readOnly = false },
        { sourceVolume = "secrets", containerPath = "/.keys", readOnly = false }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = "/ecs/${each.key}" # Log group name
          awslogs-stream-prefix = "agent-worker"     # Stream prefix for log streams
        }
      }
    }
  ])
  volume {
    name = "license"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "files"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "secrets"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "datamasque-mounts"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }
}

resource "aws_ecs_service" "datamasque_agent_service" {
  depends_on             = [aws_ecs_service.queue_service, aws_db_instance.dm_pgdb]
  for_each               = lookup(local.ecs_config["ecs"], "clusters", {})
  name                   = "${each.key}-dm-agent-serv"
  cluster                = aws_ecs_cluster.datamasque_cluster[each.key].id
  task_definition        = aws_ecs_task_definition.agent_task[each.key].arn
  desired_count          = each.value["agentContainer"]["desiredCount"]
  enable_execute_command = true
  launch_type            = "FARGATE"

  network_configuration {
    subnets         = values(local.common_env_config.subnets)
    security_groups = [aws_security_group.ecs_sg[each.key].id] # Replace with your security group
  }
  service_registries {
    registry_arn = aws_service_discovery_service.agent[each.key].arn
  }
}

resource "aws_ecs_task_definition" "agent_queue" {
  depends_on               = [aws_cloudwatch_log_group.ecs_log_group]
  for_each                 = lookup(local.ecs_config["ecs"], "clusters", {})
  family                   = "datamasque-agent-queue-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role[each.key].arn
  task_role_arn      = aws_iam_role.ecs_task_role[each.key].arn

  container_definitions = jsonencode([
    {
      name      = "${each.key}-agent-queue"
      image     = "${local.ecr_base_url[each.key]}/agent-queue:${local.ecr_image_url[each.key].image_tag}"
      essential = true
      user      = "1000:1000"
      portMappings = [{
        containerPort = 6379
        hostPort      = 6379
      }]

      environment = [
        {
          name  = "POSTGRES_USER"
          value = "postgres"
        },
        { name = "MASQUE_HOST_SUFFIX", value = lookup(each.value, "dnsNamespace", "internal") }
      ]
      secrets = [
        {
          name      = "POSTGRES_PASSWORD"
          valueFrom = aws_secretsmanager_secret.datamasque_postgres[each.key].arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = "/ecs/${each.key}" # Log group name
          awslogs-stream-prefix = "agent-queue"      # Stream prefix for log streams
        }
      }
  }])
}

resource "aws_ecs_service" "queue_service" {
  for_each               = lookup(local.ecs_config["ecs"], "clusters", {})
  name                   = "${each.key}-queue-srv"
  cluster                = aws_ecs_cluster.datamasque_cluster[each.key].id
  task_definition        = aws_ecs_task_definition.agent_queue[each.key].arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"

  network_configuration {
    subnets         = values(local.common_env_config.subnets)
    security_groups = [aws_security_group.ecs_sg[each.key].id]
  }
  service_registries {
    registry_arn = aws_service_discovery_service.queue[each.key].arn
  }
}

resource "aws_ecs_task_definition" "admin_server" {
  depends_on               = [aws_cloudwatch_log_group.ecs_log_group]
  for_each                 = lookup(local.ecs_config["ecs"], "clusters", {})
  family                   = "datamasque-admin-server-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "4096"

  execution_role_arn = aws_iam_role.ecs_task_execution_role[each.key].arn
  task_role_arn      = aws_iam_role.ecs_task_role[each.key].arn

  container_definitions = jsonencode([

    {
      name       = "${each.key}-admin-server"
      image      = "${local.ecr_base_url[each.key]}/admin-server:${local.ecr_image_url[each.key].image_tag}"
      entryPoint = ["/entrypoint.sh"]
      essential  = true
      user       = "1000:1000" # Set the user to match EFS access point UID:GID
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = "/ecs/${each.key}" # Log group name
          awslogs-stream-prefix = "admin-server"     # Stream prefix for log streams
        }
      }
      mountPoints = [
        { sourceVolume = "license", containerPath = "/license", readOnly = false },
        { sourceVolume = "files", containerPath = "/files", readOnly = false },
        { sourceVolume = "secrets", containerPath = "/.keys/", readOnly = false },
        { sourceVolume = "datamasque-mounts", containerPath = "/datamasque-mounts", readOnly = false }
      ]
      environment = [
        { name = "MASQUE_ADMIN_ENV", value = "prod" },
        { name = "MASQUE_ADMIN_DB_NAME", value = "postgres" },
        { name = "MASQUE_ADMIN_DB_USER", value = "postgres" },
        { name = "MASQUE_HOST_SUFFIX", value = lookup(each.value, "dnsNamespace", "internal") },
        { name = "MASQUE_ADMIN_DB_HOST", value = "${aws_db_instance.dm_pgdb[each.key].address}" }, ##change it to FQDN
        { name = "MASQUE_ADMIN_DB_PORT", value = tostring(aws_db_instance.dm_pgdb[each.key].port) },
        { name = "MASQUE_SANDBOX_PATH", value = "/files/user/" },
        {
          name  = "MASQUE_VERSION"
          value = each.value["masqueVersion"]
        },
        {
          name  = "AGENT_QUEUE_SERVICE_HOST" # WE NEED FQDN
          value = "agent-queue.${lookup(each.value, "dnsNamespace", "internal")}"
        }

      ]
      portMappings = [{
        name          = "uwsgi"
        containerPort = 8000
        hostPort      = 8000
      }]
      secrets = [
        {
          name      = "MASQUE_ADMIN_DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.datamasque_postgres[each.key].arn}:POSTGRES_PASSWORD::"
        }
      ]
  }])

  volume {
    name = "license"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "certs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "files"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "secrets"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "datamasque-mounts"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

}

resource "aws_ecs_service" "dm_adminserver_service" {
  depends_on             = [aws_ecs_service.datamasque_agent_service, aws_db_instance.dm_pgdb]
  for_each               = lookup(local.ecs_config["ecs"], "clusters", {})
  name                   = "${each.key}-dm-adminserver-serv"
  cluster                = aws_ecs_cluster.datamasque_cluster[each.key].id
  task_definition        = aws_ecs_task_definition.admin_server[each.key].arn
  desired_count          = 1
  enable_execute_command = true

  launch_type = "FARGATE"
  service_registries {
    registry_arn = aws_service_discovery_service.admin_server[each.key].arn
  }

  network_configuration {
    subnets          = values(local.common_env_config.subnets)
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_sg[each.key].id] # Replace with your security group
  }
}

resource "aws_ecs_task_definition" "in_flight_server" {
  depends_on               = [aws_cloudwatch_log_group.ecs_log_group]
  for_each                 = lookup(local.ecs_config["ecs"], "clusters", {})
  family                   = "datamasque-inflightserver-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value["inflightContainer"]["cpu"]
  memory                   = each.value["inflightContainer"]["memory"]

  execution_role_arn = aws_iam_role.ecs_task_execution_role[each.key].arn
  task_role_arn      = aws_iam_role.ecs_task_role[each.key].arn

  container_definitions = jsonencode([
    {
      name      = "${each.key}-in-flight-server"
      image     = "${local.ecr_base_url[each.key]}/in-flight-server:${local.ecr_image_url[each.key].image_tag}"
      essential = true
      user      = "1000:1000"
      cpu       = each.value["inflightContainer"]["cpu"]    # Minimum CPU for this container
      memory    = each.value["inflightContainer"]["memory"] # Minimum memory for this container
      portMappings = [{
        containerPort = 5000
        hostPort      = 5000
        name          = "inflightserver-port"
      }]
      mountPoints = [
        { sourceVolume = "license", containerPath = "/license" },
        { sourceVolume = "files", containerPath = "/files" },
        { sourceVolume = "secrets", containerPath = "/.keys/" },
        { sourceVolume = "in_flight_data", containerPath = "/db" }
      ]
      environment = [
        { name = "JWT_SIGNING_KEY", value = "/.keys/jwt.key" },
        { name = "INSTANCE_SECRET_FILE", value = "/.keys/instance_secret.bin" },
        { name = "MASQUE_SANDBOX_PATH", value = "/files/user/" },
        { name = "MASQUE_VERSION", value = each.value["masqueVersion"] },
        { name = "PYARMOR_LICENSE", value = "/app/license/license.lic" },
        { name = "MASQUE_HOST_SUFFIX", value = lookup(each.value, "dnsNamespace", "internal") }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = "/ecs/${each.key}" # Log group name
          awslogs-stream-prefix = "in-flight-server" # Stream prefix for log streams
        }
      }
  }])
  volume {
    name = "license"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "certs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "files"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "secrets"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "in_flight_data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

}

resource "aws_ecs_service" "dm_inflight_service" {
  depends_on             = [aws_ecs_service.dm_adminserver_service]
  for_each               = lookup(local.ecs_config["ecs"], "clusters", {})
  name                   = "${each.key}-dm-inflight-service"
  cluster                = aws_ecs_cluster.datamasque_cluster[each.key].id
  task_definition        = aws_ecs_task_definition.in_flight_server[each.key].arn
  desired_count          = each.value["inflightContainer"]["desiredCount"]
  enable_execute_command = true
  launch_type            = "FARGATE"
  service_registries {
    registry_arn = aws_service_discovery_service.inflight[each.key].arn
  }

  network_configuration {
    subnets          = values(local.common_env_config.subnets)
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_sg[each.key].id] # Replace with your security group
  }
}

resource "aws_ecs_task_definition" "frontend_server" {
  depends_on               = [aws_cloudwatch_log_group.ecs_log_group]
  for_each                 = lookup(local.ecs_config["ecs"], "clusters", {})
  family                   = "datamasque-adminfrontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role[each.key].arn
  task_role_arn      = aws_iam_role.ecs_task_role[each.key].arn

  container_definitions = jsonencode([
    {
      name       = "${each.key}-admin-frontend"
      image      = "${local.ecr_base_url[each.key]}/admin-frontend:${local.ecr_image_url[each.key].image_tag}"
      entryPoint = ["/entrypoint.sh"]
      essential = true
      user      = "1000:1000"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = "/ecs/${each.key}" # Log group name
          awslogs-stream-prefix = "admin-frontend"   # Stream prefix for log streams
        }
      }
      mountPoints = [
        { sourceVolume = "certs", containerPath = "/certs" },
        { sourceVolume = "files", containerPath = "/files" }
      ]
      environment = [
        { name = "HOST_IP", value = "127.0.0.1" },
        { name = "MASQUE_VERSION", value = each.value["masqueVersion"] },
        # { name = "MASQUE_HOST_SUFFIX", value = lookup(each.value, "dnsNamespace", ".internal") }
        { name = "MASQUE_ADMIN_SERVER_HOST", value = "admin-server.${lookup(each.value, "dnsNamespace", "internal")}" },
        { name = "MASQUE_IN_FLIGHT_SERVER_HOST", value = "in-flight-server.${lookup(each.value, "dnsNamespace", "internal")}" },
        { name = "MASQUE_ADMIN_FRONTEND_HOST", value = "localhost" }
      ]
      portMappings = [
        { containerPort = 8443, hostPort = 8443 },
        { containerPort = 8080, hostPort = 8080 },
        { containerPort = 3000, hostPort = 3000 }
      ]
    }
  ])

  volume {
    name = "certs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "files"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.datamasque_efs[each.key].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.dm_efs_access_point[each.key].id
        iam             = "ENABLED"
      }
    }
  }
}

resource "aws_ecs_service" "dm_frontend_service" {
  depends_on             = [aws_ecs_service.dm_inflight_service]
  for_each               = lookup(local.ecs_config["ecs"], "clusters", {})
  name                   = "${each.key}-dm-frontend-service"
  cluster                = aws_ecs_cluster.datamasque_cluster[each.key].id
  task_definition        = aws_ecs_task_definition.frontend_server[each.key].arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  service_registries {
    registry_arn = aws_service_discovery_service.admin_frontend[each.key].arn
  }

  network_configuration { 
    subnets          = values(local.common_env_config.subnets)
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_sg[each.key].id] # Replace with your security group
  }
}
