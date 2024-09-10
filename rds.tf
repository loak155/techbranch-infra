####################################################
# RDS SSM
####################################################

data "aws_ssm_parameter" "database_name" {
  name = "${local.ssm_parameter_store_base}/database_name"
}

data "aws_ssm_parameter" "database_user" {
  name = "${local.ssm_parameter_store_base}/database_user"
}

data "aws_ssm_parameter" "database_password" {
  name = "${local.ssm_parameter_store_base}/database_password"
}

####################################################
# RDS SG
####################################################

resource "aws_security_group" "database_sg" {
  name        = "${local.app_name}-database-sg"
  description = "${local.app_name}-database"

  vpc_id = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.app_name}-database-sg"
  }
}

resource "aws_security_group_rule" "database_sg_rule" {
  security_group_id = aws_security_group.database_sg.id

  type = "ingress"

  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"
  source_security_group_id = aws_security_group.app.id
}

resource "aws_db_subnet_group" "database_sg_group" {
  name        = "${local.app_name}-database-subnet-group"
  description = "${local.app_name}-database-subnet-group"
  subnet_ids  = [
    aws_subnet.private_1a.id,
    aws_subnet.private_1c.id,
    aws_subnet.private_1d.id,
  ]
}

####################################################
# RDS Instance
####################################################

resource "aws_db_instance" "this" {
  allocated_storage           = 10
  storage_type                = "gp2"
  identifier                  = "${local.app_name}-database"
  engine                      = "postgres"
  engine_version              = "16.2"
  instance_class              = "db.t3.micro"
  db_name                     = data.aws_ssm_parameter.database_name.value
  username                    = data.aws_ssm_parameter.database_user.value
  password                    = data.aws_ssm_parameter.database_password.value
  skip_final_snapshot         = true
  multi_az                    = false
  availability_zone           = "ap-northeast-1a"
  vpc_security_group_ids      = [aws_security_group.database_sg.id]
  db_subnet_group_name        = aws_db_subnet_group.database_sg_group.name
}

####################################################
# Create SSM DB url
####################################################

resource "aws_ssm_parameter" "database_url" {
  name  = "${local.ssm_parameter_store_base}/database_url"
  type  = "String"
  value = aws_db_instance.this.endpoint
}