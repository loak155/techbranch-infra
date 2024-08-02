#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list
}

variable "acm_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "subdomain" {
  type = string
}

variable "subdomain_zone_id" {
  type = string
}

#--------------------------------------------------------------
# Security group
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB security group for ${var.name}"

  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name}-alb-sg"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule
# HTTPインバウンドルール
resource "aws_security_group_rule" "alb_ingress_http" {
  type = "ingress"
  from_port = 80
  to_port   = 80
  protocol  = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# HTTPSインバウンドルール
resource "aws_security_group_rule" "alb_ingress_https" {
  type = "ingress"
  from_port = 443
  to_port   = 443
  protocol  = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}


# アウトバウンドルール
resource "aws_security_group_rule" "alb_egress_vpc" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

#--------------------------------------------------------------
#  Elastic Load Balancing
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
resource "aws_lb" "alb" {
  load_balancer_type = "application"
  name               = "${var.name}-alb"
  security_groups = [aws_security_group.alb.id]
  subnets         = var.public_subnet_ids
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
# ALBがリクエストを受け付けるポートを設定
resource "aws_lb_listener" "http" {
  port     = "80"
  protocol = "HTTP"

  load_balancer_arn = aws_lb.alb.arn

  # "ok" という固定レスポンスを設定する
  default_action {
    type             = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
      message_body = "ok"
    }
  }

  # default_action {
  #   type = "redirect"

  #   redirect {
  #     port        = "443"
  #     protocol    = "HTTPS"
  #     status_code = "HTTP_301"
  #   }
  # }
}

# ALBがリクエストを受け付けるポートを設定
resource "aws_lb_listener" "https" {
  port     = "443"
  protocol = "HTTPS"

  load_balancer_arn = aws_lb.alb.arn
  certificate_arn   = var.acm_id

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
      message_body = "ok"
    }
  }
}

# --------------------------------------------------------------
# Route53 record
# Route53に登録したドメインでロードバランサーに飛ぶように、Aレコードを作成する
# --------------------------------------------------------------

data "aws_route53_zone" "domain" {
  name         = var.domain
  private_zone = false
}

resource "aws_route53_record" "domain" {
  type    = "A"
  name    = var.domain
  zone_id = data.aws_route53_zone.domain.id
  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "subdomain" {
  type    = "A"
  name    = var.subdomain
  zone_id = var.subdomain_zone_id
  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

#--------------------------------------------------------------
# Output
#--------------------------------------------------------------

output "http_listener_arn" {
  value = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "alb_security_group" {
  value = aws_security_group.alb.id
}