
resource "random_password" "masque_admin_db_password" {
  for_each         = lookup(local.ecs_config["ecs"], "clusters", {})
  length           = 24      # Length of the password
  special          = true    # Include special characters
  upper            = true    # Include uppercase letters
  lower            = true    # Include lowercase letters
  numeric          = true    # Include numbers
  override_special = "!#$%_" # Specify allowed special characters
}

# Store the password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "datamasque_postgres" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "${each.key}-dm-ecs-db-password"
  # Retain deleted secrets for a recovery window instead of immediate purge, so
  # an accidental destroy can be undone within the window.
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "datamasque_postgres_version" {
  for_each  = lookup(local.ecs_config["ecs"], "clusters", {})
  secret_id = aws_secretsmanager_secret.datamasque_postgres[each.key].id
  secret_string = jsonencode({
    POSTGRES_PASSWORD = random_password.masque_admin_db_password[each.key].result
  })

  lifecycle {
    ignore_changes = [
      secret_string
    ]
  }
}
