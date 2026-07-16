# Look up the existing RDS subnet group by its name
data "aws_db_subnet_group" "dm" {
  name = local.common_env_config.db_subnetgroup # e.g. "production-db-subnet-group"
}

resource "aws_db_instance" "dm_pgdb" {
  for_each               = lookup(local.ecs_config["ecs"], "clusters", {})
  identifier             = "${each.key}-pg-dm-rds"
  engine                 = "postgres"
  instance_class         = "db.t4g.micro" # e.g. db.t4g.small
  allocated_storage      = 20             # GiB
  storage_type           = "gp3"
  username               = "postgres" # e.g. "postgres"
  password               = jsondecode(aws_secretsmanager_secret_version.datamasque_postgres_version[each.key].secret_string)["POSTGRES_PASSWORD"]
  db_name                = "postgres" # initial database name
  db_subnet_group_name   = data.aws_db_subnet_group.dm.name
  vpc_security_group_ids = [aws_security_group.rds_sg[each.key].id]
  publicly_accessible    = false
  storage_encrypted      = true # encrypt DataMasque metadata at rest (uses the default AWS-managed KMS key)
  multi_az               = each.value["rds"]["multiAz"]
  # Defaults preserve the original blueprint behaviour (no snapshot, no
  # protection) for easy teardown of disposable environments. Set
  # rds.skipFinalSnapshot: false and rds.deletionProtection: true in the
  # environment config to protect data you cannot afford to lose.
  skip_final_snapshot        = lookup(each.value["rds"], "skipFinalSnapshot", true)
  deletion_protection        = lookup(each.value["rds"], "deletionProtection", false)
  auto_minor_version_upgrade = true

  tags = {
    Environment = terraform.workspace
    Application = each.key
  }
}
