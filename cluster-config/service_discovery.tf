resource "aws_service_discovery_private_dns_namespace" "local" {
  for_each    = lookup(local.ecs_config["ecs"], "clusters", {})
  name        = lookup(each.value, "dnsNamespace", "internal")
  vpc         = local.common_env_config.vpcid
  description = "Private DNS namespace for service discovery"
}

resource "aws_service_discovery_service" "admin_frontend" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "admin-frontend"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.local[each.key].id
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}


resource "aws_service_discovery_service" "admin_server" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "admin-server"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.local[each.key].id
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}


resource "aws_service_discovery_service" "admin_db" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "admin-db"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.local[each.key].id
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "queue" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "agent-queue"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.local[each.key].id
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}


resource "aws_service_discovery_service" "agent" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "agent"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.local[each.key].id
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}


resource "aws_service_discovery_service" "inflight" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "in-flight-server"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.local[each.key].id
    dns_records {
      ttl  = 20
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}


