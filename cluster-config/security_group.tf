

resource "aws_security_group" "ecs_sg" {
  for_each    = lookup(local.ecs_config["ecs"], "clusters", {})
  name        = "${each.key}-dm-sg"
  description = "ECS Security Group for ${each.key}"
  vpc_id      = local.common_env_config.vpcid
  tags = {
    Environment = terraform.workspace
  }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_sg_ingress_https" {
  for_each          = lookup(local.ecs_config["ecs"], "clusters", {})
  security_group_id = aws_security_group.ecs_sg[each.key].id
  cidr_ipv4         = local.common_env_config.inbound_cidr_range
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  description       = "Allow HTTPS traffic"
}

resource "aws_vpc_security_group_ingress_rule" "ecs_sg_ingress_https2" {
  for_each          = lookup(local.ecs_config["ecs"], "clusters", {})
  security_group_id = aws_security_group.ecs_sg[each.key].id
  cidr_ipv4         = local.common_env_config.inbound_cidr_range
  from_port         = 8443
  ip_protocol       = "tcp"
  to_port           = 8443
  description       = "Allow HTTPS traffic"
}

resource "aws_vpc_security_group_ingress_rule" "ecs_sg_ingress_self" {
  for_each                     = lookup(local.ecs_config["ecs"], "clusters", {})
  security_group_id            = aws_security_group.ecs_sg[each.key].id
  referenced_security_group_id = aws_security_group.ecs_sg[each.key].id
  ip_protocol                  = -1
  description                  = "Allow HTTPS traffic"
}

resource "aws_security_group" "rds_sg" {
  for_each    = lookup(local.ecs_config["ecs"], "clusters", {})
  name        = "${each.key}-dm-rds-sg"
  description = "DataMasque RDS Security Group for ${each.key}"
  vpc_id      = local.common_env_config.vpcid
  tags = {
    Environment = terraform.workspace
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_sg_ingress_https2" {
  for_each                     = lookup(local.ecs_config["ecs"], "clusters", {})
  security_group_id            = aws_security_group.rds_sg[each.key].id
  referenced_security_group_id = aws_security_group.ecs_sg[each.key].id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  description                  = "Allow traffic from DataMasque instance"
}


resource "aws_vpc_security_group_egress_rule" "rds_sg_egress" {
  for_each          = lookup(local.ecs_config["ecs"], "clusters", {})
  security_group_id = aws_security_group.rds_sg[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1
  ip_protocol       = -1
  to_port           = -1
}

resource "aws_vpc_security_group_egress_rule" "ecs_sg_egress" {
  for_each          = lookup(local.ecs_config["ecs"], "clusters", {})
  security_group_id = aws_security_group.ecs_sg[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = -1
  ip_protocol       = -1
  to_port           = -1
}
