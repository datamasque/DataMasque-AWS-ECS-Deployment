# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "${each.key}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

}

resource "aws_iam_role_policy" "ecs_task_execution_policy" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "${each.key}ECSTaskExecPolicy"
  role     = aws_iam_role.ecs_task_execution_role[each.key].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream", # Allows creating log streams in the log group
          "logs:PutLogEvents"     # Allows writing logs to the log group
        ],
        Resource = "${aws_cloudwatch_log_group.ecs_log_group[each.key].arn}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRead"
        ],
        Resource = aws_efs_access_point.dm_efs_access_point[each.key].arn
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = aws_secretsmanager_secret.datamasque_postgres[each.key].arn
      },
      {
        "Sid" : "SSM",
        "Effect" : "Allow",
        "Action" : [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        "Resource" : ["*"]
      }
    ]
  })
}

# Attach managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  for_each   = lookup(local.ecs_config["ecs"], "clusters", {})
  role       = aws_iam_role.ecs_task_execution_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "${each.key}-ecsTaskRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_access_policy" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "${each.key}ECSTaskAccessPolicy"
  role     = aws_iam_role.ecs_task_role[each.key].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRead"
        ],
        Resource = aws_efs_access_point.dm_efs_access_point[each.key].arn
      },
      {
        "Sid" : "SSM",
        "Effect" : "Allow",
        "Action" : [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        "Resource" : ["*"]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket",
          "s3:GetBucketAcl",
          "s3:GetBucketPolicyStatus",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetEncryptionConfiguration"
        ],
        Resource = ["arn:aws:s3:::*"]
      },
      {
        "Sid" : "BucketReadWrite",
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:GetObject"
        ],
        "Resource" : ["arn:aws:s3:::*/*"]
      },
      {
        "Sid" : "DataMasqueListSecrets",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:ListSecrets",
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowSecretRead",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue"
        ],
        "Resource" : "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*"
      },
      {
        "Sid" : "DataMasqueLicenseCheckInAndOut",
        "Effect" : "Allow",
        "Action" : [
          "license-manager:CheckoutLicense",
          "license-manager:CheckInLicense"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "DataMasqueStepFunctionAutomation",
        "Effect" : "Allow",
        "Action" : [
          "states:ListStateMachines",
          "states:ListExecutions",
          "states:StartExecution"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "DataMasqueQueryTasks",
        "Effect" : "Allow",
        "Action" : [
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ],
        "Resource" : "*"
      }
    ]
  })
}
