####################################################
# ECS Cluster
####################################################

resource "aws_ecs_cluster" "this" {
  name               = "${local.app_name}-app-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
  }
}

####################################################
# ECS IAM Role
####################################################

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
  ]
}
resource "aws_iam_role_policy" "kms_decrypt_policy" {
  name = "${local.app_name}_ecs_task_execution_role_policy_kms"
  role               = aws_iam_role.ecs_task_execution_role.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        "Effect": "Allow",
        "Action": [
          "kms:Decrypt"
        ],
        "Resource": [
          data.aws_ssm_parameter.database_password.arn
        ]
      }
    ]
  })
}

####################################################
# ECS Task Container Log Groups
####################################################

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.app_name}/frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.app_name}/backend"
  retention_in_days = 30
}

####################################################
# ECR data source
####################################################

locals {
  ecr_frontend_repository_name       = "techbranch-frontend"
  ecr_backend_repository_name        = "techbranch-backend"
}

data "external" "ecr_image_frontend_newest" {
  program = [
    "aws", "ecr", "describe-images",
    "--repository-name", local.ecr_frontend_repository_name,
    "--query", "{\"tags\": to_string(sort_by(imageDetails,& imagePushedAt)[-1].imageTags)}",
  ]
}

locals {
  ecr_frontend_repository_newest_tags = jsondecode(data.external.ecr_image_frontend_newest.result.tags)
}

data "external" "ecr_image_backend_newest" {
  program = [
    "aws", "ecr", "describe-images",
    "--repository-name", local.ecr_backend_repository_name,
    "--query", "{\"tags\": to_string(sort_by(imageDetails,& imagePushedAt)[-1].imageTags)}",
  ]
}

locals {
  ecr_backend_repository_newest_tags = jsondecode(data.external.ecr_image_backend_newest.result.tags)
}


data "aws_ecr_repository" "frontend" {
  name = local.ecr_frontend_repository_name
}

data "aws_ecr_repository" "backend" {
  name = local.ecr_backend_repository_name
}

####################################################
# ECS Task Definition
####################################################

locals {
  frontend_task_name = "${local.app_name}-app-task-frontend"
  backend_task_name = "${local.app_name}-app-task-backend"
  frontend_task_container_name = "${local.app_name}-app-container-frontend"
  backend_task_container_name = "${local.app_name}-app-container-backend"
}

