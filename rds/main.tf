#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "name" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "alb_security_group" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "engine" {
  type    = string
  default = "mysql"
}
variable "engine_version" {
  type    = string
  default = "8.0.20"
}
variable "db_instance" {
  type    = string
  default = "db.t2.micro"
}

variable "db_port" {
  type    = number
  default = 3306
}

variable "db_password" {
  type = string
}

#--------------------------------------------------------------
# Security Group
#--------------------------------------------------------------

resource "aws_security_group" "db_sg" {
  name        = "${var.name}-db"
  description = "security group on db of ${var.name}"

  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg of db"
  }
}

resource "aws_security_group_rule" "db-rule" {
  security_group_id = aws_security_group.db_sg.id

  type = "ingress"

  from_port   = var.db_port
  to_port     = var.db_port
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

#--------------------------------------------------------------
# Subnet Group
#--------------------------------------------------------------

resource "aws_db_subnet_group" "db_subnet_group" {
  name        = var.db_name
  description = "db subent group of ${var.name}"
  subnet_ids  = var.private_subnet_ids
}

#--------------------------------------------------------------
# RDS
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance
resource "aws_db_instance" "db" {
  allocated_storage           = 10
  storage_type                = "gp2"
  identifier                  = var.db_name
  engine                      = var.engine
  engine_version              = var.engine_version
  instance_class              = var.db_instance
  db_name                     = var.db_name
  username                    = var.db_username
  password                    = var.db_password
  # manage_master_user_password = true
  skip_final_snapshot         = true
  multi_az                    = false
  # availability_zone           = "ap-northeast-1a"
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  db_subnet_group_name        = aws_db_subnet_group.db_subnet_group.name
}

#--------------------------------------------------------------
# Output
#--------------------------------------------------------------

output "db_address" {
  value = aws_db_instance.db.address
}

# output "db_password_arn" {
#   value = aws_db_instance.db.master_user_secret[0].secret_arn
# }
