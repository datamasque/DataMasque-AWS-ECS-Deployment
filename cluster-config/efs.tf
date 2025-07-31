resource "aws_efs_file_system" "datamasque_efs" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  creation_token = "${each.key}-efs"
  encrypted      = true
  tags = {
    Name = "${each.key}-efs"
  }
}

#Capture VPC CIDR Block

data "aws_vpc" "get_vpc_details" {
  id = local.common_env_config["vpcid"]
}

#Create EFS mount targets

resource "aws_efs_mount_target" "efs_mount_targets_subnetA" {
  for_each        = lookup(local.ecs_config["ecs"], "clusters", {})
  file_system_id  = aws_efs_file_system.datamasque_efs[each.key].id
  subnet_id       = local.common_env_config["subnets"]["subneta"]
  security_groups = [aws_security_group.ecs_efs_sg[each.key].id]
}

resource "aws_efs_mount_target" "efs_mount_targets_subnetB" {
  for_each        = lookup(local.ecs_config["ecs"], "clusters", {})
  file_system_id  = aws_efs_file_system.datamasque_efs[each.key].id
  subnet_id       = local.common_env_config["subnets"]["subnetb"]
  security_groups = [aws_security_group.ecs_efs_sg[each.key].id]
}

resource "aws_efs_mount_target" "efs_mount_targets_subnetC" {
  for_each        = lookup(local.ecs_config["ecs"], "clusters", {})
  file_system_id  = aws_efs_file_system.datamasque_efs[each.key].id
  subnet_id       = local.common_env_config["subnets"]["subnetc"]
  security_groups = [aws_security_group.ecs_efs_sg[each.key].id]
}

resource "aws_efs_access_point" "dm_efs_access_point" {
  for_each       = lookup(local.ecs_config["ecs"], "clusters", {})
  file_system_id = aws_efs_file_system.datamasque_efs[each.key].id
  posix_user {
    gid = 1000
    uid = 1000
  }
  root_directory {
    path = "/datamasque/app"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = 777
    }
  }

}

resource "aws_efs_access_point" "dm_efs_access_point_admindb" {
  for_each       = lookup(local.ecs_config["ecs"], "clusters", {})
  file_system_id = aws_efs_file_system.datamasque_efs[each.key].id
  posix_user {
    gid = 999
    uid = 999
  }
  root_directory {
    path = "/datamasque/pgdata"
    creation_info {
      owner_uid   = 999
      owner_gid   = 999
      permissions = 777
    }
  }

}

resource "aws_security_group" "ecs_efs_sg" {
  for_each    = lookup(local.ecs_config["ecs"], "clusters", {})
  name        = "${each.key}-efs"
  description = "Allow inbound traffic for EFS from within VPC and all outbound traffic"
  vpc_id      = local.common_env_config["vpcid"]

  tags = {
    Name = "${each.key}-efs"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_allow_tls_ipv4" {
  for_each          = lookup(local.ecs_config["ecs"], "clusters", {})
  security_group_id = aws_security_group.ecs_efs_sg[each.key].id
  cidr_ipv4         = data.aws_vpc.get_vpc_details.cidr_block
  from_port         = 2049
  ip_protocol       = "tcp"
  to_port           = 2049
}
