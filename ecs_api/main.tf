#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "http_listener_arn" {
  type = string
}

variable "https_listener_arn" {
  type = string
}

variable "subnet_ids" {
  type = list
}

variable "db_host" {
    type = string
}

variable "db_port" {
    type = number
}

variable "db_user" {
    type = string
}

variable "db_password" {
    type = string
}

variable "db_name" {
    type = string
}

variable "migration_url" {
    type = string
}

variable "http_server_address" {
    type = string
}

variable "grpc_server_address" {
    type = string
}

variable "http_port" {
  type = number
}

variable "grpc_port" {
  type = number
}

data "aws_caller_identity" "user" {}

# variable "db_password_arn" {
# }

# data "aws_secretsmanager_secret_version" "db_password_arn" {
#   secret_id = var.db_password_arn
# }

# locals {
#   username = jsondecode(data.aws_secretsmanager_secret_version.db_password_arn.secret_string)["username"]
#   db_password = jsondecode(data.aws_secretsmanager_secret_version.db_password_arn.secret_string)["password"]
#   db_source = "postgresql://${var.db_user}:${local.db_password}@${var.db_host}:${var.db_port}/${var.db_name}"
# }

locals {
  account_id = data.aws_caller_identity.user.account_id

  db_source = "postgresql://${var.db_user}:${var.db_password}@${var.db_host}:${var.db_port}/${var.db_name}"
}

#--------------------------------------------------------------
# CloudWatch Logs
# ECSのログ主力先を作成
#--------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs_log" {
  name              = "/ecs/techbranch-api"
  retention_in_days = 180
}

#--------------------------------------------------------------
# IAM Role
# AmazonECSTaskExecutionRolePolicy の参照
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy
data "aws_iam_policy" "ecs_task_execution_role_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

module "ecs_task_execution_role" {
  source     = "../iam_role"
  name       = "ecs-task-execution"
  identifier = "ecs-tasks.amazonaws.com"
  policy_arn = data.aws_iam_policy.ecs_task_execution_role_policy.arn
}

#--------------------------------------------------------------
# Task Definition
# どんなコンテナをどんな設定で動かすかを定義する
#--------------------------------------------------------------

data "template_file" "container_definitions" {
  template = file("./ecs_api/container_definitions.json")

  vars = {
    account_id  = local.account_id
    db_source   = local.db_source
    migration_url = var.migration_url
    http_server_address = var.http_server_address
    grpc_server_address = var.grpc_server_address
    http_port   = var.http_port
    grpc_port   = var.grpc_port
  }
}

# https://www.terraform.io/docs/providers/aws/r/ecs_task_definition.html
resource "aws_ecs_task_definition" "task_definition" {
  family = var.name

  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc" # Fargateを使用する場合は"awsvpc"決め打ち
  requires_compatibilities = ["FARGATE"]

  container_definitions = data.template_file.container_definitions.rendered
  execution_role_arn    = module.ecs_task_execution_role.iam_role_arn
}

#--------------------------------------------------------------
# ALB
# ロードバランサの設定
# ロードバランサとコンテナの紐付けは"ターゲットグループ"と"リスナー"の2つを使用します。
# ターゲットグループ: ヘルスチェックを行う
# リスナー: ロードバランサがリクエスト受けた際、どのターゲットグループへリクエストを受け渡すのかの設定
#--------------------------------------------------------------

# https://www.terraform.io/docs/providers/aws/r/lb_target_group.html
# TODO: grpc用のaws_lb_target_groupを作成する
resource "aws_lb_target_group" "target_group" {
  name = var.name

  vpc_id = var.vpc_id

  # ALBからECSタスクのコンテナへトラフィックを振り分ける設定
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"

  health_check {
    port = 8080
    path = "/"
  }
}

# https://www.terraform.io/docs/providers/aws/r/lb_target_group.html
resource "aws_lb_listener_rule" "http_rule" {
  listener_arn = var.http_listener_arn

  # 受け取ったトラフィックをターゲットグループへ受け渡す
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.id
  }

  # ターゲットグループへ受け渡すトラフィックの条件
  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

resource "aws_lb_listener_rule" "https_rule" {
  listener_arn = var.https_listener_arn

  # 受け取ったトラフィックをターゲットグループへ受け渡す
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.id
  }

  # ターゲットグループへ受け渡すトラフィックの条件
  condition {
    path_pattern {
      values = ["*"]
    }
  }
}

# --------------------------------------------------------------
# Security Group
# --------------------------------------------------------------

# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group" "ecs_security_group" {
  name        = "${var.name}-sg"
  description = "security group of ${var.name} ecs"

  vpc_id = var.vpc_id

  # セキュリティグループ内のリソースからインターネットへのアクセス許可設定
  # 今回の場合DockerHubへのPullに使用する。
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.name
  }
}

# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group_rule" "http_ingress_rule" {
  security_group_id = aws_security_group.ecs_security_group.id

  # インターネットからセキュリティグループ内のリソースへのアクセス許可設定
  type              = "ingress"

  # TCPでの80ポートへのアクセスを許可する
  from_port   = 8080
  to_port     = 8080
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

# https://www.terraform.io/docs/providers/aws/r/security_group.html
resource "aws_security_group_rule" "https_ingress_rule" {
  security_group_id = aws_security_group.ecs_security_group.id

  # インターネットからセキュリティグループ内のリソースへのアクセス許可設定
  type              = "ingress"

  # TCPでの443ポートへのアクセスを許可する
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

#--------------------------------------------------------------
# ECS Service
# どのタスク定義でコンテナを立ち上げ、そのコンテナとどのロードバランサ(ターゲットグループ, リスナー)と紐付けるか
#--------------------------------------------------------------

# https://www.terraform.io/docs/providers/aws/r/ecs_service.html
resource "aws_ecs_service" "ecs_service" {
  name = var.name

  launch_type = "FARGATE"

  # ECSタスクの起動数を定義
  desired_count = 1

  # 当該ECSサービスを配置するECSクラスターの指定
  cluster = var.cluster_name

  # 起動するECSタスクのタスク定義
  task_definition = aws_ecs_task_definition.task_definition.arn

  # ECSタスクへ設定するネットワークの設定
  network_configuration {
    # タスクの起動を許可するサブネット
    subnets         = var.subnet_ids
    # タスクに紐付けるセキュリティグループ
    security_groups = [aws_security_group.ecs_security_group.id]
    # パブリックIPを割り当てるかどうか
    assign_public_ip = true
  }

  # ECSタスクの起動後に紐付けるELBターゲットグループ
  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = "techbranch-api"
    container_port   = "8080"
  }
}
