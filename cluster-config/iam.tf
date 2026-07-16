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
        # ECS Exec (SSM Session Manager) channel actions do not support
        # resource-level scoping; "*" is required by AWS. Needed for
        # `enable_execute_command` shell access into tasks. Intentional wildcard.
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
    # S3 access for file masking is scoped to the buckets listed in each
    # cluster's `maskingBuckets` config (see config/example.yml). When the list
    # is empty the S3 statements are omitted entirely (an empty Resource list is
    # rejected by IAM), so the default deployment carries no S3 permissions
    # until you name the buckets it must read masked/source files from.
    Statement = concat([
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
        # ECS Exec (SSM Session Manager) channel actions do not support
        # resource-level scoping; "*" is required by AWS. Needed for
        # `enable_execute_command` shell access into tasks. Intentional wildcard.
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
        # ListSecrets has no resource-level scoping in IAM (AWS requires "*"),
        # so this stays a wildcard by necessity. It is metadata-only (names/ARNs,
        # never values); DataMasque uses it to enumerate connection secrets in
        # the console. Remove this statement if you wire connections by ARN only.
        "Sid" : "DataMasqueListSecrets",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:ListSecrets",
        ],
        "Resource" : "*"
      },
      {
        # GetSecretValue is scoped to this deployment's secret name prefix in
        # this account/region. The masking agent only needs to read the DB
        # password and any DataMasque connection secrets it provisions, all of
        # which share the `<cluster>-dm-` / `datamasque` naming prefix.
        "Sid" : "AllowSecretRead",
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetSecretValue"
        ],
        "Resource" : [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${each.key}-dm-*",
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:datamasque*"
        ]
      },
      {
        # license-manager Checkout/CheckIn operate on AWS-managed license
        # configurations and do not accept resource-level scoping; "*" is the
        # only valid resource for these actions. Intentionally left wildcard.
        "Sid" : "DataMasqueLicenseCheckInAndOut",
        "Effect" : "Allow",
        "Action" : [
          "license-manager:CheckoutLicense",
          "license-manager:CheckInLicense"
        ],
        "Resource" : "*"
      },
      {
        # Step Functions automation: state machine ARNs are created by the
        # operator outside this plan and are not known at apply time, so these
        # list/start actions stay wildcard. Narrow to specific state-machine
        # ARNs if you pre-create them.
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
        # ecs:ListTasks/DescribeTasks do not support resource-level permissions
        # for listing across a cluster; AWS requires "*". Read-only task
        # introspection used by the agent. Intentionally left wildcard.
        "Sid" : "DataMasqueQueryTasks",
        "Effect" : "Allow",
        "Action" : [
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ],
        "Resource" : "*"
      }
      ], flatten([
        # The S3 statements are included only when maskingBuckets is non-empty.
        # range() yields a consistently-typed list(number) ([0] or []), so this
        # gate avoids the "inconsistent conditional result types" error that a
        # `? [stmt1, stmt2] : []` ternary raises (2-element vs 0-element tuple).
        for _ in range(length(lookup(each.value, "maskingBuckets", [])) > 0 ? 1 : 0) : [
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
            Resource = [for b in each.value["maskingBuckets"] : "arn:aws:s3:::${b}"]
          },
          {
            "Sid" : "BucketReadWrite",
            "Effect" : "Allow",
            "Action" : [
              "s3:PutObject",
              "s3:GetObject"
            ],
            "Resource" : [for b in each.value["maskingBuckets"] : "arn:aws:s3:::${b}/*"]
          }
        ]
    ]))
  })
}
