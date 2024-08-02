#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------

variable "name" {
  type = string
}

#--------------------------------------------------------------
# ECS Cluster
#--------------------------------------------------------------

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.name
}

#--------------------------------------------------------------
# Output
#--------------------------------------------------------------

output "cluster_name" {
  value = aws_ecs_cluster.ecs_cluster.name
}