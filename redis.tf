####################################################
# Elasticache SG
####################################################

resource "aws_security_group" "redis_sg" {
  name        = "${local.app_name}-redis-sg"
  description = "${local.app_name}-redis"

  vpc_id = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.app_name}-redis-sg"
  }
}

resource "aws_security_group_rule" "redis_sg_rule" {
  security_group_id = aws_security_group.redis_sg.id

  type = "ingress"

  from_port   = 6379
  to_port     = 6379
  protocol    = "tcp"
  source_security_group_id = aws_security_group.app.id
}

resource "aws_elasticache_subnet_group" "redis_sg_group" {
  name        = "${local.app_name}-redis-subnet-group"
  description = "${local.app_name}-redis-subnet-group"
  subnet_ids  = [
    aws_subnet.private_1a.id,
    aws_subnet.private_1c.id,
    aws_subnet.private_1d.id,
  ]
}

####################################################
# ElastiCache Cluster
####################################################

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${local.app_name}-redis"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis5.0"
  engine_version       = "5.0.6"
  port                 = 6379

  security_group_ids   = [aws_security_group.redis_sg.id]
  subnet_group_name    = aws_elasticache_subnet_group.redis_sg_group.name

  tags = {
    Name = "${local.app_name}-redis"
  }
}

####################################################
# Create SSM Redis url
####################################################

resource "aws_ssm_parameter" "redis_url" {
  name  = "${local.ssm_parameter_store_base}/redis_url"
  type  = "String"
  value = "${aws_elasticache_cluster.this.cache_nodes.0.address}:${aws_elasticache_cluster.this.cache_nodes.0.port}"
}