data "aws_ssm_parameter" "jwt_secret" {
  name = "${local.ssm_parameter_store_base}/jwt_secret"
}
data "aws_ssm_parameter" "oauth_google_state" {
  name = "${local.ssm_parameter_store_base}/oauth_google_state"
}
data "aws_ssm_parameter" "oauth_google_client_id" {
  name = "${local.ssm_parameter_store_base}/oauth_google_client_id"
}
data "aws_ssm_parameter" "oauth_google_client_secret" {
  name = "${local.ssm_parameter_store_base}/oauth_google_client_secret"
}
data "aws_ssm_parameter" "oauth_google_redirect_url" {
  name = "${local.ssm_parameter_store_base}/oauth_google_redirect_url"
}
data "aws_ssm_parameter" "gmail_from" {
  name = "${local.ssm_parameter_store_base}/gmail_from"
}
data "aws_ssm_parameter" "gmail_password" {
  name = "${local.ssm_parameter_store_base}/gmail_password"
}
data "aws_ssm_parameter" "signup_url" {
  name = "${local.ssm_parameter_store_base}/signup_url"
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = local.frontend_task_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
    {
      name             = local.frontend_task_container_name
      image            = "${data.aws_ecr_repository.frontend.repository_url}:${local.ecr_frontend_repository_newest_tags[0]}"
      portMappings     = [{ containerPort : 80 }]
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-region : "ap-northeast-1"
          awslogs-group : aws_cloudwatch_log_group.frontend.name
          awslogs-stream-prefix : "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "backend" {
  family                   = local.backend_task_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
    {
      name             = local.backend_task_container_name
      image            = "${data.aws_ecr_repository.backend.repository_url}:${local.ecr_backend_repository_newest_tags[0]}"
      portMappings     = [{ containerPort : 80 }]
      environment = [
        {
          name: "MIGRATION_URL",
          value: "file://migrations"
        },
        {
          name: "HTTP_SERVER_ADDRESS",
          value: "0.0.0.0:80"
        },
        {
          name: "GRPC_SERVER_ADDRESS",
          value: "0.0.0.0:90"
        },
        {
          name: "REDIS_ACCESS_TOKEN_DB",
          value: "0"
        },
        {
          name: "REDIS_REFRESH_TOKEN_DB",
          value: "1"
        },
        {
          name: "JWT_ISSUER",
          value: "https://api.techbranch.link"
        },
        {
          name: "ACCESS_TOKEN_EXPIRES",
          value: "1h"
        },
        {
          name: "REFRESH_TOKEN_EXPIRES",
          value: "720h"
        },
        {
          name: "REDIS_PRESIGNUP_DB",
          value: "0"
        },
        {
          name: "PRESIGNUP_EXPIRES",
          value: "1h"
        },
        {
          name: "PRESIGNUP_MAIL_SUBJECT",
          value: "ユーザー仮登録の確認"
        },
        {
          name: "PRESIGNUP_MAIL_TEMPLATE",
          value: "./pkg/mail/presignup.tmpl"
        },
        {
          name: "DB_SOURCE",
          value: "postgresql://${data.aws_ssm_parameter.database_user.value}:${data.aws_ssm_parameter.database_password.value}@${aws_ssm_parameter.database_url.value}/${data.aws_ssm_parameter.database_name.value}"
        },
        {
          name: "REDIS_ADDRESS",
          value: aws_ssm_parameter.redis_url.value
        },
        {
          name: "JWT_SECRET",
          value: data.aws_ssm_parameter.jwt_secret.value
        },
        {
          name: "OAUTH_GOOGLE_STATE",
          value: data.aws_ssm_parameter.oauth_google_state.value
        },
        {
          name: "OAUTH_GOOGLE_CLIENT_ID",
          value: data.aws_ssm_parameter.oauth_google_client_id.value
        },
        {
          name: "OAUTH_GOOGLE_CLIENT_SECRET",
          value: data.aws_ssm_parameter.oauth_google_client_secret.value
        },
        {
          name: "OAUTH_GOOGLE_REDIRECT_URL",
          value: data.aws_ssm_parameter.oauth_google_redirect_url.value
        },
        {
          name: "GMAIL_FROM",
          value: data.aws_ssm_parameter.gmail_from.value
        },
        {
          name: "GMAIL_PASSWORD",
          value: data.aws_ssm_parameter.gmail_password.value
        },
        {
          name: "SIGNUP_URL",
          value: data.aws_ssm_parameter.signup_url.value
        }
      ]
      secrets = [
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-region : "ap-northeast-1"
          awslogs-group : aws_cloudwatch_log_group.backend.name
          awslogs-stream-prefix : "ecs"
        }
      }
    }
  ])
}

####################################################
# ECS Cluster Service
####################################################

resource "aws_ecs_service" "frontend" {
  name                               = "${local.app_name}-frontend"
  cluster                            = aws_ecs_cluster.this.id
  platform_version                   = "LATEST"
  task_definition                    = aws_ecs_task_definition.frontend.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  propagate_tags                     = "SERVICE"
  enable_execute_command             = true
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 60
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    assign_public_ip = true
    subnets          = [
      aws_subnet.public_1a.id,
    ]
    security_groups = [
      aws_security_group.app.id,
    ]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = local.frontend_task_container_name
    container_port   = 80
  }
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${local.app_name}-service-tg-frontend"
  vpc_id               = aws_vpc.this.id
  target_type          = "ip"
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 60
  health_check { path = "/" }
}

resource "aws_lb_listener_rule" "frontend" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
  condition {
    host_header {
      values = [local.app_domain_name]
    }
  }
}

resource "aws_ecs_service" "backend" {
  name                               = "${local.app_name}-backend"
  cluster                            = aws_ecs_cluster.this.id
  platform_version                   = "LATEST"
  task_definition                    = aws_ecs_task_definition.backend.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  propagate_tags                     = "SERVICE"
  enable_execute_command             = true
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 60
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    assign_public_ip = true
    subnets          = [
      aws_subnet.public_1c.id,
    ]
    security_groups = [
      aws_security_group.app.id,
    ]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = local.backend_task_container_name
    container_port   = 80
  }
}

resource "aws_lb_target_group" "backend" {
  name                 = "${local.app_name}-service-tg-backend"
  vpc_id               = aws_vpc.this.id
  target_type          = "ip"
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 60
  health_check { path = "/docs" }
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 2
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
  condition {
    host_header {
      values = [local.api_domain_name]
    }
  }
}

resource "aws_lb_listener_rule" "maintenance" {
  listener_arn = aws_lb_listener.https.arn
  priority = 100
  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/html"
      message_body = local.maintenance_body
      status_code = "503"
    }
  }
  condition {
    path_pattern {
      values = ["*"]
    }
  }
}